import AppKit
import SwiftUI
import Observation
import Carbon

/// Bảng lệnh toàn cục (Command Palette kiểu TinyCast/Spotlight/Raycast):
/// phím tắt tùy chỉnh (mặc định ⌘K) mở từ bất kỳ app nào → panel nổi với ô
/// tìm + kết quả của QuickSearchEngine (quicklink · ứng dụng · phép tính ·
/// tập tin). Cấu hình nằm trong trang Tìm kiếm, không có trang riêng.
///
/// - Hotkey dùng Carbon `RegisterEventHotKey` như TinyCast: hệ thống chỉ
///   báo về đúng tổ hợp đã đăng ký — KHÔNG cần quyền Trợ năng (khác
///   CGEvent tap), không nuốt phím của app khác, và đổi phím chỉ là
///   Unregister + Register.
/// - Recorder: local `NSEvent` monitor tạm ngừng đăng ký phím cũ trong lúc
///   ghi, bắt tổ hợp tiếp theo (phải có ⌘/⌥/⌃), Esc hủy.
/// - Panel là `KeyablePanel` (subclass cho `canBecomeKey`) với
///   `.nonactivatingPanel` → app trước đó giữ focus, TextField vẫn nhận gõ.
/// - Phím khi mở: ↑/↓ chọn · ↵ thực thi (onSubmit) · Esc đóng (local key
///   monitor); click ngoài panel đóng (cặp global + local mouseDown).
@MainActor
@Observable
final class QuickSearchPanelController {
    static let shared = QuickSearchPanelController()

    private(set) var isOpen = false
    private(set) var isRecording = false
    /// Nhãn hiển thị ("⌘K", "⌥Space"…) — lưu kèm khi ghi phím mới.
    private(set) var hotkeyLabel: String =
        UserDefaults.standard.string(forKey: "quickSearch.hotkeyLabel") ?? "⌘K"
    var query = ""
    var selectedIndex = 0

    private var panel: KeyablePanel?
    private var hotKeyRef: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?
    private var recordMonitor: Any?
    private var panelKeyMonitor: Any?
    private var dismissMonitor: Any?
    private var localDismissMonitor: Any?

    private init() {}

    private var hotkeyEnabled: Bool {
        UserDefaults.standard.object(forKey: "quickSearch.enabled") as? Bool ?? true
    }

    func applySettings() {
        guard hotkeyEnabled else { unregisterHotkey(); return }
        registerHotkey()
    }

    // MARK: - Hotkey Carbon (như TinyCast)

    /// 'XFnd' — chữ ký của tổ hợp phím XFinder đăng ký với hệ thống.
    private static let hotKeySignature: OSType = 0x58464E64
    private static let hotKeyID: UInt32 = 1

    private func registerHotkey() {
        installCarbonHandlerIfNeeded()
        guard hotKeyRef == nil else { return }
        let hk = Self.storedHotkey()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hk.keyCode, hk.carbonModifiers,
            EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID),
            GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotKeyRef = ref }
    }

    private func unregisterHotkey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// Handler chỉ cài một lần cho cả đời app; lọc theo chữ ký của XFinder.
    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event,
                              UInt32(kEventParamDirectObject),
                              UInt32(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &id)
            guard id.signature == QuickSearchPanelController.hotKeySignature,
                  id.id == QuickSearchPanelController.hotKeyID
            else { return OSStatus(eventNotHandledErr) }
            let c = Unmanaged<QuickSearchPanelController>.fromOpaque(userData).takeUnretainedValue()
            c.hotkeyFired()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    private nonisolated func hotkeyFired() {
        Task { @MainActor in
            // The global Quick Search default also owns Cmd-K. While a browser is key,
            // let its configured palette binding own that chord; other apps retain Quick Search.
            let stored = Self.storedChordRaw()
            let flags = NSEvent.ModifierFlags(rawValue: UInt(stored.nsModifiers))
            let chord = KeyChord("k", command: flags.contains(.command), shift: flags.contains(.shift),
                                 option: flags.contains(.option), control: flags.contains(.control))
            if stored.keyCode == 40, let command = BrowserSettings.keyBindings.command(for: chord),
               BrowserWindowController.shared.performShortcutInKeyWindow(command) { return }
            self.toggle()
        }
    }

    /// Đọc phím đã lưu (NSEvent keycode + NSEvent.ModifierFlags raw) — mặc định
    /// ⌘K. UserDefaults thread-safe nên đọc được từ nonisolated.
    nonisolated private static func storedHotkey() -> (keyCode: UInt32, carbonModifiers: UInt32) {
        let (code, nsRaw) = storedChordRaw()
        var carbon: UInt32 = 0
        if nsRaw & Int(NSEvent.ModifierFlags.command.rawValue) != 0 { carbon |= UInt32(cmdKey) }
        if nsRaw & Int(NSEvent.ModifierFlags.option.rawValue) != 0 { carbon |= UInt32(optionKey) }
        if nsRaw & Int(NSEvent.ModifierFlags.control.rawValue) != 0 { carbon |= UInt32(controlKey) }
        if nsRaw & Int(NSEvent.ModifierFlags.shift.rawValue) != 0 { carbon |= UInt32(shiftKey) }
        return (UInt32(code), carbon)
    }

    /// P3: the stored chord as written — key code + `NSEvent.ModifierFlags` raw — the ONE read of these two keys,
    /// shared by the Carbon registration above and the Phím tắt page's cross-feature clash check (which used to leave
    /// ⌘K out entirely because it could not decode this layout).
    nonisolated static func storedChordRaw() -> (keyCode: Int, nsModifiers: Int) {
        let d = UserDefaults.standard
        let code = d.object(forKey: "quickSearch.hotkeyCode") as? Int ?? 40 // K
        let nsRaw = d.object(forKey: "quickSearch.hotkeyModifiers") as? Int
            ?? Int(NSEvent.ModifierFlags.command.rawValue)
        return (code, nsRaw)
    }

    // MARK: - Ghi phím tắt mới (recorder)

    /// Bắt đầu ghi: gỡ đăng ký phím cũ để bấm phím cũ không mở panel giữa
    /// chừng; local monitor bắt tổ hợp tiếp theo (như TinyCast — recorder
    /// không cần event tap hay quyền gì).
    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        unregisterHotkey()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc — hủy
                Task { @MainActor in self.cancelRecording() }
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Phải có ⌘/⌥/⌃ — phím trần va vào gõ chữ bình thường.
            guard !mods.intersection([.command, .option, .control]).isEmpty else { return event }
            let code = Int(event.keyCode)
            let modsRaw = Int(mods.rawValue)
            let chars = event.charactersIgnoringModifiers ?? ""
            Task { @MainActor in
                self.finishRecording(keyCode: code, modifiersRaw: modsRaw, characters: chars)
            }
            return nil
        }
    }

    func cancelRecording() {
        releaseRecordMonitor()
        isRecording = false
        registerHotkey()
    }

    private func finishRecording(keyCode: Int, modifiersRaw: Int, characters: String) {
        let d = UserDefaults.standard
        d.set(keyCode, forKey: "quickSearch.hotkeyCode")
        d.set(modifiersRaw, forKey: "quickSearch.hotkeyModifiers")
        let label = Self.label(keyCode: keyCode, modifiersRaw: modifiersRaw, characters: characters)
        d.set(label, forKey: "quickSearch.hotkeyLabel")
        hotkeyLabel = label
        releaseRecordMonitor()
        isRecording = false
        applySettings()
    }

    private func releaseRecordMonitor() {
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
    }

    /// "⌥Space", "⌘K"… — ký hiệu ⌘⌥⌃⇧ + tên phím.
    nonisolated private static func label(keyCode: Int, modifiersRaw: Int, characters: String) -> String {
        var s = ""
        if modifiersRaw & Int(NSEvent.ModifierFlags.command.rawValue) != 0 { s += "⌘" }
        if modifiersRaw & Int(NSEvent.ModifierFlags.option.rawValue) != 0 { s += "⌥" }
        if modifiersRaw & Int(NSEvent.ModifierFlags.control.rawValue) != 0 { s += "⌃" }
        if modifiersRaw & Int(NSEvent.ModifierFlags.shift.rawValue) != 0 { s += "⇧" }
        let key: String
        if keyCode == 49 {
            key = "Space"
        } else if keyCode == 53 {
            key = "Esc"
        } else if keyCode == 36 {
            key = "↵"
        } else {
            let c = characters.trimmingCharacters(in: .whitespaces).uppercased()
            key = c.isEmpty ? "Key\(keyCode)" : String(c.prefix(1))
        }
        return s + key
    }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        query = ""
        selectedIndex = 0
        QuickSearchEngine.shared.clear()

        let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: QuickSearchPanelView())
        position(p)
        p.makeKeyAndOrderFront(nil)
        panel = p
        isOpen = true
        armPanelMonitors()
    }

    /// Spotlight-style: giữa ngang, lệch lên ~1/4 màn hình, trên màn có trỏ.
    private func position(_ p: NSPanel) {
        let screen = WindowManager.screenUnderPointer()
        let width: CGFloat = 640
        let height: CGFloat = 460
        let frame = screen.visibleFrame
        let x = frame.midX - width / 2
        let y = frame.maxY - height - frame.height * 0.22
        p.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    func close() {
        releasePanelMonitors()
        panel?.orderOut(nil)
        panel = nil
        isOpen = false
        QuickSearchEngine.shared.clear()
    }

    /// View gọi khi ô tìm đổi nội dung — lái sang engine (debounce bên trong).
    func queryChanged(_ text: String) {
        selectedIndex = 0
        QuickSearchEngine.shared.search(query: text)
    }

    private func move(_ delta: Int) {
        let count = QuickSearchEngine.shared.results.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    func executeSelected() {
        let results = QuickSearchEngine.shared.results
        guard results.indices.contains(selectedIndex) else { return }
        let result = results[selectedIndex]
        close()
        result.action()
    }

    // MARK: - Monitors khi panel mở

    private func armPanelMonitors() {
        // ↑/↓/Esc trước khi TextField thấy chúng (panel là key window).
        if panelKeyMonitor == nil {
            panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch Int(event.keyCode) {
                case 53: // Esc
                    Task { @MainActor in self.close() }
                    return nil
                case 126: // ↑
                    Task { @MainActor in self.move(-1) }
                    return nil
                case 125: // ↓
                    Task { @MainActor in self.move(1) }
                    return nil
                default:
                    return event
                }
            }
        }
        // Click ngoài panel → đóng. Cặp global + local theo quy tắc CLAUDE.md:
        // global im lặng khi chính XFinder frontmost.
        if dismissMonitor == nil {
            dismissMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.dismissIfClickedOutside() }
            }
        }
        if localDismissMonitor == nil {
            localDismissMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                Task { @MainActor in self?.dismissIfClickedOutside() }
                return event
            }
        }
    }

    private func dismissIfClickedOutside() {
        guard isOpen, let panel else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) { close() }
    }

    private func releasePanelMonitors() {
        if let panelKeyMonitor { NSEvent.removeMonitor(panelKeyMonitor) }
        panelKeyMonitor = nil
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
        if let localDismissMonitor { NSEvent.removeMonitor(localDismissMonitor) }
        localDismissMonitor = nil
    }
}

// `KeyablePanel` (subclass cho `canBecomeKey`) đã có trong EdgeNotesController —
// tái dùng luôn, không định nghĩa cái thứ hai.