import XCTest

/// XF-T27 — Chống ngủ (resume, battery) and Lau bàn phím (Esc counter, minutes).
final class CaffeineRulesTests: XCTestCase {
    typealias C = CaffeineRules
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testAHoldIsStoredAndResumedForWhatIsLeft() {
        let stored = C.storedUntil(start: t0, minutes: 60)
        XCTAssertEqual(stored, t0.timeIntervalSince1970 + 3600)
        XCTAssertEqual(C.resume(stored: stored, now: t0.addingTimeInterval(40 * 60)), .minutesLeft(20))
        XCTAssertEqual(C.resume(stored: stored, now: t0.addingTimeInterval(3_560)), .none, "under a minute left: not restarted")
        XCTAssertEqual(C.resume(stored: stored, now: t0.addingTimeInterval(4_000)), .none, "expired while the app was closed")
        XCTAssertEqual(C.resume(stored: C.storedUntil(start: t0, minutes: nil), now: t0.addingTimeInterval(1e6)), .indefinite)
        XCTAssertEqual(C.resume(stored: C.off, now: t0), .none)
    }

    func testLowBatteryEndsAHoldOnlyOnBatteryPower() {
        XCTAssertTrue(C.shouldStopForBattery(percent: 10, onBattery: true))
        XCTAssertFalse(C.shouldStopForBattery(percent: 11, onBattery: true))
        XCTAssertFalse(C.shouldStopForBattery(percent: 5, onBattery: false), "charging / on AC: keep going")
        XCTAssertFalse(C.shouldStopForBattery(percent: nil, onBattery: true), "no battery (a desktop): keep going")
    }

    /// A UPS is a power source too; the Mac's own battery is the one that counts.
    func testTheInternalBatteryIsChosenOverAUPS() {
        let ups: [String: Any] = ["Type": "UPS", "Current Capacity": 90, "Max Capacity": 100, "Power Source State": "Battery Power"]
        let mac: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 8, "Max Capacity": 100, "Power Source State": "Battery Power"]
        let b = C.internalBattery([ups, mac])
        XCTAssertEqual(b?.percent, 8); XCTAssertEqual(b?.onBattery, true)
        XCTAssertNil(C.internalBattery([ups]))
        var ac = mac; ac["Power Source State"] = "AC Power"
        XCTAssertEqual(C.internalBattery([ac])?.onBattery, false)
    }

    func testEscFiveTimesWithinThreeSecondsUnlocks() {
        var e = C.EscCounter()
        for i in 0..<4 { XCTAssertFalse(e.press(isEscape: true, at: Double(i) * 0.5)) }
        XCTAssertTrue(e.press(isEscape: true, at: 2.0))
        var slow = C.EscCounter()
        for i in 0..<5 { XCTAssertFalse(slow.press(isEscape: true, at: Double(i) * 0.9), "presses spread over 3.6 s") }
        var mixed = C.EscCounter()
        for i in 0..<4 { _ = mixed.press(isEscape: true, at: Double(i) * 0.1) }
        XCTAssertFalse(mixed.press(isEscape: false, at: 0.5), "another key resets the count")
        XCTAssertFalse(mixed.press(isEscape: true, at: 0.6))
    }

    func testCleaningMinutesAreClamped() {
        XCTAssertEqual(C.clampCleaning(0), 1); XCTAssertEqual(C.clampCleaning(9), 5); XCTAssertEqual(C.clampCleaning(3), 3)
        XCTAssertEqual(C.defaultCleaningMinutes, 2)
    }
}
