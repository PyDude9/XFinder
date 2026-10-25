import XCTest

/// XF-T30 W5a — saved searches keep the query + scope, never a frozen result list. Unique names (case-insensitively),
/// rename refusals, delete, sidebar toggle, and a tolerant decode where one bad entry costs only itself.
final class SavedSearchTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func testAddTrimsNameAndDefaultsEmptyToAPlaceholder() {
        var store = SavedSearchStore()
        let a = store.add(name: "  My Search  ", query: "report", scope: "mac", folder: nil, showInSidebar: false, now: now)
        XCTAssertEqual(a.name, "My Search")
        let b = store.add(name: "   ", query: "x", scope: "mac", folder: nil, showInSidebar: false, now: now)
        XCTAssertFalse(b.name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testAddKeepsQueryAndScopeExactlyNotAFrozenResultSet() {
        var store = SavedSearchStore()
        let s = store.add(name: "Weekly PDFs", query: "pdfs from last week", scope: "folder", folder: "/Users/alice/Reports",
                           showInSidebar: true, now: now)
        XCTAssertEqual(s.query, "pdfs from last week")
        XCTAssertEqual(s.scope, "folder")
        XCTAssertEqual(s.folder, "/Users/alice/Reports")
        XCTAssertEqual(s.showInSidebar, true)
    }

    func testNamesAreUniqueCaseInsensitively() {
        var store = SavedSearchStore()
        _ = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        let second = store.add(name: "reports", query: "b", scope: "mac", folder: nil, showInSidebar: false, now: now)
        XCTAssertNotEqual(second.name.lowercased(), "reports")
        XCTAssertEqual(store.searches.count, 2)
    }

    func testThirdCollidingNameGetsItsOwnSuffix() {
        var store = SavedSearchStore()
        _ = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        _ = store.add(name: "REPORTS", query: "b", scope: "mac", folder: nil, showInSidebar: false, now: now)
        let third = store.add(name: "reports", query: "c", scope: "mac", folder: nil, showInSidebar: false, now: now)
        let names = Set(store.searches.map { $0.name.lowercased() })
        XCTAssertEqual(names.count, 3, "all three names must be distinct: \(store.searches.map(\.name))")
        _ = third
    }

    func testRenameToAUniqueNameSucceeds() {
        var store = SavedSearchStore()
        let a = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        XCTAssertTrue(store.rename(a.id, to: "Monthly Reports"))
        XCTAssertEqual(store.searches.first { $0.id == a.id }?.name, "Monthly Reports")
    }

    func testRenameToAnEmptyNameIsRefused() {
        var store = SavedSearchStore()
        let a = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        XCTAssertFalse(store.rename(a.id, to: "   "))
        XCTAssertEqual(store.searches.first { $0.id == a.id }?.name, "Reports")
    }

    func testRenameToAnotherSearchsNameCaseInsensitivelyIsRefused() {
        var store = SavedSearchStore()
        let a = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        _ = store.add(name: "Invoices", query: "b", scope: "mac", folder: nil, showInSidebar: false, now: now)
        XCTAssertFalse(store.rename(a.id, to: "invoices"))
        XCTAssertEqual(store.searches.first { $0.id == a.id }?.name, "Reports")
    }

    func testRenameToItsOwnCurrentNameWithDifferentCaseIsAllowed() {
        var store = SavedSearchStore()
        let a = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        XCTAssertTrue(store.rename(a.id, to: "REPORTS"))
        XCTAssertEqual(store.searches.first { $0.id == a.id }?.name, "REPORTS")
    }

    func testRenameOfUnknownIdIsRefused() {
        var store = SavedSearchStore()
        _ = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        XCTAssertFalse(store.rename(UUID(), to: "New Name"))
    }

    func testDeleteRemovesOnlyThatEntry() {
        var store = SavedSearchStore()
        let a = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        let b = store.add(name: "Invoices", query: "b", scope: "mac", folder: nil, showInSidebar: false, now: now)
        store.delete(a.id)
        XCTAssertEqual(store.searches.map(\.id), [b.id])
    }

    func testDeleteOfUnknownIdDoesNothing() {
        var store = SavedSearchStore()
        let a = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        store.delete(UUID())
        XCTAssertEqual(store.searches.map(\.id), [a.id])
    }

    func testSetShowInSidebarTogglesOnlyTheNamedEntry() {
        var store = SavedSearchStore()
        let a = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        let b = store.add(name: "Invoices", query: "b", scope: "mac", folder: nil, showInSidebar: false, now: now)
        store.setShowInSidebar(a.id, true)
        XCTAssertEqual(store.searches.first { $0.id == a.id }?.showInSidebar, true)
        XCTAssertEqual(store.searches.first { $0.id == b.id }?.showInSidebar, false)
    }

    // MARK: decode — tolerant, one bad entry costs only itself

    func testEncodeThenDecodeRoundTrips() {
        var store = SavedSearchStore()
        _ = store.add(name: "Reports", query: "pdfs from last week", scope: "folder", folder: "/Users/alice/R",
                       showInSidebar: true, now: now)
        let decoded = SavedSearchStore.decode(store.encoded())
        XCTAssertEqual(decoded, store)
    }

    func testDecodeOfNilIsAnEmptyStoreNotACrash() {
        XCTAssertEqual(SavedSearchStore.decode(nil), SavedSearchStore())
    }

    func testDecodeOfEmptyDataIsAnEmptyStore() {
        XCTAssertEqual(SavedSearchStore.decode(Data()), SavedSearchStore())
    }

    func testDecodeOfTotalGarbageCostsNothing() {
        let garbage = Data("not json at all {{{".utf8)
        XCTAssertEqual(SavedSearchStore.decode(garbage), SavedSearchStore())
    }

    func testDecodeOfAJSONObjectInsteadOfAnArrayCostsNothing() {
        let notAnArray = Data("{\"a\": 1}".utf8)
        XCTAssertEqual(SavedSearchStore.decode(notAnArray), SavedSearchStore())
    }

    func testOneDamagedEntryCostsOnlyItself() {
        var store = SavedSearchStore()
        let good1 = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        let good2 = store.add(name: "Invoices", query: "b", scope: "folder", folder: "/x", showInSidebar: true, now: now)
        // Build a JSON array by hand: good1, a garbage object missing required fields, good2.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let goodData1 = try! encoder.encode(good1)
        let goodData2 = try! encoder.encode(good2)
        let good1Obj = try! JSONSerialization.jsonObject(with: goodData1)
        let good2Obj = try! JSONSerialization.jsonObject(with: goodData2)
        let garbageObj: [String: Any] = ["name": "Broken"] // missing id/query/scope/showInSidebar/created
        let combined = try! JSONSerialization.data(withJSONObject: [good1Obj, garbageObj, good2Obj])

        let decoded = SavedSearchStore.decode(combined)
        XCTAssertEqual(Set(decoded.searches.map(\.id)), [good1.id, good2.id], "only the two well-formed entries survive")
        XCTAssertEqual(decoded.searches.count, 2)
    }

    func testPositiveControlAllGoodEntriesSurviveWithNoGarbage() {
        var store = SavedSearchStore()
        _ = store.add(name: "Reports", query: "a", scope: "mac", folder: nil, showInSidebar: false, now: now)
        _ = store.add(name: "Invoices", query: "b", scope: "mac", folder: nil, showInSidebar: false, now: now)
        let decoded = SavedSearchStore.decode(store.encoded())
        XCTAssertEqual(decoded.searches.count, 2)
    }
}
