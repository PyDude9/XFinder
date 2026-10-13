import Foundation
import CoreGraphics

/// Smart Selection E1 — every rule between "the user selected some text in another app" and "a small badge appears
/// beside it; clicking it shows what XFinder can do with that text". Pure: the watcher (AX) and the panel (SwiftUI)
/// only feed it facts and act on its answers.
///
/// Designed from a 10-minute passive probe (`scratchpad/e-probe/selwatch`, selection LENGTHS only, never text):
/// * `kAXSelectedTextChangedNotification` registers in every app tried (Chrome, Safari, Claude/Electron, AyuGram)
///   without writing any attribute of theirs — so nothing here ever writes `AXManualAccessibility`.
/// * It fires on every step of a drag (110 events in Chrome, 46 in Claude in 10 min; lengths 1 → 11 → 14 → 17 → 20…),
///   so the badge waits for the selection to stop changing AND for a mouse-up near the last change (`Watch`).
/// * `kAXBoundsForRangeParameterizedAttribute` came back as `0,1117 0×0` for 94/94 Chrome and 42/42 Claude selections
///   (1117 = the primary screen's height: "no data"), so the badge anchors at the mouse-up point unless the AX rect is
///   real (`anchor`).
/// * A keyboard selection has no trustworthy screen position, so it never shows the badge — ⇧⌘G covers it.
enum SmartSelectionRules {

    static let enabledKey = "smartSelect.enabled"
    static let minLengthKey = "smartSelect.minLength"
    static let excludedAppsKey = "smartSelect.excludedApps"
    static let defaultMinLength = 2
    static let minLengthChoices = [1, 2, 3, 5, 10]
    /// Same cap as translation: a whole document selected is not a "selection" to act on.
    static let maxLength = 5000
    /// The selection must stop changing for this long before the badge appears.
    static let settleDelay: TimeInterval = 0.3
    /// A mouse-up counts for a selection change at most this far before or after it.
    static let mouseUpWindow: TimeInterval = 0.6
    /// An unclicked badge goes away on its own.
    static let badgeLifetime: TimeInterval = 6
    static let badgeSize = CGSize(width: 30, height: 24)

    // MARK: Gate

    /// Whether a selection in the frontmost app is worth looking at at all.
    static func shouldConsider(text: String, minLength: Int, frontBundleID: String?, frontAppName: String?,
                               ownBundleID: String, excluded: Set<String>) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= max(1, minLength), t.count <= maxLength else { return false }
        guard let bid = frontBundleID, !bid.isEmpty, bid != ownBundleID, !excluded.contains(bid) else { return false }
        return !SecretApps.matches(bid, frontAppName)
    }

    /// `smartSelect.excludedApps` is a comma list of bundle ids; blanks and duplicates are dropped.
    static func parseExcluded(_ raw: String?) -> Set<String> {
        Set((raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func encodeExcluded(_ ids: Set<String>) -> String { ids.sorted().joined(separator: ",") }

    // MARK: Actions

    struct DateMatch: Equatable {
        let date: Date
        /// The text the detector matched ("Friday at 9am"), used to cut the event title out of the selection.
        let matched: String
    }

    enum Action: Equatable {
        case unit(UnitConversion.Result)
        case time(TimeZoneConversion.Result)
        case arithmetic(value: Double)
        /// `title` is the selection with the date words removed ("" ⇒ the panel uses a default title).
        case calendar(title: String, date: Date, hasTime: Bool)
        case translate
    }

    /// What XFinder can do with a selection, most specific first. Empty ⇒ no badge.
    static func actions(for text: String, now: Date, localZone: TimeZone,
                        detectDate: (String) -> DateMatch? = SmartSelectionRules.detectDate) -> [Action] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= maxLength else { return [] }
        var out: [Action] = []
        if let u = UnitConversion.convert(t) { out.append(.unit(u)) }
        if let tz = TimeZoneConversion.convert(t, now: now, to: localZone), !tz.isSameAsLocal { out.append(.time(tz)) }
        let dateMatch = t.count <= 200 ? detectDate(t) : nil
        if let v = arithmetic(t), dateMatch.map({ !covers($0.matched, t) }) ?? true { out.append(.arithmetic(value: v)) }
        if let d = dateMatch, out.allSatisfy({ if case .time = $0 { return false } else { return true } }) {
            out.append(.calendar(title: eventTitle(selection: t, matched: d.matched), date: d.date,
                                 hasTime: hasTimeOfDay(d.matched)))
        }
        if t.rangeOfCharacter(from: .letters) != nil { out.append(.translate) }
        return out
    }

    /// Arithmetic only when the selection is clearly a calculation: digits and operators only, at least one strong
    /// operator (+ × ÷ * ^) or a SPACED minus/slash. That keeps dates (`15/10/2026`), phone numbers (`090-123-4567`)
    /// and lone signed numbers (`+84`) out — each of them evaluates, none of them is a sum anyone selected.
    static func arithmetic(_ t: String) -> Double? {
        let allowed = CharacterSet(charactersIn: "0123456789 .+-*/×÷^()")
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }), t.contains(where: \.isNumber) else { return nil }
        let strong = t.contains { "+*×÷^".contains($0) }
        let spaced = t.range(of: #"\s[-/]\s"#, options: .regularExpression) != nil
        guard strong || spaced else { return nil }
        guard Double(t.replacingOccurrences(of: " ", with: "")) == nil else { return nil }   // "+84", "-3"
        return SafeArithmetic.evaluate(t)
    }

    /// The real date detector (Foundation `NSDataDetector`). Measured: it reads Vietnamese (`15 tháng 10 năm 2026`,
    /// `thứ Sáu 9 giờ`, `15/10/2026` as 15 October) and gives a date-only match a time of 12:00.
    static func detectDate(_ text: String) -> DateMatch? {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = text as NSString
        guard let m = det.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), let d = m.date else { return nil }
        return DateMatch(date: d, matched: ns.substring(with: m.range))
    }

    /// Does the match account for (almost) all of the selection? Then a "calculation" in it is really a date.
    static func covers(_ matched: String, _ text: String) -> Bool {
        matched.count * 10 >= text.count * 8
    }

    /// The detector returns noon for a date without a time, so "has a time of day" must be read from the words.
    static func hasTimeOfDay(_ matched: String) -> Bool {
        let s = matched.lowercased()
        let patterns = [#"\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)"#, #"\d{1,2}:\d{2}"#, #"\b\d{1,2}h(\d{2})?\b"#,
                        #"\d{1,2}\s*giờ"#, #"\b(noon|midnight)\b"#, #"(buổi )?(trưa|sáng|chiều|tối)\b"#]
        return patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }

    /// The selection minus the date words and the little connectors around them ("Meeting on Friday" → "Meeting").
    static func eventTitle(selection: String, matched: String) -> String {
        var s = selection.replacingOccurrences(of: matched, with: " ")
        let connectors = ["on", "at", "by", "from", "vào", "lúc", "ngày", "hôm", "-", "–", "—", ",", ":"]
        var words = s.split(whereSeparator: \.isWhitespace).map(String.init)
        while let last = words.last, connectors.contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, connectors.contains(first.lowercased()) { words.removeFirst() }
        s = words.joined(separator: " ")
        return String(s.prefix(120))
    }

    /// A calculation result for the panel and the clipboard: up to 6 decimals, trailing zeros trimmed, thousands
    /// grouped, decimal mark by UI language, never "-0".
    static func formatResult(_ v: Double, decimalComma: Bool) -> String {
        guard v.isFinite else { return "–" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = decimalComma ? "." : ","
        f.decimalSeparator = decimalComma ? "," : "."
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 6
        let rounded = (v * 1_000_000).rounded() / 1_000_000
        return f.string(from: NSNumber(value: rounded == 0 ? 0 : rounded)) ?? "–"
    }

    /// Every notice the panel can show. They reach the screen through `L10n.t(notice.key)` — a variable, which no
    /// literal sweep can see — so they live here and `SmartSelectionRulesTests` resolves each one in the store.
    enum NoticeKey {
        static let copied = "Đã sao chép."
        static let calendarDenied = "XFinder chưa được phép ghi vào Lịch."
        static let noDefaultCalendar = "Không tìm thấy lịch mặc định để ghi."
        static let calendarAdded = "Đã thêm vào Lịch."
        static let calendarFailed = "Không thêm được vào Lịch."
        static let all = [copied, calendarDenied, noDefaultCalendar, calendarAdded, calendarFailed]
    }

    // MARK: Attaching to an app

    /// Retry schedule for `AXObserverAddNotification` after `kAXErrorCannotComplete` (-25204).
    ///
    /// Measured on the installed app (e2e, 2026-10-13): an app activated while still launching answered BOTH
    /// registrations with -25204 under a 0.3 s messaging timeout, and the watcher kept that pid as "attached", so the
    /// feature stayed silent in that app until the user switched away and back. -25204 means "busy / not answering
    /// yet" — worth a few more tries while the app stays frontmost. Every other error is final: -25207 the app does
    /// not post that notification, -25211 Accessibility is not granted, -25202 the app is gone.
    static let registrationRetryDelays: [TimeInterval] = [0.5, 1.5, 3.0]
    static let axCannotComplete: Int32 = -25204

    static func registrationRetryDelay(attempt: Int, error: Int32) -> TimeInterval? {
        guard error == axCannotComplete, attempt >= 0, attempt < registrationRetryDelays.count else { return nil }
        return registrationRetryDelays[attempt]
    }

    // MARK: When to show the badge

    struct MouseUp: Equatable {
        let point: CGPoint
        let time: TimeInterval
    }

    struct Watch: Equatable {
        var length = 0
        var lastChange: TimeInterval?
        var lastMouseUp: MouseUp?
        var shown = false
    }

    enum Event: Equatable {
        case selectionChanged(length: Int, at: TimeInterval)
        case mouseUp(CGPoint, at: TimeInterval)
        case settle(at: TimeInterval)
        /// Click elsewhere, Esc, app switch, focus moved, badge expired.
        case dismiss
    }

    enum Effect: Equatable {
        case hide
        case armSettle(at: TimeInterval)
        case show(at: CGPoint)
    }

    static func reduce(_ w: inout Watch, _ e: Event, minLength: Int) -> [Effect] {
        switch e {
        case .selectionChanged(let length, let t):
            var fx: [Effect] = w.shown ? [.hide] : []
            w.shown = false
            w.length = length
            w.lastChange = t
            if length >= max(1, minLength) { fx.append(.armSettle(at: t + settleDelay)) }
            return fx
        case .mouseUp(let p, let t):
            w.lastMouseUp = MouseUp(point: p, time: t)
            guard w.length >= max(1, minLength), w.lastChange != nil, !w.shown else { return [] }
            return [.armSettle(at: t + settleDelay)]
        case .settle(let t):
            guard !w.shown, w.length >= max(1, minLength), let change = w.lastChange, let up = w.lastMouseUp,
                  t - change >= settleDelay - 0.001,
                  t - up.time >= settleDelay - 0.001,
                  abs(up.time - change) <= mouseUpWindow else { return [] }
            w.shown = true
            return [.show(at: up.point)]
        case .dismiss:
            let fx: [Effect] = w.shown ? [.hide] : []
            w.shown = false
            return fx
        }
    }

    // MARK: Where

    /// The badge's anchor in AppKit space: the bottom-right of the selection when Accessibility gave a real rect
    /// (AX is top-left origin on the primary screen, so it is flipped), otherwise the mouse-up point.
    static func anchor(axBounds: CGRect?, mouseUp: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        if let r = axBounds, r.width > 0, r.height > 0, r.minY < primaryScreenHeight {
            return CGPoint(x: r.maxX, y: primaryScreenHeight - r.maxY)
        }
        return mouseUp
    }

    /// The badge sits just below-right of the anchor, inside the visible frame of the screen that contains it.
    static func badgeFrame(anchor: CGPoint, visible: CGRect, size: CGSize = SmartSelectionRules.badgeSize) -> CGRect {
        let r = CGRect(x: anchor.x + 6, y: anchor.y - 6 - size.height, width: size.width, height: size.height)
        var o = r.origin
        o.x = min(max(o.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        o.y = min(max(o.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return CGRect(origin: o, size: size)
    }
}
