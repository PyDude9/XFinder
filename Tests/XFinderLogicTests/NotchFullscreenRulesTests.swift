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

    /// Frames measured 2026-11-07 on the notched 1728×1117 built-in display (safe-area top 32).
    func testNotchedDisplayFullscreenSitsBelowTheHousingAndNeedsTheAXFlag() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let nativeFullscreen = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let zoomedDockShown = CGRect(x: 0, y: 33, width: 1728, height: 1022)
        let wholeDisplay = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        XCTAssertFalse(R.matchesDisplayFrame(nativeFullscreen, display), "the old rule never fired on the notched screen")
        XCTAssertTrue(R.isFullscreenFrame(nativeFullscreen, display: display, topInset: 32, axFullScreen: true))
        XCTAssertFalse(R.isFullscreenFrame(nativeFullscreen, display: display, topInset: 32, axFullScreen: false),
                       "a Fill window with the Dock hidden has this frame but AXFullScreen false")
        XCTAssertFalse(R.isFullscreenFrame(nativeFullscreen, display: display, topInset: 32, axFullScreen: nil),
                       "no Accessibility answer ⇒ show")
        XCTAssertFalse(R.isFullscreenFrame(zoomedDockShown, display: display, topInset: 32, axFullScreen: true))
        XCTAssertTrue(R.isFullscreenFrame(wholeDisplay, display: display, topInset: 32, axFullScreen: nil),
                      "a whole-display frame needs no flag: zoomed windows never cover the menu bar")
        XCTAssertFalse(R.isFullscreenFrame(nativeFullscreen, display: display, topInset: 0, axFullScreen: true),
                       "a display without a housing has no below-housing frame")
    }

    func testDeliberateOpenAndActionableWorkMustRemainVisible() {
        func keep(expanded: Bool = false, task: Bool = false, agents: Int = 0, reply: Bool = false,
                  composer: Bool = false, buttons: Bool = false) -> Bool {
            R.mustRemainVisible(expanded: expanded, taskRunning: task, agentsNeedingYou: agents,
                                replyPending: reply, composerOpen: composer, activityHasButtons: buttons)
        }
        XCTAssertFalse(keep(), "an idle badge or hover peek may hide over a fullscreen app")
        XCTAssertTrue(keep(expanded: true), "a surface opened by click, hotkey or URL must not vanish at once")
        XCTAssertTrue(keep(task: true))
        XCTAssertTrue(keep(agents: 1))
        XCTAssertTrue(keep(reply: true))
        XCTAssertTrue(keep(composer: true))
        XCTAssertTrue(keep(buttons: true))
    }

    func testActionableWorkKeepsNotchVisibleRegardlessOfPolicy() {
        let context = R.Context(fullscreenOwnerPID: 101, frontmostPID: 101,
                                mediaPID: 101, mediaPlaying: true, mustRemainVisible: true)
        XCTAssertFalse(R.shouldHide(.hideInFullscreen, context: context))
        XCTAssertFalse(R.shouldHide(.hideForFullscreenMedia, context: context))
    }
}
