import Foundation
import AppKit
import ApplicationServices

private func checkWindowMinimized(windowID: CGWindowID, pid: pid_t) -> Bool {
    let appElement = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        for win in windows {
            var wid: CGWindowID = 0
            if axGetWindowID(win, &wid) == .success, wid == windowID {
                var minRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef) == .success,
                   let isMini = minRef as? Bool {
                    return isMini
                }
            }
        }
    }
    return false
}

/// Single source of truth for window previews and special previews.
@MainActor
@Observable
public final class WindowPreviewStore {
    public static let shared = WindowPreviewStore()

    // MARK: Hidden-app windows (the "Hiện cả cửa sổ ẩn" switch)

    /// The ONE reader of `windowPreview.showHiddenWindows`. The Xem trước cửa sổ page binds
    /// this key; `WindowManager.listWindows()` calls this accessor rather than reading the
    /// key again, so the default cannot drift between two copies (CLAUDE.md Part 0 §4/§5).
    /// Default `false` must equal the view's `@AppStorage` default —
    /// `FeatureKeyDefaultsTests` parses both and fails if they differ.
    public nonisolated static var showsHiddenWindows: Bool {
        UserDefaults.standard.object(forKey: "windowPreview.showHiddenWindows") as? Bool ?? false
    }

    /// Whether a window whose owning app is hidden (⌘H, or an app that hides its last
    /// window on close — Spotify, Slack) belongs in the list. Pure so the rule is testable
    /// without a real window server: hidden apps are listed only when the switch is on.
    public nonisolated static func listsWindow(ofHiddenApp isHidden: Bool, showHidden: Bool) -> Bool {
        !isHidden || showHidden
    }

    // MARK: Phase C — the ONE reader of each switcher key, and the pure rules behind the keys

    /// Bundle ids the switcher never lists. Read here and only here (the page writes through
    /// `setExcludedApps`); before Phase C the page and the store each read the key themselves.
    public nonisolated static var excludedApps: [String] {
        UserDefaults.standard.stringArray(forKey: "windowPreview.excludedApps") ?? []
    }
    public nonisolated static func setExcludedApps(_ apps: [String]) {
        UserDefaults.standard.set(apps, forKey: "windowPreview.excludedApps")
    }
    /// A window with no resolvable bundle id is never excluded — an empty string must not match an empty list entry.
    public nonisolated static func isExcluded(bundleID: String, excluded: Set<String>) -> Bool {
        !bundleID.isEmpty && excluded.contains(bundleID)
    }

    /// Multi-display: list only windows on the screen under the pointer. Off by default — the
    /// user's list must not shrink silently. Default must equal the page's `@AppStorage` (FeatureKeyDefaultsTests).
    public nonisolated static var currentScreenOnly: Bool {
        UserDefaults.standard.object(forKey: "windowPreview.currentScreenOnly") as? Bool ?? false
    }
    /// `CGWindowListCopyWindowInfo` bounds are top-left origin; `NSScreen.frame` is bottom-left. Both
    /// share the primary screen's height as the flip, so the two can be compared in CG space.
    public nonisolated static func cgRect(forAppKitFrame f: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }
    /// A window counts as "on this screen" when any part of it is — a window straddling two
    /// displays belongs to both.
    public nonisolated static func isOnScreen(_ w: WindowRef, screenCG: CGRect) -> Bool {
        w.bounds.intersects(screenCG)
    }

    /// One card per app (`apps`) or one card per window of one app (`windows`) — the ` key flips.
    public enum Mode: Equatable { case apps, windows(bundleID: String) }
    public var mode: Mode = .apps
    /// Space: a large capture of the selected window below the deck.
    public var isZoomed = false
    public var zoomImage: NSImage?
    /// Windows that survived exclusion and the screen filter, front-to-back, with their bundle ids.
    private var allowedWins: [WindowRef] = []
    private var bundleByWindow: [CGWindowID: String] = [:]
    private var appItems: [PreviewItem] = []
    private var lastScreenCG: CGRect?

    /// One card per window of `bundleID`, in z-order, titled by the window (or the app when untitled).
    public nonisolated static func windowItems(for bundleID: String, wins: [WindowRef], appName: String) -> [PreviewItem] {
        wins.map { w in
            PreviewItem(windowID: w.id, bundleID: bundleID, title: w.title.isEmpty ? appName : w.title, appName: appName,
                        isOnOtherSpace: !w.isOnCurrentSpace, isGroup: false, windowCount: 1, windowIDs: [w.id],
                        isStageMiniature: w.isStageMiniature)
        }
    }

    /// The deck after a window was closed (Q): the card of a one-window app disappears; a group
    /// shrinks, and if its representative window was the one closed the next window stands in.
    public nonisolated static func removing(windowID: CGWindowID, from items: [PreviewItem]) -> [PreviewItem] {
        items.compactMap { item in
            guard item.windowIDs.contains(windowID) else { return item }
            let rest = item.windowIDs.filter { $0 != windowID }
            guard let first = rest.first else { return nil }
            return PreviewItem(windowID: item.windowID == windowID ? first : item.windowID,
                               bundleID: item.bundleID, title: item.title, appName: item.appName,
                               thumbnail: item.windowID == windowID ? nil : item.thumbnail,
                               isFrozen: item.isFrozen, tabs: item.tabs, isOnOtherSpace: item.isOnOtherSpace,
                               isGroup: rest.count > 1, windowCount: rest.count, windowIDs: rest,
                               isStageMiniature: item.isStageMiniature)
        }
    }

    /// A selection that always points at a card (or 0 when there is none).
    public nonisolated static func clampedSelection(_ index: Int, count: Int) -> Int {
        count <= 0 ? 0 : min(max(0, index), count - 1)
    }

    public struct WindowRef: Identifiable, Sendable {
        public let id: CGWindowID
        public let ownerPID: pid_t
        public let ownerName: String
        public let title: String
        public let bounds: CGRect
        public let isOnCurrentSpace: Bool
        public let isStageMiniature: Bool

        public init(
            id: CGWindowID,
            ownerPID: pid_t,
            ownerName: String,
            title: String,
            bounds: CGRect = .zero,
            isOnCurrentSpace: Bool = true,
            isStageMiniature: Bool = false
        ) {
            self.id = id
            self.ownerPID = ownerPID
            self.ownerName = ownerName
            self.title = title
            self.bounds = bounds
            self.isOnCurrentSpace = isOnCurrentSpace
            self.isStageMiniature = isStageMiniature
        }
    }

    public var previewItems: [PreviewItem] = []
    public var activeBrowserTabs: [BrowserTabItem] = []
    public var calendarEvents: [CalendarEventItem] = []
    public var weatherInfo: WeatherInfo?
    public var needsAutomationPermission: Bool = false
    public var isScreenRecordingDenied: Bool = false
    public var searchQuery: String = ""
    public var selectedIndex: Int = 0
    public var isSearchActive: Bool = false

    public var filteredPreviewItems: [PreviewItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return previewItems }
        return previewItems.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed) ||
            item.bundleID.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public let captureProvider: ScreenCaptureProviding
    public let browserProvider: BrowserTabProvider
    public let calendarProvider: CalendarPreviewProvider
    public let weatherProvider: WeatherPreviewProvider

    public var windowLister: () -> [WindowRef] = {
        guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let showHidden = WindowPreviewStore.showsHiddenWindows
        var out: [WindowRef] = []
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

            let isMinimized = checkWindowMinimized(windowID: wid, pid: pid)
            if isMinimized && !isOnScreen { continue }

            let isStageMiniature = ScreenCaptureProvider.isStageManagerProxy(frame: bounds)
            let isOnOtherSpace = !isOnScreen && layer == 0 && !isHidden && !isMinimized && !isStageMiniature
            print("[Space] \(bundleID) onScreen=\(isOnScreen) hidden=\(isHidden) isStage=\(isStageMiniature) -> otherSpace=\(isOnOtherSpace)")

            let title = (dict[kCGWindowName as String] as? String) ?? ""
            out.append(WindowRef(id: wid, ownerPID: pid, ownerName: owner, title: title, bounds: bounds, isOnCurrentSpace: isOnScreen, isStageMiniature: isStageMiniature))
        }
        return out
    }

    public init(
        captureProvider: ScreenCaptureProviding = ScreenCaptureProvider.shared,
        browserProvider: BrowserTabProvider = BrowserTabProvider.shared,
        calendarProvider: CalendarPreviewProvider = CalendarPreviewProvider.shared,
        weatherProvider: WeatherPreviewProvider = WeatherPreviewProvider.shared
    ) {
        self.captureProvider = captureProvider
        self.browserProvider = browserProvider
        self.calendarProvider = calendarProvider
        self.weatherProvider = weatherProvider
    }

    /// At most this many window cards in the Dock preview; the header says how many more there are.
    nonisolated public static let dockMaxCards = 4
    /// The app's real windows through Accessibility (set by the app at launch; nil in tests and without the permission).
    public var axWindowIDs: (pid_t) -> Set<CGWindowID>? = { _ in nil }

    /// The windows a Dock preview shows, in order (pure, tested). Tiny utility windows (palettes, < 260 × 180) are left
    /// out unless they are all there is; a Stage Manager strip tile IS the app's parked window and stays. Titled windows
    /// on the current Space come first, then other titled ones, then the rest — each group in the lister's z-order.
    ///
    /// `axWindows` (the app's own window list through Accessibility) decides what a window IS when known: measured
    /// 2026-10-20, CGWindowList lists every Finder TAB as a window (Finder with one 3-tab window and one other window:
    /// 5 entries, AX says 2) and every app's hidden helper windows (Claude 3 sized entries, AX 1; TradingView 6, AX 1).
    nonisolated public static func dockWindowCards(_ wins: [WindowRef], axWindows: Set<CGWindowID>? = nil) -> [WindowRef] {
        if let ax = axWindows, !ax.isEmpty {
            let known = wins.filter { ax.contains($0.id) }
            if !known.isEmpty { return dockWindowCards(known) }
        }
        let real = wins.filter { $0.isStageMiniature || ($0.bounds.width >= 260 && $0.bounds.height >= 180) }
        let pool = real.isEmpty ? wins : real
        func rank(_ w: WindowRef) -> Int { (w.title.isEmpty ? 2 : 0) + (w.isOnCurrentSpace || w.isStageMiniature ? 0 : 1) }
        return pool.enumerated().sorted { a, b in
            rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
        }.map(\.element)
    }

    /// Load window previews for a specific application PID (for Dock hover).
    public func loadDockPreviews(for pid: pid_t) {
        let allWins = windowLister().filter { $0.ownerPID == pid }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let isBrowser = BrowserTabProvider.isSupportedBrowser(bundleID: bundleID)

        // Browsers: one primary window (their tabs are the cards). Other apps: one card per window (2026-10-19 redesign),
        // see `dockWindowCards`.
        let windows = Self.dockWindowCards(allWins, axWindows: axWindowIDs(pid))
        guard let win = windows.first else {
            self.previewItems = []
            self.activeBrowserTabs = []
            return
        }

        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? win.ownerName
        let fallbackTitle = allWins.first(where: { !$0.title.isEmpty })?.title ?? ""
        let title = win.title.isEmpty ? (fallbackTitle.isEmpty ? appName : fallbackTitle) : win.title
        let item = PreviewItem(
            windowID: win.id,
            bundleID: bundleID,
            title: title,
            appName: appName,
            thumbnail: (captureProvider as? ScreenCaptureProvider)?.cache.get(win.id),
            isFrozen: false,
            tabs: [],
            isOnOtherSpace: !win.isOnCurrentSpace,
            isGroup: false,
            windowCount: allWins.count,
            windowIDs: allWins.map { $0.id },
            isStageMiniature: win.isStageMiniature
        )
        if isBrowser {
            self.previewItems = [item]
        } else {
            let cache = (captureProvider as? ScreenCaptureProvider)?.cache
            self.previewItems = windows.prefix(Self.dockMaxCards).map { w in
                PreviewItem(windowID: w.id, bundleID: bundleID,
                            title: w.title.isEmpty ? appName : w.title, appName: appName,
                            thumbnail: cache?.get(w.id), isFrozen: false, tabs: [],
                            isOnOtherSpace: !w.isOnCurrentSpace && !w.isStageMiniature, isGroup: false,
                            windowCount: windows.count, windowIDs: [w.id], isStageMiniature: w.isStageMiniature)
            }
        }
        self.isScreenRecordingDenied = !captureProvider.isScreenRecordingAllowed()

        // Asynchronously fetch thumbnails (fresh cache entries come back without a capture).
        let ids = self.previewItems.map(\.windowID)
        Task {
            let thumbs = await captureProvider.captureWindows(windowIDs: ids, maxSize: 800)
            for (i, it) in self.previewItems.enumerated() where it.bundleID == bundleID {
                if let thumb = thumbs[it.windowID] { self.previewItems[i].thumbnail = thumb }
            }
            if isBrowser, let thumb = thumbs[win.id],
               let actTab = self.activeBrowserTabs.first(where: { $0.isActive }) ?? self.activeBrowserTabs.first {
                TabPreviewCache.shared.setPreview(tabId: actTab.id, image: thumb)
            }
        }

        // Special previews for Dock: browsers show all open tabs; normal apps do not
        if isBrowser {
            Task {
                let tabs = await browserProvider.getAllTabs(for: bundleID)
                if !self.previewItems.isEmpty {
                    self.previewItems[0].tabs = tabs
                    if let act = tabs.first(where: { $0.isActive }) ?? tabs.first, !act.title.isEmpty {
                        self.previewItems[0].title = act.title
                        if let tabThumb = TabPreviewCache.shared.getPreview(tabId: act.id) {
                            self.previewItems[0].thumbnail = tabThumb
                        } else if let winThumb = self.previewItems[0].thumbnail {
                            TabPreviewCache.shared.setPreview(tabId: act.id, image: winThumb)
                        }
                    }
                }
                self.activeBrowserTabs = tabs
                self.needsAutomationPermission = browserProvider.needsAutomationPermission
            }
        } else {
            self.activeBrowserTabs = []
            self.needsAutomationPermission = false
        }

        if bundleID == "com.apple.iCal" {
            Task {
                self.calendarEvents = await calendarProvider.fetchNextEvents()
            }
        } else {
            self.calendarEvents = []
        }

        if bundleID == "com.apple.weather" {
            Task {
                self.weatherInfo = await weatherProvider.fetchWeather()
            }
        } else {
            self.weatherInfo = nil
        }
    }

    /// Load all switchable windows for Cmd+Tab overlay (1 preview card per application).
    /// `screenCG`: when set (Phase C, `currentScreenOnly`), only windows intersecting it are listed.
    public func loadSwitchableWindows(screenCG: CGRect? = nil) {
        let excluded = Set(Self.excludedApps)
        let allWins = windowLister()
        var wins = allWins.filter { $0.bounds.width >= 40 && $0.bounds.height >= 40 }
        if let screenCG { wins = wins.filter { Self.isOnScreen($0, screenCG: screenCG) } }
        lastScreenCG = screenCG

        // Filter excluded apps
        let allowedWins = wins.filter { win in
            let bID = NSRunningApplication(processIdentifier: win.ownerPID)?.bundleIdentifier ?? ""
            return !Self.isExcluded(bundleID: bID, excluded: excluded)
        }

        // Group by bundleID preserving front-to-back z-order
        var orderedBundleIDs: [String] = []
        var winsByBundle: [String: [WindowRef]] = [:]
        var bundleByWindow: [CGWindowID: String] = [:]
        for win in allowedWins {
            let bID = NSRunningApplication(processIdentifier: win.ownerPID)?.bundleIdentifier ?? (win.ownerName.isEmpty ? "unknown" : win.ownerName)
            if winsByBundle[bID] == nil {
                orderedBundleIDs.append(bID)
                winsByBundle[bID] = []
            }
            winsByBundle[bID]?.append(win)
            bundleByWindow[win.id] = bID
        }
        self.allowedWins = allowedWins
        self.bundleByWindow = bundleByWindow
        self.mode = .apps
        self.isZoomed = false
        self.zoomImage = nil

        var items: [PreviewItem] = []
        for bID in orderedBundleIDs {
            guard let appWins = winsByBundle[bID], !appWins.isEmpty else { continue }
            // Pick most active/frontmost window on current space if available, preferring non-miniature
            let nonMiniatures = appWins.filter { !$0.isStageMiniature }
            let bestWin = nonMiniatures.first(where: { $0.isOnCurrentSpace })
                ?? nonMiniatures.first
                ?? appWins.first(where: { $0.isOnCurrentSpace })
                ?? appWins.first!
            let appName = NSRunningApplication(processIdentifier: bestWin.ownerPID)?.localizedName ?? (bestWin.ownerName.isEmpty ? bID : bestWin.ownerName)
            let fallbackTitle = appWins.first(where: { !$0.title.isEmpty })?.title ?? ""
            let title = bestWin.title.isEmpty ? (fallbackTitle.isEmpty ? appName : fallbackTitle) : bestWin.title
            let cachedThumb = (captureProvider as? ScreenCaptureProvider)?.cache.get(bestWin.id)

            let item = PreviewItem(
                windowID: bestWin.id,
                bundleID: bID,
                title: title,
                appName: appName,
                thumbnail: cachedThumb,
                isFrozen: false,
                tabs: [],
                isOnOtherSpace: !bestWin.isOnCurrentSpace,
                isGroup: appWins.count > 1,
                windowCount: appWins.count,
                windowIDs: appWins.map { $0.id },
                isStageMiniature: bestWin.isStageMiniature
            )
            items.append(item)
        }

        self.previewItems = items
        self.appItems = items
        self.selectedIndex = self.previewItems.count > 1 ? 1 : 0
        self.isScreenRecordingDenied = !captureProvider.isScreenRecordingAllowed()
        fetchThumbnails()

        // Switcher does NOT show Open Tabs
        self.activeBrowserTabs = []
        if self.previewItems.indices.contains(self.selectedIndex) {
            let current = self.previewItems[self.selectedIndex]
            if current.bundleID == "com.apple.iCal" || current.bundleID == "com.apple.weather" {
                loadSpecialPreviews(for: current)
            }
        }
    }

    private func fetchThumbnails() {
        let ids = self.previewItems.filter { $0.windowID != 0 }.map { $0.windowID }
        guard !ids.isEmpty else { return }
        Task {
            let thumbs = await captureProvider.captureWindows(windowIDs: ids, maxSize: 800)
            for (idx, item) in self.previewItems.enumerated() {
                if let thumb = thumbs[item.windowID] {
                    self.previewItems[idx].thumbnail = thumb
                }
            }
        }
    }

    // MARK: Phase C — app ⇄ window mode, zoom, close/hide bookkeeping

    /// ` : one card per window of the selected app, and back. Selection lands on the first window,
    /// and returns to the app's card on the way back.
    public func toggleMode() {
        isZoomed = false; zoomImage = nil
        switch mode {
        case .apps:
            guard let current = commitSelection() else { return }
            let wins = allowedWins.filter { bundleByWindow[$0.id] == current.bundleID }
            guard !wins.isEmpty else { return }
            mode = .windows(bundleID: current.bundleID)
            previewItems = Self.windowItems(for: current.bundleID, wins: wins, appName: current.appName).map { item in
                var i = item; i.thumbnail = (captureProvider as? ScreenCaptureProvider)?.cache.get(i.windowID); return i
            }
            selectedIndex = 0
            fetchThumbnails()
        case .windows(let bundleID):
            mode = .apps
            previewItems = appItems
            selectedIndex = Self.clampedSelection(appItems.firstIndex { $0.bundleID == bundleID } ?? 0, count: appItems.count)
        }
    }

    /// Space: a large capture of the selected window. Re-fetched on every step while zoomed.
    public func toggleZoom() {
        isZoomed.toggle()
        if isZoomed { refreshZoom() } else { zoomImage = nil }
    }

    public func refreshZoom() {
        guard isZoomed, let item = commitSelection(), item.windowID != 0 else { zoomImage = nil; return }
        zoomImage = item.thumbnail
        let id = item.windowID
        Task {
            let big = await captureProvider.captureWindows(windowIDs: [id], maxSize: 1600)
            if self.isZoomed, self.commitSelection()?.windowID == id, let img = big[id] { self.zoomImage = img }
        }
    }

    /// Q: the window is gone — update both decks locally (the window server lags the AX press).
    public func removeWindow(id: CGWindowID) {
        allowedWins.removeAll { $0.id == id }
        bundleByWindow[id] = nil
        appItems = Self.removing(windowID: id, from: appItems)
        previewItems = Self.removing(windowID: id, from: previewItems)
        if case .windows = mode, previewItems.isEmpty { mode = .apps; previewItems = appItems }
        selectedIndex = Self.clampedSelection(selectedIndex, count: previewItems.count)
        if isZoomed { refreshZoom() }
    }

    /// H: every card of the app is gone.
    public func removeApp(bundleID: String) {
        allowedWins.removeAll { bundleByWindow[$0.id] == bundleID }
        bundleByWindow = bundleByWindow.filter { $0.value != bundleID }
        appItems.removeAll { $0.bundleID == bundleID }
        if case .windows(let b) = mode, b == bundleID { mode = .apps }
        previewItems = (mode == .apps) ? appItems : previewItems.filter { $0.bundleID != bundleID }
        selectedIndex = Self.clampedSelection(selectedIndex, count: previewItems.count)
        if isZoomed { refreshZoom() }
    }

    /// Re-list after Q/H settled, keeping the mode (the window server is the truth; the local
    /// removal above was only the immediate feedback).
    public func reload() {
        let keep = mode
        let sel = commitSelection()
        loadSwitchableWindows(screenCG: lastScreenCG)
        if case .windows(let b) = keep, let idx = appItems.firstIndex(where: { $0.bundleID == b }) {
            selectedIndex = idx
            toggleMode()
            if let sel, let i = previewItems.firstIndex(where: { $0.windowID == sel.windowID }) { selectedIndex = i }
        } else if let sel, let i = previewItems.firstIndex(where: { $0.bundleID == sel.bundleID }) {
            selectedIndex = i
        }
    }

    public func step(forward: Bool) {
        let items = filteredPreviewItems
        guard !items.isEmpty else { return }
        if forward {
            selectedIndex = (selectedIndex + 1) % items.count
        } else {
            selectedIndex = (selectedIndex - 1 + items.count) % items.count
        }
    }

    public func select(index: Int) {
        let items = filteredPreviewItems
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Calculates how many cards comfortably fit on a display of given width (clamped to 5...7).
    public nonisolated static func maxVisibleCards(screenWidth: CGFloat) -> Int {
        max(5, min(7, Int((screenWidth - 160) / 232)))
    }

    public func commitSelection() -> PreviewItem? {
        let items = filteredPreviewItems
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    /// Load special previews for a highlighted preview item.
    public func loadSpecialPreviews(for item: PreviewItem) {
        let bID = item.bundleID
        self.activeBrowserTabs = []
        self.needsAutomationPermission = false

        if bID == "com.apple.iCal" {
            Task {
                self.calendarEvents = await calendarProvider.fetchNextEvents()
            }
        } else {
            self.calendarEvents = []
        }

        if bID == "com.apple.weather" {
            Task {
                self.weatherInfo = await weatherProvider.fetchWeather()
            }
        } else {
            self.weatherInfo = nil
        }
    }

    public func clear() {
        mode = .apps; isZoomed = false; zoomImage = nil
        allowedWins = []; bundleByWindow = [:]; appItems = []; lastScreenCG = nil
        previewItems = []
        activeBrowserTabs = []
        calendarEvents = []
        weatherInfo = nil
        needsAutomationPermission = false
        searchQuery = ""
        selectedIndex = 0
        isSearchActive = false
    }
}
