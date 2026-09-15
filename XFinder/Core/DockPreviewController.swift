import AppKit
import SwiftUI
import ApplicationServices

/// Dock-hover window preview, MFinder-style: dwell the pointer over an app's
/// Dock icon and a thumbnail panel of that app's on-screen windows slides in;
/// click a thumbnail to raise it.
///
/// Icon frames come from the public Accessibility API walked over the Dock
/// process (role subrole `AXApplicationDockItem`) — needs the same
/// `AXIsProcessTrusted()` grant as snap zones; there is no other public source
/// of per-icon geometry. The panel itself is a plain borderless NSWindow.
@MainActor
@Observable
final class DockPreviewController {
    static let shared = DockPreviewController()

    /// "idle" | "ready" | "notrusted" — drives the settings-page copy.
    var statusHint: String = ""

    private struct IconRect { let pid: pid_t; let title: String; let rect: CGRect }

    private var monitor: Any?
    private var localMonitor: Any?
    private var icons: [IconRect] = []
    private var hoveredPID: pid_t?
    private var hoverSince = Date.distantPast
    private var panel: NSWindow?
    private var panelPID: pid_t?
    /// Short enough to feel instant; long enough that merely sweeping the
    /// pointer across the Dock does not fire a panel for every icon.
    private let dwell: TimeInterval = 0.12
    private var lastIconLoad = Date.distantPast

    private init() {}

    // MARK: - Lifecycle
    // App-lifetime, gated on the `windowPreview.hoverEnabled` key: the whole
    // point is hovering the Dock from anywhere, so this cannot be tied to a
    // page's onAppear. When the toggle is off no timer runs → idle CPU 0%.

    /// Called at launch and on every change of the hover settings keys.
    func applySettings() {
        let enabled = UserDefaults.standard.object(forKey: "windowPreview.hoverEnabled") as? Bool ?? true
        guard enabled else {
            stop()
            statusHint = "Đang tắt — bật “Hiện bản xem trước khi di chuột qua ứng dụng trên Dock”."
            return
        }
        guard WindowManager.isTrusted else {
            stop()
            statusHint = "Chưa có quyền Trợ năng — không đọc được vị trí icon Dock."
            return
        }
        statusHint = "Đang chờ: di chuột vào icon app trên Dock."
        guard monitor == nil else { return }
        reloadIcons()
        // Event-driven: `mouseMoved` fires only on actual movement, so hovering
        // stays instant while a still pointer costs nothing. A 0.03 s timer
        // here meant 33 wake-ups per second forever.
        // A GLOBAL monitor only sees events delivered to *other* apps, so while
        // XFinder itself was frontmost the Dock hover never fired. The local
        // monitor covers that case; both are needed.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in self?.tick() }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        monitor = nil
        localMonitor = nil
        hoveredPID = nil
        hidePanel()
    }

    // MARK: - Hover state machine

    private func tick() {
        let mouse = NSEvent.mouseLocation
        // Refresh icon geometry ~1s after the Dock might have moved.
        if Date().timeIntervalSince(lastIconLoad) > 10 { reloadIcons() }

        if let icon = icons.first(where: { $0.rect.contains(mouse) }) {
            if panelPID == icon.pid { return } // pointer went into the panel zone
            if hoveredPID != icon.pid {
                hoveredPID = icon.pid
                hoverSince = Date()
                // The pointer may now stop moving entirely, and a mouse-move
                // monitor would never fire again — so schedule the dwell check
                // explicitly instead of waiting for another event.
                scheduleDwellCheck(for: icon)
                return
            }
            if Date().timeIntervalSince(hoverSince) >= dwell { showPanel(for: icon) }
            return
        }
        // Outside icons: keep the panel while the pointer is inside it.
        if let panel, panel.frame.insetBy(dx: -8, dy: -8).contains(mouse) { return }
        hoveredPID = nil
        hidePanel()
    }

    /// One-shot, fires once the dwell has elapsed; re-checks that the pointer
    /// is still on the same icon before showing anything.
    private func scheduleDwellCheck(for icon: IconRect) {
        let pid = icon.pid
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell + 0.01) { [weak self] in
            guard let self, self.hoveredPID == pid, self.panelPID != pid,
                  icon.rect.contains(NSEvent.mouseLocation) else { return }
            self.showPanel(for: icon)
        }
    }

    private func reloadIcons() {
        lastIconLoad = Date()
        guard let dockApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return }
        let root = AXUIElementCreateApplication(dockApp.processIdentifier)
        var out: [IconRect] = []
        Self.collectDockItems(root, depth: 0, into: &out)
        icons = out
    }

    private static func collectDockItems(_ el: AXUIElement, depth: Int, into out: inout [IconRect]) {
        guard depth < 6 else { return }
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subrole) == .success,
           (subrole as? String) == kAXApplicationDockItemSubrole as String || (subrole as? String) == "AXApplicationDockItem",
           let (pid, title, rect) = dockItemInfo(el) {
            out.append(IconRect(pid: pid, title: title, rect: rect))
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
              let arr = children as? [AXUIElement] else { return }
        for child in arr { collectDockItems(child, depth: depth + 1, into: &out) }
    }

    private static func dockItemInfo(_ el: AXUIElement) -> (pid: pid_t, title: String, rect: CGRect)? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String, !title.isEmpty else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else { return nil }
        // pid: Dock items expose AXURL (the .app bundle) — derive via workspace.
        var pid: pid_t = 0
        var urlRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &urlRef) == .success,
           let url = urlRef as? URL,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == url.path }) {
            pid = app.processIdentifier
        }
        if pid == 0,
           let app = NSWorkspace.shared.runningApplications.first(where: {
               $0.activationPolicy == .regular && $0.localizedName == title
           }) {
            pid = app.processIdentifier
        }
        guard pid != 0 else { return nil }
        // AXPosition is top-left origin; NSEvent.mouseLocation is bottom-left.
        // Comparing them directly made a Dock icon at the bottom of the screen
        // match the pointer at the TOP (the notch) — the reported bug.
        return (pid, title, flipToAppKit(CGRect(origin: point, size: size)))
    }

    /// Convert a top-left-origin (Accessibility/CoreGraphics) rect into
    /// AppKit's bottom-left-origin screen space.
    private static func flipToAppKit(_ rect: CGRect) -> CGRect {
        // Global flip is about the primary display's height (CG origin screen).
        guard let primary = NSScreen.screens.first else { return rect }
        let maxY = primary.frame.maxY
        return CGRect(x: rect.origin.x,
                      y: maxY - rect.origin.y - rect.height,
                      width: rect.width,
                      height: rect.height)
    }

    // MARK: - Panel

    private func showPanel(for icon: IconRect) {
        if panelPID == icon.pid, panel != nil { return }
        hidePanel()
        let content = DockPreviewView(pid: icon.pid, title: icon.title) { [weak self] in
            self?.hidePanel()
        }
        let host = NSHostingView(rootView: content)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 160)),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        self.panelPID = icon.pid
        anchorAbove(icon: icon)

        // Thumbnails arrive asynchronously and change the fitting size, so
        // re-anchor once the real size is known. Without this the panel is
        // positioned from a pre-layout size and lands ON TOP of the Dock icon.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.panelPID == icon.pid else { return }
            self.anchorAbove(icon: icon)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.panelPID == icon.pid else { return }
            self.anchorAbove(icon: icon)
        }
    }

    /// Places the panel fully ABOVE the hovered Dock icon, never overlapping it.
    private func anchorAbove(icon: IconRect) {
        guard let panel, let host = panel.contentView else { return }
        var size = host.fittingSize
        if size.width < 60 || size.height < 40 { size = NSSize(width: 320, height: 160) }

        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: icon.rect.midX, y: icon.rect.midY)) })
            ?? NSScreen.main
        var x = icon.rect.midX - size.width / 2
        // icon.rect is already AppKit space (bottom-left), so the icon's TOP
        // edge is maxY — sit the panel's bottom just above it.
        var y = icon.rect.maxY + 8
        if let screen {
            x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
            // Clamp only so the panel stays on screen; keep it above the icon.
            let highest = screen.frame.maxY - size.height - 8
            if y > highest { y = highest }
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
        panelPID = nil
    }
}

/// Thumbnail grid shown above a hovered Dock icon.
struct DockPreviewView: View {
    let pid: pid_t
    let title: String
    let onPick: () -> Void
    @State private var windows: [WindowManager.WindowInfo] = []
    @State private var thumbs: [CGWindowID: NSImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.top, 10)
            HStack(spacing: 8) {
                ForEach(windows.prefix(8)) { win in
                    Button(action: {
                        WindowManager.activate(pid: win.ownerPID)
                        onPick()
                    }) {
                        VStack(spacing: 4) {
                            Group {
                                if let img = thumbs[win.id] {
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                                } else {
                                    Rectangle().fill(Color(.controlBackgroundColor))
                                        .overlay(Image(systemName: "macwindow").foregroundColor(.secondary))
                                }
                            }
                            .frame(width: 150, height: 94)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            Text(win.title.isEmpty ? title : win.title)
                                .font(.system(size: 10)).lineLimit(1).frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .frame(maxWidth: 720)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separatorColor), lineWidth: 1))
        .onAppear { load() }
    }

    private func load() {
        windows = WindowManager.listWindows().filter { $0.ownerPID == pid }
        let ids = windows.map(\.id)
        Task {
            // One batched ScreenCaptureKit round trip for the whole panel.
            // `thumbnails(windowIDs:)` queries shareable content once and then
            // captures each window, instead of re-querying per window.
            let made = await WindowManager.thumbnails(windowIDs: ids, maxSize: 220)
            for (id, img) in made { thumbs[id] = img }
        }
    }
}
