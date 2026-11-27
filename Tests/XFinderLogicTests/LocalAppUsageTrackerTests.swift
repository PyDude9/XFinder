import Foundation
import XCTest

@MainActor
final class LocalAppUsageTrackerTests: XCTestCase {

    // MARK: - Deterministic Fakes

    @MainActor
    private final class FakeObserverBackend: LocalAppUsageObserverBackend {
        private(set) var isAttached = false
        private(set) var attachCount = 0
        private(set) var detachCount = 0

        var frontmostApp: LocalAppUsageRules.AppIdentity?

        var onAppActivate: (@MainActor (LocalAppUsageRules.AppIdentity?) -> Void)?
        var onSessionResign: (@MainActor () -> Void)?
        var onSessionBecomeActive: (@MainActor () -> Void)?
        var onScreenLock: (@MainActor () -> Void)?
        var onScreenUnlock: (@MainActor () -> Void)?
        var onWillSleep: (@MainActor () -> Void)?
        var onDidWake: (@MainActor () -> Void)?
        var onTimeZoneOrDayChange: (@MainActor () -> Void)?

        func currentFrontmostApp() -> LocalAppUsageRules.AppIdentity? {
            frontmostApp
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
            isAttached = true
            attachCount += 1
            self.onAppActivate = onAppActivate
            self.onSessionResign = onSessionResign
            self.onSessionBecomeActive = onSessionBecomeActive
            self.onScreenLock = onScreenLock
            self.onScreenUnlock = onScreenUnlock
            self.onWillSleep = onWillSleep
            self.onDidWake = onDidWake
            self.onTimeZoneOrDayChange = onTimeZoneOrDayChange
        }

        func detach() {
            if isAttached { detachCount += 1 }
            isAttached = false
            onAppActivate = nil
            onSessionResign = nil
            onSessionBecomeActive = nil
            onScreenLock = nil
            onScreenUnlock = nil
            onWillSleep = nil
            onDidWake = nil
            onTimeZoneOrDayChange = nil
        }
    }

    @MainActor
    private final class FakeScheduler: LocalAppUsageScheduler {
        private(set) var isScheduled = false
        private(set) var scheduleCount = 0
        private(set) var cancelCount = 0
        private var action: (@MainActor () -> Void)?

        func scheduleRepeating(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
            isScheduled = true
            scheduleCount += 1
            self.action = action
        }

        func cancel() {
            if isScheduled { cancelCount += 1 }
            isScheduled = false
            action = nil
        }

        func fire() {
            action?()
        }
    }

    // MARK: - Helpers

    private struct Harness {
        let tracker: LocalAppUsageTracker
        let backend: FakeObserverBackend
        let scheduler: FakeScheduler
        let fileURL: URL
        let defaults: UserDefaults
        let suiteName: String
        let getNow: () -> Date
        let setNow: (Date) -> Void
        let advance: (TimeInterval) -> Void
        let setIdle: (TimeInterval) -> Void
        let setTimeZone: (TimeZone) -> Void
    }

    private func makeHarness(
        initialDate: Date? = nil,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!,
        idleThreshold: TimeInterval = 300,
        sampleInterval: TimeInterval = 15,
        maxSampleDelta: TimeInterval = 120,
        retentionDays: Int = 30,
        preexistingData: Data? = nil,
        writeOverride: ((Data, URL) throws -> Void)? = nil
    ) throws -> Harness {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xfinder-app-usage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("local-app-usage.json")
        if let preexistingData {
            try preexistingData.write(to: fileURL, options: .atomic)
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var now = initialDate ?? {
            var comps = DateComponents()
            comps.calendar = cal
            comps.timeZone = timeZone
            comps.year = 2026
            comps.month = 11
            comps.day = 26
            comps.hour = 10
            comps.minute = 0
            comps.second = 0
            return cal.date(from: comps)!
        }()
        var idleSeconds: TimeInterval = 0

        let suiteName = "com.xfinder.tests.appusage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let backend = FakeObserverBackend()
        let scheduler = FakeScheduler()

        let tracker = LocalAppUsageTracker(
            fileURL: fileURL,
            idleThresholdSeconds: idleThreshold,
            sampleIntervalSeconds: sampleInterval,
            maxSampleDeltaSeconds: maxSampleDelta,
            retentionDays: retentionDays,
            observerBackend: backend,
            scheduler: scheduler,
            nowProvider: { now },
            calendarProvider: { cal },
            idleSecondsProvider: { idleSeconds },
            writeData: writeOverride,
            defaults: defaults,
            defaultsKey: "test.appUsage.enabled"
        )

        return Harness(
            tracker: tracker,
            backend: backend,
            scheduler: scheduler,
            fileURL: fileURL,
            defaults: defaults,
            suiteName: suiteName,
            getNow: { now },
            setNow: { now = $0 },
            advance: { now = now.addingTimeInterval($0) },
            setIdle: { idleSeconds = $0 },
            setTimeZone: { tz in
                var next = Calendar(identifier: .gregorian)
                next.timeZone = tz
                cal = next
            }
        )
    }

    private func cleanup(_ h: Harness) {
        h.tracker.shutdown()
        h.defaults.removePersistentDomain(forName: h.suiteName)
        try? FileManager.default.removeItem(at: h.fileURL.deletingLastPathComponent())
    }

    // MARK: - Tests

    func testDefaultOptOutHoldsZeroObserversAndZeroTimers() throws {
        let h = try makeHarness()
        defer { cleanup(h) }

        XCTAssertFalse(h.tracker.isTrackingEnabled)
        XCTAssertFalse(h.backend.isAttached)
        XCTAssertFalse(h.scheduler.isScheduled)

        h.tracker.startIfEnabled()
        XCTAssertFalse(h.backend.isAttached)
        XCTAssertFalse(h.scheduler.isScheduled)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 0)
    }

    func testStartSwitchAndStopImmediatelyDetaches() throws {
        let h = try makeHarness()
        defer { cleanup(h) }

        let safari = LocalAppUsageRules.AppIdentity(appID: "com.apple.Safari", displayName: "Safari")
        let xcode = LocalAppUsageRules.AppIdentity(appID: "com.apple.dt.Xcode", displayName: "Xcode")
        h.backend.frontmostApp = safari

        h.tracker.startTracking()
        XCTAssertTrue(h.tracker.isTrackingEnabled)
        XCTAssertTrue(h.backend.isAttached)
        XCTAssertTrue(h.scheduler.isScheduled)

        h.advance(40)
        h.backend.frontmostApp = xcode
        h.backend.onAppActivate?(xcode)

        h.advance(25)
        h.tracker.stopTracking()

        XCTAssertFalse(h.tracker.isTrackingEnabled)
        XCTAssertFalse(h.backend.isAttached)
        XCTAssertFalse(h.scheduler.isScheduled)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 65)
        XCTAssertEqual(h.tracker.snapshot.todayApps.first?.appID, "com.apple.Safari")
        XCTAssertEqual(h.tracker.snapshot.todayApps.first?.seconds, 40)
        XCTAssertEqual(h.tracker.snapshot.todayApps.last?.appID, "com.apple.dt.Xcode")
        XCTAssertEqual(h.tracker.snapshot.todayApps.last?.seconds, 25)

        // Advance time while OFF: nothing accrues.
        h.advance(100)
        h.tracker.refreshForDisplay()
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 65)
    }

    func testPauseAndResumeNeverCreditPausedTime() throws {
        let h = try makeHarness()
        defer { cleanup(h) }

        let notes = LocalAppUsageRules.AppIdentity(appID: "com.apple.Notes", displayName: "Notes")
        h.backend.frontmostApp = notes

        h.tracker.startTracking()
        h.advance(30)
        h.tracker.pauseTracking()

        XCTAssertTrue(h.tracker.isTrackingEnabled)
        XCTAssertTrue(h.tracker.isPaused)
        XCTAssertFalse(h.backend.isAttached)
        XCTAssertFalse(h.scheduler.isScheduled)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 30)

        h.advance(180)
        h.tracker.resumeTracking()
        XCTAssertFalse(h.tracker.isPaused)
        XCTAssertTrue(h.backend.isAttached)
        XCTAssertTrue(h.scheduler.isScheduled)

        h.advance(20)
        h.scheduler.fire()
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 50)
    }

    func testIdleStopsAccrualAndResumesCleanly() throws {
        let h = try makeHarness(idleThreshold: 60, maxSampleDelta: 120)
        defer { cleanup(h) }

        let app = LocalAppUsageRules.AppIdentity(appID: "com.apple.Terminal", displayName: "Terminal")
        h.backend.frontmostApp = app

        h.tracker.startTracking()
        h.advance(20)
        h.setIdle(5)
        h.scheduler.fire()
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 20)
        XCTAssertFalse(h.tracker.isIdle)

        // 75s later, user has been idle for 65s -> 10s were active before idle.
        h.advance(75)
        h.setIdle(65)
        h.scheduler.fire()
        XCTAssertTrue(h.tracker.isIdle)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 30)

        // Still idle 100s later -> 0s added.
        h.advance(100)
        h.setIdle(165)
        h.scheduler.fire()
        XCTAssertTrue(h.tracker.isIdle)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 30)

        // User moves mouse (idle = 0): starts fresh anchor at now, does not credit idle gap.
        h.advance(50)
        h.setIdle(0)
        h.scheduler.fire()
        XCTAssertFalse(h.tracker.isIdle)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 30)

        h.advance(15)
        h.scheduler.fire()
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 45)
    }

    func testLockSessionResignAndSleepSuspendCollection() throws {
        let h = try makeHarness()
        defer { cleanup(h) }

        let app = LocalAppUsageRules.AppIdentity(appID: "com.apple.Finder", displayName: "Finder")
        h.backend.frontmostApp = app
        h.tracker.startTracking()

        // Screen lock
        h.advance(20)
        h.backend.onScreenLock?()
        XCTAssertTrue(h.tracker.isSuspended)
        XCTAssertFalse(h.scheduler.isScheduled)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 20)

        h.advance(500)
        h.backend.onScreenUnlock?()
        XCTAssertFalse(h.tracker.isSuspended)
        XCTAssertTrue(h.scheduler.isScheduled)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 20)

        // Sleep / Wake
        h.advance(15)
        h.backend.onWillSleep?()
        XCTAssertTrue(h.tracker.isSuspended)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 35)

        h.advance(3600)
        h.backend.onDidWake?()
        XCTAssertFalse(h.tracker.isSuspended)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 35)

        // Session resign / become active
        h.advance(10)
        h.backend.onSessionResign?()
        XCTAssertTrue(h.tracker.isSuspended)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 45)

        h.advance(200)
        h.backend.onSessionBecomeActive?()
        XCTAssertFalse(h.tracker.isSuspended)
        h.advance(5)
        h.scheduler.fire()
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 50)
    }

    func testMidnightRolloverAndBackwardClockJump() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.calendar = cal
        comps.timeZone = cal.timeZone
        comps.year = 2026
        comps.month = 11
        comps.day = 26
        comps.hour = 23
        comps.minute = 59
        comps.second = 40
        let start = cal.date(from: comps)!

        let h = try makeHarness(initialDate: start)
        defer { cleanup(h) }

        let app = LocalAppUsageRules.AppIdentity(appID: "com.apple.Safari", displayName: "Safari")
        h.backend.frontmostApp = app
        h.tracker.startTracking()

        // Cross midnight: 20s on Nov 26, 30s on Nov 27
        h.advance(50)
        h.scheduler.fire()

        XCTAssertEqual(h.tracker.snapshot.todayKey, "2026-11-27")
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 30)
        XCTAssertEqual(h.tracker.snapshot.sevenDayTotalSeconds, 50)

        // Clock jumps backward by 15 seconds (still on 2026-11-27 00:00:15) -> 0s added, anchor resets.
        h.advance(-15)
        h.scheduler.fire()
        XCTAssertEqual(h.tracker.snapshot.todayKey, "2026-11-27")
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 30)
        XCTAssertEqual(h.tracker.snapshot.sevenDayTotalSeconds, 50)

        // Subsequent forward tick from the reset anchor accrues normally.
        h.advance(10)
        h.scheduler.fire()
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 40)
        XCTAssertEqual(h.tracker.snapshot.sevenDayTotalSeconds, 60)
    }

    func testTimeZoneChangeFlushesAndSwitchesCalendarCleanly() throws {
        let h = try makeHarness(timeZone: TimeZone(secondsFromGMT: 0)!)
        defer { cleanup(h) }

        let app = LocalAppUsageRules.AppIdentity(appID: "com.apple.Mail", displayName: "Mail")
        h.backend.frontmostApp = app
        h.tracker.startTracking()

        h.advance(25)
        h.setTimeZone(TimeZone(secondsFromGMT: 7 * 3600)!)
        h.backend.onTimeZoneOrDayChange?()

        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 25)

        h.advance(15)
        h.scheduler.fire()
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 40)
    }

    func testMissingBundleIDRecordedSafely() throws {
        let h = try makeHarness()
        defer { cleanup(h) }

        let missing = LocalAppUsageRules.normalizeApp(bundleID: nil, localizedName: "Custom Helper")
        h.backend.frontmostApp = missing
        h.tracker.startTracking()

        h.advance(30)
        h.scheduler.fire()

        XCTAssertEqual(h.tracker.snapshot.todayApps.first?.appID, "unidentified:custom-helper")
        XCTAssertEqual(h.tracker.snapshot.todayApps.first?.displayName, "Custom Helper")
        XCTAssertEqual(h.tracker.snapshot.todayApps.first?.seconds, 30)
    }

    func testCorruptFilePreservesExistingBytesAndAllowsRetry() throws {
        let corrupt = Data("{ corrupted json".utf8)
        let h = try makeHarness(preexistingData: corrupt)
        defer { cleanup(h) }

        XCTAssertTrue(h.tracker.isReadBlocked)
        XCTAssertNotNil(h.tracker.readError)

        // Attempting to start or clear must NOT overwrite the existing file.
        h.tracker.startTracking()
        XCTAssertFalse(h.backend.isAttached)
        XCTAssertFalse(h.tracker.confirmClearHistory())
        XCTAssertEqual(try Data(contentsOf: h.fileURL), corrupt)

        // Replace file with valid JSON and retry -> unblocks and starts because user opted in.
        var validStore = LocalAppUsageRules.UsageStore()
        LocalAppUsageRules.record(
            seconds: 90,
            for: .init(appID: "com.apple.Safari", displayName: "Safari"),
            dayKey: "2026-11-26",
            into: &validStore
        )
        try LocalAppUsageRules.encodeStore(validStore).write(to: h.fileURL, options: .atomic)

        XCTAssertTrue(h.tracker.retryLoad())
        XCTAssertFalse(h.tracker.isReadBlocked)
        XCTAssertNil(h.tracker.readError)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 90)
        XCTAssertTrue(h.backend.isAttached)
    }

    func testWriteFailureSurfacesErrorAndRecovers() throws {
        var shouldFail = true
        let h = try makeHarness(writeOverride: { data, url in
            if shouldFail {
                throw NSError(domain: "TestDisk", code: 28, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
            }
            try data.write(to: url, options: .atomic)
        })
        defer { cleanup(h) }

        h.backend.frontmostApp = .init(appID: "com.apple.Safari", displayName: "Safari")
        h.tracker.startTracking()
        h.advance(20)
        h.scheduler.fire()

        XCTAssertNotNil(h.tracker.saveError)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 20)

        shouldFail = false
        h.advance(10)
        h.scheduler.fire()
        XCTAssertNil(h.tracker.saveError)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 30)
    }

    func testClearHistoryWithConfirmationNeverReAddsOldSegment() throws {
        let h = try makeHarness()
        defer { cleanup(h) }

        let safari = LocalAppUsageRules.AppIdentity(appID: "com.apple.Safari", displayName: "Safari")
        let xcode = LocalAppUsageRules.AppIdentity(appID: "com.apple.dt.Xcode", displayName: "Xcode")
        h.backend.frontmostApp = safari
        h.tracker.startTracking()

        // Accumulate 30s flushed + 45s still open in activeSegment.
        h.advance(30)
        h.scheduler.fire()
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 30)

        h.advance(45)
        h.tracker.requestClearHistory()
        XCTAssertTrue(h.tracker.confirmingClear)

        XCTAssertTrue(h.tracker.confirmClearHistory())
        XCTAssertFalse(h.tracker.confirmingClear)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 0)
        XCTAssertFalse(h.tracker.hasHistory)

        // Switch app 10s after clear: ONLY the 10s AFTER clear may be counted (never the 45s before clear).
        h.advance(10)
        h.backend.frontmostApp = xcode
        h.backend.onAppActivate?(xcode)

        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 10)
        XCTAssertEqual(h.tracker.snapshot.todayApps.first?.appID, "com.apple.Safari")
        XCTAssertEqual(h.tracker.snapshot.todayApps.first?.seconds, 10)
    }

    func testRapidToggleDoesNotLeakOrDoubleCount() throws {
        let h = try makeHarness()
        defer { cleanup(h) }

        let safari = LocalAppUsageRules.AppIdentity(appID: "com.apple.Safari", displayName: "Safari")
        h.backend.frontmostApp = safari

        for _ in 0..<5 {
            h.tracker.startTracking()
            h.advance(5)
            h.tracker.stopTracking()
        }

        XCTAssertFalse(h.tracker.isTrackingEnabled)
        XCTAssertFalse(h.backend.isAttached)
        XCTAssertFalse(h.scheduler.isScheduled)
        XCTAssertEqual(h.backend.attachCount, h.backend.detachCount)
        XCTAssertEqual(h.scheduler.scheduleCount, h.scheduler.cancelCount)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 25)
    }

    func testShutdownFlushesAndPreservesOptInForNextLaunch() throws {
        let h = try makeHarness()
        defer { cleanup(h) }

        h.backend.frontmostApp = .init(appID: "com.apple.Safari", displayName: "Safari")
        h.tracker.startTracking()
        h.advance(35)
        h.tracker.shutdown()

        XCTAssertTrue(h.tracker.isTrackingEnabled)
        XCTAssertFalse(h.backend.isAttached)
        XCTAssertFalse(h.scheduler.isScheduled)
        XCTAssertEqual(h.tracker.snapshot.todayTotalSeconds, 35)
        XCTAssertEqual(h.defaults.object(forKey: "test.appUsage.enabled") as? Bool, true)
    }
}
