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
    /// XF-T30 W5b — per-path metadata `SearchCoordinator.search` returns alongside `results` that `DirectoryEntry`
    /// has no field for (its file, `DirectoryEntry.swift`, belongs to a different builder): which source(s) matched
    /// (tên / Spotlight / nội dung) and the content-index snippet, keyed by `DirectoryEntry.path`. Only ever
    /// populated for a `SearchCoordinator`-backed search (contract §"Một đường tìm"); empty for a plain Spotlight
    /// fallback run before this existed would simply show no source label, never a wrong one.
    var sources: [String: Set<SearchCoordinator.Source>] = [:]
    var snippets: [String: String] = [:]
}

@MainActor @Observable final class PaneState: Identifiable {
    /// The pane this tab lives in. XF-T30 W1: a PaneState is ONE TAB of a pane. `id` stays immutable (a `let` keeps the
    /// `Identifiable` conformance nonisolated under Swift 6): a tab moved to another pane becomes a NEW PaneState there
    /// carrying the same `tabID`, folder, history, view, sort, selection and groupBy (one reload).
    let id: PaneID
    /// The tab's own identity — kept across moves between panes.
    let tabID: TabID
    /// XF-T30: Group By for this tab (W2 implements the grouping; W1 only stores it and shows it in the Group menu).
    var groupBy: GroupBy = .none
    /// XF-T32 W3 — group by a custom property (its id); nil = use `groupBy`. Sections are built in `rebuildSections`.
    var propertyGroupID: UUID?
    var metadataGroupingRevision: Int = 0
    /// ⌃⌘0 Use Groups — independent of the chosen field.
    var useGroups = false
    /// Names to reselect after the first load (session restore, `TabSnapshot.selectedNames`). W1 builder (model).
    var restoreSelectionNames: [String]?
    /// XF-T30 W2 — this folder's remembered view options (nil = defaults), the Group By sections of `entries` (empty
    /// when not grouping), and Column view's whole column trail (Q-T30-7). Maintained by BrowserWindowModel+Views.swift.
    var folderPrefs: FolderViewPrefs?
    var sections: [EntrySection] = []
    var columnPath: [String] = []
    private(set) var path: String
    private(set) var history: PaneHistory
    var viewMode: BrowserViewMode
    var sort: SortOrder
    var showHidden: Bool
    var foldersFirst = false
    private(set) var entries: [DirectoryEntry] = []
    /// Bumped every time `entries` is re-derived — the cheap "did the listing change" check a view needs on every
    /// SwiftUI update (comparing 100 000 paths there would not be).
    private(set) var listingRevision: Int = 0
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
    /// Only for virtual locations (Recents, tags), which list through Spotlight. Real folders go through
    /// `subscription`.
    private var loadTask: Task<Void, Never>?
    /// XF-T32 W0 — the shared listing of a real folder (cache first, one read + one watcher per folder for every
    /// pane). Replaces the per-tab `DirectoryWatcher`; cancelled when the tab leaves the folder or closes.
    private var subscription: ListingSubscription?
    private var subscribedPath: String?
    /// The folder `rawEntries` was read from; nil before the first load and after a failure.
    private var loadedPath: String?
    /// XF-T30 W5b — the live `SearchCoordinator` run behind `search`, if any; cancelled whenever the tab navigates
    /// to a different folder, is closed, or the search itself ends/restarts (contract: "huỷ khi tab đổi thư mục/đóng").
    private var searchHandle: SearchCoordinator.Handle?
    /// The raw listing from the last successful load, before `visible`/`filter`/`sorted` — kept so a view-option
    /// change (sort, showHidden, foldersFirst, filterText) or a search ending can re-derive `entries` without a
    /// fresh disk read.
    private var rawEntries: [DirectoryEntry] = []

    init(id: PaneID, path: String, viewMode: BrowserViewMode, sort: SortOrder, showHidden: Bool, history: PaneHistory?,
         tabID: TabID = TabID()) {
        self.id = id
        self.tabID = tabID
        self.path = path
        self.history = history ?? PaneHistory(current: path)
        self.viewMode = viewMode
        self.sort = sort
        self.showHidden = showHidden
        startLoad(of: path)
    }

    // MARK: - Navigation

    /// Records history and loads `path`'s listing; cancels whatever load was already in flight.
    func navigate(to path: String) {
        guard path != self.path else { return }
        history.visit(path)
        self.path = path
        cancelSearch()   // XF-T30 W5b: a tab that leaves its folder drops any live search (contract "huỷ khi ... đổi thư mục")
        startLoad(of: path)
        BrowserWindowModel.noteRecentFolder(path)   // XF-T30 W3 (BrowserWindowModel+Go.swift)
        BrowserWindowModel.applyRememberedViewOptions(to: self)   // XF-T30 W2: per-folder view options
    }

    func goBack() {
        guard let destination = history.goBack() else { return }
        path = destination
        cancelSearch()
        startLoad(of: destination)
        BrowserWindowModel.applyRememberedViewOptions(to: self)
    }

    func goForward() {
        guard let destination = history.goForward() else { return }
        path = destination
        cancelSearch()
        startLoad(of: destination)
        BrowserWindowModel.applyRememberedViewOptions(to: self)
    }

    /// XF-T30 W1 — the toolbar's history menus (press-and-hold Back/Forward lists several entries; picking one
    /// jumps straight there). Nothing changes when `steps` overshoots the available entries.
    func goBack(steps: Int) {
        guard let destination = history.goBack(steps: steps) else { return }
        path = destination
        cancelSearch()
        startLoad(of: destination)
    }

    func goForward(steps: Int) {
        guard let destination = history.goForward(steps: steps) else { return }
        path = destination
        cancelSearch()
        startLoad(of: destination)
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

    /// The tab is going away (closed, its pane closed, moved and re-created, window closed): stop the watcher AND the
    /// load still in flight (review 2026-10-25: only the watcher stopped; a slow folder kept reading up to 5 s).
    /// XF-T30 W5b: also cancels a live search (contract "huỷ khi ... đóng").
    func stopWatching() {
        dropSubscription()
        loadTask?.cancel()
        loadTask = nil
        cancelSearch()
    }

    /// Cancels the `SearchCoordinator` run behind `search`, if any — idempotent, safe to call whether or not a
    /// search is in flight.
    private func cancelSearch() {
        searchHandle?.cancel()
        searchHandle = nil
    }

    var selectedEntries: [DirectoryEntry] {
        entries.filter { selection.contains($0.path) }
    }

    // MARK: - Loading

    private func startLoad(of path: String) {
        loadTask?.cancel()
        loadTask = nil
        currentGeneration += 1
        let generation: Int = currentGeneration
        // A refresh of the folder already on screen (watcher, ⌘R, a finished operation) keeps showing it until the
        // new listing lands. `.loading` swaps the whole view for a spinner and rebuilds the table: scroll, expanded
        // folders, an inline rename and the click in flight were lost — 2 refreshes a minute in a home folder
        // (measured 2026-10-26), both panes in Side by Side.
        if !LoadRules.isRefresh(of: path, loadedPath: loadedPath, isLoaded: loadState == .loaded) {
            loadState = .loading
        }
        // XF-T30 W3: a virtual location (Recents, a tag) lists through Spotlight, not the directory reader.
        if let virtual: VirtualLocation = VirtualLocation.parse(path) {
            dropSubscription()
            loadTask = Task { [weak self] in
                let result: Result<[DirectoryEntry], DirectoryReadError> = await VirtualLocations.list(virtual)
                guard let self, !Task.isCancelled, generation == self.currentGeneration else { return }
                self.applyListing(result, path: path, settled: true)
            }
            return
        }
        // Same folder, live subscription ⇒ ask the shared session to read again (coalesced with other panes).
        if subscribedPath == path, subscription != nil {
            DirectoryLoadCoordinator.shared.reload(path: path)
            return
        }
        dropSubscription()
        subscribedPath = path
        subscription = DirectoryLoadCoordinator.shared.subscribe(
            path: path,
            onListing: { [weak self] result in
                guard let self, self.subscribedPath == path else { return }
                switch result {
                case .success(let delivery):
                    // A cached copy can lack a just-created name; only a disk read settles "not there".
                    self.applyListing(.success(delivery.entries), path: path, settled: delivery.source == .disk)
                case .failure(let error):
                    self.applyListing(.failure(error), path: path, settled: true)
                }
            },
            onGone: { [weak self] in
                guard let self, self.subscribedPath == path, self.path == path else { return }
                self.dropSubscription()
                self.navigateToNearestExistingAncestor(from: path)
            })
    }

    private func dropSubscription() {
        subscription?.cancel()
        subscription = nil
        subscribedPath = nil
    }

    /// One listing (cache copy, disk read or virtual list) lands. `settled` = nothing newer is on its way, so a
    /// pending reselection that found no match is given up.
    private func applyListing(_ result: Result<[DirectoryEntry], DirectoryReadError>, path: String, settled: Bool) {
        switch result {
        case .success(let listing):
            rawEntries = listing
            loadedPath = path
            loadState = .loaded
            applyEntries()
            BrowserMetadata.shared.load(folder: path)   // XF-T32 W3: pins, nicknames, chips for this folder
            var reselected: Bool = false
            if let wanted: String = selectAfterLoad, listing.contains(where: { $0.name == wanted }) {
                // `appendingPathComponent`, not string concatenation — `path` can be "/" (a volume root),
                // where "\(path)/\(wanted)" doubles the slash and never matches any entry's `path`.
                selection = [(path as NSString).appendingPathComponent(wanted)]
                reselected = true
            } else if let names: [String] = restoreSelectionNames {
                // XF-T30 W1 — session restore (`TabSnapshot.selectedNames`): reselect only the names that still
                // exist after the first load; applied once (cleared right after), same as `selectAfterLoad`.
                let present: Set<String> = Set(listing.map(\.name))
                let kept: [String] = names.filter { present.contains($0) }
                if !kept.isEmpty {
                    selection = Set(kept.map { (path as NSString).appendingPathComponent($0) })
                    reselected = true
                }
            }
            if reselected || settled {
                selectAfterLoad = nil
                restoreSelectionNames = nil
            }
        case .failure(let error):
            rawEntries = []
            entries = []
            listingRevision &+= 1
            loadedPath = nil
            loadState = .failed(error)
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
        listingRevision &+= 1
        rebuildSections()   // XF-T30 W2 (BrowserWindowModel+Views.swift)
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
        startSearch(text: text, parsed: parsed, scope: scope, paneFolders: paneFolders)
    }

    /// Runs a search straight from an already-`ParsedSearch` (edited chips): same pipeline as
    /// `runSearch(_:scope:paneFolders:)` but skips `SearchQuery.parse` — a chip edit (remove/replace) only ever
    /// changes `ParsedSearch`, and rebuilding it back into text first would drop chips that cannot round-trip
    /// through text (pastDays / olderThan / month — spec XF-T28 Wave 4 §E), which is exactly the bug this exists to
    /// fix. `text` on the resulting `PaneSearchState` is kept as whatever free terms/phrases remain so the search
    /// bar's text field still shows something sensible; a chips-only edit (no terms left) shows an empty field,
    /// same as starting a fresh search would.
    func runSearch(parsed: ParsedSearch, scope: PaneSearchState.Scope, paneFolders: [String] = []) {
        let text = (parsed.terms + parsed.phrases.map { "\"\($0)\"" }).joined(separator: " ")
        startSearch(text: text, parsed: parsed, scope: scope, paneFolders: paneFolders)
    }

    /// Shared tail of both `runSearch` overloads (text and chip-edited): resolves the scope's folders, then hands
    /// off to `SearchCoordinator.shared.search` (contract "Một đường tìm" — filename index + Spotlight + content
    /// index merged, streamed back live via `onUpdate`) instead of calling `FileSearchEngine.runMdfind` directly.
    /// No `now`/`calendar` parameters here: `SearchCoordinator.search` takes its own `Date()`/`Calendar.current`
    /// snapshot internally for chip date-range resolution (review 2026-10-25: an earlier version of this comment
    /// claimed this function forwarded a shared snapshot to the coordinator for that purpose — it never did; the
    /// parameters were dead and have been removed instead of leaving a false invariant documented here. `parsed`'s
    /// chips are already resolved to a `ParsedSearch` by `SearchQuery.parse`/the chip editor before reaching this
    /// function, so this one caller's clock does not actually need to agree with the coordinator's for correctness).
    private func startSearch(text: String, parsed: ParsedSearch, scope: PaneSearchState.Scope, paneFolders: [String]) {
        cancelSearch()   // a re-run (new text, scope change, chip edit) replaces whatever search was already live.
        search = PaneSearchState(text: text, parsed: parsed, scope: scope, results: [], running: true, truncated: false)
        let generation = currentGeneration
        let scopes = searchScopes(for: scope, paneFolders: paneFolders)
        searchHandle = SearchCoordinator.shared.search(
            parsed, folders: scopes, limit: 500,
            onUpdate: { [weak self] results in
                guard let self, generation == self.currentGeneration, self.search != nil else { return }
                self.applySearchResults(results)
            },
            onFinish: { [weak self] truncated in
                guard let self, generation == self.currentGeneration, self.search != nil else { return }
                self.search?.running = false
                self.search?.truncated = truncated
            }
        )
    }

    /// Converts `SearchCoordinator.Result`s (path + sources + tier + snippet) into `DirectoryEntry`s via `lstat`,
    /// off the main actor (same reasoning as the old direct-`mdfind` path: a network-mounted hit can stall a stat
    /// call, and up to 500 of them must not block the UI). A path that no longer exists by the time this runs
    /// (deleted between index/Spotlight returning it and the stat here) is silently dropped, same as before.
    private func applySearchResults(_ results: [SearchCoordinator.Result]) {
        let generation = currentGeneration
        Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) { () -> [(DirectoryEntry, Set<SearchCoordinator.Source>, String?)] in
                results.compactMap { result in
                    guard let entry = PaneState.entry(forPath: result.path) else { return nil }
                    return (entry, result.sources, result.snippet)
                }
            }.value
            guard let self, generation == self.currentGeneration, self.search != nil else { return }
            self.search?.results = built.map(\.0)
            self.search?.sources = Dictionary(uniqueKeysWithValues: built.map { ($0.0.path, $0.1) })
            self.search?.snippets = Dictionary(uniqueKeysWithValues: built.compactMap { entry, _, snippet in
                snippet.map { (entry.path, $0) }
            })
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

    /// Public wrapper of `searchScopes(for:paneFolders:)` as plain path strings — the search bar uses this to ask
    /// `BrowserWindowModel.scopeIsIndexing` about the CURRENT search's scope, without duplicating the folder-resolution
    /// rule above.
    func searchScopeFolderPaths(for scope: PaneSearchState.Scope, paneFolders: [String]) -> [String] {
        searchScopes(for: scope, paneFolders: paneFolders).map(\.path)
    }

    func endSearch() {
        cancelSearch()
        search = nil
        applyEntries()
    }

    // MARK: - Saved search (XF-T30 W5b)

    /// "Lưu tìm kiếm…" on the search bar: persists the query text + scope (+ folder, for `.folder`) into
    /// `BrowserSettings.savedSearches` — contract: "lưu câu tìm + phạm vi, không lưu kết quả", so this deliberately
    /// ignores `search.results`. Does nothing without a live search (nothing to save).
    @discardableResult
    func saveCurrentSearch(name: String, addToSidebar: Bool) -> SavedSearch? {
        guard let search else { return nil }
        var store = BrowserSettings.savedSearches
        let folder = search.scope == .folder ? path : nil
        let saved = store.add(name: name, query: search.text, scope: search.scope.rawValue, folder: folder,
                              showInSidebar: addToSidebar, now: Date())
        BrowserSettings.savedSearches = store
        return saved
    }

    /// Go ▸ Tìm kiếm đã lưu / a sidebar row: re-runs a saved query against its saved scope — contract: "mở = chạy
    /// lại câu tìm (ngày tương đối tính lại)", automatic here since `runSearch` always resolves relative dates
    /// (`today`/`last week`/…) against `Date()` at the moment it runs, never a date baked in when the search was
    /// first saved.
    func runSavedSearch(_ saved: SavedSearch, paneFolders: [String] = []) {
        let scope = PaneSearchState.Scope(rawValue: saved.scope) ?? .mac
        if scope == .folder, let folder = saved.folder, folder != path {
            navigate(to: folder)
        }
        runSearch(saved.query, scope: scope, paneFolders: paneFolders)
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

/// XF-T30 W1 — what the window chrome (toolbar, window controller) does for the model. Implemented by
/// `BrowserToolbarController`; the model holds it weakly.
@MainActor protocol BrowserChrome: AnyObject {
    func focusSearchField()
    func toggleToolbarShown()
    func runToolbarCustomization()
}

/// XF-T30 W1 — sheets any surface (toolbar item, menu, palette) can ask the root view to present.
enum BrowserSheet: String, Identifiable {
    case saveWorkspace, openWorkspace, manageWorkspaces
    var id: String { rawValue }
}

@MainActor @Observable final class BrowserWindowModel {
    enum PaletteMode: Equatable { case quickOpen, commands }

    /// XF-T30 W1: the chrome that owns the toolbar of this model's window.
    weak var chrome: BrowserChrome?
    /// XF-T30 W1: the sheet to present (BrowserRootView binds to it).
    var sheet: BrowserSheet?
    /// XF-T30 W1: "Lọc thư mục hiện tại" (no chord since ⌘F became Find, Q-T30-2) asks this pane's filter field to show
    /// and take focus; the search bar clears it once focused.
    var filterFocusRequest: PaneID?
    /// XF-T38: File ▸ Save Search… asks this pane's search bar to show its Save Search popover (cleared by the bar).
    var saveSearchRequest: PaneID?

    var tree: PaneTree
    /// XF-T30 W1 (contract §1/§3) — the tabs of every pane, and every tab's own state. A `PaneState` is one TAB: its
    /// `id` (the pane it currently lives in) changes when the tab moves to another pane, its `tabID` never does.
    /// `panes` below stays the read surface every pre-W1 call site already uses (the SELECTED tab of each pane).
    private(set) var tabLists: [PaneID: PaneTabList] = [:]
    private(set) var tabStates: [TabID: PaneState] = [:]
    var activePane: PaneID
    /// Each pane's frame in its window's content view (top-left origin), reported by `PaneView`. Read by
    /// `BrowserWindow.sendEvent` to activate the pane under a click that lands outside a file view (path bar,
    /// status bar, empty area). Not observed: a geometry write must never re-render the panes.
    @ObservationIgnored var paneFramesInWindow: [PaneID: CGRect] = [:]
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
            for paneSnapshot in snapshot.panes {
                installPane(paneSnapshot.id, tabs: paneSnapshot.allTabs, selectedIndex: paneSnapshot.selectedTabIndex)
            }
            // A tree/pane-list mismatch (hand-edited session file) must not leave a leaf without tabs.
            for id in snapshot.tree.panes where tabLists[id] == nil {
                installPane(id, tabs: [defaultTabSnapshot(home: home)], selectedIndex: 0)
            }
            self.shelfVisible = snapshot.shelfVisible
            if !snapshot.tree.panes.contains(activePane), let first = snapshot.tree.panes.first {
                self.activePane = first
            }
        } else {
            let tree = PaneTree()
            let first = tree.panes[0]
            self.tree = tree
            self.activePane = first
            installPane(first, tabs: [defaultTabSnapshot(home: home, path: initialPath ?? home)], selectedIndex: 0)
        }
    }

    /// A single fresh tab using the browser's own defaults (new pane, or repairing a hand-edited/damaged session).
    private func defaultTabSnapshot(home: String, path: String? = nil) -> TabSnapshot {
        TabSnapshot(path: path ?? home, viewMode: BrowserSettings.defaultView, sort: .finderDefault,
                   history: PaneHistory(current: path ?? home), showHidden: BrowserSettings.showHidden)
    }

    /// Builds `pane`'s `PaneTabList` from `tabs` (never empty — a `TabSnapshot.selectionLimit`-worth caller already
    /// guarantees at least one) and installs a `PaneState` for each into `tabStates`. `selectedIndex` is clamped.
    private func installPane(_ pane: PaneID, tabs: [TabSnapshot], selectedIndex: Int) {
        let snapshots = tabs.isEmpty ? [defaultTabSnapshot(home: FileManager.default.homeDirectoryForCurrentUser.path)] : tabs
        var ids: [TabID] = []
        for snap in snapshots {
            let tabID = TabID()
            ids.append(tabID)
            let state = PaneState(id: pane, path: snap.path, viewMode: snap.viewMode, sort: snap.sort,
                                  showHidden: snap.showHidden, history: snap.history, tabID: tabID)
            state.groupBy = snap.groupBy ?? .none
            state.restoreSelectionNames = snap.selectedNames
            state.columnPath = snap.columnPath ?? []   // Q-T30-7: Column view reopens its whole trail
            tabStates[tabID] = state
        }
        let clampedIndex = max(0, min(selectedIndex, ids.count - 1))
        var list = PaneTabList(first: ids[0])
        for id in ids.dropFirst() { list.insert(id, at: list.count, select: false) }
        _ = list.select(ids[clampedIndex])
        tabLists[pane] = list
    }

    /// The selected tab of every pane (XF-T30 W1: pre-W1 call sites all read this; `tabs(of:)` reaches every tab).
    /// Read-only — every write goes through the tab helpers in the XF-T30 W1 extension below, which keep `tabLists`
    /// and `tabStates` (the actual storage) consistent with each other and with `tree`.
    var panes: [PaneID: PaneState] {
        var result: [PaneID: PaneState] = [:]
        for (pane, list) in tabLists {
            if let state = tabStates[list.selectedTab] { result[pane] = state }
        }
        return result
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
            filterFocusRequest = activePane   // no chord since Q-T30-2; the search bar shows the filter field and focuses it
        case .find:
            // XF-T30 W1 contract §3: `find` goes through `chrome` when the toolbar's search field exists (just
            // focuses it, like Finder — the field itself starts the search on Return); no chrome ⇒ old behavior.
            if let chrome {
                chrome.focusSearchField()
            } else if active.search == nil {
                runSearch("", scope: BrowserWindowModel.resolvedDefaultSearchScope())
            }
        case .editLocation:
            editingLocation = activePane
        case .goToFolder:
            editingLocation = activePane
        case .quickOpen:
            if palette != nil { palette = palette == .commands ? .quickOpen : .commands }
            else { palette = .quickOpen }
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
                let closed = activePane
                activePane = next
                destroyPane(closed)
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
            downloadSelectionNowCloudAware()   // XF-T30 W8 hook: BrowserWindowModel+Cloud.swift
        case .removeDownload:
            guard batchCloudGated(active.selectedEntries) else { return true }
            removeDownloadForSelectionCloudAware()   // XF-T30 W8 hook: BrowserWindowModel+Cloud.swift
        case .showInFinder:
            let urls = active.selectedEntries.map { URL(fileURLWithPath: $0.path) }
            guard !urls.isEmpty else { return false }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .closeWindow:
            // XF-T38 (found testing the menus in the Atlas helper): this used to `break` and still report success, so
            // ⌘W was eaten by the window's key handler and File ▸ Close / the palette did nothing — the window stayed.
            BrowserWindowController.shared.closeWindow(of: self)
        case .getInfo:
            let paths = getInfoTargetPaths()
            guard !paths.isEmpty else { return false }
            GetInfoWindowController.shared.show(paths: paths, readOnly: active.search != nil)
        case .newWindowTab:
            BrowserWindowController.shared.openWindowTab(besideWindowOf: self)
        case .newPaneTab:
            _ = newTab(in: activePane, path: nil)
        case .nextPaneTab:
            selectAdjacentTab(in: activePane, forward: true)
        case .previousPaneTab:
            selectAdjacentTab(in: activePane, forward: false)
        case .closePaneTab:
            closeTab(active.tabID)
        case .moveTabToNextPane:
            guard let other = tree.other(than: activePane) else { return false }
            moveTab(active.tabID, toPane: other, at: nil)
        case .moveTabToNewPaneRight:
            _ = moveTabToNewPane(active.tabID, beside: activePane, .right)
        case .moveTabToNewPaneBelow:
            _ = moveTabToNewPane(active.tabID, beside: activePane, .down)
        case .swapWithNextPane:
            guard let other = tree.other(than: activePane) else { return false }
            swapPaneContents(activePane, other)
        case .moveTabToWindow:
            moveTabToWindow(active.tabID)
        case .paneLeft, .paneRight, .paneAbove, .paneBelow:
            guard let direction = Self.paneDirection(for: command), let target = neighborPane(toward: direction) else { return false }
            activePane = target
        case .makePaneWider:
            tree.resize(activePane, axis: .horizontal, grow: true)
        case .makePaneNarrower:
            tree.resize(activePane, axis: .horizontal, grow: false)
        case .makePaneTaller:
            tree.resize(activePane, axis: .vertical, grow: true)
        case .makePaneShorter:
            tree.resize(activePane, axis: .vertical, grow: false)
        case .toggleLocationBar:
            setBrowserDefault(!BrowserSettings.showLocationBar, key: "fileBrowser.showLocationBar")
        case .togglePathBar:
            setBrowserDefault(!BrowserSettings.showPathBar, key: "fileBrowser.showPathBar")
        case .toggleStatusBar:
            setBrowserDefault(!BrowserSettings.showStatusBar, key: "fileBrowser.showStatusBar")
        case .toggleToolbar:
            chrome?.toggleToolbarShown()
        case .customizeToolbar:
            chrome?.runToolbarCustomization()
        case .toggleSidebar:
            setBrowserDefault(!BrowserSettings.showSidebar, key: "fileBrowser.showSidebar")
        case .openInNewTab:
            openSelectionInNewTabs()
        case .openInNewWindow:
            openSelectionInNewWindows()
        case .useGroups:
            active.useGroups.toggle()
        // XF-T30 W2–W7: each wave owns its own extension file (contracts XF-T30-w2/w3/w4/w6/w78).
        case .makeAlias, .showOriginal, .addToSidebar, .share, .showViewOptions:
            return performViewsCommand(command)
        case .goRecents, .goDocuments, .goDesktop, .goDownloads, .goHome, .goAirDrop, .goNetwork, .goICloud,
             .goApplications, .goUtilities, .goComputer, .connectToServer, .eject, .clearRecentFolders:
            return performGoCommand(command)
        case .openBrowserSettings, .showWelcome:
            return performSettingsCommand(command)
        case .newFolderWithSelection, .cut, .redo, .clearOperationHistory:
            return performFileOpsCommand(command)
        case .togglePreview, .slideshow:
            return performPreviewCommand(command)
        case .refresh:
            active.reload()
            return true
        case .saveSearch:
            // The pane's own search bar shows its Save Search popover (same UI as its bookmark button).
            guard active.search != nil else { return false }
            saveSearchRequest = activePane
            return true
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
        if VirtualLocation.parse(active.path) == .learn {
            switch command {
            case .newFolder, .paste, .pasteMove, .newFolderWithSelection, .getInfo, .filter, .find,
                 .viewIcons, .viewList, .viewColumns, .viewGallery, .showViewOptions, .togglePreview,
                 .useGroups, .toggleHidden, .selectAll, .openEnclosing:
                return false
            default: break
            }
        }
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
            // FileOctopus R30: greyed when the other pane shows a virtual location (Recents, a tag) or is searching.
            guard tree.count >= 2, !active.selectedEntries.isEmpty, let other: PaneID = tree.other(than: activePane),
                  let target: PaneState = panes[other] else { return false }
            return VirtualLocation.parse(target.path) == nil && target.search == nil
        case .addToShelf:
            return !active.selectedEntries.isEmpty
        case .compress:
            return !active.selectedEntries.isEmpty
        case .batchRename:
            return !active.entries.isEmpty
        case .downloadNow:
            return canDownloadNowCloudAware   // XF-T30 W8 hook: BrowserWindowModel+Cloud.swift
        case .removeDownload:
            return canRemoveDownloadCloudAware   // XF-T30 W8 hook: BrowserWindowModel+Cloud.swift
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
        case .newWindowTab, .newPaneTab, .nextPaneTab, .previousPaneTab, .toggleLocationBar, .togglePathBar,
             .toggleStatusBar, .toggleSidebar, .useGroups:
            return true
        case .closePaneTab:
            // Q-T30-4: the last tab of the last pane stays (nothing to close down to).
            return (tabLists[activePane]?.count ?? 1) > 1 || tree.count > 1
        case .moveTabToNewPaneRight, .moveTabToNewPaneBelow:
            // Contract §3: the source pane needs at least 2 tabs (moving the only tab would leave an empty pane to
            // split from); the split itself is also Pro-gated like any other split.
            return (tabLists[activePane]?.count ?? 1) >= 2 && canSplitUnderLicense
        case .moveTabToNextPane, .swapWithNextPane:
            return tree.count >= 2 && tree.other(than: activePane) != nil
        case .moveTabToWindow:
            // Gray when it is the only tab of the only pane — nothing would be left behind.
            return tree.count > 1 || (tabLists[activePane]?.count ?? 1) > 1
        case .paneLeft, .paneRight, .paneAbove, .paneBelow:
            guard let direction = Self.paneDirection(for: command) else { return false }
            return neighborPane(toward: direction) != nil
        case .makePaneWider, .makePaneNarrower, .makePaneTaller, .makePaneShorter:
            return true
        case .toggleToolbar, .customizeToolbar:
            return chrome != nil
        case .openInNewTab, .openInNewWindow:
            return !active.selectedEntries.isEmpty
        case .makeAlias, .showOriginal, .addToSidebar, .share, .showViewOptions:
            return canPerformViewsCommand(command)
        case .goRecents, .goDocuments, .goDesktop, .goDownloads, .goHome, .goAirDrop, .goNetwork, .goICloud,
             .goApplications, .goUtilities, .goComputer, .connectToServer, .eject, .clearRecentFolders:
            return canPerformGoCommand(command)
        case .openBrowserSettings, .showWelcome:
            return canPerformSettingsCommand(command)
        case .newFolderWithSelection, .cut, .redo, .clearOperationHistory:
            return canPerformFileOpsCommand(command)
        case .togglePreview, .slideshow:
            return canPerformPreviewCommand(command)
        case .refresh:
            return active.search == nil
        case .saveSearch:
            return active.search != nil
        }
    }

    private static func paneDirection(for command: BrowserCommand) -> SplitDirection? {
        switch command {
        case .paneLeft: return .left
        case .paneRight: return .right
        case .paneAbove: return .up
        case .paneBelow: return .down
        default: return nil
        }
    }

    /// `.pane{Left,Right,Above,Below}`'s target, via `tree.neighbor` over a fixed 1000×1000 rect (contract §3 — the
    /// toolbar/menu only needs to know "is there one", not the window's actual on-screen geometry).
    private func neighborPane(toward direction: SplitDirection) -> PaneID? {
        tree.neighbor(of: activePane, toward: direction, in: Self.neighborProbeRect, divider: 1)
    }

    private static let neighborProbeRect = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    // MARK: - Pane tree helpers

    private func split(_ direction: SplitDirection) {
        guard let newID = tree.split(activePane, direction) else { return }
        let template = active
        createPane(newID, path: template.path, viewMode: template.viewMode, sort: template.sort,
                  showHidden: template.showHidden)
        activePane = newID
    }

    private func applyPreset(_ preset: PanePreset) {
        let template = active
        let (kept, removed) = tree.apply(preset)
        for id in removed {
            destroyPane(id)
        }
        for id in kept where tabLists[id] == nil {
            createPane(id, path: template.path, viewMode: BrowserSettings.defaultView,
                      sort: .finderDefault, showHidden: BrowserSettings.showHidden)
        }
        if !kept.contains(activePane), let first = kept.first {
            activePane = first
        }
    }

    /// A brand-new pane with ONE tab (contract §3: "ngăn mới = một tab copy thư mục + kiểu xem của tab đang chọn").
    private func createPane(_ pane: PaneID, path: String, viewMode: BrowserViewMode, sort: SortOrder, showHidden: Bool) {
        let tabID = TabID()
        let state = PaneState(id: pane, path: path, viewMode: viewMode, sort: sort, showHidden: showHidden,
                              history: nil, tabID: tabID)
        tabStates[tabID] = state
        tabLists[pane] = PaneTabList(first: tabID)
    }

    /// Stops every tab's watcher before dropping the pane — a removed pane must not leak a `DirectoryWatcher` for
    /// any tab it held, not just the one that happened to be selected (contract §3, ca hỏng §7).
    private func destroyPane(_ pane: PaneID) {
        guard let list = tabLists.removeValue(forKey: pane) else { return }
        for tabID in list.tabs {
            tabStates.removeValue(forKey: tabID)?.stopWatching()
        }
    }

    // MARK: - Pane tabs (XF-T30 W1 §3) — `.newPaneTab`/`.nextPaneTab`/etc. and the command helpers above

    private func selectAdjacentTab(in pane: PaneID, forward: Bool) {
        guard var list = tabLists[pane] else { return }
        if forward { list.selectNext() } else { list.selectPrevious() }
        tabLists[pane] = list
    }

    /// `.swapWithNextPane` (Q-T30-6): the two panes trade their WHOLE tab stacks (every tab + its history), their
    /// position in the tree stays put. `PaneState.id` is immutable (contract §1/the doc comment on `PaneState.id`):
    /// every tab that crosses to the other pane becomes a new `PaneState` there, carrying its `tabID`/folder/
    /// history/view/sort/selection/groupBy across — same as `moveTab`'s own rebuild.
    private func swapPaneContents(_ a: PaneID, _ b: PaneID) {
        guard let listA = tabLists[a], let listB = tabLists[b] else { return }
        var newListA = PaneTabList(first: listB.tabs[0])
        for tabID in listB.tabs { rehome(tabID, into: a) }
        for tabID in listB.tabs.dropFirst() { newListA.insert(tabID, at: newListA.count, select: false) }
        if let selected = listB.tabs.firstIndex(of: listB.selectedTab) { _ = newListA.select(listB.tabs[selected]) }

        var newListB = PaneTabList(first: listA.tabs[0])
        for tabID in listA.tabs { rehome(tabID, into: b) }
        for tabID in listA.tabs.dropFirst() { newListB.insert(tabID, at: newListB.count, select: false) }
        if let selected = listA.tabs.firstIndex(of: listA.selectedTab) { _ = newListB.select(listA.tabs[selected]) }

        tabLists[a] = newListA
        tabLists[b] = newListB
    }

    /// Replaces the `PaneState` for `tabID` with a clone that lives in `pane` instead, carrying over its folder,
    /// history, view, sort, selection, filter, groupBy and search — the one place `moveTab`/`moveTabToNewPane`/
    /// `swapPaneContents` all go through, since `PaneState.id` cannot be mutated in place.
    @discardableResult
    private func rehome(_ tabID: TabID, into pane: PaneID) -> PaneState? {
        guard let old = tabStates[tabID] else { return nil }
        old.stopWatching()
        let moved = PaneState(id: pane, path: old.path, viewMode: old.viewMode, sort: old.sort,
                              showHidden: old.showHidden, history: old.history, tabID: tabID)
        moved.groupBy = old.groupBy
        moved.useGroups = old.useGroups
        moved.foldersFirst = old.foldersFirst
        moved.selection = old.selection
        moved.filterText = old.filterText
        moved.search = old.search
        tabStates[tabID] = moved
        return moved
    }

    private func setBrowserDefault(_ value: Bool, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// `.openInNewTab`: every selected folder becomes a new tab in the active pane, the last one selected
    /// (contract §3). A selected file (not a folder) is skipped — there is nowhere for it to open as a tab.
    private func openSelectionInNewTabs() {
        let folders = active.selectedEntries.filter(\.isFolderLike).map(\.path)
        guard !folders.isEmpty else { return }
        for folder in folders {
            _ = newTab(in: activePane, path: folder)
        }
    }

    /// `.openInNewWindow`: every selected folder opens as its own new window.
    private func openSelectionInNewWindows() {
        let folders = active.selectedEntries.filter(\.isFolderLike).map(\.path)
        guard !folders.isEmpty else { return }
        for folder in folders {
            BrowserWindowController.shared.openWindow(path: folder)
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
        guard confirmTrashIfGoogleDrive(paths: paths) else { return }   // XF-T30 W8 hook
        _ = FileOperationQueue.shared.enqueue(.trash, sources: paths, destination: nil)
    }

    /// `commitRename` is the only path that actually renames a file in a pane (⌘⇧N also routes through it after the
    /// new folder is created and `renaming` is set). The name rule and the rename itself are `BatchRenameRules.renameOne`
    /// (XF-T37 L1): a case-only change ("report.txt" → "Report.txt") is a real rename, not "another item has this name".
    func commitRename(_ path: String, to newName: String) -> Bool {
        switch BatchRenameRules.renameOne(path, to: newName) {
        case .unchanged:
            renaming = nil
            return true
        case .rejected(let key):
            banner = key   // `BrowserRootView.bannerView` wraps the key in `L10n.t`
            return false
        case .renamed(let destination):
            ActionHistoryStore.shared.recordRenames(pairs: [(old: URL(fileURLWithPath: path), new: URL(fileURLWithPath: destination))])
            FileOperationQueue.shared.recordRename(from: path, to: destination)   // ⌘Z in the browser undoes it
            renaming = nil
            active.selection = [destination]
            active.reload()
            return true
        }
    }

    // MARK: - Pasteboard

    private func copySelectionToPasteboard() {
        let urls = active.selectedEntries.map { URL(fileURLWithPath: $0.path) as NSURL }
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls)
        cancelPendingCut()   // a fresh ⌘C cancels a pending ⌘X (CutBoard rule)
    }

    private func copySelectionPaths() {
        let paths = active.selectedEntries.map(\.path).joined(separator: "\n")
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
    }

    private func pasteFromPasteboard(move: Bool) {
        if pasteCutItems() { return }   // XF-T30 W6: a pending ⌘X cut moves instead (BrowserWindowModel+FileOps.swift)
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
        guard !blockCrossBoundaryCloudDrop(paths: paths, destination: folder) else { return }   // XF-T30 W8 hook
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
        BrowserWindowModel.lastUsedScope = scope   // XF-T30 W5b: fileBrowser.search.defaultScope == "previous"
    }

    /// Chip-edit counterpart of `runSearch(_:scope:)` (same `.panes` folder resolution + "previous scope" memory),
    /// used when a chip popover replaces/removes a chip on an already-running search.
    func runSearch(parsed: ParsedSearch, scope: PaneSearchState.Scope) {
        let folders = scope == .panes ? tree.panes.compactMap { panes[$0]?.path } : []
        active.runSearch(parsed: parsed, scope: scope, paneFolders: folders)
        BrowserWindowModel.lastUsedScope = scope
    }

    /// `fileBrowser.search.defaultScope` resolved to an actual `PaneSearchState.Scope`: `mac`/`folder` map directly,
    /// `previous` reads the in-session memory of whatever scope the last search anywhere in the app used (contract
    /// "nhớ trong phiên" — process lifetime, not persisted to disk), falling back to `.mac` the very first time a
    /// search starts in this launch (nothing to remember yet, same default the setting itself ships with).
    static func resolvedDefaultSearchScope() -> PaneSearchState.Scope {
        switch BrowserSettings.defaultSearchScope {
        case "folder": return .folder
        case "previous": return lastUsedScope ?? .mac
        default: return .mac
        }
    }

    /// In-process memory for `defaultSearchScope == "previous"` — deliberately `static` (not per-window/per-pane):
    /// FileOctopus's own "Use the Previous Search Scope" means the last scope searched ANYWHERE, not per-window.
    private static var lastUsedScope: PaneSearchState.Scope?

    /// Whether any approved index root inside `folders` (empty = every root, "This Mac") is still building or
    /// catching up — contract: "'Đang cập nhật chỉ mục…' ở thanh tìm khi một gốc trong phạm vi đang indexing/updating".
    /// Reads both `FilenameIndex` and `ContentIndex` status (either indexing a root makes the combined answer for
    /// that root "still settling", since a content-index root is always also a filename-index root).
    static func scopeIsIndexing(folders: [String]) async -> Bool {
        let roots = BrowserSettings.indexRoots.filter { !$0.paused }
        let folderPaths = folders.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        // Same "root is inside/under a scope folder" test `SearchCoordinator.rootsInScope` applies (that one is
        // `fileprivate` to its own file) — empty `folders` ("This Mac") matches every approved root.
        let scoped: [IndexRoot] = folderPaths.isEmpty ? roots : roots.filter { root in
            folderPaths.contains { folder in
                root.path == folder || folder.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
                    || root.path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
            }
        }
        guard !scoped.isEmpty else { return false }
        let ids = Set(scoped.map(\.id))
        async let nameStatus = FilenameIndex.shared.status()
        async let contentStatus = ContentIndex.shared.status()
        let (names, contents) = await (nameStatus, contentStatus)
        func isSettling(_ status: IndexRootStatus?) -> Bool {
            switch status {
            case .indexing, .updating: return true
            default: return false
            }
        }
        return ids.contains { isSettling(names[$0]) || isSettling(contents[$0]) }
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

    // XF-T30 W8: downloadSelectionNowCloudAware()/removeDownloadForSelectionCloudAware() in
    // BrowserWindowModel+Cloud.swift replace the two private helpers that used to live here (they skipped
    // non-eligible items with no `CloudRules` check at all — e.g. Remove Download could evict a file mid-upload).

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

    /// Writes v2 (contract §3: every tab, `selectedNames` capped at `TabSnapshot.selectionLimit`, `groupBy`).
    func snapshot(frame: CGRect?) -> WindowSnapshot {
        let paneSnapshots = tree.panes.compactMap { id -> PaneSnapshot? in
            guard let list = tabLists[id] else { return nil }
            let tabs = list.tabs.compactMap { tabID -> TabSnapshot? in
                guard let state = tabStates[tabID] else { return nil }
                let names = Array(state.selection.map { ($0 as NSString).lastPathComponent }.prefix(TabSnapshot.selectionLimit))
                return TabSnapshot(path: state.path, viewMode: state.viewMode, sort: state.sort, history: state.history,
                                   showHidden: state.showHidden, selectedNames: names.isEmpty ? nil : names,
                                   groupBy: state.groupBy, columnPath: state.columnPath.isEmpty ? nil : state.columnPath)
            }
            guard !tabs.isEmpty else { return nil }
            let selectedIndex = list.tabs.firstIndex(of: list.selectedTab) ?? 0
            return PaneSnapshot(id: id, tabs: tabs, selectedTab: selectedIndex)
        }
        return WindowSnapshot(frame: frame, tree: tree, panes: paneSnapshots, activePane: activePane, shelfVisible: shelfVisible)
    }

    /// Stops the watcher of EVERY tab of EVERY pane (contract §3/§7) — not just the selected one `panes.values`
    /// alone would reach.
    func tearDown() {
        bannerClearTask?.cancel()
        for state in tabStates.values { state.stopWatching() }
        discardCutBoard()   // XF-T30 W6: the window's pending cut goes with it
    }
}

// MARK: - Wave 4 API (XF-T28 Wave 4 / XF-T29 Pro gates)

extension BrowserWindowModel {
    /// Saved workspaces, read from disk on first use each call — the store is a small JSON file (not kept resident
    /// in the model), so every reader always sees the latest save made from any window.
    var workspaces: [Workspace] {
        WorkspaceStore.decode(WorkspaceStore.load()).store.workspaces
    }

    /// XF-T39 — Save Workspace… as FileOctopus 1.0.10 does it: EVERY open browser window (tabs, panes, folders, views),
    /// an empty name or a taken name is not silently fixed — `.nameTaken` lets the sheet ask whether to replace it.
    /// Pro (`.browserWorkspaces`; XF-T29): Free ⇒ banner + nil, nothing written. nil also when the store file could not
    /// be read and could not be moved aside (it is never overwritten).
    @discardableResult
    func saveWorkspace(named name: String, replacing: UUID? = nil) -> WorkspaceStore.SaveResult? {
        guard LicenseManager.shared.allows(.browserWorkspaces) else {
            banner = "Cần XFinder Pro để lưu Workspace"
            return nil
        }
        let windows = BrowserWindowController.shared.allWindowSnapshots()
        var result: WorkspaceStore.SaveResult?
        let written = changeWorkspaces { store in
            result = store.save(name: name, windows: windows, now: Date(), replacing: replacing)
            if case .saved = result { return true }
            return false
        }
        return written == nil ? nil : result
    }

    /// XF-T39 — FileOctopus: "Opening it later adds these windows" — nothing open is closed or replaced. Pro
    /// (`.browserWorkspaces`).
    func openWorkspace(_ id: UUID) {
        guard LicenseManager.shared.allows(.browserWorkspaces) else {
            banner = "Cần XFinder Pro để mở Workspace"
            return
        }
        guard let workspace = workspaces.first(where: { $0.id == id }), !workspace.windows.isEmpty else {
            banner = "Workspace này không còn nữa."
            return
        }
        BrowserWindowController.shared.openWorkspaceWindows(workspace.windows)
    }

    /// Rename/delete/export stay free (spec XF-T29 §2): only saving/opening a workspace needs Pro.
    @discardableResult
    func renameWorkspace(_ id: UUID, to name: String) -> Bool {
        var outcome: WorkspaceStore.RenameResult = .missing
        _ = changeWorkspaces { store in
            outcome = store.renameChecked(id, to: name)
            return outcome == .renamed
        }
        switch outcome {
        case .renamed: return true
        case .needsName: banner = "Workspace cần có tên."
        case .nameTaken: banner = "Đã có workspace tên này. Chọn tên khác."
        case .missing: banner = "Workspace này không còn nữa."
        }
        return false
    }

    func duplicateWorkspace(_ id: UUID) {
        _ = changeWorkspaces { store in store.duplicate(id, now: Date()) != nil }
    }

    func deleteWorkspace(_ id: UUID) {
        _ = changeWorkspaces { store in
            guard store.workspaces.contains(where: { $0.id == id }) else { return false }
            store.delete(id)
            return true
        }
    }

    func exportWorkspaces() -> Data {
        WorkspaceStore.decode(WorkspaceStore.load()).store.exportJSON()
    }

    /// "Xem các workspace đã lưu…": what each one holds, read-only.
    var workspaceSummaries: [WorkspaceStore.Summary] {
        WorkspaceStore.decode(WorkspaceStore.load()).store.summaries()
    }

    /// One read-change-write of `workspaces.json`. `change` returns whether it changed anything worth writing. A file
    /// that could not be fully read is NEVER written over (FileOctopus: "The saved workspaces file couldn't be read, so
    /// it isn't changed"): it is moved aside first, and when even that fails nothing is written. Returns nil when the
    /// write was refused, otherwise whether something was written.
    private func changeWorkspaces(_ change: (inout WorkspaceStore) -> Bool) -> Bool? {
        let (decoded, skipped) = WorkspaceStore.decode(WorkspaceStore.load())
        var store = decoded
        guard change(&store) else { return false }
        if skipped > 0, !WorkspaceStore.moveUnreadableFileAside(now: Date()) {
            banner = "Không đọc được tệp workspace đã lưu nên không ghi đè."
            return nil
        }
        store.persist()
        return true
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
        try? storageJSON().write(to: url, options: .atomic)
    }

    /// XF-T39: keeps a damaged or newer-format `workspaces.json` next to the new one ("workspaces-unreadable-<time>.json")
    /// instead of letting the next save drop what this build could not read. false = could not move it.
    static func moveUnreadableFileAside(now: Date) -> Bool {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        let stamp = Int(now.timeIntervalSince1970)
        let aside = url.deletingLastPathComponent().appendingPathComponent("workspaces-unreadable-\(stamp).json")
        return (try? FileManager.default.moveItem(at: url, to: aside)) != nil
    }
}

// MARK: - XF-T30 W1 pane tabs (contract docs/specs/XF-T30-w1-contract.md §3)

extension BrowserWindowModel {
    /// The selected tab of `pane`, O(1) (the tab strip asks once per tab on every render).
    func selectedTabID(of pane: PaneID) -> TabID? { tabLists[pane]?.selectedTab }

    /// The tabs of `pane`, in strip order (the selected one is `panes[pane]`).
    func tabs(of pane: PaneID) -> [PaneState] {
        guard let list = tabLists[pane] else { return [] }
        return list.tabs.compactMap { tabStates[$0] }
    }

    /// Shows `tab` in its pane and focuses that pane.
    func selectTab(_ tab: TabID) {
        guard let pane = pane(containing: tab), var list = tabLists[pane] else { return }
        guard list.select(tab) else { return }
        tabLists[pane] = list
        activePane = pane
    }

    /// A new tab right after the selected one of `pane`, on `path` (nil = the selected tab's folder), selected.
    @discardableResult
    func newTab(in pane: PaneID, path: String?) -> TabID? {
        guard var list = tabLists[pane], let template = tabStates[list.selectedTab] else { return nil }
        let tabID = TabID()
        let state = PaneState(id: pane, path: path ?? template.path, viewMode: template.viewMode, sort: template.sort,
                              showHidden: template.showHidden, history: nil, tabID: tabID)
        tabStates[tabID] = state
        list.add(tabID)
        tabLists[pane] = list
        return tabID
    }

    /// Q-T30-4: the last tab of a pane closes the pane when another pane exists; the last tab of the last pane stays.
    func closeTab(_ tab: TabID) {
        guard let pane = pane(containing: tab), var list = tabLists[pane] else { return }
        if list.count == 1 {
            guard tree.count > 1 else { return }   // the one pane left in the window keeps its one tab.
            if let next = tree.close(pane) {
                activePane = (activePane == pane) ? next : activePane
                destroyPane(pane)
            }
            return
        }
        guard list.remove(tab) else { return }
        tabStates.removeValue(forKey: tab)?.stopWatching()
        tabLists[pane] = list
    }

    /// Moves `tab` into `pane` at `index` (nil = after its selected tab) and selects it there. A no-op when `tab`
    /// is already the only tab of `pane` (dragging a one-tab pane's tab back onto itself — contract §7).
    func moveTab(_ tab: TabID, toPane pane: PaneID, at index: Int?) {
        guard let sourcePane = self.pane(containing: tab), var sourceList = tabLists[sourcePane] else { return }
        if pane == sourcePane {
            guard let targetIndex = index else { return }
            sourceList.move(tab, to: targetIndex)
            tabLists[pane] = sourceList
            return
        }
        guard var destList = tabLists[pane] else { return }
        guard sourceList.remove(tab) else { return }   // refuses when `tab` is the only tab of `sourcePane`.
        let moved = rehome(tab, into: pane)
        let insertIndex = index ?? (destList.selected + 1)
        destList.insert(tab, at: insertIndex, select: true)
        tabLists[sourcePane] = sourceList
        tabLists[pane] = destList
        if moved != nil { activePane = pane }
    }

    /// Splits `pane` toward `dir` (Pro-gated like any split) and moves `tab` into the new pane. Returns the new pane.
    /// A no-op (nil) when `tab` is the only tab of `pane` — there would be nothing left in `pane` to split from
    /// (contract §7: "kéo tab của ngăn một-tab ra mép chính nó ⇒ không gì").
    @discardableResult
    func moveTabToNewPane(_ tab: TabID, beside pane: PaneID, _ dir: SplitDirection) -> PaneID? {
        guard canSplitUnderLicense, var sourceList = tabLists[pane], sourceList.count >= 2 else { return nil }
        guard let newID = tree.split(pane, dir) else { return nil }
        guard sourceList.remove(tab) else {
            // Should not happen (count >= 2 was checked), but undo the tree split rather than leave a dangling pane.
            _ = tree.close(newID)
            return nil
        }
        tabLists[pane] = sourceList
        let moved = rehome(tab, into: newID)
        tabLists[newID] = PaneTabList(first: tab)
        if moved != nil { activePane = newID }
        return newID
    }

    /// Opens a new window holding only `tab` (folder, history, view) and closes it here. The new window gets a
    /// single pane with `tab`'s exact state (Pro's pane limit does not apply — one pane is always allowed); a fresh
    /// `PaneTree()` is always a single leaf, so its own (freshly minted) pane id is used, rather than reusing
    /// `tab`'s current pane id, which the new tree knows nothing about.
    func moveTabToWindow(_ tab: TabID) {
        guard let state = tabStates[tab] else { return }
        let newTree = PaneTree()
        let newPaneID = newTree.panes[0]
        let tabSnapshot = TabSnapshot(path: state.path, viewMode: state.viewMode, sort: state.sort, history: state.history,
                                      showHidden: state.showHidden, groupBy: state.groupBy,
                                      columnPath: state.columnPath.isEmpty ? nil : state.columnPath)
        let paneSnapshot = PaneSnapshot(id: newPaneID, tabs: [tabSnapshot], selectedTab: 0)
        let snapshot = WindowSnapshot(frame: nil, tree: newTree, panes: [paneSnapshot], activePane: newPaneID, shelfVisible: false)
        BrowserWindowController.shared.openRestoredWindow(snapshot)
        closeTab(tab)
    }

    /// The pane that holds `tab`.
    func pane(containing tab: TabID) -> PaneID? {
        for (pane, list) in tabLists where list.tabs.contains(tab) {
            return pane
        }
        return nil
    }

    /// A tab dragged inside this window and dropped on `pane` (`PaneTabRules.dropTarget` decided `target`).
    func dropTab(_ tab: TabID, onto pane: PaneID, target: PaneTabRules.DropTarget) {
        switch target {
        case .strip(let index):
            moveTab(tab, toPane: pane, at: index)
        case .edge(let direction):
            _ = moveTabToNewPane(tab, beside: pane, direction)
        case .center:
            moveTab(tab, toPane: pane, at: nil)
        }
    }
}
