import Foundation

/// Modes inside the Dynamic Island Timer tool (`NotchTimerPage`).
enum NotchClockMode: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case countdown
    case stopwatch
    case pomodoro

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .countdown: return "Hẹn giờ"
        case .stopwatch: return "Bấm giờ"
        case .pomodoro: return "Pomodoro"
        }
    }

    var symbol: String {
        switch self {
        case .countdown: return "timer"
        case .stopwatch: return "stopwatch"
        case .pomodoro: return "flame.fill"
        }
    }
}

/// Pure wall-clock stopwatch: running = `startedAt != nil`, paused = `startedAt == nil && isActive`.
/// Survives sleep/wake and relaunch via `accumulated + max(0, now - startedAt)`.
struct NotchStopwatch: Equatable, Codable, Sendable {
    static let maxLaps = 50

    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date? = nil
    private(set) var laps: [TimeInterval] = []

    var isRunning: Bool { startedAt != nil }
    var isActive: Bool { isRunning || accumulated > 0 || !laps.isEmpty }
    var isPaused: Bool { !isRunning && isActive }

    func elapsed(at now: Date) -> TimeInterval {
        let running = startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, accumulated + running)
    }

    /// "0:00", "12:34", "1:02:03" — whole elapsed seconds (floored, matching standard stopwatch ticks).
    func label(at now: Date) -> String {
        Self.formatDuration(elapsed(at: now))
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func started(at now: Date) -> NotchStopwatch {
        guard !isRunning else { return self }
        var copy = self
        copy.startedAt = now
        return copy
    }

    func paused(at now: Date) -> NotchStopwatch {
        guard isRunning else { return self }
        var copy = self
        copy.accumulated = elapsed(at: now)
        copy.startedAt = nil
        return copy
    }

    func resumed(at now: Date) -> NotchStopwatch {
        started(at: now)
    }

    func recordedLap(at now: Date) -> NotchStopwatch {
        guard isActive else { return self }
        var copy = self
        copy.laps.append(elapsed(at: now))
        if copy.laps.count > Self.maxLaps {
            copy.laps.removeFirst(copy.laps.count - Self.maxLaps)
        }
        return copy
    }

    func reset() -> NotchStopwatch {
        NotchStopwatch()
    }
}

/// Pure Pomodoro state machine with focus, short break, and long break phases.
/// Transitions to the next phase in a ready (idle) state on completion so sleep/wake or app quit
/// never spams chained alerts.
struct NotchPomodoro: Equatable, Codable, Sendable {
    enum Phase: String, Codable, Equatable, Sendable {
        case focus
        case shortBreak
        case longBreak

        var titleKey: String {
            switch self {
            case .focus: return "Tập trung"
            case .shortBreak: return "Nghỉ ngắn"
            case .longBreak: return "Nghỉ dài"
            }
        }

        var symbol: String {
            switch self {
            case .focus: return "flame.fill"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak: return "sparkles"
            }
        }
    }

    struct Config: Equatable, Codable, Sendable {
        var focusMinutes: Int = 25
        var shortBreakMinutes: Int = 5
        var longBreakMinutes: Int = 15
        var cyclesBeforeLongBreak: Int = 4

        init(
            focusMinutes: Int = 25,
            shortBreakMinutes: Int = 5,
            longBreakMinutes: Int = 15,
            cyclesBeforeLongBreak: Int = 4
        ) {
            self.focusMinutes = min(max(focusMinutes, 5), 90)
            self.shortBreakMinutes = min(max(shortBreakMinutes, 1), 30)
            self.longBreakMinutes = min(max(longBreakMinutes, 5), 60)
            self.cyclesBeforeLongBreak = min(max(cyclesBeforeLongBreak, 2), 8)
        }

        func duration(for phase: Phase) -> TimeInterval {
            switch phase {
            case .focus: return TimeInterval(focusMinutes * 60)
            case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
            case .longBreak: return TimeInterval(longBreakMinutes * 60)
            }
        }
    }

    private(set) var config: Config
    private(set) var phase: Phase
    private(set) var completedFocusSessions: Int
    private(set) var duration: TimeInterval
    private(set) var endsAt: Date?
    private(set) var pausedRemaining: TimeInterval?

    init(config: Config = Config()) {
        self.config = config
        self.phase = .focus
        self.completedFocusSessions = 0
        self.duration = config.duration(for: .focus)
        self.endsAt = nil
        self.pausedRemaining = nil
    }

    var isRunning: Bool { endsAt != nil }
    var isPaused: Bool { endsAt == nil && pausedRemaining != nil }
    var isActive: Bool { isRunning || isPaused }

    /// 1-based focus slot within the current cycle (1…cyclesBeforeLongBreak).
    var cycleSlot: Int {
        let n = max(1, config.cyclesBeforeLongBreak)
        return (completedFocusSessions % n) + 1
    }

    /// Number of completed focus dots in the current cycle (0…cyclesBeforeLongBreak).
    var completedDotsInCycle: Int {
        let n = max(1, config.cyclesBeforeLongBreak)
        if phase == .longBreak { return n }
        return completedFocusSessions % n
    }

    func remaining(at now: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
        if let pausedRemaining { return max(0, pausedRemaining) }
        return max(0, duration)
    }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    func isPhaseFinished(at now: Date) -> Bool {
        isRunning && remaining(at: now) <= 0
    }

    /// Whole seconds rounded UP, matching `LiveActivity.Countdown`.
    func label(at now: Date) -> String {
        let t = Int(remaining(at: now).rounded(.up))
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func started(at now: Date) -> NotchPomodoro {
        guard !isRunning else { return self }
        var copy = self
        let left = pausedRemaining ?? duration
        copy.endsAt = now.addingTimeInterval(max(1, left))
        copy.pausedRemaining = nil
        return copy
    }

    func paused(at now: Date) -> NotchPomodoro {
        guard isRunning else { return self }
        var copy = self
        copy.pausedRemaining = remaining(at: now)
        copy.endsAt = nil
        return copy
    }

    func resumed(at now: Date) -> NotchPomodoro {
        guard isPaused else { return self }
        return started(at: now)
    }

    /// Completes the current phase, increments focus count when finishing `.focus`,
    /// and prepares the next phase in ready (idle) state.
    func advancedAfterCompletion() -> (state: NotchPomodoro, completed: Phase) {
        let completed = phase
        var copy = self
        switch completed {
        case .focus:
            copy.completedFocusSessions += 1
            let n = max(1, copy.config.cyclesBeforeLongBreak)
            copy.phase = (copy.completedFocusSessions % n == 0) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            copy.phase = .focus
        }
        copy.duration = copy.config.duration(for: copy.phase)
        copy.endsAt = nil
        copy.pausedRemaining = nil
        return (copy, completed)
    }

    /// Skips the current phase without crediting an unfinished focus session.
    func skipped() -> NotchPomodoro {
        var copy = self
        switch phase {
        case .focus:
            copy.phase = .shortBreak
        case .shortBreak, .longBreak:
            copy.phase = .focus
        }
        copy.duration = copy.config.duration(for: copy.phase)
        copy.endsAt = nil
        copy.pausedRemaining = nil
        return copy
    }

    func reset() -> NotchPomodoro {
        NotchPomodoro(config: config)
    }
}

/// Optional periodic hydration reminder. OFF by default; coalesces missed intervals across sleep/relaunch
/// into a single due event so the user is never spammed on wake.
struct NotchHydrationReminder: Equatable, Codable, Sendable {
    static let enabledKey = "notch.timer.hydration.enabled"
    static let intervalKey = "notch.timer.hydration.intervalMinutes"

    static let minIntervalMinutes = 15
    static let maxIntervalMinutes = 180
    static let defaultIntervalMinutes = 45
    static let snoozeMinutes = 10
    static let intervalPresets = [30, 45, 60, 90]
    static let dailyLimitRange = 1...8
    static let defaultDailyLimit = 6
    static let firstHour = 8
    static let lastHour = 20

    private(set) var enabled: Bool = false
    private(set) var intervalMinutes: Int = defaultIntervalMinutes
    private(set) var nextDueAt: Date? = nil
    // Optional fields keep existing v1 clock state decodable.
    private var savedDailyLimit: Int?
    private var dayStart: Date?
    private var dailyCount: Int?

    var dailyLimit: Int {
        min(max(savedDailyLimit ?? Self.defaultDailyLimit, Self.dailyLimitRange.lowerBound), Self.dailyLimitRange.upperBound)
    }
    private var scheduledGap: Int {
        max(intervalMinutes, (Self.lastHour - Self.firstHour) * 60 / dailyLimit)
    }

    init(enabled: Bool = false, intervalMinutes: Int = defaultIntervalMinutes, nextDueAt: Date? = nil) {
        self.enabled = enabled
        self.intervalMinutes = Self.validIntervalMinutes(intervalMinutes)
        self.nextDueAt = enabled ? nextDueAt : nil
    }

    static func validIntervalMinutes(_ minutes: Int?) -> Int {
        guard let minutes else { return defaultIntervalMinutes }
        return min(max(minutes, minIntervalMinutes), maxIntervalMinutes)
    }

    static func nextPreset(after current: Int) -> Int {
        if let idx = intervalPresets.firstIndex(of: current) {
            return intervalPresets[(idx + 1) % intervalPresets.count]
        }
        return intervalPresets.first(where: { $0 > current }) ?? intervalPresets[0]
    }

    mutating func setEnabled(_ isOn: Bool, now: Date) {
        enabled = isOn
        nextDueAt = isOn ? eligible(now.addingTimeInterval(TimeInterval(scheduledGap * 60)), now: now) : nil
    }

    mutating func setInterval(minutes: Int, now: Date) {
        intervalMinutes = Self.validIntervalMinutes(minutes)
        if enabled {
            nextDueAt = eligible(now.addingTimeInterval(TimeInterval(scheduledGap * 60)), now: now)
        }
    }

    mutating func setDailyLimit(_ limit: Int, now: Date) {
        savedDailyLimit = min(max(limit, Self.dailyLimitRange.lowerBound), Self.dailyLimitRange.upperBound)
        if enabled {
            nextDueAt = eligible(now.addingTimeInterval(TimeInterval(scheduledGap * 60)), now: now)
        }
    }

    mutating func acknowledge(now: Date) {
        guard enabled else {
            nextDueAt = nil
            return
        }
        nextDueAt = eligible(now.addingTimeInterval(TimeInterval(scheduledGap * 60)), now: now)
    }

    mutating func snooze(minutes: Int = snoozeMinutes, now: Date) {
        guard enabled else {
            nextDueAt = nil
            return
        }
        nextDueAt = eligible(now.addingTimeInterval(TimeInterval(max(1, minutes) * 60)), now: now)
    }

    func secondsUntilDue(at now: Date) -> TimeInterval? {
        guard enabled, let nextDueAt else { return nil }
        return max(0, nextDueAt.timeIntervalSince(now))
    }

    /// Evaluates whether hydration is due at `now`. Returns true at most once per wake/relaunch
    /// and reschedules `nextDueAt` to `now + interval`.
    mutating func reconcile(at now: Date) -> Bool {
        guard enabled else {
            nextDueAt = nil
            return false
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        if dayStart != start {
            dayStart = start
            dailyCount = 0
        }
        guard Self.firstHour..<Self.lastHour ~= calendar.component(.hour, from: now),
              (dailyCount ?? 0) < dailyLimit else {
            nextDueAt = eligible(max(now, nextDueAt ?? now), now: now)
            return false
        }
        guard let due = nextDueAt else {
            nextDueAt = eligible(now.addingTimeInterval(TimeInterval(scheduledGap * 60)), now: now)
            return false
        }
        if now >= due {
            dailyCount = (dailyCount ?? 0) + 1
            nextDueAt = eligible(now.addingTimeInterval(TimeInterval(scheduledGap * 60)), now: now)
            return true
        }
        return false
    }

    private func eligible(_ preferred: Date, now: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: preferred)
        let opening = calendar.date(bySettingHour: Self.firstHour, minute: 0, second: 0, of: day) ?? preferred
        let closing = calendar.date(bySettingHour: Self.lastHour, minute: 0, second: 0, of: day) ?? preferred
        if preferred >= closing || (dayStart == day && (dailyCount ?? 0) >= dailyLimit) {
            return calendar.date(byAdding: .day, value: 1, to: opening) ?? now.addingTimeInterval(3600)
        }
        return max(preferred, opening)
    }
}

/// Unified pure state for Countdown, Stopwatch, Pomodoro, and optional Hydration reminder.
/// Owns collapsed badge arbitration, sleep/wake & relaunch reconciliation, and Codable persistence.
struct NotchClockSuite: Equatable, Codable, Sendable {
    static let stateStorageKey = "notch.clock.state.v1"

    struct CollapsedBadge: Equatable, Sendable {
        let mode: NotchClockMode
        let symbol: String
        let text: String
        let isPaused: Bool
        let titleKey: String
    }

    enum ClockEvent: Equatable, Sendable {
        case countdownFinished(LiveActivity.Countdown)
        case pomodoroPhaseFinished(completed: NotchPomodoro.Phase, next: NotchPomodoro.Phase, completedFocusSessions: Int)
        case hydrationDue(intervalMinutes: Int)
    }

    var selectedMode: NotchClockMode = .countdown
    var countdown: LiveActivity.Countdown? = nil
    var stopwatch: NotchStopwatch = NotchStopwatch()
    var pomodoro: NotchPomodoro = NotchPomodoro()
    var hydration: NotchHydrationReminder = NotchHydrationReminder()

    /// True only when a visible ticking clock is actively advancing (drives the 1 s ticker).
    /// Hydration alone uses a one-shot timer and never keeps the 1 s ticker alive.
    var needsSecondTicker: Bool {
        (countdown != nil && countdown?.isPaused == false) || stopwatch.isRunning || pomodoro.isRunning
    }

    var hasAnyActiveClock: Bool {
        countdown != nil || stopwatch.isActive || pomodoro.isActive
    }

    /// Deterministic collapsed badge arbitration:
    /// 1. Running clocks win over paused clocks.
    /// 2. Within the same tier (running or paused), `selectedMode` wins ties; otherwise
    ///    priority is Countdown → Pomodoro → Stopwatch.
    /// 3. Hydration waiting in the background never claims the collapsed clock wing.
    func collapsedBadge(at now: Date) -> CollapsedBadge? {
        let runningOrder = prioritizedModes()
        for mode in runningOrder {
            if let badge = badge(for: mode, runningOnly: true, at: now) {
                return badge
            }
        }
        for mode in runningOrder {
            if let badge = badge(for: mode, runningOnly: false, at: now) {
                return badge
            }
        }
        return nil
    }

    private func prioritizedModes() -> [NotchClockMode] {
        var order: [NotchClockMode] = [selectedMode]
        for mode in [NotchClockMode.countdown, .pomodoro, .stopwatch] where !order.contains(mode) {
            order.append(mode)
        }
        return order
    }

    private func badge(for mode: NotchClockMode, runningOnly: Bool, at now: Date) -> CollapsedBadge? {
        switch mode {
        case .countdown:
            guard let c = countdown else { return nil }
            if runningOnly && c.isPaused { return nil }
            if !runningOnly && !c.isPaused { return nil }
            return CollapsedBadge(
                mode: .countdown,
                symbol: c.isPaused ? "pause.fill" : "timer",
                text: c.label(at: now),
                isPaused: c.isPaused,
                titleKey: "Hẹn giờ"
            )
        case .pomodoro:
            guard pomodoro.isActive else { return nil }
            if runningOnly && !pomodoro.isRunning { return nil }
            if !runningOnly && !pomodoro.isPaused { return nil }
            return CollapsedBadge(
                mode: .pomodoro,
                symbol: pomodoro.isPaused ? "pause.fill" : pomodoro.phase.symbol,
                text: pomodoro.label(at: now),
                isPaused: pomodoro.isPaused,
                titleKey: "Pomodoro"
            )
        case .stopwatch:
            guard stopwatch.isActive else { return nil }
            if runningOnly && !stopwatch.isRunning { return nil }
            if !runningOnly && !stopwatch.isPaused { return nil }
            return CollapsedBadge(
                mode: .stopwatch,
                symbol: stopwatch.isPaused ? "pause.fill" : "stopwatch",
                text: stopwatch.label(at: now),
                isPaused: stopwatch.isPaused,
                titleKey: "Bấm giờ"
            )
        }
    }

    /// Reconciles every clock and optional hydration reminder at `now` (tick, sleep/wake, or relaunch).
    mutating func reconcile(at now: Date) -> [ClockEvent] {
        var events: [ClockEvent] = []

        if let c = countdown, c.isFinished(at: now) {
            countdown = nil
            events.append(.countdownFinished(c))
        }

        if pomodoro.isPhaseFinished(at: now) {
            let result = pomodoro.advancedAfterCompletion()
            pomodoro = result.state
            events.append(.pomodoroPhaseFinished(
                completed: result.completed,
                next: pomodoro.phase,
                completedFocusSessions: pomodoro.completedFocusSessions
            ))
        }

        if hydration.reconcile(at: now) {
            events.append(.hydrationDue(intervalMinutes: hydration.intervalMinutes))
        }

        return events
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Restores persisted state, syncing explicit hydration preferences if present and falling back
    /// cleanly on missing or corrupted data.
    static func decoded(
        from data: Data?,
        hydrationEnabledOverride: Bool? = nil,
        hydrationIntervalOverride: Int? = nil,
        now: Date = Date()
    ) -> NotchClockSuite {
        var suite: NotchClockSuite
        if let data, let parsed = try? JSONDecoder().decode(NotchClockSuite.self, from: data) {
            suite = parsed
        } else {
            suite = NotchClockSuite()
        }
        if let interval = hydrationIntervalOverride {
            let valid = NotchHydrationReminder.validIntervalMinutes(interval)
            if valid != suite.hydration.intervalMinutes {
                suite.hydration.setInterval(minutes: valid, now: now)
            }
        }
        if let enabled = hydrationEnabledOverride, enabled != suite.hydration.enabled {
            suite.hydration.setEnabled(enabled, now: now)
        }
        return suite
    }

    // MARK: - LiveActivity item factories

    static func pomodoroFinishedItem(completed: NotchPomodoro.Phase, next: NotchPomodoro.Phase) -> LiveActivity.Item {
        let titleKey: String
        switch completed {
        case .focus:
            titleKey = next == .longBreak ? "Xong phiên tập trung — nghỉ dài" : "Xong phiên tập trung"
        case .shortBreak:
            titleKey = "Hết giờ nghỉ ngắn"
        case .longBreak:
            titleKey = "Hết giờ nghỉ dài"
        }
        return LiveActivity.Item(
            kind: .timer,
            symbol: next.symbol,
            titleKey: titleKey,
            detail: nil,
            tint: completed == .focus ? .good : .warning,
            duration: 8
        )
    }

    static func hydrationDueItem(intervalMinutes: Int) -> LiveActivity.Item {
        LiveActivity.Item(
            kind: .timer,
            symbol: "drop.fill",
            titleKey: "Đến giờ uống nước",
            detail: "\(intervalMinutes)m",
            tint: .neutral,
            duration: 10,
            buttons: [.hydrateAck, .hydrateSnooze(minutes: NotchHydrationReminder.snoozeMinutes)]
        )
    }
}
