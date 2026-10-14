import AppKit
import SwiftUI
import ApplicationServices
import os

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
    /// The press being qualified (did the window under the pointer move?) and that window's number.
    private var qualifier: SnapLayout.DragQualifier?
    private var pressedWindow: CGWindowID?
    private let snapLog = Logger(subsystem: "com.xfinder.app", category: "SnapDrag")
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
    private var showPreview: Bool {
        UserDefaults.standard.object(forKey: "snapzones.showPreview") as? Bool ?? true
    }
    private var hapticEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapzones.haptic") as? Bool ?? false
    }
    /// B3: dragging a window to the notch shows a layout row instead of maximising there.
    private var notchRowEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapzones.notchRow") as? Bool ?? true
    }
    private var restoreOnUnsnap: Bool {
        UserDefaults.standard.object(forKey: "snapzones.restoreOnUnsnap") as? Bool ?? true
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
        hideRow()
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
                let hit = windowUnderPointer(at: mouse)
                pressedWindow = hit?.id
                qualifier = SnapLayout.DragQualifier(pressPoint: mouse, windowOrigin: hit?.origin)
            }
            if qualifier?.verdict == .pending, let id = pressedWindow {
                let verdict = qualifier?.observe(pointer: mouse, windowOriginNow: windowOrigin(id))
                if verdict != .pending { snapLog.debug("drag verdict \(String(describing: verdict), privacy: .public)") }
            }
            dragIsWindowMove = qualifier?.verdict == .windowMove
            guard dragIsWindowMove else { return }

            let screen = WindowManager.screenUnderPointer()
            let notch = NotchSurfaceLayout.notch(screen: screen.frame, auxLeft: screen.auxiliaryTopLeftArea,
                                                 auxRight: screen.auxiliaryTopRightArea)
            let decision = SnapLayout.decide(point: mouse, screen: screen.frame, notch: notch, edgeMargin: edgeMargin,
                                             rowEnabled: notchRowEnabled, rowVisible: rowPanel?.isVisible ?? false)
            if case .row(let tile) = decision {
                showRow(highlight: tile, notch: notch, on: screen)
                let target = tile.map { SnapLayout.rowTargets[$0] }
                if target != activeZone {
                    activeZone = target
                    if let target, showPreview { showOverlay(zone: target, on: screen) } else { hideOverlay() }
                    if target != nil, hapticEnabled {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    }
                }
                return
            }
            hideRow()
            if case .edge(let edge) = decision, let zone = edge {
                if zone != activeZone {
                    activeZone = zone
                    if showPreview {
                        showOverlay(zone: zone, on: screen)
                    }
                    if hapticEnabled {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    }
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
            qualifier = nil
            pressedWindow = nil
            hideRow()
            guard wasWindowMove else { return }
            if let zone = activeZone {
                hideOverlay()
                activeZone = nil
                let ok = WindowManager.snapFrontmost(to: zone)
                if ok && hapticEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                }
                lastOutcome = ok
                    ? "\(L10n.t("Đã đưa cửa sổ vào “"))\(zone.titleVI)”."
                    : L10n.t("Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.")
            } else {
                hideOverlay()
            }
        }
    }

    /// The normal (layer-0) window under the pointer at press, from WindowServer: its number and its top-left origin.
    /// nil for a press on the menu bar / Dock strip, on XFinder's own window, or on nothing. No Accessibility walk —
    /// see `SnapLayout.DragQualifier` for why the old one never qualified a drag on macOS 27.
    private func windowUnderPointer(at point: CGPoint) -> (id: CGWindowID, origin: CGPoint)? {
        // Nhấn trong dải menu bar (wifi / ngày giờ…) hay Dock KHÔNG phải kéo cửa sổ.
        let screen = WindowManager.screenUnderPointer()
        if point.y >= screen.visibleFrame.maxY - 1 || point.y <= screen.visibleFrame.minY + 1 { return nil }
        // CGWindowList is top-left of the MAIN screen; NSEvent is bottom-left of the main screen.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let cg = CGPoint(x: point.x, y: top - point.y)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {                                   // front to back: the first normal window hit is the pressed one
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary), rect.contains(cg),
                  let num = w[kCGWindowNumber as String] as? Int else { continue }
            if (w[kCGWindowOwnerPID as String] as? Int32) == me { return nil }   // our own window: nothing to snap
            return (CGWindowID(num), rect.origin)
        }
        return nil
    }

    /// That window's current top-left origin, or nil if it can no longer be read.
    private func windowOrigin(_ id: CGWindowID) -> CGPoint? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let b = list.first?[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
        return rect.origin
    }

    // MARK: Notch layout row (B3)

    private var rowPanel: SurfacePanel?
    private let rowModel = SnapRowModel()

    private func showRow(highlight: Int?, notch: CGRect, on screen: NSScreen) {
        let frame = SnapLayout.rowFrame(count: SnapLayout.rowTargets.count, notch: notch, screen: screen.frame)
        if rowPanel == nil {
            let p = SurfacePanel(kind: .passive, size: frame.size)       // mouse-transparent: the drag continues underneath
            p.host(SnapRowView(model: rowModel))
            rowPanel = p
        }
        rowModel.highlighted = highlight
        rowPanel?.setFrame(frame, display: true)
        if rowPanel?.isVisible != true { rowPanel?.orderFrontRegardless() }
    }

    private func hideRow() {
        rowModel.highlighted = nil
        rowPanel?.orderOut(nil)
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
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private nonisolated func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.eventTap, CFMachPortIsValid(tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
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
        case 2:   target = .leftThird    // D
        case 3:   target = .centerThird  // F
        case 5:   target = .rightThird   // G
        default:  target = nil
        }
        guard let target else { return Unmanaged.passUnretained(event) }
        Task { @MainActor in
            let ok = WindowManager.snapFrontmost(to: target)
            self.lastOutcome = ok
                ? "\(L10n.t("Đã đưa cửa sổ vào “"))\(target.titleVI)”."
                : L10n.t("Không di chuyển được — ứng dụng không cho phép.")
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
