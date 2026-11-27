import Foundation
import XCTest

final class LocalAppUsageRulesTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeDate(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        calendar: Calendar
    ) -> Date {
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return calendar.date(from: comps)!
    }

    func testNormalizeAppWithBundleIDAndSanitization() {
        let app = LocalAppUsageRules.normalizeApp(
            bundleID: "  com.apple.Safari\n",
            localizedName: "Safari\t\nBrowser  "
        )
        XCTAssertEqual(app.appID, "com.apple.Safari")
        XCTAssertEqual(app.displayName, "Safari Browser")
    }

    func testNormalizeAppMissingBundleIDFallsBackDeterministically() {
        let a = LocalAppUsageRules.normalizeApp(bundleID: nil, localizedName: "My CLI Tool")
        let b = LocalAppUsageRules.normalizeApp(bundleID: "   ", localizedName: "My CLI Tool")
        XCTAssertEqual(a.appID, "unidentified:my-cli-tool")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.displayName, "My CLI Tool")

        let unknown = LocalAppUsageRules.normalizeApp(bundleID: nil, localizedName: nil)
        XCTAssertEqual(unknown.appID, LocalAppUsageRules.unknownAppID)
        XCTAssertEqual(unknown.displayName, "")
    }

    func testNormalizeAppTruncatesExcessiveDisplayName() {
        let longName = String(repeating: "A", count: 200)
        let app = LocalAppUsageRules.normalizeApp(bundleID: "com.example.long", localizedName: longName)
        XCTAssertEqual(app.displayName.count, LocalAppUsageRules.maxDisplayNameLength)
    }

    func testDayKeyRoundTripAndRejectsInvalidCalendarDates() {
        let cal = utcCalendar()
        let date = makeDate(2026, 11, 26, 14, 30, 0, calendar: cal)
        let key = LocalAppUsageRules.dayKey(for: date, calendar: cal)
        XCTAssertEqual(key, "2026-11-26")

        let parsed = LocalAppUsageRules.date(fromDayKey: key, calendar: cal)
        XCTAssertEqual(parsed, makeDate(2026, 11, 26, 0, 0, 0, calendar: cal))

        XCTAssertNil(LocalAppUsageRules.date(fromDayKey: "2026-02-31", calendar: cal))
        XCTAssertNil(LocalAppUsageRules.date(fromDayKey: "not-a-date", calendar: cal))
    }

    func testEvaluateIntervalHandlesBackwardClockJump() {
        let cal = utcCalendar()
        let start = makeDate(2026, 11, 26, 10, 0, 30, calendar: cal)
        let end = makeDate(2026, 11, 26, 10, 0, 10, calendar: cal)
        let result = LocalAppUsageRules.evaluateInterval(from: start, to: end, idleSeconds: 0)
        XCTAssertNil(result.credit)
        XCTAssertFalse(result.isNowIdle)
    }

    func testEvaluateIntervalCapsHugeForwardJump() {
        let cal = utcCalendar()
        let start = makeDate(2026, 11, 26, 10, 0, 0, calendar: cal)
        let end = makeDate(2026, 11, 26, 12, 0, 0, calendar: cal)
        let result = LocalAppUsageRules.evaluateInterval(
            from: start,
            to: end,
            idleSeconds: 5,
            idleThreshold: 300,
            maxSampleDelta: 120
        )
        XCTAssertFalse(result.isNowIdle)
        XCTAssertEqual(result.credit?.start, start)
        XCTAssertEqual(result.credit?.end, start.addingTimeInterval(120))
    }

    func testEvaluateIntervalIdleAttribution() {
        let cal = utcCalendar()
        let start = makeDate(2026, 11, 26, 10, 0, 0, calendar: cal)
        let end = makeDate(2026, 11, 26, 10, 6, 0, calendar: cal) // 360s elapsed
        // User became idle 320s before `end` -> 40s active before idle started.
        let result = LocalAppUsageRules.evaluateInterval(
            from: start,
            to: end,
            idleSeconds: 320,
            idleThreshold: 300,
            maxSampleDelta: 120
        )
        XCTAssertTrue(result.isNowIdle)
        XCTAssertEqual(result.credit?.start, start)
        XCTAssertEqual(result.credit?.end, start.addingTimeInterval(40))

        // If idle started before `start`, nothing is credited.
        let allIdle = LocalAppUsageRules.evaluateInterval(
            from: start,
            to: end,
            idleSeconds: 400,
            idleThreshold: 300,
            maxSampleDelta: 120
        )
        XCTAssertTrue(allIdle.isNowIdle)
        XCTAssertNil(allIdle.credit)
    }

    func testSplitAndRecordIntervalAcrossMidnight() {
        let cal = utcCalendar()
        let start = makeDate(2026, 11, 26, 23, 59, 40, calendar: cal)
        let end = makeDate(2026, 11, 27, 0, 0, 25, calendar: cal)
        let app = LocalAppUsageRules.AppIdentity(appID: "com.apple.dt.Xcode", displayName: "Xcode")

        var store = LocalAppUsageRules.UsageStore()
        var carry: [String: Double] = [:]
        let added = LocalAppUsageRules.recordInterval(
            from: start,
            to: end,
            for: app,
            calendar: cal,
            into: &store,
            fractionalCarry: &carry
        )

        XCTAssertEqual(added, 45)
        XCTAssertEqual(store.days["2026-11-26"]?.first?.seconds, 20)
        XCTAssertEqual(store.days["2026-11-27"]?.first?.seconds, 25)
    }

    func testPruneRetentionKeepsThirtyDaysInclusive() {
        let cal = utcCalendar()
        let today = makeDate(2026, 11, 30, 12, 0, 0, calendar: cal)
        let app = LocalAppUsageRules.AppIdentity(appID: "com.apple.Safari", displayName: "Safari")

        var store = LocalAppUsageRules.UsageStore()
        // Day 0 (today): 2026-11-30 -> kept
        // Day -29 (30th day): 2026-11-01 -> kept
        // Day -30 (31st day): 2026-10-31 -> pruned
        LocalAppUsageRules.record(seconds: 100, for: app, dayKey: "2026-11-30", into: &store)
        LocalAppUsageRules.record(seconds: 200, for: app, dayKey: "2026-11-01", into: &store)
        LocalAppUsageRules.record(seconds: 300, for: app, dayKey: "2026-10-31", into: &store)
        LocalAppUsageRules.record(seconds: 50, for: app, dayKey: "invalid-key", into: &store)

        LocalAppUsageRules.pruneRetention(in: &store, referenceDate: today, calendar: cal, retentionDays: 30)

        XCTAssertNotNil(store.days["2026-11-30"])
        XCTAssertNotNil(store.days["2026-11-01"])
        XCTAssertNil(store.days["2026-10-31"])
        XCTAssertNil(store.days["invalid-key"])
    }

    func testRetentionCapsBucketCountAfterTimezoneMovesWest() {
        let calendar = utcCalendar()
        let today = makeDate(2026, 11, 30, 12, 0, 0, calendar: calendar)
        let app = LocalAppUsageRules.AppIdentity(appID: "com.apple.Safari", displayName: "Safari")
        var store = LocalAppUsageRules.UsageStore()
        for key in ["2026-11-29", "2026-11-30", "2026-12-01"] {
            LocalAppUsageRules.record(seconds: 60, for: app, dayKey: key, into: &store)
        }

        LocalAppUsageRules.pruneRetention(in: &store, referenceDate: today, calendar: calendar, retentionDays: 2)

        XCTAssertEqual(Set(store.days.keys), ["2026-11-30", "2026-12-01"])
    }

    func testEncodeDecodeStoreAndMinimalPrivacySchema() throws {
        var store = LocalAppUsageRules.UsageStore()
        let app = LocalAppUsageRules.AppIdentity(appID: "com.apple.Terminal", displayName: "Terminal")
        LocalAppUsageRules.record(seconds: 420, for: app, dayKey: "2026-11-26", into: &store)

        let data = try LocalAppUsageRules.encodeStore(store)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "days"])

        let days = try XCTUnwrap(json["days"] as? [String: [[String: Any]]])
        let entry = try XCTUnwrap(days["2026-11-26"]?.first)
        XCTAssertEqual(Set(entry.keys), ["appID", "displayName", "seconds"])

        let decoded = try LocalAppUsageRules.decodeStore(from: data)
        XCTAssertEqual(decoded, store)

        XCTAssertThrowsError(try LocalAppUsageRules.decodeStore(from: Data("not json".utf8))) { err in
            XCTAssertEqual(err as? LocalAppUsageRules.StoreError, .malformedData)
        }

        let badVersion = Data(#"{"version":99,"days":{}}"#.utf8)
        XCTAssertThrowsError(try LocalAppUsageRules.decodeStore(from: badVersion)) { err in
            XCTAssertEqual(err as? LocalAppUsageRules.StoreError, .unsupportedVersion(99))
        }
    }

    func testDashboardSnapshotBuildsSevenDaysAndSortedApps() {
        let cal = utcCalendar()
        let today = makeDate(2026, 11, 26, 15, 0, 0, calendar: cal)
        var store = LocalAppUsageRules.UsageStore()
        LocalAppUsageRules.record(
            seconds: 120,
            for: .init(appID: "com.a", displayName: "Alpha"),
            dayKey: "2026-11-26",
            into: &store
        )
        LocalAppUsageRules.record(
            seconds: 360,
            for: .init(appID: "com.b", displayName: "Beta"),
            dayKey: "2026-11-26",
            into: &store
        )
        LocalAppUsageRules.record(
            seconds: 500,
            for: .init(appID: "com.a", displayName: "Alpha"),
            dayKey: "2026-11-20",
            into: &store
        )

        let snap = LocalAppUsageRules.dashboardSnapshot(from: store, referenceDate: today, calendar: cal)
        XCTAssertEqual(snap.todayKey, "2026-11-26")
        XCTAssertEqual(snap.todayTotalSeconds, 480)
        XCTAssertEqual(snap.sevenDayTotalSeconds, 980)
        XCTAssertEqual(snap.lastSevenDays.count, 7)
        XCTAssertEqual(snap.lastSevenDays.first?.dayKey, "2026-11-20")
        XCTAssertEqual(snap.lastSevenDays.last?.dayKey, "2026-11-26")
        XCTAssertEqual(snap.lastSevenDays.last?.isToday, true)
        XCTAssertEqual(snap.todayApps.map(\.appID), ["com.b", "com.a"])
        XCTAssertEqual(snap.todayApps.first?.share ?? 0, 0.75, accuracy: 0.0001)
    }

    func testDurationParts() {
        XCTAssertEqual(LocalAppUsageRules.durationParts(seconds: -5), .init(hours: 0, minutes: 0, seconds: 0))
        XCTAssertEqual(LocalAppUsageRules.durationParts(seconds: 45), .init(hours: 0, minutes: 0, seconds: 45))
        XCTAssertEqual(LocalAppUsageRules.durationParts(seconds: 3665), .init(hours: 1, minutes: 1, seconds: 5))
    }
}
