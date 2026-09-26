import AppKit
import ApplicationServices
import Carbon

/// TypingSink implements system-wide text insertion into the currently focused application.
/// Tier 1: Accessibility API (kAXSelectedTextAttribute / kAXValueAttribute)
/// Tier 2: Fallback via NSPasteboard simulation (⌘V) with clipboard snapshot restoration.
public final class TypingSink: @unchecked Sendable, TypingSinkProtocol {
    public static let shared = TypingSink()

    private let lock = NSLock()
    private var lastSnapshot: String = ""

    public init() {}

    public func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        let currentClip = NSPasteboard.general.string(forType: .string) ?? ""
        lastSnapshot = currentClip
        return currentClip
    }

    public func applyPartial(_ text: String) {
        // Partial text is rendered through VoiceGhostOverlay
    }

    public func commit(_ text: String) {
        guard !text.isEmpty else { return }

        // Tier 1: Try Accessibility API direct insertion
        if insertViaAccessibility(text: text) {
            return
        }

        // Tier 2: Fallback via simulated Pasteboard ⌘V
        insertViaPasteboard(text: text)
    }

    public func rollback() {
        // If needed, restore saved clipboard
        lock.lock()
        let snap = lastSnapshot
        lock.unlock()

        if !snap.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(snap, forType: .string)
        }
    }

    // MARK: - Tier 1: Accessibility API

    private func insertViaAccessibility(text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)

        guard result == .success, let focusedRef = focusedElementRef else {
            return false
        }

        let focusedElement = focusedRef as! AXUIElement
        var settable: DarwinBoolean = false

        // Check if kAXSelectedTextAttribute is supported and settable
        if AXUIElementIsAttributeSettable(focusedElement, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue {
            let error = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if error == .success {
                return true
            }
        }

        return false
    }

    // MARK: - Tier 2: Pasteboard + Cmd+V Fallback

    private func insertViaPasteboard(text: String) {
        let pboard = NSPasteboard.general
        let previousItems = pboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type, data)
        } ?? []

        // Set text into pasteboard
        pboard.clearContents()
        pboard.setString(text, forType: .string)

        // Synthesize ⌘V (keyCode 9 is 'V')
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Restore previous clipboard after 180ms so the target app has time to ingest the paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let pb = NSPasteboard.general
            pb.clearContents()
            for (type, data) in previousItems {
                pb.setData(data, forType: type)
            }
        }
    }
}
