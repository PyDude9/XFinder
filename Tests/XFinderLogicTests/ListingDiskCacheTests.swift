import XCTest
import SQLite3

/// XF-T32 W0 §A — the SQLite listing cache against a database in a fresh temporary folder (never the real one).
final class ListingDiskCacheTests: XCTestCase {
    private var folder: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListingDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        dbURL = folder.appendingPathComponent("listing-cache.sqlite")
    }

    override func tearDownWithError() throws {
        if let folder: URL = folder { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: Fixtures

    private let token: ListingToken = ListingToken(modifiedNs: 1_761_000_000_123_456_789,
                                                   changedNs: 1_761_000_000_987_654_321, size: 1_856, inode: 9_001)

    /// A date exactly as `DirectoryReader` builds it from a `timespec`.
    private func readerDate(_ seconds: Int, _ nanos: Int) -> Date {
        Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1e9)
    }

    private func entry(_ index: Int, in parent: String = "/Users/u/Dir", name: String? = nil) -> DirectoryEntry {
        let fileName: String = name ?? "file \(index).txt"
        var result: DirectoryEntry = DirectoryEntry(
            name: fileName, path: parent + "/" + fileName, kind: index % 7 == 0 ? .directory : .file,
            isPackage: index % 11 == 0, isHidden: index % 5 == 0, size: Int64(index) * 1_031,
            modified: readerDate(1_700_000_000 + index, (index * 7_919) % 1_000_000_000),
            created: readerDate(1_600_000_000 + index, (index * 104_729) % 1_000_000_000), volumeID: 16_777_232)
        result.inode = UInt64(10_000 + index)
        result.hidesExtension = index % 3 == 0
        if index % 4 == 0 { result.added = readerDate(1_650_000_000 + index, 123_456_789) }
        if index % 6 == 0 { result.lastOpened = readerDate(1_690_000_000, 1) }
        if index % 8 == 0 { result.tags = ["Red"] } else if index % 8 == 1 { result.tags = [] }
        return result
    }

    private func entries(_ count: Int, in parent: String = "/Users/u/Dir") -> [DirectoryEntry] {
        (0..<count).map { entry($0, in: parent) }
    }

    // MARK: Round trip

    func testMissingFolderIsNil() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        let hit: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/nowhere")
        XCTAssertNil(hit)
    }

    func testStoreThenLookupIsExactAndKeepsOrder() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        let stored: [DirectoryEntry] = entries(64).reversed()
        await cache.store("/Users/u/Dir", token: token, entries: stored)
        let hit: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/Users/u/Dir")
        XCTAssertEqual(hit?.token, token)
        XCTAssertEqual(hit?.entries, stored)
        XCTAssertEqual(hit?.entries.map(\.nameKey), stored.map(\.nameKey))
        XCTAssertEqual(hit?.entries.map(\.tags), stored.map(\.tags))
        XCTAssertNil(hit?.entries.first(where: { $0.path.hasSuffix("/file 2.txt") })?.tags)
        XCTAssertEqual(hit?.entries.first(where: { $0.path.hasSuffix("/file 1.txt") })?.tags, [])
    }

    func testEmptyFolderIsCached() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/empty", token: token, entries: [])
        let hit: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/empty")
        XCTAssertEqual(hit?.token, token)
        XCTAssertEqual(hit?.entries.count, 0)
    }

    func testOddNamesSurviveByteForByte() async {
        let nfd: String = "Tie\u{0302}\u{0301}ng Vie\u{0323}\u{0302}t.txt"   // NFD, as HFS+/APFS listings may hand it over
        let names: [String] = [nfd, "line1\nline2", "emoji 🐙 ✅", "quote ' \" ; DROP TABLE listing_items;--", " lead"]
        let stored: [DirectoryEntry] = names.enumerated().map { entry($0.offset, name: $0.element) }
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/Users/u/Dir", token: token, entries: stored)
        let hit: [DirectoryEntry] = await cache.lookup("/Users/u/Dir")?.entries ?? []
        XCTAssertEqual(hit.map { Array($0.name.unicodeScalars) }, names.map { Array($0.unicodeScalars) })
        XCTAssertEqual(hit.map { Array($0.path.utf8) }, stored.map { Array($0.path.utf8) })
    }

    func testReaderShapedDatesComeBackBitIdentical() async {
        var generator: SystemRandomNumberGenerator = SystemRandomNumberGenerator()
        var stored: [DirectoryEntry] = []
        for index in 0..<2_000 {
            let seconds: Int = Int.random(in: -2_000_000_000...4_000_000_000, using: &generator)
            let nanos: Int = Int.random(in: 0..<1_000_000_000, using: &generator)
            var row: DirectoryEntry = entry(index)
            row = DirectoryEntry(name: row.name, path: row.path, kind: row.kind, isPackage: row.isPackage,
                                 isHidden: row.isHidden, size: row.size, modified: readerDate(seconds, nanos),
                                 created: readerDate(nanos % 1_000, 999_999_999), volumeID: row.volumeID)
            row.added = readerDate(seconds / 2, nanos)
            stored.append(row)
        }
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/dates", token: token, entries: stored)
        let hit: [DirectoryEntry] = await cache.lookup("/dates")?.entries ?? []
        XCTAssertEqual(hit.count, stored.count)
        for (back, original) in zip(hit, stored) {
            XCTAssertEqual(back.modified.timeIntervalSince1970.bitPattern, original.modified.timeIntervalSince1970.bitPattern)
            XCTAssertEqual(back.created.timeIntervalSince1970.bitPattern, original.created.timeIntervalSince1970.bitPattern)
            XCTAssertEqual(back.added, original.added)
        }
    }

    func testExtremeDatesClampInsteadOfTrapping() async {
        var row: DirectoryEntry = DirectoryEntry(name: "far", path: "/far", kind: .file, isPackage: false, isHidden: false,
                                                 size: 0, modified: .distantFuture, created: .distantPast, volumeID: 0)
        row.lastOpened = Date(timeIntervalSince1970: .infinity)
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/far", token: token, entries: [row])
        let back: DirectoryEntry? = await cache.lookup("/far")?.entries.first
        XCTAssertNotNil(back)
        XCTAssertGreaterThan(back?.modified.timeIntervalSince1970 ?? 0, 9_000_000_000)
        XCTAssertLessThan(back?.created.timeIntervalSince1970 ?? 0, -9_000_000_000)
        XCTAssertNotNil(back?.lastOpened)
    }

    // MARK: Store rules

    func testStoreReplacesThePreviousListing() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/d", token: token, entries: entries(30, in: "/d"))
        let newer: ListingToken = ListingToken(modifiedNs: 1, changedNs: 2, size: 3, inode: 4)
        let single: [DirectoryEntry] = [entry(99, in: "/d")]
        await cache.store("/d", token: newer, entries: single)
        let hit: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/d")
        XCTAssertEqual(hit?.token, newer)
        XCTAssertEqual(hit?.entries, single)
    }

    func testFoldersDoNotLeakIntoEachOther() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/a", token: token, entries: entries(3, in: "/a"))
        await cache.store("/a/b", token: token, entries: entries(5, in: "/a/b"))
        let a: Int? = await cache.lookup("/a")?.entries.count
        let ab: Int? = await cache.lookup("/a/b")?.entries.count
        XCTAssertEqual(a, 3)
        XCTAssertEqual(ab, 5)
    }

    func testOverTheCapIsNotStored() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/big", token: token, entries: entries(20_001, in: "/big"))
        let hit: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/big")
        XCTAssertNil(hit)
        XCTAssertFalse(ListingCacheRules.shouldStore(entryCount: 100_000))
    }

    func testInvalidateAndRemoveAll() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/a", token: token, entries: entries(3, in: "/a"))
        await cache.store("/b", token: token, entries: entries(3, in: "/b"))
        await cache.invalidate("/a")
        let a: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/a")
        let b: Int? = await cache.lookup("/b")?.entries.count
        XCTAssertNil(a)
        XCTAssertEqual(b, 3)
        await cache.removeAll()
        let afterAll: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/b")
        XCTAssertNil(afterAll)
        let bytes: Int64 = await cache.approximateBytes()
        XCTAssertGreaterThan(bytes, 0)
    }

    func testParallelStoresOfOneFolderNeverMix() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        let variants: [[DirectoryEntry]] = (1...12).map { count in entries(count * 10, in: "/same") }
        let sharedToken: ListingToken = token
        await withTaskGroup(of: Void.self) { group in
            for variant in variants {
                group.addTask { await cache.store("/same", token: sharedToken, entries: variant) }
            }
        }
        let hit: [DirectoryEntry] = await cache.lookup("/same")?.entries ?? []
        XCTAssertTrue(variants.contains(hit), "the stored listing is one whole variant, count \(hit.count)")
    }

    // MARK: Damage

    func testGarbageFileMissesThenRebuilds() async throws {
        try Data((0..<8_192).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: dbURL)
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        let first: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/a")
        XCTAssertNil(first)
        await cache.store("/a", token: token, entries: entries(4, in: "/a"))
        let second: Int? = await cache.lookup("/a")?.entries.count
        XCTAssertEqual(second, 4)
    }

    func testGarbageWrittenUnderAnOpenConnectionNeverCrashes() async throws {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        let stored: [DirectoryEntry] = entries(10, in: "/a")
        await cache.store("/a", token: token, entries: stored)
        for suffix in ["", "-wal"] {
            let path: String = dbURL.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try Data(repeating: 0xA5, count: 65_536).write(to: URL(fileURLWithPath: path))
            }
        }
        let hit: [DirectoryEntry]? = await cache.lookup("/a")?.entries
        if let hit: [DirectoryEntry] = hit { XCTAssertEqual(hit, stored) }   // either a miss or the right data
        await cache.store("/b", token: token, entries: entries(2, in: "/b"))
        _ = await cache.lookup("/b")
        _ = await cache.approximateBytes()
    }

    func testOtherSchemaVersionIsDroppedAndRebuilt() async throws {
        try rawExecute(["CREATE TABLE listing_folders (folder_path TEXT PRIMARY KEY, junk BLOB)",
                        "INSERT INTO listing_folders VALUES ('/a', x'00')",
                        "PRAGMA user_version=7"])
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        let stale: (token: ListingToken, entries: [DirectoryEntry])? = await cache.lookup("/a")
        XCTAssertNil(stale)
        await cache.store("/a", token: token, entries: entries(3, in: "/a"))
        let fresh: Int? = await cache.lookup("/a")?.entries.count
        XCTAssertEqual(fresh, 3)
        XCTAssertEqual(try rawScalar("PRAGMA user_version"), Int64(ListingCacheRules.schemaVersion))
    }

    func testExclusivelyLockedDatabaseMissesThenRecovers() async throws {
        await seed("/a", count: 3)
        let other: OpaquePointer = try XCTUnwrap(rawOpen())
        // EXCLUSIVE locking mode + a write keeps every other connection out until this one closes.
        XCTAssertEqual(sqlite3_exec(other, "PRAGMA locking_mode=EXCLUSIVE", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(other, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(other, "DELETE FROM listing_items WHERE 0", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(other, "COMMIT", nil, nil, nil), SQLITE_OK)
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        let lockedCount: Int? = await cache.lookup("/a")?.entries.count
        XCTAssertNil(lockedCount)
        await cache.store("/b", token: token, entries: entries(1, in: "/b"))   // busy: dropped, no crash
        let lockedBytes: Int64 = await cache.approximateBytes()
        XCTAssertEqual(lockedBytes, 0)
        sqlite3_close_v2(other)
        let recovered: Int? = await cache.lookup("/a")?.entries.count
        XCTAssertEqual(recovered, 3, "a locked DB is not mistaken for a damaged one (nothing discarded)")
    }

    /// Stores through a cache whose connection is closed before returning (the actor is released at scope end).
    private func seed(_ path: String, count: Int) async {
        let writer: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await writer.store(path, token: token, entries: entries(count, in: path))
    }

    // MARK: Budget

    func testOldestFolderIsEvictedPastTheBudget() async {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        let longParent: String = "/" + String(repeating: "p", count: 6_000)
        // Estimate per row ≈ (96 fixed + 6 000 path + name + 2 × folder path) × 3/2 ≈ 9.2 KB; × 1 500 rows ≈ 13.8 MB
        // per folder; 5 folders ≈ 69 MB > 64 MB ⇒ exactly the oldest one goes.
        for index in 0..<5 {
            await cache.store("/f\(index)", token: token, entries: entries(1_500, in: longParent + "\(index)"))
        }
        let oldestCount: Int? = await cache.lookup("/f0")?.entries.count
        let secondCount: Int? = await cache.lookup("/f1")?.entries.count
        let newest: Int? = await cache.lookup("/f4")?.entries.count
        XCTAssertNil(oldestCount)
        XCTAssertEqual(secondCount, 1_500, "only as many folders as needed are evicted")
        XCTAssertEqual(newest, 1_500)
        let bytes: Int64 = await cache.approximateBytes()
        XCTAssertLessThan(bytes, ListingCacheRules.budgetBytes + (16 << 20))
    }

    // MARK: Token

    func testCurrentTokenFollowsTheFolder() throws {
        let dir: URL = folder.appendingPathComponent("watched", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let first: ListingToken = try XCTUnwrap(ListingDiskCache.currentToken(for: dir.path))
        XCTAssertEqual(ListingDiskCache.currentToken(for: dir.path), first)
        let inode: UInt64 = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: dir.path))[.systemFileNumber]
            as? UInt64)
        XCTAssertEqual(first.inode, inode)

        try Data("x".utf8).write(to: dir.appendingPathComponent("new.txt"))
        let afterAdd: ListingToken? = ListingDiskCache.currentToken(for: dir.path)
        XCTAssertFalse(ListingCacheRules.isFresh(stored: first, current: afterAdd))

        // Renamed away and replaced by another folder of the same name ⇒ another inode ⇒ stale.
        try FileManager.default.moveItem(at: dir, to: folder.appendingPathComponent("moved", isDirectory: true))
        XCTAssertNil(ListingDiskCache.currentToken(for: dir.path))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let replaced: ListingToken = try XCTUnwrap(ListingDiskCache.currentToken(for: dir.path))
        XCTAssertNotEqual(replaced.inode, afterAdd?.inode)
        XCTAssertFalse(ListingCacheRules.isFresh(stored: try XCTUnwrap(afterAdd), current: replaced))
    }

    func testCurrentTokenFollowsASymlinkToItsTarget() throws {
        let target: URL = folder.appendingPathComponent("target", isDirectory: true)
        let other: URL = folder.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
        let link: URL = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let before: ListingToken = try XCTUnwrap(ListingDiskCache.currentToken(for: link.path))
        XCTAssertEqual(before, ListingDiskCache.currentToken(for: target.path), "the link is fingerprinted as its target")
        // A change inside the target never touches the link itself (lstat would stay equal).
        try Data("x".utf8).write(to: target.appendingPathComponent("new.txt"))
        XCTAssertFalse(ListingCacheRules.isFresh(stored: before, current: ListingDiskCache.currentToken(for: link.path)))
        // Retargeting the link ⇒ another inode.
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        XCTAssertEqual(ListingDiskCache.currentToken(for: link.path)?.inode, ListingDiskCache.currentToken(for: other.path)?.inode)
    }

    // MARK: Vacuum

    func testFreshDatabaseIsIncrementalAutoVacuumAndShrinksAfterRemoveAll() async throws {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/big", token: token, entries: entries(3_000, in: "/" + String(repeating: "q", count: 400)))
        let full: Int64 = await cache.approximateBytes()
        XCTAssertEqual(try rawScalar("PRAGMA auto_vacuum"), 2, "INCREMENTAL must be set before WAL writes page 1")
        await cache.removeAll()
        let emptied: Int64 = await cache.approximateBytes()
        XCTAssertLessThan(emptied, full / 4, "full=\(full) emptied=\(emptied)")
    }

    func testOldFileWithoutAutoVacuumIsRebuiltOnOpen() async throws {
        try rawExecute([
            "PRAGMA journal_mode=WAL",
            "CREATE TABLE junk (x)",
            "PRAGMA user_version=\(ListingCacheRules.schemaVersion)"
        ])
        XCTAssertEqual(try rawScalar("PRAGMA auto_vacuum"), 0)
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        _ = await cache.approximateBytes()
        XCTAssertEqual(try rawScalar("PRAGMA auto_vacuum"), 2)
    }

    // MARK: Measure

    /// 5 000 entries: contract target store < 150 ms, lookup < 30 ms (release, warm). Bounds here are generous for a
    /// debug test build; set LISTING_CACHE_PERF_OUT=<file> to record the measured milliseconds.
    func testFiveThousandEntriesStoreAndLookupTimes() async throws {
        let cache: ListingDiskCache = ListingDiskCache(databaseURL: dbURL)
        await cache.store("/warm", token: token, entries: entries(10, in: "/warm"))
        let rows: [DirectoryEntry] = entries(5_000, in: "/Users/u/Five")
        let clock: ContinuousClock = ContinuousClock()
        let storeStart: ContinuousClock.Instant = clock.now
        await cache.store("/Users/u/Five", token: token, entries: rows)
        let storeTime: Duration = clock.now - storeStart
        let lookupStart: ContinuousClock.Instant = clock.now
        let hit: [DirectoryEntry]? = await cache.lookup("/Users/u/Five")?.entries
        let lookupTime: Duration = clock.now - lookupStart
        XCTAssertEqual(hit?.count, 5_000)
        XCTAssertLessThan(storeTime, .milliseconds(1_500))
        XCTAssertLessThan(lookupTime, .milliseconds(500))
        if let out: String = ProcessInfo.processInfo.environment["LISTING_CACHE_PERF_OUT"] {
            let line: String = "store5000_ms=\(milliseconds(storeTime)) lookup5000_ms=\(milliseconds(lookupTime))\n"
            try? Data(line.utf8).write(to: URL(fileURLWithPath: out))
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let parts: (seconds: Int64, attoseconds: Int64) = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    // MARK: Raw SQLite helpers

    private func rawOpen() -> OpaquePointer? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close_v2(handle)
            return nil
        }
        return handle
    }

    private func rawExecute(_ statements: [String]) throws {
        let handle: OpaquePointer = try XCTUnwrap(rawOpen())
        defer { sqlite3_close_v2(handle) }
        for sql in statements { XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql) }
    }

    private func rawScalar(_ sql: String) throws -> Int64 {
        let handle: OpaquePointer = try XCTUnwrap(rawOpen())
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return sqlite3_column_int64(statement, 0)
    }
}
