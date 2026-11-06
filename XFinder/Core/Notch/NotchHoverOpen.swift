import Foundation

/// N2 (2026-10-13) — what resting the pointer on the notch opens. Measured on OneNotch 2.0.5: one setting,
/// `notchOpenBehavior`, with "every hover opens the same page" versus "activity" ("Music playing opens Media,
/// a running agent opens AI agents"). XFinder had one Bool for one case (`notch.clipboardOnHover`, D1); this
/// replaces it with ONE key, `notch.hoverOpens`, read by `NotchSurfaceController` and decided here.
///
/// `peek` keeps the B1 rule: hover reveals files already held or the playing track, never an empty tray.
/// Every other value opens the hub on a page — clips, agents and the player are never "empty", so this does
/// not repeat the Part 3c empty-tray trap; `files` falls back to the peek when nothing is held.
enum NotchHoverOpen: String, CaseIterable, Equatable {
    /// Hover only peeks (files / track); clicking opens the hub. The default.
    case peek
    /// The page the current activity calls for: a session waiting for you → agents, a playing track →
    /// Now Playing, files held → the tray, otherwise the clipboard.
    case activity
    case clipboard
    case files
    case nowPlaying
    case agents
    /// The page the hub was on last time.
    case lastPage

    static let key = "notch.hoverOpens"
    static let defaultRaw = "peek"

    /// Legacy D1 key: `true` meant "hover opens the clipboard". Read once by `migrated(raw:legacyClipboard:)`.
    static let legacyKey = "notch.clipboardOnHover"

    static func parse(_ raw: String?) -> NotchHoverOpen {
        raw.flatMap(NotchHoverOpen.init(rawValue:)) ?? .peek
    }

    /// The stored value, honouring a user who had turned the D1 switch on before this key existed. That switch
    /// meant "clipboard when there is nothing else to show" (files and a track still peeked), which is closest
    /// to `.activity` — not to a fixed `.clipboard`, which would now open the clipboard over held files too.
    static func migrated(raw: String?, legacyClipboard: Bool) -> NotchHoverOpen {
        if let raw, let v = NotchHoverOpen(rawValue: raw) { return v }
        return legacyClipboard ? .activity : .peek
    }

    /// What is going on right now, as the machine knows it.
    struct Activity: Equatable {
        var itemCount = 0
        var trackPlaying = false
        var agentNeedsYou = false
        var lastPage: NotchSurfaceMachine.Page? = nil
    }

    /// The page a hover opens, or nil for "peek instead". `shown` is the user's page order (hidden pages are
    /// never opened by a hover; the request falls back as `NotchPages.resolve` does, except that a hidden
    /// target under `.activity` moves on to the next activity, and `.files` with nothing held peeks).
    func page(for a: Activity, shown: [NotchSurfaceMachine.Page]) -> NotchSurfaceMachine.Page? {
        func visible(_ p: NotchSurfaceMachine.Page) -> NotchSurfaceMachine.Page? { shown.contains(p) ? p : nil }
        switch self {
        case .peek: return nil
        case .clipboard: return visible(.clipboard) ?? shown.first
        case .nowPlaying: return visible(.nowPlaying) ?? shown.first
        case .agents: return visible(.agents) ?? shown.first
        case .files: return a.itemCount > 0 ? (visible(.files) ?? shown.first) : nil
        case .lastPage: return a.lastPage.flatMap(visible) ?? shown.first
        case .activity:
            if a.agentNeedsYou, let p = visible(.agents) { return p }
            if a.trackPlaying, let p = visible(.nowPlaying) { return p }
            if a.itemCount > 0, let p = visible(.files) { return p }
            return visible(.clipboard) ?? shown.first
        }
    }

    /// Store keys for the picker (the view wraps them in `L10n.t`).
    var labelKey: String {
        switch self {
        case .peek: return "Chỉ xem nhanh"
        case .activity: return "Theo hoạt động"
        case .clipboard: return "Clipboard"
        case .files: return "Khay"
        case .nowPlaying: return "Đang phát"
        case .agents: return "Agent AI"
        case .lastPage: return "Trang mở lần cuối"
        }
    }
}

/// Where an intentional click/shortcut open should land. Kept separate from hover behavior so a
/// brief pointer pause can remain a peek while an explicit open still lands on a useful page.
enum NotchClickOpen: String, CaseIterable, Equatable {
    case files, clipboard, nowPlaying, agents, calendar, timer, aiUsage
    case lastPage
    case activity

    static let defaultRaw = "files"

    static func parse(_ raw: String?) -> NotchClickOpen {
        raw.flatMap(NotchClickOpen.init(rawValue:)) ?? .files
    }

    static func resolve(explicitPage: NotchSurfaceMachine.Page?, rule: NotchClickOpen,
                        activity: NotchHoverOpen.Activity, shown: [NotchSurfaceMachine.Page]) -> NotchSurfaceMachine.Page {
        if let explicitPage { return NotchPages.resolve(explicitPage, shown: shown) }
        return rule.page(for: activity, shown: shown)
    }

    func page(for activity: NotchHoverOpen.Activity, shown: [NotchSurfaceMachine.Page]) -> NotchSurfaceMachine.Page {
        func visible(_ page: NotchSurfaceMachine.Page) -> NotchSurfaceMachine.Page? {
            shown.contains(page) ? page : nil
        }
        switch self {
        case .files, .clipboard, .nowPlaying, .agents, .calendar, .timer, .aiUsage:
            let target = NotchSurfaceMachine.Page(rawValue: rawValue) ?? .files
            return visible(target) ?? shown.first ?? NotchPages.defaultOrder[0]
        case .lastPage:
            return activity.lastPage.flatMap(visible) ?? shown.first ?? NotchPages.defaultOrder[0]
        case .activity:
            if activity.agentNeedsYou, let page = visible(.agents) { return page }
            if activity.trackPlaying, let page = visible(.nowPlaying) { return page }
            if activity.itemCount > 0, let page = visible(.files) { return page }
            if let page = visible(.clipboard) { return page }
            return shown.first ?? NotchPages.defaultOrder[0]
        }
    }

    var labelKey: String {
        switch self {
        case .lastPage: return "Trang mở lần cuối"
        case .activity: return "Theo hoạt động"
        default:
            return NotchSurfaceMachine.Page(rawValue: rawValue).map(NotchPages.titleKey) ?? NotchPages.titleKey(.files)
        }
    }
}
