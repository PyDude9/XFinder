import XCTest

/// XF-T37 L5 — "Warn before quitting (⌘Q)": only a typed ⌘Q in a browser window is held back; a second ⌘Q (or the key
/// repeat of a held ⌘Q) inside the confirm window quits.
final class QuitGuardRulesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func decide(enabled: Bool = true, typed: Bool = true, browserKey: Bool = true, last: Date? = nil,
                        now: Date) -> QuitGuardRules.Decision {
        QuitGuardRules.decide(enabled: enabled, typedCommandQ: typed, browserWindowIsKey: browserKey, lastWarning: last, now: now)
    }

    func testFirstCommandQInABrowserWindowWarns() {
        XCTAssertEqual(decide(now: t0), .warn)
    }

    func testSecondCommandQInsideTheWindowQuits() {
        XCTAssertEqual(decide(last: t0, now: t0.addingTimeInterval(0.4)), .quit, "a key repeat of a held ⌘Q")
        XCTAssertEqual(decide(last: t0, now: t0.addingTimeInterval(QuitGuardRules.confirmWindow)), .quit)
        XCTAssertEqual(decide(last: t0, now: t0.addingTimeInterval(QuitGuardRules.confirmWindow + 0.01)), .warn, "too late: warn again")
        XCTAssertEqual(decide(last: t0, now: t0.addingTimeInterval(-1)), .warn, "a clock step back is not a confirmation")
    }

    func testEverythingElseQuitsAtOnce() {
        XCTAssertEqual(decide(enabled: false, now: t0), .quit)
        XCTAssertEqual(decide(typed: false, now: t0), .quit, "menu-bar Quit, Dock, logout")
        XCTAssertEqual(decide(browserKey: false, now: t0), .quit, "another XFinder window is key")
    }

    func testCommandQRecognition() {
        XCTAssertTrue(QuitGuardRules.isCommandQ(isKeyDown: true, charactersIgnoringModifiers: "q", hasCommand: true))
        XCTAssertTrue(QuitGuardRules.isCommandQ(isKeyDown: true, charactersIgnoringModifiers: "Q", hasCommand: true))
        XCTAssertFalse(QuitGuardRules.isCommandQ(isKeyDown: true, charactersIgnoringModifiers: "q", hasCommand: false))
        XCTAssertFalse(QuitGuardRules.isCommandQ(isKeyDown: false, charactersIgnoringModifiers: nil, hasCommand: true))
        XCTAssertFalse(QuitGuardRules.isCommandQ(isKeyDown: true, charactersIgnoringModifiers: "w", hasCommand: true))
    }
}
