import AppKit
import Carbon.HIToolbox

/// Global typing-buffer snippet auto-expander (`CGEvent` tap).
/// Zero idle cost: the tap exists ONLY when `clipboard.snippetsAutoExpand` is ON, at least one
/// snippet is enabled, and Accessibility is granted. Always skips `IsSecureEventInputEnabled()`.
@MainActor
@Observable
final class TextSnippetExpander {
    static let shared = TextSnippetExpander()

    enum State: Equatable {
        case off
        case needsAccessibility
        case noSnippets
        case running
    }

    private(set) var state: State = .off

    /// ONE reader (matches `SettingsDetailView.swift`'s `@AppStorage("clipboard.snippetsAutoExpand")` default `false`).
    var autoExpandEnabled: Bool {
        UserDefaults.standard.object(forKey: "clipboard.snippetsAutoExpand") as? Bool ?? false
    }

    @ObservationIgnored private var eventTap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var buffer = TextSnippetRules.TypingBuffer()
    @ObservationIgnored private var activeSnippets: [TextSnippet] = []

    private init() {}

    func applySettings() {
        let enabledSnippets = TextSnippetStore.shared.snippets.filter(\.isEnabled)
        guard autoExpandEnabled else {
            activeSnippets = []
            teardownTap()
            state = .off
            return
        }
        guard !enabledSnippets.isEmpty else {
            activeSnippets = []
            teardownTap()
            state = .noSnippets
            return
        }
        guard AXIsProcessTrusted() else {
            activeSnippets = []
            teardownTap()
            state = .needsAccessibility
            return
        }
        activeSnippets = enabledSnippets
        setupTap()
        state = eventTap != nil ? .running : .needsAccessibility
    }

    private func setupTap() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            if event.getIntegerValueField(.eventSourceUserData) == TextSnippetRules.syntheticTag {
                return Unmanaged.passUnretained(event)
            }
            let expander = Unmanaged<TextSnippetExpander>.fromOpaque(refcon).takeUnretainedValue()
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.rawValue
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            if type == .keyDown {
                event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
            }
            let typed = length > 0 ? String(utf16CodeUnits: chars, count: min(length, 8)) : ""
            // Run loop source is attached to CFRunLoopGetMain(), so callback executes on main thread.
            let swallow = MainActor.assumeIsolated {
                expander.handle(type: type, keyCode: keyCode, flags: flags, typed: typed)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        buffer.clear()
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        buffer.clear()
    }

    private func handle(type: CGEventType, keyCode: Int, flags: UInt64, typed: String) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            buffer.clear()
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            buffer.clear()
            return false
        }
        guard type == .keyDown else { return false }

        if IsSecureEventInputEnabled() {
            buffer.clear()
            return false
        }

        if TextSnippetRules.shouldResetBuffer(keyCode: keyCode, flags: flags) {
            buffer.clear()
            return false
        }

        if keyCode == TextSnippetRules.keyCodeBackspace {
            buffer.backspace()
            return false
        }

        guard !typed.isEmpty,
              !typed.unicodeScalars.contains(where: { $0.value < 0x20 }) else {
            buffer.clear()
            return false
        }

        buffer.append(typed)

        if let matched = TextSnippetRules.match(buffer: buffer.text, snippets: activeSnippets) {
            buffer.clear()
            Task { @MainActor [weak self] in
                self?.performExpansion(matched)
            }
            return true
        }
        return false
    }

    private func performExpansion(_ snippet: TextSnippet) {
        let pb = NSPasteboard.general
        let savedClip = pb.string(forType: .string)
        let expanded = TextSnippetRules.expand(snippet.expansion, now: Date(), clipboardText: savedClip)

        let backspaces = max(0, snippet.trigger.count - 1)
        if backspaces > 0, let source = CGEventSource(stateID: .hidSystemState) {
            for _ in 0..<backspaces {
                if let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(TextSnippetRules.keyCodeBackspace), keyDown: true),
                   let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(TextSnippetRules.keyCodeBackspace), keyDown: false) {
                    down.setIntegerValueField(.eventSourceUserData, value: TextSnippetRules.syntheticTag)
                    up.setIntegerValueField(.eventSourceUserData, value: TextSnippetRules.syntheticTag)
                    down.post(tap: .cgSessionEventTap)
                    up.post(tap: .cgSessionEventTap)
                }
            }
        }

        pb.clearContents()
        pb.setString(expanded, forType: .string)
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let writtenChangeCount = pb.changeCount

        // Virtual key 9 = 'v'
        if let source = CGEventSource(stateID: .hidSystemState),
           let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true),
           let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false) {
            vDown.flags = .maskCommand
            vUp.flags = .maskCommand
            vDown.setIntegerValueField(.eventSourceUserData, value: TextSnippetRules.syntheticTag)
            vUp.setIntegerValueField(.eventSourceUserData, value: TextSnippetRules.syntheticTag)
            vDown.post(tap: .cgSessionEventTap)
            vUp.post(tap: .cgSessionEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { @MainActor in
                let currentPB = NSPasteboard.general
                guard currentPB.changeCount == writtenChangeCount else { return }
                currentPB.clearContents()
                if let savedClip {
                    currentPB.setString(savedClip, forType: .string)
                    currentPB.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
                }
            }
        }
    }
}
