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
    private let dwell: TimeInterval = 0.08
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
            statusHint = L10n.t("Đang tắt — bật “Hiện bản xem trước khi di chuột qua ứng dụng trên Dock”.")
            return
        }
        guard WindowManager.isTrusted else {
            stop()
            statusHint = L10n.t("Chưa có quyền Trợ năng — không đọc được vị trí icon Dock.")
            return
        }
        statusHint = L10n.t("Đang chờ: di chuột vào icon app trên Dock.")
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
        let bundleID = NSRunningApplication(processIdentifier: icon.pid)?.bundleIdentifier ?? ""
        let isBrowser = BrowserTabProvider.isSupportedBrowser(bundleID: bundleID)
        let panelHeight: CGFloat = isBrowser ? 280 : 220
        let panelWidth: CGFloat = 320

        if panelPID == icon.pid, panel != nil { return }

        // If panel already exists, smoothly morph to new icon without tearing down the window
        if let panel = self.panel, let host = panel.contentView as? NSHostingView<DockPreviewView> {
            self.panelPID = icon.pid
            withTransaction(Transaction(animation: nil)) {
                host.rootView = DockPreviewView(pid: icon.pid, title: icon.title) { [weak self] in
                    self?.hidePanel()
                }
            }
            anchorAbove(icon: icon, isBrowser: isBrowser, animated: true)
            return
        }

        hidePanel()
        let content = DockPreviewView(pid: icon.pid, title: icon.title) { [weak self] in
            self?.hidePanel()
        }
        let host = NSHostingView(rootView: content)
        host.wantsLayer = true
        host.layer?.cornerRadius = LiquidGlassTokens.containerRadius
        host.layer?.masksToBounds = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.contentView = host
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        self.panel = panel
        self.panelPID = icon.pid
        anchorAbove(icon: icon, isBrowser: isBrowser, animated: false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            panel.animator().alphaValue = 1.0
        }
    }

    /// Places the panel fully ABOVE the hovered Dock icon with a fixed width 320 and height 280 (browser) or 220 (normal).
    private func anchorAbove(icon: IconRect, isBrowser: Bool, animated: Bool = true) {
        guard let panel else { return }
        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = isBrowser ? 280 : 220
        let gap: CGFloat = 12

        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: icon.rect.midX, y: icon.rect.midY)) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var originX = icon.rect.midX - 160
        var originY = icon.rect.maxY + gap

        // Clamp horizontally so it stays within visible screen bounds
        originX = max(screen.minX + 8, min(originX, screen.maxX - windowWidth - 8))

        // If top edge would exceed screen, place below icon if possible or clamp
        if originY + windowHeight > screen.maxY {
            originY = icon.rect.minY - windowHeight - gap
        }
        if originY < screen.minY + 8 {
            originY = screen.minY + 8
        }

        let targetFrame = NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func hidePanel() {
        guard let currentPanel = panel else { return }
        self.panel = nil
        self.panelPID = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            currentPanel.animator().alphaValue = 0.0
        }, completionHandler: {
            currentPanel.orderOut(nil)
        })
    }
}

/// Thumbnail grid shown above a hovered Dock icon with Liquid Glass styling.
struct DockPreviewView: View {
    let pid: pid_t
    let title: String
    let onPick: () -> Void
    @State private var store = WindowPreviewStore.shared
    @State private var hoveredTabID: String?
    @State private var scale: CGFloat = 0.95
    @State private var opacity: Double = 0.0

    private var bundleID: String {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    }

    private var isBrowser: Bool {
        BrowserTabProvider.isSupportedBrowser(bundleID: bundleID)
    }

    private var activeTab: BrowserTabItem? {
        store.activeBrowserTabs.first(where: { $0.isActive }) ?? store.activeBrowserTabs.first
    }

    private var currentTab: BrowserTabItem? {
        if let hID = hoveredTabID, let match = store.activeBrowserTabs.first(where: { $0.id == hID }) {
            return match
        }
        return activeTab
    }

    var body: some View {
        let dockItems = store.previewItems.filter { !$0.isOnOtherSpace }
        let targetHeight: CGFloat = isBrowser ? 280 : 220

        VStack(alignment: .leading, spacing: 6) {
            // Header: fixed 36px
            HStack(spacing: 7) {
                if let icon = iconForPID(pid) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                VStack(alignment: .leading, spacing: 1) {
                    let displayTitle = isBrowser && currentTab != nil ? currentTab!.title : (dockItems.first?.title.isEmpty == false ? dockItems.first!.title : title)
                    let displaySubtitle = isBrowser && currentTab != nil ? currentTab!.domain : (dockItems.first?.appName.isEmpty == false ? dockItems.first!.appName : title)
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(displaySubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
            }
            .frame(height: 36)
            .padding(.horizontal, 8)

            // Thumbnail / WebSnapshotCardView / AppHeroCardView: fixed 304x160
            if isBrowser, let cur = currentTab {
                Button(action: {
                    BrowserTabProvider.shared.selectTab(tab: cur, in: bundleID)
                    WindowManager.activate(pid: pid)
                    onPick()
                }) {
                    if let tabThumb = TabPreviewCache.shared.getPreview(tabId: cur.id) {
                        WindowThumbnailView(image: tabThumb, width: 304, height: 160)
                    } else if cur.isActive, let firstThumb = dockItems.first?.thumbnail {
                        WindowThumbnailView(image: firstThumb, width: 304, height: 160)
                    } else {
                        let curIndex = store.activeBrowserTabs.firstIndex(where: { $0.id == cur.id })
                        WebSnapshotCardView(
                            tab: cur,
                            tabIndex: curIndex != nil ? curIndex! + 1 : nil,
                            totalTabs: store.activeBrowserTabs.count > 0 ? store.activeBrowserTabs.count : nil,
                            width: 304,
                            height: 160,
                            showFullDetails: true
                        )
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            } else if let first = dockItems.first {
                Button(action: {
                    WindowManager.activate(pid: pid)
                    onPick()
                }) {
                    if let thumb = first.thumbnail {
                        WindowThumbnailView(image: thumb, width: 304, height: 160)
                    } else {
                        AppHeroCardView(
                            appName: first.appName.isEmpty ? title : first.appName,
                            title: first.title.isEmpty ? (first.appName.isEmpty ? title : first.appName) : first.title,
                            bundleID: bundleID,
                            isStageMiniature: first.isStageMiniature,
                            isOnOtherSpace: first.isOnOtherSpace,
                            width: 304,
                            height: 160
                        )
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    ProgressView().scaleEffect(0.6)
                }
                .frame(width: 304, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 8)
            }

            // Tabs / Special: fixed 68px for browser
            if isBrowser {
                if !store.activeBrowserTabs.isEmpty || store.needsAutomationPermission {
                    BrowserTabCarouselView(
                        tabs: store.activeBrowserTabs,
                        needsPermission: store.needsAutomationPermission,
                        selectedTabID: currentTab?.id,
                        onHoverTab: { tab in
                            hoveredTabID = tab.id
                        },
                        onSelectTab: { tab in
                            BrowserTabProvider.shared.selectTab(tab: tab, in: bundleID)
                            WindowManager.activate(pid: pid)
                            onPick()
                        }
                    )
                    .frame(height: 68)
                } else {
                    Color.clear
                        .frame(height: 68)
                }
            } else if bundleID == "com.apple.iCal" && !store.calendarEvents.isEmpty {
                CalendarPreviewView(events: store.calendarEvents)
                    .frame(height: 54)
                    .padding(.horizontal, 8)
            } else if bundleID == "com.apple.weather", let weather = store.weatherInfo {
                WeatherPreviewView(weather: weather)
                    .frame(height: 54)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 320, height: targetHeight)
        .liquidGlassContainer(cornerRadius: LiquidGlassTokens.Container.cornerRadius)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(LiquidGlassTokens.spring) {
                scale = 1.0
                opacity = 1.0
            }
            store.loadDockPreviews(for: pid)
        }
        .onChange(of: pid) { newPID in
            withTransaction(Transaction(animation: nil)) {
                store.loadDockPreviews(for: newPID)
            }
        }
    }

    private func iconForPID(_ p: pid_t) -> NSImage? {
        guard let app = NSRunningApplication(processIdentifier: p),
              let url = app.bundleURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
