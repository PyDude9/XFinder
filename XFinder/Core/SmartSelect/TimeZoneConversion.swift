import Foundation

/// Smart Selection E3 — "the user selected `3pm PST`; show what time that is here". Pure: the reference date and the
/// local zone are passed in.
///
/// Measured before writing (macOS 27): `TimeZone(abbreviation:)` maps by REGION and follows daylight time — `EST`
/// returned America/New_York at UTC−4 in October, although EST is defined as UTC−5; `CST` returned Chicago (it is also
/// China Standard Time) and `IST` Kolkata (also Israel / Ireland). So this file keeps its own table:
/// * explicit standard/daylight abbreviations are FIXED offsets (`EST` = UTC−5, `EDT` = UTC−4) — the result carries the
///   offset used, and a note when the region is on the other one at that moment ("New York is on UTC−4 now");
/// * generic ones (`ET`, `PT`, …) follow the region's rules on that date;
/// * ambiguous ones (`CST`, `IST`, `BST`, `AST`, `GST`) are refused rather than guessed.
/// The WHOLE selection must be one clock time plus one zone, ≤ `maxLength` characters.
enum TimeZoneConversion {

    static let maxLength = 40

    struct Zone: Equatable {
        /// Seconds east of UTC for a fixed abbreviation; nil for a region-following one.
        let fixedOffset: Int?
        /// IANA region used for the daylight note (fixed) or for the offset itself (region-following).
        let regionID: String?
    }

    struct Result: Equatable {
        /// What the user wrote for the zone, upper-cased (`PST`, `UTC+7`).
        let zoneLabel: String
        /// The offset actually used, seconds east of UTC.
        let sourceOffset: Int
        let sourceHour: Int
        let sourceMinute: Int
        let instant: Date
        let localOffset: Int
        let localHour: Int
        let localMinute: Int
        /// Local calendar day minus the source calendar day: −1, 0 or +1.
        let dayShift: Int
        /// Set when a fixed abbreviation disagrees with its region at that moment (EST written while New York is on EDT).
        let regionNote: RegionNote?
        /// Same wall-clock time here — Smart Selection does not offer a conversion that changes nothing.
        var isSameAsLocal: Bool { sourceOffset == localOffset }
    }

    struct RegionNote: Equatable {
        let regionID: String
        let regionOffset: Int
        /// "New York" from "America/New_York".
        var city: String { regionID.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? regionID }
    }

    static let ambiguous: Set<String> = ["CST", "IST", "BST", "AST", "GST", "SST", "ECT", "CDT/CST"]

    static let table: [String: Zone] = {
        func f(_ h: Double, _ region: String?) -> Zone { Zone(fixedOffset: Int(h * 3600), regionID: region) }
        func r(_ region: String) -> Zone { Zone(fixedOffset: nil, regionID: region) }
        return [
            "UTC": f(0, nil), "GMT": f(0, nil), "Z": f(0, nil),
            "EST": f(-5, "America/New_York"), "EDT": f(-4, "America/New_York"), "ET": r("America/New_York"),
            "CDT": f(-5, "America/Chicago"), "CT": r("America/Chicago"),
            "MST": f(-7, "America/Denver"), "MDT": f(-6, "America/Denver"), "MT": r("America/Denver"),
            "PST": f(-8, "America/Los_Angeles"), "PDT": f(-7, "America/Los_Angeles"), "PT": r("America/Los_Angeles"),
            "AKST": f(-9, "America/Anchorage"), "AKDT": f(-8, "America/Anchorage"),
            "HST": f(-10, "Pacific/Honolulu"),
            "WET": f(0, "Europe/Lisbon"), "WEST": f(1, "Europe/Lisbon"),
            "CET": f(1, "Europe/Paris"), "CEST": f(2, "Europe/Paris"),
            "EET": f(2, "Europe/Athens"), "EEST": f(3, "Europe/Athens"),
            "MSK": f(3, "Europe/Moscow"),
            "ICT": f(7, "Asia/Ho_Chi_Minh"), "WIB": f(7, "Asia/Jakarta"),
            "SGT": f(8, "Asia/Singapore"), "HKT": f(8, "Asia/Hong_Kong"), "AWST": f(8, "Australia/Perth"),
            "JST": f(9, "Asia/Tokyo"), "KST": f(9, "Asia/Seoul"),
            "AEST": f(10, "Australia/Sydney"), "AEDT": f(11, "Australia/Sydney"),
            "NZST": f(12, "Pacific/Auckland"), "NZDT": f(13, "Pacific/Auckland"),
        ]
    }()

    /// The zone for a token: a table abbreviation or `UTC±H[:MM]` / `GMT±H[:MM]`. Nil for unknown or ambiguous.
    static func zone(for token: String) -> (label: String, zone: Zone)? {
        let t = token.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: " ", with: "").uppercased()
        if ambiguous.contains(t) { return nil }
        if let z = table[t] { return (t, z) }
        guard t.hasPrefix("UTC") || t.hasPrefix("GMT") else { return nil }
        let rest = t.dropFirst(3)
        guard let signChar = rest.first, signChar == "+" || signChar == "-" else { return nil }
        let body = rest.dropFirst()
        let parts = body.contains(":") ? body.split(separator: ":").map(String.init)
            : (body.count > 2 ? [String(body.prefix(body.count - 2)), String(body.suffix(2))] : [String(body)])
        guard (1...2).contains(parts.count), let h = Int(parts[0]), (0...14).contains(h) else { return nil }
        let m = parts.count == 2 ? Int(parts[1]) : 0
        guard let minutes = m, [0, 15, 30, 45].contains(minutes), parts[0].count <= 2 else { return nil }
        let secs = (h * 3600 + minutes * 60) * (signChar == "-" ? -1 : 1)
        return (offsetLabel(secs), Zone(fixedOffset: secs, regionID: nil))
    }

    /// `3pm` · `3 PM` · `3:30pm` · `9:30 a.m.` · `15:00` · `15h` · `15h30`. Nil when it is not a clock time.
    static func parseClock(_ raw: String) -> (hour: Int, minute: Int)? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
        func ints(_ pattern: String) -> [Int?]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).flatMap { Int(s[$0]) } }
        }
        if let g = ints(#"^(\d{1,2})(?::(\d{2}))?\s*(?:am|pm)$"#), let h = g[0] {
            let minute = g.count > 1 ? (g[1] ?? 0) : 0
            guard (1...12).contains(h), (0...59).contains(minute) else { return nil }
            let pm = s.hasSuffix("pm")
            return ((h % 12) + (pm ? 12 : 0), minute)
        }
        if let g = ints(#"^(\d{1,2}):(\d{2})$"#), let h = g[0], let m = g[1] {
            guard (0...23).contains(h), (0...59).contains(m) else { return nil }
            return (h, m)
        }
        if let g = ints(#"^(\d{1,2})h(\d{2})?$"#), let h = g[0] {
            let m = g.count > 1 ? (g[1] ?? 0) : 0
            guard (0...23).contains(h), (0...59).contains(m) else { return nil }
            return (h, m)
        }
        return nil
    }

    static func convert(_ text: String, now: Date, to local: TimeZone) -> Result? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= maxLength else { return nil }
        let pattern = #"^(.+?)\s*((?:UTC|GMT|utc|gmt)\s*[+\-−]\s*\d{1,2}(?::?\d{2})?|[A-Za-z]{1,5})$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let clockRange = Range(m.range(at: 1), in: t), let zoneRange = Range(m.range(at: 2), in: t),
              let clock = parseClock(String(t[clockRange])),
              let found = zone(for: String(t[zoneRange])) else { return nil }
        let label = found.label, zone = found.zone

        // The source zone as a TimeZone: the fixed offset, or the region.
        let sourceTZ: TimeZone?
        if let off = zone.fixedOffset { sourceTZ = TimeZone(secondsFromGMT: off) }
        else if let id = zone.regionID { sourceTZ = TimeZone(identifier: id) }
        else { sourceTZ = nil }
        guard let srcTZ = sourceTZ else { return nil }

        // Today in the SOURCE zone, at the written clock time there.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = srcTZ
        var dc = cal.dateComponents([.year, .month, .day], from: now)
        dc.hour = clock.hour; dc.minute = clock.minute; dc.second = 0
        guard let instant = cal.date(from: dc) else { return nil }

        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = local
        let lc = localCal.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        guard let lh = lc.hour, let lm = lc.minute else { return nil }
        let dayShift = dayNumber(lc) - dayNumber(dc)

        var note: RegionNote?
        if zone.fixedOffset != nil, let id = zone.regionID, let region = TimeZone(identifier: id) {
            let regionOffset = region.secondsFromGMT(for: instant)
            if regionOffset != srcTZ.secondsFromGMT(for: instant) { note = RegionNote(regionID: id, regionOffset: regionOffset) }
        }
        return Result(zoneLabel: label, sourceOffset: srcTZ.secondsFromGMT(for: instant),
                      sourceHour: clock.hour, sourceMinute: clock.minute, instant: instant,
                      localOffset: local.secondsFromGMT(for: instant), localHour: lh, localMinute: lm,
                      dayShift: max(-1, min(1, dayShift)), regionNote: note)
    }

    /// Days since a fixed epoch for a y/m/d triple, independent of time zone.
    private static func dayNumber(_ c: DateComponents) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let d = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? Date(timeIntervalSince1970: 0)
        return Int((d.timeIntervalSince1970 / 86_400).rounded())
    }

    /// `UTC−5` · `UTC+5:30` · `UTC` — a true minus sign, minutes only when non-zero.
    static func offsetLabel(_ seconds: Int) -> String {
        guard seconds != 0 else { return "UTC" }
        let sign = seconds < 0 ? "−" : "+"
        let a = abs(seconds), h = a / 3600, m = (a % 3600) / 60
        return m == 0 ? "UTC\(sign)\(h)" : String(format: "UTC%@%d:%02d", sign, h, m)
    }

    /// `HH:mm` (24 h). The panel adds the day shift and the zone separately.
    static func clockLabel(hour: Int, minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }
}
