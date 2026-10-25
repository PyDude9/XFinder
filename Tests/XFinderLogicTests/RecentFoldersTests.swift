import XCTest

/// XF-T30 W3 — `RecentFolders`: MRU-10, dedupe-and-rebump, virtual locations never recorded, "Clear Menu", and the
/// `existing(_:)` filter used before the Go menu draws the list.
final class RecentFoldersTests: XCTestCase {

    // MARK: - note

    func testNoteAddsAPath() {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        XCTAssertEqual(folders.paths, ["/tmp/a"])
    }

    func testNoteKeepsNewestFirst() {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        folders.note("/tmp/b")
        XCTAssertEqual(folders.paths, ["/tmp/b", "/tmp/a"])
    }

    func testNoteDedupesAndRebumpsToTop() {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        folders.note("/tmp/b")
        folders.note("/tmp/a")
        XCTAssertEqual(folders.paths, ["/tmp/a", "/tmp/b"])
    }

    func testNoteDoesNotDuplicateAnAlreadyTopPath() {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        folders.note("/tmp/a")
        XCTAssertEqual(folders.paths, ["/tmp/a"])
    }

    func testNoteIgnoresEmptyPath() {
        var folders = RecentFolders()
        folders.note("")
        XCTAssertTrue(folders.paths.isEmpty)
    }

    func testNoteIgnoresVirtualLocationRecents() {
        var folders = RecentFolders()
        folders.note(VirtualLocation.recents.path)
        XCTAssertTrue(folders.paths.isEmpty)
    }

    func testNoteIgnoresVirtualLocationTag() {
        var folders = RecentFolders()
        folders.note(VirtualLocation.tag("Dự án").path)
        XCTAssertTrue(folders.paths.isEmpty)
    }

    func testNoteIgnoresVirtualLocationAllTags() {
        var folders = RecentFolders()
        folders.note(VirtualLocation.allTags.path)
        XCTAssertTrue(folders.paths.isEmpty)
    }

    func testNoteOfOrdinaryPathStillWorksAlongsideIgnoredVirtualOnes() {
        var folders = RecentFolders()
        folders.note(VirtualLocation.recents.path)
        folders.note("/tmp/real")
        XCTAssertEqual(folders.paths, ["/tmp/real"])
    }

    // MARK: - limit

    func testNoteCapsAtLimitDroppingOldest() {
        var folders = RecentFolders()
        for i in 0..<(RecentFolders.limit + 5) {
            folders.note("/tmp/\(i)")
        }
        XCTAssertEqual(folders.paths.count, RecentFolders.limit)
        XCTAssertEqual(folders.paths.first, "/tmp/\(RecentFolders.limit + 4)")
        XCTAssertFalse(folders.paths.contains("/tmp/0"))
    }

    func testRebumpingAnExistingPathNeverGrowsPastLimit() {
        var folders = RecentFolders()
        for i in 0..<RecentFolders.limit {
            folders.note("/tmp/\(i)")
        }
        folders.note("/tmp/0")   // already present — rebump, not a new 11th entry
        XCTAssertEqual(folders.paths.count, RecentFolders.limit)
        XCTAssertEqual(folders.paths.first, "/tmp/0")
    }

    func testLimitIsTen() {
        XCTAssertEqual(RecentFolders.limit, 10)
    }

    // MARK: - clear

    func testClearEmptiesTheList() {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        folders.clear()
        XCTAssertTrue(folders.paths.isEmpty)
    }

    func testClearOnAlreadyEmptyListIsHarmless() {
        var folders = RecentFolders()
        folders.clear()
        XCTAssertTrue(folders.paths.isEmpty)
    }

    // MARK: - existing filter

    func testExistingKeepsOnlyPathsThatStillExist() {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        folders.note("/tmp/b")
        let kept = folders.existing { $0 == "/tmp/b" }
        XCTAssertEqual(kept, ["/tmp/b"])
    }

    func testExistingPreservesNewestFirstOrder() {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        folders.note("/tmp/b")
        folders.note("/tmp/c")
        let kept = folders.existing { $0 != "/tmp/b" }
        XCTAssertEqual(kept, ["/tmp/c", "/tmp/a"])
    }

    func testExistingOnEmptyListReturnsEmpty() {
        let folders = RecentFolders()
        XCTAssertTrue(folders.existing { _ in true }.isEmpty)
    }

    func testExistingDoesNotMutateStoredPaths() {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        _ = folders.existing { _ in false }
        XCTAssertEqual(folders.paths, ["/tmp/a"])
    }

    // MARK: - Codable round-trip (stored as JSON under `fileBrowser.recentFolders`)

    func testEncodeDecodeRoundTrips() throws {
        var folders = RecentFolders()
        folders.note("/tmp/a")
        folders.note("/tmp/b")
        let data = try JSONEncoder().encode(folders)
        let decoded = try JSONDecoder().decode(RecentFolders.self, from: data)
        XCTAssertEqual(decoded, folders)
    }

    func testDefaultInitIsEmpty() {
        XCTAssertTrue(RecentFolders().paths.isEmpty)
    }
}
