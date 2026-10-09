import XCTest
import Foundation

final class FlyoutLayoutTests: XCTestCase {
    private let all = ["controls", "antiSleep", "system", "network", "storage", "battery", "notes"]

    func testEncodeDecodeRoundTripsAndIsStable() {
        let h: Set<String> = ["notes", "battery"]
        XCTAssertEqual(FlyoutLayout.encode(h), "battery,notes", "sorted, so the stored string does not churn")
        XCTAssertEqual(FlyoutLayout.decode("battery,notes"), h)
        XCTAssertEqual(FlyoutLayout.decode(""), [])
        XCTAssertEqual(FlyoutLayout.decode(" battery , ,notes,"), h, "stray spaces and empties are ignored")
    }

    func testNothingHiddenByDefault() {
        XCTAssertEqual(FlyoutLayout.hidden(stored: nil, legacyShowBattery: nil, legacyShowNetwork: nil), [])
        XCTAssertEqual(FlyoutLayout.visible(all: all, hidden: []), all)
    }

    func testLegacyKeysAreHonouredOnlyUntilTheUserCustomises() {
        XCTAssertEqual(FlyoutLayout.hidden(stored: nil, legacyShowBattery: false, legacyShowNetwork: true), ["battery"])
        XCTAssertEqual(FlyoutLayout.hidden(stored: nil, legacyShowBattery: false, legacyShowNetwork: false), ["battery", "network"])
        XCTAssertEqual(FlyoutLayout.hidden(stored: nil, legacyShowBattery: true, legacyShowNetwork: true), [])
        // After the first customisation the new key wins outright — a stale legacy `false` must not
        // keep hiding a tab the user turned back on.
        XCTAssertEqual(FlyoutLayout.hidden(stored: "", legacyShowBattery: false, legacyShowNetwork: false), [],
                       "an EMPTY stored value means 'show everything', and is not the same as no value")
        XCTAssertEqual(FlyoutLayout.hidden(stored: "notes", legacyShowBattery: false, legacyShowNetwork: nil), ["notes"])
    }

    func testVisibleKeepsOrderAndIgnoresUnknownIds() {
        XCTAssertEqual(FlyoutLayout.visible(all: all, hidden: ["system", "storage"]),
                       ["controls", "antiSleep", "network", "battery", "notes"])
        XCTAssertEqual(FlyoutLayout.visible(all: all, hidden: ["from-a-future-version"]), all)
    }

    /// The popover must never be empty — not through the UI, and not through a hand-edited default.
    func testVisibleNeverReturnsAnEmptyList() {
        XCTAssertEqual(FlyoutLayout.visible(all: all, hidden: Set(all)), all)
        XCTAssertFalse(FlyoutLayout.visible(all: all, hidden: Set(all)).isEmpty)
    }

    func testTheLastVisibleTabCannotBeHidden() {
        let almost = Set(all.filter { $0 != "notes" })
        XCTAssertFalse(FlyoutLayout.canHide("notes", all: all, hidden: almost))
        XCTAssertEqual(FlyoutLayout.toggled("notes", all: all, hidden: almost), almost, "a refused hide changes nothing")
        XCTAssertTrue(FlyoutLayout.canHide("notes", all: all, hidden: []))
        XCTAssertTrue(FlyoutLayout.canHide("system", all: all, hidden: ["notes"]))
    }

    func testTogglingHidesAndRestores() {
        var h = Set<String>()
        h = FlyoutLayout.toggled("battery", all: all, hidden: h); XCTAssertEqual(h, ["battery"])
        h = FlyoutLayout.toggled("network", all: all, hidden: h); XCTAssertEqual(h, ["battery", "network"])
        h = FlyoutLayout.toggled("battery", all: all, hidden: h); XCTAssertEqual(h, ["network"], "toggling a hidden tab shows it")
    }

    /// Hide tabs one by one through the real toggle: however you do it, at least one stays.
    func testNoSequenceOfTogglesCanEmptyThePopover() {
        var h = Set<String>()
        for id in all + all.reversed() {
            h = FlyoutLayout.toggled(id, all: all, hidden: h)
            XCTAssertFalse(all.filter { !h.contains($0) }.isEmpty, "everything got hidden after toggling \(id)")
        }
    }

    func testSelectionMovesWhenItsTabIsHidden() {
        let vis = FlyoutLayout.visible(all: all, hidden: ["controls", "antiSleep"])
        XCTAssertEqual(FlyoutLayout.selection(current: "controls", visible: vis), "system", "first visible")
        XCTAssertEqual(FlyoutLayout.selection(current: "network", visible: vis), "network", "still visible: stay")
    }
}
