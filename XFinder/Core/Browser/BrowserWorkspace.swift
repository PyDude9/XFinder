import Foundation
import CoreGraphics

/// XF-T28 — the layout snapshots behind session restore and named Workspaces (symlinked into the test package).
///
/// A workspace is a layout, not a backup: it remembers windows, their pane trees, each pane's folder, view, sort and
/// Back/Forward history — never file contents. Restoring never mounts a disk or recreates a folder: a pane whose folder
/// is gone opens Home and the person is told which folders were missing (spec XF-T28 §2.1 item 12, §4).
struct PaneSnapshot: Codable, Equatable, Sendable {
    var id: PaneID
    var path: String
    var viewMode: BrowserViewMode
    var sort: SortOrder
    var history: PaneHistory
    var showHidden: Bool
}

struct WindowSnapshot: Codable, Equatable, Sendable {
    var frame: CGRect?
    var tree: PaneTree
    var panes: [PaneSnapshot]
    var activePane: PaneID
    var shelfVisible: Bool
}

struct Workspace: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var windows: [WindowSnapshot]
    var savedAt: Date
}

struct WorkspaceStore: Codable, Equatable, Sendable {
    private(set) var workspaces: [Workspace]

    init() { workspaces = [] }

    /// The name a new workspace gets: trimmed, "Workspace" when empty, "Name 2", "Name 3"… when taken.
    private func uniqueName(_ raw: String, excluding: UUID? = nil) -> String {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Workspace" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(workspaces.filter { $0.id != excluding }.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    mutating func save(name: String, windows: [WindowSnapshot], now: Date) -> Workspace {
        let ws = Workspace(id: UUID(), name: uniqueName(name), windows: windows, savedAt: now)
        workspaces.append(ws)
        return ws
    }

    /// Empty names and a name another workspace already has are refused (nothing changes).
    @discardableResult
    mutating func rename(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = workspaces.firstIndex(where: { $0.id == id }),
              !workspaces.contains(where: { $0.id != id && $0.name.lowercased() == trimmed.lowercased() }) else { return false }
        workspaces[i].name = trimmed
        return true
    }

    mutating func duplicate(_ id: UUID, now: Date) -> Workspace? {
        guard let original = workspaces.first(where: { $0.id == id }) else { return nil }
        let copy = Workspace(id: UUID(), name: uniqueName("\(original.name) copy"), windows: original.windows, savedAt: now)
        workspaces.append(copy)
        return copy
    }

    mutating func delete(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// "Export Saved Workspaces…": readable, stable JSON (sorted keys) — a view of the layouts, never file contents.
    func exportJSON() -> Data {
        (try? Self.encoder().encode(workspaces)) ?? Data("[]".utf8)
    }

    /// Each workspace is decoded on its own: one damaged entry (a hand-edited file, a field from a newer build) costs only
    /// that entry, counted in `skipped` so the page can say so.
    static func decode(_ data: Data) -> (store: WorkspaceStore, skipped: Int) {
        var store = WorkspaceStore()
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return (store, data.isEmpty ? 0 : 1)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var skipped = 0
        for item in raw {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let ws = try? decoder.decode(Workspace.self, from: itemData) else { skipped += 1; continue }
            store.workspaces.append(ws)
        }
        return (store, skipped)
    }
}

enum SessionRestore {
    /// A pane whose folder is gone opens `home`; its history keeps only folders that still exist. Never mounts anything.
    static func restored(_ window: WindowSnapshot, exists: (String) -> Bool, home: String) -> (window: WindowSnapshot, missing: [String]) {
        var w = window
        var missing: [String] = []
        for i in w.panes.indices {
            let path = w.panes[i].path
            if !exists(path) {
                missing.append(path)
                w.panes[i].path = home
            }
            w.panes[i].history.removeMissing(exists: exists, fallback: w.panes[i].path)
        }
        // A tree and a pane list that disagree (hand-edited file) must not leave a pane without a folder or a folder
        // without a pane: panes not in the tree are dropped; tree panes without a snapshot open home.
        let treePanes = Set(w.tree.panes)
        w.panes.removeAll { !treePanes.contains($0.id) }
        let known = Set(w.panes.map(\.id))
        for id in w.tree.panes where !known.contains(id) {
            w.panes.append(PaneSnapshot(id: id, path: home, viewMode: .list, sort: .finderDefault,
                                        history: PaneHistory(current: home), showHidden: false))
        }
        if !treePanes.contains(w.activePane), let first = w.tree.panes.first { w.activePane = first }
        return (w, missing)
    }

    /// Holding Shift at launch opens an empty window (FileOctopus' one-time skip); the setting turns restore off for good.
    static func shouldRestore(shiftHeld: Bool, reopenEnabled: Bool) -> Bool {
        reopenEnabled && !shiftHeld
    }
}
