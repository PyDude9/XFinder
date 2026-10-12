import XCTest
import Foundation

/// D1 group 2: page order and visibility, the two-finger page swipe, named accents.
final class NotchPagesTests: XCTestCase {
    typealias P = NotchPages
    typealias Page = NotchSurfaceMachine.Page

    func testParseKeepsOrderDropsUnknownsAndDuplicatesAndNeverReturnsEmpty() {
        XCTAssertEqual(P.parse("clipboard, files"), [.clipboard, .files], "order is the user's")
        XCTAssertEqual(P.parse("clipboard,bogus,files,clipboard"), [.clipboard, .files], "unknown dropped, duplicate collapsed")
        XCTAssertEqual(P.parse(nil), P.defaultOrder)
        XCTAssertEqual(P.parse(""), P.defaultOrder, "empty ⇒ default, never a hub with no page")
        XCTAssertEqual(P.parse("bogus"), P.defaultOrder)
        XCTAssertEqual(P.parse(P.defaultRaw), P.defaultOrder, "the view's default string and the reader's agree")
        XCTAssertEqual(P.serialize([.nowPlaying, .files]), "nowPlaying,files")
    }

    func testHiddenPagesTrailInTheSettingsListAndRequestsResolveToAShownPage() {
        XCTAssertEqual(P.allInOrder(shown: [.nowPlaying]), [.nowPlaying, .files, .clipboard, .agents, .calendar])   // N3/N4: hidden pages trail in default order
        XCTAssertEqual(P.resolve(.files, shown: [.clipboard, .nowPlaying]), .clipboard, "a hidden tray tab: the badge click opens the first shown page")
        XCTAssertEqual(P.resolve(.clipboard, shown: [.clipboard]), .clipboard)
    }

    func testToggleNeverHidesTheLastPageAndShowsAtTheEnd() {
        XCTAssertEqual(P.toggled(.files, in: [.files, .clipboard]), [.clipboard])
        XCTAssertEqual(P.toggled(.files, in: [.files]), [.files], "the last page cannot be hidden")
        XCTAssertEqual(P.toggled(.nowPlaying, in: [.files]), [.files, .nowPlaying])
    }

    func testMoveStepsOneAndStopsAtTheEnds() {
        XCTAssertEqual(P.moved(.clipboard, by: -1, in: [.files, .clipboard, .nowPlaying]), [.clipboard, .files, .nowPlaying])
        XCTAssertEqual(P.moved(.files, by: -1, in: [.files, .clipboard]), [.files, .clipboard], "already first")
        XCTAssertEqual(P.moved(.nowPlaying, by: 1, in: [.files, .nowPlaying]), [.files, .nowPlaying], "already last")
        XCTAssertEqual(P.moved(.nowPlaying, by: 1, in: [.files]), [.files], "not shown ⇒ unchanged")
    }

    func testSwipeFiresOncePastTheThresholdInTheGesturesDirectionAndResets() {
        var s = P.SwipeAccumulator()
        XCTAssertNil(s.feed(deltaX: -20)); XCTAssertNil(s.feed(deltaX: -30))
        XCTAssertEqual(s.feed(deltaX: -15), 1, "fingers moving left ⇒ next page")
        XCTAssertNil(s.feed(deltaX: -100), "already fired in this gesture")
        s.reset()
        XCTAssertEqual(s.feed(deltaX: 70), -1, "fingers moving right ⇒ previous page")
        s.reset()
        XCTAssertNil(s.feed(deltaX: 40)); XCTAssertNil(s.feed(deltaX: -40)); XCTAssertNil(s.feed(deltaX: 10), "wobbling under the threshold never fires")
    }

    func testPageAfterSwipeStopsAtTheEnds() {
        let shown: [Page] = [.files, .clipboard, .nowPlaying]
        XCTAssertEqual(P.pageAfterSwipe(.files, direction: 1, shown: shown), .clipboard)
        XCTAssertNil(P.pageAfterSwipe(.files, direction: -1, shown: shown), "no wrap at the start")
        XCTAssertNil(P.pageAfterSwipe(.nowPlaying, direction: 1, shown: shown), "no wrap at the end")
        XCTAssertEqual(P.pageAfterSwipe(.nowPlaying, direction: 1, shown: [.files]), .files, "a current page that is not shown lands on the first")
    }

    func testAccentNamesMapToColoursAndSystemMeansNone() {
        XCTAssertNil(NotchAccent.rgb(named: "system"))
        XCTAssertNil(NotchAccent.rgb(named: "chartreuse"), "unknown ⇒ system, never a crash or black")
        for name in NotchAccent.choices.dropFirst() {
            let c = NotchAccent.rgb(named: name)
            XCTAssertNotNil(c, name)
            if let c { XCTAssertTrue((0...1).contains(c.red) && (0...1).contains(c.green) && (0...1).contains(c.blue)) }
        }
        XCTAssertEqual(NotchAccent.choices.first, "system")
    }
}
