import XCTest

/// XF-T32 W0 §D — dispatch of relief plans to registered caches.
@MainActor final class MemoryPressureReliefTests: XCTestCase {
    func testRelieversRunInRegistrationOrderWithThePlanOfTheLevel() {
        let relief: MemoryPressureRelief = MemoryPressureRelief()
        var calls: [String] = []
        var plans: [PressureRules.Plan] = []
        relief.register("icons") { plan in calls.append("icons"); plans.append(plan) }
        relief.register("thumbs") { plan in calls.append("thumbs"); plans.append(plan) }
        relief.simulate(.warning)
        XCTAssertEqual(calls, ["icons", "thumbs"])
        XCTAssertEqual(plans, [PressureRules.warningPlan, PressureRules.warningPlan])
        relief.simulate(.critical)
        XCTAssertEqual(plans.suffix(2), [PressureRules.criticalPlan, PressureRules.criticalPlan])
        XCTAssertEqual(relief.lastRelief?.level, .critical)
    }

    func testReRegisteringReplacesInPlaceAndKeepsOrder() {
        let relief: MemoryPressureRelief = MemoryPressureRelief()
        var calls: [String] = []
        relief.register("a") { _ in calls.append("a1") }
        relief.register("b") { _ in calls.append("b") }
        relief.register("a") { _ in calls.append("a2") }
        relief.simulate(.warning)
        XCTAssertEqual(calls, ["a2", "b"], "replaced, not appended, and still first")
    }

    func testRelieverRegisteringAnotherDuringReliefDoesNotRunItThisRound() {
        let relief: MemoryPressureRelief = MemoryPressureRelief()
        var calls: [String] = []
        relief.register("first") { _ in
            calls.append("first")
            relief.register("late") { _ in calls.append("late") }
        }
        relief.simulate(.warning)
        XCTAssertEqual(calls, ["first"])
        relief.simulate(.warning)
        XCTAssertEqual(calls, ["first", "first", "late"])
    }

    func testNoRelieversStillRecordsTheRelief() {
        let relief: MemoryPressureRelief = MemoryPressureRelief()
        XCTAssertNil(relief.lastRelief)
        relief.simulate(.warning)
        XCTAssertEqual(relief.lastRelief?.level, .warning)
    }

    func testStartIsIdempotentAndStopCancels() {
        let relief: MemoryPressureRelief = MemoryPressureRelief()
        XCTAssertFalse(relief.isRunning)
        relief.start(); relief.start()
        XCTAssertTrue(relief.isRunning)
        relief.stop()
        XCTAssertFalse(relief.isRunning)
        relief.start()
        XCTAssertTrue(relief.isRunning)
        relief.stop()
    }
}
