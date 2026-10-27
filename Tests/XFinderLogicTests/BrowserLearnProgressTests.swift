import XCTest

final class BrowserLearnProgressTests: XCTestCase {
    func testMalformedAndEmptyProgress() {
        XCTAssertEqual(BrowserLearnProgress.count(in: Data()), 0)
        XCTAssertEqual(BrowserLearnProgress.count(in: Data("{bad".utf8)), 0)
    }

    func testCompletionRoundTripAndUncheckPreservesOtherLessons() {
        var data = BrowserLearnProgress.updating(Data(), lesson: "tabs", isComplete: true)
        data = BrowserLearnProgress.updating(data, lesson: "spaces", isComplete: true)
        XCTAssertEqual(BrowserLearnProgress.count(in: data), 2)
        data = BrowserLearnProgress.updating(data, lesson: "tabs", isComplete: false)
        XCTAssertEqual(BrowserLearnProgress.completed(in: data), ["spaces"])
    }

    func testUnknownFutureIDsSurviveButDoNotInflateCount() throws {
        let original = try JSONEncoder().encode(["future", "navigation", "navigation"])
        let changed = BrowserLearnProgress.updating(original, lesson: "tabs", isComplete: true)
        XCTAssertEqual(BrowserLearnProgress.completed(in: changed), ["future", "navigation", "tabs"])
        XCTAssertEqual(BrowserLearnProgress.count(in: changed), 2)
        XCTAssertEqual(BrowserLearnProgress.updating(changed, lesson: "unknown", isComplete: true), changed)
    }

    func testAllSixAndVirtualLocationRoundTrip() {
        let data = BrowserLearnProgress.lessonIDs.reduce(Data()) {
            BrowserLearnProgress.updating($0, lesson: $1, isComplete: true)
        }
        XCTAssertEqual(BrowserLearnProgress.count(in: data), 6)
        XCTAssertEqual(VirtualLocation.parse(VirtualLocation.learn.path), .learn)
        XCTAssertNil(VirtualLocation.parse(VirtualLocation.learn.path + "/bad"))
    }
}
