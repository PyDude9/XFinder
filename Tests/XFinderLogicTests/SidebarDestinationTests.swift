import XCTest
import AppKit

/// P3 (2026-10-13) — the sidebar is a map of intentions (Part 0 §3). These pin the shape the settings shell renders:
/// every page reachable exactly once, every icon a real and unique SF Symbol (a missing symbol renders as nothing —
/// CLAUDE.md Part 3c), every title and group heading translated, and the notch pages together.
final class SidebarDestinationTests: XCTestCase {

    private var grouped: [SidebarDestination] { SidebarDestination.groups.flatMap(\.items) }

    func testEveryPageExceptAboutIsInExactlyOneGroup() {
        let counts = Dictionary(grouping: grouped, by: { $0 }).mapValues(\.count)
        // The footer rows (XF-T29 Pro, About) sit under the groups, never in one.
        for dest in SidebarDestination.allCases where dest != .about && dest != .pro && dest.hostRow == dest {
            XCTAssertEqual(counts[dest], 1, "\(dest.rawValue) must appear in exactly one sidebar group")
        }
        XCTAssertNil(counts[.about], "About is the footer row, never a group member")
        XCTAssertNil(counts[.pro], "Pro is a footer row, never a group member")
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
        XCTAssertEqual(notch.items, [.notchInterface, .dropTray, .media, .aiAgents, .calendar, .liveActivities,
                                    .stocks, .websiteAnalytics, .revenue])
        XCTAssertEqual(SidebarDestination.dropTray.titleKey, "Khay thả",
                       "the tray page no longer holds the notch settings — its title must not promise them")
        let general = try XCTUnwrap(SidebarDestination.groups.first { $0.header == "CHUNG" })
        XCTAssertTrue(general.items.contains(.shortcuts), "Phím tắt is app-wide, so it lives in CHUNG")
    }

    /// A tabbed row: its first member is the sidebar row, the other members are in no group, map to the row and stay
    /// reachable (deep links, search). A row's tabs are a segmented picker ⇒ 2…4 members, each page in one group at most.
    func testTabGroupsAreOneRowEachWithTwoToFourTabs() throws {
        XCTAssertFalse(SidebarDestination.tabGroups.isEmpty, "the check would pass on nothing")
        var seen = Set<SidebarDestination>()
        let store = try L10nFixture.load()
        for group in SidebarDestination.tabGroups {
            XCTAssertTrue((2...4).contains(group.count), "\(group.map(\.rawValue)): a segmented picker takes 2–4 tabs")
            let row = group[0]
            for tab in group {
                XCTAssertTrue(seen.insert(tab).inserted, "\(tab.rawValue) is in two tab groups")
                XCTAssertEqual(tab.hostRow, row)
                XCTAssertEqual(grouped.filter { $0 == tab }.count, tab == row ? 1 : 0, "\(tab.rawValue) is a tab, not a row")
                guard let e = store.entries[tab.tabTitleKey] else { XCTFail("\(tab.tabTitleKey) is not in the store"); continue }
                XCTAssertFalse(e.en.isEmpty)
            }
            XCTAssertEqual(Set(row.searchAlsoKeys), Set(group.map(\.tabTitleKey)), "searching a tab's name still finds its row")
            if let sub = row.tabbedSubtitleKey {
                XCTAssertNotNil(store.entries[sub], "\(sub) is not in the store")
            }
        }
        XCTAssertEqual(SidebarDestination.antiSleep.hostRow, .features, "antiSleep is merged into features hub")
        XCTAssertEqual(SidebarDestination.features.searchAlsoKeys, ["Chống ngủ"], "searching Chống ngủ finds features hub")
    }

    /// Hệ thống, Mạng, Ổ đĩa, Pin are one row ("Theo dõi hệ thống") — the first tab group.
    func testTheMonitorPagesAreOneRowWithFourTabs() {
        XCTAssertEqual(SidebarDestination.system.tabGroup, [.system, .network, .storage, .pin])
        XCTAssertEqual(SidebarDestination.pin.hostRow, .system)
        XCTAssertEqual(SidebarDestination.system.titleKey, "Theo dõi hệ thống")
        XCTAssertEqual(SidebarDestination.system.tabTitleKey, "Hệ thống")
    }

    func testEveryTileNameIsAColourTheViewMaps() {
        // The view maps each SidebarTile to an NSColor.system* — a case added here without a mapping would not compile
        // there, so this only pins that every page has a tile and the palette is not silently one colour.
        let used = Set(SidebarDestination.allCases.map(\.tile))
        XCTAssertGreaterThanOrEqual(used.count, 8, "the tiles collapsed to a few colours")
    }
}
