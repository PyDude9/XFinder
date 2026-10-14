import AppKit

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
final class MenubarController: NSObject, NSMenuDelegate {
    var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func setup() {
        let statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            MenuBarReadoutsController.shared.attach(button)
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem?.menu = menu
        applyIcon()
        VoiceManager.shared.onStateChange = { [weak self] state in
            self?.updateVoiceState(state)
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
        ("magnifier", "magnifyingglass", L10n.t("Kính lúp")),
        ("folder", "folder.fill", L10n.t("Thư mục")),
        ("stack", "rectangle.stack.fill", L10n.t("Chồng lớp")),
    ]

    func applyIcon() {
        let raw = UserDefaults.standard.string(forKey: "menubar.icon") ?? "magnifier"
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

        // Clipboard
        menu.addItem(ActionItem(L10n.t("Thư viện Clipboard")) { AppState.shared.navigate(to: .clipboard) })
        menu.addItem(clipboardOpenItem())
        let paused = ClipboardManager.shared.isPaused
        let pause = ActionItem(L10n.t("Tạm dừng ghi clipboard")) {
            // `ClipboardManager.isPaused` is the one reader; the Cài đặt Clipboard switch binds the same key.
            UserDefaults.standard.set(!ClipboardManager.shared.isPaused, forKey: "clipboard.paused")
        }
        pause.state = paused ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())

        // Quick actions
        menu.addItem(captureItem())
        if TranslateSelectionController.shared.isEnabled {
            let translate = ActionItem(L10n.t("Dịch vùng chọn")) {
                TranslateSelectionController.shared.translateSelection()
            }
            translate.setShortcut("g", [.command, .shift])
            menu.addItem(translate)
        }
        // The timer lives on the notch; with the notch off `startTimer` does nothing, so the row is not offered.
        if NotchSurfaceController.shared.isEnabled {
            menu.addItem(timerItem())
        }
        menu.addItem(antiSleepItem())
        // `createNote()` turns the screen-edge notes on itself when they are off — this row is how a note is made.
        menu.addItem(ActionItem(L10n.t("Ghi chú mới")) { EdgeNotesController.shared.createNote() })
        menu.addItem(.separator())

        // Pages
        menu.addItem(ActionItem(L10n.t("Theo dõi hệ thống")) { AppState.shared.navigate(to: .system) })
        let settings = ActionItem(L10n.t("Cài đặt…")) { AppState.shared.navigate(to: .features) }
        settings.setShortcut(",", [.command])
        menu.addItem(settings)
        menu.addItem(ActionItem(L10n.t("Kiểm tra cập nhật…")) {
            AppState.shared.navigate(to: .about)   // the result is shown on that page
            UpdateChecker.shared.check()
        })
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
