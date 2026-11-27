import Foundation

/// Pure Dynamic Island Phase-1 rules: single collapsed signal selection, expanded navigation
/// partitioning (pinned named tabs + "Thêm" overflow), open-page priority during active file work,
/// keyboard command decoding, and Reduce Motion policy. Foundation-only so `Tests/XFinderLogicTests`
/// verifies every rule without AppKit.
enum NotchCollapsedSignal: Equatable, Sendable {
    case agentNeedsYou
    case timerRunning
    case files(Int)
    case timerPaused
    case agentBusy
    case nowPlaying
    case agentIdle
    case none

    /// Projection onto `NotchSurfaceLayout` flags so the collapsed Island / external pill renders
    /// at most ONE useful signal at a time instead of stacking every background subsystem together.
    struct WingProjection: Equatable, Sendable {
        var itemCount: Int = 0
        var timerActive: Bool = false
        var nowPlayingActive: Bool = false
        var agentActive: Bool = false
        var agentBusy: Bool = false
        var agentCount: Int = 0

        var isVisible: Bool {
            itemCount > 0 || timerActive || nowPlayingActive || agentActive
        }
    }

    static func resolve(
        itemCount: Int,
        timerActive: Bool,
        timerPaused: Bool,
        nowPlayingActive: Bool,
        nowPlayingPlaying: Bool,
        agentActive: Bool,
        agentBusy: Bool,
        agentsNeedingYou: Int,
        visibleDestinations: Set<NotchDestinationID>? = nil
    ) -> NotchCollapsedSignal {
        let allow: (NotchDestinationID) -> Bool = { id in
            visibleDestinations?.contains(id) ?? true
        }
        let showAgents = agentActive && allow(.agents)
        let showTimer = timerActive && allow(.timer)
        let showFiles = itemCount > 0 && allow(.files)
        let showNowPlaying = nowPlayingActive && allow(.nowPlaying)

        if showAgents && agentsNeedingYou > 0 { return .agentNeedsYou }
        if showTimer && !timerPaused { return .timerRunning }
        if showFiles { return .files(itemCount) }
        if showTimer && timerPaused { return .timerPaused }
        if showAgents && agentBusy { return .agentBusy }
        if showNowPlaying && nowPlayingPlaying { return .nowPlaying }
        if showAgents { return .agentIdle }
        if showNowPlaying { return .nowPlaying }
        return .none
    }

    func projection(agentCount: Int) -> WingProjection {
        let clampedAgents = max(1, agentCount)
        switch self {
        case .agentNeedsYou, .agentBusy:
            return WingProjection(agentActive: true, agentBusy: true, agentCount: clampedAgents)
        case .timerRunning, .timerPaused:
            return WingProjection(timerActive: true)
        case .files(let n):
            return WingProjection(itemCount: max(0, n))
        case .nowPlaying:
            return WingProjection(nowPlayingActive: true)
        case .agentIdle:
            return WingProjection(agentActive: true, agentBusy: false, agentCount: clampedAgents)
        case .none:
            return WingProjection()
        }
    }

    var targetPage: NotchSurfaceMachine.Page? {
        switch self {
        case .agentNeedsYou, .agentBusy, .agentIdle: return .agents
        case .timerRunning, .timerPaused: return .timer
        case .files: return .files
        case .nowPlaying: return .nowPlaying
        case .none: return nil
        }
    }
}

/// Pure navigation partition for the expanded Island top band: named pinned buttons on the left
/// wing, and all remaining destinations inside the "Thêm" menu on the right wing.
enum NotchNavLayout {
    typealias Page = NotchSurfaceMachine.Page

    struct BandPlan: Equatable, Sendable {
        let pinned: [Page]
        let overflowPages: [Page]
        let overflowExtras: [NotchExtraModule]
    }

    /// Preferred pinned order: files first, then clipboard, then media/agents. Respects the user's
    /// visibility order in `shown` and never overflows narrow wings beside a physical notch.
    static func plan(
        shown: [Page],
        available: (Page) -> Bool,
        current: Page,
        isWide: Bool,
        hasPhysicalNotch: Bool,
        searchFieldVisible: Bool = false,
        weatherAvailable: Bool = false,
        stocksAvailable: Bool = false,
        revenueAvailable: Bool = false
    ) -> BandPlan {
        let visible = shown.filter(available)
        let pool = visible.isEmpty ? [NotchPages.defaultOrder[0]] : visible

        let maxPinned: Int
        if !isWide && hasPhysicalNotch {
            maxPinned = 1
        } else if searchFieldVisible && hasPhysicalNotch {
            maxPinned = 2
        } else {
            maxPinned = 3
        }

        // Keep `.files` pinned first whenever it is visible so staged files and operations stay one click away.
        var orderedCandidates: [Page] = []
        if pool.contains(.files) { orderedCandidates.append(.files) }
        for page in pool where !orderedCandidates.contains(page) {
            orderedCandidates.append(page)
        }

        var pinned = Array(orderedCandidates.prefix(maxPinned))
        // On a narrow physical-notch page (1 slot), show the currently open page so the user always sees where they are.
        if maxPinned == 1, pool.contains(current) {
            pinned = [current]
        }

        let pinnedSet = Set(pinned)
        let overflowPages = pool.filter { !pinnedSet.contains($0) }
        var overflowExtras: [NotchExtraModule] = []
        if weatherAvailable { overflowExtras.append(.weather) }
        if stocksAvailable { overflowExtras.append(.stocks) }
        if revenueAvailable { overflowExtras.append(.revenue) }
        overflowExtras.append(.system)
        overflowExtras.append(.audio)
        return BandPlan(pinned: pinned, overflowPages: overflowPages, overflowExtras: overflowExtras)
    }

    struct UnifiedBandPlan: Equatable, Sendable {
        let pinned: [NotchDestinationID]
        let overflowPages: [NotchDestinationID]
        let overflowExtras: [NotchDestinationID]

        var isEmpty: Bool {
            pinned.isEmpty && overflowPages.isEmpty && overflowExtras.isEmpty
        }
    }

    /// XF-ISLAND-C: Unified navigation partition over BOTH legacy pages and extra modules.
    /// Respects exact user order, never resurrects hidden tabs, never shows unconfigured modules as working,
    /// and returns an empty plan when all destinations are hidden so the shell shows Settings recovery.
    static func unifiedPlan(
        catalog: NotchTabCatalogState,
        availability: NotchDestinationAvailability,
        current: NotchDestinationID?,
        isWide: Bool,
        hasPhysicalNotch: Bool,
        searchFieldVisible: Bool = false
    ) -> UnifiedBandPlan {
        let pool = catalog.visibleDestinations(availability: availability)
        guard !pool.isEmpty else {
            return UnifiedBandPlan(pinned: [], overflowPages: [], overflowExtras: [])
        }

        let maxPinned: Int
        if !isWide && hasPhysicalNotch {
            maxPinned = 1
        } else if searchFieldVisible && hasPhysicalNotch {
            maxPinned = 2
        } else {
            maxPinned = 3
        }

        var pinned = Array(pool.prefix(maxPinned))
        if maxPinned == 1, let current, pool.contains(current) {
            pinned = [current]
        }

        let pinnedSet = Set(pinned)
        let overflow = pool.filter { !pinnedSet.contains($0) }
        return UnifiedBandPlan(
            pinned: pinned,
            overflowPages: overflow.filter(\.isLegacyPage),
            overflowExtras: overflow.filter { !$0.isLegacyPage }
        )
    }

    /// Whether the expanded body should use the wide 612-pt canvas so files, thumbnails, names,
    /// status badges, and batch actions fit cleanly without cramping.
    static func usesWideCanvas(page: Page, extraModule: NotchExtraModule?, preferNarrowExtra: Bool = false) -> Bool {
        if extraModule != nil { return !preferNarrowExtra }
        return page == .files || NotchSurfaceLayout.Metrics.isWide(page)
    }
}

/// Pure open-page prioritization when expanding the Island.
enum NotchExpandPriority {
    /// Deliberate open: explicit page wins; otherwise an active file operation prioritizes `.files`
    /// when visible; otherwise falls back to `NotchClickOpen`.
    static func resolveOpenPage(
        explicitPage: NotchSurfaceMachine.Page?,
        clickRule: NotchClickOpen,
        activity: NotchHoverOpen.Activity,
        shown: [NotchSurfaceMachine.Page],
        hasActiveFileOperation: Bool
    ) -> NotchSurfaceMachine.Page {
        if let explicitPage {
            return NotchPages.resolve(explicitPage, shown: shown)
        }
        if hasActiveFileOperation, shown.contains(.files) {
            return .files
        }
        return NotchClickOpen.resolve(explicitPage: nil, rule: clickRule, activity: activity, shown: shown)
    }
}

/// Pure Reduce Motion policy shared by the Notch controller and view.
enum NotchMotionPolicy {
    static func shouldGrowFromNotch(wasVisible: Bool, anchor: NotchSurfaceMachine.Anchor, reduceMotion: Bool) -> Bool {
        !wasVisible && anchor == .notch && !reduceMotion
    }

    static func appearBlurRadius(appearFromNotch: Bool, reduceMotion: Bool) -> Double {
        (appearFromNotch && !reduceMotion) ? 8 : 0
    }

    static func pillHoverScale(hovered: Bool, reduceMotion: Bool) -> Double {
        (hovered && !reduceMotion) ? 1.03 : 1.0
    }
}

/// Pure keyboard shortcut decoder for the expanded Island hub (outside text fields & clipboard scopes).
enum NotchHubKeyAction: Equatable, Sendable {
    case escape
    case quickLook
    case selectAll
    case removeSelected
    case openSelected
    case moveSelection(delta: Int, extend: Bool)
    case switchToSlot(Int)     // 1-based visible page slot (⌘1…⌘9)
    case toggleMoreGallery     // ⌘G

    static func decode(
        keyCode: UInt16,
        characters: String?,
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool,
        onFilesPage: Bool
    ) -> NotchHubKeyAction? {
        guard !option, !control else { return nil }
        if keyCode == 53 && !command { return .escape }

        if command {
            let lower = characters?.lowercased() ?? ""
            if lower == "g" && !shift { return .toggleMoreGallery }
            if onFilesPage && lower == "a" && !shift { return .selectAll }
            if onFilesPage && keyCode == 51 { return .removeSelected }
            if !shift, let digit = Int(lower), (1...9).contains(digit) {
                return .switchToSlot(digit)
            }
            return nil
        }

        guard onFilesPage else { return nil }
        switch keyCode {
        case 49: return .quickLook                               // Space
        case 36, 76: return .openSelected                        // Return / Enter
        case 51, 117: return .removeSelected                     // Backspace / Forward delete
        case 123: return .moveSelection(delta: -1, extend: shift) // Left
        case 124: return .moveSelection(delta: 1, extend: shift)  // Right
        case 126: return .moveSelection(delta: -1, extend: shift) // Up
        case 125: return .moveSelection(delta: 1, extend: shift)  // Down
        default: return nil
        }
    }
}
