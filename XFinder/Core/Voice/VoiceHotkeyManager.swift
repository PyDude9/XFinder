import AppKit
import Carbon

/// The system-wide event tap that drives a dictation session.
///
/// It owns the *keys* — which key starts a session, whether it is hold or toggle, and the
/// three session keys (Space = insert raw now, Esc = cancel, Return = accept the reviewed
/// text). It knows nothing about audio or models; `VoiceManager` owns the flow.
///
/// Why a `CGEvent` tap rather than `NSEvent.addGlobalMonitorForEvents`: a monitor can only
/// observe, so it could never *consume* Escape while a session is live — the keystroke would
/// also reach the application and, for instance, close a dialog the user was working in. The
/// tap can drop it. (CLAUDE.md's global-monitor rule still applies to the controllers that
/// use monitors; this one never did.)
///
/// The tap is armed only while the feature is enabled **and** Accessibility is granted, so an
/// idle app installs no tap and burns no CPU.
@MainActor
public final class VoiceHotkeyManager: ObservableObject {
    public static let shared = VoiceHotkeyManager()

    /// Where the session currently is. Drives which keys are consumed.
    public enum SessionState: Equatable {
        case idle
        case listening
        case refining
        case reviewing
    }

    public private(set) var state: SessionState = .idle
    public private(set) var isTriggerDown = false

    public var triggerKey: VoiceTriggerKey = .rightOption
    public var activationMode: VoiceActivationMode = .hold

    public var onStart: (() -> Void)?
    public var onStop: (() -> Void)?
    public var onCancel: (() -> Void)?
    /// Space while refining — insert the raw transcription without waiting for the model.
    public var onSkipRewrite: (() -> Void)?
    public var onReviewAccept: (() -> Void)?
    public var onReviewReject: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    public var isTapInstalled: Bool { eventTap != nil }

    public func start() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { return }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<VoiceHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTriggerDown = false
        state = .idle
    }

    /// Called by `VoiceManager` as the session advances, so the tap consumes the right keys.
    public func setState(_ newState: SessionState) {
        state = newState
    }

    // MARK: - Event handling

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that takes too long. Re-arm it and pass the event on —
        // this is the "event-tap recovery" the brief asks to preserve.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.eventTap, CFMachPortIsValid(tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .keyDown:
            return handleKeyDown(keyCode: keyCode, event: event)
        case .flagsChanged:
            return handleFlagsChanged(keyCode: keyCode, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// The three session keys. Only the ones that belong to the current state are consumed,
    /// so Space still types a space in the document when no session is running.
    private func handleKeyDown(keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch state {
        case .reviewing:
            if keyCode == 36 || keyCode == 76 {   // Return / keypad Enter
                state = .idle
                Task { @MainActor in self.onReviewAccept?() }
                return nil
            }
            if keyCode == 53 {                    // Escape
                state = .idle
                Task { @MainActor in self.onReviewReject?() }
                return nil
            }
            // Any other key means the user has moved on; treat it as "keep editing" and
            // discard the review rather than holding a stale card on screen.
            if keyCode != triggerKey.keyCode {
                state = .idle
                Task { @MainActor in self.onReviewReject?() }
            }
            return Unmanaged.passUnretained(event)

        case .refining:
            if keyCode == 49 {                    // Space — insert the raw text now
                Task { @MainActor in self.onSkipRewrite?() }
                return nil
            }
            if keyCode == 53 {                    // Escape — abandon
                state = .idle
                Task { @MainActor in self.onCancel?() }
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .listening:
            if keyCode == 53 {                    // Escape — abandon
                state = .idle
                Task { @MainActor in self.onCancel?() }
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .idle:
            // Toggle mode starts on the trigger's own key-down. A modifier never produces a
            // plain keyDown, so this branch is reached only for non-modifier triggers.
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard keyCode == triggerKey.keyCode else { return Unmanaged.passUnretained(event) }

        let isDown = (event.flags.rawValue & triggerKey.modifierMask) != 0

        if isDown && !isTriggerDown {
            isTriggerDown = true
            switch state {
            case .idle:
                state = .listening
                Task { @MainActor in self.onStart?() }
            case .listening:
                // A second press while already listening only means something in toggle mode.
                if activationMode == .toggle {
                    state = .idle
                    Task { @MainActor in self.onStop?() }
                }
            default:
                break
            }
        } else if !isDown && isTriggerDown {
            isTriggerDown = false
            if activationMode == .hold, state == .listening {
                state = .idle
                Task { @MainActor in self.onStop?() }
            }
        }

        // The trigger is a modifier; passing it through keeps ⌥-combinations working in the
        // application underneath. Consuming it here would break the user's own shortcuts.
        return Unmanaged.passUnretained(event)
    }
}
