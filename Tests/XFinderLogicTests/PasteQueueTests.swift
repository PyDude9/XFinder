import XCTest
import Foundation

final class PasteQueueTests: XCTestCase {

    func testStartPopInOrderAndDrain() {
        var q = PasteQueue<Int>()
        q.start(with: [1, 2, 3])
        XCTAssertTrue(q.active); XCTAssertEqual(q.remaining, 3); XCTAssertEqual(q.total, 3)
        XCTAssertEqual(q.popNext(), 1); XCTAssertEqual(q.popNext(), 2)
        XCTAssertEqual(q.pasted, 2); XCTAssertEqual(q.total, 3)
        XCTAssertEqual(q.popNext(), 3)
        XCTAssertFalse(q.active, "drained ⇒ inactive, so the next ⌘V is a normal paste")
        XCTAssertNil(q.popNext())
    }

    func testAppendBuildsAStackWithoutDuplicates() {
        var q = PasteQueue<Int>()
        XCTAssertFalse(q.active)
        q.append(7); q.append(7); q.append(8)
        XCTAssertEqual(q.items, [7, 8], "⌘-clicking the same card twice must not paste it twice")
        XCTAssertTrue(q.active)
        q.remove(7); q.remove(8)
        XCTAssertFalse(q.active)
    }

    func testStopClearsEverything() {
        var q = PasteQueue<Int>(); q.start(with: [1]); q.stop()
        XCTAssertFalse(q.active); XCTAssertEqual(q.remaining, 0); XCTAssertNil(q.popNext())
    }

    func testStartingAnEmptyStackIsInactive() {
        var q = PasteQueue<Int>(); q.start(with: [])
        XCTAssertFalse(q.active)
    }
}
