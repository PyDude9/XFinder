import Foundation
import AppKit
import Combine

/// Window operations on public APIs only:
/// - Listing + thumbnails: `CGWindowListCopyWindowInfo` / `CGWindowListCreateImage` (public, no entitlement).
/// - Moving/resizing: AXUIElement (public ApplicationServices framework, but
///   requires the user to grant Accessibility trust — the UI gates on
///   `AXIsProcessTrusted()` and links straight to the Privacy pane instead of
///   faking anything).
/// - Menubar-icon hiding: NO public API exists → callers render the honest
///   placeholder, never a fake toggle.
enum WindowManager {

    struct WindowInfo: Identifiable, Equatable {
        var id: CGWindowID
        var ownerPID: pid_t
        var ownerName: String
        var title: String
        var bounds: CGRect
        var isOnScreen: Bool
    }

    // MARK: - List (public, always works)

    static func listWindows() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var out: [WindowInfo] = []
        for dict in raw {
            guard let owner = dict[kCGWindowOwnerName as String] as? String,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let widNum = dict[kCGWindowNumber as String] as? NSNumber
            else { continue }
            if owner == "XFinder" { continue } // hide self
            let bounds: CGRect
            if let bd = dict[kCGWindowBounds as String] as? NSDictionary,
               let r = CGRect(dictionaryRepresentation: bd) {
                bounds = r
            } else { bounds = .zero }
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            out.append(WindowInfo(id: CGWindowID(widNum.uint32Value), ownerPID: pid,
                                  ownerName: owner, title: title, bounds: bounds,
                                  isOnScreen: true))
        }
        // Most-recently-used first is not exposed; keep layer order, cap for perf.
        return Array(out.prefix(40))
    }

    // MARK: - Thumbnail (public, no entitlement)

    static func thumbnail(windowID: CGWindowID, maxSize: CGFloat = 320) -> NSImage? {
        guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                               windowID, [.bestResolution]) else { return nil }
        let img = NSImage(cgImage: cg, size: .zero)
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxSize / max(w, h))
        img.size = NSSize(width: w * scale, height: h * scale)
        return img
    }

    // MARK: - Activate (public)

    @discardableResult
    static func activate(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activate(options: [.activateAllWindows])
    }

    // MARK: - Accessibility-gated move/resize

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func openAccessibilityPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Screen Recording (needed for live thumbnails on macOS 10.15+)

    /// `CGPreflightScreenCaptureAccess` is the public check; on older systems
    /// it is unavailable, in which case capture is always permitted.
    static var canRecordScreen: Bool {
        if #available(macOS 10.15, *) { return CGPreflightScreenCaptureAccess() }
        return true
    }

    /// Triggers the system prompt the first time; afterwards the user must
    /// flip the switch in System Settings, so open that pane too.
    static func requestScreenRecording() {
        if #available(macOS 10.15, *) { CGRequestScreenCaptureAccess() }
    }

    static func openScreenRecordingPane() {
        requestScreenRecording()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Moves + resizes the frontmost window of `pid` to `rect` (screen coords).
    /// Returns false when untrusted or the app exposes no AX windows.
    @discardableResult
    static func setFrontWindow(pid: pid_t, rect: CGRect) -> Bool {
        guard isTrusted else { return false }
        let appRef = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let win = winRef else {
            // Fall back to the first window if none is focused.
            var winsRef: CFArray?
            guard AXUIElementCopyAttributeValues(appRef, kAXWindowsAttribute as CFString, 0, 1, &winsRef) == .success,
                  let arr = winsRef as? [AXUIElement], let first = arr.first
            else { return false }
            return setAXWindow(first, rect: rect)
        }
        return setAXWindow(win as! AXUIElement, rect: rect)
    }

    private static func setAXWindow(_ win: AXUIElement, rect: CGRect) -> Bool {
        var pos = CGPoint(x: rect.minX, y: rect.minY)
        var size = CGSize(width: rect.width, height: rect.height)
        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size) else { return false }
        let r1 = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posVal)
        let r2 = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
        return r1 == .success && r2 == .success
    }

    // MARK: - Snap targets

    enum SnapTarget: String, CaseIterable, Identifiable {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case maximize, center
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .leftHalf: return "Trái nửa màn hình"
            case .rightHalf: return "Phải nửa màn hình"
            case .topHalf: return "Trên nửa màn hình"
            case .bottomHalf: return "Dưới nửa màn hình"
            case .topLeft: return "Góc trên-trái"
            case .topRight: return "Góc trên-phải"
            case .bottomLeft: return "Góc dưới-trái"
            case .bottomRight: return "Góc dưới-phải"
            case .maximize: return "Toàn màn hình"
            case .center: return "Giữa màn hình"
            }
        }

        func rect(in screen: CGRect) -> CGRect {
            let w = screen.width, h = screen.height, x = screen.minX, y = screen.minY
            switch self {
            case .leftHalf:    return CGRect(x: x, y: y, width: w / 2, height: h)
            case .rightHalf:   return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
            case .topHalf:     return CGRect(x: x, y: y, width: w, height: h / 2)
            case .bottomHalf:  return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
            case .topLeft:     return CGRect(x: x, y: y, width: w / 2, height: h / 2)
            case .topRight:    return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
            case .bottomLeft:  return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
            case .bottomRight: return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
            case .maximize:    return screen
            case .center:
                let cw = min(w * 0.7, 1100), ch = min(h * 0.75, 750)
                return CGRect(x: x + (w - cw) / 2, y: y + (h - ch) / 2, width: cw, height: ch)
            }
        }
    }

    static func mainScreenFrame() -> CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Stage Manager is on. macOS does NOT shrink `visibleFrame` for its strip
    /// (verified: left gap reads 0 with the feature enabled), so a snapped
    /// window would sit on top of the app thumbnails.
    static var isStageManagerEnabled: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?
            .object(forKey: "GloballyEnabled") as? Bool ?? false
    }

    /// Width to keep clear on the left for the Stage Manager strip — enough to
    /// recognise an app icon, not the full expanded thumbnails.
    ///
    /// Two gates, both user-controlled: `reserveStage` turns the clearance off
    /// entirely (some people want the full screen width and accept the
    /// overlap), and `stageInset` tunes how much. Defaults match the previous
    /// hard-coded behaviour so an existing install does not change under the
    /// user's feet.
    static var stageManagerInset: CGFloat {
        guard isStageManagerEnabled else { return 0 }
        let reserve = UserDefaults.standard.object(forKey: "snapzones.reserveStage") as? Bool ?? true
        guard reserve else { return 0 }
        let custom = UserDefaults.standard.object(forKey: "snapzones.stageInset") as? Double
        // Clamp to the slider's own range. A value below 48 pt is too narrow to
        // show an app icon, and an install from before the floor existed can
        // still hold one — clamping here keeps the stored value and the UI in
        // agreement instead of honouring a width the slider cannot express.
        return min(max(CGFloat(custom ?? 68), 48), 140)
    }

    /// `visibleFrame` is in AppKit coordinates (origin bottom-left) while
    /// AXPosition is top-left based — mixing them puts windows under the menu
    /// bar. Convert here so every snap path shares one definition, and reserve
    /// the Stage Manager strip so snapped windows never cover it.
    static func axVisibleFrame(for screen: NSScreen) -> CGRect {
        let full = screen.frame
        let visible = screen.visibleFrame
        let flippedY = full.maxY - visible.maxY
        let inset = stageManagerInset
        return CGRect(x: visible.minX + inset,
                      y: flippedY,
                      width: visible.width - inset,
                      height: visible.height)
    }

    /// Inverse of `axVisibleFrame`: converts a top-left-origin AX rect back
    /// into AppKit's bottom-left-origin space (for NSWindow frames).
    static func axRectToAppKit(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(x: rect.origin.x,
                      y: primary.frame.maxY - rect.origin.y - rect.height,
                      width: rect.width,
                      height: rect.height)
    }

    /// The screen the pointer is on — the one the user means when snapping.
    static func screenUnderPointer() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Focused-window snapping

    /// The frontmost app other than XFinder — snapping targets what the user
    /// was just using, not a dropdown selection.
    static func frontmostOtherApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && !$0.isHidden
        }
    }

    @discardableResult
    static func snapFrontmost(to target: SnapTarget) -> Bool {
        guard isTrusted, let app = frontmostOtherApp() else { return false }
        let rect = target.rect(in: axVisibleFrame(for: screenUnderPointer()))
        return setFrontWindow(pid: app.processIdentifier, rect: rect)
    }
}
