import AppKit
import Observation

/// XF-T28 cluster C — STUB (contract: docs/specs/XF-T28-ui-contract.md).
enum PaneLoadState: Equatable { case idle, loading, loaded, failed(DirectoryReadError) }

struct PaneSearchState: Equatable {
    enum Scope: String, CaseIterable { case folder, mac, panes }
    var text: String
    var parsed: ParsedSearch
    var scope: Scope
    var results: [DirectoryEntry]
    var running: Bool
    var truncated: Bool
}

@MainActor @Observable final class PaneState: Identifiable {
    let id: PaneID
    private(set) var path: String
    private(set) var history: PaneHistory
    var viewMode: BrowserViewMode
    var sort: SortOrder
    var showHidden: Bool
    var foldersFirst = false
    private(set) var entries: [DirectoryEntry] = []
    private(set) var loadState: PaneLoadState = .idle
    var selection: Set<String> = []
    var filterText = ""
    var search: PaneSearchState?
    var selectAfterLoad: String?

    init(id: PaneID, path: String, viewMode: BrowserViewMode, sort: SortOrder, showHidden: Bool, history: PaneHistory?) {
        self.id = id
        self.path = path
        self.history = history ?? PaneHistory(current: path)
        self.viewMode = viewMode
        self.sort = sort
        self.showHidden = showHidden
    }

    func navigate(to path: String) { self.path = path }
    func goBack() {}
    func goForward() {}
    func goUp() {}
    func reload() {}
    func open(_ entry: DirectoryEntry) {}
    func runSearch(_ text: String, scope: PaneSearchState.Scope) {}
    func endSearch() { search = nil }
    var selectedEntries: [DirectoryEntry] { entries.filter { selection.contains($0.path) } }
    func stopWatching() {}
}

@MainActor @Observable final class BrowserWindowModel {
    enum PaletteMode: Equatable { case quickOpen, commands }

    var tree: PaneTree
    private(set) var panes: [PaneID: PaneState]
    var activePane: PaneID
    var shelf = ShelfModel()
    var shelfVisible = false
    var palette: PaletteMode?
    var editingLocation: PaneID?
    var renaming: PaneID?
    var batchRenameSources: [String]?
    var banner: String?

    init(snapshot: WindowSnapshot?, initialPath: String?) {
        let tree = PaneTree()
        let first = tree.panes[0]
        self.tree = tree
        self.activePane = first
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.panes = [first: PaneState(id: first, path: initialPath ?? home, viewMode: .list, sort: .finderDefault,
                                       showHidden: false, history: nil)]
    }

    var active: PaneState { panes[activePane] ?? panes.values.first! }
    @discardableResult func perform(_ command: BrowserCommand) -> Bool { false }
    func canPerform(_ command: BrowserCommand) -> Bool { false }
    func focus(_ pane: PaneID) { activePane = pane }
    func snapshot(frame: CGRect?) -> WindowSnapshot {
        WindowSnapshot(frame: frame, tree: tree, panes: [], activePane: activePane, shelfVisible: shelfVisible)
    }
    func commitRename(_ path: String, to newName: String) -> Bool { false }
    func drop(_ paths: [String], into folder: String, copy: Bool?) {}
    func tearDown() {}
}
