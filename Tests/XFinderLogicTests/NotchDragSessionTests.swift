import XCTest
import Foundation

final class NotchDragSessionTests: XCTestCase {
    let fileTypes = ["public.file-url", "com.apple.finder.node"]

    /// The measured trap: the drag pasteboard still holds an old Finder drag. A new press that
    /// drags a window or selects text never writes to it, so its change count does not move — and
    /// that press must NOT be treated as a file drag.
    func testStaleFileTypesFromAnEarlierDragAreIgnored() {
        var d = NotchDragSession(currentChangeCount: 7)
        d.pressBegan(changeCount: 7)
        var asked = 0
        XCTAssertFalse(d.carriesFiles(changeCount: 7, types: { asked += 1; return self.fileTypes }))
        XCTAssertEqual(asked, 0, "types must not even be read while the change count is unchanged")
    }

    func testANewFileDragDuringThePressIsRecognised() {
        var d = NotchDragSession(currentChangeCount: 7)
        d.pressBegan(changeCount: 7)
        XCTAssertTrue(d.carriesFiles(changeCount: 8, types: { self.fileTypes }))
        XCTAssertTrue(d.carriesFiles(changeCount: 8, types: { XCTFail("verdict must be cached"); return [] }))
    }

    func testANewTextDragIsNotAFileDrag() {
        var d = NotchDragSession(currentChangeCount: 1)
        d.pressBegan(changeCount: 1)
        XCTAssertFalse(d.carriesFiles(changeCount: 2, types: { ["public.utf8-plain-text"] }))
    }

    func testTheLegacyFilenamesTypeCounts() {
        var d = NotchDragSession(currentChangeCount: 1)
        d.pressBegan(changeCount: 1)
        XCTAssertTrue(d.carriesFiles(changeCount: 2, types: { ["NSFilenamesPboardType"] }))
    }

    func testEachPressStartsUndecided() {
        var d = NotchDragSession(currentChangeCount: 1)
        d.pressBegan(changeCount: 1)
        XCTAssertTrue(d.carriesFiles(changeCount: 2, types: { self.fileTypes }))
        // Next press: a window drag. The pasteboard still says "files" at count 2.
        d.pressBegan(changeCount: 2)
        XCTAssertFalse(d.carriesFiles(changeCount: 2, types: { self.fileTypes }), "the previous press's verdict must not leak")
    }

    func testMonitorsStartedMidPressDoNotTrustTheStalePasteboard() {
        // `init` seeds the count with the current value, so a controller armed while a drag is
        // already in flight (or long after one ended) starts from "no new session".
        var d = NotchDragSession(currentChangeCount: 42)
        XCTAssertFalse(d.carriesFiles(changeCount: 42, types: { self.fileTypes }))
    }
}
