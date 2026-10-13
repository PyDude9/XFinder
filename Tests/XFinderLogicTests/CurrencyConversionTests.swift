import XCTest
import Foundation

/// Smart Selection E6. The two feed fixtures are the bytes measured on 2026-10-13 (trimmed to the rows used), not
/// hand-made shapes — the parsers are tested against what the servers actually send.
final class CurrencyConversionTests: XCTestCase {
    typealias C = CurrencyConversion

    static let ecbXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
    \t<gesmes:subject>Reference rates</gesmes:subject>
    \t<gesmes:Sender>
    \t\t<gesmes:name>European Central Bank</gesmes:name>
    \t</gesmes:Sender>
    \t<Cube>
    \t\t<Cube time='2026-10-12'>
    \t\t\t<Cube currency='USD' rate='1.1181'/>
    \t\t\t<Cube currency='JPY' rate='177.33'/>
    \t\t\t<Cube currency='CZK' rate='24.391'/>
    \t\t\t<Cube currency='DKK' rate='7.4748'/>
    \t\t\t<Cube currency='GBP' rate='0.84478'/>
    \t\t\t<Cube currency='HUF' rate='365.13'/>
    \t\t</Cube>
    \t</Cube>
    </gesmes:Envelope>
    """

    static let vcbXML = """
    <!--For reference only. Only one request every 5 minutes!-->
    <ExrateList>
      <DateTime>10/13/2026 10:55:00 AM</DateTime>
      <Exrate CurrencyCode="AUD" CurrencyName="AUSTRALIAN DOLLAR   " Buy="17,553.19" Transfer="17,730.49" Sell="18,298.72" />
      <Exrate CurrencyCode="DKK" CurrencyName="DANISH KRONE        " Buy="-" Transfer="3,797.21" Sell="3,942.49" />
      <Exrate CurrencyCode="EUR" CurrencyName="EURO                " Buy="28,173.50" Transfer="28,458.08" Sell="29,659.47" />
      <Exrate CurrencyCode="JPY" CurrencyName="YEN                 " Buy="157.49" Transfer="159.08" Sell="168.34" />
      <Exrate CurrencyCode="KRW" CurrencyName="KOREAN WON          " Buy="16.79" Transfer="18.65" Sell="20.24" />
      <Exrate CurrencyCode="KWD" CurrencyName="KUWAITI DINAR       " Buy="-" Transfer="83,645.39" Sell="87,701.50" />
      <Exrate CurrencyCode="RUB" CurrencyName="RUSSIAN RUBLE       " Buy="-" Transfer="293.74" Sell="-" />
      <Exrate CurrencyCode="USD" CurrencyName="US DOLLAR           " Buy="25,700.00" Transfer="25,730.00" Sell="26,110.00" />
      <Source>Joint Stock Commercial Bank for Foreign Trade of Vietnam - Vietcombank</Source>
    </ExrateList>
    """

    let fetched = Date(timeIntervalSince1970: 1_792_000_000)

    var vcb: C.Table { C.parseVietcombank(Data(Self.vcbXML.utf8), fetchedAt: fetched)! }
    var ecb: C.Table { C.parseECB(Data(Self.ecbXML.utf8), fetchedAt: fetched)! }

    // MARK: Reading an amount

    func testAmountsAndMarkers() {
        XCTAssertEqual(C.parse("$20"), .init(value: 20, code: "USD", assumedFrom: "$"))
        XCTAssertEqual(C.parse("20$"), .init(value: 20, code: "USD", assumedFrom: "$"))
        XCTAssertEqual(C.parse("US$20"), .init(value: 20, code: "USD", assumedFrom: nil), "US$ is not a guess")
        XCTAssertEqual(C.parse("20 USD"), .init(value: 20, code: "USD", assumedFrom: nil))
        XCTAssertEqual(C.parse("usd 20"), .init(value: 20, code: "USD", assumedFrom: nil))
        XCTAssertEqual(C.parse("€15,50"), .init(value: 15.5, code: "EUR", assumedFrom: nil))
        XCTAssertEqual(C.parse("15\u{00A0}€"), .init(value: 15, code: "EUR", assumedFrom: nil), "no-break space")
        XCTAssertEqual(C.parse("20 đô"), .init(value: 20, code: "USD", assumedFrom: "đô"))
        XCTAssertEqual(C.parse("₩10,000"), .init(value: 10_000, code: "KRW", assumedFrom: nil))
        XCTAssertEqual(C.parse("JP¥1000"), .init(value: 1000, code: "JPY", assumedFrom: nil))
        XCTAssertEqual(C.parse("100 nhân dân tệ"), .init(value: 100, code: "CNY", assumedFrom: nil))
    }

    /// A price never has more decimals than its currency: one separator + three digits groups thousands.
    func testSeparatorsFollowTheCurrencysMinorUnits() {
        XCTAssertEqual(C.parse("1.500 €")?.value, 1500, "EUR has 2 decimals, so .500 cannot be cents")
        XCTAssertEqual(C.parse("1,500 $")?.value, 1500)
        XCTAssertEqual(C.parse("1,500.25 USD")?.value, 1500.25)
        XCTAssertEqual(C.parse("1.234.567,89 EUR")?.value, 1_234_567.89)
        XCTAssertEqual(C.parse("KWD 1.500")?.value, 1.5, "KWD has 3 decimals")
        XCTAssertEqual(C.parse("€9,9")?.value, 9.9)
        XCTAssertNil(C.parse("12345.678 €"), "neither a grouping nor a price")
        XCTAssertNil(C.parse("€1.5000"))
    }

    func testNotAnAmountIsRefused() {
        for bad in ["¥1000", "1000 ¥", "20 kr", "20", "USD", "$", "$20 and $30", "costs $20", "20 pounds",
                    "$0", "20 XYZ", "€ 1,2,3", String(repeating: "9", count: 30) + " USD"] {
            XCTAssertNil(C.parse(bad), bad)
        }
    }

    // MARK: Sources and conversion

    func testTheSourceFollowsTheLocalCurrency() {
        XCTAssertEqual(C.source(forLocalCurrency: "VND"), .vietcombank, "ECB does not quote VND (measured)")
        XCTAssertEqual(C.source(forLocalCurrency: "EUR"), .ecb)
        XCTAssertEqual(C.source(forLocalCurrency: "USD"), .ecb)
        XCTAssertNil(C.source(forLocalCurrency: "ARS"))
        XCTAssertNil(C.source(forLocalCurrency: nil))
        XCTAssertFalse(C.Source.ecb.listed.contains("VND"))
    }

    func testVietcombankFeedReadsTheSellRateAndItsVietnamTime() throws {
        let t = vcb
        XCTAssertEqual(t.rates["USD"], 26_110, "SELL, not Transfer 25,730 or Buy 25,700")
        XCTAssertEqual(t.rates["JPY"], 168.34)
        XCTAssertEqual(t.rates["KWD"], 87_701.5)
        XCTAssertNil(t.rates["RUB"], "Sell=\"-\" is not quoted, never 0")
        XCTAssertEqual(t.rates.count, 7)
        XCTAssertTrue(t.publishedHasTime)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: t.published)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 10, 13, 10, 55])
    }

    func testECBFeedReadsEveryRateAndTheDay() {
        let t = ecb
        XCTAssertEqual(t.rates.count, 6)
        XCTAssertEqual(t.rates["USD"], 1.1181)
        XCTAssertFalse(t.publishedHasTime)
        XCTAssertEqual(t.published, Date(timeIntervalSince1970: 1_791_763_200), "2026-10-12 00:00 UTC")
    }

    func testAPageThatIsNotAFeedIsNotATable() {
        XCTAssertNil(C.parseECB(Data("<html><body>Service unavailable</body></html>".utf8), fetchedAt: fetched))
        XCTAssertNil(C.parseVietcombank(Data("<ExrateList><DateTime>10/13/2026 10:55:00 AM</DateTime></ExrateList>".utf8),
                                        fetchedAt: fetched), "a date with no rates")
        XCTAssertNil(C.parseVietcombank(Data(Self.ecbXML.utf8), fetchedAt: fetched), "the other feed")
    }

    func testVietcombankConvertsIntoVNDAtTheSellRate() throws {
        let r = try XCTUnwrap(C.convert(.init(value: 20, code: "USD", assumedFrom: "$"), to: "VND", table: vcb))
        XCTAssertEqual(r.targetValue, 522_200, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(C.convert(.init(value: 1000, code: "JPY", assumedFrom: nil), to: "VND", table: vcb)).targetValue,
                       168_340, accuracy: 1e-6)
        XCTAssertNil(C.convert(.init(value: 20, code: "USD", assumedFrom: nil), to: "EUR", table: vcb), "only INTO VND")
        XCTAssertNil(C.convert(.init(value: 20, code: "RUB", assumedFrom: nil), to: "VND", table: vcb))
    }

    func testECBCrossesThroughTheEuro() throws {
        let usdToEur = try XCTUnwrap(C.convert(.init(value: 20, code: "USD", assumedFrom: nil), to: "EUR", table: ecb))
        XCTAssertEqual(usdToEur.targetValue, 20 / 1.1181, accuracy: 1e-9)
        let usdToJpy = try XCTUnwrap(C.convert(.init(value: 20, code: "USD", assumedFrom: nil), to: "JPY", table: ecb))
        XCTAssertEqual(usdToJpy.targetValue, 20 / 1.1181 * 177.33, accuracy: 1e-9)
        XCTAssertNil(C.convert(.init(value: 20, code: "USD", assumedFrom: nil), to: "USD", table: ecb))
    }

    // MARK: The row and the fetch policy

    func testTheRowShowsOnlyWhenOnAndNeverForTheLocalCurrency() throws {
        let now = fetched
        XCTAssertNil(C.row(for: "$20", context: nil, now: now), "switch off ⇒ no row")
        let ctx = C.Context(localCode: "VND", source: .vietcombank, table: vcb, failed: false)
        guard case .converted(let r) = try XCTUnwrap(C.row(for: "$20", context: ctx, now: now)) else { return XCTFail("not converted") }
        XCTAssertEqual(r.targetValue, 522_200, accuracy: 1e-6)
        XCTAssertNil(C.row(for: "500.000 VND", context: ctx, now: now), "already in the local currency")
        XCTAssertNil(C.row(for: "₱100", context: ctx, now: now), "the source does not quote PHP")
        let empty = C.Context(localCode: "VND", source: .vietcombank, table: nil, failed: false)
        XCTAssertEqual(C.row(for: "$20", context: empty, now: now), .pending(.init(value: 20, code: "USD", assumedFrom: "$"), to: "VND"))
        let euroNoTable = C.Context(localCode: "EUR", source: .ecb, table: nil, failed: false)
        XCTAssertNil(C.row(for: "€20", context: euroNoTable, now: now), "never \"fetching EUR → EUR\" while the table loads")
        XCTAssertEqual(C.row(for: "$20", context: euroNoTable, now: now), .pending(.init(value: 20, code: "USD", assumedFrom: "$"), to: "EUR"))
        let failed = C.Context(localCode: "VND", source: .vietcombank, table: nil, failed: true)
        XCTAssertEqual(C.row(for: "$20", context: failed, now: now), .failed(.init(value: 20, code: "USD", assumedFrom: "$"), to: "VND"))
    }

    func testAnOldOrForeignTableIsNotShown() {
        let t = vcb
        let ctx = C.Context(localCode: "VND", source: .vietcombank, table: t, failed: false)
        let eightDays = t.published.addingTimeInterval(8 * 86_400)
        XCTAssertEqual(C.row(for: "$20", context: ctx, now: eightDays), .pending(.init(value: 20, code: "USD", assumedFrom: "$"), to: "VND"),
                       "a week-old rate is not shown as ≈")
        let wrong = C.Context(localCode: "VND", source: .vietcombank, table: ecb, failed: false)
        XCTAssertEqual(C.row(for: "€20", context: wrong, now: fetched), .pending(.init(value: 20, code: "EUR", assumedFrom: nil), to: "VND"),
                       "a table from the other source is never used")
    }

    func testOneRequestPerTwelveHoursAndNoneRightAfterAFailure() {
        let t = vcb
        XCTAssertTrue(C.shouldFetch(now: fetched, table: nil, source: .vietcombank, lastFailure: nil, inFlight: false))
        XCTAssertFalse(C.shouldFetch(now: fetched, table: nil, source: .vietcombank, lastFailure: nil, inFlight: true))
        XCTAssertFalse(C.shouldFetch(now: fetched.addingTimeInterval(11 * 3600), table: t, source: .vietcombank, lastFailure: nil, inFlight: false))
        XCTAssertTrue(C.shouldFetch(now: fetched.addingTimeInterval(12 * 3600), table: t, source: .vietcombank, lastFailure: nil, inFlight: false))
        XCTAssertTrue(C.shouldFetch(now: fetched.addingTimeInterval(-60), table: t, source: .vietcombank, lastFailure: nil, inFlight: false),
                      "the clock moved back: the table's age is unknown")
        XCTAssertTrue(C.shouldFetch(now: fetched, table: t, source: .ecb, lastFailure: nil, inFlight: false), "region changed")
        let failure = fetched
        XCTAssertFalse(C.shouldFetch(now: failure.addingTimeInterval(14 * 60), table: nil, source: .vietcombank, lastFailure: failure, inFlight: false))
        XCTAssertTrue(C.shouldFetch(now: failure.addingTimeInterval(15 * 60), table: nil, source: .vietcombank, lastFailure: failure, inFlight: false))
    }

    func testFormattingUsesTheCurrencysOwnDecimals() {
        XCTAssertEqual(C.format(522_200, code: "VND", decimalComma: false), "522,200 VND")
        XCTAssertEqual(C.format(522_200, code: "VND", decimalComma: true), "522.200 VND")
        XCTAssertEqual(C.format(17.887487, code: "EUR", decimalComma: true), "17,89 EUR")
        XCTAssertEqual(C.format(1.5, code: "KWD", decimalComma: false), "1.500 KWD")
        XCTAssertEqual(C.format(1234.6, code: "JPY", decimalComma: false), "1,235 JPY")
    }

    // MARK: Wired into the rules

    func testTheRulesOfferTheCurrencyRowFirstAndOnlyWhenOn() throws {
        let now = fetched
        let hcm = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let noDate: (String) -> SmartSelectionRules.DateMatch? = { _ in nil }
        XCTAssertEqual(SmartSelectionRules.actions(for: "$20", now: now, localZone: hcm, detectDate: noDate), [],
                       "off ⇒ \"$20\" offers nothing (no letters, no unit)")
        let ctx = C.Context(localCode: "VND", source: .vietcombank, table: vcb, failed: false)
        let on = SmartSelectionRules.actions(for: "20 USD", now: now, localZone: hcm, currency: ctx, detectDate: noDate)
        guard case .currency(.converted)? = on.first else { return XCTFail("currency row is not first: \(on)") }
    }

    /// Every string the panel and the page show for E6, resolved in the shipped store.
    func testEveryCurrencyStringIsTranslated() throws {
        let keys = [": đang lấy tỷ giá…", "Không lấy được tỷ giá. XFinder thử lại sau ít phút.", "Giá bán Vietcombank",
                    "Tỷ giá tham chiếu ECB", " hiểu là ", "Đổi tiền tệ", "Đổi tiền tệ (cần mạng)",
                    "Đang tải bảng tỷ giá…", "Bảng tỷ giá đang dùng: ", " đồng tiền.", "Vùng của macOS dùng "]
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = (root["entries"] as? [String: Any]) ?? root
        for k in keys {
            let en = (entries[k] as? [String: Any])?["en"] as? String
            XCTAssertFalse((en ?? "").isEmpty, "missing English for \(k)")
        }
    }
}
