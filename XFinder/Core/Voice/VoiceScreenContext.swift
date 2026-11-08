import AppKit
import ApplicationServices

/// Reads *where* the dictation is happening so the rewrite can be told about it.
///
/// Everything here comes from Accessibility, which the feature already requires for text
/// insertion. That is deliberate: adding a screen-capture requirement just to label a
/// paragraph would be a much bigger permission ask for a much smaller gain.
///
/// Each field is resolved independently and may legitimately be `nil` — an app can expose no
/// window title, and a focused element can refuse to report its selection. The caller treats
/// a missing field as "no context", never as an error.
///
/// Not included, and stated plainly in the docs: a *window thumbnail* for multimodal models.
/// It would need Screen Recording permission on top of Accessibility, and only some of the
/// providers accept images, so it is a later pass rather than something half-wired here.
public enum VoiceScreenContext {

    /// The frontmost application's name, from `NSWorkspace` — no permission needed.
    public static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// The frontmost app's bundle identifier, used to avoid describing XFinder to itself.
    public static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// The focused window's title, via the frontmost application's AX element.
    public static func focusedWindowTitle() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return nil }

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String,
              !title.isEmpty else { return nil }
        return title
    }

    /// The user's current selection, if the focused element will report it.
    ///
    /// This is the one field with a real privacy weight: it can contain anything. It is only
    /// read when the user has explicitly switched selection context on, and it is only ever
    /// sent to the provider the user configured.
    public static func selectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        // 1. Try frontmost application focused element (more reliable on macOS 14+ than systemWide)
        if let front = NSWorkspace.shared.frontmostApplication {
            let appEl = AXUIElementCreateApplication(front.processIdentifier)
            var focusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
               let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                if let text = extractSelectedText(from: focused as! AXUIElement) {
                    return text
                }
            }
        }

        // 2. Fallback to systemWide
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            if let text = extractSelectedText(from: focused as! AXUIElement) {
                return text
            }
        }

        return nil
    }

    private static func extractSelectedText(from element: AXUIElement) -> String? {
        var selectionRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectionRef) == .success,
           let selection = selectionRef as? String {
            let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 1 { return trimmed }
        }
        var range: CFTypeRef?, out: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &range) == .success, let r = range,
           AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, r, &out) == .success,
           let s = out as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 1 { return trimmed }
        }
        return nil
    }

    /// Assemble the context according to the user's switches.
    public static func capture(includeApp: Bool, includeSelection: Bool) -> RefineContext? {
        guard includeApp || includeSelection else { return nil }

        // XFinder is frontmost while the settings page's own test runs. Describing XFinder to
        // the model would be actively misleading, so the app name is dropped in that case.
        let bundleID = frontmostBundleID()
        let isSelf = bundleID == Bundle.main.bundleIdentifier

        let context = RefineContext(
            appName: (includeApp && !isSelf) ? frontmostAppName() : nil,
            windowTitle: (includeApp && !isSelf) ? focusedWindowTitle() : nil,
            selectedText: includeSelection ? selectedText() : nil
        )
        return context.isEmpty ? nil : context
    }
}
