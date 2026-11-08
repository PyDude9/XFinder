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
    public struct CapturedItem: Sendable {
        public let types: [(NSPasteboard.PasteboardType, Data)]
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

        // Web browsers, Electron apps (like Orca, VS Code, Slack), and terminals do not
        // reliably dispatch DOM input events when text is mutated through AXSelectedTextAttribute.
        // For those, always prefer Pasteboard + ⌘V so the web framework receives the paste event.
        if shouldSkipAccessibility(for: NSWorkspace.shared.frontmostApplication) {
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }

        let element = focused as! AXUIElement
        if isWebOrNonNativeElement(element) {
            return false
        }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    private func shouldSkipAccessibility(for app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if let bundleID = app.bundleIdentifier?.lowercased() {
            let patterns = [
                "orca", "electron", "chrome", "safari", "firefox", "brave", "edge",
                "slack", "discord", "vscode", "code", "cursor", "obsidian",
                "terminal", "iterm", "ghostty", "kitty", "alacritty", "warp"
            ]
            if patterns.contains(where: { bundleID.contains($0) }) {
                return true
            }
        }
        if let bundleURL = app.bundleURL {
            let frameworksURL = bundleURL.appendingPathComponent("Contents/Frameworks")
            if FileManager.default.fileExists(atPath: frameworksURL.appendingPathComponent("Electron Framework.framework").path) {
                return true
            }
        }
        return false
    }

    private func isWebOrNonNativeElement(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            if role == "AXWebArea" || role == "AXLink" || role == "AXGroup" {
                return true
            }
        }
        var domRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXDOMIdentifier" as CFString, &domRef) == .success {
            return true
        }
        return false
    }

    // MARK: - Tier 2: Pasteboard + ⌘V

    private func insertViaPasteboard(text: String) {
        lock.lock()
        let restore = captured
        lock.unlock()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let vKeyCode: CGKeyCode = 9
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        guard restoresClipboard, !restore.isEmpty else { return }
        // 650 ms gives Electron and WebKit renderers sufficient time to read the pasteboard over IPC
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            TypingSink.restorePasteboard(restore)
        }
    }

    // MARK: - Pasteboard capture / restore

    public static func capturePasteboard() -> [CapturedItem] {
        guard let items = NSPasteboard.general.pasteboardItems else { return [] }
        return items.compactMap { item in
            let types = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return types.isEmpty ? nil : CapturedItem(types: types)
        }
    }

    public static func restorePasteboard(_ items: [CapturedItem]) {
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
