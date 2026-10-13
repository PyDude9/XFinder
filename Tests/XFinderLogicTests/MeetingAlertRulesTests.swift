import XCTest

/// §3b #33 — when the notch alerts before an event.
final class MeetingAlertRulesTests: XCTestCase {
    typealias R = MeetingAlertRules
    let now = Date(timeIntervalSince1970: 1_791_885_600)   // 2026-10-13 10:00 UTC
    func ev(_ id: String, inMinutes m: Double, length: Double = 30, allDay: Bool = false, reminder: Bool = false) -> GlanceEvent {
        GlanceEvent(id: id, title: id, start: now.addingTimeInterval(m * 60), end: now.addingTimeInterval((m + length) * 60),
                    isAllDay: allDay, location: nil, notes: nil, url: nil, calendarTitle: nil, isReminder: reminder)
    }

    func testFiresLeadMinutesBeforeTheEarliestTimedEvent() throws {
        let events = [ev("later", inMinutes: 90), ev("soon", inMinutes: 30), ev("allday", inMinutes: 10, allDay: true)]
        let plan = try XCTUnwrap(R.next(events: events, now: now, leadMinutes: 5, alerted: [], snoozedUntil: [:], includeReminders: true))
        XCTAssertEqual(plan.key, R.key(events[1]), "all-day events never alert")
        XCTAssertEqual(plan.fireAt, now.addingTimeInterval(25 * 60))
    }

    func testInsideTheLeadWindowFiresNowNeverInThePast() throws {
        let plan = try XCTUnwrap(R.next(events: [ev("a", inMinutes: 2)], now: now, leadMinutes: 5, alerted: [], snoozedUntil: [:], includeReminders: true))
        XCTAssertEqual(plan.fireAt, now)
    }

    func testAnAlertedOccurrenceIsSilentUntilSnoozed() throws {
        let e = ev("standup", inMinutes: 3)
        XCTAssertNil(R.next(events: [e], now: now, leadMinutes: 5, alerted: [R.key(e)], snoozedUntil: [:], includeReminders: true))
        let snooze = now.addingTimeInterval(5 * 60)
        let plan = try XCTUnwrap(R.next(events: [e], now: now, leadMinutes: 5, alerted: [R.key(e)], snoozedUntil: [R.key(e): snooze], includeReminders: true))
        XCTAssertEqual(plan.fireAt, snooze)
        let ended = now.addingTimeInterval(40 * 60)
        XCTAssertNil(R.next(events: [e], now: now, leadMinutes: 5, alerted: [R.key(e)], snoozedUntil: [R.key(e): ended], includeReminders: true),
                     "a snooze past the end of the event has nothing left to join")
    }

    func testEveryOccurrenceOfARepeatingEventHasItsOwnKey() {
        var tomorrow = ev("standup", inMinutes: 3); tomorrow.start.addTimeInterval(86_400); tomorrow.end.addTimeInterval(86_400)
        XCTAssertNotEqual(R.key(ev("standup", inMinutes: 3)), R.key(tomorrow), "alerting today must not silence tomorrow")
    }

    func testOldEventsAndRemindersFollowTheRules() {
        XCTAssertNil(R.next(events: [ev("gone", inMinutes: -5)], now: now, leadMinutes: 5, alerted: [], snoozedUntil: [:], includeReminders: true),
                     "started five minutes ago: too late for an alert")
        XCTAssertNotNil(R.next(events: [ev("just", inMinutes: -0.5)], now: now, leadMinutes: 5, alerted: [], snoozedUntil: [:], includeReminders: true),
                        "started 30 s ago (the Mac just woke): still alerted")
        let r = ev("pay rent", inMinutes: 20, reminder: true)
        XCTAssertNil(R.next(events: [r], now: now, leadMinutes: 5, alerted: [], snoozedUntil: [:], includeReminders: false))
        XCTAssertNotNil(R.next(events: [r], now: now, leadMinutes: 5, alerted: [], snoozedUntil: [:], includeReminders: true))
    }

    func testMinutesRoundUpAndNeverGoNegative() {
        XCTAssertEqual(R.minutesUntil(now.addingTimeInterval(61), now: now), 2)
        XCTAssertEqual(R.minutesUntil(now.addingTimeInterval(240), now: now), 4)
        XCTAssertEqual(R.minutesUntil(now.addingTimeInterval(-30), now: now), 0)
        XCTAssertEqual(R.leadChoices, [1, 5, 10, 15])
        XCTAssertTrue(R.leadChoices.contains(R.defaultLead))
    }

    func testNoticeKeysAreTranslated() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = (root["entries"] as? [String: Any]) ?? root
        for k in [R.eventHeadlineKey, R.reminderHeadlineKey, R.startingNowKey] {
            XCTAssertFalse((((entries[k] as? [String: Any])?["en"] as? String) ?? "").isEmpty, "not translated: \(k)")
        }
    }
}
