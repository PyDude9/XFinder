import XCTest

/// XF-T32 W0 §C — main-thread hitch rules.
final class HitchRulesTests: XCTestCase {
    private let base: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testContractConstants() {
        XCTAssertEqual(HitchRules.pingInterval, 0.1)
        XCTAssertEqual(HitchRules.threshold, 0.25)
        XCTAssertEqual(HitchRules.maxSamplesPerHour, 3)
        XCTAssertEqual(HitchRules.sleepWakeCutoff, 30)
        XCTAssertLessThan(HitchRules.pingInterval, HitchRules.threshold)
    }

    func testThresholdBoundary() {
        XCTAssertFalse(HitchRules.isHitch(latency: 0))
        XCTAssertFalse(HitchRules.isHitch(latency: 0.249))
        XCTAssertTrue(HitchRules.isHitch(latency: 0.25))
        XCTAssertTrue(HitchRules.isHitch(latency: 3.3))
    }

    func testSleepWakeLatencyIsIgnored() {
        XCTAssertTrue(HitchRules.isHitch(latency: 30))
        XCTAssertFalse(HitchRules.isHitch(latency: 30.001))
        XCTAssertFalse(HitchRules.isHitch(latency: 8 * 3600))
    }

    func testGarbageLatenciesAreNotHitches() {
        XCTAssertFalse(HitchRules.isHitch(latency: -1))
        XCTAssertFalse(HitchRules.isHitch(latency: .nan))
        XCTAssertFalse(HitchRules.isHitch(latency: .infinity))
        XCTAssertFalse(HitchRules.isHitch(latency: -.infinity))
    }

    func testSamplingAllowsThreePerRollingHour() {
        XCTAssertTrue(HitchRules.shouldSample(now: base, previousSamples: []))
        let two: [Date] = [base.addingTimeInterval(-600), base.addingTimeInterval(-60)]
        XCTAssertTrue(HitchRules.shouldSample(now: base, previousSamples: two))
        let three: [Date] = two + [base.addingTimeInterval(-1)]
        XCTAssertFalse(HitchRules.shouldSample(now: base, previousSamples: three))
        XCTAssertFalse(HitchRules.shouldSample(now: base, previousSamples: three + [base]))
    }

    func testSamplesOlderThanAnHourDoNotCount() {
        let old: [Date] = [
            base.addingTimeInterval(-3600),
            base.addingTimeInterval(-3601),
            base.addingTimeInterval(-7200),
            base.addingTimeInterval(-10),
        ]
        XCTAssertTrue(HitchRules.shouldSample(now: base, previousSamples: old))
        let justInside: [Date] = [-3599.0, -3000.0, -10.0].map { (offset: Double) -> Date in base.addingTimeInterval(offset) }
        XCTAssertFalse(HitchRules.shouldSample(now: base, previousSamples: justInside))
    }

    func testClockChangeNeverBlocksForever() {
        // Clock moved back a minute: the "future" samples still count.
        let nearFuture: [Date] = [60.0, 120.0, 180.0].map { (offset: Double) -> Date in base.addingTimeInterval(offset) }
        XCTAssertFalse(HitchRules.shouldSample(now: base, previousSamples: nearFuture))
        // Clock moved back a day: those samples are ignored.
        let farFuture: [Date] = [86_400.0, 86_401.0, 86_402.0].map { (offset: Double) -> Date in base.addingTimeInterval(offset) }
        XCTAssertTrue(HitchRules.shouldSample(now: base, previousSamples: farFuture))
    }

    func testPrunedKeepsTheMostRecentInOrder() {
        let hitches: [HitchRules.Hitch] = (0..<60).map { (index: Int) -> HitchRules.Hitch in
            HitchRules.Hitch(at: base.addingTimeInterval(TimeInterval(index)), latency: 0.3)
        }
        let kept: [HitchRules.Hitch] = HitchRules.pruned(hitches)
        XCTAssertEqual(kept.count, 50)
        XCTAssertEqual(kept.first?.at, base.addingTimeInterval(10))
        XCTAssertEqual(kept.last?.at, base.addingTimeInterval(59))
        XCTAssertEqual(HitchRules.pruned(hitches, keep: 3).map(\.at),
                       [57.0, 58.0, 59.0].map { (offset: Double) -> Date in base.addingTimeInterval(offset) })
    }

    func testPrunedSortsAndHandlesSmallOrEmptyInput() {
        let late: HitchRules.Hitch = HitchRules.Hitch(at: base.addingTimeInterval(5), latency: 1)
        let early: HitchRules.Hitch = HitchRules.Hitch(at: base, latency: 2)
        let tieA: HitchRules.Hitch = HitchRules.Hitch(at: base.addingTimeInterval(5), latency: 3)
        XCTAssertEqual(HitchRules.pruned([late, early, tieA]), [early, late, tieA])
        XCTAssertEqual(HitchRules.pruned([late, early], keep: 1), [late])
        XCTAssertEqual(HitchRules.pruned([], keep: 50), [])
        XCTAssertEqual(HitchRules.pruned([late], keep: 0), [])
        XCTAssertEqual(HitchRules.pruned([late], keep: -4), [])
    }
}
