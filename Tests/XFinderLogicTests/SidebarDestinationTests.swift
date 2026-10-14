import XCTest
import AppKit

/// P3 (2026-10-13) — the sidebar is a map of intentions (Part 0 §3). These pin the shape the settings shell renders:
/// every page reachable exactly once, every icon a real and unique SF Symbol (a missing symbol renders as nothing —
/// CLAUDE.md Part 3c), every title and group heading translated, and the notch pages together.
final class SidebarDestinationTests: XCTestCase {

    private var grouped: [SidebarDestination] { SidebarDestination.groups.flatMap(\.items) }

    func testEveryPageExceptAboutIsInExactlyOneGroup() {
        let counts = Dictionary(grouping: grouped, by: { $0 }).mapValues(\.count)
        for dest in SidebarDestination.allCases where dest != .about && dest.monitorRow == dest {
            XCTAssertEqual(counts[dest], 1, "\(dest.rawValue) must appear in exactly one sidebar group")
        }
        XCTAssertNil(counts[.about], "About is the footer row, never a group member")
        XCTAssertGreaterThan(SidebarDestination.allCases.count, 40, "the case list collapsed — the check would pass on nothing")
    }

    func testGroupHeadingsAreUniqueAndNonEmpty() {
        let headers = SidebarDestination.groups.map(\.header)
        XCTAssertEqual(Set(headers).count, headers.count, "ForEach(groups, id: \\.header) needs unique headings")
        XCTAssertFalse(headers.contains(where: \.isEmpty))
        XCTAssertGreaterThanOrEqual(headers.count, 7)
    }

    func testEveryIconIsARealSymbolAndNoTwoPagesShareOne() {
        var seen: [String: SidebarDestination] = [:]
        for dest in SidebarDestination.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: dest.icon, accessibilityDescription: nil),
                            "\(dest.rawValue): '\(dest.icon)' is not an SF Symbol on this macOS — the row would have no icon")
            if let other = seen[dest.icon] {
                XCTFail("\(dest.rawValue) and \(other.rawValue) share the icon '\(dest.icon)'")
            }
            seen[dest.icon] = dest
        }
    }

    func testEveryTitleAndHeadingIsTranslated() throws {
        let store = try L10nFixture.load()
        let allow = try L10nFixture.allowlist()
        var keys = SidebarDestination.allCases.map(\.titleKey)
        keys += SidebarDestination.groups.map(\.header)
        for key in keys {
            let entry = try XCTUnwrap(store.entries[key], "'\(key)' is not in the store — the English sidebar would show Vietnamese")
            XCTAssertFalse(entry.en.isEmpty, "'\(key)' has an empty English value")
            if entry.en == key {
                XCTAssertTrue(allow.contains(key), "'\(key)' is identical in English but not on the allowlist")
            }
        }
    }

    func testTheNotchPagesAreOneGroupAndTheOldCombinedTitleIsGone() throws {
        let notch = try XCTUnwrap(SidebarDestination.groups.first { $0.header == "NOTCH" }, "the NOTCH group is missing")
        XCTAssertEqual(notch.items, [.notchInterface, .dropTray, .media, .aiAgents, .calendar, .liveActivities])
        XCTAssertEqual(SidebarDestination.dropTray.titleKey, "Khay thả",
                       "the tray page no longer holds the notch settings — its title must not promise them")
        let general = try XCTUnwrap(SidebarDestination.groups.first { $0.header == "CHUNG" })
        XCTAssertTrue(general.items.contains(.shortcuts), "Phím tắt is app-wide, so it lives in CHUNG")
    }

    /// Hệ thống, Mạng, Ổ đĩa, Pin are one row ("Theo dõi hệ thống") with four tabs; the three tab cases are in no group,
    /// map to the row, and stay reachable (deep links, search).
    func testTheMonitorPagesAreOneRowWithFourTabs() throws {
        XCTAssertEqual(SidebarDestination.monitorTabs, [.system, .network, .storage, .pin])
        for tab in SidebarDestination.monitorTabs {
            XCTAssertEqual(tab.monitorRow, .system)
            XCTAssertEqual(grouped.filter { $0 == tab }.count, tab == .system ? 1 : 0, "\(tab.rawValue) is a tab, not a row")
        }
        XCTAssertEqual(SidebarDestination.antiSleep.monitorRow, .antiSleep, "every other page is its own row")
        XCTAssertEqual(SidebarDestination.system.titleKey, "Theo dõi hệ thống")
        XCTAssertEqual(SidebarDestination.system.tabTitleKey, "Hệ thống")
        XCTAssertEqual(Set(SidebarDestination.system.searchAlsoKeys), ["Hệ thống", "Mạng", "Ổ đĩa", "Pin"],
                       "searching a tab's name still finds the page")
        let store = try L10nFixture.load()
        for key in SidebarDestination.monitorTabs.map(\.tabTitleKey) + [SidebarDestination.system.titleKey] {
            guard let e = store.entries[key] else { XCTFail("\(key) is not in the store"); continue }
            XCTAssertFalse(e.en.isEmpty)
        }
    }

    func testEveryTileNameIsAColourTheViewMaps() {
        // The view maps each SidebarTile to an NSColor.system* — a case added here without a mapping would not compile
        // there, so this only pins that every page has a tile and the palette is not silently one colour.
        let used = Set(SidebarDestination.allCases.map(\.tile))
        XCTAssertGreaterThanOrEqual(used.count, 8, "the tiles collapsed to a few colours")
    }
}
