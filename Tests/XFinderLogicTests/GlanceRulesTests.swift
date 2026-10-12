import XCTest
import Foundation

/// N4 — the Glance page's rules, with OneNotch's own video frame as one fixture (27 Sep 2026 = "16/8 Lunar").
final class GlanceRulesTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!; return c }
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    func ev(_ title: String, _ start: Date, minutes: Int = 60, allDay: Bool = false, location: String? = nil, notes: String? = nil, url: URL? = nil) -> GlanceEvent {
        GlanceEvent(id: title, title: title, start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: allDay, location: location, notes: notes, url: url, calendarTitle: nil)
    }

    /// Known dates, not a reference app's frame (OneNotch's video shows "16/8" for 27 Sep 2026; the new moon that
    /// month is 11 Sep 10:27 ICT, so 27 Sep is 17/8 — Foundation's Chinese calendar agrees).
    func testTheLunarDateMatchesKnownDates() {
        typealias L = VietnameseLunar
        XCTAssertEqual(L.fromSolar(day: 17, month: 2, year: 2026), .init(day: 1, month: 1, year: 2026, isLeap: false), "Tết Bính Ngọ")
        XCTAssertEqual(L.fromSolar(day: 29, month: 1, year: 2025), .init(day: 1, month: 1, year: 2025, isLeap: false), "Tết Ất Tỵ")
        XCTAssertEqual(L.fromSolar(day: 10, month: 2, year: 2024), .init(day: 1, month: 1, year: 2024, isLeap: false), "Tết Giáp Thìn")
        XCTAssertEqual(L.fromSolar(day: 25, month: 9, year: 2026).day, 15, "Trung thu 2026 is 25 Sep")
        XCTAssertEqual(L.fromSolar(day: 25, month: 9, year: 2026).month, 8)
        XCTAssertEqual(L.fromSolar(day: 27, month: 9, year: 2026), .init(day: 17, month: 8, year: 2026, isLeap: false))
        // 2025 has a leap 6th month in the Vietnamese calendar: 25 Jul 2025 is 1/6+ (nhuận)
        XCTAssertTrue(L.fromSolar(day: 25, month: 7, year: 2025).isLeap)
        XCTAssertEqual(L.fromSolar(day: 25, month: 7, year: 2025).month, 6)
        // The famous divergence: Tết Ất Sửu was 21 Jan 1985 in Vietnam (UTC+7) but 20 Feb 1985 in China (UTC+8)
        XCTAssertEqual(L.fromSolar(day: 21, month: 1, year: 1985, timeZone: 7), .init(day: 1, month: 1, year: 1985, isLeap: false))
        XCTAssertEqual(L.fromSolar(day: 20, month: 2, year: 1985, timeZone: 8), .init(day: 1, month: 1, year: 1985, isLeap: false))
        XCTAssertEqual(GlanceRules.lunarLabel(for: date(2026, 9, 27, 12), timeZone: cal.timeZone), "17/8")
        XCTAssertEqual(GlanceRules.lunarLabel(for: date(2025, 7, 25, 12), timeZone: cal.timeZone), "1/6+")
    }

    func testTheWeekStripIsNineDaysCentredOnToday() {
        let strip = GlanceRules.weekStrip(around: date(2026, 9, 27, 15), calendar: cal)
        XCTAssertEqual(strip.count, 9)
        XCTAssertEqual(cal.component(.day, from: strip[0]), 23)
        XCTAssertEqual(cal.component(.day, from: strip[4]), 27)
        XCTAssertEqual(cal.component(.day, from: strip[8]), 1, "crosses into October")
    }

    func testUpNextPrefersTheEventInProgressThenTheSoonestAndNeverAllDay() {
        let now = date(2026, 9, 27, 14, 30)
        let holiday = ev("Holiday", date(2026, 9, 27), minutes: 1440, allDay: true)
        let standup = ev("Standup", date(2026, 9, 27, 14, 0))           // in progress until 15:00
        let shipment = ev("Shipment", date(2026, 9, 27, 15, 0))
        let past = ev("Breakfast", date(2026, 9, 27, 8, 0))
        XCTAssertEqual(GlanceRules.upNext([holiday, shipment, standup, past], now: now)?.title, "Standup")
        XCTAssertEqual(GlanceRules.upNext([holiday, shipment, past], now: now)?.title, "Shipment")
        XCTAssertNil(GlanceRules.upNext([holiday, past], now: now))
    }

    func testDayEventsSortAllDayFirstAndCanHideThem() {
        let d = date(2026, 9, 27)
        let evs = [ev("Lunch", date(2026, 9, 27, 12)), ev("Holiday", d, minutes: 1440, allDay: true), ev("Standup", date(2026, 9, 27, 9)),
                   ev("Tomorrow", date(2026, 9, 28, 9)), ev("Overnight", date(2026, 9, 26, 23), minutes: 120)]
        XCTAssertEqual(GlanceRules.dayEvents(evs, on: d, hideAllDay: false, calendar: cal).map(\.title), ["Holiday", "Overnight", "Standup", "Lunch"])
        XCTAssertEqual(GlanceRules.dayEvents(evs, on: d, hideAllDay: true, calendar: cal).map(\.title), ["Overnight", "Standup", "Lunch"])
    }

    func testMeetingLinksAreFoundInURLLocationOrNotesForTheKnownHosts() {
        let meet = ev("Sync", date(2026, 9, 27, 10), url: URL(string: "https://meet.google.com/abc-defg-hij"))
        XCTAssertEqual(GlanceRules.meetingURL(in: meet)?.host, "meet.google.com")
        let zoom = ev("Review", date(2026, 9, 27, 10), location: "https://us02web.zoom.us/j/123456789?pwd=x")
        XCTAssertEqual(GlanceRules.meetingURL(in: zoom)?.host, "us02web.zoom.us", "a subdomain of zoom.us counts")
        let teams = ev("1:1", date(2026, 9, 27, 10), notes: "Join here: https://teams.microsoft.com/l/meetup-join/19%3ameeting_x")
        XCTAssertEqual(GlanceRules.meetingURL(in: teams)?.host, "teams.microsoft.com")
        let plain = ev("Dentist", date(2026, 9, 27, 10), location: "12 Nguyễn Huệ", notes: "see https://example.com/map")
        XCTAssertNil(GlanceRules.meetingURL(in: plain), "a link that is not a meeting host is not a meeting")
        XCTAssertFalse(GlanceRules.isMeeting(URL(string: "https://notzoom.us/x")!), "suffix match needs a dot boundary")
    }

    func testCountdownUnitsAndGreeting() {
        let now = date(2026, 9, 27, 14, 30)
        XCTAssertEqual(GlanceRules.countdown(to: date(2026, 9, 27, 14, 55), now: now)?.number, 25)
        XCTAssertEqual(GlanceRules.countdown(to: date(2026, 9, 27, 14, 55), now: now)?.unitKey, "phút")
        XCTAssertEqual(GlanceRules.countdown(to: date(2026, 9, 27, 17, 0), now: now)?.unitKey, "giờ")
        XCTAssertEqual(GlanceRules.countdown(to: date(2026, 9, 29, 9, 0), now: now)?.number, 1)
        XCTAssertNil(GlanceRules.countdown(to: date(2026, 9, 27, 14, 0), now: now), "started ⇒ no countdown")
        XCTAssertEqual(GlanceRules.greetingKey(hour: 9), "Chào buổi sáng.")
        XCTAssertEqual(GlanceRules.greetingKey(hour: 15), "Chào buổi chiều.")
        XCTAssertEqual(GlanceRules.greetingKey(hour: 23), "Chào buổi tối.")
    }

    func testDotsMarkOnlyDaysWithEvents() {
        let strip = GlanceRules.weekStrip(around: date(2026, 9, 27, 12), calendar: cal)
        let dots = GlanceRules.daysWithEvents([ev("A", date(2026, 9, 24, 9)), ev("B", date(2026, 9, 30, 9))], strip: strip, calendar: cal)
        XCTAssertEqual(Set(dots.map { cal.component(.day, from: $0) }), [24, 30])
    }

    func testGreetingKeysAreInTheStore() throws {
        let store = try L10nFixture.load()
        for h in [9, 15, 23] { XCTAssertNotNil(store.entries[GlanceRules.greetingKey(hour: h)]) }
    }
}
