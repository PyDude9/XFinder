import AppKit
import ApplicationServices
import Carbon

/// Inserts text into whatever application currently has focus.
///
/// Two tiers, in order:
///
/// 1. **Accessibility** — write `kAXSelectedTextAttribute` on the focused element. This does
///    not touch the clipboard at all, so the user's clipboard survives untouched, and it is
///    the only path that works when the clipboard is holding something they still need.
/// 2. **Pasteboard + ⌘V** — set the text, post ⌘V, then restore what was there. The restore
///    is scheduled 180 ms later because the target application reads the pasteboard
///    asynchronously; restoring immediately would paste the *old* contents.
///
/// The earlier version snapshotted only the plain-text flavour of the clipboard, so cancelling
/// a session after a paste destroyed a copied image or a rich-text selection. The snapshot is
/// now the full list of pasteboard items, each with all of its types.
public final class TypingSink: @unchecked Sendable, TypingSinkProtocol {
    public static let shared = TypingSink()

    /// One captured pasteboard item: every type it carried, with its bytes.
    private struct CapturedItem {
        let types: [(NSPasteboard.PasteboardType, Data)]
    }

    private let lock = NSLock()
    private var captured: [CapturedItem] = []

    /// When off, the dictated text is left on the clipboard after a paste. Some users want
    /// that (the text is then one ⌘V away in another app); the default is to restore.
    public var restoresClipboard: Bool = true

    public init() {}

    // MARK: - TypingSinkProtocol

    public func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        captured = TypingSink.capturePasteboard()
        // The protocol asks for the text that was on the clipboard. It is returned for
        // compatibility; `captured` is the authoritative copy, because restoring only the
        // string flavour would destroy a copied image or a rich-text selection.
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    public func applyPartial(_ text: String) {
        // Partial text never reaches the document — it is shown in the HUD. Inserting and
        // deleting on every partial result would fight the user's own typing.
    }

    public func commit(_ text: String) {
        guard !text.isEmpty else { return }
        if insertViaAccessibility(text: text) { return }
        insertViaPasteboard(text: text)
    }

    /// Put the clipboard back the way it was before the session.
    public func rollback() {
        lock.lock()
        let items = captured
        lock.unlock()
        guard restoresClipboard, !items.isEmpty else { return }
        TypingSink.restorePasteboard(items)
    }

    // MARK: - Tier 1: Accessibility

    private func insertViaAccessibility(text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }

        let element = focused as! AXUIElement
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    // MARK: - Tier 2: Pasteboard + ⌘V

    private func insertViaPasteboard(text: String) {
        lock.lock()
        let restore = captured
        lock.unlock()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

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

        guard restoresClipboard, !restore.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            TypingSink.restorePasteboard(restore)
        }
    }

    // MARK: - Pasteboard capture / restore

    private static func capturePasteboard() -> [CapturedItem] {
        guard let items = NSPasteboard.general.pasteboardItems else { return [] }
        return items.compactMap { item in
            let types = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return types.isEmpty ? nil : CapturedItem(types: types)
        }
    }

    private static func restorePasteboard(_ items: [CapturedItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let restored = items.map { captured -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in captured.types { item.setData(data, forType: type) }
            return item
        }
        guard !restored.isEmpty else { return }
        pasteboard.writeObjects(restored)
    }
}
