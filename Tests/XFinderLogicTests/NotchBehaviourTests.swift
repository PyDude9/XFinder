import XCTest
import Foundation

/// B7: the settings that tune the notch surface. Pure rules only; the window's `sharingType` is AppKit
/// and is measured on the installed app instead (kCGWindowSharingState).
final class NotchBehaviourTests: XCTestCase {
    typealias S = NotchSurfaceMachine.Settings

    func testHoverSpeedMapsToDwellAndUnknownReadsAsMedium() {
        XCTAssertEqual(S.hoverDwell(forSpeed: "fast"), 0.06)
        XCTAssertEqual(S.hoverDwell(forSpeed: "medium"), 0.14)
        XCTAssertEqual(S.hoverDwell(forSpeed: "slow"), 0.35)
        XCTAssertEqual(S.hoverDwell(forSpeed: "turbo"), 0.14, "a value from a future build must not read as 0 s")
        XCTAssertEqual(S.hoverDwell(forSpeed: ""), 0.14)
        XCTAssertEqual(S.hoverDwell(forSpeed: "medium"), S().hoverDwell, "the picker's default equals the machine's default")
        XCTAssertLessThan(S.hoverDwell(forSpeed: "fast"), S.hoverDwell(forSpeed: "slow"))
    }

    func testDwellGatesTheHoverInTheMachine() {
        var s = S(); s.hoverDwell = S.hoverDwell(forSpeed: "slow")
        var m = NotchSurfaceMachine.Machine(); m.itemCount = 1
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        m.handle(.hoverInZone(since: t0), settings: s, now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(m.state, .collapsed, "0.3 s is not enough on 'slow'")
        m.handle(.hoverInZone(since: t0), settings: s, now: t0.addingTimeInterval(0.6))
        XCTAssertEqual(m.state, .peek)
    }
}
