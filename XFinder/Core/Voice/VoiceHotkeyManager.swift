import AppKit
import Carbon

/// Global event tap interceptor that detects press-and-hold of Right Option (keyCode 61)
/// and Escape (keyCode 53) cancellation.
@MainActor
public final class VoiceHotkeyManager: ObservableObject {
    public static let shared = VoiceHotkeyManager()

    public var isHolding = false
    public var targetKeyCode: Int64 = 61 // Right Option by default (Left Option is 58)

    public var onHoldStart: (() -> Void)?
    public var onHoldEnd: (() -> Void)?
    public var onCancel: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    public func start() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { return }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
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
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isHolding = false
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Cancel on Escape while holding
        if isHolding && type == .keyDown && keyCode == 53 {
            isHolding = false
            Task { @MainActor in
                self.onCancel?()
            }
            return nil // consume Escape
        }

        if type == .flagsChanged && keyCode == targetKeyCode {
            let isOptionPressed = event.flags.contains(.maskAlternate)
            if isOptionPressed && !isHolding {
                isHolding = true
                Task { @MainActor in
                    self.onHoldStart?()
                }
            } else if !isOptionPressed && isHolding {
                isHolding = false
                Task { @MainActor in
                    self.onHoldEnd?()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
