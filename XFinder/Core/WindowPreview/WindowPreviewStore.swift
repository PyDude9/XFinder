import Foundation
import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindowFromRef(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

private func checkWindowMinimized(windowID: CGWindowID, pid: pid_t) -> Bool {
    let appElement = AXUIElementCreateApplication(pid)
    var windowsRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        for win in windows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindowFromRef(win, &wid) == .success, wid == windowID {
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

            let isStageMiniature = (bounds.width <= 260 && bounds.height <= 260) || (bounds.origin.x <= 80 && bounds.width <= 280)
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

    /// Load window previews for a specific application PID (for Dock hover).
    public func loadDockPreviews(for pid: pid_t) {
        let allWins = windowLister().filter { $0.ownerPID == pid }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        let isBrowser = BrowserTabProvider.isSupportedBrowser(bundleID: bundleID)

        // Dock hover: strictly 1 primary window preview.
        // Filter out Stage Manager miniature tiles and tiny utility windows:
        let validWins = allWins.filter { !$0.isStageMiniature && $0.bounds.width >= 260 && $0.bounds.height >= 180 }
        let candidates = !validWins.isEmpty ? validWins : allWins
        let titledWins = candidates.filter { !$0.title.isEmpty }
        guard let win = titledWins.first(where: { $0.isOnCurrentSpace })
            ?? titledWins.first
            ?? candidates.first(where: { $0.isOnCurrentSpace })
            ?? candidates.first else {
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
        self.previewItems = [item]
        self.isScreenRecordingDenied = !captureProvider.isScreenRecordingAllowed()

        // Asynchronously fetch thumbnail
        Task {
            let thumbs = await captureProvider.captureWindows(windowIDs: [win.id], maxSize: 800)
            if let thumb = thumbs[win.id], !self.previewItems.isEmpty {
                self.previewItems[0].thumbnail = thumb
                if isBrowser, let actTab = self.activeBrowserTabs.first(where: { $0.isActive }) ?? self.activeBrowserTabs.first {
                    TabPreviewCache.shared.setPreview(tabId: actTab.id, image: thumb)
                }
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
    public func loadSwitchableWindows() {
        let excluded = Set(UserDefaults.standard.stringArray(forKey: "windowPreview.excludedApps") ?? [])
        let allWins = windowLister()
        let wins = allWins.filter { $0.bounds.width >= 40 && $0.bounds.height >= 40 }

        // Filter excluded apps
        let allowedWins = wins.filter { win in
            let bID = NSRunningApplication(processIdentifier: win.ownerPID)?.bundleIdentifier ?? ""
            return bID.isEmpty || !excluded.contains(bID)
        }

        // Group by bundleID preserving front-to-back z-order
        var orderedBundleIDs: [String] = []
        var winsByBundle: [String: [WindowRef]] = [:]
        for win in allowedWins {
            let bID = NSRunningApplication(processIdentifier: win.ownerPID)?.bundleIdentifier ?? (win.ownerName.isEmpty ? "unknown" : win.ownerName)
            if winsByBundle[bID] == nil {
                orderedBundleIDs.append(bID)
                winsByBundle[bID] = []
            }
            winsByBundle[bID]?.append(win)
        }

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
        self.selectedIndex = self.previewItems.count > 1 ? 1 : 0
        self.isScreenRecordingDenied = !captureProvider.isScreenRecordingAllowed()

        let ids = self.previewItems.filter { $0.windowID != 0 }.map { $0.windowID }
        Task {
            let thumbs = await captureProvider.captureWindows(windowIDs: ids, maxSize: 800)
            for (idx, item) in self.previewItems.enumerated() {
                if let thumb = thumbs[item.windowID] {
                    self.previewItems[idx].thumbnail = thumb
                }
            }
        }

        // Switcher does NOT show Open Tabs
        self.activeBrowserTabs = []
        if self.previewItems.indices.contains(self.selectedIndex) {
            let current = self.previewItems[self.selectedIndex]
            if current.bundleID == "com.apple.iCal" || current.bundleID == "com.apple.weather" {
                loadSpecialPreviews(for: current)
            }
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
