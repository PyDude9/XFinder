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
    private var warmLog: [pid_t: Date] = [:]

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
        // Real windows through Accessibility (tabs and hidden helper windows are not windows) — see dockWindowCards.
        WindowPreviewStore.shared.axWindowIDs = { axWindowIDs(pid: $0) }
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
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard WindowManager.isStageManagerEnabled,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated {      // queue: .main
                    guard let self, ThumbnailFreshness.claimWarm(pid: pid, now: Date(), log: &self.warmLog) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        Task.detached(priority: .utility) { await ScreenCaptureProvider.shared.warmUprightPictures(pid: pid) }
                    }
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
        warmLog = [:]
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
        if panelPID == icon.pid, panel != nil { return }
        // Load first, then size from what will actually be drawn: the panel was sized from one count (CG windows, tabs
        // included) and drew another — an empty slot, or content taller than the panel spilling past the screen edge.
        WindowPreviewStore.shared.loadDockPreviews(for: icon.pid)
        let windowCount = isBrowser ? 1 : WindowPreviewStore.dockCardItems(WindowPreviewStore.shared.previewItems).count
        let dims = isBrowser ? browserPanelDimensions(tabCount: tabCount)
            : windowPanelDimensions(count: windowCount).withExtraHeight(DockPreviewView.widgetHeight(bundleID, WindowPreviewStore.shared))
        let panelWidth = dims.panelWidth
        let panelHeight = dims.panelHeight

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
        host.layer?.cornerRadius = DockCard.panelRadius
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
        let dockItems = WindowPreviewStore.dockCardItems(store.previewItems)
        let visibleTabs = isBrowser ? activeTabsForDockPreview(store.activeBrowserTabs) : []
        let tabCount = visibleTabs.count
        let dims = browserPanelDimensions(tabCount: max(1, tabCount))

        Group {
            if isBrowser && tabCount >= 2 {
                // Windows Taskbar style: up to 5 preview cards side by side (active tabs only)
                HStack(spacing: DockCard.gap) {
                    ForEach(visibleTabs) { tab in
                        DockBrowserTabCard(
                            tab: tab,
                            appIcon: ClipboardAppIcon.icon(forBundleID: bundleID),
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
                .padding(DockCard.padding)
                .frame(width: dims.panelWidth, height: dims.panelHeight)
            } else if !isBrowser {
                DockWindowCardsView(pid: pid, title: title,
                                    items: WindowPreviewStore.dockCardItems(store.previewItems),
                                    store: store, onPick: onPick)
            } else {
                // Single card mode: a browser with one tab — the same DockCard as every other preview.
                let targetHeight: CGFloat = windowPanelDimensions(count: 1).withExtraHeight(Self.widgetHeight(bundleID, store)).panelHeight

                VStack(alignment: .leading, spacing: 6) {
                    // Header: DockCard.header
                    HStack(spacing: 7) {
                        if let icon = ClipboardAppIcon.icon(forBundleID: bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        let curTab = visibleTabs.first ?? store.activeBrowserTabs.first(where: { $0.isActive }) ?? store.activeBrowserTabs.first
                        Text(curTab.map { $0.title.isEmpty ? $0.domain : $0.title } ?? (dockItems.first?.appName ?? title))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                    }
                    .frame(height: DockCard.header)

                    // Thumbnail / WebSnapshotCardView / AppHeroCardView: one DockCard picture
                    if isBrowser, let cur = visibleTabs.first ?? store.activeBrowserTabs.first(where: { $0.isActive }) ?? store.activeBrowserTabs.first {
                        Button(action: {
                            BrowserTabProvider.shared.selectTab(tab: cur, in: bundleID)
                            WindowManager.activate(pid: pid)
                            onPick()
                        }) {
                            if let tabThumb = TabPreviewCache.shared.getPreview(tabId: cur.id) {
                                WindowThumbnailView(image: tabThumb, width: DockCard.thumbWidth, height: DockCard.thumbHeight)
                            } else if let firstThumb = dockItems.first?.thumbnail {
                                WindowThumbnailView(image: firstThumb, width: DockCard.thumbWidth, height: DockCard.thumbHeight)
                            } else {
                                WebSnapshotCardView(
                                    tab: cur,
                                    width: DockCard.thumbWidth,
                                    height: DockCard.thumbHeight,
                                    showFullDetails: true
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    } else if let first = dockItems.first {
                        Button(action: {
                            WindowManager.activate(pid: pid)
                            onPick()
                        }) {
                            if let thumb = first.thumbnail {
                                WindowThumbnailView(image: thumb, width: DockCard.thumbWidth, height: DockCard.thumbHeight)
                            } else {
                                AppHeroCardView(
                                    appName: first.appName.isEmpty ? title : first.appName,
                                    title: first.title.isEmpty ? (first.appName.isEmpty ? title : first.appName) : first.title,
                                    bundleID: bundleID,
                                    isStageMiniature: first.isStageMiniature,
                                    isOnOtherSpace: first.isOnOtherSpace,
                                    width: DockCard.thumbWidth,
                                    height: DockCard.thumbHeight
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        ZStack {
                            Color.white.opacity(0.06)
                            ProgressView().scaleEffect(0.6)
                        }
                        .frame(width: DockCard.thumbWidth, height: DockCard.thumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .padding(DockCard.padding + DockCard.inset)
                .frame(width: DockCard.width + 2 * DockCard.padding, height: targetHeight)
            }
        }
        .dockGlass(cornerRadius: DockCard.panelRadius)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.8)) {
                offset = 0
                opacity = 1.0
            }
        }
        .onChange(of: pid) { _, newPID in
        }
        .onChange(of: store.calendarEvents.count + (store.weatherInfo == nil ? 0 : 1)) { _, _ in
            guard !isBrowser else { return }   // a widget arriving after the panel opened grows it
            let dims = windowPanelDimensions(count: WindowPreviewStore.dockCardItems(store.previewItems).count)
                .withExtraHeight(Self.widgetHeight(bundleID, store))
            DockPreviewController.shared.updatePanelSize(width: dims.panelWidth, height: dims.panelHeight, animated: true)
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

    /// Calendar's next events / Weather's conditions under the cards (60 pt), else nothing.
    static func widgetHeight(_ bundleID: String, _ store: WindowPreviewStore) -> CGFloat {
        (bundleID == "com.apple.iCal" && !store.calendarEvents.isEmpty) || (bundleID == "com.apple.weather" && store.weatherInfo != nil) ? 60 : 0
    }
}

/// One card per window of a non-browser app: the same card the browser uses for its single tab — header (icon, window
/// title, app name) over a DockCard picture of the whole window, never cropped — side by side, at most four. A click
/// raises THAT window. Fixed size: only the number of cards changes from app to app.
struct DockWindowCardsView: View {
    let pid: pid_t
    let title: String
    let items: [PreviewItem]
    let store: WindowPreviewStore
    let onPick: () -> Void

    var body: some View {
        let dims = windowPanelDimensions(count: items.count)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: DockCard.gap) {
                if items.isEmpty {
                    DockWindowCard(item: nil, fallbackTitle: title, pid: pid, dims: dims, onPick: onPick)
                } else {
                    ForEach(items) { item in
                        DockWindowCard(item: item, fallbackTitle: title, pid: pid, dims: dims, onPick: onPick)
                    }
                }
            }
            if let bid = items.first?.bundleID, bid == "com.apple.iCal", !store.calendarEvents.isEmpty {
                CalendarPreviewView(events: store.calendarEvents).frame(height: 54)
            } else if let bid = items.first?.bundleID, bid == "com.apple.weather", let weather = store.weatherInfo {
                WeatherPreviewView(weather: weather).frame(height: 54)
            }
        }
        .padding(DockCard.padding)
    }
}

private struct DockWindowCard: View {
    let item: PreviewItem?
    let fallbackTitle: String
    let pid: pid_t
    let dims: DockPreviewDimensions
    let onPick: () -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            guard let item else { return }
            let info = WindowManager.WindowInfo(id: item.windowID, ownerPID: pid, ownerName: item.appName, title: item.title,
                                                bounds: .zero, isOnScreen: true)
            WindowManager.raiseWindow(info)
            onPick()
        } label: {
            // The switcher card's anatomy, without its subtitle and corner badge, and without a card around it: the app
            // name, then the picture — hover outlines the picture instead of filling a card.
            VStack(alignment: .leading, spacing: DockCard.headerGap) {
                HStack(spacing: 6) {
                    if let icon = ClipboardAppIcon.icon(forBundleID: item?.bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(item?.appName ?? fallbackTitle)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: DockCard.header)
                WindowThumbnailView(image: item?.thumbnail, width: dims.thumbWidth, height: dims.thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DockCard.thumbRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DockCard.thumbRadius, style: .continuous)
                            .strokeBorder(hovered ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    }
            }
            .frame(width: dims.cardWidth, height: dims.cardHeight, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(item?.title ?? fallbackTitle)
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
            // The window card's anatomy (DockWindowCard): icon + the tab's title on one line, then the picture with the
            // thin MacBook-style bezel; hover outlines the picture. No card fill, frame or shadow of its own.
            VStack(alignment: .leading, spacing: DockCard.headerGap) {
                HStack(spacing: 6) {
                    if let appIcon {
                        Image(nsImage: appIcon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: tab.isSecure ? "lock.fill" : "globe").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(tab.title.isEmpty ? tab.domain : tab.title)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if tab.isActive {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    }
                }
                .frame(height: DockCard.header)
                Group {
                    if let tabThumb = TabPreviewCache.shared.getPreview(tabId: tab.id) {
                        WindowThumbnailView(image: tabThumb, width: thumbWidth, height: thumbHeight)
                    } else if tab.isActive, let primaryThumb = primaryThumb {
                        WindowThumbnailView(image: primaryThumb, width: thumbWidth, height: thumbHeight)
                    } else {
                        WebSnapshotCardView(tab: tab, width: thumbWidth, height: thumbHeight, showFullDetails: false)
                    }
                }
                .frame(width: thumbWidth, height: thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: DockCard.thumbRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DockCard.thumbRadius, style: .continuous)
                        .strokeBorder(isHovered ? Color.accentColor : Color.clear, lineWidth: 1.5)
                }
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .help(tab.title.isEmpty ? tab.domain : tab.title)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = h
            }
        }
    }
}

