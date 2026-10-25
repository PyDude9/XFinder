import Foundation
import CoreGraphics

/// XF-T28 — the layout snapshots behind session restore and named Workspaces (symlinked into the test package).
///
/// A workspace is a layout, not a backup: it remembers windows, their pane trees, each pane's folder, view, sort and
/// Back/Forward history — never file contents. Restoring never mounts a disk or recreates a folder: a pane whose folder
/// is gone opens Home and the person is told which folders were missing (spec XF-T28 §2.1 item 12, §4).
/// XF-T30 W1 — one tab of a pane (FileOctopus keeps folder, Back history, selection and view per pane tab).
struct TabSnapshot: Codable, Equatable, Sendable {
    var path: String
    var viewMode: BrowserViewMode
    var sort: SortOrder
    var history: PaneHistory
    var showHidden: Bool
    /// Names (not paths) selected in the tab, reselected after restore; at most `TabSnapshot.selectionLimit`.
    var selectedNames: [String]? = nil
    var groupBy: GroupBy? = nil
    /// Column view's whole column trail (Q-T30-7: restore it, FileOctopus only restores the last folder). W2 fills it.
    var columnPath: [String]? = nil

    static let selectionLimit = 200
}

/// A pane. The top-level path/view/sort/history/showHidden are the v1 (XF-T28) fields and always mirror the selected
/// tab, so a v1 build reading a v2 file still opens the right folder; `tabs` is nil in a v1 file.
struct PaneSnapshot: Codable, Equatable, Sendable {
    var id: PaneID
    var path: String
    var viewMode: BrowserViewMode
    var sort: SortOrder
    var history: PaneHistory
    var showHidden: Bool
    var tabs: [TabSnapshot]? = nil
    var selectedTab: Int? = nil

    /// Every tab, v1 files included (one tab built from the top-level fields).
    var allTabs: [TabSnapshot] {
        guard let tabs, !tabs.isEmpty else {
            return [TabSnapshot(path: path, viewMode: viewMode, sort: sort, history: history, showHidden: showHidden)]
        }
        return tabs
    }

    /// The selected tab's index into `allTabs`, clamped.
    var selectedTabIndex: Int {
        let count = allTabs.count
        guard count > 0 else { return 0 }
        return min(max(selectedTab ?? 0, 0), count - 1)
    }

    /// A v2 snapshot whose top-level fields mirror `tabs[selectedTab]`.
    init(id: PaneID, tabs: [TabSnapshot], selectedTab: Int) {
        let t = tabs.isEmpty ? nil : tabs[max(0, min(selectedTab, tabs.count - 1))]
        self.init(id: id, path: t?.path ?? "/", viewMode: t?.viewMode ?? .list, sort: t?.sort ?? .finderDefault,
                  history: t?.history ?? PaneHistory(current: t?.path ?? "/"), showHidden: t?.showHidden ?? false,
                  tabs: tabs, selectedTab: selectedTab)
    }

    init(id: PaneID, path: String, viewMode: BrowserViewMode, sort: SortOrder, history: PaneHistory, showHidden: Bool,
         tabs: [TabSnapshot]? = nil, selectedTab: Int? = nil) {
        self.id = id; self.path = path; self.viewMode = viewMode; self.sort = sort; self.history = history
        self.showHidden = showHidden; self.tabs = tabs; self.selectedTab = selectedTab
    }
}

struct WindowSnapshot: Codable, Equatable, Sendable {
    var frame: CGRect?
    var tree: PaneTree
    var panes: [PaneSnapshot]
    var activePane: PaneID
    var shelfVisible: Bool
    /// XF-T30 W1 — native window tabs: windows with the same `tabGroup` were one tab group, in `tabIndex` order;
    /// `selectedInGroup` marks the tab that was in front. nil for a window without tabs (and in v1 files).
    var tabGroup: Int? = nil
    var tabIndex: Int? = nil
    var selectedInGroup: Bool? = nil
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
    /// v2 (XF-T30 W1): a tab whose current folder is gone KEEPS its path — it becomes a dead tab (the pane/tab state
    /// reports the error and offers "Try Again"), never silently falling back to Home or a parent. History drops any
    /// entry (back or forward) whose target no longer exists, same as v1. `selectedTab` is clamped into range. Tree
    /// and pane-list disagreement (a hand-edited file) is repaired exactly as v1 did: panes outside the tree are
    /// dropped, tree panes missing a snapshot open Home. Never mounts anything.
    static func restored(_ window: WindowSnapshot, exists: (String) -> Bool, home: String) -> (window: WindowSnapshot, missing: [String]) {
        var w = window
        var missing: [String] = []
        for i in w.panes.indices {
            var tabs = w.panes[i].allTabs
            for t in tabs.indices {
                if !exists(tabs[t].path) {
                    missing.append(tabs[t].path)
                    // Dead tab: path is kept as-is (the view/model layer shows "Try Again" for it), only its
                    // history is pruned of now-missing entries. The fallback passed to `removeMissing` is the
                    // tab's own (unreachable) path, since v2 never redirects a dead tab's `current` elsewhere.
                }
                tabs[t].history.removeMissing(exists: exists, fallback: tabs[t].path)
            }
            let selected = min(max(w.panes[i].selectedTab ?? w.panes[i].selectedTabIndex, 0), max(tabs.count - 1, 0))
            w.panes[i] = PaneSnapshot(id: w.panes[i].id, tabs: tabs, selectedTab: selected)
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
