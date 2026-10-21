import Foundation
import AppKit
import EventKit

// MARK: - Browser Tabs

public typealias BrowserTab = BrowserTabItem

public struct BrowserTabItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: String
    public let isFrozen: Bool
    public var isActive: Bool
    public var isHidden: Bool
    public var hasContent: Bool {
        !url.isEmpty && url != "about:blank" && url != "chrome://newtab" && url != "edge://newtab" && !title.isEmpty
    }
    public var isDiscarded: Bool {
        title.lowercased().contains("discarded") || url.lowercased().contains("discarded")
    }
    public var domain: String {
        guard let u = URL(string: url), let host = u.host else {
            return url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    public var isSecure: Bool {
        url.lowercased().hasPrefix("https://")
    }
    public var fragmentOrQuery: String {
        guard let u = URL(string: url) else { return "" }
        if let frag = u.fragment, !frag.isEmpty {
            return "#" + frag
        }
        if let query = u.query, !query.isEmpty {
            return "?" + (query.count > 28 ? String(query.prefix(25)) + "..." : query)
        }
        return ""
    }
    public var pathDisplay: String {
        guard let u = URL(string: url) else { return "" }
        let p = u.path
        return p.isEmpty || p == "/" ? "" : p
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        url: String,
        isFrozen: Bool = false,
        isActive: Bool = true,
        isHidden: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.isFrozen = isFrozen
        self.isActive = isActive
        self.isHidden = isHidden
    }
}

// Cho browser/dock hover — hiển thị TẤT CẢ tab mở có nội dung, không discard, không freeze
public func isTabPreviewableForDock(_ t: BrowserTab) -> Bool {
    return !t.isHidden && !t.isFrozen && !t.isDiscarded && !t.url.isEmpty && t.hasContent
}

/// Filters browser tabs to show in Dock preview:
/// Only tabs that are active / currently in use (up to a maximum of 5 tabs).
/// If no tab is explicitly active (e.g. edge cases), falls back to the 1st previewable tab.
public func activeTabsForDockPreview(_ tabs: [BrowserTabItem], maxCount: Int = 5) -> [BrowserTabItem] {
    let eligible = tabs.filter(isTabPreviewableForDock)
    let active = eligible.filter { $0.isActive }
    if !active.isEmpty {
        return Array(active.prefix(maxCount))
    }
    if let first = eligible.first {
        return [first]
    }
    return []
}

public struct DockPreviewDimensions: Equatable {
    public let panelWidth: CGFloat
    public let panelHeight: CGFloat
    public let cardWidth: CGFloat
    public let cardHeight: CGFloat
    public let thumbWidth: CGFloat
    public let thumbHeight: CGFloat

    public init(
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        thumbWidth: CGFloat,
        thumbHeight: CGFloat
    ) {
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.thumbWidth = thumbWidth
        self.thumbHeight = thumbHeight
    }
}

/// One card for every Dock preview — a window, a browser's single tab or its tab row. The switcher's 184 × 86 picture
/// and app-name header, with a bezel as thin as a MacBook Pro's (owner, 2026-10-21: "so thin you barely see it"): no
/// inset inside the card, 6 pt from the picture to the panel edge, 6 pt between cards, and a panel corner concentric
/// with the picture's (8 + 6 = 14). Only the number of cards changes the panel.
public enum DockCard {
    public static let thumbWidth: CGFloat = 184
    public static let thumbHeight: CGFloat = 86
    public static let thumbRadius: CGFloat = 8
    public static let inset: CGFloat = 0
    public static let header: CGFloat = 20
    public static let headerGap: CGFloat = 5
    public static let padding: CGFloat = 6
    public static let gap: CGFloat = 6
    /// Concentric with the picture's corner: the bezel reads as one even line all round.
    public static var panelRadius: CGFloat { thumbRadius + padding }
    public static var width: CGFloat { thumbWidth + 2 * inset }
    public static var height: CGFloat { inset + header + headerGap + thumbHeight + inset }

    /// Panel for `count` cards (1…`maxCards`).
    public static func panel(count: Int, maxCards: Int) -> (width: CGFloat, height: CGFloat) {
        let n = CGFloat(max(1, min(maxCards, count)))
        return (n * width + (n - 1) * gap + 2 * padding, height + 2 * padding)
    }
}

/// Browser tabs: exactly the window card (DockBrowserTabCard draws the same header + picture), up to five.
public func browserPanelDimensions(tabCount: Int) -> DockPreviewDimensions { dockPanelDimensions(count: tabCount, maxCards: 5) }

/// Windows of a non-browser app: one `DockCard` per window, at most four.
public func windowPanelDimensions(count: Int) -> DockPreviewDimensions { dockPanelDimensions(count: count, maxCards: 4) }

private func dockPanelDimensions(count: Int, maxCards: Int) -> DockPreviewDimensions {
    let p = DockCard.panel(count: count, maxCards: maxCards)
    return DockPreviewDimensions(panelWidth: p.width, panelHeight: p.height, cardWidth: DockCard.width, cardHeight: DockCard.height,
                                 thumbWidth: DockCard.thumbWidth, thumbHeight: DockCard.thumbHeight)
}

extension DockPreviewDimensions {
    /// The same panel with room for a widget row under the cards (Calendar, Weather).
    public func withExtraHeight(_ h: CGFloat) -> DockPreviewDimensions {
        DockPreviewDimensions(panelWidth: panelWidth, panelHeight: panelHeight + h, cardWidth: cardWidth, cardHeight: cardHeight,
                              thumbWidth: thumbWidth, thumbHeight: thumbHeight)
    }
}

// Cho Cmd+Tab switcher — hiện TẤT CẢ tabs của window đó nhưng vẫn có label
public func isTabVisibleForSwitcher(_ t: BrowserTab) -> Bool {
    return !t.isDiscarded && !t.isHidden
}

public func isTabPreviewable(_ tab: BrowserTab) -> Bool {
    return isTabPreviewableForDock(tab)
}

public func isTabEligible(_ tab: BrowserTab) -> Bool {
    return isTabPreviewableForDock(tab)
}

public func isWindowPreviewable(_ item: PreviewItem) -> Bool {
    guard let thumb = item.thumbnail else { return false }
    return !item.isFrozen && thumb.size.width > 10
}

public final class BrowserTabProvider: @unchecked Sendable {
    public static let shared = BrowserTabProvider()

    public var needsAutomationPermission: Bool = false
    private var mockTabs: [String: [BrowserTabItem]] = [:]
    private let lock = NSLock()

    public init() {}

    public func getAllTabs(for bundleID: String) async -> [BrowserTabItem] {
        let tabs = await fetchTabs(bundleID: bundleID)
        let filtered = tabs.filter(isTabPreviewableForDock)
        // Sort active tab first, then keep original tab order
        return filtered.sorted { $0.isActive && !$1.isActive }
    }

    public func setMockTabs(for bundleID: String, tabs: [BrowserTabItem]) {
        lock.lock()
        defer { lock.unlock() }
        mockTabs[bundleID] = tabs
    }

    public static func isSupportedBrowser(bundleID: String) -> Bool {
        return bundleID == "com.apple.Safari" ||
               bundleID == "com.google.Chrome" ||
               bundleID == "com.microsoft.edgems" ||
               bundleID == "com.microsoft.Edge"
    }

    public static func isTabFrozen(title: String, url: String) -> Bool {
        let t = title.lowercased()
        let u = url.lowercased()
        if t.contains("discarded") || t.contains("sleeping") || t.contains("frozen") || t.contains("saved memory") {
            return true
        }
        if u.contains("discarded") || u.contains("sleeping") || u.contains("about:discarded") ||
           u.contains("edge://discards") || u.contains("chrome://discards") {
            return true
        }
        return false
    }

    private func getMockTabs(for bundleID: String) -> [BrowserTabItem]? {
        lock.lock()
        defer { lock.unlock() }
        return mockTabs[bundleID]
    }

    public func fetchTabs(bundleID: String) async -> [BrowserTabItem] {
        if let mock = getMockTabs(for: bundleID) {
            return mock.filter { !$0.isFrozen }
        }

        guard Self.isSupportedBrowser(bundleID: bundleID) else { return [] }

        // 1-second timeout wrapper to prevent UI stalls
        do {
            return try await withThrowingTaskGroup(of: [BrowserTabItem].self) { group in
                group.addTask {
                    return try await self.executeAppleScriptFetch(bundleID: bundleID)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    throw CancellationError()
                }
                let first = try await group.next() ?? []
                group.cancelAll()
                return first
            }
        } catch {
            return []
        }
    }

    private func executeAppleScriptFetch(bundleID: String) async throws -> [BrowserTabItem] {
        let scriptSource: String
        if bundleID == "com.apple.Safari" {
            scriptSource = """
            tell application id "com.apple.Safari"
                set tabList to {}
                repeat with w in windows
                    set curIdx to index of current tab of w
                    repeat with t in tabs of w
                        set tName to name of t
                        set tURL to URL of t
                        set isAct to (index of t = curIdx)
                        copy (tName & "\\t" & tURL & "\\t" & isAct) to end of tabList
                    end repeat
                end repeat
                return tabList
            end tell
            """
        } else if bundleID == "com.google.Chrome" {
            scriptSource = """
            tell application id "com.google.Chrome"
                set tabList to {}
                repeat with w in windows
                    set actIndex to active tab index of w
                    set idx to 1
                    repeat with t in tabs of w
                        set tTitle to title of t
                        set tURL to URL of t
                        set isAct to (idx = actIndex)
                        copy (tTitle & "\\t" & tURL & "\\t" & isAct) to end of tabList
                        set idx to idx + 1
                    end repeat
                end repeat
                return tabList
            end tell
            """
        } else {
            // Edge (com.microsoft.edgems or com.microsoft.Edge)
            scriptSource = """
            tell application id "\(bundleID)"
                set tabList to {}
                repeat with w in windows
                    set actIndex to active tab index of w
                    set idx to 1
                    repeat with t in tabs of w
                        set tTitle to title of t
                        set tURL to URL of t
                        set isAct to (idx = actIndex)
                        copy (tTitle & "\\t" & tURL & "\\t" & isAct) to end of tabList
                        set idx to idx + 1
                    end repeat
                end repeat
                return tabList
            end tell
            """
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorDict: NSDictionary?
                guard let script = NSAppleScript(source: scriptSource) else {
                    continuation.resume(returning: [])
                    return
                }
                let descriptor = script.executeAndReturnError(&errorDict)
                if let errorDict = errorDict {
                    if let code = errorDict[NSAppleScript.errorNumber] as? Int, code == -1743 {
                        self.needsAutomationPermission = true
                    }
                    continuation.resume(returning: [])
                    return
                }
                self.needsAutomationPermission = false

                var items: [BrowserTabItem] = []
                let count = descriptor.numberOfItems
                if count > 0 {
                    for i in 1...count {
                        if let str = descriptor.atIndex(i)?.stringValue {
                            let parts = str.components(separatedBy: "\t")
                            let title = parts.first ?? ""
                            let url = parts.count > 1 ? parts[1] : ""
                            let isAct = parts.count > 2 ? (parts[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true") : true
                            let frozen = Self.isTabFrozen(title: title, url: url)
                            if !frozen {
                                items.append(BrowserTabItem(title: title, url: url, isFrozen: false, isActive: isAct))
                            }
                        }
                    }
                }
                continuation.resume(returning: items)
            }
        }
    }

    /// Selects a specific browser tab and brings that window to front.
    public func selectTab(tab: BrowserTabItem, in bundleID: String) {
        let scriptSource: String
        let safeTitle = tab.title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeURL = tab.url.replacingOccurrences(of: "\"", with: "\\\"")
        if bundleID == "com.apple.Safari" {
            scriptSource = """
            tell application id "com.apple.Safari"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t is "\(safeURL)" or name of t is "\(safeTitle)" then
                            set current tab of w to t
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        } else {
            scriptSource = """
            tell application id "\(bundleID)"
                activate
                repeat with w in windows
                    set idx to 1
                    repeat with t in tabs of w
                        if URL of t is "\(safeURL)" or title of t is "\(safeTitle)" then
                            set active tab index of w to idx
                            set index of w to 1
                            return
                        end if
                        set idx to idx + 1
                    end repeat
                end repeat
            end tell
            """
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&error)
            }
        }
    }
}

// MARK: - Calendar

public struct CalendarEventItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool

    public init(id: String = UUID().uuidString, title: String, startDate: Date, endDate: Date, isAllDay: Bool = false) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }

    public var timeString: String {
        if isAllDay { return L10n.t("Cả ngày") }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }
}

public final class CalendarPreviewProvider: @unchecked Sendable {
    public static let shared = CalendarPreviewProvider()

    private let eventStore = EKEventStore()
    private var mockEvents: [CalendarEventItem]?
    private let lock = NSLock()

    public init() {}

    public func setMockEvents(_ events: [CalendarEventItem]) {
        lock.lock()
        defer { lock.unlock() }
        mockEvents = events
    }

    private func getMockEvents() -> [CalendarEventItem]? {
        lock.lock()
        defer { lock.unlock() }
        return mockEvents
    }

    public func fetchNextEvents(limit: Int = 3) async -> [CalendarEventItem] {
        if let mock = getMockEvents() {
            return Array(mock.prefix(limit))
        }

        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            if status != .fullAccess && status != .authorized {
                return fallbackEvents()
            }
        } else {
            if status != .authorized {
                return fallbackEvents()
            }
        }

        let now = Date()
        let oneWeek = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let predicate = eventStore.predicateForEvents(withStart: now, end: oneWeek, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        let result = events.prefix(limit).map {
            CalendarEventItem(
                id: $0.eventIdentifier ?? UUID().uuidString,
                title: $0.title ?? L10n.t("Sự kiện"),
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay
            )
        }
        return result.isEmpty ? fallbackEvents() : result
    }

    private func fallbackEvents() -> [CalendarEventItem] {
        let now = Date()
        return [
            CalendarEventItem(title: L10n.t("Họp nhóm Sprint"), startDate: now, endDate: now.addingTimeInterval(3600), isAllDay: false),
            CalendarEventItem(title: L10n.t("Ăn trưa với Team"), startDate: now.addingTimeInterval(7200), endDate: now.addingTimeInterval(10800), isAllDay: false),
            CalendarEventItem(title: L10n.t("Demo tính năng mới"), startDate: now.addingTimeInterval(14400), endDate: now.addingTimeInterval(18000), isAllDay: false)
        ]
    }
}

// MARK: - Weather

public struct WeatherInfo: Equatable, Sendable {
    public let temperature: String
    public let condition: String
    public let symbolName: String

    public init(temperature: String, condition: String, symbolName: String) {
        self.temperature = temperature
        self.condition = condition
        self.symbolName = symbolName
    }
}

public final class WeatherPreviewProvider: @unchecked Sendable {
    public static let shared = WeatherPreviewProvider()

    private var mockWeather: WeatherInfo?
    private let lock = NSLock()

    public init() {}

    public func setMockWeather(_ weather: WeatherInfo) {
        lock.lock()
        defer { lock.unlock() }
        mockWeather = weather
    }

    private func getMockWeather() -> WeatherInfo? {
        lock.lock()
        defer { lock.unlock() }
        return mockWeather
    }

    public func fetchWeather() async -> WeatherInfo {
        if let mock = getMockWeather() {
            return mock
        }

        // Fallback default weather for preview
        return WeatherInfo(temperature: "28°C", condition: L10n.t("Có nắng"), symbolName: "sun.max.fill")
    }
}
