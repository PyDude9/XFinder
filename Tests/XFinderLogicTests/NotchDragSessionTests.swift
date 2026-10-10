import XCTest
import Foundation

final class NotchDragSessionTests: XCTestCase {
    let fileTypes = ["public.file-url", "com.apple.finder.node"]
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// The measured trap: the drag pasteboard still holds an old Finder drag. A new press that
    /// drags a window or selects text never writes to it, so its change count does not move — and
    /// that press must NOT be treated as a file drag.
    func testStaleFileTypesFromAnEarlierDragAreIgnored() {
        var d = NotchDragSession(currentChangeCount: 7)
        d.pressBegan(changeCount: 7)
        var asked = 0
        XCTAssertFalse(d.carriesFiles(now: t0, changeCount: { 7 }, types: { asked += 1; return self.fileTypes }))
        XCTAssertEqual(asked, 0, "types must not even be read while the change count is unchanged")
    }

    func testANewFileDragDuringThePressIsRecognisedAndCached() {
        var d = NotchDragSession(currentChangeCount: 7)
        d.pressBegan(changeCount: 7)
        XCTAssertTrue(d.carriesFiles(now: t0, changeCount: { 8 }, types: { self.fileTypes }))
        XCTAssertTrue(d.carriesFiles(now: at(1), changeCount: { XCTFail("no pasteboard read once decided"); return 0 },
                                     types: { XCTFail("verdict must be cached"); return [] }))
    }

    func testANewTextDragIsNotAFileDragAndIsNotReReadEither() {
        var d = NotchDragSession(currentChangeCount: 1)
        d.pressBegan(changeCount: 1)
        XCTAssertFalse(d.carriesFiles(now: t0, changeCount: { 2 }, types: { ["public.utf8-plain-text"] }))
        XCTAssertFalse(d.carriesFiles(now: at(1), changeCount: { XCTFail("decided ⇒ no read"); return 2 }, types: { [] }))
    }

    func testTheLegacyFilenamesTypeCounts() {
        var d = NotchDragSession(currentChangeCount: 1)
        d.pressBegan(changeCount: 1)
        XCTAssertTrue(d.carriesFiles(now: t0, changeCount: { 2 }, types: { ["NSFilenamesPboardType"] }))
    }

    func testEachPressStartsUndecided() {
        var d = NotchDragSession(currentChangeCount: 1)
        d.pressBegan(changeCount: 1)
        XCTAssertTrue(d.carriesFiles(now: t0, changeCount: { 2 }, types: { self.fileTypes }))
        // Next press: a window drag. The pasteboard still says "files" at count 2.
        d.pressBegan(changeCount: 2)
        XCTAssertFalse(d.carriesFiles(now: at(1), changeCount: { 2 }, types: { self.fileTypes }),
                       "the previous press's verdict must not leak")
    }

    func testMonitorsStartedMidPressDoNotTrustTheStalePasteboard() {
        var d = NotchDragSession(currentChangeCount: 42)
        XCTAssertFalse(d.carriesFiles(now: t0, changeCount: { 42 }, types: { self.fileTypes }))
    }

    /// A window drag never starts a drag session, so the verdict never settles — and every pixel of
    /// that drag would otherwise cost a pasteboard-server round trip. Reads are throttled.
    func testWhileUndecidedThePasteboardIsReadAtMostOncePerInterval() {
        var d = NotchDragSession(currentChangeCount: 5)
        d.pressBegan(changeCount: 5)
        var reads = 0
        // 120 drag events over one second (a fast window drag), change count never moves.
        for i in 0..<120 {
            _ = d.carriesFiles(now: at(Double(i) / 120), changeCount: { reads += 1; return 5 }, types: { [] })
        }
        XCTAssertLessThanOrEqual(reads, 21, "\(reads) reads in 1 s — the throttle is not working")
        XCTAssertGreaterThanOrEqual(reads, 15, "\(reads) reads in 1 s — throttled so hard a real drag would be missed")
    }
}
