import XCTest
import Foundation

final class ClipboardAutoClearTests: XCTestCase {

    // MARK: - Off means nothing is scheduled

    func testOffAndNegativeSettingsProduceNoDelay() {
        XCTAssertNil(ClipboardAutoClear.delay(forSetting: 0), "0 is off — no timer may be created")
        XCTAssertNil(ClipboardAutoClear.delay(forSetting: -30), "a corrupt negative value must not clear anything")
    }

    func testDelayHonoursTheSettingWithAFloorForHandEditedValues() {
        XCTAssertEqual(ClipboardAutoClear.delay(forSetting: 30), 30)
        XCTAssertEqual(ClipboardAutoClear.delay(forSetting: 900), 900)
        XCTAssertEqual(ClipboardAutoClear.delay(forSetting: 1), ClipboardAutoClear.minimumDelay,
                       "a 1 s clear would race the user's own paste")
    }

    func testPickerChoicesStartWithOffAndAreStrictlyIncreasing() {
        let c = ClipboardAutoClear.choices
        XCTAssertEqual(c.first, 0, "the first choice must be Off")
        XCTAssertEqual(c, c.sorted())
        XCTAssertEqual(Set(c).count, c.count, "no duplicate choices")
        for s in c.dropFirst() {
            XCTAssertNotNil(ClipboardAutoClear.delay(forSetting: s), "every non-zero choice must schedule")
            XCTAssertGreaterThanOrEqual(TimeInterval(s), ClipboardAutoClear.minimumDelay)
        }
    }

    // MARK: - Rule 1: never clear something the user copied later

    func testClearsOnlyWhileTheChangeCountIsStillTheArmedOne() {
        XCTAssertTrue(ClipboardAutoClear.shouldClear(armedChangeCount: 41, currentChangeCount: 41, pasteboardIsEmpty: false))
        XCTAssertFalse(ClipboardAutoClear.shouldClear(armedChangeCount: 41, currentChangeCount: 42, pasteboardIsEmpty: false),
                       "the user copied again — the older timer must not wipe the newer copy")
        XCTAssertFalse(ClipboardAutoClear.shouldClear(armedChangeCount: 41, currentChangeCount: 40, pasteboardIsEmpty: false),
                       "any mismatch, not just 'newer', is a refusal")
    }

    // MARK: - Rule 2: no clear-loop on an empty pasteboard

    func testNeverClearsOrArmsOnAnEmptyPasteboard() {
        XCTAssertFalse(ClipboardAutoClear.shouldClear(armedChangeCount: 7, currentChangeCount: 7, pasteboardIsEmpty: true))
        XCTAssertFalse(ClipboardAutoClear.shouldArm(setting: 30, pasteboardIsEmpty: true),
                       "arming for our own clearContents() change would loop forever")
        XCTAssertTrue(ClipboardAutoClear.shouldArm(setting: 30, pasteboardIsEmpty: false))
        XCTAssertFalse(ClipboardAutoClear.shouldArm(setting: 0, pasteboardIsEmpty: false), "off never arms")
    }

    /// The loop, simulated end to end with the real rules: a copy arms a timer, the timer clears,
    /// the clear bumps the count and empties the pasteboard, the monitor sees that change — and
    /// must NOT arm again. If it did, this would keep going.
    func testTheClearDoesNotRearmItself() {
        var changeCount = 100
        var isEmpty = false
        var timersArmed = 0

        // 1. user copies
        changeCount += 1; isEmpty = false
        if ClipboardAutoClear.shouldArm(setting: 30, pasteboardIsEmpty: isEmpty) { timersArmed += 1 }
        let armed = changeCount
        XCTAssertEqual(timersArmed, 1)

        // 2. timer fires
        if ClipboardAutoClear.shouldClear(armedChangeCount: armed, currentChangeCount: changeCount, pasteboardIsEmpty: isEmpty) {
            changeCount += 1; isEmpty = true     // clearContents()
        }
        XCTAssertTrue(isEmpty)

        // 3. monitor observes the clear as a change
        if ClipboardAutoClear.shouldArm(setting: 30, pasteboardIsEmpty: isEmpty) { timersArmed += 1 }
        XCTAssertEqual(timersArmed, 1, "the clear re-armed a timer — an endless clear loop")
    }
}
