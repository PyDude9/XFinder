import XCTest

final class MenubarPanelRulesTests: XCTestCase {
    func testUnsleepPresetsIncludeIndefiniteAndPositiveDurations() {
        XCTAssertTrue(MenubarPanelRules.unsleepPresets.contains(where: { $0.minutes == 0 }))
        XCTAssertTrue(MenubarPanelRules.unsleepPresets.contains(where: { $0.minutes == 15 }))
        XCTAssertTrue(MenubarPanelRules.unsleepPresets.contains(where: { $0.minutes == 60 }))
    }

    func testFormatRemainingHandlesMinutesHoursAndNil() {
        XCTAssertNil(MenubarPanelRules.formatRemaining(seconds: nil))
        XCTAssertNil(MenubarPanelRules.formatRemaining(seconds: 0))
        XCTAssertEqual(MenubarPanelRules.formatRemaining(seconds: 65), "01:05")
        XCTAssertEqual(MenubarPanelRules.formatRemaining(seconds: 3720), "1h 02m")
    }

    func testCollapsedHeadersRoundTripAndWhitespace() {
        XCTAssertTrue(MenubarPanelRules.parseCollapsedHeaders("").isEmpty)
        XCTAssertTrue(MenubarPanelRules.parseCollapsedHeaders("  \n \n ").isEmpty)
        let encoded = MenubarPanelRules.encodeCollapsedHeaders([" NOTCH ", "CỬA SỔ", "", "  "])
        XCTAssertEqual(encoded, "CỬA SỔ\nNOTCH")
        XCTAssertEqual(MenubarPanelRules.parseCollapsedHeaders(encoded), Set(["CỬA SỔ", "NOTCH"]))
    }

    func testFormatTemp() {
        XCTAssertNil(MenubarPanelRules.formatTemp(nil))
        XCTAssertEqual(MenubarPanelRules.formatTemp(42.4), "42 °C")
        XCTAssertEqual(MenubarPanelRules.formatTemp(56.6), "57 °C")
    }

    func testFormatBatteryRemaining() {
        XCTAssertNil(MenubarPanelRules.formatBatteryRemaining(minutes: 0))
        XCTAssertNil(MenubarPanelRules.formatBatteryRemaining(minutes: -10))
        XCTAssertEqual(MenubarPanelRules.formatBatteryRemaining(minutes: 45), "45m")
        XCTAssertEqual(MenubarPanelRules.formatBatteryRemaining(minutes: 125), "2h 05m")
    }

    func testFormatRateKBsAndBytes() {
        XCTAssertEqual(MenubarPanelRules.formatRateKBs(-5), "0 KB/s")
        XCTAssertEqual(MenubarPanelRules.formatRateKBs(0), "0 KB/s")
        XCTAssertEqual(MenubarPanelRules.formatRateKBs(43), "43 KB/s")
        XCTAssertEqual(MenubarPanelRules.formatRateKBs(2764.8), "2.7 MB/s")

        XCTAssertEqual(MenubarPanelRules.formatBytes(0), "0 B")
        XCTAssertEqual(MenubarPanelRules.formatBytes(512), "512 B")
        XCTAssertEqual(MenubarPanelRules.formatBytes(454_000_000), "454 MB")
        XCTAssertEqual(MenubarPanelRules.formatBytes(11_430_000_000), "11.4 GB")
        XCTAssertEqual(MenubarPanelRules.formatBytes(1_500_000_000_000), "1.50 TB")
    }
}
