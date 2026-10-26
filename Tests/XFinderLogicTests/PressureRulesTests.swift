import Dispatch
import XCTest

/// XF-T32 W0 §D — memory-pressure levels and relief plans.
final class PressureRulesTests: XCTestCase {
    func testRawBitsMatchDispatch() {
        XCTAssertEqual(PressureRules.DispatchBit.normal, DispatchSource.MemoryPressureEvent.normal.rawValue)
        XCTAssertEqual(PressureRules.DispatchBit.warning, DispatchSource.MemoryPressureEvent.warning.rawValue)
        XCTAssertEqual(PressureRules.DispatchBit.critical, DispatchSource.MemoryPressureEvent.critical.rawValue)
    }

    func testNormalZeroAndUnknownBitsAreNil() {
        XCTAssertNil(PressureRules.level(fromDispatchMask: DispatchSource.MemoryPressureEvent.normal.rawValue))
        XCTAssertNil(PressureRules.level(fromDispatchMask: 0))
        XCTAssertNil(PressureRules.level(fromDispatchMask: 0x8))
        XCTAssertNil(PressureRules.level(fromDispatchMask: 0x1 | 0x8))
    }

    func testSingleBits() {
        XCTAssertEqual(PressureRules.level(fromDispatchMask: DispatchSource.MemoryPressureEvent.warning.rawValue), .warning)
        XCTAssertEqual(PressureRules.level(fromDispatchMask: DispatchSource.MemoryPressureEvent.critical.rawValue), .critical)
    }

    func testCombinedMasksPickMostSevere() {
        let all: DispatchSource.MemoryPressureEvent = .all
        XCTAssertEqual(PressureRules.level(fromDispatchMask: all.rawValue), .critical)
        XCTAssertEqual(PressureRules.level(fromDispatchMask: 0x2 | 0x4), .critical)
        XCTAssertEqual(PressureRules.level(fromDispatchMask: 0x1 | 0x4), .critical)
        XCTAssertEqual(PressureRules.level(fromDispatchMask: 0x1 | 0x2), .warning)
        XCTAssertEqual(PressureRules.level(fromDispatchMask: 0x2 | 0x8), .warning)
    }

    func testWarningPlan() {
        let plan: PressureRules.Plan = PressureRules.plan(for: .warning)
        XCTAssertEqual(plan.keepFraction, 0.5)
        XCTAssertTrue(plan.dropIdleSessions)
        XCTAssertFalse(plan.dropPathIcons)
    }

    func testCriticalPlan() {
        let plan: PressureRules.Plan = PressureRules.plan(for: .critical)
        XCTAssertEqual(plan.keepFraction, 0)
        XCTAssertTrue(plan.dropIdleSessions)
        XCTAssertTrue(plan.dropPathIcons)
        XCTAssertNotEqual(plan, PressureRules.plan(for: .warning))
    }

    func testKeepCount() {
        let warning: PressureRules.Plan = PressureRules.plan(for: .warning)
        let critical: PressureRules.Plan = PressureRules.plan(for: .critical)
        XCTAssertEqual(PressureRules.keepCount(of: 40, plan: warning), 20)
        XCTAssertEqual(PressureRules.keepCount(of: 7, plan: warning), 3)
        XCTAssertEqual(PressureRules.keepCount(of: 1, plan: warning), 0)
        XCTAssertEqual(PressureRules.keepCount(of: 40, plan: critical), 0)
        XCTAssertEqual(PressureRules.keepCount(of: 0, plan: warning), 0)
        XCTAssertEqual(PressureRules.keepCount(of: -5, plan: warning), 0)
    }

    func testKeepCountClampsBadFractions() {
        let over: PressureRules.Plan = PressureRules.Plan(keepFraction: 2, dropIdleSessions: false, dropPathIcons: false)
        let under: PressureRules.Plan = PressureRules.Plan(keepFraction: -1, dropIdleSessions: false, dropPathIcons: false)
        let nan: PressureRules.Plan = PressureRules.Plan(keepFraction: .nan, dropIdleSessions: false, dropPathIcons: false)
        XCTAssertEqual(PressureRules.keepCount(of: 10, plan: over), 10)
        XCTAssertEqual(PressureRules.keepCount(of: 10, plan: under), 0)
        XCTAssertEqual(PressureRules.keepCount(of: 10, plan: nan), 0)
        XCTAssertEqual(PressureRules.keepCount(of: Int.max, plan: over), Int.max)
    }
}
