import AppKit
import SwiftUI
import ApplicationServices

/// Vùng bắt dính — snapping the *focused* window, two ways:
///
/// 1. **Drag to a screen edge.** While the left button is down, a window drag
///    near an edge shows a translucent zone overlay; releasing there snaps.
///    Detected by polling `NSEvent.pressedMouseButtons` (no event tap needed).
/// 2. **Global hotkeys** ⌃⌥← → ↑ ↓ and ⌃⌥Return, via a CGEvent tap.
///
/// Both paths move another app's window, so both need Accessibility trust; the
/// page shows the grant flow instead of dead controls when it is missing.
@MainActor
@Observable
final class SnapZoneController {
    static let shared = SnapZoneController()

    private(set) var isRunning = false
    var lastOutcome: String?

    private var dragMonitor: Any?
    private var overlay: NSWindow?
    private var activeZone: WindowManager.SnapTarget?
    private var wasDragging = false
    /// Whether the in-flight drag started on a window's title bar. Evaluated
    /// once per drag so a mid-drag AX query cannot flip the verdict.
    private var dragIsWindowMove = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: Settings (read at point of use)

    private var dragEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapzones.dragEnabled") as? Bool ?? true
    }
    private var hotkeysEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapzones.hotkeysEnabled") as? Bool ?? true
    }
    /// How close to the edge (points) counts as a snap gesture.
    private var edgeMargin: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: "snapzones.edgeMargin") as? Double ?? 20)
    }

    /// Master gate from the page header. Off ⇒ no timer, no event tap.
    private var featureEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapzones.enabled") as? Bool ?? true
    }

    func applySettings() {
        guard featureEnabled, WindowManager.isTrusted else {
            stop()
            isRunning = false
            return
        }
        if dragEnabled { startDragWatch() } else { stopDragWatch() }
        if hotkeysEnabled { startHotkeys() } else { stopHotkeys() }
        isRunning = dragMonitor != nil || eventTap != nil
    }

    func stop() {
        stopDragWatch()
        stopHotkeys()
        isRunning = false
    }

    // MARK: Drag-to-edge

    /// Event-driven, not a constant poll. A global mouse monitor wakes the
    /// controller only while a drag is actually in flight; the old 0.06 s timer
    /// ran ~17×/s forever and was measurably the app's largest idle CPU cost.
    /// Deliberately global-ONLY — the documented exception to the "always pair
    /// a global monitor with a local one" rule in CLAUDE.md Part 3c.
    /// Snapping targets `frontmostOtherApp()`, which excludes XFinder by
    /// construction, so a drag of our own window has nothing to snap. Adding a
    /// local monitor here would only burn CPU on drags we must ignore.
    private func startDragWatch() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] _ in
            Task { @MainActor in self?.dragTick() }
        }
    }

    private func stopDragWatch() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        hideOverlay()
        wasDragging = false
    }

    private func dragTick() {
        let buttonDown = NSEvent.pressedMouseButtons & 1 == 1
        let mouse = NSEvent.mouseLocation

        if buttonDown {
            // Only a genuine *window* drag may snap. A press that began
            // anywhere else — selecting text, dragging a file, drawing in an
            // app — must never snap, so qualify the gesture once at press
            // time and remember that verdict for the rest of the drag.
            if !wasDragging {
                wasDragging = true
                dragIsWindowMove = beganOnWindowTitleBar(at: mouse)
            }
            guard dragIsWindowMove else { return }

            let screen = WindowManager.screenUnderPointer()
            if let zone = zone(for: mouse, on: screen) {
                if zone != activeZone {
                    activeZone = zone
                    showOverlay(zone: zone, on: screen)
                }
            } else {
                activeZone = nil
                hideOverlay()
            }
            return
        }

        // Button released — commit if a zone was highlighted.
        if wasDragging {
            wasDragging = false
            let wasWindowMove = dragIsWindowMove
            dragIsWindowMove = false
            guard wasWindowMove else { return }
            if let zone = activeZone {
                hideOverlay()
                activeZone = nil
                let ok = WindowManager.snapFrontmost(to: zone)
                lastOutcome = ok
                    ? "Đã đưa cửa sổ vào “\(zone.titleVI)”."
                    : "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền."
            } else {
                hideOverlay()
            }
        }
    }

    /// True when the pointer is over a window's title bar (or the window's own
    /// background chrome), which is what macOS itself treats as "move window".
    /// Uses the system-wide AX element under the cursor — the only public way
    /// to know what was clicked in another app.
    private func beganOnWindowTitleBar(at point: CGPoint) -> Bool {
        guard WindowManager.isTrusted else { return false }
        // Nhấn trong dải menu bar (wifi / ngày giờ…) hay Dock KHÔNG phải kéo cửa
        // sổ. Nút status-item nằm trong window nhỏ của menu bar nên walk-up dễ
        // nhận nhầm thành title bar → chặn ngay vùng ngoài visibleFrame.
        let screen = WindowManager.screenUnderPointer()
        if point.y >= screen.visibleFrame.maxY - 1 || point.y <= screen.visibleFrame.minY + 1 {
            return false
        }
        // AXUIElementCopyElementAtPosition dùng gốc top-left của MÀN CHÍNH (y
        // tăng xuống), còn NSEvent.mouseLocation là bottom-left của màn chính.
        // Flip luôn phải dùng biên trên của màn CHÍNH — dùng screen-under-
        // pointer sẽ lệch với màn phụ (bug "chỉ chạy trên màn 2").
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let cgPoint = CGPoint(x: point.x, y: top - point.y)

        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                               Float(cgPoint.x), Float(cgPoint.y),
                                               &element) == .success,
              let element else { return false }

        // The hit element is often a sub-view (traffic-light button, toolbar
        // child, text) — walk a short parent chain to find its ancestor
        // window/toolbar, which proves the press began on a title bar.
        var cur: AXUIElement = element
        for _ in 0..<4 {
            if isWindowOrToolbar(cur) { return true }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString,
                                                &parentRef) == .success,
                  let parent = parentRef else { break }
            cur = parent as! AXUIElement
        }
        return false
    }

    private func isWindowOrToolbar(_ el: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString,
                                            &roleRef) == .success,
              let role = roleRef as? String else { return false }
        return role == (kAXWindowRole as String) || role == "AXToolbar"
    }

    /// Screen-edge hit test in AppKit coordinates (origin bottom-left).
    private func zone(for point: CGPoint, on screen: NSScreen) -> WindowManager.SnapTarget? {
        let f = screen.frame
        let m = edgeMargin
        let nearLeft = point.x <= f.minX + m
        let nearRight = point.x >= f.maxX - m
        let nearTop = point.y >= f.maxY - m
        let nearBottom = point.y <= f.minY + m
        // Corners win over edges; a corner region is 25% of the screen height.
        let cornerY = f.height * 0.25
        if nearLeft && point.y >= f.maxY - cornerY { return .topLeft }
        if nearLeft && point.y <= f.minY + cornerY { return .bottomLeft }
        if nearRight && point.y >= f.maxY - cornerY { return .topRight }
        if nearRight && point.y <= f.minY + cornerY { return .bottomRight }
        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        if nearTop { return .maximize }
        if nearBottom { return .bottomHalf }
        return nil
    }

    private func showOverlay(zone: WindowManager.SnapTarget, on screen: NSScreen) {
        // `SnapTarget.rect(in:)` is defined in TOP-LEFT origin space (it feeds
        // AXPosition). An NSWindow frame is BOTTOM-LEFT, so feeding it
        // visibleFrame directly drew "bottom-left" where "top-left" belongs —
        // the reported wrong-corner bug. Compute in AX space, then flip.
        let axRect = zone.rect(in: WindowManager.axVisibleFrame(for: screen))
        let rect = WindowManager.axRectToAppKit(axRect)
        if overlay == nil {
            let w = NSWindow(contentRect: rect,
                             styleMask: [.borderless],
                             backing: .buffered, defer: false)
            w.level = .floating
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.contentView = NSHostingView(rootView: SnapOverlayView())
            overlay = w
        }
        overlay?.setFrame(rect, display: true)
        overlay?.orderFrontRegardless()
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
    }

    // MARK: Global hotkeys

    private func startHotkeys() {
        guard eventTap == nil else { return }
        let mask = 1 << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let c = Unmanaged<SnapZoneController>.fromOpaque(refcon).takeUnretainedValue()
            return c.handleKey(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func stopHotkeys() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private nonisolated func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        guard flags.contains(.maskControl), flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let target: WindowManager.SnapTarget?
        switch keyCode {
        case 123: target = .leftHalf     // ←
        case 124: target = .rightHalf    // →
        case 126: target = .maximize     // ↑
        case 125: target = .bottomHalf   // ↓
        case 36:  target = .center       // Return
        default:  target = nil
        }
        guard let target else { return Unmanaged.passUnretained(event) }
        Task { @MainActor in
            let ok = WindowManager.snapFrontmost(to: target)
            self.lastOutcome = ok
                ? "Đã đưa cửa sổ vào “\(target.titleVI)”."
                : "Không di chuyển được — ứng dụng không cho phép."
        }
        return nil // consume
    }
}

/// The translucent rectangle shown while a drag hovers a snap zone.
private struct SnapOverlayView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2)
            )
            .padding(6)
    }
}
