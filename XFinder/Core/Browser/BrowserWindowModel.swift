import AppKit
import Observation

/// XF-T28 cluster C (contract: docs/specs/XF-T28-ui-contract.md) — the file browser window's state: one `PaneState`
/// per leaf of the `PaneTree`, plus the single dispatcher (`perform(_:)`) every key, menu and toolbar button goes
/// through. Loading, searching and watching are all here (Cụm A gives the mechanisms — `DirectoryReader`,
/// `DirectoryWatcher`, `FileIconCache` — this file decides when to call them and what to do with what comes back);
/// the actual copy/move/trash work is Cụm B's `FileOperationQueue`, which this file only enqueues onto.
enum PaneLoadState: Equatable {
    case idle, loading, loaded, failed(DirectoryReadError)
}

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
    var filterText = "" {
        didSet { if filterText != oldValue { applyEntries() } }
    }
    var search: PaneSearchState?
    var selectAfterLoad: String?

    /// Bumped on every `navigate`/`reload`; a load whose generation no longer matches `currentGeneration` when it
    /// completes is stale (the pane moved on) and its result is thrown away instead of overwriting newer entries.
    private var currentGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var watcher: DirectoryWatcher?
    /// The raw listing from the last successful load, before `visible`/`filter`/`sorted` — kept so a view-option
    /// change (sort, showHidden, foldersFirst, filterText) or a search ending can re-derive `entries` without a
    /// fresh disk read.
    private var rawEntries: [DirectoryEntry] = []

    init(id: PaneID, path: String, viewMode: BrowserViewMode, sort: SortOrder, showHidden: Bool, history: PaneHistory?) {
        self.id = id
        self.path = path
        self.history = history ?? PaneHistory(current: path)
        self.viewMode = viewMode
        self.sort = sort
        self.showHidden = showHidden
        startLoad(of: path)
        installWatcher()
    }

    // MARK: - Navigation

    /// Records history and loads `path`'s listing; cancels whatever load was already in flight.
    func navigate(to path: String) {
        guard path != self.path else { return }
        history.visit(path)
        self.path = path
        startLoad(of: path)
        installWatcher()
    }

    func goBack() {
        guard let destination = history.goBack() else { return }
        path = destination
        startLoad(of: destination)
        installWatcher()
    }

    func goForward() {
        guard let destination = history.goForward() else { return }
        path = destination
        startLoad(of: destination)
        installWatcher()
    }

    /// ⌘↑: remember the folder we're leaving so re-entering the parent can reselect it, same as Finder.
    func goUp() {
        let current = (path as NSString)
        let parent = current.deletingLastPathComponent
        guard !parent.isEmpty, parent != path else { return }
        let leftChildName = current.lastPathComponent
        history.noteLeaving(child: leftChildName, of: parent)
        selectAfterLoad = leftChildName
        navigate(to: parent)
    }

    func reload() {
        startLoad(of: path)
    }

    /// A folder navigates into it; a file or package opens with its default app, same as Finder.
    func open(_ entry: DirectoryEntry) {
        if entry.isFolderLike {
            navigate(to: entry.path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        }
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    var selectedEntries: [DirectoryEntry] {
        entries.filter { selection.contains($0.path) }
    }

    // MARK: - Loading

    private func startLoad(of path: String) {
        loadTask?.cancel()
        currentGeneration += 1
        let generation = currentGeneration
        loadState = .loading
        loadTask = Task { [weak self] in
            let result = await DirectoryReader.list(path, timeout: 5)
            guard let self, !Task.isCancelled, generation == self.currentGeneration else { return }
            switch result {
            case .success(let listing):
                self.rawEntries = listing
                self.loadState = .loaded
                self.applyEntries()
                if let wanted = self.selectAfterLoad, listing.contains(where: { $0.name == wanted }) {
                    // `appendingPathComponent`, not string concatenation — `path` can be "/" (a volume root),
                    // where "\(path)/\(wanted)" doubles the slash and never matches any entry's `path`.
                    self.selection = [(path as NSString).appendingPathComponent(wanted)]
                }
                self.selectAfterLoad = nil
            case .failure(let error):
                self.rawEntries = []
                self.entries = []
                self.loadState = .failed(error)
            }
        }
    }

    /// Re-derives `entries` from `rawEntries` (or the active search's results) through the visible/filter/sort
    /// pipeline, without touching disk.
    private func applyEntries() {
        let base = search == nil ? rawEntries : (search?.results ?? [])
        let visible = EntryRules.visible(base, showHidden: showHidden)
        let filtered = EntryRules.filter(visible, query: filterText)
        entries = EntryRules.sorted(filtered, by: sort, foldersFirst: foldersFirst) { entry in
            FileIconCache.shared.kindName(for: entry)
        }
    }

    private func installWatcher() {
        watcher?.cancel()
        let watchedPath = path
        watcher = DirectoryWatcher(
            path: watchedPath,
            onChange: { [weak self] in
                guard let self, self.path == watchedPath else { return }
                let keptSelection = self.selection
                self.reload()
                self.selection = keptSelection
            },
            onGone: { [weak self] in
                guard let self, self.path == watchedPath else { return }
                self.navigateToNearestExistingAncestor(from: watchedPath)
            }
        )
    }

    /// The watched folder vanished (deleted/renamed out from under us): walk up to the first ancestor that still
    /// exists, falling back to Home if none do.
    private func navigateToNearestExistingAncestor(from goneP: String) {
        var candidate = (goneP as NSString).deletingLastPathComponent
        let fm = FileManager.default
        var isDir: ObjCBool = false
        while !candidate.isEmpty, candidate != "/" {
            if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                navigate(to: candidate)
                return
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        if fm.fileExists(atPath: "/", isDirectory: &isDir), isDir.boolValue {
            navigate(to: FileManager.default.homeDirectoryForCurrentUser.path)
        }
    }

    // MARK: - Search

    /// `paneFolders`: the open panes' folders, supplied by `BrowserWindowModel.runSearch` for `.panes` — this pane
    /// cannot see its siblings, only the window model holds `panes: [PaneID: PaneState]`. Any other scope ignores it.
    func runSearch(_ text: String, scope: PaneSearchState.Scope, paneFolders: [String] = []) {
        let now = Date()
        let calendar = Calendar.current
        let parsed = SearchQuery.parse(text, now: now, calendar: calendar)
        startSearch(text: text, parsed: parsed, scope: scope, paneFolders: paneFolders, now: now, calendar: calendar)
    }

    /// Runs a search straight from an already-`ParsedSearch` (edited chips): same pipeline as
    /// `runSearch(_:scope:paneFolders:)` but skips `SearchQuery.parse` — a chip edit (remove/replace) only ever
    /// changes `ParsedSearch`, and rebuilding it back into text first would drop chips that cannot round-trip
    /// through text (pastDays / olderThan / month — spec XF-T28 Wave 4 §E), which is exactly the bug this exists to
    /// fix. `text` on the resulting `PaneSearchState` is kept as whatever free terms/phrases remain so the search
    /// bar's text field still shows something sensible; a chips-only edit (no terms left) shows an empty field,
    /// same as starting a fresh search would.
    func runSearch(parsed: ParsedSearch, scope: PaneSearchState.Scope, paneFolders: [String] = []) {
        let now = Date()
        let calendar = Calendar.current
        let text = (parsed.terms + parsed.phrases.map { "\"\($0)\"" }).joined(separator: " ")
        startSearch(text: text, parsed: parsed, scope: scope, paneFolders: paneFolders, now: now, calendar: calendar)
    }

    /// Shared tail of both `runSearch` overloads (text and chip-edited): builds the `mdfind` expression and scopes,
    /// then runs the actual search off the main actor. Both the `mdfind` process AND the `lstat()` of every hit (up
    /// to 200) belong off the main actor — a network-mounted result can stall each stat for a while, and this used
    /// to run the whole `lstat` loop back on `@MainActor` after only the process hop was detached.
    private func startSearch(text: String, parsed: ParsedSearch, scope: PaneSearchState.Scope, paneFolders: [String],
                             now: Date, calendar: Calendar) {
        search = PaneSearchState(text: text, parsed: parsed, scope: scope, results: [], running: true, truncated: false)
        let generation = currentGeneration
        let expression = SearchQuery.mdfindExpression(parsed, now: now, calendar: calendar)
        let scopes = searchScopes(for: scope, paneFolders: paneFolders)
        Task { [weak self] in
            let results = await Task.detached(priority: .userInitiated) { () -> (found: FileSearchEngine.Found, entries: [DirectoryEntry]) in
                let found = FileSearchEngine.runMdfind(query: expression, scopes: scopes, limit: 200)
                var entries: [DirectoryEntry] = []
                entries.reserveCapacity(found.items.count)
                for item in found.items {
                    if let entry = PaneState.entry(forPath: item.path) {
                        entries.append(entry)
                    }
                }
                return (found, entries)
            }.value
            guard let self, generation == self.currentGeneration, self.search != nil else { return }
            self.search?.results = results.entries
            self.search?.running = false
            self.search?.truncated = results.found.truncated
            self.applyEntries()
        }
    }

    /// `.folder` searches only this pane's own path; `.mac` searches the whole machine (no scope folders);
    /// `.panes` searches every open pane's folder — `paneFolders`, supplied by `BrowserWindowModel.runSearch` (the
    /// only thing that can see every pane). Falls back to just this pane's own folder if nothing was supplied
    /// (e.g. a lone pane, or a caller that goes straight to `PaneState.runSearch`).
    private func searchScopes(for scope: PaneSearchState.Scope, paneFolders: [String]) -> [URL] {
        switch scope {
        case .folder: return [URL(fileURLWithPath: path)]
        case .mac: return []
        case .panes:
            let folders = paneFolders.isEmpty ? [path] : paneFolders
            return folders.map { URL(fileURLWithPath: $0) }
        }
    }

    func endSearch() {
        search = nil
        applyEntries()
    }

    /// Builds a `DirectoryEntry` for a search hit via `lstat` (a search result may be anywhere on disk, not just
    /// the current folder's listing, so this does not go through `DirectoryReader.list`). `nonisolated`: called
    /// from inside `Task.detached` off the main actor, same as the mdfind call next to it — a path's `lstat` does
    /// not touch any pane state.
    fileprivate nonisolated static func entry(forPath path: String) -> DirectoryEntry? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let name = (path as NSString).lastPathComponent
        let kind: DirectoryEntry.Kind
        switch st.st_mode & S_IFMT {
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symlink
        case S_IFREG: kind = .file
        default: kind = .other
        }
        let isPackage = kind == .directory && Self.packageExtensions.contains((name as NSString).pathExtension.lowercased())
        let isHidden = (st.st_flags & UInt32(UF_HIDDEN)) != 0 || name.hasPrefix(".")
        let size = kind == .directory ? Int64(-1) : Int64(st.st_size)
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
        let created = Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec) + TimeInterval(st.st_birthtimespec.tv_nsec) / 1e9)
        return DirectoryEntry(name: name, path: path, kind: kind, isPackage: isPackage, isHidden: isHidden,
                              size: size, modified: modified, created: created, volumeID: Int32(st.st_dev))
    }

    /// `nonisolated`: a plain constant read from `entry(forPath:)`, which itself runs off the main actor.
    private nonisolated static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "pages", "numbers", "key", "rtfd", "photoslibrary", "xcodeproj", "playground",
    ]
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
    var banner: String? {
        didSet { scheduleBannerClear() }
    }
    /// Remembers which archive a `compress` created, so `undo` can trash it (spec: "ZIP: ⌘Z đưa tệp ZIP vào
    /// Thùng rác" — `FileOperationQueue.undoLast()` only knows about copy/move/rename/duplicate/trash jobs it ran
    /// itself, not about a ZIP this model asked `ArchiveRunner` to build directly).
    private var lastCompressedArchive: String?
    private var bannerClearTask: Task<Void, Never>?
    /// The sync pair shown side by side in this window (XF-T28 Wave 4 §C). Backing storage for the public
    /// `activeSyncPair` read-only property in the Wave 4 extension below.
    fileprivate var activeSyncPairStorage: FolderSyncController.Pair?

    init(snapshot: WindowSnapshot?, initialPath: String?) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let snapshot {
            self.tree = snapshot.tree
            self.activePane = snapshot.activePane
            var built: [PaneID: PaneState] = [:]
            for paneSnapshot in snapshot.panes {
                built[paneSnapshot.id] = PaneState(
                    id: paneSnapshot.id, path: paneSnapshot.path, viewMode: paneSnapshot.viewMode,
                    sort: paneSnapshot.sort, showHidden: paneSnapshot.showHidden, history: paneSnapshot.history)
            }
            // A tree/pane-list mismatch (hand-edited session file) must not leave a leaf without a `PaneState`.
            for id in snapshot.tree.panes where built[id] == nil {
                built[id] = PaneState(id: id, path: home, viewMode: BrowserSettings.defaultView,
                                      sort: .finderDefault, showHidden: BrowserSettings.showHidden, history: nil)
            }
            self.panes = built
            self.shelfVisible = snapshot.shelfVisible
            if !snapshot.tree.panes.contains(activePane), let first = snapshot.tree.panes.first {
                self.activePane = first
            }
        } else {
            let tree = PaneTree()
            let first = tree.panes[0]
            self.tree = tree
            self.activePane = first
            self.panes = [first: PaneState(id: first, path: initialPath ?? home, viewMode: BrowserSettings.defaultView,
                                           sort: .finderDefault, showHidden: BrowserSettings.showHidden, history: nil)]
        }
    }

    var active: PaneState { panes[activePane] ?? panes.values.first! }

    func focus(_ pane: PaneID) {
        guard tree.contains(pane) else { return }
        activePane = pane
    }

    // MARK: - The one dispatcher

    /// Every key, menu item, toolbar button and palette entry funnels through here. Returns `false` when the
    /// command had nothing to do (the view/controller then lets the chord fall through, e.g. to a text field).
    @discardableResult
    func perform(_ command: BrowserCommand) -> Bool {
        guard canPerform(command) else { return false }
        switch command {
        case .newWindow:
            BrowserWindowController.shared.openWindow(path: nil)
        case .newFolder:
            createNewFolder()
        case .open:
            for entry in active.selectedEntries { active.open(entry) }
        case .openEnclosing:
            active.goUp()
        case .back:
            active.goBack()
        case .forward:
            active.goForward()
        case .rename:
            guard active.selection.count == 1 else { return false }
            renaming = activePane
        case .duplicate:
            duplicateSelection()
        case .moveToTrash:
            trashSelection()
        case .quickLook:
            BrowserWindowController.shared.toggleQuickLook(for: self)
        case .copy:
            copySelectionToPasteboard()
        case .paste:
            pasteFromPasteboard(move: false)
        case .pasteMove:
            pasteFromPasteboard(move: true)
        case .copyPath:
            copySelectionPaths()
        case .toggleHidden:
            active.showHidden.toggle()
        case .selectAll:
            active.selection = Set(active.entries.map(\.path))
        case .undo:
            // `FileOperationQueue.undoLast()` returns ALREADY-RENDERED text (it calls `L10n.t` itself before
            // returning — the same "model returns rendered text" trap `L10n.swift`'s header warns about, and the
            // exact one `syncNow` below works around): routing it through `banner`, which `BrowserRootView` passes
            // through `L10n.t` a second time, double-translates it. A fixed literal here, like `syncNow`'s own
            // banner, side-steps that; the detailed per-item count still shows wherever `undoLast()`'s caller
            // already displays it verbatim (Lịch sử thao tác page).
            if FileOperationQueue.shared.undoLast() != nil {
                banner = "Đã hoàn tác"
            } else if let archive = lastCompressedArchive {
                _ = FileOperationQueue.shared.enqueue(.trash, sources: [archive], destination: nil)
                lastCompressedArchive = nil
            }
        case .viewIcons:
            active.viewMode = .icons
        case .viewList:
            active.viewMode = .list
        case .viewColumns:
            active.viewMode = .columns
        case .viewGallery:
            active.viewMode = .gallery
        case .filter:
            break   // the search bar owns first responder for the filter field; nothing to dispatch here.
        case .find:
            if active.search == nil {
                runSearch("", scope: .folder)
            }
        case .editLocation:
            editingLocation = activePane
        case .goToFolder:
            editingLocation = activePane
        case .quickOpen:
            palette = .quickOpen
        case .commandPalette:
            palette = .commands
        case .splitRight:
            splitGated(.right)
        case .splitLeft:
            splitGated(.left)
        case .splitDown:
            splitGated(.down)
        case .splitUp:
            splitGated(.up)
        case .closePane:
            if let next = tree.close(activePane) {
                let removedPane = panes.removeValue(forKey: activePane)
                removedPane?.stopWatching()
                activePane = next
            }
        case .equalizePanes:
            tree.equalize()
        case .zoomPane:
            tree.toggleZoom(activePane)
        case .nextPane:
            activePane = tree.next(after: activePane)
        case .previousPane:
            activePane = tree.previous(before: activePane)
        case .presetSingle:
            applyPreset(.single)
        case .presetSideBySide:
            applyPreset(.sideBySide)
        case .presetStacked:
            applyPreset(.stacked)
        case .presetGrid:
            applyPreset(.grid)
        case .copyToOtherPane:
            copyOrMoveToOtherPane(move: false)
        case .moveToOtherPane:
            copyOrMoveToOtherPane(move: true)
        case .addToShelf:
            addSelectionToShelfGated()
        case .toggleShelf:
            shelfVisible.toggle()
        case .operations:
            break   // view-only: opens the OperationsPanelView popover.
        case .batchRename:
            let sources = active.selectedEntries.isEmpty ? active.entries.map(\.path) : active.selectedEntries.map(\.path)
            guard !sources.isEmpty else { return false }
            batchRenameSources = sources
        case .compress:
            compressSelection()
        case .saveWorkspace:
            _ = saveWorkspace(named: "Workspace")
        case .openWorkspace:
            break   // view-only: opens the workspace list sheet.
        case .downloadNow:
            guard batchCloudGated(active.selectedEntries) else { return true }
            downloadSelectionNow()
        case .removeDownload:
            guard batchCloudGated(active.selectedEntries) else { return true }
            removeDownloadForSelection()
        case .showInFinder:
            let urls = active.selectedEntries.map { URL(fileURLWithPath: $0.path) }
            guard !urls.isEmpty else { return false }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .closeWindow:
            break   // view-only: the owning NSWindow closes itself.
        case .getInfo:
            let paths = getInfoTargetPaths()
            guard !paths.isEmpty else { return false }
            GetInfoWindowController.shared.show(paths: paths, readOnly: active.search != nil)
        }
        return true
    }

    /// `.getInfo`'s target: the selection, or — with nothing selected — the folder the active pane shows (same as
    /// Finder's ⌘I with no selection: "Get Info" on the enclosing folder itself).
    private func getInfoTargetPaths() -> [String] {
        let selected = active.selectedEntries.map(\.path)
        return selected.isEmpty ? [active.path] : selected
    }

    func canPerform(_ command: BrowserCommand) -> Bool {
        switch command {
        case .splitRight, .splitLeft, .splitDown, .splitUp:
            // XF-T29: false at the Free pane limit, same as at the hard 16-pane ceiling — a layout already bigger
            // than the limit (inherited from a trial or a Workspace) stays usable, just cannot grow further.
            return canSplitUnderLicense
        case .closePane:
            return tree.count > 1
        case .rename:
            return active.selection.count == 1
        case .open, .openEnclosing, .moveToTrash, .duplicate, .copyPath, .quickLook, .showInFinder, .copy:
            return !active.selectedEntries.isEmpty
        case .back:
            return active.history.canGoBack
        case .forward:
            return active.history.canGoForward
        case .paste, .pasteMove:
            return true
        case .copyToOtherPane, .moveToOtherPane:
            return tree.count >= 2 && !active.selectedEntries.isEmpty && tree.other(than: activePane) != nil
        case .addToShelf:
            return !active.selectedEntries.isEmpty
        case .compress:
            return !active.selectedEntries.isEmpty
        case .batchRename:
            return !active.entries.isEmpty
        case .downloadNow, .removeDownload:
            return !active.selectedEntries.isEmpty
        case .undo:
            return true
        case .newWindow, .newFolder, .toggleHidden, .selectAll, .viewIcons, .viewList, .viewColumns, .viewGallery,
             .filter, .find, .editLocation, .goToFolder, .quickOpen, .commandPalette, .equalizePanes, .zoomPane,
             .nextPane, .previousPane, .presetSingle, .presetSideBySide, .presetStacked, .presetGrid, .toggleShelf,
             .operations, .saveWorkspace, .openWorkspace, .closeWindow:
            return true
        case .getInfo:
            // A search pane with no results yet still shows an (empty) folder-less state — only true when there is
            // something to describe: a selection, or a normal (non-search) pane showing a real folder.
            return !active.selectedEntries.isEmpty || active.search == nil
        }
    }

    // MARK: - Pane tree helpers

    private func split(_ direction: SplitDirection) {
        guard let newID = tree.split(activePane, direction) else { return }
        let template = active
        panes[newID] = PaneState(id: newID, path: template.path, viewMode: template.viewMode, sort: template.sort,
                                 showHidden: template.showHidden, history: nil)
        activePane = newID
    }

    private func applyPreset(_ preset: PanePreset) {
        let template = active
        let (kept, removed) = tree.apply(preset)
        for id in removed {
            panes.removeValue(forKey: id)?.stopWatching()
        }
        for id in kept where panes[id] == nil {
            panes[id] = PaneState(id: id, path: template.path, viewMode: BrowserSettings.defaultView,
                                  sort: .finderDefault, showHidden: BrowserSettings.showHidden, history: nil)
        }
        if !kept.contains(activePane), let first = kept.first {
            activePane = first
        }
    }

    // MARK: - File operations

    private func createNewFolder() {
        let existing = Set(active.entries.map(\.name))
        let name = FileOperationRules.keepBothName(for: "untitled folder", existing: existing)
        let destination = (active.path as NSString).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: false)
            active.selection = [destination]
            active.selectAfterLoad = name
            renaming = activePane
            active.reload()
        } catch {
            banner = "Không tạo được thư mục mới"
        }
    }

    private func duplicateSelection() {
        let selected = active.selectedEntries
        guard !selected.isEmpty else { return }
        let existing = Set(active.entries.map(\.name))
        var taken = existing
        for entry in selected {
            let newName = FileOperationRules.duplicateName(for: entry.name, existing: taken)
            taken.insert(newName)
            let destination = (active.path as NSString).appendingPathComponent(newName)
            _ = FileOperationQueue.shared.enqueue(.duplicate, sources: [entry.path], destination: destination)
        }
    }

    private func trashSelection() {
        let paths = active.selectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        _ = FileOperationQueue.shared.enqueue(.trash, sources: paths, destination: nil)
    }

    /// `commitRename` is the only path that actually renames a file (⌘⇧N also routes through it after the new
    /// folder is created and `renaming` is set). Rejects the empty name and the two characters Finder itself
    /// rejects (":" is HFS+'s path separator under the hood, "/" is everyone's).
    func commitRename(_ path: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(":"), !trimmed.contains("/") else {
            banner = "Tên không được để trống hoặc chứa \":\" \"/\""
            return false
        }
        let directory = (path as NSString).deletingLastPathComponent
        let destination = (directory as NSString).appendingPathComponent(trimmed)
        guard destination != path else {
            renaming = nil
            return true
        }
        guard !FileManager.default.fileExists(atPath: destination) else {
            banner = "Đã có mục khác tên này"
            return false
        }
        do {
            try FileManager.default.moveItem(atPath: path, toPath: destination)
            ActionHistoryStore.shared.recordRenames(pairs: [(old: URL(fileURLWithPath: path), new: URL(fileURLWithPath: destination))])
            renaming = nil
            active.selection = [destination]
            active.reload()
            return true
        } catch {
            banner = "Không đổi được tên"
            return false
        }
    }

    // MARK: - Pasteboard

    private func copySelectionToPasteboard() {
        let urls = active.selectedEntries.map { URL(fileURLWithPath: $0.path) as NSURL }
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls)
    }

    private func copySelectionPaths() {
        let paths = active.selectedEntries.map(\.path).joined(separator: "\n")
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
    }

    private func pasteFromPasteboard(move: Bool) {
        guard let items = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !items.isEmpty else { return }
        drop(items.map(\.path), into: active.path, copy: move ? false : true)
    }

    /// Drag-and-drop and ⌘V/⌥⌘V both land here. `copy`: `nil` ⇒ same volume moves, cross-volume copies (Finder's
    /// own default); `true` forces a copy (⌥ while dragging, plain ⌘V); `false` forces a move (⌘ while dragging,
    /// ⌥⌘V).
    func drop(_ paths: [String], into folder: String, copy: Bool?) {
        guard FileOperationRules.nestingViolation(sources: paths, destination: folder) == nil else {
            banner = "Không thể chép một thư mục vào chính nó"
            return
        }
        let sameVolume = DirectoryReader.volumeID(of: folder) != nil
            && paths.allSatisfy { DirectoryReader.volumeID(of: $0) == DirectoryReader.volumeID(of: folder) }
        let shouldCopy: Bool
        if let copy {
            shouldCopy = copy
        } else {
            shouldCopy = !sameVolume
        }
        enqueueGated(shouldCopy ? .copy : .move, sources: paths, destination: folder)
    }

    private func copyOrMoveToOtherPane(move: Bool) {
        guard let other = tree.other(than: activePane), let otherPane = panes[other] else { return }
        let paths = active.selectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        enqueueGated(move ? .move : .copy, sources: paths, destination: otherPane.path)
    }

    // MARK: - Search

    /// Runs the active pane's search, resolving `.panes` to every open pane's folder first — only the window model
    /// can see `panes: [PaneID: PaneState]`, so `.panes` must come through here rather than `PaneState.runSearch`
    /// directly (which, with no folders supplied, can only fall back to its own single folder).
    func runSearch(_ text: String, scope: PaneSearchState.Scope) {
        let folders = scope == .panes ? tree.panes.compactMap { panes[$0]?.path } : []
        active.runSearch(text, scope: scope, paneFolders: folders)
    }

    // MARK: - Shelf

    private func addSelectionToShelf() {
        let selected = active.selectedEntries
        guard !selected.isEmpty else { return }
        var sizes: [String: Int64] = [:]
        for entry in selected where entry.size >= 0 { sizes[entry.path] = entry.size }
        shelf.add(selected.map(\.path), sizes: sizes)
    }

    // MARK: - Compress / archive

    private func compressSelection() {
        let selected = active.selectedEntries
        guard !selected.isEmpty else { return }
        let urls = selected.map { URL(fileURLWithPath: $0.path) }
        let name = ArchiveEngine.archiveName(selected.count == 1 ? selected[0].name : "Archive")
        let base = URL(fileURLWithPath: active.path).appendingPathComponent("\(name).zip")
        let destination = ArchiveEngine.destination(base: base, policy: .keepBoth) { FileManager.default.fileExists(atPath: $0.path) }
        guard case .write(let output) = destination else { return }
        lastCompressedArchive = output.path
        Task {
            let result = await ArchiveRunner.compress(sources: urls, format: .zip, output: output)
            await MainActor.run {
                switch result {
                case .success:
                    self.active.reload()
                case .failure(let failure):
                    self.banner = failure.messageKey
                    self.lastCompressedArchive = nil
                }
            }
        }
    }

    // MARK: - Cloud

    private func downloadSelectionNow() {
        for entry in active.selectedEntries {
            try? FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: entry.path))
        }
    }

    private func removeDownloadForSelection() {
        for entry in active.selectedEntries {
            try? FileManager.default.evictUbiquitousItem(at: URL(fileURLWithPath: entry.path))
        }
    }

    // MARK: - Banner

    private func scheduleBannerClear() {
        bannerClearTask?.cancel()
        guard banner != nil else { return }
        bannerClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    // MARK: - Snapshot / teardown

    func snapshot(frame: CGRect?) -> WindowSnapshot {
        let paneSnapshots = tree.panes.compactMap { id -> PaneSnapshot? in
            guard let state = panes[id] else { return nil }
            return PaneSnapshot(id: id, path: state.path, viewMode: state.viewMode, sort: state.sort,
                               history: state.history, showHidden: state.showHidden)
        }
        return WindowSnapshot(frame: frame, tree: tree, panes: paneSnapshots, activePane: activePane, shelfVisible: shelfVisible)
    }

    func tearDown() {
        bannerClearTask?.cancel()
        for pane in panes.values { pane.stopWatching() }
    }
}

// MARK: - Wave 4 API (XF-T28 Wave 4 / XF-T29 Pro gates)

extension BrowserWindowModel {
    /// Saved workspaces, read from disk on first use each call — the store is a small JSON file (not kept resident
    /// in the model), so every reader always sees the latest save made from any window.
    var workspaces: [Workspace] {
        WorkspaceStore.decode(WorkspaceStore.load()).store.workspaces
    }

    /// Pro (`.browserWorkspaces`; XF-T29 — rename/delete/export stay free, only save/open are gated). Free ⇒ banner
    /// + nil, nothing written.
    @discardableResult
    func saveWorkspace(named name: String) -> Workspace? {
        guard LicenseManager.shared.allows(.browserWorkspaces) else {
            banner = "Cần XFinder Pro để lưu Workspace"
            return nil
        }
        var (store, _) = WorkspaceStore.decode(WorkspaceStore.load())
        let saved = store.save(name: name, windows: [snapshot(frame: nil)], now: Date())
        store.persist()
        return saved
    }

    /// Pro (`.browserWorkspaces`). Replaces THIS window's layout with the workspace's first window; any further
    /// windows the workspace remembers open as new windows (one window can only show one layout at a time).
    func openWorkspace(_ id: UUID) {
        guard LicenseManager.shared.allows(.browserWorkspaces) else {
            banner = "Cần XFinder Pro để mở Workspace"
            return
        }
        guard let workspace = workspaces.first(where: { $0.id == id }), let first = workspace.windows.first else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let (restored, missing) = SessionRestore.restored(first, exists: { FileManager.default.fileExists(atPath: $0) }, home: home)
        replaceLayout(with: restored)
        if !missing.isEmpty {
            banner = "Một số thư mục của Workspace này không còn tồn tại"
        }
        for extra in workspace.windows.dropFirst() {
            let (restoredExtra, _) = SessionRestore.restored(extra, exists: { FileManager.default.fileExists(atPath: $0) }, home: home)
            BrowserWindowController.shared.openRestoredWindow(restoredExtra)
        }
    }

    /// Replaces this window's own pane tree/layout in place (used by `openWorkspace` — stays free to read, the
    /// gate is on reaching this method at all).
    private func replaceLayout(with snapshot: WindowSnapshot) {
        for pane in panes.values { pane.stopWatching() }
        tree = snapshot.tree
        var built: [PaneID: PaneState] = [:]
        for paneSnapshot in snapshot.panes {
            built[paneSnapshot.id] = PaneState(
                id: paneSnapshot.id, path: paneSnapshot.path, viewMode: paneSnapshot.viewMode,
                sort: paneSnapshot.sort, showHidden: paneSnapshot.showHidden, history: paneSnapshot.history)
        }
        for id in snapshot.tree.panes where built[id] == nil {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            built[id] = PaneState(id: id, path: home, viewMode: BrowserSettings.defaultView,
                                  sort: .finderDefault, showHidden: BrowserSettings.showHidden, history: nil)
        }
        panes = built
        shelfVisible = snapshot.shelfVisible
        activePane = snapshot.tree.panes.contains(snapshot.activePane) ? snapshot.activePane : (snapshot.tree.panes.first ?? activePane)
        activeSyncPairStorage = nil
    }

    /// Rename/delete/export stay free (spec XF-T29 §2): only saving/opening a workspace needs Pro.
    @discardableResult
    func renameWorkspace(_ id: UUID, to name: String) -> Bool {
        var (store, _) = WorkspaceStore.decode(WorkspaceStore.load())
        guard store.rename(id, to: name) else { return false }
        store.persist()
        return true
    }

    func duplicateWorkspace(_ id: UUID) {
        var (store, _) = WorkspaceStore.decode(WorkspaceStore.load())
        guard store.duplicate(id, now: Date()) != nil else { return }
        store.persist()
    }

    func deleteWorkspace(_ id: UUID) {
        var (store, _) = WorkspaceStore.decode(WorkspaceStore.load())
        store.delete(id)
        store.persist()
    }

    func exportWorkspaces() -> Data {
        WorkspaceStore.decode(WorkspaceStore.load()).store.exportJSON()
    }

    // MARK: - Sync pair

    /// Side by Side: left pane = source, right pane = destination; opening either pane somewhere else clears the
    /// pair (`observeSyncPaneDrift`, installed by `openSyncPair`).
    func openSyncPair(_ pair: FolderSyncController.Pair) {
        applyPreset(.sideBySide)
        let ids = tree.panes
        guard ids.count >= 2, let sourcePane = panes[ids[0]], let destPane = panes[ids[1]] else { return }
        sourcePane.navigate(to: pair.sourcePath)
        destPane.navigate(to: pair.destPath)
        activeSyncPairStorage = pair
        observeSyncPaneDrift(sourceID: ids[0], destID: ids[1], pair: pair)
    }

    /// Runs `FolderSyncController.shared.run(pair)` off the main thread (the controller itself hops to a detached
    /// task for the `rsync` process — this only awaits it and brings the banner back to main), for the window's
    /// `activeSyncPair`. Pro-gated inside `FolderSyncController.run` itself (`.folderSync`); false when nothing ran,
    /// either because there is no active pair or because Free has no sync pro access.
    @discardableResult
    func syncNow() async -> Bool {
        guard let pair = activeSyncPair else { return false }
        let ok = await FolderSyncController.shared.run(pair)
        // `FolderSyncController.lastError` is already display text (it calls `L10n.t` itself before storing it —
        // the exact "model returns rendered text" trap `L10n.swift`'s own header comment warns about), so it must
        // NOT be routed through `banner`, which `BrowserRootView` passes through `L10n.t` a second time. This
        // model's own banner literal covers both outcomes instead; the sync pairs page still shows the detailed
        // per-pair result from `FolderSyncController` itself.
        banner = ok ? "Đồng bộ xong" : "Đồng bộ không thành công — xem chi tiết ở trang Đồng bộ"
        return ok
    }

    /// One-line notice (an L10n key — the Vietnamese sentence itself), auto-hidden by the view.
    func showBanner(_ key: String) { banner = key }

    // MARK: - Pro gates (XF-T29)

    /// `.splitRight/.splitLeft/.splitDown/.splitUp` at the Free pane limit: an existing larger layout (reached
    /// during a trial, or inherited from a Workspace) stays fully usable — this only blocks making it bigger.
    var canSplitUnderLicense: Bool {
        guard let limit = LicenseManager.shared.limit(.browserPanes) else { return tree.canSplit }
        return tree.canSplit && tree.count < limit
    }

    private func splitGated(_ direction: SplitDirection) {
        guard canSplitUnderLicense else {
            banner = "Bản Free chỉ chia được 2 ngăn — cần XFinder Pro để chia thêm"
            return
        }
        split(direction)
    }

    private func addSelectionToShelfGated() {
        guard LicenseManager.shared.allows(.browserShelf) else {
            banner = "Cần XFinder Pro để thêm vào Shelf"
            return
        }
        addSelectionToShelf()
    }

    /// Free: starting a copy/move while another file operation is already running shows a banner instead of
    /// queueing it — Pro (`.browserQueue`) queues normally, same as `FileOperationQueue` already does on its own.
    private func enqueueGated(_ kind: FileOperationKind, sources: [String], destination: String?) {
        if kind == .copy || kind == .move, !LicenseManager.shared.allows(.browserQueue), FileOperationQueue.shared.hasActiveWork {
            banner = "Bản Free chạy một thao tác chép một lúc — chờ việc đang chạy xong"
            return
        }
        _ = FileOperationQueue.shared.enqueue(kind, sources: sources, destination: destination)
    }

    /// `.downloadNow`/`.removeDownload` on more than one item need Pro (`.browserBatchCloud`); a single item is
    /// free either tier.
    private func batchCloudGated(_ selection: [DirectoryEntry]) -> Bool {
        guard selection.count > 1, !LicenseManager.shared.allows(.browserBatchCloud) else { return true }
        banner = "Cần XFinder Pro để tải về hoặc gỡ nhiều mục đám mây cùng lúc"
        return false
    }
}

/// Drift tracking for `activeSyncPair` (the stored property itself lives on the main class, declared next to
/// `lastCompressedArchive`/`bannerClearTask`).
extension BrowserWindowModel {
    /// The sync pair shown side by side in this window (nil when none, or after either pane navigated away).
    var activeSyncPair: FolderSyncController.Pair? { activeSyncPairStorage }

    /// Clears `activeSyncPair` the moment either the source or destination pane's folder changes — a manual
    /// navigation away from the pair means the sync bar no longer describes what's on screen (spec XF-T28 §C:
    /// "clear it when the person navigates either pane away"). One-shot per registration like
    /// `BrowserWindowController.observeTitle`: `withObservationTracking`'s `onChange` fires once, so this
    /// re-installs itself after every fire until the pair itself is cleared.
    private func observeSyncPaneDrift(sourceID: PaneID, destID: PaneID, pair: FolderSyncController.Pair) {
        guard let sourcePane = panes[sourceID], let destPane = panes[destID] else { return }
        withObservationTracking {
            _ = sourcePane.path
            _ = destPane.path
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.activeSyncPairStorage?.id == pair.id else { return }
                let stillMatches = self.panes[sourceID]?.path == pair.sourcePath && self.panes[destID]?.path == pair.destPath
                if stillMatches {
                    self.observeSyncPaneDrift(sourceID: sourceID, destID: destID, pair: pair)
                } else {
                    self.activeSyncPairStorage = nil
                }
            }
        }
    }
}

// MARK: - Workspace persistence (JSON at a fixed path, per the contract)

extension WorkspaceStore {
    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder/Browser/workspaces.json", isDirectory: false)
    }

    static func load() -> Data {
        (try? Data(contentsOf: fileURL)) ?? Data()
    }

    func persist() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? exportJSON().write(to: url, options: .atomic)
    }
}
