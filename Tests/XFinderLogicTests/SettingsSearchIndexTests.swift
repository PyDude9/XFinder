import XCTest

final class SettingsSearchIndexTests: XCTestCase {
    func testEveryDestinationHasNonEmptyKeywords() {
        for dest in SidebarDestination.allCases {
            let terms = SettingsSearchIndex.keywords(for: dest)
            XCTAssertFalse(terms.isEmpty, "SidebarDestination.\(dest.rawValue) should have search keywords")
            for term in terms {
                XCTAssertFalse(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "Empty keyword in SidebarDestination.\(dest.rawValue)")
            }
        }
    }

    func testDeepSettingQueriesFindExpectedDestinations() {
        func matches(_ dest: SidebarDestination, query: String) -> Bool {
            SidebarSearch.matches(query: query, texts: SettingsSearchIndex.keywords(for: dest))
        }

        XCTAssertTrue(matches(.settingsClipboard, query: "auto clear"))
        XCTAssertTrue(matches(.settingsClipboard, query: "touch id"))
        XCTAssertTrue(matches(.settingsClipboard, query: "mcp"))
        XCTAssertTrue(matches(.snapZones, query: "mru"))
        XCTAssertTrue(matches(.snapZones, query: "fixed space order"))
        XCTAssertTrue(matches(.features, query: "backup"))
        XCTAssertTrue(matches(.features, query: "dotfiles"))
        XCTAssertTrue(matches(.appQuit, query: "hold ⌘q"))
        XCTAssertTrue(matches(.mouseGestures, query: "smooth scroll"))
        XCTAssertTrue(matches(.aiAgents, query: "claude"))
        XCTAssertTrue(matches(.aiAgents, query: "codex"))
    }

    func testFirstMatchedKeywordReturnsHintForQueryAndNilWhenBlank() {
        XCTAssertNil(SettingsSearchIndex.firstMatchedKeyword(for: .snapZones, query: "   "))
        XCTAssertEqual(SettingsSearchIndex.firstMatchedKeyword(for: .snapZones, query: "mru"), "mru")
        XCTAssertEqual(SettingsSearchIndex.firstMatchedKeyword(for: .settingsClipboard, query: "snippet"), "snippet")
    }
}
