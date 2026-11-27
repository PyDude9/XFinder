import AppKit
import CoreGraphics
import Foundation
import Observation

/// Abstraction over macOS workspace, session, lock, sleep/wake, and timezone notifications so
/// `LocalAppUsageTracker` can be tested deterministically without observing real user activity.
@MainActor
protocol LocalAppUsageObserverBackend: AnyObject {
    var isAttached: Bool { get }
    func currentFrontmostApp() -> LocalAppUsageRules.AppIdentity?
    func attach(
        onAppActivate: @escaping @MainActor (LocalAppUsageRules.AppIdentity?) -> Void,
        onSessionResign: @escaping @MainActor () -> Void,
        onSessionBecomeActive: @escaping @MainActor () -> Void,
        onScreenLock: @escaping @MainActor () -> Void,
        onScreenUnlock: @escaping @MainActor () -> Void,
        onWillSleep: @escaping @MainActor () -> Void,
        onDidWake: @escaping @MainActor () -> Void,
        onTimeZoneOrDayChange: @escaping @MainActor () -> Void
    )
    func detach()
}

/// Abstraction over the active-only sampling heartbeat so unit tests drive ticks deterministically
/// and verify zero timers exist when tracking is off, paused, or suspended.
@MainActor
protocol LocalAppUsageScheduler: AnyObject {
    var isScheduled: Bool { get }
    func scheduleRepeating(interval: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

/// Production `DispatchSourceTimer` scheduler on the main queue. Holds no timer when cancelled.
@MainActor
final class DispatchAppUsageScheduler: LocalAppUsageScheduler {
    private var timer: DispatchSourceTimer?

    var isScheduled: Bool { timer != nil }

    func scheduleRepeating(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        let clamped = max(1, interval)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + clamped, repeating: clamped, leeway: .seconds(1))
        source.setEventHandler {
            MainActor.assumeIsolated {
                action()
            }
        }
        timer = source
        source.resume()
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }
}

/// Production observer backend wired to `NSWorkspace`, `DistributedNotificationCenter`, and
/// `NotificationCenter.default`. Attaches zero observers until `attach(...)` is called and removes
/// every token in `detach()`.
@MainActor
final class WorkspaceAppUsageObserverBackend: LocalAppUsageObserverBackend {
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var defaultTokens: [NSObjectProtocol] = []
    private(set) var isAttached = false

    func currentFrontmostApp() -> LocalAppUsageRules.AppIdentity? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return LocalAppUsageRules.normalizeApp(
            bundleID: app.bundleIdentifier,
            localizedName: app.localizedName
        )
    }

    func attach(
        onAppActivate: @escaping @MainActor (LocalAppUsageRules.AppIdentity?) -> Void,
        onSessionResign: @escaping @MainActor () -> Void,
        onSessionBecomeActive: @escaping @MainActor () -> Void,
        onScreenLock: @escaping @MainActor () -> Void,
        onScreenUnlock: @escaping @MainActor () -> Void,
        onWillSleep: @escaping @MainActor () -> Void,
        onDidWake: @escaping @MainActor () -> Void,
        onTimeZoneOrDayChange: @escaping @MainActor () -> Void
    ) {
        detach()
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default

        workspaceTokens.append(
            ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let identity = app.map {
                    LocalAppUsageRules.normalizeApp(bundleID: $0.bundleIdentifier, localizedName: $0.localizedName)
                }
                Task { @MainActor in onAppActivate(identity) }
            }
        )
        workspaceTokens.append(
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: nil) { _ in
                Task { @MainActor in onSessionResign() }
            }
        )
        workspaceTokens.append(
            ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: nil) { _ in
                Task { @MainActor in onSessionBecomeActive() }
            }
        )
        workspaceTokens.append(
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { _ in
                Task { @MainActor in onWillSleep() }
            }
        )
        workspaceTokens.append(
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in
                Task { @MainActor in onDidWake() }
            }
        )

        distributedTokens.append(
            dist.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: nil) { _ in
                Task { @MainActor in onScreenLock() }
            }
        )
        distributedTokens.append(
            dist.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: nil) { _ in
                Task { @MainActor in onScreenUnlock() }
            }
        )

        defaultTokens.append(
            nc.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: nil) { _ in
                Task { @MainActor in onTimeZoneOrDayChange() }
            }
        )
        defaultTokens.append(
            nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: nil) { _ in
                Task { @MainActor in onTimeZoneOrDayChange() }
            }
        )

        isAttached = true
    }

    func detach() {
        let ws = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens { ws.removeObserver(token) }
        workspaceTokens.removeAll()

        let dist = DistributedNotificationCenter.default()
        for token in distributedTokens { dist.removeObserver(token) }
        distributedTokens.removeAll()

        let nc = NotificationCenter.default
        for token in defaultTokens { nc.removeObserver(token) }
        defaultTokens.removeAll()

        isAttached = false
    }
}

/// Local foreground app usage tracker for Dynamic Island.
///
/// Lifecycle & privacy guarantees:
/// - Default opt-in is `false`; `init()` never attaches observers or starts timers.
/// - Coordinator calls `startIfEnabled()` on launch and `shutdown()` on app termination.
/// - Turning tracking OFF (`stopTracking()`) immediately detaches all observers and cancels the timer.
/// - Pausing (`pauseTracking()`) flushes the active segment, detaches observers, and cancels the timer.
/// - Read failures (`isReadBlocked`) preserve the existing file on disk and refuse to overwrite until `retryLoad()` succeeds.
/// - `confirmClearHistory()` bumps `historyEpoch` and resets the active segment so pre-clear time is never re-added.
@MainActor
@Observable
final class LocalAppUsageTracker {

    static let shared = LocalAppUsageTracker()

    nonisolated static var defaultFileURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return appSupport
            .appendingPathComponent("XFinder", isDirectory: true)
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("local-app-usage.json", isDirectory: false)
    }

    nonisolated static func defaultIdleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return 0 }
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    // MARK: - Configuration

    let fileURL: URL
    let idleThresholdSeconds: TimeInterval
    let sampleIntervalSeconds: TimeInterval
    let maxSampleDeltaSeconds: TimeInterval
    let retentionDays: Int

    // MARK: - Observable State

    private(set) var isTrackingEnabled: Bool
    private(set) var isPaused: Bool = false
    private(set) var isIdle: Bool = false
    private(set) var isAsleep: Bool = false
    private(set) var isScreenLocked: Bool = false
    private(set) var isSessionActive: Bool = true
    private(set) var readError: String?
    private(set) var saveError: String?
    private(set) var confirmingClear: Bool = false
    private(set) var snapshot: LocalAppUsageRules.DashboardSnapshot

    var isReadBlocked: Bool { readError != nil }
    var isSuspended: Bool { isAsleep || isScreenLocked || !isSessionActive }
    var hasHistory: Bool { !store.isEmpty }
    var isActivelyCollecting: Bool {
        isTrackingEnabled && !isPaused && !isReadBlocked && !isSuspended && !isIdle && observerBackend.isAttached
    }

    // MARK: - Internal State & Dependencies

    private var store: LocalAppUsageRules.UsageStore = LocalAppUsageRules.UsageStore()
    private var activeSegment: LocalAppUsageRules.ActiveSegment?
    private var fractionalCarry: [String: Double] = [:]
    private var historyEpoch: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0
    private var activeCalendar: Calendar

    private let observerBackend: LocalAppUsageObserverBackend
    private let scheduler: LocalAppUsageScheduler
    private let nowProvider: () -> Date
    private let calendarProvider: () -> Calendar
    private let idleSecondsProvider: () -> TimeInterval
    private let readData: (URL) throws -> Data?
    private let writeData: (Data, URL) throws -> Void
    private let defaults: UserDefaults?
    private let defaultsKey: String

    // MARK: - Init

    init(
        fileURL: URL = LocalAppUsageTracker.defaultFileURL,
        idleThresholdSeconds: TimeInterval = LocalAppUsageRules.defaultIdleThresholdSeconds,
        sampleIntervalSeconds: TimeInterval = LocalAppUsageRules.defaultSampleIntervalSeconds,
        maxSampleDeltaSeconds: TimeInterval = LocalAppUsageRules.defaultMaxSampleDeltaSeconds,
        retentionDays: Int = LocalAppUsageRules.retentionDays,
        observerBackend: LocalAppUsageObserverBackend? = nil,
        scheduler: LocalAppUsageScheduler? = nil,
        nowProvider: @escaping () -> Date = { Date() },
        calendarProvider: @escaping () -> Calendar = { Calendar.current },
        idleSecondsProvider: @escaping () -> TimeInterval = { LocalAppUsageTracker.defaultIdleSeconds() },
        readData: ((URL) throws -> Data?)? = nil,
        writeData: ((Data, URL) throws -> Void)? = nil,
        defaults: UserDefaults? = .standard,
        defaultsKey: String = LocalAppUsageRules.trackingEnabledDefaultsKey
    ) {
        self.fileURL = fileURL
        self.idleThresholdSeconds = max(1, idleThresholdSeconds)
        self.sampleIntervalSeconds = max(1, sampleIntervalSeconds)
        self.maxSampleDeltaSeconds = max(1, maxSampleDeltaSeconds)
        self.retentionDays = max(1, retentionDays)
        self.observerBackend = observerBackend ?? WorkspaceAppUsageObserverBackend()
        self.scheduler = scheduler ?? DispatchAppUsageScheduler()
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
        self.idleSecondsProvider = idleSecondsProvider
        self.readData = readData ?? Self.defaultReadData
        self.writeData = writeData ?? Self.defaultWriteData
        self.defaults = defaults
        self.defaultsKey = defaultsKey

        let initialCal = calendarProvider()
        self.activeCalendar = initialCal
        self.isTrackingEnabled = (defaults?.object(forKey: defaultsKey) as? Bool) ?? false
        self.snapshot = LocalAppUsageRules.DashboardSnapshot.empty(referenceDate: nowProvider(), calendar: initialCal)

        loadFromDisk()
    }

    // MARK: - Coordinator & User Lifecycle API

    /// Called by the app coordinator on launch. Begins collection ONLY if the user previously opted in
    /// and the persisted store loaded cleanly.
    func startIfEnabled() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked else {
            teardownCollection()
            return
        }
        beginCollection()
    }

    /// Explicit user opt-in. Persists the preference and starts collection immediately (unless read-blocked).
    func startTracking() {
        confirmingClear = false
        isTrackingEnabled = true
        isPaused = false
        defaults?.set(true, forKey: defaultsKey)
        guard !isReadBlocked else {
            teardownCollection()
            return
        }
        beginCollection()
    }

    /// Explicit user opt-out. Flushes any valid active segment, persists preference = false, and
    /// immediately detaches all observers and cancels the sampling timer.
    func stopTracking() {
        confirmingClear = false
        let wasTracking = isTrackingEnabled
        if wasTracking && !isPaused && !isReadBlocked && !isSuspended {
            flushActiveSegment(at: nowProvider(), persistIfChanged: true)
        }
        isTrackingEnabled = false
        isPaused = false
        isIdle = false
        defaults?.set(false, forKey: defaultsKey)
        teardownCollection()
        refreshSnapshot(at: nowProvider())
    }

    /// Pauses collection while keeping the user's opt-in enabled. Detaches observers and cancels the timer
    /// so paused state consumes zero CPU and accrues zero time.
    func pauseTracking() {
        guard isTrackingEnabled, !isPaused else { return }
        confirmingClear = false
        if !isReadBlocked && !isSuspended {
            flushActiveSegment(at: nowProvider(), persistIfChanged: true)
        }
        isPaused = true
        isIdle = false
        teardownCollection()
        refreshSnapshot(at: nowProvider())
    }

    /// Resumes collection after `pauseTracking()` with a fresh timestamp anchor.
    func resumeTracking() {
        guard isTrackingEnabled, isPaused else { return }
        confirmingClear = false
        isPaused = false
        guard !isReadBlocked else {
            teardownCollection()
            return
        }
        beginCollection()
    }

    /// Called by the app coordinator on application termination. Flushes cleanly and releases observers/timers
    /// without altering the user's saved opt-in preference.
    func shutdown() {
        let now = nowProvider()
        if isTrackingEnabled && !isPaused && !isReadBlocked && !isSuspended {
            flushActiveSegment(at: now, persistIfChanged: true)
        }
        teardownCollection()
        refreshSnapshot(at: now)
    }

    /// Called when the Island page appears so the displayed totals include time accrued since the last tick.
    /// Never starts tracking if tracking is off or paused.
    func refreshForDisplay() {
        let now = nowProvider()
        if isTrackingEnabled && !isPaused && !isReadBlocked && !isSuspended && observerBackend.isAttached {
            handleSampleTick()
        } else {
            activeCalendar = calendarProvider()
            refreshSnapshot(at: now)
        }
    }

    // MARK: - Clear History (Two-Step Confirmation)

    func requestClearHistory() {
        guard !isReadBlocked, hasHistory else { return }
        confirmingClear = true
    }

    func cancelClearHistory() {
        confirmingClear = false
    }

    /// Clears all persisted usage history and advances `historyEpoch` + active segment anchor so
    /// time accumulated before the clear is never re-added.
    @discardableResult
    func confirmClearHistory() -> Bool {
        confirmingClear = false
        guard !isReadBlocked else { return false }

        let now = nowProvider()
        historyEpoch &+= 1
        store = LocalAppUsageRules.UsageStore()
        fractionalCarry.removeAll()

        // Drop the old segment and re-anchor at `now` only if actively collecting.
        if isTrackingEnabled && !isPaused && !isSuspended && !isIdle && observerBackend.isAttached {
            if let current = observerBackend.currentFrontmostApp() {
                activeSegment = LocalAppUsageRules.ActiveSegment(
                    app: current,
                    startedAt: now,
                    historyEpoch: historyEpoch
                )
            } else {
                activeSegment = nil
            }
        } else {
            activeSegment = nil
        }

        let persisted = persistStore()
        refreshSnapshot(at: now)
        return persisted
    }

    // MARK: - Reload After Read Error

    /// Retries loading from disk after a read failure. Never overwrites the file on failure.
    @discardableResult
    func retryLoad() -> Bool {
        confirmingClear = false
        loadFromDisk()
        guard !isReadBlocked else { return false }
        if isTrackingEnabled && !isPaused {
            beginCollection()
        }
        return true
    }

    // MARK: - Collection Plumbing

    private func beginCollection() {
        teardownCollection()
        guard isTrackingEnabled, !isPaused, !isReadBlocked else { return }

        lifecycleGeneration &+= 1
        let gen = lifecycleGeneration
        activeCalendar = calendarProvider()
        isAsleep = false
        isScreenLocked = false
        isSessionActive = true

        observerBackend.attach(
            onAppActivate: { [weak self] app in
                guard let self, self.lifecycleGeneration == gen else { return }
                self.handleAppActivated(app)
            },
            onSessionResign: { [weak self] in
                guard let self, self.lifecycleGeneration == gen else { return }
                self.handleSessionResigned()
            },
            onSessionBecomeActive: { [weak self] in
                guard let self, self.lifecycleGeneration == gen else { return }
                self.handleSessionBecameActive()
            },
            onScreenLock: { [weak self] in
                guard let self, self.lifecycleGeneration == gen else { return }
                self.handleScreenLocked()
            },
            onScreenUnlock: { [weak self] in
                guard let self, self.lifecycleGeneration == gen else { return }
                self.handleScreenUnlocked()
            },
            onWillSleep: { [weak self] in
                guard let self, self.lifecycleGeneration == gen else { return }
                self.handleWillSleep()
            },
            onDidWake: { [weak self] in
                guard let self, self.lifecycleGeneration == gen else { return }
                self.handleDidWake()
            },
            onTimeZoneOrDayChange: { [weak self] in
                guard let self, self.lifecycleGeneration == gen else { return }
                self.handleTimeZoneOrDayChanged()
            }
        )

        let now = nowProvider()
        let idleNow = idleSecondsProvider() >= idleThresholdSeconds
        isIdle = idleNow
        if !idleNow, let app = observerBackend.currentFrontmostApp() {
            activeSegment = LocalAppUsageRules.ActiveSegment(
                app: app,
                startedAt: now,
                historyEpoch: historyEpoch
            )
        } else {
            activeSegment = nil
        }

        startHeartbeatIfEligible(generation: gen)
        refreshSnapshot(at: now)
    }

    private func teardownCollection() {
        lifecycleGeneration &+= 1
        scheduler.cancel()
        observerBackend.detach()
        activeSegment = nil
    }

    private func startHeartbeatIfEligible(generation: UInt64) {
        guard isTrackingEnabled, !isPaused, !isReadBlocked, !isSuspended, observerBackend.isAttached else {
            scheduler.cancel()
            return
        }
        scheduler.scheduleRepeating(interval: sampleIntervalSeconds) { [weak self] in
            guard let self, self.lifecycleGeneration == generation else { return }
            self.handleSampleTick()
        }
    }

    // MARK: - Event Handlers

    private func handleAppActivated(_ app: LocalAppUsageRules.AppIdentity?) {
        guard isTrackingEnabled, !isPaused, !isReadBlocked, !isSuspended else { return }
        let now = nowProvider()
        flushActiveSegment(at: now, persistIfChanged: true)

        if !isIdle, let app {
            activeSegment = LocalAppUsageRules.ActiveSegment(
                app: app,
                startedAt: now,
                historyEpoch: historyEpoch
            )
        } else {
            activeSegment = nil
        }
        refreshSnapshot(at: now)
    }

    private func handleSampleTick() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked, !isSuspended else { return }
        let now = nowProvider()

        let currentCal = calendarProvider()
        if currentCal.timeZone != activeCalendar.timeZone {
            handleTimeZoneOrDayChanged()
            return
        }

        let idleSeconds = idleSecondsProvider()
        let currentlyIdle = idleSeconds >= idleThresholdSeconds

        if isIdle {
            if !currentlyIdle {
                // User returned from idle: start fresh segment at `now`, never crediting idle gap.
                isIdle = false
                if let app = observerBackend.currentFrontmostApp() {
                    activeSegment = LocalAppUsageRules.ActiveSegment(
                        app: app,
                        startedAt: now,
                        historyEpoch: historyEpoch
                    )
                }
            }
            refreshSnapshot(at: now)
            return
        }

        if let seg = activeSegment {
            guard seg.historyEpoch == historyEpoch else {
                activeSegment = nil
                refreshSnapshot(at: now)
                return
            }
            let evaluation = LocalAppUsageRules.evaluateInterval(
                from: seg.startedAt,
                to: now,
                idleSeconds: idleSeconds,
                idleThreshold: idleThresholdSeconds,
                maxSampleDelta: maxSampleDeltaSeconds
            )
            var changed = false
            if let credit = evaluation.credit {
                let added = LocalAppUsageRules.recordInterval(
                    from: credit.start,
                    to: credit.end,
                    for: seg.app,
                    calendar: activeCalendar,
                    into: &store,
                    fractionalCarry: &fractionalCarry
                )
                changed = added > 0
            }

            if evaluation.isNowIdle {
                isIdle = true
                activeSegment = nil
            } else {
                activeSegment = LocalAppUsageRules.ActiveSegment(
                    app: seg.app,
                    startedAt: now,
                    historyEpoch: historyEpoch
                )
            }

            pruneAndPersistIfNeeded(changed: changed, at: now)
        } else if !currentlyIdle {
            if let app = observerBackend.currentFrontmostApp() {
                activeSegment = LocalAppUsageRules.ActiveSegment(
                    app: app,
                    startedAt: now,
                    historyEpoch: historyEpoch
                )
            }
        } else {
            isIdle = true
        }

        refreshSnapshot(at: now)
    }

    private func handleSessionResigned() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked else { return }
        let now = nowProvider()
        if !isSuspended {
            flushActiveSegment(at: now, persistIfChanged: true)
        }
        isSessionActive = false
        activeSegment = nil
        scheduler.cancel()
        refreshSnapshot(at: now)
    }

    private func handleSessionBecameActive() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked else { return }
        isSessionActive = true
        resumeAfterSuspensionIfReady()
    }

    private func handleScreenLocked() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked else { return }
        let now = nowProvider()
        if !isSuspended {
            flushActiveSegment(at: now, persistIfChanged: true)
        }
        isScreenLocked = true
        activeSegment = nil
        scheduler.cancel()
        refreshSnapshot(at: now)
    }

    private func handleScreenUnlocked() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked else { return }
        isScreenLocked = false
        resumeAfterSuspensionIfReady()
    }

    private func handleWillSleep() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked else { return }
        let now = nowProvider()
        if !isSuspended {
            flushActiveSegment(at: now, persistIfChanged: true)
        }
        isAsleep = true
        activeSegment = nil
        scheduler.cancel()
        refreshSnapshot(at: now)
    }

    private func handleDidWake() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked else { return }
        isAsleep = false
        resumeAfterSuspensionIfReady()
    }

    private func handleTimeZoneOrDayChanged() {
        guard isTrackingEnabled, !isPaused, !isReadBlocked else { return }
        let now = nowProvider()
        if !isSuspended {
            // Flush using the previous calendar/timezone up to `now` before switching.
            flushActiveSegment(at: now, persistIfChanged: true)
        }
        activeCalendar = calendarProvider()
        LocalAppUsageRules.pruneRetention(
            in: &store,
            referenceDate: now,
            calendar: activeCalendar,
            retentionDays: retentionDays
        )
        if !isSuspended && !isIdle && observerBackend.isAttached {
            if let app = observerBackend.currentFrontmostApp() {
                activeSegment = LocalAppUsageRules.ActiveSegment(
                    app: app,
                    startedAt: now,
                    historyEpoch: historyEpoch
                )
            }
        }
        refreshSnapshot(at: now)
    }

    private func resumeAfterSuspensionIfReady() {
        let now = nowProvider()
        guard isTrackingEnabled, !isPaused, !isReadBlocked, !isSuspended, observerBackend.isAttached else {
            refreshSnapshot(at: now)
            return
        }
        activeCalendar = calendarProvider()
        let idleNow = idleSecondsProvider() >= idleThresholdSeconds
        isIdle = idleNow
        if !idleNow, let app = observerBackend.currentFrontmostApp() {
            activeSegment = LocalAppUsageRules.ActiveSegment(
                app: app,
                startedAt: now,
                historyEpoch: historyEpoch
            )
        } else {
            activeSegment = nil
        }
        startHeartbeatIfEligible(generation: lifecycleGeneration)
        refreshSnapshot(at: now)
    }

    // MARK: - Flush & Persistence

    private func flushActiveSegment(at now: Date, persistIfChanged: Bool) {
        guard let seg = activeSegment else { return }
        activeSegment = nil

        guard seg.historyEpoch == historyEpoch else { return }

        let evaluation = LocalAppUsageRules.evaluateInterval(
            from: seg.startedAt,
            to: now,
            idleSeconds: idleSecondsProvider(),
            idleThreshold: idleThresholdSeconds,
            maxSampleDelta: maxSampleDeltaSeconds
        )
        isIdle = evaluation.isNowIdle

        var changed = false
        if let credit = evaluation.credit {
            let added = LocalAppUsageRules.recordInterval(
                from: credit.start,
                to: credit.end,
                for: seg.app,
                calendar: activeCalendar,
                into: &store,
                fractionalCarry: &fractionalCarry
            )
            changed = added > 0
        }

        if persistIfChanged {
            pruneAndPersistIfNeeded(changed: changed, at: now)
        }
    }

    private func pruneAndPersistIfNeeded(changed: Bool, at now: Date) {
        let beforeCount = store.days.count
        LocalAppUsageRules.pruneRetention(
            in: &store,
            referenceDate: now,
            calendar: activeCalendar,
            retentionDays: retentionDays
        )
        let pruned = store.days.count != beforeCount
        if changed || pruned {
            _ = persistStore()
        }
    }

    private func loadFromDisk() {
        let now = nowProvider()
        activeCalendar = calendarProvider()
        do {
            guard let data = try readData(fileURL) else {
                store = LocalAppUsageRules.UsageStore()
                readError = nil
                saveError = nil
                refreshSnapshot(at: now)
                return
            }
            let decoded = try LocalAppUsageRules.decodeStore(from: data)
            store = LocalAppUsageRules.sanitizeStore(
                decoded,
                referenceDate: now,
                calendar: activeCalendar,
                retentionDays: retentionDays
            )
            readError = nil
            refreshSnapshot(at: now)
        } catch {
            // Preserve the existing file on disk; block writes and collection until retry succeeds.
            readError = error.localizedDescription
            teardownCollection()
            refreshSnapshot(at: now)
        }
    }

    @discardableResult
    private func persistStore() -> Bool {
        guard !isReadBlocked else { return false }
        do {
            let data = try LocalAppUsageRules.encodeStore(store)
            try writeData(data, fileURL)
            saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func refreshSnapshot(at now: Date) {
        snapshot = LocalAppUsageRules.dashboardSnapshot(
            from: store,
            referenceDate: now,
            calendar: activeCalendar
        )
    }

    // MARK: - Default Disk I/O

    nonisolated private static func defaultReadData(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    nonisolated private static func defaultWriteData(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
