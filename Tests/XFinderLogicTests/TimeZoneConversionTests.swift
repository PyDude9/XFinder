import XCTest

/// Locks down Smart Selection E3 — "the user selected `3pm PST`; show what time that is here".
///
/// Sibling of `TimeZoneConversionTests` in `SmartSelectConversionTests.swift` (which drives the
/// code through `convert`): this file drives the **table and the parsers directly** — the
/// `zone(for:)` decisions, the whole `ambiguous` refusal set, the offset syntax, and the
/// `maxLength` boundary — none of which the existing class exercises on its own.
///
/// Every expectation below is derived from `TimeZoneConversion.swift` plus a measurement of
/// the platform, never guessed. The `regionNote` tests are the ones that would go red if a
/// fixed abbreviation ever started following New York's daylight rules.
///
/// Pure values only: the reference date and the local zone are passed in, so nothing here
/// needs a running app, a permission, or a particular machine clock.
final class TimeZoneConversionEdgeCaseTests: XCTestCase {

    private let vietnam = TimeZone(identifier: "Asia/Ho_Chi_Minh")!  // UTC+7, no daylight time

    // MARK: - Helpers

    /// A date built in UTC so the fixtures do not depend on the machine's own zone.
    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - zone(for:)

    func testZoneFixedAbbreviationKeepsItsOffsetAndRegion() {
        let found = TimeZoneConversion.zone(for: "EST")
        XCTAssertEqual(found?.label, "EST")
        XCTAssertEqual(found?.zone.fixedOffset, -5 * 3600)
        XCTAssertEqual(found?.zone.regionID, "America/New_York")
    }

    func testZoneRegionFollowingAbbreviationHasNoFixedOffset() {
        let found = TimeZoneConversion.zone(for: "PT")
        XCTAssertEqual(found?.label, "PT")
        XCTAssertNil(found?.zone.fixedOffset)
        XCTAssertEqual(found?.zone.regionID, "America/Los_Angeles")
    }

    func testZoneRefusesEveryAmbiguousAbbreviation() {
        // The whole set, not a sample: adding one to `ambiguous` must extend the refusal.
        for token in TimeZoneConversion.ambiguous {
            XCTAssertNil(TimeZoneConversion.zone(for: token), "\(token) must be refused, not guessed")
        }
        XCTAssertTrue(TimeZoneConversion.ambiguous.contains("CST"))
        XCTAssertTrue(TimeZoneConversion.ambiguous.contains("IST"))
        XCTAssertTrue(TimeZoneConversion.ambiguous.contains("ECT"))
        XCTAssertTrue(TimeZoneConversion.ambiguous.contains("CDT/CST"))
    }

    func testZoneParsesUTCOffsetsAndNormalisesInput() {
        let plus7 = TimeZoneConversion.zone(for: "UTC+7")
        XCTAssertEqual(plus7?.label, "UTC+7")
        XCTAssertEqual(plus7?.zone.fixedOffset, 25200)
        XCTAssertNil(plus7?.zone.regionID)

        // Lower-case and a true minus sign (U+2212) are both normalised.
        let lower = TimeZoneConversion.zone(for: "est")
        XCTAssertEqual(lower?.label, "EST")
        XCTAssertEqual(lower?.zone.fixedOffset, -5 * 3600)

        let unicodeMinus = TimeZoneConversion.zone(for: "GMT\u{2212}5")
        XCTAssertEqual(unicodeMinus?.zone.fixedOffset, -5 * 3600)

        // Minutes are carried, and the label uses the true minus sign.
        let halfHour = TimeZoneConversion.zone(for: "GMT-5:30")
        XCTAssertEqual(halfHour?.label, "UTC\u{2212}5:30")
        XCTAssertEqual(halfHour?.zone.fixedOffset, -19800)
    }

    func testZoneRejectsInvalidOffsetsAndUnknownTokens() {
        // Minutes must be one of 0/15/30/45; a stray 07 is not a zone.
        XCTAssertNil(TimeZoneConversion.zone(for: "UTC+5:07"))
        XCTAssertNil(TimeZoneConversion.zone(for: "XYZ"))
        XCTAssertNil(TimeZoneConversion.zone(for: "UTC+"))
    }

    // MARK: - parseClock(_:)

    func testParseClockAcceptsWrittenForms() {
        XCTAssertEqual(TimeZoneConversion.parseClock("3pm")?.hour, 15)
        XCTAssertEqual(TimeZoneConversion.parseClock("3pm")?.minute, 0)
        XCTAssertEqual(TimeZoneConversion.parseClock("3:30pm")?.hour, 15)
        XCTAssertEqual(TimeZoneConversion.parseClock("3:30pm")?.minute, 30)
        XCTAssertEqual(TimeZoneConversion.parseClock("9:30 a.m.")?.hour, 9)
        XCTAssertEqual(TimeZoneConversion.parseClock("9:30 a.m.")?.minute, 30)
        XCTAssertEqual(TimeZoneConversion.parseClock("15:00")?.hour, 15)
        XCTAssertEqual(TimeZoneConversion.parseClock("15:00")?.minute, 0)
        XCTAssertEqual(TimeZoneConversion.parseClock("15h30")?.hour, 15)
        XCTAssertEqual(TimeZoneConversion.parseClock("15h30")?.minute, 30)
        XCTAssertEqual(TimeZoneConversion.parseClock("15h")?.hour, 15)
        XCTAssertEqual(TimeZoneConversion.parseClock("15h")?.minute, 0)
    }

    func testParseClockRejectsNonClockTimes() {
        XCTAssertNil(TimeZoneConversion.parseClock("13pm"))
        XCTAssertNil(TimeZoneConversion.parseClock("3:99pm"))
        XCTAssertNil(TimeZoneConversion.parseClock("25:00"))
        XCTAssertNil(TimeZoneConversion.parseClock("hello"))
    }

    // MARK: - convert(_:now:to:)

    func testConvertFixedOffsetDiffersFromLocal() {
        let result = TimeZoneConversion.convert("3pm UTC", now: utcDate(2026, 7, 15), to: vietnam)
        XCTAssertEqual(result?.zoneLabel, "UTC")
        XCTAssertEqual(result?.sourceOffset, 0)
        XCTAssertEqual(result?.localOffset, 7 * 3600)
        XCTAssertEqual(result?.isSameAsLocal, false)
    }

    /// The daylight-note rule: `EST` is written, but New York is on `EDT` in July, so the
    /// panel must say so — and the note's offset must be the real one, not a shipped guess.
    func testConvertAddsRegionNoteOnlyWhenTheRegionDisagrees() throws {
        let summer = try XCTUnwrap(TimeZoneConversion.convert("3pm EST", now: utcDate(2026, 7, 15), to: vietnam))
        let note = try XCTUnwrap(summer.regionNote)
        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(note.regionOffset, newYork.secondsFromGMT(for: summer.instant))
        XCTAssertNotEqual(note.regionOffset, -5 * 3600, "July in New York is EDT, not the written EST")
        XCTAssertEqual(note.city, "New York")

        // In January New York *is* on EST, so the note must disappear.
        let winter = try XCTUnwrap(TimeZoneConversion.convert("3pm EST", now: utcDate(2026, 1, 15), to: vietnam))
        XCTAssertNil(winter.regionNote)
        XCTAssertEqual(winter.sourceOffset, -5 * 3600)
    }

    func testConvertRegionFollowingZoneUsesTheRegionsOffsetOnThatDate() throws {
        let result = try XCTUnwrap(TimeZoneConversion.convert("3pm PT", now: utcDate(2026, 7, 15), to: vietnam))
        let la = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(result.sourceOffset, la.secondsFromGMT(for: result.instant))
        XCTAssertEqual(result.sourceOffset, -25200, "July in Los Angeles is PDT (UTC−7)")
        XCTAssertNil(result.regionNote, "a region-following zone never needs a note")
    }

    func testConvertReportsSameWallClockTime() throws {
        // ICT is UTC+7, the same as the local zone → Smart Selection must not offer a no-op.
        let result = try XCTUnwrap(TimeZoneConversion.convert("3pm ICT", now: utcDate(2026, 7, 15), to: vietnam))
        XCTAssertEqual(result.isSameAsLocal, true)
        XCTAssertEqual(result.localHour, 15)
        XCTAssertNil(result.regionNote)
    }

    func testConvertEnforcesMaxLengthBoundary() {
        XCTAssertEqual(TimeZoneConversion.maxLength, 40)
        let atLimit = "3pm" + String(repeating: " ", count: 34) + "UTC"  // 40 characters
        XCTAssertEqual(atLimit.count, 40)
        XCTAssertNotNil(TimeZoneConversion.convert(atLimit, now: utcDate(2026, 7, 15), to: vietnam))

        let overLimit = "3pm" + String(repeating: " ", count: 35) + "UTC"  // 41 characters
        XCTAssertEqual(overLimit.count, 41)
        XCTAssertNil(TimeZoneConversion.convert(overLimit, now: utcDate(2026, 7, 15), to: vietnam))
    }

    func testConvertRejectsUnknownZone() {
        XCTAssertNil(TimeZoneConversion.convert("3pm XYZ", now: utcDate(2026, 7, 15), to: vietnam))
    }

    // MARK: - Small value types

    func testRegionNoteCityName() {
        let note = TimeZoneConversion.RegionNote(regionID: "America/New_York", regionOffset: -14400)
        XCTAssertEqual(note.city, "New York")
    }

    func testOffsetLabelFormats() {
        XCTAssertEqual(TimeZoneConversion.offsetLabel(0), "UTC")
        XCTAssertEqual(TimeZoneConversion.offsetLabel(25200), "UTC+7")
        XCTAssertEqual(TimeZoneConversion.offsetLabel(-19800), "UTC\u{2212}5:30")
        XCTAssertEqual(TimeZoneConversion.offsetLabel(-18000), "UTC\u{2212}5")
    }

    func testClockLabelPads() {
        XCTAssertEqual(TimeZoneConversion.clockLabel(hour: 9, minute: 5), "09:05")
        XCTAssertEqual(TimeZoneConversion.clockLabel(hour: 15, minute: 0), "15:00")
    }
}
