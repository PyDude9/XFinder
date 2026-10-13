import XCTest
import Foundation

/// N7 — when the What's New sheet appears and that every word it shows is in the store.
final class WhatsNewRulesTests: XCTestCase {
    typealias R = WhatsNewRules

    func testShowsOncePerVersionToExistingUsersWithNotes() {
        XCTAssertTrue(R.shouldShow(lastSeen: nil, current: "1.3.0", isExistingUser: true))
        XCTAssertTrue(R.shouldShow(lastSeen: "1.2.0", current: "1.3.0", isExistingUser: true))
        XCTAssertFalse(R.shouldShow(lastSeen: "1.3.0", current: "1.3.0", isExistingUser: true))
        XCTAssertFalse(R.shouldShow(lastSeen: nil, current: "1.3.0", isExistingUser: false), "a fresh install is on setup, not on the sheet")
        XCTAssertFalse(R.shouldShow(lastSeen: nil, current: "9.9.0", isExistingUser: true), "no notes for that version ⇒ no sheet")
        XCTAssertEqual(R.notes(for: "1.3.4").count, R.notes13.count, "a patch release carries its minor's notes")
        XCTAssertEqual(R.minor(" 1.3.0 "), "1.3")
    }

    func testEveryNoteKeyIsInTheStoreAndDestinationsAreRealPages() throws {
        let store = try L10nFixture.load()
        XCTAssertGreaterThanOrEqual(R.notes13.count, 5)
        for n in R.notes13 { for k in [n.titleKey, n.bodyKey] { XCTAssertNotNil(store.entries[k], k) } }
        XCTAssertEqual(Set(R.notes13.map(\.id)).count, R.notes13.count)
        // raw destinations must be real SidebarDestination cases — parsed from the model source, which the package
        // cannot compile (it imports SwiftUI)
        let src = try String(contentsOf: L10nFixture.repoRoot().appendingPathComponent("XFinder/Models/SidebarDestination.swift"), encoding: .utf8)
        let cases = Set(src.split(separator: "\n").compactMap { line -> String? in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("case ") else { return nil }
            return s.dropFirst(5).split(separator: " ").first.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: ",:"))
        })
        XCTAssertGreaterThan(cases.count, 20, "the case parse found too few destinations")
        for raw in R.notes13.compactMap(\.destinationRaw) { XCTAssertTrue(cases.contains(raw), "\(raw) is not a SidebarDestination case") }
    }
}
