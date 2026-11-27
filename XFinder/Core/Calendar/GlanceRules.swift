import Foundation

/// N4 (2026-10-13) — the "Glance" page at the notch (OneNotch's calendar page, measured from its onboarding video:
/// weekday · lunar date · a nine-day strip with dots · "Good afternoon. Up next: Shipment · Lin at 15:00"), re-derived
/// for XFinder. Pure: every rule about WHAT to show is here; `CalendarGlanceMonitor` (EventKit) only fetches.
///
/// Job: *"I am at the notch — what is next today, and when; is there a meeting link to join?"*
struct GlanceEvent: Equatable, Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var url: URL?
    var calendarTitle: String?
    /// A reminder with a due time (EventKit reminders), listed beside events.
    var isReminder = false
}

enum GlanceRules {
    /// The strip the page draws: `days` centred on `day` (the video shows 23…1 around the 27th = 9 days).
    static func weekStrip(around day: Date, days: Int = 9, calendar: Calendar = .current) -> [Date] {
        let half = days / 2
        let start = calendar.startOfDay(for: day)
        return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0 - half, to: start) }
    }

    /// The Vietnamese lunar date as "day/month" (a leap month gets "+"). NOT Foundation's `.chinese` calendar:
    /// ICU computes it on Beijing time (UTC+8) whatever `timeZone` is set, while the Vietnamese calendar is reckoned
    /// at UTC+7 — the two disagree by a day (or, famously, a whole month: Tết 1985 fell on 21 Jan in Vietnam and
    /// 20 Feb in China). `VietnameseLunar` is the standard astronomical algorithm (Hồ Ngọc Đức) evaluated at UTC+7.
    /// (OneNotch's onboarding frame says "16/8" for 27 Sep 2026; the new moon that month is 11 Sep 10:27 ICT, so
    /// 27 Sep is 17/8 in both calendars — the frame is marketing, not a fixture.)
    static func lunarLabel(for day: Date, timeZone: TimeZone = .current) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = timeZone
        let comps = c.dateComponents([.year, .month, .day], from: day)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return "" }
        let l = VietnameseLunar.fromSolar(day: d, month: m, year: y)
        return "\(l.day)/\(l.month)\(l.isLeap ? "+" : "")"
    }

    /// Events on `day`, in start order; all-day ones first unless hidden.
    static func dayEvents(_ events: [GlanceEvent], on day: Date, hideAllDay: Bool, calendar: Calendar = .current) -> [GlanceEvent] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let onDay = events.filter { $0.start < dayEnd && $0.end > dayStart && !(hideAllDay && $0.isAllDay) }
        return onDay.sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return a.start < b.start
        }
    }

    /// The thing to say after the greeting: the event in progress, else the next one to start — never an
    /// all-day entry (it has no "at 15:00"), never one already over.
    static func upNext(_ events: [GlanceEvent], now: Date) -> GlanceEvent? {
        events.filter { !$0.isAllDay && $0.end > now }.min { a, b in
            let aLive = a.start <= now, bLive = b.start <= now
            if aLive != bLive { return aLive }          // in progress beats upcoming
            return a.start < b.start
        }
    }

    /// Store key for the greeting (the view wraps it in `L10n.t`).
    static func greetingKey(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Chào buổi sáng."
        case 12..<18: return "Chào buổi chiều."
        default: return "Chào buổi tối."
        }
    }

    /// Hosts that mean "a meeting you can join" — the set OneNotch's strings name (meet.google.com, zoom, teams,
    /// whereby, jitsi, zoomgov). The link is looked for in the event URL, then the location, then the notes.
    static let meetingHosts = ["meet.google.com", "zoom.us", "zoomgov.com", "teams.microsoft.com", "teams.live.com", "whereby.com", "meet.jit.si"]

    static func meetingURL(in e: GlanceEvent) -> URL? {
        if let u = e.url, isMeeting(u) { return u }
        for text in [e.location, e.notes].compactMap({ $0 }) {
            if let u = firstMeetingLink(in: text) { return u }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func firstMeetingLink(in text: String) -> URL? {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let ns = text as NSString
        for m in det.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if let u = m.url, isMeeting(u) { return u }
        }
        return nil
    }

    /// "in 25 min" / "in 2 h" as (fragmentKey, number, unitKey); nil once started.
    static func countdown(to start: Date, now: Date) -> (number: Int, unitKey: String)? {
        let s = start.timeIntervalSince(now)
        guard s > 0 else { return nil }
        if s < 3600 { return (max(1, Int((s / 60).rounded(.up))), "phút") }
        if s < 86_400 { return (Int((s / 3600).rounded(.down)), "giờ") }
        return (Int((s / 86_400).rounded(.down)), "ngày")
    }

    /// Days in the strip that have at least one event (the dots under the numbers).
    static func daysWithEvents(_ events: [GlanceEvent], strip: [Date], calendar: Calendar = .current) -> Set<Date> {
        Set(strip.filter { !dayEvents(events, on: $0, hideAllDay: false, calendar: calendar).isEmpty })
    }

    /// One cell in a calendar month grid. `inMonth == false` marks leading/trailing padding days.
    struct MonthCell: Equatable, Hashable, Sendable {
        let date: Date
        let inMonth: Bool
    }

    /// Builds a 7-column month grid (starting on `calendar.firstWeekday`) covering every day of `month`.
    /// Pure Foundation so month/day agenda views and tests share identical grid geometry.
    static func monthGrid(for month: Date, calendar: Calendar = .current) -> [MonthCell] {
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard let firstOfMonth = calendar.date(from: comps),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [MonthCell] = []
        if leading > 0 {
            for offset in stride(from: -leading, to: 0, by: 1) {
                if let d = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                    cells.append(MonthCell(date: d, inMonth: false))
                }
            }
        }
        for dayOffset in 0..<dayRange.count {
            if let d = calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth) {
                cells.append(MonthCell(date: d, inMonth: true))
            }
        }
        let remainder = cells.count % 7
        if remainder != 0, let last = cells.last?.date {
            let trailing = 7 - remainder
            for offset in 1...trailing {
                if let d = calendar.date(byAdding: .day, value: offset, to: last) {
                    cells.append(MonthCell(date: d, inMonth: false))
                }
            }
        }
        return cells
    }
}

/// Solar → Vietnamese lunar date, the astronomical method published by Hồ Ngọc Đức (new moons and the sun's
/// longitude from Jean Meeus's formulae, months reckoned at `timeZone` hours east of UTC — 7 for Vietnam). Pure
/// integer/double arithmetic, no Foundation calendar, so the result is the same on every machine and locale.
enum VietnameseLunar {
    struct LunarDate: Equatable { var day: Int; var month: Int; var year: Int; var isLeap: Bool }

    static func fromSolar(day dd: Int, month mm: Int, year yy: Int, timeZone tz: Double = 7) -> LunarDate {
        let dayNumber = jdFromDate(dd, mm, yy)
        let k = Int(floor((Double(dayNumber) - 2415021.076998695) / 29.530588853))
        var monthStart = newMoonDay(k + 1, tz)
        if monthStart > dayNumber { monthStart = newMoonDay(k, tz) }
        var a11 = lunarMonth11(yy, tz)
        var b11 = a11
        var lunarYear: Int
        if a11 >= monthStart {
            lunarYear = yy
            a11 = lunarMonth11(yy - 1, tz)
        } else {
            lunarYear = yy + 1
            b11 = lunarMonth11(yy + 1, tz)
        }
        let lunarDay = dayNumber - monthStart + 1
        let diff = Int(floor(Double(monthStart - a11) / 29))
        var leap = false
        var lunarMonth = diff + 11
        if b11 - a11 > 365 {
            let leapMonthDiff = leapMonthOffset(a11, tz)
            if diff >= leapMonthDiff {
                lunarMonth = diff + 10
                if diff == leapMonthDiff { leap = true }
            }
        }
        if lunarMonth > 12 { lunarMonth -= 12 }
        if lunarMonth >= 11 && diff < 4 { lunarYear -= 1 }
        return LunarDate(day: lunarDay, month: lunarMonth, year: lunarYear, isLeap: leap)
    }

    /// Julian day number of a Gregorian (or, before 1582-10-15, Julian) date.
    static func jdFromDate(_ dd: Int, _ mm: Int, _ yy: Int) -> Int {
        let a = (14 - mm) / 12
        let y = yy + 4800 - a
        let m = mm + 12 * a - 3
        var jd = dd + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        if jd < 2299161 { jd = dd + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083 }
        return jd
    }

    /// Julian day (fractional, UT) of the k-th new moon after 1900-01-01.
    static func newMoon(_ k: Int) -> Double {
        let kk = Double(k)
        let T = kk / 1236.85, T2 = T * T, T3 = T2 * T
        let dr = Double.pi / 180
        var jd1 = 2415020.75933 + 29.53058868 * kk + 0.0001178 * T2 - 0.000000155 * T3
        jd1 += 0.00033 * sin((166.56 + 132.87 * T - 0.009173 * T2) * dr)
        let M = 359.2242 + 29.10535608 * kk - 0.0000333 * T2 - 0.00000347 * T3
        let Mpr = 306.0253 + 385.81691806 * kk + 0.0107306 * T2 + 0.00001236 * T3
        let F = 21.2964 + 390.67050646 * kk - 0.0016528 * T2 - 0.00000239 * T3
        var c1 = (0.1734 - 0.000393 * T) * sin(M * dr) + 0.0021 * sin(2 * dr * M)
        c1 -= 0.4068 * sin(Mpr * dr) + 0.0161 * sin(dr * 2 * Mpr)
        c1 -= 0.0004 * sin(dr * 3 * Mpr)
        c1 += 0.0104 * sin(dr * 2 * F) - 0.0051 * sin(dr * (M + Mpr))
        c1 -= 0.0074 * sin(dr * (M - Mpr)) + 0.0004 * sin(dr * (2 * F + M))
        c1 -= 0.0004 * sin(dr * (2 * F - M)) - 0.0006 * sin(dr * (2 * F + Mpr))
        c1 += 0.0010 * sin(dr * (2 * F - Mpr)) + 0.0005 * sin(dr * (2 * Mpr + M))
        let deltat: Double = T < -11
            ? 0.001 + 0.000839 * T + 0.0002261 * T2 - 0.00000845 * T3 - 0.000000081 * T * T3
            : -0.000278 + 0.000265 * T + 0.000262 * T2
        return jd1 + c1 - deltat
    }

    /// Apparent longitude of the sun at Julian day `jdn`, in radians 0…2π.
    static func sunLongitude(_ jdn: Double) -> Double {
        let T = (jdn - 2451545.0) / 36525, T2 = T * T
        let dr = Double.pi / 180
        let M = 357.52910 + 35999.05030 * T - 0.0001559 * T2 - 0.00000048 * T * T2
        let L0 = 280.46645 + 36000.76983 * T + 0.0003032 * T2
        let DL = (1.914600 - 0.004817 * T - 0.000014 * T2) * sin(dr * M) + (0.019993 - 0.000101 * T) * sin(dr * 2 * M) + 0.000290 * sin(dr * 3 * M)
        var L = (L0 + DL) * dr
        L -= Double.pi * 2 * floor(L / (Double.pi * 2))
        return L
    }

    /// Which of the 12 major solar terms the sun is in at the start of local day `dayNumber`.
    static func sunLongitudeIndex(_ dayNumber: Int, _ tz: Double) -> Int {
        Int(floor(sunLongitude(Double(dayNumber) - 0.5 - tz / 24) / Double.pi * 6))
    }

    static func newMoonDay(_ k: Int, _ tz: Double) -> Int { Int(floor(newMoon(k) + 0.5 + tz / 24)) }

    /// The local day of the new moon that begins lunar month 11 of `yy` (the month holding the winter solstice).
    static func lunarMonth11(_ yy: Int, _ tz: Double) -> Int {
        let off = jdFromDate(31, 12, yy) - 2415021
        let k = Int(floor(Double(off) / 29.530588853))
        var nm = newMoonDay(k, tz)
        if sunLongitudeIndex(nm, tz) >= 9 { nm = newMoonDay(k - 1, tz) }
        return nm
    }

    /// Offset (in months after month 11) of the leap month in a 13-month lunar year.
    static func leapMonthOffset(_ a11: Int, _ tz: Double) -> Int {
        let k = Int(floor((Double(a11) - 2415021.076998695) / 29.530588853 + 0.5))
        var last = 0
        var i = 1
        var arc = sunLongitudeIndex(newMoonDay(k + i, tz), tz)
        repeat {
            last = arc
            i += 1
            arc = sunLongitudeIndex(newMoonDay(k + i, tz), tz)
        } while arc != last && i < 14
        return i - 1
    }
}

/// §3b #33 — "nhắc họp": an alert under the notch before a timed event (OneNotch: "Show alerts under the notch for
/// upcoming events", a lead-time picker, snooze, a sound). Pure: which event is next to alert, and when.
enum MeetingAlertRules {
    static let leadChoices = [1, 5, 10, 15]
    static let defaultLead = 5
    /// Headline keys of the notice — they reach the screen through `L10n.t(item.titleKey)`, so a test resolves them.
    static let eventHeadlineKey = "Sắp đến giờ"
    static let reminderHeadlineKey = "Đến giờ lời nhắc"
    static let startingNowKey = "đang bắt đầu"
    static let snoozeMinutes = 5
    /// An event that started less than this long ago still gets its alert (the Mac just woke, the store just refreshed).
    static let lateGrace: TimeInterval = 60

    /// One occurrence of an event. EventKit gives every occurrence of a repeating event the SAME identifier, so the
    /// start time is part of the key — otherwise alerting Monday's stand-up would silence every later Monday.
    static func key(_ e: GlanceEvent) -> String { "\(e.id)@\(Int(e.start.timeIntervalSince1970))" }

    struct Plan: Equatable {
        let key: String
        let fireAt: Date
    }

    /// The next alert to fire: timed events only (never all-day), reminders only when asked, not yet alerted unless
    /// snoozed; fire at `start − lead` (or the snooze time), never in the past. nil ⇒ nothing to schedule.
    static func next(events: [GlanceEvent], now: Date, leadMinutes: Int, alerted: Set<String>,
                     snoozedUntil: [String: Date], includeReminders: Bool) -> Plan? {
        var best: (plan: Plan, start: Date)?
        for e in events where !e.isAllDay && (includeReminders || !e.isReminder) {
            let k = key(e)
            let fire: Date
            if let s = snoozedUntil[k] {
                guard s < e.end else { continue }                     // snoozed past the end: nothing to join any more
                fire = s
            } else {
                guard !alerted.contains(k), e.start > now.addingTimeInterval(-lateGrace) else { continue }
                fire = e.start.addingTimeInterval(-TimeInterval(max(0, leadMinutes)) * 60)
            }
            let plan = Plan(key: k, fireAt: max(fire, now))
            if best == nil || plan.fireAt < best!.plan.fireAt || (plan.fireAt == best!.plan.fireAt && e.start < best!.start) {
                best = (plan, e.start)
            }
        }
        return best?.plan
    }

    /// Whole minutes left before the start, rounded UP (an alert never says "0" while there is time), ≥ 0.
    static func minutesUntil(_ start: Date, now: Date) -> Int {
        max(0, Int((start.timeIntervalSince(now) / 60).rounded(.up)))
    }
}
