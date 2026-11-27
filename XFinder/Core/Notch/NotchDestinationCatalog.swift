import Foundation

/// XF-ISLAND-C — Stable identifiers for every Dynamic Island destination (legacy pages + inline extra modules).
/// Pure Foundation so `Tests/XFinderLogicTests` verifies migration, ordering, visibility, availability gating,
/// and fallback rules without AppKit.
enum NotchDestinationID: String, CaseIterable, Equatable, Hashable, Codable, Sendable, Identifiable {
    case files
    case clipboard
    case nowPlaying
    case agents
    case calendar
    case reminders
    case timer
    case aiUsage
    case system
    case audio
    case home
    case weather
    case stocks
    case revenue
    case websiteAnalytics
    case mirror
    case teleprompter
    case notes
    case capture
    case units
    case scratchpad
    case emoji
    case fileBrowser
    case links
    case imageConvert
    case sounds
    case todos
    case shortcuts
    case appUsage
    case localChat
    case message
    case feedback

    var id: String { rawValue }

    var destination: NotchGalleryDestination {
        switch self {
        case .files: return .page(.files)
        case .clipboard: return .page(.clipboard)
        case .nowPlaying: return .page(.nowPlaying)
        case .agents: return .page(.agents)
        case .calendar: return .page(.calendar)
        case .reminders: return .extra(.reminders)
        case .timer: return .page(.timer)
        case .aiUsage: return .page(.aiUsage)
        case .system: return .extra(.system)
        case .audio: return .extra(.audio)
        case .home: return .extra(.home)
        case .weather: return .extra(.weather)
        case .stocks: return .extra(.stocks)
        case .revenue: return .extra(.revenue)
        case .websiteAnalytics: return .extra(.websiteAnalytics)
        case .mirror: return .extra(.mirror)
        case .teleprompter: return .extra(.teleprompter)
        case .notes: return .extra(.notes)
        case .capture: return .extra(.capture)
        case .units: return .extra(.units)
        case .scratchpad: return .extra(.scratchpad)
        case .emoji: return .extra(.emoji)
        case .fileBrowser: return .extra(.fileBrowser)
        case .links: return .extra(.links)
        case .imageConvert: return .extra(.imageConvert)
        case .sounds: return .extra(.sounds)
        case .todos: return .extra(.todos)
        case .shortcuts: return .extra(.shortcuts)
        case .appUsage: return .extra(.appUsage)
        case .localChat: return .extra(.localChat)
        case .message: return .extra(.message)
        case .feedback: return .extra(.feedback)
        }
    }

    var legacyPage: NotchSurfaceMachine.Page? {
        switch self {
        case .files: return .files
        case .clipboard: return .clipboard
        case .nowPlaying: return .nowPlaying
        case .agents: return .agents
        case .calendar: return .calendar
        case .timer: return .timer
        case .aiUsage: return .aiUsage
        case .system, .audio, .home, .reminders, .weather, .stocks, .revenue, .websiteAnalytics, .mirror, .teleprompter, .notes, .capture, .units, .scratchpad, .emoji, .fileBrowser, .links, .imageConvert, .sounds, .todos, .shortcuts, .appUsage, .localChat, .message, .feedback: return nil
        }
    }

    var extraModule: NotchExtraModule? {
        switch self {
        case .system: return .system
        case .audio: return .audio
        case .home: return .home
        case .reminders: return .reminders
        case .weather: return .weather
        case .stocks: return .stocks
        case .revenue: return .revenue
        case .websiteAnalytics: return .websiteAnalytics
        case .mirror: return .mirror
        case .teleprompter: return .teleprompter
        case .notes: return .notes
        case .capture: return .capture
        case .units: return .units
        case .scratchpad: return .scratchpad
        case .emoji: return .emoji
        case .fileBrowser: return .fileBrowser
        case .links: return .links
        case .imageConvert: return .imageConvert
        case .sounds: return .sounds
        case .todos: return .todos
        case .shortcuts: return .shortcuts
        case .appUsage: return .appUsage
        case .localChat: return .localChat
        case .message: return .message
        case .feedback: return .feedback
        case .files, .clipboard, .nowPlaying, .agents, .calendar, .timer, .aiUsage: return nil
        }
    }

    var isLegacyPage: Bool { legacyPage != nil }

    /// Modules that require an explicit provider / connector before they can operate in the Island.
    var requiresProviderConfiguration: Bool {
        switch self {
        case .weather, .stocks, .revenue: return true
        default: return false
        }
    }

    /// Default user preference when no explicit catalog state exists yet.
    /// Provider-backed modules still remain hidden from the Island until configured (`NotchDestinationAvailability`).
    var isDefaultEnabled: Bool { true }

    /// Settings remains reachable for provider-backed pages in every readiness state.
    /// Other destinations expose a Settings route only when their owning feature is disabled.
    func settingsTarget(for readiness: NotchDestinationReadiness) -> String? {
        switch self {
        case .stocks: return "stocks"
        case .revenue: return "revenue"
        case .websiteAnalytics: return "websiteAnalytics"
        default:
            if case .featureDisabled(let target) = readiness { return target }
            return nil
        }
    }

    var titleKey: String {
        if let p = legacyPage { return NotchPages.titleKey(p) }
        if let e = extraModule { return NotchGalleryRules.titleKey(for: e) }
        return rawValue
    }

    var symbol: String {
        if let p = legacyPage { return NotchPages.symbol(p) }
        if let e = extraModule { return NotchGalleryRules.symbol(for: e) }
        return "square.grid.2x2"
    }

    var shortcutKey: String {
        switch self {
        case .files: return "F"
        case .clipboard: return "B"
        case .nowPlaying: return "M"
        case .agents: return "A"
        case .calendar: return "C"
        case .reminders: return "N"
        case .timer: return "T"
        case .aiUsage: return "U"
        case .system: return "S"
        case .audio: return "V"
        case .home: return "H"
        case .weather: return "W"
        case .stocks: return "K"
        case .revenue: return "R"
        case .mirror: return "I"
        case .teleprompter: return "P"
        case .notes: return "O"
        case .capture: return "D"
        case .units: return "J"
        case .scratchpad: return "X"
        case .emoji: return "E"
        case .fileBrowser: return "Y"
        case .links: return "L"
        case .imageConvert: return "Z"
        case .sounds: return "Q"
        case .todos: return "G"
        case .shortcuts, .appUsage, .localChat, .message, .feedback, .websiteAnalytics: return ""
        }
    }

    var digitKey: String {
        switch self {
        case .files: return "1"
        case .clipboard: return "2"
        case .nowPlaying: return "3"
        case .agents: return "4"
        case .calendar: return "5"
        case .reminders: return "["
        case .timer: return "6"
        case .aiUsage: return "7"
        case .system: return "8"
        case .audio: return "9"
        case .home: return ""
        case .weather: return "0"
        case .stocks: return "-"
        case .revenue: return "="
        case .mirror, .teleprompter, .notes, .capture, .units, .scratchpad, .emoji, .fileBrowser, .links, .imageConvert, .sounds, .todos, .shortcuts, .appUsage, .localChat, .message, .feedback, .websiteAnalytics: return ""
        }
    }

    var galleryItem: NotchGalleryItem {
        NotchGalleryItem(
            id: rawValue,
            destination: destination,
            titleKey: titleKey,
            symbol: symbol,
            shortcutKey: shortcutKey,
            digitKey: digitKey
        )
    }

    init?(destination: NotchGalleryDestination) {
        switch destination {
        case .page(let p):
            self.init(page: p)
        case .extra(let e):
            self.init(extra: e)
        }
    }

    init(page: NotchSurfaceMachine.Page) {
        switch page {
        case .files: self = .files
        case .clipboard: self = .clipboard
        case .nowPlaying: self = .nowPlaying
        case .agents: self = .agents
        case .calendar: self = .calendar
        case .timer: self = .timer
        case .aiUsage: self = .aiUsage
        }
    }

    init?(extra: NotchExtraModule) {
        switch extra {
        case .sections, .settings: return nil
        case .home: self = .home
        case .system: self = .system
        case .audio: self = .audio
        case .reminders: self = .reminders
        case .weather: self = .weather
        case .stocks: self = .stocks
        case .revenue: self = .revenue
        case .websiteAnalytics: self = .websiteAnalytics
        case .mirror: self = .mirror
        case .teleprompter: self = .teleprompter
        case .notes: self = .notes
        case .capture: self = .capture
        case .units: self = .units
        case .scratchpad: self = .scratchpad
        case .emoji: self = .emoji
        case .fileBrowser: self = .fileBrowser
        case .links: self = .links
        case .imageConvert: self = .imageConvert
        case .sounds: self = .sounds
        case .todos: self = .todos
        case .shortcuts: self = .shortcuts
        case .appUsage: self = .appUsage
        case .localChat: self = .localChat
        case .message: self = .message
        case .feedback: self = .feedback
        }
    }
}

/// Separates runtime readiness from the user's on/off toggle so unconfigured modules are never shown as working
/// while preserving the user's visibility preference when the source becomes ready later.
enum NotchDestinationReadiness: Equatable, Sendable {
    case ready
    /// Owning feature switch is off (e.g. Media, Agent AI, Calendar). `settingsTarget` matches `SidebarDestination.rawValue`.
    case featureDisabled(settingsTarget: String)
    /// Provider / connector has not been configured for this build or account (Weather, Stocks, Revenue).
    case unconfigured
}

struct NotchDestinationAvailability: Equatable, Sendable {
    var nowPlayingReady: Bool = true
    var agentsReady: Bool = true
    var calendarReady: Bool = true
    var weatherConfigured: Bool = false
    var stocksConfigured: Bool = false
    var revenueConfigured: Bool = false

    func readiness(for id: NotchDestinationID) -> NotchDestinationReadiness {
        switch id {
        case .files, .clipboard, .timer, .system, .audio, .home, .reminders, .mirror, .teleprompter, .notes, .capture, .units, .scratchpad, .emoji, .fileBrowser, .links, .imageConvert, .sounds, .todos, .shortcuts, .appUsage, .localChat, .message, .feedback, .websiteAnalytics:
            return .ready
        case .nowPlaying:
            return nowPlayingReady ? .ready : .featureDisabled(settingsTarget: "media")
        case .agents, .aiUsage:
            return agentsReady ? .ready : .featureDisabled(settingsTarget: "aiAgents")
        case .calendar:
            return calendarReady ? .ready : .featureDisabled(settingsTarget: "calendar")
        case .weather:
            return weatherConfigured ? .ready : .unconfigured
        case .stocks:
            return stocksConfigured ? .ready : .unconfigured
        case .revenue:
            return revenueConfigured ? .ready : .unconfigured
        }
    }

    func isReady(_ id: NotchDestinationID) -> Bool {
        readiness(for: id) == .ready
    }

    func canOpen(_ id: NotchDestinationID) -> Bool {
        isReady(id) || id == .stocks
    }

    static let allReady = NotchDestinationAvailability(
        nowPlayingReady: true,
        agentsReady: true,
        calendarReady: true,
        weatherConfigured: true,
        stocksConfigured: true,
        revenueConfigured: true
    )

    static let builtInOnly = NotchDestinationAvailability(
        nowPlayingReady: true,
        agentsReady: true,
        calendarReady: true,
        weatherConfigured: false,
        stocksConfigured: false,
        revenueConfigured: false
    )
}

struct NotchTabEntry: Equatable, Hashable, Codable, Sendable, Identifiable {
    let id: NotchDestinationID
    var enabled: Bool
}

/// Ordered visibility state for every Dynamic Island destination.
/// Invariant: every `NotchDestinationID` appears exactly once; hidden tabs retain their exact persistent order.
struct NotchTabCatalogState: Equatable, Sendable {
    var entries: [NotchTabEntry]

    var isAllHidden: Bool {
        entries.allSatisfy { !$0.enabled }
    }

    var enabledIDs: [NotchDestinationID] {
        entries.filter(\.enabled).map(\.id)
    }

    var enabledLegacyPages: [NotchSurfaceMachine.Page] {
        entries.compactMap { $0.enabled ? $0.id.legacyPage : nil }
    }

    func isEnabled(_ id: NotchDestinationID) -> Bool {
        entries.first(where: { $0.id == id })?.enabled ?? false
    }

    /// Destinations that are BOTH enabled by the user AND ready/configured at runtime.
    func visibleDestinations(availability: NotchDestinationAvailability) -> [NotchDestinationID] {
        entries.compactMap { entry in
            (entry.enabled && availability.canOpen(entry.id)) ? entry.id : nil
        }
    }

    func visibleLegacyPages(availability: NotchDestinationAvailability) -> [NotchSurfaceMachine.Page] {
        visibleDestinations(availability: availability).compactMap(\.legacyPage)
    }

    func visibleExtraModules(availability: NotchDestinationAvailability) -> [NotchExtraModule] {
        visibleDestinations(availability: availability).compactMap(\.extraModule)
    }

    func isOpenable(_ id: NotchDestinationID, availability: NotchDestinationAvailability) -> Bool {
        isEnabled(id) && availability.canOpen(id)
    }

    /// Toggle visibility in place without losing the tab's persistent order. Allows hiding the last tab (all-hidden).
    func toggled(_ id: NotchDestinationID) -> NotchTabCatalogState {
        var copy = entries
        guard let idx = copy.firstIndex(where: { $0.id == id }) else { return self }
        copy[idx].enabled.toggle()
        return NotchTabCatalogState(entries: copy)
    }

    /// Explicitly set a destination's enabled state without changing its persistent order.
    func setting(_ id: NotchDestinationID, enabled: Bool) -> NotchTabCatalogState {
        var copy = entries
        guard let idx = copy.firstIndex(where: { $0.id == id }) else { return self }
        copy[idx].enabled = enabled
        return NotchTabCatalogState(entries: copy)
    }

    /// Move any destination (enabled or hidden) one step; ends stay put.
    func moved(_ id: NotchDestinationID, by delta: Int) -> NotchTabCatalogState {
        var copy = entries
        guard let i = copy.firstIndex(where: { $0.id == id }) else { return self }
        let j = i + delta
        guard j >= 0, j < copy.count else { return self }
        copy.swapAt(i, j)
        return NotchTabCatalogState(entries: copy)
    }

    /// Reorder entries for drag-and-drop (IndexSet semantics matching SwiftUI `onMove`).
    func moved(fromOffsets source: IndexSet, toOffset destination: Int) -> NotchTabCatalogState {
        var copy = entries
        let moving = source.sorted().compactMap { $0 < copy.count ? copy[$0] : nil }
        for index in source.sorted(by: >) where index < copy.count {
            copy.remove(at: index)
        }
        let removedBefore = source.filter { $0 < destination }.count
        let target = max(0, min(copy.count, destination - removedBefore))
        copy.insert(contentsOf: moving, at: target)
        return NotchTabCatalogState(entries: copy)
    }

    /// Reorder within the enabled or disabled list while leaving the other group's slots alone.
    func movedWithinVisibilityGroup(_ source: NotchDestinationID, to target: NotchDestinationID) -> NotchTabCatalogState {
        guard source != target, let sourceEntry = entries.first(where: { $0.id == source }) else { return self }
        let slots = entries.indices.filter { entries[$0].enabled == sourceEntry.enabled }
        var group = slots.map { entries[$0] }
        guard let from = group.firstIndex(where: { $0.id == source }),
              let to = group.firstIndex(where: { $0.id == target }) else { return self }
        group.remove(at: from)
        group.insert(sourceEntry, at: to)
        var reordered = entries
        for (index, entry) in zip(slots, group) { reordered[index] = entry }
        return NotchTabCatalogState(entries: reordered)
    }

    /// Nearest enabled & ready destination when `current` is hidden or becomes unavailable; `nil` when none are openable.
    func fallbackDestination(
        from current: NotchDestinationID,
        availability: NotchDestinationAvailability
    ) -> NotchDestinationID? {
        if isOpenable(current, availability: availability) {
            return current
        }
        guard let currentIndex = entries.firstIndex(where: { $0.id == current }) else {
            return visibleDestinations(availability: availability).first
        }
        // Search outward by distance (preferring the next item on tie, matching tab-close intuition).
        let count = entries.count
        for distance in 1..<count {
            let nextIdx = currentIndex + distance
            if nextIdx < count {
                let candidate = entries[nextIdx]
                if candidate.enabled && availability.canOpen(candidate.id) {
                    return candidate.id
                }
            }
            let prevIdx = currentIndex - distance
            if prevIdx >= 0 {
                let candidate = entries[prevIdx]
                if candidate.enabled && availability.canOpen(candidate.id) {
                    return candidate.id
                }
            }
        }
        return nil
    }
}

/// Unified Dynamic Island tab catalog: single source of truth for storage, legacy migration,
/// persistent ordering of hidden tabs, intentional all-hidden handling, and deep-link resolution.
enum NotchDestinationCatalog {
    static let storageKey = "notch.tabCatalog.v1"
    static let defaultRaw = ""
    static let formatPrefix = "v1:"
    static let allHiddenSentinel = "v1:none"

    static let canonicalOrder: [NotchDestinationID] = NotchDestinationID.allCases.filter { $0 != .fileBrowser }

    static let defaultState = NotchTabCatalogState(
        entries: canonicalOrder.map { NotchTabEntry(id: $0, enabled: $0.isDefaultEnabled) }
    )

    static let allHiddenState = NotchTabCatalogState(
        entries: canonicalOrder.map { NotchTabEntry(id: $0, enabled: false) }
    )

    /// Canonical serialization (`v1:id:1,id:0,...`). Explicitly encodes all-hidden (`:0` for every entry),
    /// keeping it unambiguously distinct from a missing/unset config (`nil` or `""`).
    static func serialize(_ state: NotchTabCatalogState) -> String {
        let normalized = normalize(state.entries)
        let body = normalized.map { "\($0.id.rawValue):\($0.enabled ? 1 : 0)" }.joined(separator: ",")
        return "\(formatPrefix)\(body)"
    }

    /// Parses the unified catalog string if present; otherwise migrates cleanly from legacy `notch.pages`.
    /// - Missing legacy config (`catalogRaw == nil/""` and `legacyPagesRaw == nil`) ⇒ `defaultState`.
    /// - Intentional all-hidden (`catalogRaw == "v1:none"` or all entries `:0`) ⇒ `allHiddenState` (preserving order).
    /// - Unknown tokens are dropped; duplicate tokens collapse to their first occurrence.
    static func parse(catalogRaw: String?, legacyPagesRaw: String?) -> NotchTabCatalogState {
        if let raw = catalogRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if raw == allHiddenSentinel {
                return allHiddenState
            }
            let hasPrefix = raw.hasPrefix(formatPrefix)
            let body = hasPrefix ? String(raw.dropFirst(formatPrefix.count)) : raw
            var parsed: [NotchTabEntry] = []
            var seen = Set<NotchDestinationID>()

            for token in body.split(separator: ",") {
                let piece = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !piece.isEmpty else { continue }
                let parts = piece.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard let id = NotchDestinationID(rawValue: parts[0]), seen.insert(id).inserted else {
                    continue
                }
                let enabled: Bool
                if parts.count == 2 {
                    if parts[1] == "0" || parts[1].lowercased() == "false" {
                        enabled = false
                    } else if parts[1] == "1" || parts[1].lowercased() == "true" {
                        enabled = true
                    } else {
                        enabled = id.isDefaultEnabled
                    }
                } else {
                    enabled = true
                }
                parsed.append(NotchTabEntry(id: id, enabled: enabled))
            }

            if !parsed.isEmpty {
                return NotchTabCatalogState(entries: normalize(parsed))
            }
            if hasPrefix && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return allHiddenState
            }
        }

        return migrateFromLegacy(legacyPagesRaw)
    }

    /// Migrates a legacy `notch.pages` comma string into the unified catalog.
    /// `nil` (missing legacy key) returns `defaultState`. A non-empty legacy list preserves exact user order,
    /// marks omitted legacy pages as hidden, and appends extra modules with their defaults.
    static func migrateFromLegacy(_ legacyPagesRaw: String?) -> NotchTabCatalogState {
        guard let raw = legacyPagesRaw else {
            return defaultState
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Legacy `notch.pages` never permitted all-hidden; empty legacy value recovers to default.
            return defaultState
        }

        var enabledLegacy: [NotchSurfaceMachine.Page] = []
        for token in trimmed.split(separator: ",") {
            let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if let page = NotchSurfaceMachine.Page(rawValue: t), !enabledLegacy.contains(page) {
                enabledLegacy.append(page)
            }
        }
        guard !enabledLegacy.isEmpty else {
            return defaultState
        }

        var entries: [NotchTabEntry] = enabledLegacy.map {
            NotchTabEntry(id: NotchDestinationID(page: $0), enabled: true)
        }
        for page in NotchPages.defaultOrder where !enabledLegacy.contains(page) {
            entries.append(NotchTabEntry(id: NotchDestinationID(page: page), enabled: false))
        }
        for extraID in canonicalOrder where !extraID.isLegacyPage {
            entries.append(NotchTabEntry(id: extraID, enabled: extraID.isDefaultEnabled))
        }
        return NotchTabCatalogState(entries: normalize(entries))
    }

    /// Resolves `xfinder://notch?page=<id>` against the unified catalog and live availability.
    /// Returns `nil` when all destinations are hidden or unavailable (caller shows Settings recovery).
    static func resolveDeepLink(
        pageParam: String?,
        catalog: NotchTabCatalogState,
        availability: NotchDestinationAvailability
    ) -> NotchDestinationID? {
        let requested: NotchDestinationID
        if let param = pageParam?.trimmingCharacters(in: .whitespacesAndNewlines),
           let parsed = NotchDestinationID(rawValue: param) {
            requested = parsed
        } else {
            requested = .files
        }
        return catalog.fallbackDestination(from: requested, availability: availability)
    }

    /// Ensures every canonical `NotchDestinationID` appears once (deduplicating and appending any newly introduced IDs).
    private static func normalize(_ input: [NotchTabEntry]) -> [NotchTabEntry] {
        var result: [NotchTabEntry] = []
        var seen = Set<NotchDestinationID>()
        for entry in input where entry.id != .fileBrowser && seen.insert(entry.id).inserted {
            result.append(entry)
        }
        for id in canonicalOrder where seen.insert(id).inserted {
            result.append(NotchTabEntry(id: id, enabled: id.isDefaultEnabled))
        }
        return result
    }
}
