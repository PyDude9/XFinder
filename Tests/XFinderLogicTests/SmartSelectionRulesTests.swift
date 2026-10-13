import XCTest
import Foundation
import CoreGraphics

/// Smart Selection E1 — gate, actions, the show/hide machine, and the anchor. The event sequences replay what the
/// passive probe measured (one notification per drag step, lengths 1 → 11 → 14 → 17 → 20).
final class SmartSelectionRulesTests: XCTestCase {
    typealias R = SmartSelectionRules
    let hcm = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    let october = Date(timeIntervalSince1970: 1_791_885_600)   // 2026-10-13 10:00 UTC
    func noDate(_: String) -> R.DateMatch? { nil }

    // MARK: Gate

    func testGate() {
        func ok(_ t: String, min: Int = 2, bid: String? = "com.google.Chrome", name: String? = "Google Chrome",
                excluded: Set<String> = []) -> Bool {
            R.shouldConsider(text: t, minLength: min, frontBundleID: bid, frontAppName: name, ownBundleID: "com.xfinder.app", excluded: excluded)
        }
        XCTAssertTrue(ok("hello"))
        XCTAssertFalse(ok("a"), "below the minimum length")
        XCTAssertTrue(ok("a", min: 1))
        XCTAssertFalse(ok("   \n  "), "whitespace only")
        XCTAssertFalse(ok(String(repeating: "x", count: R.maxLength + 1)))
        XCTAssertFalse(ok("hello", bid: "com.xfinder.app"), "never on XFinder's own windows")
        XCTAssertFalse(ok("hello", bid: nil))
        XCTAssertFalse(ok("hello", excluded: ["com.google.Chrome"]))
        XCTAssertFalse(ok("hello", bid: "com.1password.1password", name: "1Password"), "password managers, by bundle id")
        XCTAssertFalse(ok("hello", bid: "com.apple.Passwords", name: "Passwords"))
        XCTAssertFalse(ok("hello", bid: "com.example.vault", name: "Bitwarden"), "…or by app name")
    }

    func testExcludedListCodec() {
        XCTAssertEqual(R.parseExcluded(" com.a , com.b,,com.a "), ["com.a", "com.b"])
        XCTAssertEqual(R.parseExcluded(nil), [])
        XCTAssertEqual(R.encodeExcluded(["com.b", "com.a"]), "com.a,com.b")
    }

    // MARK: Actions

    func testActionsPerKindOfSelection() throws {
        let unit = R.actions(for: "5 km", now: october, localZone: hcm, detectDate: noDate)
        guard case .unit(let u)? = unit.first else { return XCTFail("\(unit)") }
        XCTAssertEqual(u.target.unit, .mile)
        XCTAssertTrue(unit.contains(.translate), "letters ⇒ translate is offered too, after the specific action")

        let tz = R.actions(for: "3pm PST", now: october, localZone: hcm, detectDate: R.detectDate)
        XCTAssertTrue(tz.contains { if case .time = $0 { return true } else { return false } })
        XCTAssertFalse(tz.contains { if case .calendar = $0 { return true } else { return false } },
                       "a time-zone conversion is not also an event for 15:00 local")

        XCTAssertEqual(R.actions(for: "12 * (3 + 4)", now: october, localZone: hcm, detectDate: noDate), [.arithmetic(value: 84)])
        XCTAssertEqual(R.actions(for: "10:00 GMT+7", now: october, localZone: hcm, detectDate: noDate), [.translate],
                       "a conversion to the same local time is not offered")
        XCTAssertEqual(R.actions(for: "1234", now: october, localZone: hcm, detectDate: noDate), [], "a bare number has nothing to do")
    }

    func testArithmeticKeepsDatesPhonesAndSignedNumbersOut() {
        XCTAssertEqual(R.arithmetic("2+2"), 4)
        XCTAssertEqual(R.arithmetic("10 - 3"), 7, "a spaced minus is subtraction")
        XCTAssertEqual(R.arithmetic("100 / 8"), 12.5)
        for no in ["15/10/2026", "2026-10-15", "090-123-4567", "+84", "-3", "10-3", "3 apples + 2", "1/0 + 1"] {
            XCTAssertNil(R.arithmetic(no), no)
        }
    }

    func testCalendarFromTheRealDetector() throws {
        let a = R.actions(for: "Meeting on Friday at 9am", now: october, localZone: hcm)
        guard let cal = a.first(where: { if case .calendar = $0 { return true } else { return false } }),
              case .calendar(let title, _, let hasTime) = cal else { return XCTFail("\(a)") }
        XCTAssertEqual(title, "Meeting", "the date words and the connector are cut out")
        XCTAssertTrue(hasTime)

        let vi = R.actions(for: "15 tháng 10 năm 2026", now: october, localZone: hcm)
        guard case .calendar(let t2, _, let h2)? = vi.first(where: { if case .calendar = $0 { return true } else { return false } })
        else { return XCTFail("Vietnamese date not offered: \(vi)") }
        XCTAssertEqual(t2, "")
        XCTAssertFalse(h2, "a date without a time is an all-day event, not noon")
        XCTAssertNil(R.actions(for: "15/10/2026", now: october, localZone: hcm).first { if case .arithmetic = $0 { return true } else { return false } },
                     "a slash date is never offered as a division")
    }

    func testTimeOfDayAndTitleRules() {
        for yes in ["Friday at 9am", "tomorrow 14:00", "thứ Sáu 9 giờ", "15h30", "noon", "chiều mai"] { XCTAssertTrue(R.hasTimeOfDay(yes), yes) }
        for no in ["Friday", "15 Oct 2026", "15/10/2026", "tomorrow"] { XCTAssertFalse(R.hasTimeOfDay(no), no) }
        XCTAssertEqual(R.eventTitle(selection: "Họp nhóm lúc 9 giờ thứ Sáu", matched: "9 giờ thứ Sáu"), "Họp nhóm")
        XCTAssertEqual(R.eventTitle(selection: "Friday", matched: "Friday"), "")
    }

    func testCalculationResultFormatting() {
        XCTAssertEqual(R.formatResult(84, decimalComma: false), "84")
        XCTAssertEqual(R.formatResult(3.5, decimalComma: true), "3,5")
        XCTAssertEqual(R.formatResult(1_234_567.25, decimalComma: false), "1,234,567.25")
        XCTAssertEqual(R.formatResult(1_234_567.25, decimalComma: true), "1.234.567,25")
        XCTAssertEqual(R.formatResult(1.0 / 3.0, decimalComma: false), "0.333333")
        XCTAssertEqual(R.formatResult(-0.0000001, decimalComma: false), "0", "never -0")
    }

    /// The notices reach the screen through `L10n.t(variable)`; resolve each one in the shipped store.
    func testEveryNoticeKeyIsTranslated() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = (root["entries"] as? [String: Any]) ?? root
        XCTAssertEqual(R.NoticeKey.all.count, 5, "a collapsed list would pass as a clean one")
        for k in R.NoticeKey.all {
            let en = (entries[k] as? [String: Any])?["en"] as? String
            XCTAssertFalse((en ?? "").isEmpty, "notice not translated: \(k)")
        }
    }

    /// The measured failure: -25204 on an app still launching. Retry that, a few times; never retry a final error.
    func testRegistrationRetriesOnlyCannotCompleteAndOnlyAFewTimes() {
        XCTAssertEqual(R.registrationRetryDelay(attempt: 0, error: -25204), 0.5)
        XCTAssertEqual(R.registrationRetryDelay(attempt: 2, error: -25204), 3.0)
        XCTAssertNil(R.registrationRetryDelay(attempt: 3, error: -25204), "gives up after three retries")
        for final in [Int32(-25207), -25211, -25202, 0] {
            XCTAssertNil(R.registrationRetryDelay(attempt: 0, error: final), "error \(final) is not retried")
        }
        XCTAssertEqual(R.registrationRetryDelays.reduce(0, +), 5.0, "about five seconds of patience after a launch")
    }

    // MARK: The show/hide machine

    /// The measured drag: one change per step, the mouse-up 50 ms after the last one, then quiet.
    func testADragShowsOnceAfterItSettlesAtTheMouseUpPoint() {
        var w = R.Watch()
        var shown: [CGPoint] = []
        var t = 10.0
        for len in [1, 11, 14, 17, 20] {
            for fx in R.reduce(&w, .selectionChanged(length: len, at: t), minLength: 2) { if case .show(let p) = fx { shown.append(p) } }
            t += 0.05
        }
        let lastChange = t - 0.05
        _ = R.reduce(&w, .mouseUp(CGPoint(x: 400, y: 300), at: lastChange + 0.05), minLength: 2)
        XCTAssertEqual(R.reduce(&w, .settle(at: lastChange + 0.1), minLength: 2), [], "too early: still inside the settle delay")
        XCTAssertEqual(R.reduce(&w, .settle(at: lastChange + 0.36), minLength: 2), [.show(at: CGPoint(x: 400, y: 300))])
        XCTAssertEqual(R.reduce(&w, .settle(at: lastChange + 0.5), minLength: 2), [], "shown once, not again")
        XCTAssertTrue(shown.isEmpty, "nothing showed during the drag")
    }

    func testAKeyboardSelectionNeverShows() {
        var w = R.Watch()
        _ = R.reduce(&w, .mouseUp(CGPoint(x: 1, y: 1), at: 0), minLength: 2)            // an old click
        _ = R.reduce(&w, .selectionChanged(length: 12, at: 30), minLength: 2)            // ⇧→ much later
        XCTAssertEqual(R.reduce(&w, .settle(at: 31), minLength: 2), [], "no mouse-up near the change")
    }

    func testChangingTheSelectionHidesTheBadgeAndAShortOneDoesNotShow() {
        var w = R.Watch()
        _ = R.reduce(&w, .selectionChanged(length: 8, at: 0), minLength: 2)
        _ = R.reduce(&w, .mouseUp(CGPoint(x: 5, y: 5), at: 0.05), minLength: 2)
        XCTAssertEqual(R.reduce(&w, .settle(at: 0.4), minLength: 2), [.show(at: CGPoint(x: 5, y: 5))])
        XCTAssertEqual(R.reduce(&w, .selectionChanged(length: 1, at: 2), minLength: 2), [.hide], "a click collapses the selection")
        _ = R.reduce(&w, .mouseUp(CGPoint(x: 9, y: 9), at: 2.02), minLength: 2)
        XCTAssertEqual(R.reduce(&w, .settle(at: 2.5), minLength: 2), [], "1 character is below the minimum")
        XCTAssertEqual(R.reduce(&w, .dismiss, minLength: 2), [])
    }

    func testAMouseUpBeforeALateChangeStillCounts() {
        var w = R.Watch()
        _ = R.reduce(&w, .mouseUp(CGPoint(x: 7, y: 7), at: 5.0), minLength: 2)
        XCTAssertEqual(R.reduce(&w, .selectionChanged(length: 6, at: 5.2), minLength: 2), [.armSettle(at: 5.5)])
        // 0.35 s after the mouse-up but only 0.15 s after the last change: the selection may still be moving.
        XCTAssertEqual(R.reduce(&w, .settle(at: 5.35), minLength: 2), [], "must wait for the SELECTION to settle, not only the mouse")
        XCTAssertEqual(R.reduce(&w, .settle(at: 5.5), minLength: 2), [.show(at: CGPoint(x: 7, y: 7))])
        XCTAssertEqual(R.reduce(&w, .dismiss, minLength: 2), [.hide])
    }

    // MARK: Anchor

    func testAnchorUsesARealAXRectElseTheMouseUp() {
        let up = CGPoint(x: 300, y: 500)
        XCTAssertEqual(R.anchor(axBounds: CGRect(x: 0, y: 1117, width: 0, height: 0), mouseUp: up, primaryScreenHeight: 1117), up,
                       "the measured degenerate rect from Chrome/Electron")
        XCTAssertEqual(R.anchor(axBounds: nil, mouseUp: up, primaryScreenHeight: 1117), up)
        XCTAssertEqual(R.anchor(axBounds: CGRect(x: 100, y: 200, width: 80, height: 18), mouseUp: up, primaryScreenHeight: 1117),
                       CGPoint(x: 180, y: 1117 - 218), "AX top-left flipped to AppKit bottom-left")
    }

    func testBadgeStaysOnScreen() {
        let vis = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        let f = R.badgeFrame(anchor: CGPoint(x: 1727, y: 5), visible: vis)
        XCTAssertTrue(vis.contains(f), "\(f) leaves the visible frame")
        XCTAssertEqual(R.badgeFrame(anchor: CGPoint(x: 100, y: 500), visible: vis).origin, CGPoint(x: 106, y: 470))
    }
}
