import Foundation

/// Smart Selection E6 — "$20", "15 EUR", "1.500 €" selected in another app → the user's own currency. Pure: parsing,
/// conversion, the two feed parsers and the fetch policy. `CurrencyRateStore` makes the one network request.
///
/// Measured before writing (2026-10-13, this Mac: region `en_VN`, `Locale.current.currency` = VND):
/// * The ECB daily reference feed (`eurofxref-daily.xml`, no key) quotes 29 currencies against EUR — and **not VND**.
///   An ECB-only design would fail the one conversion this user needs, so the source follows the local currency.
/// * Vietcombank's public XML (`pXML.aspx`, no key, header comment "For reference only. Only one request every 5
///   minutes!") quotes 20 currencies in VND per ONE unit (JPY 168.34, KRW 20.24), with Buy/Transfer/Sell, "-" for a
///   rate it does not quote, and "," as the thousands separator. Its undocumented JSON API is not used.
/// * ICU minor units: JPY KRW VND ISK HUF IDR = 0, KWD = 3, USD = 2 — `minorUnits` pins the same values.
///
/// What is sent: one GET of the public rate table, at most every 12 hours, only while the opt-in switch is on. The
/// selected text never leaves the Mac.
enum CurrencyConversion {

    static let enabledKey = "smartSelect.currency"
    /// A fetched table is used this long before one new request is made.
    static let freshFor: TimeInterval = 12 * 3600
    /// A table PUBLISHED longer ago than this is not shown at all — a weekend plus a holiday is about four days
    /// without a new ECB fixing; a week means the feed is broken, and an old rate shown as "≈" misleads.
    static let usableFor: TimeInterval = 7 * 24 * 3600
    /// After a failed request, no new one for this long (Vietcombank asks for at most one per 5 minutes).
    static let retryAfterFailure: TimeInterval = 15 * 60

    // MARK: Sources

    enum Source: String, Codable, CaseIterable {
        case ecb, vietcombank

        var host: String {
            switch self {
            case .ecb: return "www.ecb.europa.eu"
            case .vietcombank: return "portal.vietcombank.com.vn"
            }
        }

        var url: URL {
            switch self {
            case .ecb: return URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
            case .vietcombank: return URL(string: "https://portal.vietcombank.com.vn/Usercontrols/TVPortal.TyGia/pXML.aspx")!
            }
        }

        /// What the feed quoted when measured. Used only to decide whether a "fetching…" row is worth showing before
        /// a table exists; conversion itself always uses the fetched table.
        var listed: Set<String> {
            switch self {
            case .ecb:
                return ["EUR", "USD", "JPY", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF", "ISK", "NOK", "TRY",
                        "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW", "MXN", "MYR", "NZD", "PHP", "SGD",
                        "THB", "ZAR"]
            case .vietcombank:
                return ["AUD", "CAD", "CHF", "CNY", "DKK", "EUR", "GBP", "HKD", "INR", "JPY", "KRW", "KWD", "MYR", "NOK",
                        "RUB", "SAR", "SEK", "SGD", "THB", "USD"]
            }
        }

        /// Can this source turn `code` into `target` at all?
        func quotes(_ code: String, into target: String) -> Bool {
            switch self {
            case .ecb: return listed.contains(code) && listed.contains(target)
            case .vietcombank: return target == "VND" && listed.contains(code)
            }
        }
    }

    /// VND ⇒ Vietcombank (the only public no-key feed found that quotes VND); a currency the ECB fixes ⇒ ECB;
    /// anything else ⇒ nil, and the settings page says why instead of offering a switch that cannot work.
    static func source(forLocalCurrency code: String?) -> Source? {
        guard let code else { return nil }
        if code == "VND" { return .vietcombank }
        return Source.ecb.listed.contains(code) ? .ecb : nil
    }

    // MARK: Reading an amount

    struct Amount: Equatable {
        let value: Double
        let code: String
        /// The symbol or word the currency was GUESSED from ("$" ⇒ USD). The panel says so; nil when unambiguous.
        let assumedFrom: String?
    }

    /// Exact symbols, written before or after the number.
    private static let symbols: [String: String] = [
        "US$": "USD", "€": "EUR", "£": "GBP", "₩": "KRW", "฿": "THB", "₹": "INR", "₱": "PHP", "₺": "TRY", "₪": "ILS",
        "S$": "SGD", "HK$": "HKD", "A$": "AUD", "AU$": "AUD", "C$": "CAD", "CA$": "CAD", "NZ$": "NZD", "R$": "BRL",
        "JP¥": "JPY", "CN¥": "CNY", "RM": "MYR", "Rp": "IDR", "zł": "PLN", "Kč": "CZK", "元": "CNY", "円": "JPY",
    ]
    /// Read as one currency although others share them — the panel shows the assumption.
    private static let assumed: [String: String] = ["$": "USD", "dollar": "USD", "dollars": "USD", "đô": "USD", "đô la": "USD"]
    /// Words, compared lowercased. "pound(s)" is deliberately absent: it is a weight unit too.
    private static let words: [String: String] = [
        "euro": "EUR", "euros": "EUR", "yen": "JPY", "yên": "JPY", "yuan": "CNY", "rmb": "CNY", "tệ": "CNY",
        "nhân dân tệ": "CNY", "won": "KRW", "baht": "THB", "bạt": "THB", "ringgit": "MYR", "rupee": "INR",
        "rupees": "INR", "bảng anh": "GBP",
    ]
    /// Never guessed: "¥" is the yen AND the yuan, "kr" is four Nordic crowns. A wrong currency is worse than none.
    static let ambiguous: Set<String> = ["¥", "kr", "kr.", "R", "Fr", "Fr."]

    /// Every ISO code either source can quote, plus VND.
    private static let codes: Set<String> = Source.ecb.listed.union(Source.vietcombank.listed).union(["VND"])

    /// The WHOLE selection must be one amount and one currency marker — "$20 and $30" or "costs $20" are not offered.
    static func parse(_ text: String) -> Amount? {
        let t = text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= 40, let first = t.firstIndex(where: \.isNumber) else { return nil }
        var end = first
        while end < t.endIndex, t[end].isNumber || t[end] == "." || t[end] == "," { end = t.index(after: end) }
        let number = String(t[first..<end])
        let prefix = t[t.startIndex..<first].trimmingCharacters(in: .whitespaces)
        let suffix = t[end...].trimmingCharacters(in: .whitespaces)
        guard prefix.isEmpty != suffix.isEmpty else { return nil }
        let marker = prefix.isEmpty ? suffix : prefix
        guard !ambiguous.contains(marker), let (code, guess) = currency(for: marker),
              let value = parseAmount(number, code: code), value > 0, value.isFinite else { return nil }
        return Amount(value: value, code: code, assumedFrom: guess)
    }

    private static func currency(for marker: String) -> (String, String?)? {
        if let c = symbols[marker] { return (c, nil) }
        let lower = marker.lowercased()
        if let c = assumed[marker] ?? assumed[lower] { return (c, marker) }
        if let c = words[lower] { return (c, nil) }
        if marker.count == 3, codes.contains(marker.uppercased()) { return (marker.uppercased(), nil) }
        return nil
    }

    /// A price is never written with more decimals than its currency has, so a single separator followed by exactly
    /// three digits groups thousands — `1.500 €` is 1 500, `500.000` is 500 000 — unless the currency really has three
    /// minor digits (`KWD 1.500` is 1.5). One or two digits after it are cents. This is NOT `UnitConversion`'s rule
    /// ("1.500 km" is 1.5 km), because a distance can have any number of decimals and a price cannot.
    static func parseAmount(_ s: String, code: String) -> Double? {
        guard let f = s.first, f.isNumber, let l = s.last, l.isNumber, s.count <= 24 else { return nil }
        let kinds = Set(s.filter { $0 == "." || $0 == "," })
        if kinds.count == 2 { return UnitConversion.parseNumber(s) }   // the last one is decimal, the other groups
        guard let sep = kinds.first else { return Double(s) }
        let parts = s.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first, !head.isEmpty else { return nil }
        if parts.count > 2 {
            guard (1...3).contains(head.count), parts.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
            return Double(parts.joined())
        }
        let tail = parts[1]
        if tail.count == 3 && minorUnits(code) != 3 {
            guard (1...3).contains(head.count) else { return nil }
            return Double(head + tail)
        }
        guard (1...max(2, minorUnits(code))).contains(tail.count) else { return nil }
        return Double(head + "." + tail)
    }

    /// ISO 4217 minor units as ICU reports them on this Mac (HUF and IDR: 0 in practice, as ICU says).
    static func minorUnits(_ code: String) -> Int {
        if ["KWD", "BHD", "OMR", "JOD", "TND", "IQD", "LYD"].contains(code) { return 3 }
        if ["JPY", "KRW", "VND", "ISK", "HUF", "IDR", "CLP"].contains(code) { return 0 }
        return 2
    }

    // MARK: Converting

    struct Table: Codable, Equatable {
        let source: Source
        let published: Date
        /// ECB publishes a date; Vietcombank a date and a time (Vietnam time).
        let publishedHasTime: Bool
        let fetchedAt: Date
        /// ECB: units of the currency per 1 EUR. Vietcombank: VND per 1 unit, the bank's SELL rate.
        let rates: [String: Double]
    }

    struct Result: Equatable {
        let amount: Amount
        let targetCode: String
        let targetValue: Double
        let source: Source
        let published: Date
        let publishedHasTime: Bool
    }

    /// ECB: cross through EUR (mid-market reference rates). Vietcombank: foreign → VND at the SELL rate — what the
    /// bank charges to sell you that currency, i.e. what a price in it costs in đồng. Never the other way round: the
    /// panel only converts INTO the local currency.
    static func convert(_ a: Amount, to target: String, table: Table) -> Result? {
        guard a.code != target, a.value > 0, a.value.isFinite else { return nil }
        let value: Double
        switch table.source {
        case .ecb:
            func perEUR(_ c: String) -> Double? { c == "EUR" ? 1 : table.rates[c] }
            guard let s = perEUR(a.code), let t = perEUR(target), s > 0, t > 0 else { return nil }
            value = a.value / s * t
        case .vietcombank:
            guard target == "VND", let sell = table.rates[a.code], sell > 0 else { return nil }
            value = a.value * sell
        }
        guard value.isFinite else { return nil }
        return Result(amount: a, targetCode: target, targetValue: value, source: table.source,
                      published: table.published, publishedHasTime: table.publishedHasTime)
    }

    // MARK: The panel row

    enum Row: Equatable {
        case converted(Result)
        /// The switch is on but no usable table yet: one request is on its way.
        case pending(Amount, to: String)
        /// The last request failed and there is no usable table.
        case failed(Amount, to: String)
    }

    /// What the watcher knows when a selection settles. nil ⇒ the feature is off (or the local currency has no source).
    struct Context: Equatable {
        let localCode: String
        let source: Source
        let table: Table?
        let failed: Bool
    }

    static func row(for text: String, context: Context?, now: Date) -> Row? {
        guard let ctx = context, let a = parse(text), a.code != ctx.localCode,
              ctx.source.quotes(a.code, into: ctx.localCode) else { return nil }
        if let table = ctx.table, table.source == ctx.source, isUsable(table, now: now) {
            return convert(a, to: ctx.localCode, table: table).map(Row.converted)
        }
        return ctx.failed ? .failed(a, to: ctx.localCode) : .pending(a, to: ctx.localCode)
    }

    static func isUsable(_ table: Table, now: Date) -> Bool {
        let age = now.timeIntervalSince(table.published)
        return age >= -86_400 && age <= usableFor
    }

    /// One request at a time, none within 15 minutes of a failure, and none while the table is younger than 12 hours.
    static func shouldFetch(now: Date, table: Table?, source: Source, lastFailure: Date?, inFlight: Bool) -> Bool {
        if inFlight { return false }
        if let f = lastFailure, now.timeIntervalSince(f) < retryAfterFailure, now >= f { return false }
        guard let t = table, t.source == source else { return true }
        let age = now.timeIntervalSince(t.fetchedAt)
        return age >= freshFor || age < 0
    }

    // MARK: Formatting

    /// "522,200 VND" / "17,89 EUR": the currency's own minor units, grouped, decimal mark by UI language, never "-0".
    static func format(_ value: Double, code: String, decimalComma: Bool) -> String {
        guard value.isFinite else { return "–" }
        let digits = minorUnits(code)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = decimalComma ? "." : ","
        f.decimalSeparator = decimalComma ? "," : "."
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        f.roundingMode = .halfEven
        let rounded = value == 0 ? 0 : value
        return "\(f.string(from: NSNumber(value: rounded)) ?? "–") \(code)"
    }

    // MARK: Feeds

    /// `<Cube time='2026-10-12'>` + `<Cube currency='USD' rate='1.1181'/>`. Fewer than 5 rates or no date ⇒ nil
    /// (an error page is not a table).
    static func parseECB(_ data: Data, fetchedAt: Date) -> Table? {
        let p = FeedParser(element: "Cube", codeAttribute: "currency", rateAttribute: "rate")
        guard p.run(data), let day = p.attributeDate, p.rates.count >= 5 else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: day) else { return nil }
        return Table(source: .ecb, published: date, publishedHasTime: false, fetchedAt: fetchedAt, rates: p.rates)
    }

    /// `<DateTime>10/13/2026 10:55:00 AM</DateTime>` (Vietnam time) + `<Exrate CurrencyCode="USD" … Sell="26,110.00"/>`.
    /// The SELL attribute only; "-" means the bank does not quote it and the currency is left out.
    static func parseVietcombank(_ data: Data, fetchedAt: Date) -> Table? {
        let p = FeedParser(element: "Exrate", codeAttribute: "CurrencyCode", rateAttribute: "Sell", textElement: "DateTime")
        guard p.run(data), let stamp = p.elementText, p.rates.count >= 5 else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        df.dateFormat = "MM/dd/yyyy h:mm:ss a"
        guard let date = df.date(from: stamp.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Table(source: .vietcombank, published: date, publishedHasTime: true, fetchedAt: fetchedAt, rates: p.rates)
    }

    /// One small XMLParser delegate for both feeds: rates from (code attribute, rate attribute) on `element`, the
    /// ECB date from a `time` attribute, the Vietcombank stamp from the text of `textElement`.
    private final class FeedParser: NSObject, XMLParserDelegate {
        let element: String, codeAttribute: String, rateAttribute: String, textElement: String?
        var rates: [String: Double] = [:]
        var attributeDate: String?
        var elementText: String?
        private var inText = false
        private var buffer = ""

        init(element: String, codeAttribute: String, rateAttribute: String, textElement: String? = nil) {
            self.element = element; self.codeAttribute = codeAttribute
            self.rateAttribute = rateAttribute; self.textElement = textElement
        }

        func run(_ data: Data) -> Bool {
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.shouldResolveExternalEntities = false
            return parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == textElement { inText = true; buffer = "" }
            guard name == element else { return }
            if let time = attributes["time"] { attributeDate = time }
            guard let code = attributes[codeAttribute]?.trimmingCharacters(in: .whitespaces).uppercased(), code.count == 3,
                  let raw = attributes[rateAttribute] else { return }
            let cleaned = raw.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            if let v = Double(cleaned), v > 0, v.isFinite { rates[code] = v }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { buffer += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == textElement { inText = false; elementText = buffer }
        }
    }
}
