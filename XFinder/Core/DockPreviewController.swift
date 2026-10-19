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
    private var hideWorkItem: DispatchWorkItem?
    /// Short enough to feel instant; long enough that merely sweeping the
    /// pointer across the Dock does not fire a panel for every icon. Settable (ms) for people who want the
    /// panel only when they stop on an icon; read per hover, nothing to re-arm.
    private var dwell: TimeInterval {
        Double(UserDefaults.standard.object(forKey: "windowPreview.hoverDelayMs") as? Int ?? 80) / 1000
    }
    private var lastIconLoad = Date.distantPast
    /// Stage Manager only: an app that comes on stage gets its windows' upright pictures taken (0.8 s later, after
    /// macOS's move animation) — once parked in the strip, only a tilted tile can be captured.
    private var activationObserver: NSObjectProtocol?

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
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
                guard WindowManager.isStageManagerEnabled,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                let pid = app.processIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    Task.detached(priority: .utility) { await ScreenCaptureProvider.shared.warmUprightPictures(pid: pid) }
                }
            }
        }
    }

    func stop() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        monitor = nil
        localMonitor = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        hoveredPID = nil
        hidePanel()
    }

    // MARK: - Hover state machine

    private func tick() {
        let mouse = NSEvent.mouseLocation
        // Refresh icon geometry ~1s after the Dock might have moved.
        if Date().timeIntervalSince(lastIconLoad) > 10 { reloadIcons() }

        if let icon = icons.first(where: { $0.rect.contains(mouse) }) {
            hideWorkItem?.cancel()
            hideWorkItem = nil
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
        if let panel, panel.frame.insetBy(dx: -8, dy: -8).contains(mouse) {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            return
        }
        hoveredPID = nil
        scheduleHidePanel(delay: 0.3)
    }

    private func scheduleHidePanel(delay: TimeInterval) {
        guard hideWorkItem == nil, panel != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWorkItem = nil
            let mouse = NSEvent.mouseLocation
            if let p = self.panel, p.frame.insetBy(dx: -8, dy: -8).contains(mouse) { return }
            if self.icons.contains(where: { $0.rect.contains(mouse) }) { return }
            self.hidePanel()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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

    typealias PanelDimensions = DockPreviewDimensions

    private func showPanel(for icon: IconRect) {
        let bundleID = NSRunningApplication(processIdentifier: icon.pid)?.bundleIdentifier ?? ""
        let isBrowser = BrowserTabProvider.isSupportedBrowser(bundleID: bundleID)
        let activeTabs = isBrowser ? activeTabsForDockPreview(WindowPreviewStore.shared.activeBrowserTabs) : []
        let tabCount = isBrowser ? (activeTabs.isEmpty ? 1 : activeTabs.count) : 1
        let windowCount = isBrowser ? 1 : min(WindowPreviewStore.dockMaxCards,
                                                WindowPreviewStore.dockWindowCards(WindowPreviewStore.shared.windowLister().filter { $0.ownerPID == icon.pid }).count)
        let dims = isBrowser ? browserPanelDimensions(tabCount: tabCount) : windowPanelDimensions(count: windowCount)
        let panelWidth = dims.panelWidth
        let panelHeight = dims.panelHeight

        if panelPID == icon.pid, panel != nil { return }

        // If panel already exists, smoothly morph to new icon without tearing down the window
        if let panel = self.panel, let host = panel.contentView as? NSHostingView<DockPreviewView> {
            self.panelPID = icon.pid
            withTransaction(Transaction(animation: nil)) {
                host.rootView = DockPreviewView(pid: icon.pid, title: icon.title) { [weak self] in
                    self?.hidePanel()
                }
            }
            anchorAbove(icon: icon, windowWidth: panelWidth, windowHeight: panelHeight, animated: true)
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
        anchorAbove(icon: icon, windowWidth: panelWidth, windowHeight: panelHeight, animated: false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            panel.animator().alphaValue = 1.0
        }
    }

    /// Dynamically update panel size when browser tabs load or change.
    func updatePanelSize(width: CGFloat, height: CGFloat, animated: Bool = true) {
        guard let panel, let icon = icons.first(where: { $0.pid == panelPID }) else { return }
        if panel.frame.width == width && panel.frame.height == height { return }
        anchorAbove(icon: icon, windowWidth: width, windowHeight: height, animated: animated)
    }

    /// Places the panel fully ABOVE the hovered Dock icon centered on the icon.
    private func anchorAbove(icon: IconRect, windowWidth: CGFloat, windowHeight: CGFloat, animated: Bool = true) {
        guard let panel else { return }
        let gap: CGFloat = 12

        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: icon.rect.midX, y: icon.rect.midY)) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var originX = icon.rect.midX - (windowWidth / 2)
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
        hideWorkItem?.cancel()
        hideWorkItem = nil
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
    @State private var offset: CGFloat = 8
    @State private var opacity: Double = 0.0

    private var bundleID: String {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    }

    private var isBrowser: Bool {
        BrowserTabProvider.isSupportedBrowser(bundleID: bundleID)
    }

    var body: some View {
        let dockItems = store.previewItems.filter { !$0.isOnOtherSpace }
        let visibleTabs = isBrowser ? activeTabsForDockPreview(store.activeBrowserTabs) : []
        let tabCount = visibleTabs.count
        let dims = browserPanelDimensions(tabCount: max(1, tabCount))

        Group {
            if isBrowser && tabCount >= 2 {
                // Windows Taskbar style: up to 5 preview cards side by side (active tabs only)
                HStack(spacing: tabCount >= 4 ? 10 : 12) {
                    ForEach(visibleTabs) { tab in
                        DockBrowserTabCard(
                            tab: tab,
                            appIcon: iconForPID(pid),
                            bundleID: bundleID,
                            pid: pid,
                            primaryThumb: tab.isActive ? dockItems.first?.thumbnail : nil,
                            cardWidth: dims.cardWidth,
                            cardHeight: dims.cardHeight,
                            thumbWidth: dims.thumbWidth,
                            thumbHeight: dims.thumbHeight,
                            onPick: onPick
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(width: dims.panelWidth, height: dims.panelHeight)
            } else if !isBrowser {
                DockWindowCardsView(pid: pid, title: title, items: dockItems, store: store, onPick: onPick)
            } else {
                // Single card mode: a browser with one tab (320x220)
                let targetHeight: CGFloat = (bundleID == "com.apple.iCal" && !store.calendarEvents.isEmpty) || (bundleID == "com.apple.weather" && store.weatherInfo != nil) ? 280 : 220

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
                            let curTab = visibleTabs.first ?? store.activeBrowserTabs.first(where: { $0.isActive }) ?? store.activeBrowserTabs.first
                            let firstItem = dockItems.first
                            let displayTitle: String = {
                                if isBrowser, let tab = curTab { return tab.title }
                                if let item = firstItem, !item.title.isEmpty { return item.title }
                                return title
                            }()
                            let displaySubtitle: String = {
                                if isBrowser, let tab = curTab { return tab.domain }
                                if let item = firstItem, !item.appName.isEmpty { return item.appName }
                                return title
                            }()
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
                    if isBrowser, let cur = visibleTabs.first ?? store.activeBrowserTabs.first(where: { $0.isActive }) ?? store.activeBrowserTabs.first {
                        Button(action: {
                            BrowserTabProvider.shared.selectTab(tab: cur, in: bundleID)
                            WindowManager.activate(pid: pid)
                            onPick()
                        }) {
                            if let tabThumb = TabPreviewCache.shared.getPreview(tabId: cur.id) {
                                WindowThumbnailView(image: tabThumb, width: 304, height: 160)
                            } else if let firstThumb = dockItems.first?.thumbnail {
                                WindowThumbnailView(image: firstThumb, width: 304, height: 160)
                            } else {
                                WebSnapshotCardView(
                                    tab: cur,
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

                    // Special widgets
                    if bundleID == "com.apple.iCal" && !store.calendarEvents.isEmpty {
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
            }
        }
        .dockGlass(cornerRadius: LiquidGlassTokens.Container.cornerRadius)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.8)) {
                offset = 0
                opacity = 1.0
            }
            store.loadDockPreviews(for: pid)
        }
        .onChange(of: pid) { _, newPID in
            withTransaction(Transaction(animation: nil)) {
                store.loadDockPreviews(for: newPID)
            }
        }
        .onChange(of: store.previewItems.count) { _, n in
            guard !isBrowser else { return }
            let dims = windowPanelDimensions(count: n)
            DockPreviewController.shared.updatePanelSize(width: dims.panelWidth, height: dims.panelHeight + Self.widgetHeight(bundleID, store),
                                                         animated: true)
        }
        .onChange(of: store.activeBrowserTabs) { _, _ in
            if isBrowser {
                let visible = activeTabsForDockPreview(store.activeBrowserTabs)
                let count = visible.isEmpty ? 1 : visible.count
                let dims = browserPanelDimensions(tabCount: count)
                DockPreviewController.shared.updatePanelSize(width: dims.panelWidth, height: dims.panelHeight, animated: true)
            }
        }
    }

    private func iconForPID(_ p: pid_t) -> NSImage? {
        guard let app = NSRunningApplication(processIdentifier: p),
              let url = app.bundleURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Calendar's next events / Weather's conditions under the cards (60 pt), else nothing.
    static func widgetHeight(_ bundleID: String, _ store: WindowPreviewStore) -> CGFloat {
        (bundleID == "com.apple.iCal" && !store.calendarEvents.isEmpty) || (bundleID == "com.apple.weather" && store.weatherInfo != nil) ? 60 : 0
    }
}

/// One card per window of a non-browser app (2026-10-19 redesign): a header with the app and how many windows it has,
/// then up to four cards — the whole window fitted into a 16 : 10 frame (never cropped; the old single card filled and
/// cut the top and bottom), its title under it, and a small label when the window is parked in Stage Manager or on
/// another Space. A click raises THAT window.
struct DockWindowCardsView: View {
    let pid: pid_t
    let title: String
    let items: [PreviewItem]
    let store: WindowPreviewStore
    let onPick: () -> Void

    var body: some View {
        let dims = windowPanelDimensions(count: items.count)
        let total = items.first?.windowCount ?? items.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if let icon = ClipboardAppIcon.icon(forBundleID: items.first?.bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(items.first?.appName ?? title)
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if total > 1 {
                    Text("\(total)\(L10n.t(" cửa sổ"))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(height: 28)

            if items.isEmpty {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(width: dims.thumbWidth, height: dims.thumbHeight)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(items) { item in
                        DockWindowCard(item: item, pid: pid, dims: dims, onPick: onPick)
                    }
                }
            }

            if let bid = items.first?.bundleID, bid == "com.apple.iCal", !store.calendarEvents.isEmpty {
                CalendarPreviewView(events: store.calendarEvents).frame(height: 54)
            } else if let bid = items.first?.bundleID, bid == "com.apple.weather", let weather = store.weatherInfo {
                WeatherPreviewView(weather: weather).frame(height: 54)
            }
        }
        .padding(12)
    }
}

private struct DockWindowCard: View {
    let item: PreviewItem
    let pid: pid_t
    let dims: DockPreviewDimensions
    let onPick: () -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            let info = WindowManager.WindowInfo(id: item.windowID, ownerPID: pid, ownerName: item.appName, title: item.title,
                                                bounds: .zero, isOnScreen: true)
            WindowManager.raiseWindow(info)
            onPick()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                    if let image = item.thumbnail {
                        Image(nsImage: image)
                            .resizable().interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            .padding(6)
                    } else {
                        AppHeroCardView(appName: item.appName, title: item.title, bundleID: item.bundleID,
                                        isStageMiniature: item.isStageMiniature, isOnOtherSpace: item.isOnOtherSpace,
                                        width: dims.thumbWidth, height: dims.thumbHeight)
                    }
                }
                .frame(width: dims.thumbWidth, height: dims.thumbHeight)
                .overlay(alignment: .topLeading) {
                    if item.thumbnail != nil, item.isStageMiniature || item.isOnOtherSpace {
                        Text(item.isStageMiniature ? L10n.t("Trong Stage Manager") : L10n.t("Ở Space khác"))
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(hovered ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: hovered ? 2 : 1)
                }
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(width: dims.thumbWidth, alignment: .leading)
                    .foregroundStyle(hovered ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(item.title)
    }
}

extension View {
    /// macOS 26+: the system's Liquid Glass material. Earlier: the visual-effect container this panel always used.
    @ViewBuilder func dockGlass(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.liquidGlassContainer(cornerRadius: cornerRadius)
        }
    }
}

/// A crisp card representing an active browser tab for Dock hover (supports 1..5 tabs).
struct DockBrowserTabCard: View {
    let tab: BrowserTabItem
    let appIcon: NSImage?
    let bundleID: String
    let pid: pid_t
    let primaryThumb: NSImage?
    var cardWidth: CGFloat = 240
    var cardHeight: CGFloat = 165
    var thumbWidth: CGFloat = 224
    var thumbHeight: CGFloat = 119
    let onPick: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            BrowserTabProvider.shared.selectTab(tab: tab, in: bundleID)
            WindowManager.activate(pid: pid)
            onPick()
        }) {
            VStack(alignment: .leading, spacing: 5) {
                // Header: favicon/app icon + title + domain
                HStack(spacing: 6) {
                    if let appIcon = appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: tab.isSecure ? "lock.fill" : "globe")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(tab.title.isEmpty ? tab.domain : tab.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(tab.domain)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if tab.isActive {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 26)
                .padding(.horizontal, 6)
                .padding(.top, 4)

                // Thumbnail: Retina crisp
                Group {
                    if let tabThumb = TabPreviewCache.shared.getPreview(tabId: tab.id) {
                        WindowThumbnailView(image: tabThumb, width: thumbWidth, height: thumbHeight)
                    } else if tab.isActive, let primaryThumb = primaryThumb {
                        WindowThumbnailView(image: primaryThumb, width: thumbWidth, height: thumbHeight)
                    } else {
                        WebSnapshotCardView(
                            tab: tab,
                            width: thumbWidth,
                            height: thumbHeight,
                            showFullDetails: false
                        )
                    }
                }
                .frame(width: thumbWidth, height: thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(width: cardWidth, height: cardHeight)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHovered ? Color.blue.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: isHovered ? Color.blue.opacity(0.18) : Color.black.opacity(0.08), radius: isHovered ? 8 : 4, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = h
            }
        }
    }
}

/// Placeholder card during initial async tab discovery.
struct DockTabPlaceholderCard: View {
    let title: String
    let appIcon: NSImage?
    var width: CGFloat = 240
    var height: CGFloat = 165

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let appIcon = appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .frame(height: 26)
            .padding(.horizontal, 6)
            .padding(.top, 4)

            ZStack {
                Color.white.opacity(0.06)
                ProgressView().scaleEffect(0.6)
            }
            .frame(width: width - 16, height: height - 46)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .frame(width: width, height: height)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}
