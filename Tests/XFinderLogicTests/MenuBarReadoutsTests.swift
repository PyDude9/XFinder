import XCTest
import Foundation

final class MenuBarReadoutsTests: XCTestCase {
    typealias R = MenuBarReadouts
    private let fs = String(R.figureSpace)
    private let full = R.Snapshot(cpuPercent: 12.4, memoryUsedBytes: Int64(7.2 * 1_073_741_824), gpuPercent: 48, socTemperature: 51.4,
                                  batteryPercent: 80, downKBs: 1228.8, upKBs: 35.2)

    func testSelectionRoundTripsKeepsOrderDropsUnknownAndDuplicates() {
        XCTAssertEqual(R.decode(R.encode([.battery, .cpu])), [.battery, .cpu], "order is display order")
        XCTAssertEqual(R.decode("cpu, memory,cpu,bogus,"), [.cpu, .memory])
        XCTAssertEqual(R.decode(nil), R.defaultSelection, "never customised ⇒ the default pair")
        XCTAssertEqual(R.decode(""), [], "customised to nothing ⇒ nothing, not the default")
    }

    func testIntervalOnlyAcceptsOfferedChoices() {
        XCTAssertEqual(R.validInterval(30), 30)
        XCTAssertEqual(R.validInterval(0), R.defaultInterval, "a hand-edited 0 would be a busy loop")
        XCTAssertEqual(R.validInterval(-5), R.defaultInterval)
        XCTAssertEqual(R.validInterval(7), R.defaultInterval)
    }

    func testValuesAreFixedWidthSoTheTitleNeverJitters() {
        for kind in R.Kind.allCases {
            let widths = Set([
                R.value(kind, in: full).count,
                R.value(kind, in: R.Snapshot(cpuPercent: 100, memoryUsedBytes: 64 * 1_073_741_824, gpuPercent: 0, socTemperature: 105,
                                            batteryPercent: 7, downKBs: 0, upKBs: 999)).count,
                R.value(kind, in: R.Snapshot()).count,   // everything unavailable
            ])
            XCTAssertEqual(widths.count, 1, "\(kind) changes width: \(widths)")
        }
    }

    func testPaddingUsesFigureSpaceNotASpace() {
        XCTAssertEqual(R.percent(7), fs + fs + "7%")
        XCTAssertEqual(R.percent(100), "100%")
        XCTAssertFalse(R.percent(7).contains(" "), "a plain space is narrower than a digit and jitters")
    }

    func testUnavailableReadingsRenderAsDashNeverZero() {
        let empty = R.Snapshot()
        for kind in R.Kind.allCases {
            let v = R.value(kind, in: empty)
            XCTAssertTrue(v.contains(R.unavailable), "\(kind): \(v)")
            XCTAssertFalse(v.contains("0"), "\(kind) fabricated a zero: \(v)")
        }
        XCTAssertEqual(R.percent(.nan), fs + fs + "–%")
    }

    func testFormatsMatchThePages() {
        XCTAssertEqual(R.value(.memory, in: full), fs + "7.2G")
        XCTAssertEqual(R.value(.memory, in: R.Snapshot(memoryUsedBytes: 12 * 1_073_741_824)), fs + fs + "12G", "≥ 10 GB drops the decimal")
        XCTAssertEqual(R.value(.netDown, in: full), fs + "1.2M", "≥ 1 MB/s switches to MB/s like the Mạng page")
        XCTAssertEqual(R.value(.netUp, in: full), fs + fs + "35K")
        XCTAssertEqual(R.value(.socTemp, in: full), fs + "51°")
        XCTAssertEqual(R.value(.cpu, in: R.Snapshot(cpuPercent: 250)), "100%", "clamped, never 250 %")
    }

    func testTitleJoinsSelectionWithLabelsAndEmptySelectionIsEmpty() {
        let t = R.title(for: [.cpu, .socTemp, .netDown], snapshot: full, label: { $0 == "CPU" ? "CPU" : "?" })
        XCTAssertEqual(t, "CPU " + fs + "12%  " + fs + "51°  ?" + " " + fs + "1.2M")
        XCTAssertEqual(R.title(for: [], snapshot: full, label: { $0 }), "")
    }

    func testEveryKindTextResolvesInTheStore() throws {
        let store = try L10nFixture.load(); let allow = try L10nFixture.allowlist()
        for k in R.Kind.allCases {
            XCTAssertTrue(store.entries[k.titleKey] != nil || allow.contains(k.titleKey), "title not in store: \(k.titleKey)")
            if !k.labelKey.isEmpty, !["↓", "↑"].contains(k.labelKey) {
                XCTAssertTrue(store.entries[k.labelKey] != nil || allow.contains(k.labelKey), "label not in store: \(k.labelKey)")
            }
        }
    }

    func testLegacyHiderMigrationRunsOnceOnlyWhenNewKeyIsUnset() {
        XCTAssertTrue(R.shouldMigrateLegacyHider(hideOwnIconStored: nil, legacyHiderEnabled: true))
        XCTAssertFalse(R.shouldMigrateLegacyHider(hideOwnIconStored: nil, legacyHiderEnabled: false))
        XCTAssertFalse(R.shouldMigrateLegacyHider(hideOwnIconStored: nil, legacyHiderEnabled: nil))
        XCTAssertFalse(R.shouldMigrateLegacyHider(hideOwnIconStored: false, legacyHiderEnabled: true),
                       "explicit user choice to show icon must not be overwritten")
        XCTAssertFalse(R.shouldMigrateLegacyHider(hideOwnIconStored: true, legacyHiderEnabled: true))
    }

    func testNotchRecoveryTriggersOnlyWhenItemOverflowsNotchedRightArea() {
        // Non-notched display (auxiliaryTopRightArea width == 0): never triggers recovery
        XCTAssertFalse(R.needsNotchRecovery(itemMinX: 100, itemWidth: 24, auxiliaryTopRightMinX: 0, auxiliaryTopRightWidth: 0))
        // Notched display, item safely right of notch
        XCTAssertFalse(R.needsNotchRecovery(itemMinX: 1120, itemWidth: 24, auxiliaryTopRightMinX: 1000, auxiliaryTopRightWidth: 728))
        // Notched display, item pushed left into notch
        XCTAssertTrue(R.needsNotchRecovery(itemMinX: 980, itemWidth: 24, auxiliaryTopRightMinX: 1000, auxiliaryTopRightWidth: 728))
        // Notched display, item collapsed to zero width
        XCTAssertTrue(R.needsNotchRecovery(itemMinX: 1120, itemWidth: 0, auxiliaryTopRightMinX: 1000, auxiliaryTopRightWidth: 728))
    }
}
