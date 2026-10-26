import Foundation
import SQLite3

/// XF-T32 W0 §A — SQLite cache of directory listings, validated by the folder's own `lstat` (`ListingToken`).
/// Mechanism measured in Tilde's `DirectoryListingDiskCache`; the code is ours. One connection, owned by the actor
/// (every call is serialised, so two `store`s of one folder never interleave). The database is a regenerable cache:
/// a damaged file (`SQLITE_NOTADB` / `SQLITE_CORRUPT`) is discarded and rebuilt; a locked one only makes the call miss.
actor ListingDiskCache {
    static let shared: ListingDiskCache = ListingDiskCache(databaseURL: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XFinder/Browser/listing-cache.sqlite"))

    private let databaseURL: URL
    private var connection: ListingConnection?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    /// nil when absent, damaged, locked, or written by another schema version (that one is dropped and rebuilt).
    func lookup(_ folderPath: String) -> (token: ListingToken, entries: [DirectoryEntry])? {
        guard let db: ListingConnection = openIfNeeded() else { return nil }
        do {
            guard let header: ListingFolderHeader = try ListingQueries.folderHeader(db, folderPath: folderPath) else {
                return nil
            }
            let entries: [DirectoryEntry] = try ListingQueries.items(db, folderPath: folderPath,
                                                                    expectedCount: header.itemCount)
            guard entries.count == header.itemCount else { return nil }
            return (header.token, entries)
        } catch let failure as ListingCacheFailure {
            handle(failure)
            return nil
        } catch {
            return nil
        }
    }

    /// Replaces every row of the folder in ONE transaction; skipped when `!shouldStore`; then evicts to the budget.
    func store(_ folderPath: String, token: ListingToken, entries: [DirectoryEntry]) {
        guard ListingCacheRules.shouldStore(entryCount: entries.count) else { return }
        guard let db: ListingConnection = openIfNeeded() else { return }
        do {
            try db.transaction {
                try ListingQueries.deleteFolder(db, folderPath: folderPath)
                try ListingQueries.insertFolder(db, folderPath: folderPath, token: token, entries: entries)
            }
            try evictToBudget(db)
        } catch let failure as ListingCacheFailure {
            handle(failure)
        } catch {
            return
        }
    }

    func invalidate(_ folderPath: String) {
        guard let db: ListingConnection = openIfNeeded() else { return }
        do {
            try db.transaction { try ListingQueries.deleteFolder(db, folderPath: folderPath) }
        } catch let failure as ListingCacheFailure {
            handle(failure)
        } catch {
            return
        }
    }

    func removeAll() {
        guard let db: ListingConnection = openIfNeeded() else { return }
        do {
            try db.transaction {
                try db.execute("DELETE FROM listing_items")
                try db.execute("DELETE FROM listing_folders")
            }
            try db.execute("PRAGMA incremental_vacuum")
            try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        } catch let failure as ListingCacheFailure {
            handle(failure)
        } catch {
            return
        }
    }

    /// page_count × page_size of the main database file (0 when it cannot be opened).
    func approximateBytes() -> Int64 {
        guard let db: ListingConnection = openIfNeeded() else { return 0 }
        do {
            let pages: Int64 = try db.scalarInt64("PRAGMA page_count")
            let pageSize: Int64 = try db.scalarInt64("PRAGMA page_size")
            let (product, overflow): (Int64, Bool) = pages.multipliedReportingOverflow(by: pageSize)
            return overflow ? Int64.max : product
        } catch let failure as ListingCacheFailure {
            handle(failure)
            return 0
        } catch {
            return 0
        }
    }

    /// `lstat` of the folder itself (a symlink is fingerprinted as the link); nil when it fails.
    nonisolated static func currentToken(for folderPath: String) -> ListingToken? {
        var info: stat = stat()
        guard lstat(folderPath, &info) == 0 else { return nil }
        return ListingToken(modifiedNs: ListingTimestamp.nanoseconds(info.st_mtimespec),
                            changedNs: ListingTimestamp.nanoseconds(info.st_ctimespec),
                            size: Int64(info.st_size),
                            inode: UInt64(info.st_ino))
    }

    // MARK: - Connection lifecycle

    private func openIfNeeded() -> ListingConnection? {
        if let connection: ListingConnection = connection { return connection }
        for attempt in 0..<2 {
            do {
                let opened: ListingConnection = try ListingConnection(url: databaseURL)
                try ListingSchema.prepare(opened)
                connection = opened
                return opened
            } catch let failure as ListingCacheFailure {
                guard failure.isCorruption, attempt == 0 else { return nil }
                ListingDatabaseFiles.discard(databaseURL)
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Corruption ⇒ drop the connection and the files so the next call rebuilds; busy/locked ⇒ keep both, just miss.
    private func handle(_ failure: ListingCacheFailure) {
        guard failure.isCorruption else { return }
        connection = nil
        ListingDatabaseFiles.discard(databaseURL)
    }

    private func evictToBudget(_ db: ListingConnection) throws {
        let total: Int64 = try db.scalarInt64("SELECT COALESCE(SUM(bytes), 0) FROM listing_folders")
        guard total > ListingCacheRules.budgetBytes else { return }
        let folders: [(path: String, updatedAt: Date, bytes: Int64)] = try ListingQueries.folderSizes(db)
        let victims: [String] = ListingCacheRules.evictionOrder(folders: folders, totalBytes: total)
        guard !victims.isEmpty else { return }
        try db.transaction {
            for path in victims { try ListingQueries.deleteFolder(db, folderPath: path) }
        }
        try db.execute("PRAGMA incremental_vacuum")
    }
}

// MARK: - SQLite plumbing (private to this file; the file is also compiled into the test package)

/// `SQLITE_TRANSIENT`, declared here rather than reusing `DatabaseService.swift`'s global (not in the test package).
private let listingCacheTransient: sqlite3_destructor_type = unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)

private struct ListingCacheFailure: Error {
    let code: Int32

    var isCorruption: Bool {
        let primary: Int32 = code & 0xFF
        return primary == SQLITE_NOTADB || primary == SQLITE_CORRUPT
    }
}

private enum ListingDatabaseFiles {
    /// The cache file plus its WAL and shared-memory companions. App-owned regenerable cache, never user data.
    static func discard(_ url: URL) {
        let manager: FileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path: String = url.path + suffix
            if manager.fileExists(atPath: path) { try? manager.removeItem(atPath: path) }
        }
    }
}

private final class ListingConnection {
    let handle: OpaquePointer

    init(url: URL) throws {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var opened: OpaquePointer?
        let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let code: Int32 = sqlite3_open_v2(url.path, &opened, flags, nil)
        guard code == SQLITE_OK, let opened: OpaquePointer = opened else {
            if let opened: OpaquePointer = opened { sqlite3_close_v2(opened) }
            throw ListingCacheFailure(code: code)
        }
        handle = opened
        sqlite3_busy_timeout(handle, 250)
        sqlite3_extended_result_codes(handle, 1)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        let code: Int32 = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw ListingCacheFailure(code: code) }
    }

    func prepare(_ sql: String) throws -> ListingStatement {
        try ListingStatement(db: handle, sql: sql)
    }

    func scalarInt64(_ sql: String) throws -> Int64 {
        let statement: ListingStatement = try prepare(sql)
        guard try statement.step() else { return 0 }
        return statement.int64(0)
    }

    /// BEGIN IMMEDIATE … COMMIT; any throw rolls back and is rethrown.
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }
}

private final class ListingStatement {
    private let db: OpaquePointer
    private let handle: OpaquePointer

    init(db: OpaquePointer, sql: String) throws {
        var prepared: OpaquePointer?
        let code: Int32 = sqlite3_prepare_v2(db, sql, -1, &prepared, nil)
        guard code == SQLITE_OK, let prepared: OpaquePointer = prepared else {
            if let prepared: OpaquePointer = prepared { sqlite3_finalize(prepared) }
            throw ListingCacheFailure(code: code == SQLITE_OK ? SQLITE_ERROR : code)
        }
        self.db = db
        handle = prepared
    }

    deinit {
        sqlite3_finalize(handle)
    }

    /// true = a row is ready, false = done; anything else throws with the connection's error code.
    func step() throws -> Bool {
        let code: Int32 = sqlite3_step(handle)
        if code == SQLITE_ROW { return true }
        if code == SQLITE_DONE { return false }
        throw ListingCacheFailure(code: code)
    }

    func reset() {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    func bind(_ index: Int32, _ text: String) {
        let byteCount: Int32 = Int32(clamping: text.utf8.count)
        sqlite3_bind_text(handle, index, text, byteCount, listingCacheTransient)
    }

    func bind(_ index: Int32, _ text: String?) {
        guard let text: String = text else { sqlite3_bind_null(handle, index); return }
        bind(index, text)
    }

    func bind(_ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(handle, index, value)
    }

    func bind(_ index: Int32, _ value: Int64?) {
        guard let value: Int64 = value else { sqlite3_bind_null(handle, index); return }
        sqlite3_bind_int64(handle, index, value)
    }

    func bind(_ index: Int32, _ value: Double) {
        sqlite3_bind_double(handle, index, value)
    }

    func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(handle, column)
    }

    func optionalInt64(_ column: Int32) -> Int64? {
        isNull(column) ? nil : sqlite3_column_int64(handle, column)
    }

    func double(_ column: Int32) -> Double {
        sqlite3_column_double(handle, column)
    }

    /// Exact UTF-8 bytes back (NFD names stay NFD); NULL reads as nil.
    func text(_ column: Int32) -> String? {
        guard let bytes: UnsafePointer<UInt8> = sqlite3_column_text(handle, column) else { return nil }
        let count: Int = Int(sqlite3_column_bytes(handle, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }
}

private enum ListingSchema {
    static func prepare(_ db: ListingConnection) throws {
        try db.execute("PRAGMA journal_mode=WAL")
        try db.execute("PRAGMA synchronous=NORMAL")
        let version: Int64 = try db.scalarInt64("PRAGMA user_version")
        guard version != Int64(ListingCacheRules.schemaVersion) else { return }
        if version != 0 {
            try db.execute("DROP TABLE IF EXISTS listing_items")
            try db.execute("DROP TABLE IF EXISTS listing_folders")
        }
        // auto_vacuum only takes effect before the first table exists (or after VACUUM), so eviction can shrink the file.
        try db.execute("PRAGMA auto_vacuum=INCREMENTAL")
        if version != 0 { try db.execute("VACUUM") }
        try db.execute(createFolders)
        try db.execute(createItems)
        try db.execute("PRAGMA user_version=\(ListingCacheRules.schemaVersion)")
    }

    private static let createFolders: String = """
        CREATE TABLE IF NOT EXISTS listing_folders (
            folder_path TEXT PRIMARY KEY NOT NULL,
            modified_ns INTEGER NOT NULL,
            changed_ns INTEGER NOT NULL,
            size INTEGER NOT NULL,
            inode INTEGER NOT NULL,
            item_count INTEGER NOT NULL,
            bytes INTEGER NOT NULL,
            updated_at REAL NOT NULL
        )
        """

    private static let createItems: String = """
        CREATE TABLE IF NOT EXISTS listing_items (
            folder_path TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            kind INTEGER NOT NULL,
            is_package INTEGER NOT NULL,
            is_hidden INTEGER NOT NULL,
            size INTEGER NOT NULL,
            modified_ns INTEGER NOT NULL,
            created_ns INTEGER NOT NULL,
            volume_id INTEGER NOT NULL,
            hides_extension INTEGER NOT NULL,
            inode INTEGER,
            added_ns INTEGER,
            last_opened_ns INTEGER,
            tags_json TEXT,
            PRIMARY KEY (folder_path, sort_order)
        )
        """
}

private struct ListingFolderHeader {
    let token: ListingToken
    let itemCount: Int
}

private enum ListingQueries {
    static func folderHeader(_ db: ListingConnection, folderPath: String) throws -> ListingFolderHeader? {
        let statement: ListingStatement = try db.prepare("""
            SELECT modified_ns, changed_ns, size, inode, item_count FROM listing_folders WHERE folder_path = ?
            """)
        statement.bind(1, folderPath)
        guard try statement.step() else { return nil }
        let token: ListingToken = ListingToken(modifiedNs: statement.int64(0), changedNs: statement.int64(1),
                                               size: statement.int64(2),
                                               inode: UInt64(bitPattern: statement.int64(3)))
        let count: Int64 = statement.int64(4)
        guard count >= 0, count <= Int64(ListingCacheRules.maxCachedEntries) else { return nil }
        return ListingFolderHeader(token: token, itemCount: Int(count))
    }

    /// Rows in `sort_order`; a row that cannot be decoded (bad tags JSON, missing name) fails the whole listing.
    static func items(_ db: ListingConnection, folderPath: String, expectedCount: Int) throws -> [DirectoryEntry] {
        let statement: ListingStatement = try db.prepare("""
            SELECT name, path, kind, is_package, is_hidden, size, modified_ns, created_ns, volume_id, hides_extension,
                   inode, added_ns, last_opened_ns, tags_json
            FROM listing_items WHERE folder_path = ? ORDER BY sort_order
            """)
        statement.bind(1, folderPath)
        var entries: [DirectoryEntry] = []
        entries.reserveCapacity(expectedCount)
        let decoder: JSONDecoder = JSONDecoder()
        while try statement.step() {
            guard let entry: DirectoryEntry = decodeEntry(statement, decoder: decoder) else { return [] }
            entries.append(entry)
        }
        return entries
    }

    private static func decodeEntry(_ statement: ListingStatement, decoder: JSONDecoder) -> DirectoryEntry? {
        guard let name: String = statement.text(0), let path: String = statement.text(1) else { return nil }
        var tags: [String]? = nil
        if let json: String = statement.text(13) {
            guard let decoded: [String] = try? decoder.decode([String].self, from: Data(json.utf8)) else { return nil }
            tags = decoded
        }
        let rawKind: Int64 = statement.int64(2)
        let kind: DirectoryEntry.Kind = (0...255).contains(rawKind)
            ? (DirectoryEntry.Kind(rawValue: UInt8(rawKind)) ?? .other) : .other
        var entry: DirectoryEntry = DirectoryEntry(
            name: name, path: path, kind: kind,
            isPackage: statement.int64(3) != 0, isHidden: statement.int64(4) != 0, size: statement.int64(5),
            modified: ListingTimestamp.date(statement.int64(6)), created: ListingTimestamp.date(statement.int64(7)),
            volumeID: Int32(truncatingIfNeeded: statement.int64(8)))
        entry.hidesExtension = statement.int64(9) != 0
        entry.inode = statement.optionalInt64(10).map { UInt64(bitPattern: $0) }
        entry.added = statement.optionalInt64(11).map(ListingTimestamp.date)
        entry.lastOpened = statement.optionalInt64(12).map(ListingTimestamp.date)
        entry.tags = tags
        return entry
    }

    static func deleteFolder(_ db: ListingConnection, folderPath: String) throws {
        let items: ListingStatement = try db.prepare("DELETE FROM listing_items WHERE folder_path = ?")
        items.bind(1, folderPath)
        _ = try items.step()
        let folder: ListingStatement = try db.prepare("DELETE FROM listing_folders WHERE folder_path = ?")
        folder.bind(1, folderPath)
        _ = try folder.step()
    }

    /// Caller holds the transaction. Rows keep the order of `entries` (unsorted — `PaneState.applyEntries` sorts).
    static func insertFolder(_ db: ListingConnection, folderPath: String, token: ListingToken,
                             entries: [DirectoryEntry]) throws {
        let encoder: JSONEncoder = JSONEncoder()
        let insertItem: ListingStatement = try db.prepare("""
            INSERT INTO listing_items (folder_path, sort_order, name, path, kind, is_package, is_hidden, size,
                modified_ns, created_ns, volume_id, hides_extension, inode, added_ns, last_opened_ns, tags_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        var totalBytes: Int64 = 0
        for (order, entry) in entries.enumerated() {
            let tagsJSON: String? = try entry.tags.map { tags in
                String(decoding: try encoder.encode(tags), as: UTF8.self)
            }
            insertItem.reset()
            insertItem.bind(1, folderPath)
            insertItem.bind(2, Int64(order))
            insertItem.bind(3, entry.name)
            insertItem.bind(4, entry.path)
            insertItem.bind(5, Int64(entry.kind.rawValue))
            insertItem.bind(6, Int64(entry.isPackage ? 1 : 0))
            insertItem.bind(7, Int64(entry.isHidden ? 1 : 0))
            insertItem.bind(8, entry.size)
            insertItem.bind(9, ListingTimestamp.nanoseconds(entry.modified))
            insertItem.bind(10, ListingTimestamp.nanoseconds(entry.created))
            insertItem.bind(11, Int64(entry.volumeID))
            insertItem.bind(12, Int64(entry.hidesExtension ? 1 : 0))
            insertItem.bind(13, entry.inode.map { Int64(bitPattern: $0) })
            insertItem.bind(14, entry.added.map(ListingTimestamp.nanoseconds))
            insertItem.bind(15, entry.lastOpened.map(ListingTimestamp.nanoseconds))
            insertItem.bind(16, tagsJSON)
            _ = try insertItem.step()
            totalBytes &+= ListingRowSize.estimate(entry, tagsJSON: tagsJSON)
        }
        let insertHeader: ListingStatement = try db.prepare("""
            INSERT INTO listing_folders (folder_path, modified_ns, changed_ns, size, inode, item_count, bytes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """)
        insertHeader.bind(1, folderPath)
        insertHeader.bind(2, token.modifiedNs)
        insertHeader.bind(3, token.changedNs)
        insertHeader.bind(4, token.size)
        insertHeader.bind(5, Int64(bitPattern: token.inode))
        insertHeader.bind(6, Int64(entries.count))
        insertHeader.bind(7, totalBytes)
        insertHeader.bind(8, Date().timeIntervalSince1970)
        _ = try insertHeader.step()
    }

    static func folderSizes(_ db: ListingConnection) throws -> [(path: String, updatedAt: Date, bytes: Int64)] {
        let statement: ListingStatement = try db.prepare("SELECT folder_path, updated_at, bytes FROM listing_folders")
        var folders: [(path: String, updatedAt: Date, bytes: Int64)] = []
        while try statement.step() {
            guard let path: String = statement.text(0) else { continue }
            folders.append((path, Date(timeIntervalSince1970: statement.double(1)), statement.int64(2)))
        }
        return folders
    }
}

private enum ListingRowSize {
    /// Fixed columns + key overhead ≈ 96 bytes; the variable part is the text the row stores.
    static let fixedBytes: Int64 = 96

    static func estimate(_ entry: DirectoryEntry, tagsJSON: String?) -> Int64 {
        let variable: Int = entry.name.utf8.count + entry.path.utf8.count + (tagsJSON?.utf8.count ?? 0)
        return fixedBytes + Int64(variable)
    }
}

/// Dates are stored as nanoseconds since 1970 and rebuilt with the reader's own formula
/// (`Double(tv_sec) + Double(tv_nsec) / 1e9`), so a date that came from `DirectoryReader` reads back bit-identical
/// (a cached listing then diffs equal to a fresh disk read). Out-of-range dates clamp instead of trapping.
private enum ListingTimestamp {
    private static let nanosPerSecond: Int64 = 1_000_000_000
    private static let maxSeconds: Double = Double(Int64.max / 1_000_000_000) - 1

    static func nanoseconds(_ spec: timespec) -> Int64 {
        compose(seconds: Int64(spec.tv_sec), nanos: Int64(spec.tv_nsec))
    }

    static func nanoseconds(_ date: Date) -> Int64 {
        let interval: Double = date.timeIntervalSince1970
        guard interval.isFinite else { return interval > 0 ? Int64.max : (interval < 0 ? Int64.min : 0) }
        let clamped: Double = min(max(interval, -maxSeconds), maxSeconds)
        var seconds: Double = clamped.rounded(.down)
        var nanos: Int64 = Int64(((clamped - seconds) * 1e9).rounded())
        if nanos >= nanosPerSecond {
            seconds += 1
            nanos -= nanosPerSecond
        }
        return compose(seconds: Int64(seconds), nanos: nanos)
    }

    static func date(_ nanoseconds: Int64) -> Date {
        var seconds: Int64 = nanoseconds / nanosPerSecond
        var nanos: Int64 = nanoseconds % nanosPerSecond
        if nanos < 0 {
            seconds -= 1
            nanos += nanosPerSecond
        }
        return Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1e9)
    }

    private static func compose(seconds: Int64, nanos: Int64) -> Int64 {
        let (scaled, overflowMul): (Int64, Bool) = seconds.multipliedReportingOverflow(by: nanosPerSecond)
        if overflowMul { return seconds > 0 ? Int64.max : Int64.min }
        let (total, overflowAdd): (Int64, Bool) = scaled.addingReportingOverflow(nanos)
        if overflowAdd { return nanos > 0 ? Int64.max : Int64.min }
        return total
    }
}
