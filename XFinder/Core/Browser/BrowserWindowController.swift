import AppKit
import SwiftUI
import Quartz

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

    private override init() { super.init() }

    private static var sessionURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder/Browser/session.json", isDirectory: false)
    }

    // MARK: - Opening

    /// ⌘N, menu bar item, deep link `xfinder://browser?path=`. `path` nil ⇒ Home. `startSearch`: the AI Search
    /// page's "Mở thanh tìm" link — opens the window then starts ⌥⌘F (an empty, editable search) in its active
    /// pane, same as pressing the chord by hand right after the window appears.
    func openWindow(path: String?, startSearch: Bool) {
        let model = openWindow(path: path)
        if startSearch {
            model.perform(.find)
        }
    }

    @discardableResult
    func openWindow(path: String?) -> BrowserWindowModel {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let model = BrowserWindowModel(snapshot: nil, initialPath: path ?? home)
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
    /// Opens Home (same folder `openWindow(path: nil)` would), then slots it into the SAME `NSWindowTabGroup` as
    /// `model`'s own window, right after it — "until W4 has 'New windows show'" (the contract's own wording for
    /// where the opened folder comes from is still just Home at W1).
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
        window.title = (model.active.path as NSString).lastPathComponent
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.toolbarStyle = .unified
        let hosting = NSHostingView(rootView: BrowserRootView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        if frame == nil {
            window.center()
        }
        windows.append(window)
        modelsByWindow[ObjectIdentifier(window)] = model
        let toolbar = BrowserToolbarController(model: model, window: window)
        toolbar.install()
        toolbarsByWindow[ObjectIdentifier(window)] = toolbar
        window.makeKeyAndOrderFront(nil)
        observeTitle(of: model, window: window)
        return window
    }

    /// Keeps the title in step with the active pane's folder — a window's title is "the active pane's folder
    /// name", not a fixed app name, so the user can tell windows apart in Mission Control / Dock.
    private func observeTitle(of model: BrowserWindowModel, window: BrowserWindow) {
        withObservationTracking {
            _ = model.active.path
        } onChange: { [weak self, weak window, weak model] in
            Task { @MainActor in
                guard let window, let model else { return }
                window.title = (model.active.path as NSString).lastPathComponent
                self?.observeTitle(of: model, window: window)
            }
        }
    }

    func windowClosed(_ window: BrowserWindow) {
        guard let index = windows.firstIndex(where: { $0 === window }) else { return }
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
        saveSession()
        if windows.isEmpty {
            FileIconCache.shared.purge()
        }
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
        guard let data = try? Data(contentsOf: Self.sessionURL),
              let snapshots = try? JSONDecoder().decode([WindowSnapshot].self, from: data), !snapshots.isEmpty
        else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var missingFolders: [String] = []
        /// First window opened per `tabGroup` number — later windows in the same group are added to it via
        /// `addTabbedWindow`, in ascending `tabIndex` order (the snapshots are sorted below before this loop runs).
        var groupLeaders: [Int: BrowserWindow] = [:]
        var selectedInGroupWindow: [Int: BrowserWindow] = [:]
        let ordered = snapshots.sorted { lhs, rhs in
            (lhs.tabGroup ?? Int.max, lhs.tabIndex ?? 0) < (rhs.tabGroup ?? Int.max, rhs.tabIndex ?? 0)
        }
        for snapshot in ordered {
            let (restored, missing) = SessionRestore.restored(snapshot, exists: { FileManager.default.fileExists(atPath: $0) }, home: home)
            missingFolders.append(contentsOf: missing)
            let window = openWindow(snapshot: restored)
            if let group = snapshot.tabGroup {
                if let leader = groupLeaders[group] {
                    leader.addTabbedWindow(window, ordered: .above)
                } else {
                    groupLeaders[group] = window
                }
                if snapshot.selectedInGroup == true {
                    selectedInGroupWindow[group] = window
                }
            }
        }
        for window in selectedInGroupWindow.values {
            window.tabGroup?.selectedWindow = window
        }
        if !missingFolders.isEmpty, let lastWindow = windows.last, let model = modelsByWindow[ObjectIdentifier(lastWindow)] {
            model.banner = "Một số thư mục đã phiên trước mở không còn tồn tại"
        }
    }

    /// Called on window close and app quit (contract): every open window's layout goes to `session.json`.
    ///
    /// XF-T30 W1: `window.tabGroup` is `nil` for a window with no visible tab bar (a lone window, or one whose tab
    /// bar the user hid) — such a window still gets a snapshot, just with `tabGroup`/`tabIndex`/`selectedInGroup`
    /// all nil, same as a v1 (XF-T28) snapshot would have no such fields at all.
    func saveSession() {
        let groupNumbers = Self.assignGroupNumbers(to: windows)
        let snapshots = windows.compactMap { window -> WindowSnapshot? in
            guard let model = modelsByWindow[ObjectIdentifier(window)] else { return nil }
            var snapshot = model.snapshot(frame: window.frame)
            if let tabGroup = window.tabGroup, let groupMembers = tabGroup.windows as [NSWindow]?, groupMembers.count > 1 {
                snapshot.tabGroup = groupNumbers[ObjectIdentifier(tabGroup)]
                snapshot.tabIndex = groupMembers.firstIndex(where: { $0 === window })
                snapshot.selectedInGroup = (tabGroup.selectedWindow === window)
            }
            return snapshot
        }
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
final class BrowserWindow: NSWindow {
    weak var controller: BrowserWindowController?
    fileprivate weak var model: BrowserWindowModel?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let model = modelForThisWindow()
        // A text field (the location bar, filter/search fields, rename editor, palette) keeps its own editing
        // keys; only command-chords that are not text editing are still dispatched through the browser table —
        // e.g. ⌘C/⌘V in a text field must behave like normal copy/paste, not the browser's file copy/paste.
        // ⌘⌫ is itself a standard text-editing chord (delete to beginning of line) in the location bar, filter and
        // search fields, so it must NOT fall through there — only the rename editor (Finder: ⌘⌫ trashes the file
        // being renamed, same as when nothing is being edited) gets the carve-out, and only while `renaming` is
        // actually set for this window's model.
        if let responder = firstResponder, isTextEditing(responder), !isNonTextChord(event, isRenaming: model?.renaming != nil) {
            return super.performKeyEquivalent(with: event)
        }
        guard let model,
              let chord = Self.chord(from: event),
              let command = BrowserCommands.command(for: chord)
        else {
            return super.performKeyEquivalent(with: event)
        }
        return model.perform(command) ? true : super.performKeyEquivalent(with: event)
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
        125: "down", 126: "up", 53: "escape", 48: "tab",
    ]

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 3 || event.buttonNumber == 4, let model = modelForThisWindow() else {
            super.otherMouseDown(with: event)
            return
        }
        navigate(model: model, at: event.locationInWindow, forward: event.buttonNumber == 4)
    }

    override func swipe(with event: NSEvent) {
        guard let model = modelForThisWindow() else {
            super.swipe(with: event)
            return
        }
        if event.deltaX > 0 {
            navigate(model: model, at: event.locationInWindow, forward: false)
        } else if event.deltaX < 0 {
            navigate(model: model, at: event.locationInWindow, forward: true)
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
