import SwiftUI
import AppKit

@main
struct XFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var clipboardManager = ClipboardManager.shared
    @State private var systemMonitorManager = SystemMonitorManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(clipboardManager)
                .environment(systemMonitorManager)
        }
        .windowStyle(.hiddenTitleBar)
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var menubarController: MenubarController?
    var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Touch the singleton so its `init` installs the pasteboard monitor.
        // Without this nothing is captured until some view happens to render,
        // and ⌘⇧V opened an empty shelf.
        _ = ClipboardManager.shared

        applySavedAppearance()
        setupMenubar()
        setupGlobalHotkeys()
        setupDatabase()
        EdgeNotesController.shared.applySettings()
        // App-lifetime: hovering a Dock icon must work whatever page is open,
        // not only while the Xem trước cửa sổ page happens to be on screen.
        DockPreviewController.shared.applySettings()
        CommandTabController.shared.applySettings()
        SnapZoneController.shared.applySettings()
        MenuBarHiderController.shared.applySettings()
        ClipboardShelfController.shared.applySettings()
        FinderKeyboardController.shared.applySettings()
        NotchDropController.shared.applySettings()
        QuickSearchPanelController.shared.applySettings()
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
                    AppState.shared.navigate(to: .clipboard)
                }
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
        Task { @MainActor in AppState.shared.navigate(to: .clipboard) }
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
