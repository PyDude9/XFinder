import XCTest

final class NotchFullscreenRulesTests: XCTestCase {
    typealias V = NotchFullscreenVisibility
    typealias R = NotchFullscreenRules

    func testUnknownPolicyFailsOpen() {
        XCTAssertEqual(V.parse(nil), .show)
        XCTAssertEqual(V.parse("unknown"), .show)
        XCTAssertEqual(V.parse("hideInFullscreen"), .hideInFullscreen)
    }

    func testDisplayFrameMatchUsesBoundedTolerance() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertTrue(R.matchesDisplayFrame(CGRect(x: 2, y: 1, width: 1508, height: 984), display))
        XCTAssertFalse(R.matchesDisplayFrame(CGRect(x: 20, y: 0, width: 1512, height: 982), display))
        XCTAssertFalse(R.matchesDisplayFrame(.zero, display))
        XCTAssertFalse(R.matchesDisplayFrame(display, display, tolerance: -.infinity))
    }

    func testShowAndHidePoliciesRequireKnownFrontmostFullscreenWindow() {
        let knownFullscreen = R.Context(fullscreenOwnerPID: 101, frontmostPID: 101)
        XCTAssertFalse(R.shouldHide(.show, context: knownFullscreen))
        XCTAssertTrue(R.shouldHide(.hideInFullscreen, context: knownFullscreen))
        XCTAssertFalse(R.shouldHide(.hideInFullscreen, context: .init(fullscreenOwnerPID: 101, frontmostPID: 202)))
        XCTAssertFalse(R.shouldHide(.hideInFullscreen, context: .init(frontmostPID: 101)))
    }

    func testMediaPolicyRequiresPlayingSnapshotFromFullscreenOwner() {
        XCTAssertTrue(R.shouldHide(.hideForFullscreenMedia,
                                   context: .init(fullscreenOwnerPID: 101, frontmostPID: 101,
                                                  mediaPID: 101, mediaPlaying: true)))
        XCTAssertFalse(R.shouldHide(.hideForFullscreenMedia,
                                    context: .init(fullscreenOwnerPID: 101, frontmostPID: 101,
                                                   mediaPID: 101, mediaPlaying: false)))
        XCTAssertFalse(R.shouldHide(.hideForFullscreenMedia,
                                    context: .init(fullscreenOwnerPID: 101, frontmostPID: 101,
                                                   mediaPID: 202, mediaPlaying: true)))
        XCTAssertFalse(R.shouldHide(.hideForFullscreenMedia,
                                    context: .init(fullscreenOwnerPID: 101, frontmostPID: 101,
                                                   mediaPlaying: true)))
    }

    func testActionableWorkKeepsNotchVisibleRegardlessOfPolicy() {
        let context = R.Context(fullscreenOwnerPID: 101, frontmostPID: 101,
                                mediaPID: 101, mediaPlaying: true, mustRemainVisible: true)
        XCTAssertFalse(R.shouldHide(.hideInFullscreen, context: context))
        XCTAssertFalse(R.shouldHide(.hideForFullscreenMedia, context: context))
    }
}
