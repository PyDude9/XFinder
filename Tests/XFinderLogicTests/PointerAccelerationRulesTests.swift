import XCTest

final class PointerAccelerationRulesTests: XCTestCase {
    func testEnablingFromDefaultSavesDefaultAndWritesNegativeOne() {
        let t = PointerAccelerationRules.transition(enable: true, currentScaling: nil, savedPrevious: nil)
        XCTAssertEqual(t.targetScaling, PointerAccelerationRules.disabledScaling)
        XCTAssertEqual(t.updatedSavedPrevious, PointerAccelerationRules.defaultScaling)
        XCTAssertTrue(t.needsUpdate)
    }

    func testEnablingWhenAlreadyDisabledSkipsUpdateAndPreserves() {
        let t = PointerAccelerationRules.transition(enable: true, currentScaling: -1.0, savedPrevious: nil)
        XCTAssertEqual(t.targetScaling, -1.0)
        XCTAssertEqual(t.updatedSavedPrevious, -1.0)
        XCTAssertFalse(t.needsUpdate)
    }

    func testEnablingPreservesExistingSavedPrevious() {
        let t = PointerAccelerationRules.transition(enable: true, currentScaling: -1.0, savedPrevious: 1.5)
        XCTAssertEqual(t.targetScaling, -1.0)
        XCTAssertEqual(t.updatedSavedPrevious, 1.5)
        XCTAssertFalse(t.needsUpdate)
    }

    func testDisablingRestoresSavedValueAndClearsSavedKey() {
        let t = PointerAccelerationRules.transition(enable: false, currentScaling: -1.0, savedPrevious: 1.5)
        XCTAssertEqual(t.targetScaling, 1.5)
        XCTAssertNil(t.updatedSavedPrevious)
        XCTAssertTrue(t.needsUpdate)
    }

    func testDisablingWithoutSavedValueDefaultsToStandardScaling() {
        let t = PointerAccelerationRules.transition(enable: false, currentScaling: -1.0, savedPrevious: nil)
        XCTAssertEqual(t.targetScaling, PointerAccelerationRules.defaultScaling)
        XCTAssertNil(t.updatedSavedPrevious)
        XCTAssertTrue(t.needsUpdate)
    }
}
