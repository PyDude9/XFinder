import XCTest
import Foundation

final class CutBoardTests: XCTestCase {
    // MARK: cut / isCut

    func testCutMarksEachPath() {
        var board = CutBoard()
        board.cut(["/a/x", "/a/y"], changeCount: 1)
        XCTAssertTrue(board.isCut("/a/x"))
        XCTAssertTrue(board.isCut("/a/y"))
        XCTAssertFalse(board.isCut("/a/z"))
    }

    func testFreshCutBoardHasNothingCut() {
        let board = CutBoard()
        XCTAssertFalse(board.isCut("/anything"))
    }

    // MARK: cancel

    func testCancelClearsPendingCut() {
        var board = CutBoard()
        board.cut(["/a/x"], changeCount: 1)
        board.cancel()
        XCTAssertFalse(board.isCut("/a/x"))
        XCTAssertEqual(board.pasteMoves(into: "/b", currentChangeCount: 1), [])
    }

    // MARK: pasteMoves — happy path

    func testPasteMovesReturnsCutPathsWhenChangeCountUnchanged() {
        var board = CutBoard()
        board.cut(["/a/x", "/a/y"], changeCount: 5)
        let moves = board.pasteMoves(into: "/b", currentChangeCount: 5)
        XCTAssertEqual(Set(moves), ["/a/x", "/a/y"])
    }

    // MARK: pasteMoves — cancellation via newer copy (changeCount bump)

    func testPasteMovesEmptyWhenPasteboardChangedSinceCut() {
        var board = CutBoard()
        board.cut(["/a/x"], changeCount: 5)
        // A later ⌘C (here or in another app) bumps NSPasteboard's change count — the pending cut is cancelled.
        let moves = board.pasteMoves(into: "/b", currentChangeCount: 6)
        XCTAssertEqual(moves, [])
    }

    func testPasteMovesEmptyWhenNothingWasEverCut() {
        let board = CutBoard()
        XCTAssertEqual(board.pasteMoves(into: "/b", currentChangeCount: 0), [])
    }

    // MARK: pasteMoves — pasting into the source folder is a no-op

    func testPasteMovesExcludesItemsWhoseParentIsTheDestination() {
        var board = CutBoard()
        board.cut(["/a/x", "/c/y"], changeCount: 1)
        // "/a/x" lives in "/a" — pasting back into "/a" must not move it; "/c/y" lives elsewhere and still moves.
        let moves = board.pasteMoves(into: "/a", currentChangeCount: 1)
        XCTAssertEqual(moves, ["/c/y"])
    }

    func testPasteMovesEmptyWhenAllCutItemsAlreadyLiveInDestination() {
        var board = CutBoard()
        board.cut(["/a/x", "/a/y"], changeCount: 1)
        let moves = board.pasteMoves(into: "/a", currentChangeCount: 1)
        XCTAssertEqual(moves, [])
    }

    func testPasteMovesNormalizesDestinationPathBeforeComparing() {
        var board = CutBoard()
        board.cut(["/a/x"], changeCount: 1)
        // Trailing slash on the destination must still be recognized as the same folder "/a".
        let moves = board.pasteMoves(into: "/a/", currentChangeCount: 1)
        XCTAssertEqual(moves, [])
    }

    // MARK: pasteMoves — empty cut set

    func testPasteMovesEmptyForEmptyCutSet() {
        var board = CutBoard()
        board.cut([], changeCount: 1)
        XCTAssertEqual(board.pasteMoves(into: "/b", currentChangeCount: 1), [])
    }

    // MARK: re-cutting replaces the previous set

    func testCuttingAgainReplacesThePreviousSet() {
        var board = CutBoard()
        board.cut(["/a/x"], changeCount: 1)
        board.cut(["/b/y"], changeCount: 2)
        XCTAssertFalse(board.isCut("/a/x"))
        XCTAssertTrue(board.isCut("/b/y"))
        XCTAssertEqual(board.pasteMoves(into: "/c", currentChangeCount: 2), ["/b/y"])
    }
}
