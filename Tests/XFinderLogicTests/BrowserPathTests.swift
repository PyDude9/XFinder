import XCTest

/// XF-T28 — breadcrumb segmentation, collapsing, and the "type a path" field's parsing and Tab completion.
final class BrowserPathTests: XCTestCase {

    // MARK: segments(of:rootName:)

    func testRootPathIsJustTheVolumeName() {
        let segs = BrowserPath.segments(of: "/", rootName: "Macintosh HD")
        XCTAssertEqual(segs, [BrowserPath.Segment(name: "Macintosh HD", path: "/")])
    }

    func testOrdinaryPathChainsFromTheVolumeRoot() {
        let segs = BrowserPath.segments(of: "/Users/a/Docs", rootName: "Macintosh HD")
        XCTAssertEqual(segs, [
            BrowserPath.Segment(name: "Macintosh HD", path: "/"),
            BrowserPath.Segment(name: "Users", path: "/Users"),
            BrowserPath.Segment(name: "a", path: "/Users/a"),
            BrowserPath.Segment(name: "Docs", path: "/Users/a/Docs"),
        ])
    }

    func testVolumesPathStartsAtTheVolumeNameNotSlashOrVolumes() {
        let segs = BrowserPath.segments(of: "/Volumes/External", rootName: "Macintosh HD")
        XCTAssertEqual(segs, [BrowserPath.Segment(name: "External", path: "/Volumes/External")],
                       "no '/' segment and no 'Volumes' segment — only the other disk's own name")
    }

    func testVolumesPathContinuesBelowTheVolumeName() {
        let segs = BrowserPath.segments(of: "/Volumes/External/Backups/2026", rootName: "Macintosh HD")
        XCTAssertEqual(segs, [
            BrowserPath.Segment(name: "External", path: "/Volumes/External"),
            BrowserPath.Segment(name: "Backups", path: "/Volumes/External/Backups"),
            BrowserPath.Segment(name: "2026", path: "/Volumes/External/Backups/2026"),
        ])
    }

    func testPathWithTrailingSlashSegmentsTheSameAsWithout() {
        XCTAssertEqual(BrowserPath.segments(of: "/Users/a/", rootName: "Macintosh HD"),
                       BrowserPath.segments(of: "/Users/a", rootName: "Macintosh HD"))
    }

    func testVolumesRootItselfIsJustVolumesSegment() {
        // "/Volumes" alone (no disk name yet) falls back to the ordinary chain since there is no X to anchor on.
        let segs = BrowserPath.segments(of: "/Volumes", rootName: "Macintosh HD")
        XCTAssertEqual(segs, [
            BrowserPath.Segment(name: "Macintosh HD", path: "/"),
            BrowserPath.Segment(name: "Volumes", path: "/Volumes"),
        ])
    }

    // MARK: collapse(count:maxVisible:)

    func testCountAtOrBelowMaxVisibleNeedsNoCollapsing() {
        XCTAssertEqual(BrowserPath.collapse(count: 4, maxVisible: 4), [.segment(0), .segment(1), .segment(2), .segment(3)])
        XCTAssertEqual(BrowserPath.collapse(count: 3, maxVisible: 5), [.segment(0), .segment(1), .segment(2)])
    }

    func testCollapseKeepsFirstAndTailHidingTheMiddle() {
        // 7 segments, 4 visible slots ⇒ first (0), ellipsis(1,2,3,4), then last two (5,6).
        let result = BrowserPath.collapse(count: 7, maxVisible: 4)
        XCTAssertEqual(result, [.segment(0), .ellipsis(hidden: [1, 2, 3, 4]), .segment(5), .segment(6)])
    }

    func testCollapseWithMaxVisibleThreeKeepsFirstAndLastOnly() {
        let result = BrowserPath.collapse(count: 5, maxVisible: 3)
        XCTAssertEqual(result, [.segment(0), .ellipsis(hidden: [1, 2, 3]), .segment(4)])
    }

    func testMaxVisibleBelowThreeIsTreatedAsThree() {
        XCTAssertEqual(BrowserPath.collapse(count: 5, maxVisible: 2), BrowserPath.collapse(count: 5, maxVisible: 3))
        XCTAssertEqual(BrowserPath.collapse(count: 5, maxVisible: 0), BrowserPath.collapse(count: 5, maxVisible: 3))
        XCTAssertEqual(BrowserPath.collapse(count: 5, maxVisible: -4), BrowserPath.collapse(count: 5, maxVisible: 3))
    }

    func testCollapseOfEmptyIsEmpty() {
        XCTAssertEqual(BrowserPath.collapse(count: 0, maxVisible: 4), [])
    }

    func testCollapseExactlyOneOverThresholdStillCollapses() {
        // count = maxVisible + 1 = 5, visible slots = 4 ⇒ first + 2-item tail + one ellipsis hiding the rest.
        let result = BrowserPath.collapse(count: 5, maxVisible: 4)
        XCTAssertEqual(result, [.segment(0), .ellipsis(hidden: [1, 2]), .segment(3), .segment(4)])
    }

    // MARK: resolve(typed:current:home:)

    func testEmptyTypedStaysAtCurrent() {
        XCTAssertEqual(BrowserPath.resolve(typed: "", current: "/Users/a/Docs", home: "/Users/a"), "/Users/a/Docs")
        XCTAssertEqual(BrowserPath.resolve(typed: "   ", current: "/Users/a/Docs", home: "/Users/a"), "/Users/a/Docs")
    }

    func testTildeAloneIsHome() {
        XCTAssertEqual(BrowserPath.resolve(typed: "~", current: "/Users/a/Docs", home: "/Users/a"), "/Users/a")
    }

    func testTildeSlashIsRelativeToHome() {
        XCTAssertEqual(BrowserPath.resolve(typed: "~/Desktop", current: "/Users/a/Docs", home: "/Users/a"), "/Users/a/Desktop")
    }

    func testAbsolutePathIsUsedAsIs() {
        XCTAssertEqual(BrowserPath.resolve(typed: "/Applications", current: "/Users/a/Docs", home: "/Users/a"), "/Applications")
    }

    func testRelativePathIsRelativeToCurrent() {
        XCTAssertEqual(BrowserPath.resolve(typed: "sub/dir", current: "/Users/a/Docs", home: "/Users/a"), "/Users/a/Docs/sub/dir")
    }

    func testDotDotWalksUpFromCurrent() {
        XCTAssertEqual(BrowserPath.resolve(typed: "..", current: "/Users/a/Docs", home: "/Users/a"), "/Users/a")
        XCTAssertEqual(BrowserPath.resolve(typed: "../../etc", current: "/Users/a/Docs", home: "/Users/a"), "/Users/etc")
        XCTAssertEqual(BrowserPath.resolve(typed: "../../../etc", current: "/Users/a/Docs", home: "/Users/a"), "/etc")
    }

    func testDotDotPastRootStaysAtRoot() {
        XCTAssertEqual(BrowserPath.resolve(typed: "../../../../..", current: "/Users/a", home: "/Users/a"), "/")
    }

    func testDotIsSkipped() {
        XCTAssertEqual(BrowserPath.resolve(typed: "./sub/./x", current: "/Users/a", home: "/Users/a"), "/Users/a/sub/x")
    }

    func testDoubleSlashesAreSquashed() {
        XCTAssertEqual(BrowserPath.resolve(typed: "//Users//a//Docs", current: "/", home: "/Users/a"), "/Users/a/Docs")
    }

    func testTrailingSlashIsDroppedExceptForRoot() {
        XCTAssertEqual(BrowserPath.resolve(typed: "/Applications/", current: "/", home: "/Users/a"), "/Applications")
        XCTAssertEqual(BrowserPath.resolve(typed: "/", current: "/Users/a", home: "/Users/a"), "/")
    }

    func testTildeInTheMiddleOfAWordIsNotHomeExpansion() {
        // Only a leading "~" or "~/" is special; "a~b" is a literal relative path component.
        XCTAssertEqual(BrowserPath.resolve(typed: "a~b", current: "/Users/a", home: "/x"), "/Users/a/a~b")
    }

    // MARK: completions(typed:children:)

    func testCompletionsMatchPrefixOfLastComponent() {
        let children = ["Documents", "Downloads", "Desktop", "Music"]
        XCTAssertEqual(BrowserPath.completions(typed: "/Users/a/Do", children: children), ["Documents", "Downloads"])
    }

    func testCompletionsAreCaseAndDiacriticInsensitive() {
        let children = ["ảnh", "Anh", "khác"]
        XCTAssertEqual(Set(BrowserPath.completions(typed: "/Users/a/an", children: children)), Set(["ảnh", "Anh"]))
    }

    func testCompletionsOnBareNameWithNoSlashUseWholeTypedAsPrefix() {
        XCTAssertEqual(BrowserPath.completions(typed: "Doc", children: ["Documents", "Music"]), ["Documents"])
    }

    func testEmptyLastComponentReturnsAllChildrenSorted() {
        XCTAssertEqual(BrowserPath.completions(typed: "/Users/a/", children: ["File 10", "File 2", "File 1"]),
                       ["File 1", "File 2", "File 10"], "natural order even with an empty prefix")
    }

    func testCompletionsAreNaturallySorted() {
        let children = ["File 10", "File 2", "File 1"]
        XCTAssertEqual(BrowserPath.completions(typed: "/x/File", children: children), ["File 1", "File 2", "File 10"])
    }

    func testCompletionsExcludeNonMatchingNames() {
        XCTAssertEqual(BrowserPath.completions(typed: "/x/zz", children: ["Documents", "Music"]), [])
    }

    // MARK: commonPrefix(_:)

    func testCommonPrefixOfEmptyListIsEmpty() {
        XCTAssertEqual(BrowserPath.commonPrefix([]), "")
    }

    func testCommonPrefixOfOneNameIsTheNameItself() {
        XCTAssertEqual(BrowserPath.commonPrefix(["Documents"]), "Documents")
    }

    func testCommonPrefixKeepsCasingOfFirstName() {
        XCTAssertEqual(BrowserPath.commonPrefix(["Documents", "document-old", "DOCUMENT2"]), "Document")
    }

    func testCommonPrefixWithNoSharedCharactersIsEmpty() {
        XCTAssertEqual(BrowserPath.commonPrefix(["Alpha", "Beta"]), "")
    }

    func testCommonPrefixStopsAtShortestName() {
        XCTAssertEqual(BrowserPath.commonPrefix(["Documents", "Doc"]), "Doc")
    }

    func testCommonPrefixIsCaseInsensitiveAcrossAllNames() {
        XCTAssertEqual(BrowserPath.commonPrefix(["abcXYZ", "ABCdef"]), "abc")
    }

    func testCommonPrefixOfEmptyFirstNameIsEmpty() {
        XCTAssertEqual(BrowserPath.commonPrefix(["", "Documents"]), "")
    }

    func testCommonPrefixWithLengthChangingFoldStopsAtTheRealDivergence() {
        // "ß".folding(.diacriticInsensitive) == "ss" (2 chars from 1): folding the whole string before comparing
        // would desync the shared index against the unfolded "straße" and over-report "stra\u{00DF}e" as shared.
        // The true common prefix stops at "stra" — position 4 differs ("ß" vs "s", not a per-character fold match).
        XCTAssertEqual(BrowserPath.commonPrefix(["straße", "strasse"]), "stra")
        XCTAssertEqual(BrowserPath.commonPrefix(["ß", "ssx"]), "")
        XCTAssertEqual(BrowserPath.commonPrefix(["ßabc", "ssabd"]), "")
    }
}
