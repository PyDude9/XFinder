import AppKit
import SwiftUI
import ApplicationServices
import Carbon
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
    private var localDragMonitor: Any?
    private var overlay: NSWindow?
    private let overlayModel = SnapOverlayModel()
    private var activeZone: WindowManager.SnapTarget?
    private var activeTiledDrop: TiledDropPlan?
    private var activeTiledScreen: NSScreen?
    private var wasDragging = false
    /// Whether the in-flight drag started on a window's title bar. Evaluated
    /// once per drag so a mid-drag AX query cannot flip the verdict.
    private var dragIsWindowMove = false
    /// The press being qualified (did the window under the pointer move?) and that window's number.
    private var qualifier: SnapLayout.DragQualifier?
    private var pressedWindow: CGWindowID?
    private let snapLog = Logger(subsystem: "com.xfinder.app", category: "SnapDrag")
    private nonisolated static let hotKeySignature: OSType = 0x5846535A // 'XFSZ'
    private var carbonHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private(set) var registeredHotkeyCount = 0
    private(set) var failedHotkeyCount = 0

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
        HyprTilingController.shared.applySettings(masterEnabled: true)
        isRunning = dragMonitor != nil || !hotKeyRefs.isEmpty || HyprTilingController.shared.isRunning
    }

    func stop() {
        stopDragWatch()
        stopHotkeys()
        HyprTilingController.shared.stop()
        isRunning = false
    }

    // MARK: Drag-to-edge

    /// Event-driven; local events cover XFinder's Browser windows, global events cover other apps.
    private func startDragWatch() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] _ in
            Task { @MainActor in self?.dragTick() }
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in self?.dragTick() }
            return event
        }
    }

    private func stopDragWatch() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        if let localDragMonitor { NSEvent.removeMonitor(localDragMonitor) }
        localDragMonitor = nil
        dragIsWindowMove = false
        qualifier = nil
        pressedWindow = nil
        activeZone = nil
        activeTiledDrop = nil
        activeTiledScreen = nil
        hideOverlay()
        hideRow()
        wasDragging = false
    }

    private func dragTick() {
        guard featureEnabled, dragEnabled else { return }
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
            if case .row(let tile, let target) = decision {
                activeTiledDrop = nil
                activeTiledScreen = nil
                showRow(highlight: tile, target: target, notch: notch, on: screen)
                // Inside the four-corner tile, moving to another quadrant changes the target — and taps again.
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

            if HyprTilingController.shared.isTilingMode,
               let wid = pressedWindow,
               let plan = HyprTilingController.shared.previewTiledDrag(pointerAppKit: mouse, draggedID: wid, on: screen) {
                activeZone = nil
                if plan != activeTiledDrop || activeTiledScreen != screen {
                    activeTiledDrop = plan
                    activeTiledScreen = screen
                    if showPreview {
                        let badge = plan.edge == .center ? "Hoán đổi vị trí" : "Chia ô tại đây"
                        showOverlay(axRect: plan.previewRect, badgeKey: badge)
                    }
                    if hapticEnabled {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    }
                }
                return
            }
            activeTiledDrop = nil
            activeTiledScreen = nil

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

        // Button released — commit if a zone or tiled drop target was highlighted.
        if wasDragging {
            wasDragging = false
            let wasWindowMove = dragIsWindowMove
            let releasedWindow = pressedWindow
            dragIsWindowMove = false
            qualifier = nil
            pressedWindow = nil
            hideRow()
            guard wasWindowMove else {
                activeTiledDrop = nil
                activeTiledScreen = nil
                hideOverlay()
                return
            }
            if activeTiledDrop != nil, let wid = releasedWindow {
                let targetScreen = activeTiledScreen ?? WindowManager.screenUnderPointer()
                activeTiledDrop = nil
                activeTiledScreen = nil
                hideOverlay()
                let ok = HyprTilingController.shared.commitTiledDrag(pointerAppKit: mouse, draggedID: wid, on: targetScreen)
                if ok && hapticEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                }
                lastOutcome = HyprTilingController.shared.lastOutcome
                return
            }
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
    /// nil for a press on the menu bar / Dock strip, on an XFinder panel/settings window, or on nothing. No Accessibility walk —
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
            // Stage Manager keeps layer-0 "Gesture Blocking Overlay" windows (owner WindowManager) exactly over the strip
            // thumbnails and in FRONT of them; qualifying against one would watch a window that never moves (P13 review).
            // Skipped by owner, as the switcher does — not by sharing state 0, which real windows that opt out of capture
            // (password managers, banking apps) also report.
            let owner = w[kCGWindowOwnerName as String] as? String
            if owner == "WindowManager" || owner == "Window Server" { continue }
            if (w[kCGWindowOwnerPID as String] as? Int32) == me {
                guard let browser = NSApp.windows.first(where: { $0.windowNumber == num }) as? BrowserWindow,
                      !browser.styleMask.contains(.fullScreen) else { return nil }
            }
            guard let wid = CGWindowID(exactly: num), wid != 0 else { continue }
            return (wid, rect.origin)
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

    private func showRow(highlight: Int?, target: SnapLayout.Target?, notch: CGRect, on screen: NSScreen) {
        let frame = SnapLayout.rowFrame(count: SnapLayout.rowItems.count, notch: notch, screen: screen.frame)
        if rowPanel == nil {
            let p = SurfacePanel(kind: .passive, size: frame.size)       // mouse-transparent: the drag continues underneath
            p.host(SnapRowView(model: rowModel))
            rowPanel = p
        }
        rowModel.highlighted = highlight
        rowModel.target = target
        rowPanel?.setFrame(frame, display: true)
        if rowPanel?.isVisible != true { rowPanel?.orderFrontRegardless() }
    }

    private func hideRow() {
        rowModel.highlighted = nil
        rowModel.target = nil
        rowPanel?.orderOut(nil)
    }

    private func showOverlay(zone: WindowManager.SnapTarget, on screen: NSScreen) {
        let axRect = zone.rect(in: WindowManager.axVisibleFrame(for: screen))
        showOverlay(axRect: axRect, badgeKey: nil)
    }

    private func showOverlay(axRect: CGRect, badgeKey: String?) {
        let rect = WindowManager.axRectToAppKit(axRect)
        overlayModel.badgeKey = badgeKey
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
            w.contentView = NSHostingView(rootView: SnapOverlayView(model: overlayModel))
            overlay = w
        }
        overlay?.setFrame(rect, display: true)
        overlay?.orderFrontRegardless()
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
    }

    // MARK: Global hotkeys (Carbon RegisterEventHotKey)

    private func startHotkeys() {
        installCarbonHandlerIfNeeded()
        if hotKeyRefs.count == SnapLayout.hotkeyKeyCodes.count && failedHotkeyCount == 0 {
            return
        }
        stopHotkeys()
        let modifiers = UInt32(controlKey | optionKey)
        var registered = 0
        var failed = 0
        for (idx, keyCode) in SnapLayout.hotkeyKeyCodes.enumerated() {
            let slotID = UInt32(idx + 1)
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: Self.hotKeySignature, id: slotID)
            let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeyRefs[slotID] = ref
                registered += 1
            } else {
                failed += 1
                snapLog.notice("failed to register classic hotkey keyCode=\(keyCode) status=\(status)")
            }
        }
        registeredHotkeyCount = registered
        failedHotkeyCount = failed
        snapLog.notice("registered \(registered)/\(SnapLayout.hotkeyKeyCodes.count) classic SnapZones Carbon hotkeys")
    }

    private func stopHotkeys() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredHotkeyCount = 0
        failedHotkeyCount = 0
    }

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard hkID.signature == SnapZoneController.hotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            let controller = Unmanaged<SnapZoneController>.fromOpaque(userData).takeUnretainedValue()
            let firedID = hkID.id
            Task { @MainActor in
                controller.handleCarbonHotKey(id: firedID)
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    private func handleCarbonHotKey(id: UInt32) {
        let index = Int(id) - 1
        guard SnapLayout.hotkeyKeyCodes.indices.contains(index) else { return }
        let keyCode = Int64(SnapLayout.hotkeyKeyCodes[index])
        guard let target = SnapLayout.hotkeyTarget(keyCode: keyCode) else { return }
        snapLog.notice("classic hotkey fired: keyCode=\(keyCode) target=\(target.titleVI, privacy: .public)")
        performSnap(to: target)
    }

    /// Own Browser windows also handle their keys locally, independent of global hotkey delivery.
    func performLocalShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard featureEnabled, hotkeysEnabled, WindowManager.isTrusted, event.window is BrowserWindow,
              SnapLayout.acceptsHotkey(control: flags.contains(.control), option: flags.contains(.option),
                                      command: flags.contains(.command), shift: flags.contains(.shift)),
              let target = SnapLayout.hotkeyTarget(keyCode: Int64(event.keyCode)) else { return false }
        performSnap(to: target)
        return true
    }

    private func performSnap(to target: WindowManager.SnapTarget) {
        guard featureEnabled, hotkeysEnabled else { return }
        let ok = WindowManager.snapFrontmost(to: target)
        lastOutcome = ok
            ? "\(L10n.t("Đã đưa cửa sổ vào “"))\(target.titleVI)”."
            : L10n.t("Không di chuyển được — ứng dụng không cho phép.")
    }
}

@MainActor
@Observable
private final class SnapOverlayModel {
    var badgeKey: String?
}

/// The translucent rectangle shown while a drag hovers a snap zone or tiled BSP target.
private struct SnapOverlayView: View {
    var model: SnapOverlayModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2)
                )
            if let key = model.badgeKey {
                Text(L10n.t(key))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
            }
        }
        .padding(6)
    }
}
