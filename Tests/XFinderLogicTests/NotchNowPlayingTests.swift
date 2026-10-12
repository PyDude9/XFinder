import XCTest
import Foundation
import CoreGraphics

/// B6: how a playing track changes the Notch machine and layout. The track is a `Settings` fact
/// (`nowPlayingActive`), not an event, so the exhaustive walk in NotchSurfaceMachineTests is
/// unchanged; these pin the new branches it does not reach.
final class NotchNowPlayingTests: XCTestCase {
    typealias M = NotchSurfaceMachine
    typealias L = NotchSurfaceLayout
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    var playing: M.Settings { var s = M.Settings(); s.nowPlayingActive = true; return s }

    func testHoverPeeksThePlayingTrackWithNoFilesHeld() {
        var m = M.Machine()
        m.handle(.hoverInZone(since: t0), settings: playing, now: at(1))
        XCTAssertEqual(m.state, .peek); XCTAssertEqual(m.anchor, .notch)
        var off = M.Machine()
        off.handle(.hoverInZone(since: t0), settings: M.Settings(), now: at(1))
        XCTAssertEqual(off.state, .collapsed, "without a track an empty tray never peeks (Part 3c)")
    }

    /// N2: "By activity" opens the player while a track plays; a FIXED choice opens that page whatever plays —
    /// the picker's label promises that page, so a track must not quietly override it.
    func testByActivityOpensThePlayerWhileATrackPlaysAndAFixedChoiceOpensItsPage() {
        var s = playing; s.hoverOpens = .activity
        var m = M.Machine()
        m.handle(.hoverInZone(since: t0), settings: s, now: at(1))
        XCTAssertEqual(m.state, .expanded(.nowPlaying), "By activity: a playing track opens the player page")
        var fixed = playing; fixed.hoverOpens = .clipboard
        var f = M.Machine()
        f.handle(.hoverInZone(since: t0), settings: fixed, now: at(1))
        XCTAssertEqual(f.state, .expanded(.clipboard), "a fixed choice is that page, track or not")
    }

    func testThePeekSurvivesTheTrayEmptyingWhileATrackPlays() {
        var m = M.Machine(); m.itemCount = 2
        m.handle(.hoverInZone(since: t0), settings: playing, now: at(1))
        m.handle(.itemsChanged(count: 0), settings: playing, now: at(2))
        XCTAssertEqual(m.state, .peek, "the strip switches from files to the track, it does not vanish")
        m.handle(.itemsChanged(count: 0), settings: M.Settings(), now: at(3))
        XCTAssertEqual(m.state, .collapsed, "the track ended too ⇒ nothing left to show")
    }

    func testPointerAwayStillClosesANowPlayingPeek() {
        var m = M.Machine()
        m.handle(.hoverInZone(since: t0), settings: playing, now: at(1))
        m.handle(.pointerAway(since: at(2)), settings: playing, now: at(2.1))
        XCTAssertEqual(m.state, .peek, "inside the grace period")
        m.handle(.pointerAway(since: at(2)), settings: playing, now: at(5))
        XCTAssertEqual(m.state, .collapsed)
    }

    func testTheNowPlayingPageIsOnlyReachableFromAnOpenHub() {
        var m = M.Machine()
        m.handle(.switchPage(.nowPlaying), settings: playing, now: t0)
        XCTAssertEqual(m.state, .collapsed, "a page switch never opens the surface")
        m.handle(.activate, settings: playing, now: t0)
        m.handle(.switchPage(.nowPlaying), settings: playing, now: at(1))
        XCTAssertEqual(m.state, .expanded(.nowPlaying))
        m.handle(.dismiss, settings: playing, now: at(2))
        XCTAssertEqual(m.state, .collapsed)
    }

    func testLayoutBadgePeekAndHoverZoneFollowTheTrack() {
        let notch = CGRect(x: 771.5, y: 1085, width: 185, height: 32)
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        func size(_ st: M.State, items: Int, track: Bool) -> CGSize? {
            L.size(for: st, anchor: .notch, itemCount: items, notch: notch, nowPlayingActive: track)
        }
        XCTAssertNil(size(.collapsed, items: 0, track: false), "nothing held, nothing playing ⇒ no badge")
        XCTAssertEqual(size(.collapsed, items: 0, track: true)?.height, 32 + 18, "a track hangs a badge")
        let filesPeek = size(.peek, items: 1, track: false)!, trackPeek = size(.peek, items: 0, track: true)!
        XCTAssertGreaterThan(trackPeek.width, filesPeek.width, "title + artist + three controls need more room")
        XCTAssertEqual(size(.peek, items: 1, track: true), filesPeek, "files take precedence in the strip")
        XCTAssertEqual(L.hoverZone(notch: notch, screen: screen, itemCount: 0).height, 32)
        XCTAssertEqual(L.hoverZone(notch: notch, screen: screen, itemCount: 0, nowPlayingActive: true).height, 32 + 18,
                       "resting on the track badge counts as hovering")
        XCTAssertEqual(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: CGRect(x: 0, y: 0, width: 185, height: 0), nowPlayingActive: true)?.height,
                       L.Metrics.standard.pillHeight, "no physical notch ⇒ the track shows in the pill (B7)")
    }

    /// N8: the MediaRemote numbering measured with an MPRemoteCommandCenter publisher (2026-10-13):
    /// SetShuffleMode 1/2/3 → MPShuffleType off/collections/items, SetRepeatMode 1/2/3 → off/one/all.
    func testShuffleAndRepeatModesCarryTheMeasuredMediaRemoteNumbers() throws {
        XCTAssertEqual(NowPlaying.ShuffleMode.off.rawValue, 1); XCTAssertEqual(NowPlaying.ShuffleMode.albums.rawValue, 2); XCTAssertEqual(NowPlaying.ShuffleMode.songs.rawValue, 3)
        XCTAssertEqual(NowPlaying.RepeatMode.off.rawValue, 1); XCTAssertEqual(NowPlaying.RepeatMode.one.rawValue, 2); XCTAssertEqual(NowPlaying.RepeatMode.all.rawValue, 3)
        let store = try L10nFixture.load()
        for m in NowPlaying.ShuffleMode.allCases { XCTAssertNotNil(store.entries[m.labelKey], m.labelKey) }
        for m in NowPlaying.RepeatMode.allCases { XCTAssertNotNil(store.entries[m.labelKey], m.labelKey) }
    }
}
