import SwiftUI
import AppKit

@main
struct XFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About XFinder") {
                    appDelegate.showAboutWindow()
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    AppState.shared.navigate(to: .quickControls)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button("Quit XFinder") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menubarController: MenubarController?
    var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Touch the singleton so its `init` installs the pasteboard monitor.
        // Without this nothing is captured until some view happens to render,
        // and ⌘⇧V opened an empty shelf.
        _ = ClipboardManager.shared

        // Same pattern for gestures: `GestureController.shared` runs the legacy
        // profile migration in `init`, and its `init` only happens when something
        // references it. Relying on the view to do that meant a preferences file
        // written by an older build kept a frozen copy of every preset until the
        // user happened to open the page. Touching it here makes the migration
        // run on every launch, idempotently.
        _ = GestureController.shared

        applySavedAppearance()
        setupMenubar()
        setupGlobalHotkeys()
        setupDatabase()
        // Arms the event tap when gestures are enabled, so a user who switched it
        // on does not have to reopen the page after every launch.
        GestureController.shared.start()
        EdgeNotesController.shared.applySettings()
        // App-lifetime: hovering a Dock icon must work whatever page is open,
        // not only while the Xem trước cửa sổ page happens to be on screen.
        DockPreviewController.shared.applySettings()
        CommandTabController.shared.applySettings()
        SnapZoneController.shared.applySettings()
        MenuBarHiderController.shared.autoHideTimer?.invalidate()
        MenuBarHiderController.shared.applySettings()
        ClipboardShelfController.shared.applySettings()
        FinderKeyboardController.shared.applySettings()
        QuitProtectionController.shared.applySettings()
        NotchDropController.shared.applySettings()
        QuickSearchPanelController.shared.applySettings()
        VoiceManager.shared.setup()
        PermissionManager.shared.requestAllIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            BatteryStore.shared.start()
        }

        if UserDefaults.standard.string(forKey: "startPage") != nil {
            MainWindowController.shared.showWindow()
        }

        // Re-arm AX-gated controllers khi quay lại XFinder (user vừa cấp Trợ
        // năng trong System Settings). Trước đây phải bật/tắt toggle thủ công
        // mới kích hoạt — đây là bug "phải khởi động lại app".
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                PermissionManager.shared.updateStatuses()
                DockPreviewController.shared.applySettings()
                CommandTabController.shared.applySettings()
                SnapZoneController.shared.applySettings()
                FinderKeyboardController.shared.applySettings()
                QuitProtectionController.shared.applySettings()
                ClipboardShelfController.shared.applySettings()
                QuickSearchPanelController.shared.applySettings()
                VoiceManager.shared.applySettings()
                GestureController.shared.start()
            }
        }
    }

    /// Theme + Dock visibility persist in UserDefaults; apply at launch so
    /// they hold even when the user never opens the Settings page.
    @MainActor
    private func applySavedAppearance() {
        let defaults = UserDefaults.standard
        AppearanceController.apply(defaults.string(forKey: "AppTheme") ?? "System")
        DockController.apply(defaults.object(forKey: "ShowDockIcon") as? Bool ?? true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }


    /// Clicking the Dock icon must always surface the main window.
    ///
    /// The `flag` argument is NOT usable here: it reports true whenever *any*
    /// window is on screen, and XFinder keeps floating panels (edge notes,
    /// clipboard shelf) up permanently — so the old `if !flag` guard skipped
    /// the work and the click did nothing. Always front the main window; it is
    /// idempotent when it is already frontmost.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in AppState.shared.bringMainWindowFront() }
        return true
    }

    /// Finder Sync extension gửi URL scheme `xfinder://<host>?path=…` tới đây.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "xfinder" {
            handleFinderURL(url)
        }
    }

    private func handleFinderURL(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let path = comps.queryItems?.first(where: { $0.name == "path" })?.value
        switch comps.host {
        case "droptray-add":
            if let path {
                Task { @MainActor in
                    DropTrayStore.shared.add(urls: [URL(fileURLWithPath: path)])
                    NotchDropController.shared.show()
                }
            }
        case "settings":
            Task { @MainActor in
                let dest = comps.queryItems?.first(where: { $0.name == "page" })?.value
                    .flatMap { SidebarDestination(rawValue: $0) } ?? .quickControls
                AppState.shared.navigate(to: dest)
            }
        default:
            break
        }
    }

    private func setupMenubar() {
        menubarController = MenubarController()
        menubarController?.setup()
    }

    private func setupGlobalHotkeys() {
        // ⌘⇧V is handled system-wide by ClipboardShelfController's event tap
        // (it opens the floating shelf, not the in-app page). Only ⌘⇧C
        // remains local until it too gets a global binding.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .shift]) == [.command, .shift] else { return event }
            switch event.charactersIgnoringModifiers {
            case "c", "C":
                Task { @MainActor in
                    let items = Array(ClipboardManager.shared.history.prefix(10))
                    if !items.isEmpty { ClipboardManager.shared.startPasteStack(from: items) }
                    ClipboardShelfController.shared.toggle()
                }
                return nil
            default:
                return event
            }
        }

        // ⌥⌘ ghi chú: mới / xem tất cả / ghim.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option]) == [.command, .option],
                  event.modifierFlags.intersection([.control, .shift]).isEmpty
            else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n":
                Task { @MainActor in
                    NoteStore.shared.pendingNewNote = true
                    AppState.shared.navigate(to: .notes)
                }
                return nil
            case "l":
                Task { @MainActor in AppState.shared.navigate(to: .notes) }
                return nil
            case "p":
                Task { @MainActor in NoteStore.shared.togglePinFirstActive() }
                return nil
            default:
                return event
            }
        }
    }

    private func setupDatabase() {
        Task {
            await DatabaseService.shared.initialize()
        }
    }

    @objc func toggleClipboardWindow() {
        Task { @MainActor in ClipboardShelfController.shared.toggle() }
    }

    @objc func toggleToolsWindow() {
        Task { @MainActor in AppState.shared.navigate(to: .quickControls) }
    }

    @objc func activatePasteStack() {
        // PasteStack activation is a later phase.
    }

    func showAboutWindow() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "About XFinder"
            window.setContentSize(NSSize(width: 500, height: 400))
            window.center()
            window.isReleasedWhenClosed = false
            self.aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
    }
}
