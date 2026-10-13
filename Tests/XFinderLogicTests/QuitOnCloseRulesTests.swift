import XCTest

/// F3 — the rules behind "quit when the last window closes". Each case is one of the measured facts in
/// `QuitOnCloseRules`' header.
final class QuitOnCloseRulesTests: XCTestCase {
    typealias Q = QuitOnCloseRules
    let own = "com.xfinder.app"

    func testOnlyListedAppsAreWatchedAndOnlyWhenOn() {
        let apps: Set<String> = ["com.apple.Preview", "com.apple.TextEdit"]
        XCTAssertTrue(Q.isWatched("com.apple.Preview", enabled: true, apps: apps, ownBundleID: own))
        XCTAssertFalse(Q.isWatched("com.apple.Preview", enabled: false, apps: apps, ownBundleID: own), "switch off ⇒ nothing is watched")
        XCTAssertFalse(Q.isWatched("com.apple.Safari", enabled: true, apps: apps, ownBundleID: own), "not listed ⇒ never quit")
        XCTAssertFalse(Q.isWatched(nil, enabled: true, apps: apps, ownBundleID: own))
    }

    func testFinderTheSystemAndXFinderAreNeverQuitEvenIfListed() {
        let apps: Set<String> = ["com.apple.finder", "com.apple.dock", own, "com.apple.loginwindow"]
        for bid in apps { XCTAssertFalse(Q.isWatched(bid, enabled: true, apps: apps, ownBundleID: own), bid) }
    }

    func testQuitOnlyWhenNothingIsLeft() {
        XCTAssertTrue(Q.shouldQuit(windowCount: 0, stillRunning: true, watched: true))
        XCTAssertFalse(Q.shouldQuit(windowCount: 1, stillRunning: true, watched: true), "one window left (any kind, hidden or not) keeps it")
        XCTAssertFalse(Q.shouldQuit(windowCount: nil, stillRunning: true, watched: true), "AX could not read ⇒ do nothing, never guess")
        XCTAssertFalse(Q.shouldQuit(windowCount: 0, stillRunning: false, watched: true), "already gone")
        XCTAssertFalse(Q.shouldQuit(windowCount: 0, stillRunning: true, watched: false), "unlisted while the grace ran")
    }

    func testGraceCoversCloseThenNew() {
        XCTAssertGreaterThanOrEqual(Q.grace, 0.5, "⌘W then ⌘N must not quit in between")
        XCTAssertLessThanOrEqual(Q.grace, 3, "and the app must still quit promptly")
    }

    func testListRoundTrips() {
        XCTAssertEqual(Q.parseApps(" com.a , ,com.b,com.a"), ["com.a", "com.b"])
        XCTAssertEqual(Q.encodeApps(["com.b", "com.a"]), "com.a,com.b")
        XCTAssertEqual(Q.parseApps(nil), [])
    }
}
