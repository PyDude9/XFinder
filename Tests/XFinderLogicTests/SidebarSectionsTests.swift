import XCTest

/// XF-T30 W3 — `SidebarCategory.defaultVisible`, `VirtualLocation` path round-trip, and `SidebarSections.headers`
/// ordering under every combination of visibility and the "Nhóm Vị trí theo loại" option.
final class SidebarSectionsTests: XCTestCase {

    // MARK: - SidebarCategory.defaultVisible

    func testBonjourDefaultsToHidden() {
        XCTAssertFalse(SidebarCategory.bonjour.defaultVisible)
    }

    func testEveryOtherCategoryDefaultsToVisible() {
        for category in SidebarCategory.allCases where category != .bonjour {
            XCTAssertTrue(category.defaultVisible, "\(category) should default to visible")
        }
    }

    // MARK: - VirtualLocation.path / parse round-trip

    func testRecentsPathRoundTrips() {
        XCTAssertEqual(VirtualLocation.parse(VirtualLocation.recents.path), .recents)
    }

    func testAllTagsPathRoundTrips() {
        XCTAssertEqual(VirtualLocation.parse(VirtualLocation.allTags.path), .allTags)
    }

    func testTagPathRoundTrips() {
        let location = VirtualLocation.tag("Dự án")
        XCTAssertEqual(VirtualLocation.parse(location.path), location)
    }

    func testTagPathPercentEncodesName() {
        // The raw Vietnamese name must not appear unescaped in the path (it is a URL-shaped string elsewhere in the
        // app, e.g. a session snapshot) — this also guards against silently losing the ability to round-trip it.
        let path = VirtualLocation.tag("Dự án").path
        XCTAssertFalse(path.contains(" "), "a space should be percent-encoded, not left bare")
    }

    func testTagNameContainingSlashRoundTrips() {
        // A Finder tag can be any string the person typed, including one with a "/" — this must never read back as
        // an extra path component or a different tag.
        let location = VirtualLocation.tag("A/B")
        XCTAssertEqual(VirtualLocation.parse(location.path), location)
    }

    func testTagNameContainingAmpersandAndQuestionMarkRoundTrips() {
        let location = VirtualLocation.tag("Q&A? Thẻ")
        XCTAssertEqual(VirtualLocation.parse(location.path), location)
    }

    func testDifferentTagNamesProduceDifferentPaths() {
        XCTAssertNotEqual(VirtualLocation.tag("A").path, VirtualLocation.tag("B").path)
    }

    func testParseOrdinaryFileSystemPathReturnsNil() {
        XCTAssertNil(VirtualLocation.parse("/Users/someone/Documents"))
    }

    func testParseEmptyPathReturnsNil() {
        XCTAssertNil(VirtualLocation.parse(""))
    }

    func testParseSchemeWithUnknownSuffixReturnsNil() {
        XCTAssertNil(VirtualLocation.parse(VirtualLocation.scheme + "something-unrecognised"))
    }

    func testParseTagPrefixWithEmptyNameReturnsNil() {
        XCTAssertNil(VirtualLocation.parse(VirtualLocation.scheme + "tag/"))
    }

    func testRecentsAndAllTagsHaveDistinctPaths() {
        XCTAssertNotEqual(VirtualLocation.recents.path, VirtualLocation.allTags.path)
    }

    // MARK: - SidebarSections.headers

    func testNoCategoriesVisibleProducesNoHeaders() {
        XCTAssertEqual(SidebarSections.headers(visible: [], groupLocationsByType: false), [])
    }

    func testEveryDefaultCategoryVisibleUngrouped() {
        let visible = Set(SidebarCategory.allCases.filter(\.defaultVisible))
        let headers = SidebarSections.headers(visible: visible, groupLocationsByType: false)
        // Order: Gần đây, AirDrop, iCloud Drive, Vị trí (ungrouped — Bonjour is off by default so no second "Mạng"), Thẻ, Tất cả thẻ…
        XCTAssertEqual(headers, ["Gần đây", "AirDrop", "iCloud Drive", "Vị trí", "Thẻ", "Tất cả thẻ…"])
    }

    func testRecentsHiddenOmitsItsHeaderOnly() {
        var visible = Set(SidebarCategory.allCases.filter(\.defaultVisible))
        visible.remove(.recents)
        let headers = SidebarSections.headers(visible: visible, groupLocationsByType: false)
        XCTAssertFalse(headers.contains("Gần đây"))
        XCTAssertEqual(headers, ["AirDrop", "iCloud Drive", "Vị trí", "Thẻ", "Tất cả thẻ…"])
    }

    func testNoLocationCategoryVisibleOmitsLocationsHeaderEntirely() {
        let headers = SidebarSections.headers(visible: [.recents], groupLocationsByType: false)
        XCTAssertEqual(headers, ["Gần đây"])
    }

    func testGroupLocationsByTypeSplitsIntoFourSubHeadersWhenAllFourVisible() {
        let visible: Set<SidebarCategory> = [.hardDisks, .externalDisks, .cloudStorage, .connectedServers]
        let headers = SidebarSections.headers(visible: visible, groupLocationsByType: true)
        XCTAssertEqual(headers, ["Cục bộ", "Ngoài", "Đám mây", "Mạng"])
    }

    func testGroupLocationsByTypeOmitsSubHeaderForAHiddenKind() {
        let visible: Set<SidebarCategory> = [.hardDisks, .cloudStorage]
        let headers = SidebarSections.headers(visible: visible, groupLocationsByType: true)
        XCTAssertEqual(headers, ["Cục bộ", "Đám mây"])
    }

    func testGroupingOptionIsIgnoredWhenNoLocationCategoryIsVisible() {
        let headers = SidebarSections.headers(visible: [.recents], groupLocationsByType: true)
        XCTAssertEqual(headers, ["Gần đây"])
    }

    func testOnlyOneLocationCategoryVisibleUngroupedStillShowsOneVịTríHeader() {
        let headers = SidebarSections.headers(visible: [.externalDisks], groupLocationsByType: false)
        XCTAssertEqual(headers, ["Vị trí"])
    }

    func testBonjourVisibleAddsNearbyComputersHeaderAfterLocations() {
        let visible: Set<SidebarCategory> = [.hardDisks, .bonjour]
        let headers = SidebarSections.headers(visible: visible, groupLocationsByType: false)
        XCTAssertEqual(headers, ["Vị trí", "Máy tính lân cận"])
    }

    func testBonjourAndGroupedConnectedServersProduceTwoDistinctHeadersNotTwoMạng() {
        // Grouping Vị trí by type renders a "Mạng" sub-header for already-connected servers; Bonjour renders a
        // different header for nearby, not-yet-connected computers. Both visible at once must not collide into two
        // identical "Mạng" rows that look like one merged section.
        let visible: Set<SidebarCategory> = [.connectedServers, .bonjour]
        let headers = SidebarSections.headers(visible: visible, groupLocationsByType: true)
        XCTAssertEqual(headers, ["Mạng", "Máy tính lân cận"])
        XCTAssertEqual(Set(headers).count, headers.count, "headers must be pairwise distinct")
    }

    func testRecentTagsHiddenOmitsBothThẻAndAllTagsHeaders() {
        let headers = SidebarSections.headers(visible: [.recents], groupLocationsByType: false)
        XCTAssertFalse(headers.contains("Thẻ"))
        XCTAssertFalse(headers.contains("Tất cả thẻ…"))
    }

    func testAllTagsHeaderAlwaysImmediatelyFollowsThẻHeader() {
        let visible: Set<SidebarCategory> = [.recentTags]
        let headers = SidebarSections.headers(visible: visible, groupLocationsByType: false)
        let tagsIndex = try! XCTUnwrap(headers.firstIndex(of: "Thẻ"))
        XCTAssertEqual(headers[headers.index(after: tagsIndex)], "Tất cả thẻ…")
    }

    func testHeaderOrderIsStableRegardlessOfSetIterationOrder() {
        // `visible` is a Set; the function must not depend on its (unspecified) iteration order.
        let a = SidebarSections.headers(visible: [.recents, .airDrop, .iCloud], groupLocationsByType: false)
        let b = SidebarSections.headers(visible: [.iCloud, .recents, .airDrop], groupLocationsByType: false)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, ["Gần đây", "AirDrop", "iCloud Drive"])
    }

    /// Mutant W27-08: a real folder whose path happens to end in "recents" past the scheme's length is NOT virtual.
    func testARealFolderNamedRecentsIsNotAVirtualLocation() {
        let path = "/tmp/abcdefghijkl/recents"              // 18 characters before "recents", like the scheme
        XCTAssertEqual(VirtualLocation.scheme.count, 18)
        XCTAssertNil(VirtualLocation.parse(path))
        XCTAssertNil(VirtualLocation.parse("/Users/me/all-tags"))
    }
}
