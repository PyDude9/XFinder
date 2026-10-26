import XCTest

/// XF-T32 W0 §A — pure rules of the listing cache: freshness, size cap, eviction order, row round trip.
final class ListingCacheRulesTests: XCTestCase {
    private let token: ListingToken = ListingToken(modifiedNs: 1_700_000_000_123_456_789,
                                                   changedNs: 1_700_000_001_000_000_001, size: 640, inode: 42)

    // MARK: isFresh

    func testIdenticalTokenIsFresh() {
        XCTAssertTrue(ListingCacheRules.isFresh(stored: token, current: token))
    }

    func testFailedStatIsNeverFresh() {
        XCTAssertFalse(ListingCacheRules.isFresh(stored: token, current: nil))
    }

    func testEveryFieldChangeMakesItStale() {
        let variants: [ListingToken] = [
            ListingToken(modifiedNs: token.modifiedNs + 1, changedNs: token.changedNs, size: token.size, inode: token.inode),
            ListingToken(modifiedNs: token.modifiedNs, changedNs: token.changedNs + 1, size: token.size, inode: token.inode),
            ListingToken(modifiedNs: token.modifiedNs, changedNs: token.changedNs, size: token.size + 32, inode: token.inode),
            // Renamed-in folder: same times and size, another inode.
            ListingToken(modifiedNs: token.modifiedNs, changedNs: token.changedNs, size: token.size, inode: token.inode + 1),
        ]
        for variant in variants {
            XCTAssertFalse(ListingCacheRules.isFresh(stored: token, current: variant), "\(variant)")
        }
    }

    // MARK: shouldStore

    func testStoreLimitIsInclusiveAtTwentyThousand() {
        XCTAssertEqual(ListingCacheRules.maxCachedEntries, 20_000)
        XCTAssertTrue(ListingCacheRules.shouldStore(entryCount: 0))
        XCTAssertTrue(ListingCacheRules.shouldStore(entryCount: 58))
        XCTAssertTrue(ListingCacheRules.shouldStore(entryCount: 20_000))
        XCTAssertFalse(ListingCacheRules.shouldStore(entryCount: 20_001))
        XCTAssertFalse(ListingCacheRules.shouldStore(entryCount: 100_000))
        XCTAssertFalse(ListingCacheRules.shouldStore(entryCount: -1))
    }

    func testConstants() {
        XCTAssertEqual(ListingCacheRules.budgetBytes, 64 * 1024 * 1024)
        XCTAssertEqual(ListingCacheRules.schemaVersion, 1)
    }

    // MARK: evictionOrder

    private let mb: Int64 = 1 << 20

    func testUnderBudgetEvictsNothing() {
        let folders: [(path: String, updatedAt: Date, bytes: Int64)] = [("/a", Date(timeIntervalSince1970: 1), 10 * mb)]
        XCTAssertEqual(ListingCacheRules.evictionOrder(folders: folders, totalBytes: 10 * mb), [])
        XCTAssertEqual(ListingCacheRules.evictionOrder(folders: folders, totalBytes: ListingCacheRules.budgetBytes), [])
    }

    func testOldestGoFirstUntilUnderBudget() {
        let folders: [(path: String, updatedAt: Date, bytes: Int64)] = [
            ("/new", Date(timeIntervalSince1970: 300), 30 * mb),
            ("/old", Date(timeIntervalSince1970: 100), 20 * mb),
            ("/mid", Date(timeIntervalSince1970: 200), 30 * mb),
        ]
        // 80 MB total: dropping /old (20) leaves 60 ≤ 64.
        XCTAssertEqual(ListingCacheRules.evictionOrder(folders: folders, totalBytes: 80 * mb), ["/old"])
        // 100 MB total: /old → 80, /mid → 50.
        XCTAssertEqual(ListingCacheRules.evictionOrder(folders: folders, totalBytes: 100 * mb), ["/old", "/mid"])
    }

    func testEvictionStopsExactlyAtBudget() {
        let folders: [(path: String, updatedAt: Date, bytes: Int64)] = [
            ("/a", Date(timeIntervalSince1970: 1), 1 * mb),
            ("/b", Date(timeIntervalSince1970: 2), 1 * mb),
        ]
        XCTAssertEqual(ListingCacheRules.evictionOrder(folders: folders, totalBytes: 65 * mb), ["/a"])
    }

    func testTiesBreakByPathAndNegativeBytesFreeNothing() {
        let same: Date = Date(timeIntervalSince1970: 5)
        let folders: [(path: String, updatedAt: Date, bytes: Int64)] = [
            ("/z", same, 10 * mb), ("/a", same, -5), ("/m", same, 10 * mb),
        ]
        XCTAssertEqual(ListingCacheRules.evictionOrder(folders: folders, totalBytes: 70 * mb), ["/a", "/m"])
    }

    func testEverythingGoesWhenFoldersCannotCoverTheTotal() {
        let folders: [(path: String, updatedAt: Date, bytes: Int64)] = [("/a", Date(timeIntervalSince1970: 1), mb)]
        XCTAssertEqual(ListingCacheRules.evictionOrder(folders: folders, totalBytes: 200 * mb), ["/a"])
        XCTAssertEqual(ListingCacheRules.evictionOrder(folders: [], totalBytes: 200 * mb), [])
    }

    // MARK: ListingRow

    func testRowRoundTripKeepsEveryField() {
        var entry: DirectoryEntry = DirectoryEntry(name: "Ảnh chụp.png", path: "/Users/u/Ảnh chụp.png", kind: .file,
                                                   isPackage: false, isHidden: true, size: 12_345,
                                                   modified: Date(timeIntervalSince1970: 1_700_000_000.25),
                                                   created: Date(timeIntervalSince1970: 1_600_000_000.5), volumeID: 16_777_234)
        entry.hidesExtension = true
        entry.inode = UInt64.max
        entry.added = Date(timeIntervalSince1970: 1_650_000_000)
        entry.lastOpened = Date(timeIntervalSince1970: 1_690_000_000.75)
        entry.tags = ["Red", "Công việc"]
        let back: DirectoryEntry = ListingRow(entry).entry()
        XCTAssertEqual(back, entry)
        XCTAssertEqual(back.nameKey, entry.nameKey)
        XCTAssertEqual(back.tags, ["Red", "Công việc"])
    }

    func testRowKeepsNilAndEmptyTagsApart() {
        var bare: DirectoryEntry = DirectoryEntry(name: "a", path: "/a", kind: .directory, isPackage: false, isHidden: false,
                                                  size: -1, modified: Date(timeIntervalSince1970: 0),
                                                  created: Date(timeIntervalSince1970: 0), volumeID: 1)
        XCTAssertNil(ListingRow(bare).entry().tags)
        XCTAssertNil(ListingRow(bare).entry().inode)
        XCTAssertNil(ListingRow(bare).entry().added)
        bare.tags = []
        XCTAssertEqual(ListingRow(bare).entry().tags, [])
    }

    func testRowCodableRoundTripAndUnknownKind() throws {
        let entry: DirectoryEntry = DirectoryEntry(name: "x.app", path: "/A/x.app", kind: .directory, isPackage: true,
                                                   isHidden: false, size: -1, modified: Date(timeIntervalSince1970: 9),
                                                   created: Date(timeIntervalSince1970: 8), volumeID: 2)
        let row: ListingRow = ListingRow(entry)
        let data: Data = try JSONEncoder().encode(row)
        XCTAssertEqual(try JSONDecoder().decode(ListingRow.self, from: data), row)
        // A kind written by a newer schema reads back as .other, not a crash.
        let json: String = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"kind\":1", with: "\"kind\":200")
        XCTAssertNotEqual(json, String(decoding: data, as: UTF8.self))
        let alien: ListingRow = try JSONDecoder().decode(ListingRow.self, from: Data(json.utf8))
        XCTAssertEqual(alien.entry().kind, .other)
    }
}
