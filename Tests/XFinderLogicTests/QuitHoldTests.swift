import XCTest
import Foundation

final class QuitHoldTests: XCTestCase {

    private typealias M = QuitHold.Machine
    private let cmd = QuitHold.maskCommand

    /// Feed a sequence, return the actions — so a test reads as the user's keystrokes.
    private func run(_ inputs: [QuitHold.Input], on m: inout M) -> [QuitHold.Action] {
        inputs.map { m.handle($0) }
    }

    // MARK: - Which keystroke is ⌘Q

    func testOnlyCommandQExactlyIsTheChord() {
        XCTAssertTrue(QuitHold.isQuitChord(keyCode: 12, flags: cmd))
        XCTAssertFalse(QuitHold.isQuitChord(keyCode: 12, flags: 0), "plain Q is typing")
        XCTAssertFalse(QuitHold.isQuitChord(keyCode: 12, flags: cmd | QuitHold.maskShift), "⌘⇧Q is Log Out")
        XCTAssertFalse(QuitHold.isQuitChord(keyCode: 12, flags: cmd | QuitHold.maskAlternate), "⌘⌥Q is not ⌘Q")
        XCTAssertFalse(QuitHold.isQuitChord(keyCode: 12, flags: cmd | QuitHold.maskControl), "⌃⌘Q is Lock Screen")
        XCTAssertFalse(QuitHold.isQuitChord(keyCode: 13, flags: cmd), "⌘W is not ⌘Q")
        XCTAssertFalse(QuitHold.isQuitChord(keyCode: 12, flags: QuitHold.maskShift))
    }

    func testCapsLockFnAndNumericPadBitsDoNotChangeTheChord() {
        let capsLock: UInt64 = 0x0001_0000, fn: UInt64 = 0x0080_0000, numPad: UInt64 = 0x0020_0000
        XCTAssertTrue(QuitHold.isQuitChord(keyCode: 12, flags: cmd | capsLock), "⌘Q with Caps Lock is still ⌘Q")
        XCTAssertTrue(QuitHold.isQuitChord(keyCode: 12, flags: cmd | fn | numPad))
    }

    func testFinderAndTheDockAreNeverIntercepted() {
        XCTAssertFalse(QuitHold.intercepts(bundleID: "com.apple.finder"), "⌘Q does nothing in Finder")
        XCTAssertFalse(QuitHold.intercepts(bundleID: "com.apple.dock"))
        XCTAssertFalse(QuitHold.intercepts(bundleID: nil), "no frontmost app → nothing to protect")
        XCTAssertFalse(QuitHold.intercepts(bundleID: ""))
        XCTAssertTrue(QuitHold.intercepts(bundleID: "com.apple.Safari"))
        XCTAssertTrue(QuitHold.intercepts(bundleID: "com.xfinder.app"), "XFinder protects itself too")
    }

    // MARK: - The accident this exists for

    func testAQuickTapNeverQuits() {
        var m = M()
        let a = run([.quitDown(isRepeat: false), .quitUp], on: &m)
        XCTAssertEqual(a, [.beginHold, .cancelHold(swallowEvent: true)],
                       "tap = down then up before the timer: hold begins, then is cancelled, no .quit")
        XCTAssertEqual(m.state, .idle)
        // The hold timer firing late (it raced the cancel) must do nothing.
        XCTAssertEqual(m.handle(.holdElapsed), .ignore, "a stale timer after a cancel must not quit anything")
    }

    func testHoldingForTheFullDurationQuitsExactlyOnce() {
        var m = M()
        var quits = 0
        func feed(_ i: QuitHold.Input) { if m.handle(i) == .quit { quits += 1 } }
        feed(.quitDown(isRepeat: false))
        for _ in 0..<20 { feed(.quitDown(isRepeat: true)) }      // keyboard auto-repeat
        feed(.holdElapsed)
        for _ in 0..<20 { feed(.quitDown(isRepeat: true)) }      // still holding after the quit
        feed(.holdElapsed)                                         // a duplicate timer
        feed(.quitUp)
        XCTAssertEqual(quits, 1, "one hold quits exactly one app")
        XCTAssertEqual(m.state, .idle)
    }

    func testAutoRepeatDuringTheHoldIsSwallowedNotStartedAgain() {
        var m = M()
        _ = m.handle(.quitDown(isRepeat: false))
        for _ in 0..<5 {
            XCTAssertEqual(m.handle(.quitDown(isRepeat: true)), .swallow,
                           "repeats must be consumed (the app must not see ⌘Q) and must not restart the timer")
        }
        XCTAssertEqual(m.state, .holding)
    }

    // MARK: - Property 2: no cascade after a quit

    func testKeepingTheKeyDownAfterAQuitNeverBeginsAnotherHold() {
        var m = M()
        _ = m.handle(.quitDown(isRepeat: false))
        XCTAssertEqual(m.handle(.holdElapsed), .quit)
        XCTAssertEqual(m.state, .fired)
        // The next app is now frontmost and the user is STILL holding ⌘Q.
        for _ in 0..<50 {
            XCTAssertEqual(m.handle(.quitDown(isRepeat: true)), .swallow)
        }
        XCTAssertEqual(m.state, .fired, "auto-repeat must not move fired back to holding")
        XCTAssertEqual(m.handle(.quitUp), .swallow)
        XCTAssertEqual(m.state, .idle)
    }

    // MARK: - Cancelling

    func testEscapeCancelsAHoldAndIsConsumedButOnlyDuringAHold() {
        var m = M()
        XCTAssertEqual(m.handle(.escapeDown), .passThrough, "Esc while idle belongs to the app")
        _ = m.handle(.quitDown(isRepeat: false))
        XCTAssertEqual(m.handle(.escapeDown), .cancelHold(swallowEvent: true), "Esc is the HUD's own 'cancel'")
        XCTAssertEqual(m.state, .cancelled, "the key is still down after Esc, so this is not idle")
        XCTAssertEqual(m.handle(.holdElapsed), .ignore, "the cancelled hold's timer must be inert")
    }

    /// The bug a real keyboard exposes: Esc cancels while Q is STILL held, and auto-repeat keeps
    /// coming. If the machine went back to idle, the first repeat would pass to the app and quit
    /// it — Esc would cancel nothing.
    func testEscapeCancelSurvivesTheAutoRepeatOfTheStillHeldKey() {
        var m = M()
        var reachedTheApp = 0
        var quits = 0
        func feed(_ i: QuitHold.Input) {
            switch m.handle(i) {
            case .passThrough: if case .quitDown = i { reachedTheApp += 1 }
            case .quit: quits += 1
            default: break
            }
        }
        feed(.quitDown(isRepeat: false))
        feed(.escapeDown)                                  // user cancels, Q still down
        for _ in 0..<30 { feed(.quitDown(isRepeat: true)) } // keyboard keeps repeating ⌘Q
        feed(.holdElapsed)                                  // and the old timer fires late
        XCTAssertEqual(reachedTheApp, 0, "an auto-repeat ⌘Q reached the app after Esc — it would quit")
        XCTAssertEqual(quits, 0)
        XCTAssertEqual(m.handle(.quitUp), .swallow, "releasing Q ends the cancelled hold")
        XCTAssertEqual(m.state, .idle)
        // ...and the next deliberate press works again.
        XCTAssertEqual(m.handle(.quitDown(isRepeat: false)), .beginHold)
    }

    func testReleasingCommandAfterACancelEndsItToo() {
        var m = M()
        _ = m.handle(.quitDown(isRepeat: false)); _ = m.handle(.escapeDown)
        XCTAssertEqual(m.handle(.commandReleased), .passThrough)
        XCTAssertEqual(m.state, .idle)
    }

    func testReleasingCommandFirstCancelsWithoutSwallowingTheModifierEvent() {
        var m = M()
        _ = m.handle(.quitDown(isRepeat: false))
        XCTAssertEqual(m.handle(.commandReleased), .cancelHold(swallowEvent: false),
                       "a flagsChanged event must still reach the system")
        XCTAssertEqual(m.state, .idle)
        // The Q key-up then arrives with no Command: harmless, passes through.
        XCTAssertEqual(m.handle(.quitUp), .passThrough)
    }

    func testReleasingCommandAfterAQuitSimplyEndsTheHold() {
        var m = M()
        _ = m.handle(.quitDown(isRepeat: false)); _ = m.handle(.holdElapsed)
        XCTAssertEqual(m.handle(.commandReleased), .passThrough)
        XCTAssertEqual(m.state, .idle)
    }

    // MARK: - Property 1: a lost event must not wedge the machine

    func testAMissedKeyUpHealsOnTheNextRealPress() {
        var m = M()
        // The tap was disabled by timeout mid-hold: the keyUp never arrived.
        _ = m.handle(.quitDown(isRepeat: false))
        XCTAssertEqual(m.state, .holding)
        // Much later the user presses ⌘Q again. It must start a hold, not be swallowed as a "repeat".
        XCTAssertEqual(m.handle(.quitDown(isRepeat: false)), .beginHold)
        XCTAssertEqual(m.handle(.quitUp), .cancelHold(swallowEvent: true))

        // Same after a quit whose keyUp was lost.
        _ = m.handle(.quitDown(isRepeat: false)); _ = m.handle(.holdElapsed)
        XCTAssertEqual(m.state, .fired)
        XCTAssertEqual(m.handle(.quitDown(isRepeat: false)), .beginHold,
                       "a fresh press after a lost keyUp must not stay swallowed forever")
    }

    func testResetForgetsAnUnfinishedHold() {
        var m = M()
        _ = m.handle(.quitDown(isRepeat: false))
        m.reset()
        XCTAssertEqual(m.state, .idle)
        XCTAssertEqual(m.handle(.quitUp), .passThrough, "after a reset nothing of the old hold is left")
        XCTAssertEqual(m.handle(.holdElapsed), .ignore)
    }

    // MARK: - Property 3

    func testAutoRepeatWhileIdleIsNotAHold() {
        var m = M()
        XCTAssertEqual(m.handle(.quitDown(isRepeat: true)), .passThrough,
                       "we never saw this press start (enabled mid-hold, or the tap was re-armed)")
        XCTAssertEqual(m.state, .idle)
    }

    func testIdleQuitUpAndCommandReleasedPassThrough() {
        var m = M()
        XCTAssertEqual(m.handle(.quitUp), .passThrough)
        XCTAssertEqual(m.handle(.commandReleased), .passThrough)
        XCTAssertEqual(m.handle(.holdElapsed), .ignore)
    }

    // MARK: - Exhaustive safety: no input sequence can leave Q permanently swallowed

    /// Whatever garbage arrives, a fresh non-repeat press must always be answered with
    /// `.beginHold` — i.e. the machine can never get into a state that eats the next real press.
    func testNoSequenceOfEventsCanWedgeTheNextRealPress() {
        let all: [QuitHold.Input] = [.quitDown(isRepeat: false), .quitDown(isRepeat: true), .quitUp,
                                     .escapeDown, .commandReleased, .holdElapsed]
        var checked = 0
        // every sequence of up to 4 events from the full alphabet
        func explore(_ prefix: [QuitHold.Input], depth: Int) {
            var m = M()
            for i in prefix { _ = m.handle(i) }
            XCTAssertEqual(m.handle(.quitDown(isRepeat: false)), .beginHold,
                           "after \(prefix) the next real press was not answered with beginHold")
            checked += 1
            guard depth > 0 else { return }
            for i in all { explore(prefix + [i], depth: depth - 1) }
        }
        explore([], depth: 4)
        XCTAssertGreaterThan(checked, 1000, "the exploration collapsed")
    }
}
