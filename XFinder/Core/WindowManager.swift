import Foundation
import AppKit
import Combine
import ScreenCaptureKit

/// Window operations on public APIs only:
/// - Listing: `CGWindowListCopyWindowInfo` (public, no entitlement).
/// - Thumbnails: **ScreenCaptureKit** (`SCScreenshotManager`). The old
///   `CGWindowListCreateImage` is *unavailable* on the macOS 26/27 SDK and
///   returns nil at runtime there — that was the cause of the blank Dock
///   preview and blank ⌘-Tab switcher. Requires Screen Recording permission.
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
        guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        // Same hidden-app rule as the switcher's lister, read through its single accessor.
        let showHidden = WindowPreviewStore.showsHiddenWindows
        var minimized = PerPIDMemo(axMinimizedWindowIDs)
        var out: [WindowInfo] = []
        for dict in raw {
            guard let owner = dict[kCGWindowOwnerName as String] as? String,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let widNum = dict[kCGWindowNumber as String] as? NSNumber
            else { continue }
            let wid = CGWindowID(widNum.uint32Value)
            let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? (dict[kCGWindowLayer as String] as? Int ?? -1)
            let alpha = (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? (dict[kCGWindowAlpha as String] as? Double ?? 1.0)
            let sharing = (dict[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 1

            let bounds: CGRect
            if let bd = dict[kCGWindowBounds as String] as? NSDictionary,
               let r = CGRect(dictionaryRepresentation: bd) {
                bounds = r
            } else { bounds = .zero }

            let runningApp = NSRunningApplication(processIdentifier: pid)
            let bundleID = runningApp?.bundleIdentifier ?? owner
            let isHidden = runningApp?.isHidden == true
            let isOnScreen = (dict[kCGWindowIsOnscreen as String] as? Bool == true) || ((dict[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true)

            // LOẠI HOÀN TOÀN:
            if layer != 0 { continue }
            if alpha == 0 { continue }
            if sharing == 0 { continue }
            if bounds.width < 50 || bounds.height < 50 { continue }
            if bundleID == "com.apple.dock" || bundleID == "com.apple.WindowManager" || owner == "XFinder" || owner == "WindowManager" || owner == "Window Server" || owner == "Dock" { continue }
            if !WindowPreviewStore.listsWindow(ofHiddenApp: isHidden, showHidden: showHidden) { continue }
            if let app = runningApp, app.activationPolicy != .regular { continue }

            if !isOnScreen && minimized(pid).contains(wid) { continue }

            let title = (dict[kCGWindowName as String] as? String) ?? ""
            out.append(WindowInfo(id: wid, ownerPID: pid, ownerName: owner, title: title, bounds: bounds, isOnScreen: isOnScreen))
        }
        return Array(out.prefix(40))
    }

    // MARK: - Thumbnail (public, no entitlement)

    /// Window thumbnail via **ScreenCaptureKit**.
    ///
    /// `CGWindowListCreateImage` — what this used to call — is now marked
    /// *unavailable* by the macOS 26/27 SDK ("Please use ScreenCaptureKit
    /// instead"). The app kept compiling only because the deployment target is
    /// 14.0, but at runtime it returned nil, which is exactly why the Dock
    /// hover preview and the ⌘-Tab switcher both rendered empty placeholders.
    ///
    /// Verified with a probe on macOS 27.0 (26A428): SCK captured 3/3 windows.
    /// Needs Screen Recording permission, same as before.
    static func thumbnail(windowID: CGWindowID, maxSize: CGFloat = 800) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            guard let win = content.windows.first(where: { $0.windowID == windowID }),
                  win.frame.width > 1, win.frame.height > 1 else { return nil }

            let cfg = SCStreamConfiguration()
            cfg.width = max(100, Int(win.frame.width * 2))
            cfg.height = max(100, Int(win.frame.height * 2))
            cfg.scalesToFit = false
            cfg.showsCursor = false
            cfg.capturesAudio = false
            cfg.captureResolution = .best
            let filter = SCContentFilter(desktopIndependentWindow: win)

            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: cfg)
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            guard w > 0, h > 0 else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        } catch {
            return nil
        }
    }

    /// Capture several windows in one `SCShareableContent` round trip.
    ///
    /// Calling `thumbnail(windowID:)` in a loop re-queries the shareable
    /// content for every window, which is the slow part — one query plus N
    /// captures is markedly faster for a Dock preview holding several windows.
    static func thumbnails(windowIDs: [CGWindowID],
                           maxSize: CGFloat = 800) async -> [(CGWindowID, NSImage)] {
        guard !windowIDs.isEmpty else { return [] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            let wanted = Set(windowIDs)
            var out: [(CGWindowID, NSImage)] = []
            for win in content.windows where wanted.contains(win.windowID) {
                guard win.frame.width > 1, win.frame.height > 1 else { continue }
                let cfg = SCStreamConfiguration()
                cfg.width = max(100, Int(win.frame.width * 2))
                cfg.height = max(100, Int(win.frame.height * 2))
                cfg.scalesToFit = false
                cfg.showsCursor = false
                cfg.capturesAudio = false
                cfg.captureResolution = .best
                let filter = SCContentFilter(desktopIndependentWindow: win)
                guard let cg = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: cfg) else { continue }
                let w = CGFloat(cg.width), h = CGFloat(cg.height)
                guard w > 0, h > 0 else { continue }
                out.append((win.windowID, NSImage(cgImage: cg, size: NSSize(width: w, height: h))))
            }
            return out
        } catch {
            return []
        }
    }

    // MARK: - Activate (public)

    @discardableResult
    static func activate(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if app.isHidden { app.unhide() }
        return app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    /// Opens the System Settings pane that controls Finder extensions.
    ///
    /// macOS 26/27 folded this into **Login Items & Extensions**; the old
    /// `com.apple.ExtensionsPreferences` identifier no longer lands on the
    /// right place, which is why the button appeared to do nothing useful.
    /// Tries the current identifier first, then the legacy one, then System
    /// Settings itself so the button is never dead.
    ///
    /// Note: no URL can deep-link straight to the *Finder extension* row —
    /// macOS only exposes the pane. The UI says which switch to flip.
    @discardableResult
    static func openFinderExtensionsPane() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return true }
        }
        return NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Opens System Settings ▸ Keyboard ▸ Keyboard Shortcuts.
    ///
    /// A gesture that dispatches a system action posts the chord the user's own
    /// `com.apple.symbolichotkeys` binds to it (`SpaceBinding`). When that action is
    /// **unbound**, there is nothing to post and the page must offer the fix instead of a
    /// dead gesture — this is that fix. Same shape as `openFinderExtensionsPane`: try the
    /// current pane identifier, then the legacy one, then System Settings itself, so the
    /// button is never dead.
    @discardableResult
    static func openKeyboardShortcutsPane() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return true }
        }
        return NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Raise ONE window, not the whole app.
    ///
    /// `NSRunningApplication.activate` brings every window of the app forward,
    /// which is wrong for a per-window switcher: picking the 3rd Safari window
    /// would raise all of them and leave an arbitrary one on top. AX can raise a
    /// single window, so match the CoreGraphics window by title+position and
    /// send it `AXRaise`. Falls back to app activation when AX is unavailable,
    /// so the switcher still works without the permission — just less precisely.
    /// Phase C: the switcher's Q. Presses the window's own close button through Accessibility — the
    /// same thing the user's click does, so "save changes?" sheets still appear. Matched by window id
    /// first (`_AXUIElementGetWindow`), then by title/position like `raiseWindow`.
    @discardableResult
    static func closeWindow(_ info: WindowInfo) -> Bool {
        guard isTrusted else { return false }
        let appEl = AXUIElementCreateApplication(info.ownerPID)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else { return false }
        let byID = axWindows.first { el in var wid: CGWindowID = 0; return axGetWindowID(el, &wid) == .success && wid == info.id }
        let target = byID ?? axWindows.first { el in
            var titleRef: CFTypeRef?
            let title = AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef) == .success ? (titleRef as? String ?? "") : ""
            if !info.title.isEmpty, title == info.title { return true }
            var posRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success, let posVal = posRef else { return false }
            var point = CGPoint.zero
            guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point) else { return false }
            return abs(point.x - info.bounds.origin.x) < 4 && abs(point.y - info.bounds.origin.y) < 4
        }
        guard let target else { return false }
        var buttonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target, kAXCloseButtonAttribute as CFString, &buttonRef) == .success,
              let button = buttonRef else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func raiseWindow(_ info: WindowInfo) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: info.ownerPID) else { return false }
        if app.isHidden { app.unhide() }

        guard isTrusted else {
            return app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        let appEl = AXUIElementCreateApplication(info.ownerPID)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty {
            // By window id first: two windows may share a title (two "Untitled" documents).
            let byID = axWindows.first { el in var wid: CGWindowID = 0; return axGetWindowID(el, &wid) == .success && wid == info.id }
            let target = byID ?? axWindows.first { el in
                var titleRef: CFTypeRef?
                let title = AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef) == .success
                    ? (titleRef as? String ?? "") : ""
                if !info.title.isEmpty, title == info.title { return true }

                var posRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
                      let posVal = posRef else { return false }
                var point = CGPoint.zero
                guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point) else { return false }
                return abs(point.x - info.bounds.origin.x) < 4 && abs(point.y - info.bounds.origin.y) < 4
            } ?? axWindows[0]

            // If minimized, unminimize it
            var isMinRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &isMinRef) == .success,
               (isMinRef as? Bool) == true {
                AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }

            AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }

        return app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    // MARK: - Accessibility-gated move/resize

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func openAccessibilityPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Nhắc macOS đưa XFinder vào danh sách Trợ năng (System Settings →
    /// Privacy → Accessibility hiện sẵn dòng XFinder, người dùng chỉ bật
    /// công tắc). Trả về trạng thái tin cậy *hiện tại*.
    ///
    /// Dùng literal "AXTrustedCheckOptionPrompt" thay vì hằng
    /// `kAXTrustedCheckOptionPrompt`: hằng đó là global var cũ kiểu Carbon
    /// (`Unmanaged<CFString>`), bị Swift 6 chặn ở chính tham chiếu — còn giá
    /// trị của nó chỉ là chuỗi này.
    @discardableResult
    static func requestAccessibilityTrust() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
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

    /// Một chạm xin cả hai quyền chạm màn chính (Trợ năng + Ghi màn hình):
    /// gọi hộp thoại hệ thống, rồi mở pane nếu vẫn chưa được cấp.
    static func requestAllPermissions() {
        _ = requestAccessibilityTrust()
        if #available(macOS 10.15, *) { CGRequestScreenCaptureAccess() }
        if !AXIsProcessTrusted() { openAccessibilityPane() }
        if #available(macOS 10.15, *), !CGPreflightScreenCaptureAccess() {
            openScreenRecordingPane()
        }
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
            else { DiagnosticsLog.record("snap", "noWindow"); return false }
            return setWindow(first, rect: rect)
        }
        return setWindow(win as! AXUIElement, rect: rect)
    }

    /// Internal since SNAPMEM: `SnapMemoryController` replays frames through the same setter.
    static func setWindow(_ win: AXUIElement, rect: CGRect) -> Bool {
        var pos = CGPoint(x: rect.minX, y: rect.minY)
        var size = CGSize(width: rect.width, height: rect.height)
        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size) else { return false }
        let r1 = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posVal)
        let r2 = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
        if r1 != .success || r2 != .success {
            // The AX error numbers only (e.g. -25204 cannot complete, -25205 not supported) — never the window.
            DiagnosticsLog.record("snap", "axError", detail: "position \(r1.rawValue) size \(r2.rawValue)")
        }
        return r1 == .success && r2 == .success
    }

    // MARK: - Snap targets

    /// The geometry lives in the pure `SnapLayout` (tested directly since B3); this name stays so the
    /// call sites read as before.
    typealias SnapTarget = SnapLayout.Target

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
        SnapLayout.stageInset(
            stageManagerOn: isStageManagerEnabled,
            reserve: UserDefaults.standard.object(forKey: "snapzones.reserveStage") as? Bool ?? true,
            custom: UserDefaults.standard.object(forKey: "snapzones.stageInset") as? Double)
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

    @discardableResult @MainActor
    static func snapFrontmost(to target: SnapTarget) -> Bool {
        // Our own Browser windows need native AppKit writes; AX targets another process.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let browser = NSApp.keyWindow as? BrowserWindow {
            guard !browser.styleMask.contains(.fullScreen) else { return false }
            let screen = screenUnderPointer()
            let targetFrame = axRectToAppKit(target.rect(in: axVisibleFrame(for: screen)))
            let contentMinimum = browser.frameRect(forContentRect: CGRect(origin: .zero, size: browser.contentMinSize)).size
            let minimum = CGSize(width: max(browser.minSize.width, contentMinimum.width),
                                 height: max(browser.minSize.height, contentMinimum.height))
            browser.setFrame(SnapLayout.constrainedFrame(targetFrame, minimum: minimum, visibleFrame: screen.visibleFrame),
                             display: true)
            return true
        }
        guard isTrusted, let app = frontmostOtherApp() else { return false }
        let screen = screenUnderPointer()
        let rect = target.rect(in: axVisibleFrame(for: screen))
        let ok = setFrontWindow(pid: app.processIdentifier, rect: rect)
        // SNAPMEM rule 1: a snap the user asked for is the only way an app enters layout memory.
        if ok { SnapMemoryController.shared.didSnap(app: app, target: target, screen: screen) }
        return ok
    }
}

extension SnapLayout.Target {
    var titleVI: String { L10n.t(titleKey) }
}
