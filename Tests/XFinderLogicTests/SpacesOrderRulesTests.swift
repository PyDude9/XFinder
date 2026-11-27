import XCTest

final class SpacesOrderRulesTests: XCTestCase {
    func testEnablingFromDefaultTrueLocksMRUAndSavesTrue() {
        let t = SpacesOrderRules.transition(enable: true, currentDockMRUSpaces: nil, savedPrevious: nil)
        XCTAssertEqual(t.targetDockMRUSpaces, false)
        XCTAssertEqual(t.updatedSavedPrevious, true)
        XCTAssertTrue(t.needsDockUpdate)
    }

    func testEnablingWhenAlreadyFalseSkipsDockRestartAndPreservesFalse() {
        let t = SpacesOrderRules.transition(enable: true, currentDockMRUSpaces: false, savedPrevious: nil)
        XCTAssertEqual(t.targetDockMRUSpaces, false)
        XCTAssertEqual(t.updatedSavedPrevious, false)
        XCTAssertFalse(t.needsDockUpdate)
    }

    func testEnablingPreservesExistingSavedPrevious() {
        let t = SpacesOrderRules.transition(enable: true, currentDockMRUSpaces: false, savedPrevious: true)
        XCTAssertEqual(t.targetDockMRUSpaces, false)
        XCTAssertEqual(t.updatedSavedPrevious, true)
        XCTAssertFalse(t.needsDockUpdate)
    }

    func testDisablingRestoresSavedTrueAndClearsSavedKey() {
        let t = SpacesOrderRules.transition(enable: false, currentDockMRUSpaces: false, savedPrevious: true)
        XCTAssertEqual(t.targetDockMRUSpaces, true)
        XCTAssertNil(t.updatedSavedPrevious)
        XCTAssertTrue(t.needsDockUpdate)
    }

    func testDisablingRestoresSavedFalseWithoutDockRestart() {
        let t = SpacesOrderRules.transition(enable: false, currentDockMRUSpaces: false, savedPrevious: false)
        XCTAssertEqual(t.targetDockMRUSpaces, false)
        XCTAssertNil(t.updatedSavedPrevious)
        XCTAssertFalse(t.needsDockUpdate)
    }

    func testDisablingWithoutSavedValueDefaultsToTrue() {
        let t = SpacesOrderRules.transition(enable: false, currentDockMRUSpaces: false, savedPrevious: nil)
        XCTAssertEqual(t.targetDockMRUSpaces, true)
        XCTAssertNil(t.updatedSavedPrevious)
        XCTAssertTrue(t.needsDockUpdate)
    }
}
