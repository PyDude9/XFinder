import XCTest
import Foundation

/// Smart Selection E2 (units) and E3 (time zones). Expected values are computed from the definitions
/// (1 mi = 1.609344 km, 1 lb = 0.45359237 kg, °C = (°F − 32) × 5/9, US gal = 3.785411784 l), not read back from the code.
final class UnitConversionTests: XCTestCase {
    typealias U = UnitConversion

    func testWholeSelectionQuantities() {
        XCTAssertEqual(U.parse("5 km"), .init(value: 5, unit: .kilometre))
        XCTAssertEqual(U.parse("5km"), .init(value: 5, unit: .kilometre))
        XCTAssertEqual(U.parse("  12 miles \n"), .init(value: 12, unit: .mile))
        XCTAssertEqual(U.parse("72°F"), .init(value: 72, unit: .fahrenheit))
        XCTAssertEqual(U.parse("-5 °C"), .init(value: -5, unit: .celsius))
        XCTAssertEqual(U.parse("−5 °C"), .init(value: -5, unit: .celsius), "Unicode minus from typeset text")
        XCTAssertEqual(U.parse("30 độ C"), .init(value: 30, unit: .celsius))
        XCTAssertEqual(U.parse("100 km/h"), .init(value: 100, unit: .kilometrePerHour))
        XCTAssertEqual(U.parse("2 fl oz"), .init(value: 2, unit: .fluidOunceUS))
        XCTAssertEqual(U.parse("6'"), .init(value: 6, unit: .foot))
        XCTAssertEqual(U.parse("15 cây số"), .init(value: 15, unit: .kilometre))
    }

    func testNotAQuantityIsRefused() {
        for bad in ["72 F", "5 km away", "about 5 km", "km", "5", "5 kmz", "5 lightyears", "five km", "5. km",
                    "12,34,567 m", "1,2,3 m", "km 5", String(repeating: "9", count: 40) + " km"] {
            XCTAssertNil(U.parse(bad), bad)
        }
    }

    func testThousandsAndDecimalMarks() {
        XCTAssertEqual(U.parseNumber("1,5"), 1.5, "Vietnamese decimal comma")
        XCTAssertEqual(U.parseNumber("1,500"), 1500, "comma + three digits groups thousands")
        XCTAssertEqual(U.parseNumber("12,500,000"), 12_500_000)
        XCTAssertEqual(U.parseNumber("1.5"), 1.5)
        XCTAssertEqual(U.parseNumber("1.500"), 1.5, "a single dot is always the decimal mark")
        XCTAssertEqual(U.parseNumber("1.500.000"), 1_500_000, "repeated dots group thousands")
        XCTAssertEqual(U.parseNumber("1,234.5"), 1234.5)
        XCTAssertEqual(U.parseNumber("1.234,5"), 1234.5)
        XCTAssertEqual(U.parseNumber("-3,25"), -3.25)
        for bad in ["1,2,3", "1.2.3", "1,234,5", "12,34.5", ",5", "5,", "5.", "1.234,5,6", "1,23.4.5"] {
            XCTAssertNil(U.parseNumber(bad), bad)
        }
    }

    func testConversionsAgainstTheDefinitions() throws {
        let km = try XCTUnwrap(U.convert("5 km"))
        XCTAssertEqual(km.target.unit, .mile)
        XCTAssertEqual(km.target.value, 5 / 1.609344, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(U.convert("72°F")).target.value, (72 - 32) * 5 / 9, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(U.convert("-40 °C")).target.value, -40, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(U.convert("1 gal")).target.value, 3.785411784, accuracy: 1e-9, "US gallon, not imperial 4.546")
        XCTAssertEqual(try XCTUnwrap(U.convert("1 lb")).target.value, 0.45359237, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(U.convert("100 km/h")).target.value, 100 / 1.609344, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(U.convert("10 cm")).target.value, 10 / 2.54, accuracy: 1e-9)
        // Foundation's six-figure constants would show here: 3,785,410 instead of 3,785,412.
        let big = try XCTUnwrap(U.convert("1,000,000 gal"))
        XCTAssertEqual(U.format(big.target.value, decimalComma: false), "3,785,412")
        XCTAssertEqual(U.format(try XCTUnwrap(U.convert("10,000,000 lb")).target.value, decimalComma: false), "4,535,924",
                       "Foundation's 0.453592 would print 4,535,920")
    }

    func testEveryRatioUnitHasAnExactFactorAndOnlyTemperatureHasNone() {
        for u in U.Unit.allCases {
            XCTAssertEqual(u.factorToBase == nil, u.kind == .temperature, "\(u)")
        }
    }

    func testEveryUnitAndSpellingIsWellFormed() {
        for u in U.Unit.allCases {
            XCTAssertEqual(u.counterpart.kind, u.kind, "\(u) converts across kinds")
            XCTAssertNotEqual(u.counterpart, u, "\(u) converts to itself")
            XCTAssertFalse(u.symbol.isEmpty)
            XCTAssertEqual(U.spellings[u.symbol.lowercased()] ?? (u == .fluidOunceUS || u == .gallonUS ? u : nil), u,
                           "the symbol shown must also parse back (\(u.symbol))")
        }
        XCTAssertGreaterThan(U.spellings.count, 60)
        for (spelling, _) in U.spellings { XCTAssertEqual(spelling, spelling.lowercased(), "spellings are matched lowercased") }
    }

    func testFormattingIsShortAndNeverMinusZero() {
        XCTAssertEqual(U.format(3.1068559611866697, decimalComma: false), "3.11")
        XCTAssertEqual(U.format(3.1068559611866697, decimalComma: true), "3,11")
        XCTAssertEqual(U.format(22.222222222224616, decimalComma: false), "22.22", "the measured float noise is rounded away")
        XCTAssertEqual(U.format(1609.344, decimalComma: false), "1,609")
        XCTAssertEqual(U.format(1609.344, decimalComma: true), "1.609")
        XCTAssertEqual(U.format(0.45359237, decimalComma: false), "0.454")
        XCTAssertEqual(U.format(-40.000000000003425, decimalComma: false), "-40")
        XCTAssertEqual(U.format(-0.00001, decimalComma: false), "0")
        XCTAssertEqual(U.format(.nan, decimalComma: false), "–")
    }
}

final class TimeZoneConversionTests: XCTestCase {
    typealias T = TimeZoneConversion
    let hcm = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    let la = TimeZone(identifier: "America/Los_Angeles")!

    /// 2026-10-13 10:00 UTC: New York on EDT (−4), Los Angeles on PDT (−7), Paris on CEST (+2).
    let october = Date(timeIntervalSince1970: 1_791_885_600)
    /// 2026-01-15 10:00 UTC: everyone on standard time.
    let january = Date(timeIntervalSince1970: 1_768_471_200)

    func testReferenceDatesAreWhatTheTestsAssume() {
        XCTAssertEqual(TimeZone(identifier: "America/New_York")!.secondsFromGMT(for: october), -4 * 3600)
        XCTAssertEqual(TimeZone(identifier: "America/New_York")!.secondsFromGMT(for: january), -5 * 3600)
    }

    func testFixedAbbreviationsUseTheirDefinitionAndSayWhenTheRegionDisagrees() throws {
        let pst = try XCTUnwrap(T.convert("3pm PST", now: october, to: hcm))
        XCTAssertEqual(pst.sourceOffset, -8 * 3600, "PST is UTC−8 by definition")
        XCTAssertEqual([pst.localHour, pst.localMinute, pst.dayShift], [6, 0, 1], "15:00 −8 = 23:00 UTC = 06:00 +7 next day")
        XCTAssertEqual(pst.regionNote, T.RegionNote(regionID: "America/Los_Angeles", regionOffset: -7 * 3600))
        XCTAssertEqual(pst.regionNote?.city, "Los Angeles")

        let est = try XCTUnwrap(T.convert("9:30 am EST", now: january, to: hcm))
        XCTAssertNil(est.regionNote, "in January New York IS on EST")
        XCTAssertEqual([est.localHour, est.localMinute, est.dayShift], [21, 30, 0])
    }

    func testRegionAbbreviationsFollowTheRegion() throws {
        let pt = try XCTUnwrap(T.convert("3pm PT", now: october, to: hcm))
        XCTAssertEqual(pt.sourceOffset, -7 * 3600, "PT follows Los Angeles, on PDT in October")
        XCTAssertEqual([pt.localHour, pt.dayShift], [5, 1])
        XCTAssertNil(pt.regionNote)
    }

    func testOffsetsAndDayShifts() throws {
        let utc = try XCTUnwrap(T.convert("15:00 UTC", now: october, to: hcm))
        XCTAssertEqual([utc.localHour, utc.localMinute, utc.dayShift], [22, 0, 0])
        let india = try XCTUnwrap(T.convert("8pm UTC+5:30", now: october, to: hcm))
        XCTAssertEqual(india.zoneLabel, "UTC+5:30")
        XCTAssertEqual([india.localHour, india.localMinute], [21, 30])
        let back = try XCTUnwrap(T.convert("1am UTC", now: october, to: la))
        XCTAssertEqual([back.localHour, back.dayShift], [18, -1], "01:00 UTC is 18:00 the day before in Los Angeles")
        let paris = try XCTUnwrap(T.convert("15h30 CET", now: october, to: hcm))
        XCTAssertEqual([paris.localHour, paris.localMinute], [21, 30])
        XCTAssertEqual(paris.regionNote?.regionOffset, 2 * 3600, "Paris is on CEST in October")
        let same = try XCTUnwrap(T.convert("10:00 GMT+7", now: october, to: hcm))
        XCTAssertTrue(same.isSameAsLocal)
        XCTAssertEqual(try XCTUnwrap(T.convert("12am UTC", now: october, to: hcm)).sourceHour, 0)
        XCTAssertEqual(try XCTUnwrap(T.convert("12pm UTC", now: october, to: hcm)).sourceHour, 12)
    }

    func testAmbiguousUnknownAndMalformedAreRefused() {
        for bad in ["3pm CST", "3pm IST", "3pm BST", "3pm", "3pm XYZ", "25:00 UTC", "13pm PST", "0am UTC",
                    "3:60pm UTC", "8pm UTC+15", "8pm UTC+5:20", "meet at 3pm PST tomorrow please ok ok ok ok"] {
            XCTAssertNil(T.convert(bad, now: october, to: hcm), bad)
        }
    }

    func testClockAndOffsetLabels() {
        XCTAssertEqual(T.parseClock("3 PM").map { [$0.hour, $0.minute] }, [15, 0])
        XCTAssertEqual(T.parseClock("9:30 a.m.").map { [$0.hour, $0.minute] }, [9, 30])
        XCTAssertEqual(T.parseClock("15h30").map { [$0.hour, $0.minute] }, [15, 30])
        XCTAssertEqual(T.parseClock("23:59").map { [$0.hour, $0.minute] }, [23, 59])
        XCTAssertNil(T.parseClock("24:00"))
        XCTAssertEqual(T.offsetLabel(-5 * 3600), "UTC−5")
        XCTAssertEqual(T.offsetLabel(19_800), "UTC+5:30")
        XCTAssertEqual(T.offsetLabel(0), "UTC")
        XCTAssertEqual(T.clockLabel(hour: 6, minute: 5), "06:05")
    }
}
