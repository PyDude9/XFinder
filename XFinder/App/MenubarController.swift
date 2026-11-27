import AppKit
import SwiftUI

/// The status item and its menu.
///
/// P13 (2026-10-14) — the menu is a plain native `NSMenu`, rebuilt each time it opens. It used to be a SwiftUI
/// popover with seven tabs (controls, anti-sleep, system, network, storage, battery, notes) that retained the metrics
/// sampler, the battery store, the volume observer and the audio-device list on every open and ran `diskutil` for the
/// SMART row. The owner asked for one page laid out like OneNotch's menu and for the system figures to live in
/// Settings only (Theo dõi hệ thống), so opening the menu now starts nothing: each row reads one value when the menu
/// is built. The menu-bar readouts' configuration moved to Tổng quan.
///
/// Job sentence: "I click XFinder's icon to reach a quick action (clipboard, capture, timer, anti-sleep, a new note)
/// or a page, without opening the window first."
@MainActor
final class MenubarController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    static let mainAutosaveName = "xfinder.menubar.main"
    static let readoutsAutosaveName = "xfinder.menubar.readouts"

    var statusItem: NSStatusItem?
    private var readoutItem: NSStatusItem?
    private let menu = NSMenu()
    private var popover: NSPopover?
    private var outsideClickLocalMonitor: Any?
    private var outsideClickGlobalMonitor: Any?
    private nonisolated(unsafe) var screenObserver: (any NSObjectProtocol)?

    /// ONE reader (XF-T22): hide XFinder's own status item, default false.
    var hideOwnIcon: Bool {
        UserDefaults.standard.object(forKey: "menubar.hideOwnIcon") as? Bool ?? false
    }

    func setup() {
        migrateLegacyHiderIfNeeded()

        let statusBar = NSStatusBar.system
        // Create the branded main item FIRST so macOS places it to the right of variable-width
        // readouts (farther from the notch).
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.autosaveName = Self.mainAutosaveName
        configureButton(statusItem?.button, label: "XFinder")
        menu.delegate = self
        menu.autoenablesItems = false
        applyIcon()

        let readout = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        readout.autosaveName = Self.readoutsAutosaveName
        readoutItem = readout
        configureButton(readout.button, label: L10n.t("Số liệu XFinder"))
        MenuBarReadoutsController.shared.attach(readout)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ensureMainItemRightOfNotch()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.ensureMainItemRightOfNotch()
        }

        VoiceManager.shared.onStateChange = { [weak self] state in
            self?.updateVoiceState(state)
        }
    }

    private func migrateLegacyHiderIfNeeded() {
        let defaults = UserDefaults.standard
        let storedHide = defaults.object(forKey: MenuBarReadouts.hideOwnIconKey) as? Bool
        let legacyEnabled = defaults.object(forKey: MenuBarReadouts.legacyHiderKey) as? Bool
        if MenuBarReadouts.shouldMigrateLegacyHider(hideOwnIconStored: storedHide, legacyHiderEnabled: legacyEnabled) {
            defaults.set(true, forKey: MenuBarReadouts.hideOwnIconKey)
        }
    }

    func applyIconVisibility() {
        let visible = !hideOwnIcon
        statusItem?.isVisible = visible
        if !visible {
            closePopover()
            return
        }
        ensureMainItemRightOfNotch()
    }

    func showIconAgain() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: MenuBarReadouts.hideOwnIconKey)
        defaults.removeObject(forKey: "NSStatusItem Preferred Position \(Self.mainAutosaveName)")
        applyIcon()
        ensureMainItemRightOfNotch(forceReposition: true)
    }

    func ensureMainItemRightOfNotch(forceReposition: Bool = false) {
        guard let item = statusItem, !hideOwnIcon else { return }
        if !item.isVisible { item.isVisible = true }
        let window = item.button?.window
        let frame = window?.frame ?? .zero
        let screen = window?.screen ?? NSScreen.main
        let rightArea = screen?.auxiliaryTopRightArea ?? .zero
        let needsRecovery = MenuBarReadouts.needsNotchRecovery(
            itemMinX: frame.minX,
            itemWidth: frame.width,
            auxiliaryTopRightMinX: rightArea.minX,
            auxiliaryTopRightWidth: rightArea.width
        )
        guard forceReposition || needsRecovery else { return }
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(Self.mainAutosaveName)")
        item.isVisible = false
        item.isVisible = true
    }

    static func openSystemMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func configureButton(_ button: NSStatusBarButton?, label: String) {
        guard let button else { return }
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            closePopover()
            let clickedItem = sender === readoutItem?.button ? readoutItem : statusItem
            clickedItem?.menu = menu
            clickedItem?.button?.performClick(nil)
            clickedItem?.menu = nil
            return
        }
        togglePopover(relativeTo: sender)
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if let popover, popover.isShown {
            closePopover()
            return
        }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self
        pop.contentSize = NSSize(width: MenubarPanelRules.panelWidth, height: MenubarPanelRules.panelHeight)
        pop.contentViewController = NSHostingController(rootView: MenubarPanelView(
            onClose: { [weak self] in
                self?.closePopover()
            }
        ))
        popover = pop
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
        installOutsideClickMonitors()
    }

    private func closePopover() {
        removeOutsideClickMonitors()
        popover?.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
        popover?.contentViewController = nil
        popover = nil
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self,
                  let popover = self.popover,
                  popover.isShown,
                  event.window !== popover.contentViewController?.view.window,
                  event.window !== self.statusItem?.button?.window,
                  event.window !== self.readoutItem?.button?.window else {
                return event
            }
            self.closePopover()
            return event
        }

        outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let outsideClickLocalMonitor {
            NSEvent.removeMonitor(outsideClickLocalMonitor)
            self.outsideClickLocalMonitor = nil
        }
        if let outsideClickGlobalMonitor {
            NSEvent.removeMonitor(outsideClickGlobalMonitor)
            self.outsideClickGlobalMonitor = nil
        }
    }


    private func updateVoiceState(_ state: VoiceState) {
        guard let button = statusItem?.button else { return }
        switch state {
        case .idle:
            applyIcon()
        case .listening(let rms):
            let symbolName = rms > 0.5 ? "waveform.badge.mic" : "mic.fill"
            let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Listening")
            let colored = base?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemRed, .systemOrange])
            ) ?? base
            colored?.isTemplate = false
            button.image = colored
        case .processing:
            let base = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Processing")
            let colored = base?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemBlue])
            ) ?? base
            colored?.isTemplate = false
            button.image = colored
        case .reviewing:
            let base = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Review")
            let colored = base?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            ) ?? base
            colored?.isTemplate = false
            button.image = colored
        case .error:
            let base = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
            let colored = base?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            ) ?? base
            colored?.isTemplate = false
            button.image = colored
        }
    }

    /// Các lựa chọn biểu tượng menubar (monochrome, SF Symbols kiểu macOS).
    static let iconChoices: [(id: String, symbol: String, title: String)] = [
        ("xfinder", "magnifyingglass.circle.fill", "XFinder"),
        ("magnifier", "magnifyingglass", L10n.t("Kính lúp")),
        ("folder", "folder.fill", L10n.t("Thư mục")),
        ("stack", "rectangle.stack.fill", L10n.t("Chồng lớp")),
    ]

    func applyIcon() {
        statusItem?.isVisible = !hideOwnIcon
        let raw = UserDefaults.standard.string(forKey: "menubar.icon") ?? "xfinder"
        if raw == "xfinder", let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            statusItem?.button?.image = image
            return
        }
        let symbol = Self.iconChoices.first(where: { $0.id == raw })?.symbol ?? "magnifyingglass"
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "XFinder") else { return }
        // Màu (xanh accent) thay vì trắng đơn sắc — để thấy rõ "logo", không còn
        // icon trắng trơn như trước.
        let colored = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.systemBlue])) ?? base
        colored.isTemplate = false
        statusItem?.button?.image = colored
    }

    // MARK: - Menu

    /// Built fresh on every open, so each row shows the live state (a checkmark, a remaining time, a chord the user
    /// re-recorded) and nothing has to observe anything while the menu is closed.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Several actions below (the clipboard hotkey, Translate, pasting) need Accessibility; say so first.
        if !WindowManager.isTrusted {
            menu.addItem(ActionItem(L10n.t("Cấp quyền Trợ năng…")) {
                _ = WindowManager.requestAccessibilityTrust()
            })
            menu.addItem(.separator())
        }

        // Command Bar & File Browser
        let cmdBar = ActionItem(L10n.t("Bảng lệnh")) { QuickSearchPanelController.shared.toggle() }
        cmdBar.setShortcut("k", [.command])
        cmdBar.image = Self.menuSymbol("command")
        menu.addItem(cmdBar)
        if BrowserSettings.isEnabled {
            let browser = ActionItem(L10n.t("Trình duyệt tệp")) { BrowserWindowController.shared.openWindow(path: nil) }
            browser.image = Self.menuSymbol("square.split.2x2")
            menu.addItem(browser)
        }
        menu.addItem(.separator())

        // Clipboard & Snippets
        let clipLib = ActionItem(L10n.t("Thư viện Clipboard")) { AppState.shared.navigate(to: .clipboard) }
        clipLib.image = Self.menuSymbol("doc.on.clipboard")
        menu.addItem(clipLib)
        let clipOpen = clipboardOpenItem()
        clipOpen.image = Self.menuSymbol("clipboard")
        menu.addItem(clipOpen)
        if !TextSnippetStore.shared.snippets.isEmpty {
            menu.addItem(snippetsItem())
        }
        let paused = ClipboardManager.shared.isPaused
        let pause = ActionItem(L10n.t("Tạm dừng ghi clipboard")) {
            // `ClipboardManager.isPaused` is the one reader; the Cài đặt Clipboard switch binds the same key.
            UserDefaults.standard.set(!ClipboardManager.shared.isPaused, forKey: "clipboard.paused")
        }
        pause.state = paused ? .on : .off
        pause.image = Self.menuSymbol(paused ? "play.circle" : "pause.circle")
        menu.addItem(pause)
        menu.addItem(.separator())

        // Quick actions & Unsleep
        let antiSleep = antiSleepItem()
        antiSleep.image = Self.menuSymbol("cup.and.saucer.fill")
        menu.addItem(antiSleep)
        menu.addItem(quickSettingsItem())
        let capture = captureItem()
        capture.image = Self.menuSymbol("camera.viewfinder")
        menu.addItem(capture)
        if TranslateSelectionController.shared.isEnabled {
            let translate = ActionItem(L10n.t("Dịch vùng chọn")) {
                TranslateSelectionController.shared.translateSelection()
            }
            translate.setShortcut("g", [.command, .shift])
            translate.image = Self.menuSymbol("character.book.closed")
            menu.addItem(translate)
        }
        // The timer lives on the notch; with the notch off `startTimer` does nothing, so the row is not offered.
        if NotchSurfaceController.shared.isEnabled {
            let timer = timerItem()
            timer.image = Self.menuSymbol("timer")
            menu.addItem(timer)
        }
        let cleaning = ActionItem(L10n.t("Lau bàn phím…")) { CleaningModeController.shared.start() }
        cleaning.image = Self.menuSymbol("keyboard.badge.eye")
        menu.addItem(cleaning)
        // `createNote()` turns the screen-edge notes on itself when they are off — this row is how a note is made.
        let note = ActionItem(L10n.t("Ghi chú mới")) { EdgeNotesController.shared.createNote() }
        note.image = Self.menuSymbol("note.text.badge.plus")
        menu.addItem(note)
        menu.addItem(.separator())

        // Pages
        let sys = ActionItem(L10n.t("Theo dõi hệ thống")) { AppState.shared.navigate(to: .system) }
        sys.image = Self.menuSymbol("cpu")
        menu.addItem(sys)
        let settings = ActionItem(L10n.t("Cài đặt…")) { AppState.shared.navigate(to: .features) }
        settings.setShortcut(",", [.command])
        settings.image = Self.menuSymbol("gearshape")
        menu.addItem(settings)
        let update = ActionItem(L10n.t("Kiểm tra cập nhật…")) {
            AppState.shared.navigate(to: .about)   // the result is shown on that page
            UpdateChecker.shared.check()
        }
        update.image = Self.menuSymbol("arrow.triangle.2.circlepath")
        menu.addItem(update)
        let help = helpItem()
        help.image = Self.menuSymbol("questionmark.circle")
        menu.addItem(help)
        menu.addItem(.separator())

        // App
        let version = NSMenuItem(title: Self.versionLine, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(ActionItem(L10n.t("Khởi động lại XFinder")) { [weak self] in self?.restart() })
        let quit = ActionItem(L10n.t("Thoát")) { NSApplication.shared.terminate(nil) }
        quit.setShortcut("q", [.command])
        menu.addItem(quit)
    }

    /// ⌘⇧V's own action, named after the surface it opens today (`clipboard.hotkeySurface`, falling back to the shelf
    /// when the notch or its Clipboard page is off — the same decision `hotkeyPressed()` makes). The chord is drawn only
    /// while the hotkey really fires: the tap exists only with its switch on AND Accessibility granted.
    private func clipboardOpenItem() -> NSMenuItem {
        let shelf = ClipboardShelfController.shared
        let notch = NotchSurfaceController.shared
        let surface = NotchClipboardRules.surfaceToOpen(preferred: shelf.hotkeySurface,
                                                        notchSurfaceEnabled: notch.isEnabled && notch.showsClipboardPage)
        let title = surface == .notch ? L10n.t("Mở Clipboard trên notch") : L10n.t("Mở khay Clipboard nổi")
        let item = ActionItem(title) { ClipboardShelfController.shared.hotkeyPressed() }
        if shelf.tapIsLive { item.setShortcut("v", [.command, .shift]) }
        return item
    }

    private static func menuSymbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }

    private func snippetsItem() -> NSMenuItem {
        let parent = NSMenuItem(title: L10n.t("Đoạn văn bản nhanh"), action: nil, keyEquivalent: "")
        parent.image = Self.menuSymbol("text.badge.plus")
        let sub = NSMenu()
        sub.autoenablesItems = false
        for snippet in TextSnippetStore.shared.snippets where snippet.isEnabled {
            let item = ActionItem("\(snippet.trigger) — \(snippet.expansion.prefix(36))") {
                TextSnippetStore.shared.copyExpanded(snippet)
            }
            sub.addItem(item)
        }
        if sub.items.isEmpty {
            let empty = NSMenuItem(title: L10n.t("Chưa có đoạn văn bản nhanh nào."), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        }
        parent.submenu = sub
        return parent
    }

    private func quickSettingsItem() -> NSMenuItem {
        let parent = NSMenuItem(title: L10n.t("Cài đặt nhanh"), action: nil, keyEquivalent: "")
        parent.image = Self.menuSymbol("slider.horizontal.3")
        let sub = NSMenu()
        sub.autoenablesItems = false

        let isDark = SystemControls.isDarkMode()
        let darkItem = ActionItem(L10n.t("Chế độ tối (Dark Mode)")) {
            Task { @MainActor in
                _ = await SystemControls.setAppearance(isDark ? .light : .dark)
            }
        }
        darkItem.state = isDark ? .on : .off
        darkItem.image = Self.menuSymbol("moon.fill")
        sub.addItem(darkItem)

        let dockAuto = DockPrefs.autohide()
        let dockItem = ActionItem(L10n.t("Tự động ẩn Dock của macOS")) {
            DockPrefs.setAutohide(!dockAuto)
        }
        dockItem.state = dockAuto ? .on : .off
        dockItem.image = Self.menuSymbol("dock.rectangle")
        sub.addItem(dockItem)

        let fixedSpaces = SpacesOrderController.isFixedEnabled
        let spacesItem = ActionItem(L10n.t("Cố định thứ tự không gian làm việc (Spaces)")) {
            SpacesOrderController.setFixedOrder(!fixedSpaces)
        }
        spacesItem.state = fixedSpaces ? .on : .off
        spacesItem.image = Self.menuSymbol("rectangle.3.group")
        sub.addItem(spacesItem)

        sub.addItem(.separator())
        let sleepDisplay = ActionItem(L10n.t("Tắt màn hình ngay")) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["displaysleepnow"]
            try? p.run()
        }
        sleepDisplay.image = Self.menuSymbol("lock.fill")
        sub.addItem(sleepDisplay)

        parent.submenu = sub
        return parent
    }

    private func captureItem() -> NSMenuItem {
        let parent = NSMenuItem(title: L10n.t("Chụp màn hình"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        let capture = CaptureController.shared
        for mode in CaptureMode.allCases {
            if mode == .text { sub.addItem(.separator()) }   // the two that read the screen without saving a picture
            let item = ActionItem(L10n.t(mode.titleKey)) {
                // The menu fades out for a moment after the click; let it go, or it ends up in the picture.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { CaptureController.shared.capture(mode) }
            }
            // A recorded chord is drawn only while the capture hotkeys are registered (`capture.enabled`).
            if capture.isEnabled, let chord = capture.shortcut(for: mode) { item.setShortcut(chord) }
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    /// Bug reports leave the Mac only by the person's own hand: "Báo lỗi…" opens the preview on the Giới thiệu page,
    /// where the report can be read before it is copied, saved, or pasted into a GitHub issue.
    private func helpItem() -> NSMenuItem {
        let parent = NSMenuItem(title: L10n.t("Trợ giúp"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(ActionItem(L10n.t("Báo lỗi…")) {
            AppState.shared.aboutShowsReport = true
            AppState.shared.navigate(to: .about)
        })
        sub.addItem(ActionItem(L10n.t("Sao chép thông tin hệ thống")) { DiagnosticsCenter.shared.copySystemInfo() })
        sub.addItem(ActionItem(L10n.t("Mã nguồn trên GitHub")) {
            if let url = URL(string: "https://github.com/\(DiagnosticsCenter.issuesRepo)") { NSWorkspace.shared.open(url) }
        })
        parent.submenu = sub
        return parent
    }

    private func timerItem() -> NSMenuItem {
        let notch = NotchSurfaceController.shared
        let parent = NSMenuItem(title: L10n.t("Hẹn giờ trên notch"), action: nil, keyEquivalent: "")
        parent.state = notch.timerRunning ? .on : .off
        let sub = NSMenu()
        sub.autoenablesItems = false
        for minutes in LiveActivity.timerPresets {
            sub.addItem(ActionItem(String(format: "%d:00", minutes)) {
                NotchSurfaceController.shared.startTimer(minutes: minutes)
            })
        }
        if notch.timerRunning {
            sub.addItem(.separator())
            sub.addItem(ActionItem(L10n.t("Hủy hẹn giờ")) { NotchSurfaceController.shared.cancelTimer() })
        }
        parent.submenu = sub
        return parent
    }

    /// One switch (indefinite, like the old popover's); a timed hold shows how long is left, rounded UP so it never
    /// reads 0 while the Mac is still being kept awake. Durations stay on the Chống ngủ page.
    private func antiSleepItem() -> NSMenuItem {
        let caffeine = CaffeineController.shared
        var title = L10n.t("Chống ngủ")
        if caffeine.isActive, let remaining = caffeine.remainingSeconds {
            title += " · \(max(1, (remaining + 59) / 60))\(L10n.t(" phút"))"
        }
        let item = ActionItem(title) {
            let c = CaffeineController.shared
            if c.isActive { c.deactivate() } else { c.activate(duration: .indefinite) }
        }
        item.state = caffeine.isActive ? .on : .off
        return item
    }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "XFinder \(short) (\(build))"
    }

    // MARK: - Restart

    /// Waits up to 30 s for `$1` (this process) to exit, then opens `$2` (this bundle). If the quit was cancelled the
    /// process is still alive after the wait and nothing is opened — never a second copy beside the first.
    static let relaunchScript = """
    i=0; while /bin/kill -0 "$1" 2>/dev/null && [ "$i" -lt 150 ]; do /bin/sleep 0.2; i=$((i+1)); done
    /bin/kill -0 "$1" 2>/dev/null || /usr/bin/open "$2"
    """

    private func restart() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", Self.relaunchScript, "xfinder-relaunch",
                       String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }   // no helper, no quit: the person keeps a running app
        NSApplication.shared.terminate(nil)
    }
}

/// A menu row that runs a closure. Every row is rebuilt on open, so the closure never outlives the state it read.
@MainActor
private final class ActionItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("ActionItem is built in code") }

    @objc private func fire() { handler() }

    func setShortcut(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
        keyEquivalent = key
        keyEquivalentModifierMask = modifiers
    }

    /// A recorded capture chord. Drawn only when its key is a plain letter or digit: an F-key or an arrow would need a
    /// function-key code here, and a chord drawn wrong is worse than one left out (the Phím tắt page lists them all).
    func setShortcut(_ chord: CaptureShortcut) {
        let name = CaptureShortcut.keyName(for: chord.keyCode)
        guard name.count == 1, let ch = name.first, ch.isASCII, ch.isLetter || ch.isNumber else { return }
        var mods: NSEvent.ModifierFlags = []
        if chord.hasControl { mods.insert(.control) }
        if chord.hasOption { mods.insert(.option) }
        if chord.hasShift { mods.insert(.shift) }
        if chord.hasCommand { mods.insert(.command) }
        guard !mods.isEmpty else { return }
        setShortcut(name.lowercased(), mods)
    }
}
