import AppKit
import SwiftUI
import Quartz
import os

/// XF-T28 cluster C (contract: docs/specs/XF-T28-ui-contract.md) — every file browser window: opening, session
/// save/restore, the one keyboard dispatcher (`performKeyEquivalent`), mouse Back/Forward, and Quick Look for
/// whichever window is key.
@MainActor final class BrowserWindowController: NSObject {
    static let shared = BrowserWindowController()

    /// 720×460 — the contract's minimum content size for a browser window.
    private static let minimumContentSize = NSSize(width: 720, height: 460)
    /// XF-T30 W1 §5 — every browser window shares this so macOS offers native tabbing between them.
    static let tabbingIdentifier = "com.xfinder.browser"

    private var windows: [BrowserWindow] = []
    private var modelsByWindow: [ObjectIdentifier: BrowserWindowModel] = [:]
    /// One `BrowserToolbarController` per window, kept alive here (the contract: "controller giữ strong") — the
    /// toolbar itself only holds a `weak var window`, so nothing else keeps it around once a window closes.
    private var toolbarsByWindow: [ObjectIdentifier: BrowserToolbarController] = [:]
    private let quickLook = BrowserQuickLookController()
    private weak var quickLookModel: BrowserWindowModel?
    /// XF-T30 W5b — index lifecycle (contract §"Vòng đời chỉ mục"): observes `fileBrowser.search.roots` so a change
    /// made in Settings ▸ Search reaches the running `FilenameIndex`/`ContentIndex` without a relaunch.
    private var indexRootsObserver: NSObjectProtocol?
    private var lastKnownIndexRoots: [IndexRoot] = []
    /// XF-T37 L5 — when the "press ⌘Q again" warning was last shown (nil = no warning pending).
    private var lastQuitWarning: Date?
    private let quitGuardHUD = BrowserQuitGuardHUD()

    private override init() {
        super.init()
        // Pre-warm FileProvider/Ubiquity lookup off the main thread once so the first outline cell
        // render does not take a synchronous ~376 ms dlopen hitch on the main thread (measured 2026-11-25).
        Task.detached(priority: .utility) {
            _ = CloudFactsCache.isUbiquitousFolder("/tmp")
        }
        #if DEBUG
        installClickTracer()
        #endif
    }

    #if DEBUG
    /// Debug builds only: one log line per left click in a browser window — the view the click hit, and the first
    /// responder before and after — so "a click selects nothing" can be read from `log show` instead of guessed
    /// (2026-10-26: a synthetic click left the window as first responder while AX-set selection worked).
    private var clickTracer: Any?
    private func installClickTracer() {
        clickTracer = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window as? BrowserWindow else { return event }
            let point = event.locationInWindow
            var chain: [String] = []
            var view: NSView? = window.contentView?.hitTest(point)
            while let v = view, chain.count < 8 { chain.append(String(describing: type(of: v))); view = v.superview }
            let before = String(describing: window.firstResponder.map { type(of: $0) })
            Self.clickLog.info("down \(Int(point.x))×\(Int(point.y)) hit=\(chain.joined(separator: " < "), privacy: .public) first=\(before, privacy: .public)")
            DispatchQueue.main.async {
                let after = String(describing: window.firstResponder.map { type(of: $0) })
                Self.clickLog.info("after first=\(after, privacy: .public)")
            }
            return event
        }
    }
    private static let clickLog = Logger(subsystem: "com.xfinder.app", category: "clicks")
    #endif

    private static var sessionURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder/Browser/session.json", isDirectory: false)
    }

    // MARK: - Opening

    /// The global launcher brings an existing browser back instead of accumulating duplicate windows.
    func showBrowser() {
        guard BrowserSettings.isEnabled else { return }
        let existing = NSApp.orderedWindows.compactMap { $0 as? BrowserWindow }.first {
            windows.contains($0)
        } ?? windows.last
        guard let existing else { openWindow(path: nil); return }
        if existing.isMiniaturized { existing.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        existing.makeKeyAndOrderFront(nil)
    }

    /// ⌘N, menu bar item, deep link `xfinder://browser?path=`. `path` nil ⇒ `BrowserSettings.newWindowTarget`.
    /// `startSearch`: the AI Search page's "Mở thanh tìm" link — opens the window then starts ⌥⌘F (an empty,
    /// editable search) in its active pane, same as pressing the chord by hand right after the window appears.
    func openWindow(path: String?, startSearch: Bool) {
        let model = openWindow(path: path)
        if startSearch {
            model.perform(.find)
        }
    }

    /// XF-T30 W4 §3 — a fresh install's very first browser window shows Welcome INSTEAD (its own layout step opens
    /// the real window, "filled with folders you allowed" — FileOctopus' own wording); every later window opens
    /// normally. Only an explicit request for a brand-new window goes through here — restored windows
    /// (`openWindow(snapshot:)`, including the one Welcome's own completion opens via `openRestoredWindow`) never
    /// re-enter this gate, so Welcome cannot loop into itself. Returns a model either way (Welcome's own window has
    /// no `BrowserWindowModel` of its own) so every call site keeps working; the model returned in that branch is a
    /// throwaway, unattached to any on-screen window, for API compatibility only.
    @discardableResult
    func openWindow(path: String?) -> BrowserWindowModel {
        if windows.isEmpty, !BrowserSettings.onboardingDone {
            BrowserWindowModel.showWelcomeIfFirstRun()
            return BrowserWindowModel(snapshot: nil, initialPath: path ?? BrowserWindowModel.resolvedNewWindowTarget())
        }
        // No browser window open and no specific folder asked for: bring back the last session (FileOctopus R46 —
        // closing the last window behaves like quitting; it comes back on the next open). Owner report 2026-10-25:
        // Side by Side came back as a single pane. A specific folder (deep link, sidebar, "show in folder") restores
        // the session too and opens as a new tab of the active pane — the layout survives either way.
        if windows.isEmpty, BrowserSettings.reopenWindows, restoreSavedSession(),
           let first = windows.first, let restored = modelsByWindow[ObjectIdentifier(first)] {
            if let path, restored.panes[restored.activePane]?.path != path {
                _ = restored.newTab(in: restored.activePane, path: path)
            }
            return restored
        }
        let target = path ?? BrowserWindowModel.resolvedNewWindowTarget()
        let model = BrowserWindowModel(snapshot: nil, initialPath: target)
        presentNewWindow(for: model, frame: nil)
        return model
    }

    @discardableResult
    private func openWindow(snapshot: WindowSnapshot) -> BrowserWindow {
        let model = BrowserWindowModel(snapshot: snapshot, initialPath: nil)
        return presentNewWindow(for: model, frame: snapshot.frame)
    }

    /// XF-T28 Wave 4 — `BrowserWindowModel.openWorkspace` opens any window beyond the workspace's first one
    /// (which replaces the CALLING window's own layout instead) through here; same mechanism as session restore,
    /// just invoked one window at a time instead of for a whole saved session.
    func openRestoredWindow(_ snapshot: WindowSnapshot) {
        openWindow(snapshot: snapshot)
    }

    /// XF-T30 W1 — ⌘T / the native tab bar's +: a new browser window added as a native tab of `model`'s window.
    /// Opens `BrowserSettings.newWindowTarget` (XF-T30 W4 — W1's own comment here used to say "Home, until W4 has
    /// 'New windows show'"), then slots it into the SAME `NSWindowTabGroup` as `model`'s own window, right after it.
    /// Resolves the existing global Cmd-K collision without exposing window/model internals.
    @discardableResult
    func performShortcutInKeyWindow(_ command: BrowserCommand) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
              let window = NSApp.keyWindow as? BrowserWindow,
              let model = modelsByWindow[ObjectIdentifier(window)] else { return false }
        _ = model.perform(command)
        return true
    }

    func openWindowTab(besideWindowOf model: BrowserWindowModel) {
        guard let existingWindow = windows.first(where: { modelsByWindow[ObjectIdentifier($0)] === model }) else {
            openWindow(path: nil)
            return
        }
        let newModel = openWindow(path: nil)
        guard let newWindow = windows.first(where: { modelsByWindow[ObjectIdentifier($0)] === newModel }) else { return }
        existingWindow.addTabbedWindow(newWindow, ordered: .above)
    }

    @discardableResult
    private func presentNewWindow(for model: BrowserWindowModel, frame: CGRect?) -> BrowserWindow {
        let contentRect = frame.map { NSRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) }
            ?? NSRect(x: 0, y: 0, width: Self.minimumContentSize.width, height: Self.minimumContentSize.height)
        let window = BrowserWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.controller = self
        window.contentMinSize = Self.minimumContentSize
        window.isReleasedWhenClosed = false
        window.title = VirtualLocation.parse(model.active.path) == .learn ? L10n.t("Học sử dụng") : (model.active.path as NSString).lastPathComponent
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.toolbarStyle = .unified
        let hosting = NSHostingView(rootView: BrowserRootView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        if frame == nil {
            window.center()
        }
        let isFirstWindow = windows.isEmpty
        windows.append(window)
        DockController.browserWindows(open: true)   // XF-T38: the browser owns the menu bar while it is open
        // XF-T32 W0: hitch probe (Debug builds only) runs while a browser window is open — 10 wakeups/s would
        // break the 0 s idle budget if it ran for the app's whole life.
        MainThreadHitchProbe.shared.start()
        modelsByWindow[ObjectIdentifier(window)] = model
        let toolbar = BrowserToolbarController(model: model, window: window)
        toolbar.install()
        toolbarsByWindow[ObjectIdentifier(window)] = toolbar
        window.makeKeyAndOrderFront(nil)
        observeTitle(of: model, window: window)
        if isFirstWindow { indexLifecycleWindowOpened() }
        return window
    }

    // MARK: - Index lifecycle (XF-T30 W5b)

    /// The first browser window of this launch (or since the last "all windows closed"): starts the indexes
    /// (contract: "cửa sổ trình duyệt đầu tiên mở ⇒ `resume()` + `setRoots()`") and arms the Settings ▸ Search
    /// observer so a root added/removed/paused later reaches the running indexes without a relaunch.
    private func indexLifecycleWindowOpened() {
        lastKnownIndexRoots = BrowserSettings.indexRoots
        Task {
            await FilenameIndex.shared.resume()
            await FilenameIndex.shared.setRoots(lastKnownIndexRoots)
            await ContentIndex.shared.resume()
            await ContentIndex.shared.setRoots(lastKnownIndexRoots)
        }
        guard indexRootsObserver == nil else { return }
        indexRootsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.indexRootsMayHaveChanged()
            }
        }
    }

    /// `UserDefaults.didChangeNotification` fires for EVERY default write app-wide, not just
    /// `fileBrowser.search.roots` — compare against `lastKnownIndexRoots` so an unrelated setting change (or this
    /// same `setRoots` call's own write-back, if any) does not re-issue an identical `setRoots` on every keystroke
    /// elsewhere in the app.
    private func indexRootsMayHaveChanged() {
        guard !windows.isEmpty else { return }
        let current = BrowserSettings.indexRoots
        guard current != lastKnownIndexRoots else { return }
        lastKnownIndexRoots = current
        Task {
            await FilenameIndex.shared.setRoots(current)
            await ContentIndex.shared.setRoots(current)
        }
    }

    /// No browser window left open: stops FSEvents watching (cursors are kept — contract: "đóng hết ⇒ dừng FSEvents,
    /// lưu con trỏ"), so a reopened window can catch up instead of rescanning from zero.
    private func indexLifecycleAllWindowsClosed() {
        Task {
            await FilenameIndex.shared.suspend()
            await ContentIndex.shared.suspend()
        }
    }

    /// Keeps the title in step with the active pane's folder — a window's title is "the active pane's folder
    /// name", not a fixed app name, so the user can tell windows apart in Mission Control / Dock.
    private func observeTitle(of model: BrowserWindowModel, window: BrowserWindow) {
        withObservationTracking {
            _ = model.active.path
        } onChange: { [weak self, weak window, weak model] in
            Task { @MainActor in
                guard let window, let model else { return }
                window.title = VirtualLocation.parse(model.active.path) == .learn ? L10n.t("Học sử dụng") : (model.active.path as NSString).lastPathComponent
                self?.observeTitle(of: model, window: window)
            }
        }
    }

    func windowClosed(_ window: BrowserWindow) {
        guard let index = windows.firstIndex(where: { $0 === window }) else { return }
        // The LAST window keeps its layout in the session (it used to be removed first, so an empty session overwrote
        // the real one — measured: session.json held 0 windows after closing a Side by Side window). While quitting,
        // the session was already saved with every window; closing them one by one must not shrink it.
        let closingLast: Bool = windows.count == 1
        if closingLast && !terminating { saveSession() }
        let model = modelsByWindow[ObjectIdentifier(window)]
        model?.tearDown()
        // The closing window's own model was driving Quick Look: the panel has nothing left to show for — close
        // it instead of leaving it open over a now-closed window's (stale) selection.
        if let model, quickLookModel === model {
            QLPreviewPanel.shared()?.orderOut(nil)
            quickLookModel = nil
        }
        toolbarsByWindow.removeValue(forKey: ObjectIdentifier(window))?.tearDown()
        modelsByWindow.removeValue(forKey: ObjectIdentifier(window))
        windows.remove(at: index)
        if !closingLast && !terminating { saveSession() }
        if windows.isEmpty {
            DockController.browserWindows(open: false)   // back to the user's "Hiện icon trên Dock" choice
            FileIconCache.shared.purge()
            MainThreadHitchProbe.shared.stop()
            indexLifecycleAllWindowsClosed()
        }
    }

    /// The key browser window's model, else the most recently opened window's; nil when no browser window is open.
    var frontmostModel: BrowserWindowModel? {
        if let window = NSApp.keyWindow as? BrowserWindow, let model = modelsByWindow[ObjectIdentifier(window)] { return model }
        return windows.last.flatMap { modelsByWindow[ObjectIdentifier($0)] }
    }

    /// ⌘W / File ▸ Đóng cửa sổ / the palette: close this model's window (with native tabs: its tab), like the window's
    /// own close button — `windowWillClose` then does the usual teardown.
    func closeWindow(of model: BrowserWindowModel) {
        guard let window = windows.first(where: { modelsByWindow[ObjectIdentifier($0)] === model }) else { return }
        window.performClose(nil)
    }

    // MARK: - Main menu (Q-T30-13)

    /// `window` became key: ask `BrowserMainMenu` to show the browser's own menu items for it.
    func windowBecameKey(_ window: BrowserWindow) {
        guard let model = modelsByWindow[ObjectIdentifier(window)] else { return }
        BrowserMainMenu.shared.activate(for: model)
    }

    /// `window` resigned key. Only removes the menu items when NO other browser window is now key — switching
    /// focus from one browser window straight to another (e.g. clicking a background tab) fires resign-then-become
    /// in that order, and tearing down between them would otherwise show a one-frame flash of the stock menu.
    func windowResignedKey(_ window: BrowserWindow) {
        guard !(NSApp.keyWindow is BrowserWindow) else { return }
        BrowserMainMenu.shared.deactivate()
    }

    var windowCount: Int { windows.count }

    // MARK: - Session

    /// `fileBrowser.reopenWindows` && not holding Shift at launch — holding Shift opens no windows (FileOctopus'
    /// one-time skip), same as a fresh install would see nothing to restore.
    ///
    /// XF-T30 W1 — native tab groups: snapshots carry `tabGroup`/`tabIndex`/`selectedInGroup`; windows sharing a
    /// `tabGroup` number are opened in `tabIndex` order and re-grouped via `addTabbedWindow(_:ordered:)` as each one
    /// comes up, so the group forms the same leading-to-trailing order it was saved in. A v1 session (every
    /// `tabGroup` nil) opens every window standalone, same as before this feature existed.
    func restoreSessionAtLaunch() {
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
        guard SessionRestore.shouldRestore(shiftHeld: shiftHeld, reopenEnabled: BrowserSettings.reopenWindows) else { return }
        _ = restoreSavedSession()
    }

    /// Set by `saveSessionForQuit()`: the windows AppKit closes while the app terminates must not rewrite the session.
    private var terminating: Bool = false

    /// App termination: save every open window once, then ignore the per-window closes that follow.
    func saveSessionForQuit() {
        saveSession()
        terminating = true
    }

    /// Opens every window of the saved session; false when there is nothing to restore.
    @discardableResult
    func restoreSavedSession() -> Bool {
        guard let data = try? Data(contentsOf: Self.sessionURL),
              let snapshots = try? JSONDecoder().decode([WindowSnapshot].self, from: data), !snapshots.isEmpty
        else { return false }
        let missingFolders = openSnapshots(snapshots)
        if !missingFolders.isEmpty, let lastWindow = windows.last, let model = modelsByWindow[ObjectIdentifier(lastWindow)] {
            model.banner = "Một số thư mục đã phiên trước mở không còn tồn tại"
        }
        return true
    }

    /// XF-T39 — Window ▸ Mở workspace: FileOctopus "Opening it later adds these windows" — the workspace's windows open
    /// next to the ones already open (with their native tab groups), nothing is closed or replaced.
    func openWorkspaceWindows(_ snapshots: [WindowSnapshot]) {
        let missing = openSnapshots(snapshots)
        if !missing.isEmpty, let lastWindow = windows.last, let model = modelsByWindow[ObjectIdentifier(lastWindow)] {
            model.banner = "Một số thư mục của Workspace này không còn tồn tại"
        }
    }

    /// Every open browser window as a snapshot — the session file and Save Workspace… both use it.
    func allWindowSnapshots() -> [WindowSnapshot] {
        let groupNumbers = Self.assignGroupNumbers(to: windows)
        return windows.compactMap { window -> WindowSnapshot? in
            guard let model = modelsByWindow[ObjectIdentifier(window)] else { return nil }
            var snapshot = model.snapshot(frame: window.frame)
            if let tabGroup = window.tabGroup, let groupMembers = tabGroup.windows as [NSWindow]?, groupMembers.count > 1 {
                snapshot.tabGroup = groupNumbers[ObjectIdentifier(tabGroup)]
                snapshot.tabIndex = groupMembers.firstIndex(where: { $0 === window })
                snapshot.selectedInGroup = (tabGroup.selectedWindow === window)
            }
            return snapshot
        }
    }

    /// Opens `snapshots` as windows, regrouping native tabs; returns the folders that no longer exist.
    private func openSnapshots(_ snapshots: [WindowSnapshot]) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var missingFolders: [String] = []
        /// Most-recently-opened window per `tabGroup` number — `addTabbedWindow(_:ordered:)` inserts relative to
        /// the window it is CALLED ON, not relative to the group's end, so the next tab must be added onto the
        /// previous one (not always the first/leader) for ascending `tabIndex` order to survive a 3+-tab group;
        /// calling it on a fixed leader every time would instead reverse every tab after the first.
        var groupTail: [Int: BrowserWindow] = [:]
        var selectedInGroupWindow: [Int: BrowserWindow] = [:]
        let ordered = snapshots.sorted { lhs, rhs in
            (lhs.tabGroup ?? Int.max, lhs.tabIndex ?? 0) < (rhs.tabGroup ?? Int.max, rhs.tabIndex ?? 0)
        }
        for snapshot in ordered {
            let (restored, missing) = SessionRestore.restored(snapshot, exists: { FileManager.default.fileExists(atPath: $0) }, home: home)
            missingFolders.append(contentsOf: missing)
            let window = openWindow(snapshot: restored)
            if let group = snapshot.tabGroup {
                if let tail = groupTail[group] {
                    tail.addTabbedWindow(window, ordered: .above)
                }
                groupTail[group] = window
                if snapshot.selectedInGroup == true {
                    selectedInGroupWindow[group] = window
                }
            }
        }
        for window in selectedInGroupWindow.values {
            window.tabGroup?.selectedWindow = window
        }
        return missingFolders
    }

    /// Called on window close and app quit (contract): every open window's layout goes to `session.json`.
    ///
    /// XF-T30 W1: `window.tabGroup` is `nil` for a window with no visible tab bar (a lone window, or one whose tab
    /// bar the user hid) — such a window still gets a snapshot, just with `tabGroup`/`tabIndex`/`selectedInGroup`
    /// all nil, same as a v1 (XF-T28) snapshot would have no such fields at all.
    func saveSession() {
        let snapshots = allWindowSnapshots()
        guard let data = try? Self.encoder().encode(snapshots) else { return }
        let url = Self.sessionURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// A stable small integer per distinct `NSWindowTabGroup` among the windows being saved, so two windows that
    /// share a group write the same `tabGroup` number (the group object itself has no number of its own to persist).
    private static func assignGroupNumbers(to windows: [BrowserWindow]) -> [ObjectIdentifier: Int] {
        var numbers: [ObjectIdentifier: Int] = [:]
        var next = 0
        for window in windows {
            guard let tabGroup = window.tabGroup else { continue }
            let id = ObjectIdentifier(tabGroup)
            if numbers[id] == nil {
                numbers[id] = next
                next += 1
            }
        }
        return numbers
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// The feature was switched off: save the session, close every browser window, stop every watcher.
    /// XF-T30 W5b: also stops the search indexes (contract "đóng hết ⇒ dừng FSEvents, lưu con trỏ") — this path
    /// bypasses `windowClosed`'s one-at-a-time bookkeeping entirely, so without this call turning the feature off
    /// would leave `FilenameIndex`/`ContentIndex` watching every approved root with no browser window left to use
    /// the results (an `IdleCost.onlyWhileOpen` violation: the whole point of that contract line is "no window open
    /// ⇒ zero indexing cost").
    func closeAllWindows() {
        saveSession()
        QLPreviewPanel.shared()?.orderOut(nil)
        quickLookModel = nil
        for window in windows {
            modelsByWindow[ObjectIdentifier(window)]?.tearDown()
            window.close()
        }
        windows.removeAll()
        modelsByWindow.removeAll()
        FileIconCache.shared.purge()
        MainThreadHitchProbe.shared.stop()
        indexLifecycleAllWindowsClosed()
    }

    /// XF-T37 L5 — `applicationShouldTerminate`, before anything else: the first ⌘Q typed in a browser window does not
    /// quit; a HUD says how to (⌘Q again within 1.5 s, or hold it). Quit from the menu bar, the Dock or logout passes.
    func allowQuit() -> Bool {
        let event = NSApp.currentEvent
        let isKeyDown = event?.type == .keyDown
        // `charactersIgnoringModifiers` raises on a non-key event — read it only for a keyDown.
        let characters = isKeyDown ? event?.charactersIgnoringModifiers : nil
        let typed = QuitGuardRules.isCommandQ(isKeyDown: isKeyDown, charactersIgnoringModifiers: characters,
                                              hasCommand: event?.modifierFlags.contains(.command) ?? false)
        let decision = QuitGuardRules.decide(enabled: BrowserSettings.warnBeforeQuitting, typedCommandQ: typed,
                                             browserWindowIsKey: NSApp.keyWindow is BrowserWindow,
                                             lastWarning: lastQuitWarning, now: Date())
        switch decision {
        case .quit:
            lastQuitWarning = nil
            quitGuardHUD.hide()
            return true
        case .warn:
            lastQuitWarning = Date()
            quitGuardHUD.flash(for: QuitGuardRules.confirmWindow)
            return false
        }
    }

    /// `applicationShouldTerminate`: a copy/move still running is asked about instead of being cut off mid-file.
    /// Returns `false` to stay open (NSAlert runs modally, so the caller gets a definitive answer before quitting).
    func confirmQuit() -> Bool {
        guard FileOperationQueue.shared.hasActiveWork else { return true }
        let alert = NSAlert()
        alert.messageText = L10n.t("Vẫn còn thao tác tệp đang chạy")
        alert.informativeText = L10n.t("Chờ xong rồi hãy thoát, hay dừng việc đang chạy và thoát ngay?")
        alert.addButton(withTitle: L10n.t("Đợi"))
        alert.addButton(withTitle: L10n.t("Dừng và thoát"))
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let active = FileOperationQueue.shared.queue.active {
                FileOperationQueue.shared.cancel(active.id)
            }
            return true
        }
        return false
    }

    // MARK: - Quick Look

    func toggleQuickLook(for model: BrowserWindowModel) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, quickLookModel === model {
            panel.orderOut(nil)
            return
        }
        quickLookModel = model
        quickLook.items = model.active.selectedEntries.map { URL(fileURLWithPath: $0.path) }
        panel.dataSource = quickLook
        panel.makeKeyAndOrderFront(nil)
        observeQuickLookSelection(of: model)
    }

    /// Keeps the panel's items in step with the active pane's selection while it stays open — the panel itself is
    /// a system singleton with one `dataSource`, so only the key browser window's model drives it at a time.
    private func observeQuickLookSelection(of model: BrowserWindowModel) {
        withObservationTracking {
            _ = model.active.selection
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.quickLookModel === model else { return }
                self.quickLook.items = model.active.selectedEntries.map { URL(fileURLWithPath: $0.path) }
                let panel = QLPreviewPanel.shared()
                panel?.reloadData()
                guard panel?.isVisible == true else { return }
                self.observeQuickLookSelection(of: model)
            }
        }
    }
}

/// One `NSWindow` subclass per browser window: it routes key equivalents through `BrowserCommands` and turns
/// `otherMouseDown`/`swipe` into mouse Back/Forward on whichever pane sits under the cursor.
/// A file view that belongs to one pane (List outline, Icons collection view, Columns browser). A mouse-down
/// anywhere inside it — including the browser's internal column tables — makes that pane the active one.
@MainActor
protocol PaneActivating: AnyObject {
    var activatePane: (() -> Void)? { get }
}

final class BrowserWindow: NSWindow {
    weak var controller: BrowserWindowController?
    fileprivate weak var model: BrowserWindowModel?

    /// The active pane follows the click, before the view under it handles the event. A table or outline keeps the
    /// whole mouse-down for its own tracking loop, so a SwiftUI tap gesture on the pane never fires there: the row
    /// got selected while the blue border — and every keyboard command — stayed on the previous pane (owner
    /// screenshot 2026-10-26).
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if let hit = contentView?.hitTest(event.locationInWindow), !activatePane(containing: hit) {
                activatePane(at: event.locationInWindow)
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    /// The other direction: when the active pane changes by keyboard (Tab with "Tab switches panes", next/previous
    /// pane chords), the pane's file view takes keyboard focus so arrows and type-select act where the border is.
    /// Never steals from a text field (location bar, filter, rename editor) and does nothing when focus is already
    /// inside `view`.
    func focusFileView(_ view: NSView, paneIsActive: Bool) {
        // SwiftUI mounts the palette's field during the same update as the file view.
        // Keep the outline from reclaiming focus before that field starts editing.
        guard modelForThisWindow()?.palette == nil,
              paneIsActive, view.window === self, !(firstResponder.map(isTextEditing) ?? false) else { return }
        if let responder = firstResponder as? NSView, responder === view || responder.isDescendant(of: view) { return }
        makeFirstResponder(view)
    }

    @discardableResult
    private func activatePane(containing view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if let source = candidate as? PaneActivating {
                source.activatePane?()
                return true
            }
            current = candidate.superview
        }
        return false
    }

    /// Outside a file view: the pane whose reported frame contains the click. Replaces a SwiftUI tap gesture on the
    /// pane, which sat above the outline and made AppKit hold every mouse-down for the gesture recognisers
    /// (`_NSGestureRecognizerSortAndSendDelayedEvents` before `-[NSOutlineView mouseDown:]`, sampled 2026-10-26).
    private func activatePane(at locationInWindow: NSPoint) {
        guard let content = contentView, let model = modelForThisWindow() else { return }
        var point = content.convert(locationInWindow, from: nil)
        if !content.isFlipped { point.y = content.bounds.height - point.y }
        guard let pane = model.paneFramesInWindow.first(where: { $0.value.contains(point) })?.key else { return }
        model.focus(pane)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if SnapZoneController.shared.performLocalShortcut(event) { return true }
        let model = modelForThisWindow()
        if let model, let chord = Self.chord(from: event) {
            if model.palette != nil, chord.key == "return" { return super.performKeyEquivalent(with: event) }
            if BrowserSettings.keyBindings.command(for: chord) == .quickOpen,
               model.palette != nil || chord == KeyChord("k", command: true) || chord == KeyChord("p", command: true, control: true) {
                return model.perform(.quickOpen)
            }
        }
        // A text field (the location bar, filter/search fields, rename editor, palette) keeps its own editing
        // keys; only command-chords that are not text editing are still dispatched through the browser table —
        // e.g. ⌘C/⌘V in a text field must behave like normal copy/paste, not the browser's file copy/paste.
        // ⌘⌫ is itself a standard text-editing chord (delete to beginning of line) in the location bar, filter and
        // search fields, so it must NOT fall through there — only the rename editor (Finder: ⌘⌫ trashes the file
        // being renamed, same as when nothing is being edited) gets the carve-out, and only while `renaming` is
        // actually set for this window's model.
        let editingText = firstResponder.map(isTextEditing) ?? false
        if editingText, !isNonTextChord(event, isRenaming: model?.renaming != nil) {
            return super.performKeyEquivalent(with: event)
        }
        guard let model, let chord = Self.chord(from: event) else {
            return super.performKeyEquivalent(with: event)
        }
        // XF-T30 W4 §1 "fileBrowser.tabSwitchesPanes" (Total Commander habit): plain Tab, with no field editor in
        // the way, cycles the active pane instead of doing nothing (a browser window has no other Tab-stop chain
        // worth preserving — focus only ever lives in a text field, already excluded above).
        if BrowserSettings.tabSwitchesPanes, chord == Self.plainTab, !editingText {
            return model.perform(.nextPane) || super.performKeyEquivalent(with: event)
        }
        // XF-T30 W4 §1 "fileBrowser.returnOpens" / F2 (Q-T30-10's Windows Explorer habit, also Total Commander's
        // own Return): swaps which of the two Finder-default chords on plain Return / F2 means Open vs. Rename,
        // on top of whatever `BrowserSettings.keyBindings` already resolved the chord to — a key-binding profile
        // can rebind the surrounding chords, but this single legacy toggle still needs to flip just these two.
        if let remapped = Self.remapReturnAndF2(chord, returnOpens: BrowserSettings.returnOpens) {
            return model.perform(remapped) ? true : super.performKeyEquivalent(with: event)
        }
        guard let command = BrowserSettings.keyBindings.command(for: chord) else {
            return super.performKeyEquivalent(with: event)
        }
        return model.perform(command) ? true : super.performKeyEquivalent(with: event)
    }

    private static let plainTab = KeyChord("tab")

    /// `chord` ⇒ the command `returnOpens` wants for plain Return / F2, or nil when `chord` is neither (every
    /// other chord keeps going through `BrowserSettings.keyBindings.command(for:)` as usual). `returnOpens == false`
    /// (Finder's own layout, the default): Return renames, F2 does nothing special here (no command owns it yet).
    /// `returnOpens == true` (Windows Explorer / Total Commander habit): Return opens the selection, F2 renames.
    private static func remapReturnAndF2(_ chord: KeyChord, returnOpens: Bool) -> BrowserCommand? {
        guard chord.key == "return" || chord.key == "f2", !chord.command, !chord.shift, !chord.option, !chord.control
        else { return nil }
        if chord.key == "f2" { return returnOpens ? .rename : nil }
        // chord.key == "return"
        return returnOpens ? .open : nil   // nil ⇒ let `.rename`'s own ⌘-less Return binding fire as before.
    }

    private func modelForThisWindow() -> BrowserWindowModel? {
        BrowserWindowController.shared.model(for: self)
    }

    private func isTextEditing(_ responder: NSResponder) -> Bool {
        responder is NSText || responder is NSTextView
    }

    /// Command-only chords (no option/control) that AppKit's text system does not itself own, so they should
    /// still fall through to the browser table even while a field editor is first responder — mirrors Finder,
    /// where ⌘⌫ (move to Trash) works while a filename is mid-edit but plain Return does not get hijacked.
    /// `isRenaming`: ⌘⌫ is ALSO plain `NSTextView`'s own "delete to beginning of line" binding, so outside the
    /// rename editor (location bar, filter, search, palette) it must stay text editing, not become Trash.
    private func isNonTextChord(_ event: NSEvent, isRenaming: Bool) -> Bool {
        guard isRenaming, event.modifierFlags.contains(.command) else { return false }
        let key = event.charactersIgnoringModifiers ?? ""
        return key == String(UnicodeScalar(NSDeleteCharacter)!) || key == "\u{7f}"
    }

    private static func chord(from event: NSEvent) -> KeyChord? {
        guard let key = keyName(for: event) else { return nil }
        let flags = event.modifierFlags
        return KeyChord(key, command: flags.contains(.command), shift: flags.contains(.shift),
                        option: flags.contains(.option), control: flags.contains(.control))
    }

    /// Normalizes `NSEvent.charactersIgnoringModifiers` to the lowercase letter / named-key strings
    /// `BrowserCommands`'s table uses.
    private static func keyName(for event: NSEvent) -> String? {
        if let special = specialKeys[event.keyCode] { return special }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else { return nil }
        return chars
    }

    private static let specialKeys: [UInt16: String] = [
        36: "return", 51: "delete", 49: "space", 123: "left", 124: "right",
        125: "down", 126: "up", 53: "escape", 48: "tab", 120: "f2",
    ]

    /// XF-T30 W4 §1 "fileBrowser.mouseBackForward": `off` ⇒ side buttons 4/5 do nothing (the event falls through to
    /// `super`, same as no handler being installed at all); `swapped` ⇒ button 4 (forward) acts as Back and button 5
    /// (back) acts as Forward; `on` (default) is the existing behavior unchanged.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 3 || event.buttonNumber == 4, let model = modelForThisWindow(),
              BrowserSettings.mouseBackForward != .off
        else {
            super.otherMouseDown(with: event)
            return
        }
        var forward = event.buttonNumber == 4
        if BrowserSettings.mouseBackForward == .swapped { forward.toggle() }
        navigate(model: model, at: event.locationInWindow, forward: forward)
    }

    override func swipe(with event: NSEvent) {
        guard let model = modelForThisWindow(), BrowserSettings.mouseBackForward != .off else {
            super.swipe(with: event)
            return
        }
        let swapped = BrowserSettings.mouseBackForward == .swapped
        if event.deltaX > 0 {
            navigate(model: model, at: event.locationInWindow, forward: swapped)
        } else if event.deltaX < 0 {
            navigate(model: model, at: event.locationInWindow, forward: !swapped)
        } else {
            super.swipe(with: event)
        }
    }

    /// Mouse Back/Forward and swipe act on the pane under the cursor, not necessarily the active one. `contentView`
    /// (an `NSHostingView`, flipped) is NOT the same size as the window frame when the window has a title bar — go
    /// through `convert(_:from:)` into the content view's own (already top-left) coordinate space, same pattern as
    /// `ScrollCaptureController`, instead of subtracting from the window frame's height.
    private func navigate(model: BrowserWindowModel, at point: NSPoint, forward: Bool) {
        guard let contentView else { return }
        let local = contentView.convert(point, from: nil)
        let rect = CGRect(origin: .zero, size: contentView.bounds.size)
        guard let paneID = model.tree.pane(at: local, in: rect, divider: 1),
              let pane = model.panes[paneID]
        else { return }
        if forward { pane.goForward() } else { pane.goBack() }
    }

    override func close() {
        BrowserWindowController.shared.windowClosed(self)
        super.close()
    }

    /// Native tab bar's "+" (`NSResponder`'s own `IBAction`, fired by AppKit — not something this app calls
    /// directly): same mechanism ⌘T goes through.
    override func newWindowForTab(_ sender: Any?) {
        guard let model = modelForThisWindow() else {
            super.newWindowForTab(sender)
            return
        }
        BrowserWindowController.shared.openWindowTab(besideWindowOf: model)
    }

    /// Q-T30-13: tells `BrowserMainMenu` when a browser window is/isn't the key window, so it can insert/remove
    /// its tagged items. `NSWindow` itself posts `NSWindow.didBecomeKeyNotification`/`didResignKeyNotification`
    /// AFTER these override points run, but overriding directly (rather than observing the notification) means no
    /// extra observer registration/teardown pairing to get wrong on a window that can outlive a single model.
    override func becomeKey() {
        super.becomeKey()
        BrowserWindowController.shared.windowBecameKey(self)
    }

    override func resignKey() {
        super.resignKey()
        BrowserWindowController.shared.windowResignedKey(self)
    }
}

private extension BrowserWindowController {
    func model(for window: BrowserWindow) -> BrowserWindowModel? {
        modelsByWindow[ObjectIdentifier(window)]
    }
}

/// The shared `QLPreviewPanel`'s data source for the file browser (the panel itself is a system singleton — only
/// one can exist). `BrowserWindowController` (the `@MainActor` owner) decides WHEN to show it and WHAT `items`
/// should hold; this type only answers the two data-source questions the panel asks.
///
/// Not `@MainActor`: `QLPreviewPanelDataSource` is a plain (non-isolated) AppKit protocol, and Swift 6 rejects a
/// main-actor type conforming to a non-isolated protocol ("conformance crosses into main actor-isolated code") —
/// the same reason the existing `QuickLookController`/`ClipboardQLController` in this codebase are not `@MainActor`
/// either. `items` is written and read only from the main thread in practice (every caller is `@MainActor`), same
/// as those two reference controllers' own un-isolated `url` property.
private final class BrowserQuickLookController: NSObject, QLPreviewPanelDataSource {
    var items: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard items.indices.contains(index) else { return nil }
        return items[index] as QLPreviewItem
    }
}

/// XF-T37 L5 — "XFinder is still running. Press ⌘Q again or hold ⌘Q to quit." A passive, mouse-transparent panel
/// (never takes focus from the browser), built on first use and reused; it hides itself after the confirm window.
@MainActor
final class BrowserQuitGuardHUD {
    private var panel: SurfacePanel?
    private var hideWork: DispatchWorkItem?

    func flash(for duration: TimeInterval) {
        if panel == nil {
            let p = SurfacePanel(kind: .passive, size: NSSize(width: 380, height: 64))
            p.host(BrowserQuitGuardHUDView())
            p.contentViewController?.view.layoutSubtreeIfNeeded()
            panel = p
        }
        panel?.show(anchor: .topCenter(inset: 72))
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.hide()
    }
}

struct BrowserQuitGuardHUDView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(L10n.t("XFinder vẫn đang chạy."))
                .font(XFinderTokens.Font.sectionTitle)
                .lineLimit(1)
            Text(L10n.t("Bấm ⌘Q lần nữa hoặc giữ ⌘Q để thoát."))
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, XFinderTokens.Space.section)
        .padding(.vertical, XFinderTokens.Space.row)
        .frame(width: 380, height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.surface, style: .continuous))
    }
}
