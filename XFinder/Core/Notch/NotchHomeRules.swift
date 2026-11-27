import Foundation

/// Pure Dynamic Island Home ("Tổng quan") snapshot rules.
///
/// Aggregates read-only snapshots from already-enabled modules (Now Playing, Calendar, and active work:
/// Clock suite, AI Agents, Drop Tray files) without starting monitors, requesting permissions, or performing
/// network / EventKit calls. Kept pure Foundation so `Tests/XFinderLogicTests` verifies gating, priority,
/// empty state, layout columns, and destination routing without AppKit.
enum NotchHomeRules {
    struct NowPlayingInput: Equatable, Sendable {
        var headline: String
        var subline: String
        var isPlaying: Bool
        var appName: String?

        var hasContent: Bool {
            !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    struct CalendarInput: Equatable, Sendable {
        var isAuthorized: Bool
        var title: String?
        var start: Date?
        var end: Date?
        var isAllDay: Bool
        var hasMeetingLink: Bool
        var todayCount: Int

        var hasContent: Bool {
            guard isAuthorized, let title else { return false }
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    struct ActiveWorkInput: Equatable, Sendable {
        var clockLabel: String?
        var clockMode: NotchClockMode = .countdown
        var clockSymbol: String = "timer"
        var clockPaused: Bool = false

        var agentCount: Int = 0
        var agentsNeedingYou: Int = 0
        var agentBusy: Bool = false

        var stagedFileCount: Int = 0
        var hasActiveFileTask: Bool = false
    }

    struct Input: Equatable, Sendable {
        var catalog: NotchTabCatalogState
        var availability: NotchDestinationAvailability
        var now: Date
        var nowPlaying: NowPlayingInput?
        var calendar: CalendarInput?
        var activeWork: ActiveWorkInput
        /// Optional self-destination ID (e.g. `.home`) excluded from quick-open links.
        var excludedQuickDestinationID: NotchDestinationID? = nil
    }

    enum CardKind: String, Equatable, Hashable, Sendable {
        case nowPlaying
        case calendar
        case activeWork
    }

    enum CardTint: String, Equatable, Hashable, Sendable {
        case pink
        case red
        case orange
        case purple
        case mint
        case cyan
    }

    enum CardBadge: Equatable, Sendable {
        case status(key: String)
        case countWaiting(Int)
        case none
    }

    enum CardSubtitle: Equatable, Sendable {
        case literal(String)
        case statusKey(String)
        case clockTime(label: String, paused: Bool)
        case agentCount(total: Int, waiting: Int, busy: Bool)
        case fileCount(Int, activeTask: Bool)
        case calendarTime(start: Date, inProgress: Bool)
    }

    struct Card: Equatable, Identifiable, Sendable {
        var id: String { kind.rawValue }
        var kind: CardKind
        var destination: NotchGalleryDestination
        var destinationID: NotchDestinationID
        var headerKey: String
        var symbol: String
        var tint: CardTint
        var titleLiteral: String?
        var titleKey: String?
        var subtitle: CardSubtitle
        var badge: CardBadge
        /// Number of additional active work subsystems beyond the lead active-work item.
        var extraActiveCount: Int = 0
    }

    struct Snapshot: Equatable, Sendable {
        var cards: [Card]
        var quickDestinations: [NotchDestinationID]

        var isEmpty: Bool { cards.isEmpty }

        /// Wide canvas (612 pt) lays 1–3 cards side by side; narrow canvas (382 pt) stacks in 1 column.
        func layoutColumns(isNarrow: Bool) -> Int {
            guard !cards.isEmpty else { return 1 }
            return isNarrow ? 1 : min(3, cards.count)
        }
    }

    static func build(_ input: Input) -> Snapshot {
        var cards: [Card] = []

        if let npCard = buildNowPlayingCard(input) {
            cards.append(npCard)
        }
        if let calCard = buildCalendarCard(input) {
            cards.append(calCard)
        }
        if let workCard = buildActiveWorkCard(input) {
            cards.append(workCard)
        }

        let quick = input.catalog
            .visibleDestinations(availability: input.availability)
            .filter { $0 != input.excludedQuickDestinationID }
            .prefix(4)

        return Snapshot(cards: cards, quickDestinations: Array(quick))
    }

    /// Formats a calendar event start time as `"HH:mm"` in the supplied time zone (pure, deterministic in tests).
    static func formatEventTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - Card Builders

    private static func buildNowPlayingCard(_ input: Input) -> Card? {
        guard input.catalog.isOpenable(.nowPlaying, availability: input.availability),
              let np = input.nowPlaying,
              np.hasContent else { return nil }

        let trimmedSubline = np.subline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedApp = (np.appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle: CardSubtitle
        if !trimmedSubline.isEmpty {
            subtitle = .literal(trimmedSubline)
        } else if !trimmedApp.isEmpty {
            subtitle = .literal(trimmedApp)
        } else {
            subtitle = .statusKey(np.isPlaying ? "Đang phát" : "Đang tạm dừng")
        }

        return Card(
            kind: .nowPlaying,
            destination: .page(.nowPlaying),
            destinationID: .nowPlaying,
            headerKey: "Đang phát",
            symbol: np.isPlaying ? "waveform" : "music.note",
            tint: .pink,
            titleLiteral: np.headline.trimmingCharacters(in: .whitespacesAndNewlines),
            titleKey: nil,
            subtitle: subtitle,
            badge: .status(key: np.isPlaying ? "Đang phát" : "Đang tạm dừng")
        )
    }

    private static func buildCalendarCard(_ input: Input) -> Card? {
        guard input.catalog.isOpenable(.calendar, availability: input.availability),
              let cal = input.calendar,
              cal.hasContent,
              let title = cal.title?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }

        let inProgress: Bool = {
            guard !cal.isAllDay, let start = cal.start else { return false }
            let end = cal.end ?? start
            return start <= input.now && end > input.now
        }()

        let subtitle: CardSubtitle
        if let start = cal.start, !cal.isAllDay {
            subtitle = .calendarTime(start: start, inProgress: inProgress)
        } else {
            subtitle = .statusKey("Lịch sắp tới")
        }

        let badge: CardBadge
        if cal.hasMeetingLink {
            badge = .status(key: "Cuộc họp")
        } else if inProgress {
            badge = .status(key: "Đang diễn ra")
        } else {
            badge = .none
        }

        return Card(
            kind: .calendar,
            destination: .page(.calendar),
            destinationID: .calendar,
            headerKey: "Lịch sắp tới",
            symbol: "calendar",
            tint: .red,
            titleLiteral: title,
            titleKey: nil,
            subtitle: subtitle,
            badge: badge
        )
    }

    private static func buildActiveWorkCard(_ input: Input) -> Card? {
        let work = input.activeWork
        let agentsOpenable = input.catalog.isOpenable(.agents, availability: input.availability)
        let timerOpenable = input.catalog.isOpenable(.timer, availability: input.availability)
        let filesOpenable = input.catalog.isOpenable(.files, availability: input.availability)

        let hasAgents = agentsOpenable && work.agentCount > 0
        let hasTimer = timerOpenable && !(work.clockLabel ?? "").isEmpty
        let hasFiles = filesOpenable && (work.stagedFileCount > 0 || work.hasActiveFileTask)

        let activeSubsystems = [hasAgents, hasTimer, hasFiles].filter { $0 }.count
        guard activeSubsystems > 0 else { return nil }
        let extras = max(0, activeSubsystems - 1)

        // Priority mirrors `NotchCollapsedSignal`: agents waiting > running clock > files > paused clock > agents live.
        if hasAgents && work.agentsNeedingYou > 0 {
            return Card(
                kind: .activeWork,
                destination: .page(.agents),
                destinationID: .agents,
                headerKey: "Tác vụ đang chạy",
                symbol: "terminal.fill",
                tint: .purple,
                titleLiteral: nil,
                titleKey: "Agent AI",
                subtitle: .agentCount(total: work.agentCount, waiting: work.agentsNeedingYou, busy: work.agentBusy),
                badge: .countWaiting(work.agentsNeedingYou),
                extraActiveCount: extras
            )
        }

        if hasTimer, let label = work.clockLabel, !work.clockPaused {
            return Card(
                kind: .activeWork,
                destination: .page(.timer),
                destinationID: .timer,
                headerKey: "Tác vụ đang chạy",
                symbol: work.clockSymbol,
                tint: .orange,
                titleLiteral: label,
                titleKey: nil,
                subtitle: .clockTime(label: work.clockMode.titleKey, paused: false),
                badge: .status(key: "Đang chạy"),
                extraActiveCount: extras
            )
        }

        if hasFiles {
            return Card(
                kind: .activeWork,
                destination: .page(.files),
                destinationID: .files,
                headerKey: "Tác vụ đang chạy",
                symbol: "tray.fill",
                tint: .mint,
                titleLiteral: nil,
                titleKey: work.hasActiveFileTask ? "Đang xử lý tệp" : "Khay",
                subtitle: .fileCount(work.stagedFileCount, activeTask: work.hasActiveFileTask),
                badge: work.hasActiveFileTask ? .status(key: "Đang chạy") : .none,
                extraActiveCount: extras
            )
        }

        if hasTimer, let label = work.clockLabel {
            return Card(
                kind: .activeWork,
                destination: .page(.timer),
                destinationID: .timer,
                headerKey: "Tác vụ đang chạy",
                symbol: work.clockSymbol,
                tint: .orange,
                titleLiteral: label,
                titleKey: nil,
                subtitle: .clockTime(label: work.clockMode.titleKey, paused: true),
                badge: .status(key: "Đang tạm dừng"),
                extraActiveCount: extras
            )
        }

        if hasAgents {
            return Card(
                kind: .activeWork,
                destination: .page(.agents),
                destinationID: .agents,
                headerKey: "Tác vụ đang chạy",
                symbol: "terminal.fill",
                tint: .purple,
                titleLiteral: nil,
                titleKey: "Agent AI",
                subtitle: .agentCount(total: work.agentCount, waiting: 0, busy: work.agentBusy),
                badge: work.agentBusy ? .status(key: "Đang bận") : .none,
                extraActiveCount: extras
            )
        }

        return nil
    }
}
