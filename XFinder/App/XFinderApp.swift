import SwiftUI
import AppKit

@main
struct XFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// `XFinder --mcp` (D): the binary is the Clipboard MCP server. Decided here, before any scene or
    /// AppKit object exists; `MCPServer.run()` never returns.
    init() {
        if CommandLine.arguments.contains("--mcp") { MCPServer.run() }
        // XF-T23 v2b: a crew member's PreToolUse hook (Core/Agents/CrewGuardMain.swift). Never returns.
        if CommandLine.arguments.contains("--crew-guard") { CrewGuardMain.run() }
        // One Vision job (text, cutout) in a child process, so Vision's memory leaves with it (VisionChild). Never returns.
        if CommandLine.arguments.contains(InspectorImageChild.flag) { InspectorImageChild.main() }
        if CommandLine.arguments.contains(VisionChild.flag) { VisionChild.main() }
    }

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
                Button(L10n.t("Cài đặt…")) {
                    if NSApp.keyWindow is BrowserWindow {
                        BrowserSettingsWindowController.shared.show()
                    } else {
                        AppState.shared.navigate(to: .features)
                    }
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

        // Local diagnostics first, so an unclean previous exit is noted before anything else runs.
        DiagnosticsCenter.shared.start()
        // XF-T32 W0: one memory-pressure source (no timer, no cost at rest) trims the browser's image caches.
        MemoryPressureRelief.shared.register("browser.fileIcons") { plan in FileIconCache.shared.relieve(plan) }
        MemoryPressureRelief.shared.register("browser.metadata") { plan in BrowserMetadata.shared.relieve(plan) }
        MemoryPressureRelief.shared.start()
        // Anonymous analytics: decided a few seconds after launch (windows settled, onboarding up if it shows), then on
        // every activation. Nothing is sent or announced while no receiver is configured in Info.plist.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { AnalyticsCenter.shared.evaluate() }

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
        SnapMemoryController.shared.applySettings()            // SNAPMEM: observers only for remembered apps
        SmoothScrollController.shared.applySettings()          // XF-T25: a scroll tap only while on
        CaffeineController.shared.restoreIfNeeded()            // XF-T27: a hold running at quit / update carries on
        MenuBarHiderController.shared.autoHideTimer?.invalidate()
        MenuBarHiderController.shared.applySettings()
        ClipboardShelfController.shared.applySettings()
        FinderKeyboardController.shared.applySettings()
        QuitProtectionController.shared.applySettings()
        QuitOnCloseController.shared.applySettings()           // F3: AX observers only for listed apps
        CaptureController.shared.applySettings()               // F4: Carbon hotkeys for the assigned capture shortcuts
        Task.detached(priority: .utility) { ScrollCaptureController.sweepLeftovers() }   // XF-T26: strips of a crashed session
        // XF-T28: the optional global hotkey, an interrupted-operation report, and the browser windows of the last session.
        LicenseManager.shared.refresh()                // XF-T29: starts the 14-day trial on first launch; DEBUG builds stay full
        BrowserSettings.shared.applySettings()
        FileOperationQueue.shared.loadRecovery()
        if BrowserSettings.isEnabled { BrowserWindowController.shared.restoreSessionAtLaunch() }
        AlertMonitor.shared.applySettings()
        NotchSurfaceController.shared.applySettings()
        SystemKeyInterceptor.shared.applySettings()   // owner's HUD request: after the surface exists
        TranslateSelectionController.shared.applySettings()   // N5a: ⇧⌘G, AX-gated at press time
        SelectionWatcher.shared.applySettings()               // E4: AX observer only when on and trusted
        LinkPreviewFetcher.shared.applySettings()             // D4b: backfills only when the opt-in is on
        LiveActivityMonitor.shared.applySettings()   // B4: after the surface exists
        QuickSearchPanelController.shared.applySettings()
        VoiceManager.shared.setup()
        // No permission prompts at launch: first-run setup (`OnboardingView`) asks for exactly the
        // permissions the chosen features need, and the Permissions tab asks on demand.
        PermissionManager.shared.updateStatuses()
        // BatteryStore is demand-driven like SystemMonitorManager: the Pin page's `retain()` starts the CoreBluetooth
        // GATT scan and the pollers (`startPolling`). The former unconditional `start()` here lit up CoreBluetooth for
        // every user one second after launch — audit 2026-10-18, P-1.

        let setupShowing = Onboarding.shouldShow(completedVersion: UserDefaults.standard.object(forKey: Onboarding.completedKey) as? Int)
        // N7: What's New once per version for existing users; a fresh install is on setup and records this version as seen.
        WhatsNewWindowController.shared.presentIfNeeded(setupShowing: setupShowing)
        if setupShowing {
            OnboardingWindow.shared.show()
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
                LicenseManager.shared.refresh()        // XF-T29: the trial's day count moves on while XFinder stays open
                DockPreviewController.shared.applySettings()
                CommandTabController.shared.applySettings()
                SnapZoneController.shared.applySettings()
                SnapMemoryController.shared.applySettings()
                SmoothScrollController.shared.applySettings()
                FinderKeyboardController.shared.applySettings()
                QuitProtectionController.shared.applySettings()
                QuitOnCloseController.shared.applySettings()
                ClipboardShelfController.shared.applySettings()
                QuickSearchPanelController.shared.applySettings()
                VoiceManager.shared.applySettings()
                TranslateSelectionController.shared.applySettings()
                SelectionWatcher.shared.applySettings()
                GestureController.shared.start()
                SystemKeyInterceptor.shared.applySettings()   // Accessibility may have just been granted
                AnalyticsCenter.shared.evaluate()
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

    /// XF-T28: a copy/move still running is asked about (wait / stop and quit) instead of being cut off mid-file.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard BrowserWindowController.shared.allowQuit() else { return .terminateCancel }   // XF-T37 L5
        guard BrowserWindowController.shared.confirmQuit() else { return .terminateCancel }
        guard VocabularyStore.shared.isSaving else { return .terminateNow }
        Task { @MainActor in
            await VocabularyStore.shared.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// D4: a Quick Look temp copy of an unlocked clip must not survive the process.
    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticsCenter.shared.markQuit()
        BrowserWindowController.shared.saveSessionForQuit()   // XF-T28: windows, panes, folders, Back history
        ClipboardLibraryStore.shared.relockAll()
        // Review 2026-10-18: the members are told to stop FIRST, and the crew cleanup waits (briefly) for their processes to
        // exit before it moves or removes the worktrees they were working in — the old order retired a worktree under a live member.
        WindowlessSessionManager.shared.stopAll()      // P7a: interrupt the turn, close stdin; the conversation stays on disk
        CrewManager.shared.stopAllForQuit()            // P7b: crew folders go, after the members' processes are gone (≤ 1.5 s)
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
        case "browser":
            // XF-T28: `xfinder://browser?path=/some/folder` opens a file browser window there (no path = Home).
            Task { @MainActor in
                guard BrowserSettings.isEnabled else { return }
                BrowserWindowController.shared.openWindow(path: path)
            }
        case "droptray-add":
            if let path {
                Task { @MainActor in
                    DropTrayStore.shared.add(urls: [URL(fileURLWithPath: path)])
                    // XF-T36: an explicit destination — the file just landed in the tray, so show the tray
                    // whatever `notch.clickOpens` says (that rule is for badge / peek clicks only).
                    NotchSurfaceController.shared.reveal(page: .files)
                }
            }
        case "settings":
            Task { @MainActor in
                let dest = comps.queryItems?.first(where: { $0.name == "page" })?.value
                    .flatMap { SidebarDestination(rawValue: $0) } ?? .features
                AppState.shared.navigate(to: dest)
            }
        case "translate":
            let text = comps.queryItems?.first(where: { $0.name == "text" })?.value
            Task { @MainActor in
                if let text, !text.isEmpty {
                    TranslateSelectionController.shared.translate(text: text, sourceApp: nil)
                } else {
                    TranslateSelectionController.shared.translateSelection()
                }
            }
        case "clipboard":
            // D0: `xfinder://clipboard` = the ⌘⇧V hotkey (Shortcuts, scripts, probes) — the same router,
            // so it honours `clipboard.hotkeySurface` and the notch surface's master switch.
            Task { @MainActor in ClipboardShelfController.shared.hotkeyPressed() }
        case "capture":
            // `xfinder://capture?mode=scrolling` = that mode's capture hotkey (Shortcuts, scripts, probes). An unknown
            // mode does nothing; a switched-off Capture does nothing either.
            guard let mode = comps.queryItems?.first(where: { $0.name == "mode" })?.value.flatMap(CaptureMode.init(rawValue:)) else { break }
            Task { @MainActor in
                guard CaptureController.shared.isEnabled else { return }
                CaptureController.shared.capture(mode)
            }
        case "notch":
            // `xfinder://notch?page=nowPlaying` opens the hub on a page (Shortcuts, scripts, probes). An unknown or
            // hidden page resolves the same way a click would; no page = the tray.
            let page = comps.queryItems?.first(where: { $0.name == "page" })?.value
                .flatMap { NotchSurfaceMachine.Page(rawValue: $0) } ?? .files
            Task { @MainActor in NotchSurfaceController.shared.reveal(page: page) }
        default:
            break
        }
    }

    private func setupMenubar() {
        menubarController = MenubarController()
        menubarController?.setup()
    }

    private func setupGlobalHotkeys() {
        // ⌘⇧V is handled system-wide by ClipboardShelfController's event tap (it opens the notch's Clipboard
        // page, or the floating shelf — `clipboard.hotkeySurface`). Only ⌘⇧C remains local, so it fires only
        // while XFinder is frontmost (the Phím tắt page says so).
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
        // D0: the in-app ⌘⇧V goes through the same router as the global one (notch or shelf).
        Task { @MainActor in ClipboardShelfController.shared.hotkeyPressed() }
    }

    @objc func toggleToolsWindow() {
        Task { @MainActor in AppState.shared.navigate(to: .features) }
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
