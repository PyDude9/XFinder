import XCTest
import Foundation

final class AlertRulesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private var th: AlertRules.Thresholds { var t = AlertRules.Thresholds(); t.sustainedSeconds = 60; t.cooldownSeconds = 600; return t }
    private func cpu(_ p: Double) -> AlertRules.Sample { .init(cpuPercent: p) }

    func testASpikeDoesNotFireButASustainedConditionDoes() {
        var e = AlertRules.Engine()
        XCTAssertTrue(e.step(sample: cpu(99), thresholds: th, at: at(0)).isEmpty, "first sight: start the clock, do not fire")
        XCTAssertTrue(e.step(sample: cpu(99), thresholds: th, at: at(30)).isEmpty, "30 s < 60 s sustained")
        XCTAssertTrue(e.step(sample: cpu(20), thresholds: th, at: at(45)).isEmpty, "dropped: the clock resets")
        XCTAssertTrue(e.step(sample: cpu(99), thresholds: th, at: at(60)).isEmpty, "a NEW stretch starts here")
        let fired = e.step(sample: cpu(99), thresholds: th, at: at(120))
        XCTAssertEqual(fired.map(\.kind), [.cpu])
        XCTAssertEqual(fired.first?.value, 99)
    }

    func testFiresOnceThenNeedsClearingAndCooldown() {
        var e = AlertRules.Engine()
        _ = e.step(sample: cpu(99), thresholds: th, at: at(0))
        XCTAssertEqual(e.step(sample: cpu(99), thresholds: th, at: at(60)).count, 1)
        // Still high: must NOT fire again, on any later tick.
        for s in stride(from: 90.0, through: 2000, by: 30) {
            XCTAssertTrue(e.step(sample: cpu(99), thresholds: th, at: at(s)).isEmpty, "re-fired at \(s)s while still high")
        }
        // Hovering just under the threshold is not "cleared" (hysteresis margin is 10).
        XCTAssertTrue(e.step(sample: cpu(80), thresholds: th, at: at(2030)).isEmpty)
        _ = e.step(sample: cpu(99), thresholds: th, at: at(2060))
        XCTAssertTrue(e.step(sample: cpu(99), thresholds: th, at: at(2200)).isEmpty, "never cleared ⇒ still armed off")
        // Clear properly, then high again for the sustained window ⇒ fires (cooldown long passed).
        _ = e.step(sample: cpu(10), thresholds: th, at: at(2230))
        _ = e.step(sample: cpu(99), thresholds: th, at: at(2260))
        XCTAssertEqual(e.step(sample: cpu(99), thresholds: th, at: at(2320)).count, 1)
    }

    func testCooldownBlocksARefireEvenAfterClearing() {
        var e = AlertRules.Engine()
        _ = e.step(sample: cpu(99), thresholds: th, at: at(0))
        XCTAssertEqual(e.step(sample: cpu(99), thresholds: th, at: at(60)).count, 1)
        _ = e.step(sample: cpu(10), thresholds: th, at: at(90))      // cleared
        _ = e.step(sample: cpu(99), thresholds: th, at: at(120))     // met again
        XCTAssertTrue(e.step(sample: cpu(99), thresholds: th, at: at(180)).isEmpty, "sustained again, but inside the 600 s cooldown")
        XCTAssertEqual(e.step(sample: cpu(99), thresholds: th, at: at(661)).count, 1, "cooldown over ⇒ fires")
    }

    func testUnavailableReadingsAreSkippedNotTreatedAsZero() {
        var e = AlertRules.Engine()
        let empty = AlertRules.Sample()   // everything nil — e.g. no battery, no sensors
        _ = e.step(sample: empty, thresholds: th, at: at(0))
        XCTAssertTrue(e.step(sample: empty, thresholds: th, at: at(600)).isEmpty,
                      "nil disk free / nil battery must not read as 0 % and fire")
    }

    func testDisabledKindsNeverFire() {
        var t = th; t.enabled = [.battery]; t.sustainedSeconds = 0
        var e = AlertRules.Engine()
        XCTAssertTrue(e.step(sample: cpu(100), thresholds: t, at: at(0)).isEmpty)
    }

    func testEachRuleDirection() {
        var t = th; t.sustainedSeconds = 0
        var e = AlertRules.Engine()
        let bad = AlertRules.Sample(cpuPercent: 90, memoryPressureLevel: 4, diskFreePercent: 5, socTemperature: 100, batteryPercent: 10, isCharging: false)
        XCTAssertEqual(Set(e.step(sample: bad, thresholds: t, at: at(0)).map(\.kind)), Set(AlertRules.Kind.allCases))
        var e2 = AlertRules.Engine()
        let fine = AlertRules.Sample(cpuPercent: 10, memoryPressureLevel: 1, diskFreePercent: 60, socTemperature: 50, batteryPercent: 90)
        XCTAssertTrue(e2.step(sample: fine, thresholds: t, at: at(0)).isEmpty)
    }

    func testLowBatteryWhileChargingIsNotAnAlert() {
        var t = th; t.sustainedSeconds = 0
        var e = AlertRules.Engine()
        XCTAssertTrue(e.step(sample: .init(batteryPercent: 5, isCharging: true), thresholds: t, at: at(0)).isEmpty)
        XCTAssertEqual(e.step(sample: .init(batteryPercent: 5, isCharging: false), thresholds: t, at: at(30)).map(\.kind), [.battery])
    }

    func testMemoryPressureLevelThreshold() {
        var t = th; t.sustainedSeconds = 0; t.memoryPressureLevel = 4
        var e = AlertRules.Engine()
        XCTAssertTrue(e.step(sample: .init(memoryPressureLevel: 2), thresholds: t, at: at(0)).isEmpty, "warning does not meet a 'critical' threshold")
        XCTAssertEqual(e.step(sample: .init(memoryPressureLevel: 4), thresholds: t, at: at(30)).count, 1)
        t.memoryPressureLevel = 2
        var e2 = AlertRules.Engine()
        XCTAssertEqual(e2.step(sample: .init(memoryPressureLevel: 2), thresholds: t, at: at(0)).count, 1)
    }

    func testValidationClampsHandEditedValues() {
        var t = AlertRules.Thresholds()
        t.cpuPercent = 500; t.diskFreePercent = -3; t.cooldownSeconds = 1; t.memoryPressureLevel = 3; t.sustainedSeconds = -9
        let v = t.validated()
        XCTAssertEqual(v.cpuPercent, 100); XCTAssertEqual(v.diskFreePercent, 1)
        XCTAssertEqual(v.cooldownSeconds, 60, "a 1 s cooldown would be spam")
        XCTAssertEqual(v.memoryPressureLevel, 4); XCTAssertEqual(v.sustainedSeconds, 0)
        XCTAssertEqual(AlertRules.Thresholds().validated(), AlertRules.Thresholds(), "defaults are already valid")
    }

    func testThresholdsRoundTripThroughJSON() throws {
        var t = AlertRules.Thresholds(); t.enabled = [.cpu, .battery]; t.cpuPercent = 70
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(AlertRules.Thresholds.self, from: data), t)
    }

    func testEveryKindHasTranslatedTextAndBody() throws {
        let store = try L10nFixture.load()
        for k in AlertRules.Kind.allCases {
            XCTAssertNotNil(store.entries[k.titleKey], "not in store: \(k.titleKey)")
            let (bodyKey, value) = AlertRules.bodyKeyAndValue(for: .init(kind: k, value: 42, at: t0))
            XCTAssertNotNil(store.entries[bodyKey], "not in store: \(bodyKey)")
            XCTAssertFalse(value.isEmpty)
        }
    }
}
