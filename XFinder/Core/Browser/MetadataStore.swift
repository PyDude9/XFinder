import Foundation
import SQLite3

/// SQLite's "copy the bytes now" destructor. Private to this file on purpose: the app's global `SQLITE_TRANSIENT`
/// lives in `DatabaseService.swift`, which is not part of the test package.
private let metadataStoreTransient: sqlite3_destructor_type = unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)

/// XF-T32 W1 (contract §C): the sidecar SQLite for custom properties, pins, nicknames, folder emoji and folder
/// relations. Every path key is normalised (no trailing `/`) and every row that hangs off a folder stores
/// `parent_path`, so "in folder" reads hit an index instead of scanning. Renames/moves rewrite every path column
/// with an exact prefix comparison (`substr`), never `LIKE`, so `'`, `%` and `_` in names are plain characters.
/// A corrupt file is renamed to `<name>.corrupt-<unix-ts>` (never deleted) and a fresh database is created.
actor MetadataStore {
    static let shared = MetadataStore(databaseURL: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XFinder/Browser/metadata.sqlite"))

    static let schemaVersion: Int32 = 1

    private let databaseURL: URL
    /// The connection lives in a plain class so its `deinit` closes it: an actor's nonisolated `deinit` may not read
    /// a non-Sendable `OpaquePointer` (Swift 6 error in the app target).
    private let handle: MetadataConnectionHandle = MetadataConnectionHandle()
    private var db: OpaquePointer? {
        get { handle.db }
        set { handle.db = newValue }
    }
    private var openFailed: Bool = false
    private var token: Int = 0

    init(databaseURL: URL) { self.databaseURL = databaseURL }

    // MARK: - Properties

    func catalog() -> PropertyCatalog {
        let blobs: [Data] = query("SELECT json FROM catalog WHERE id = 0", []) { stmt in Self.columnData(stmt, 0) }
        return PropertyCatalog.decode(blobs.first)
    }

    /// Saves the catalog and removes the selections/visibility of what this save REMOVED: a property or option
    /// that was in the stored catalog and is gone from the new one. Ids the stored catalog never knew (a damaged
    /// row, a newer build's property) are left alone — a smaller decode must never wipe user data.
    func saveCatalog(_ catalog: PropertyCatalog) {
        defer { bumpToken() }
        let valid: [String: Set<String>] = Self.validOptions(catalog)
        transaction { () -> Bool in
            let previous: [String: Set<String>] = Self.validOptions(self.catalog())
            guard run("INSERT OR REPLACE INTO catalog(id, json) VALUES (0, ?)", [.blob(catalog.encoded())]) else {
                return false
            }
            for (property, oldOptions) in previous {
                guard let newOptions: Set<String> = valid[property] else {
                    guard run("DELETE FROM selections WHERE property_id = ?", [.text(property)]),
                          run("DELETE FROM folder_properties WHERE property_id = ?", [.text(property)]) else { return false }
                    continue
                }
                for option in oldOptions.subtracting(newOptions) {
                    guard run("DELETE FROM selections WHERE property_id = ? AND option_id = ?",
                              [.text(property), .text(option)]) else { return false }
                }
            }
            return true
        }
    }

    func selections(property: UUID) -> [String: UUID] {
        var cache: UUIDCache = UUIDCache()
        let rows: [(String, UUID)] = query("SELECT item_path, option_id FROM selections WHERE property_id = ?",
                                           [.text(property.uuidString)]) { stmt in
            guard let path: String = Self.columnText(stmt, 0),
                  let option: UUID = cache.uuid(Self.columnText(stmt, 1)) else { return nil }
            return (path, option)
        }
        return Dictionary(rows, uniquingKeysWith: { first, _ in first })
    }

    func selections(in folder: String) -> [UUID: [String: UUID]] {
        groupedSelections("SELECT property_id, item_path, option_id FROM selections WHERE parent_path = ?",
                          [.text(Self.normalized(folder))])
    }

    func allSelections() -> [UUID: [String: UUID]] {
        groupedSelections("SELECT property_id, item_path, option_id FROM selections", [])
    }

    func select(path: String, property: UUID, option: UUID?) {
        defer { bumpToken() }
        let item: String = Self.normalized(path)
        guard let option else {
            _ = run("DELETE FROM selections WHERE item_path = ? AND property_id = ?",
                    [.text(item), .text(property.uuidString)])
            return
        }
        _ = run("""
            INSERT OR REPLACE INTO selections(item_path, parent_path, property_id, option_id) VALUES (?, ?, ?, ?)
            """, [.text(item), .text(Self.parent(of: item)), .text(property.uuidString), .text(option.uuidString)])
    }

    func folderProperties(_ folder: String) -> [(property: UUID, showInView: Bool)] {
        query("SELECT property_id, show_in_view FROM folder_properties WHERE folder_path = ? ORDER BY sort_order",
              [.text(Self.normalized(folder))]) { stmt in
            guard let id: UUID = Self.columnText(stmt, 0).flatMap(UUID.init(uuidString:)) else { return nil }
            return (property: id, showInView: sqlite3_column_int64(stmt, 1) != 0)
        }
    }

    func setFolderProperties(_ folder: String, _ list: [(property: UUID, showInView: Bool)]) {
        defer { bumpToken() }
        let key: String = Self.normalized(folder)
        var seen: Set<UUID> = []
        let unique: [(property: UUID, showInView: Bool)] = list.filter { seen.insert($0.property).inserted }
        transaction { () -> Bool in
            guard run("DELETE FROM folder_properties WHERE folder_path = ?", [.text(key)]) else { return false }
            for (index, item) in unique.enumerated() {
                guard run("""
                    INSERT INTO folder_properties(folder_path, property_id, show_in_view, sort_order) VALUES (?, ?, ?, ?)
                    """, [.text(key), .text(item.property.uuidString), .int(item.showInView ? 1 : 0), .int(Int64(index))])
                else { return false }
            }
            return true
        }
    }

    // MARK: - Pins / nicknames / emoji / relations

    func pins(in folder: String) -> [String] {
        query("SELECT item_path FROM pins WHERE folder_path = ? ORDER BY sort_order",
              [.text(Self.normalized(folder))]) { stmt in Self.columnText(stmt, 0) }
    }

    func setPins(_ pins: [String], in folder: String) {
        defer { bumpToken() }
        let key: String = Self.normalized(folder)
        var seen: Set<String> = []
        let unique: [String] = pins.map(Self.normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
        let capped: [String] = Array(unique.prefix(PinRules.maxPinsPerFolder))
        transaction { () -> Bool in
            guard run("DELETE FROM pins WHERE folder_path = ?", [.text(key)]) else { return false }
            for (index, item) in capped.enumerated() {
                guard run("INSERT INTO pins(folder_path, item_path, sort_order) VALUES (?, ?, ?)",
                          [.text(key), .text(item), .int(Int64(index))]) else { return false }
            }
            return true
        }
    }

    func nickname(for path: String) -> String? {
        let rows: [String] = query("SELECT nickname FROM nicknames WHERE item_path = ?",
                                   [.text(Self.normalized(path))]) { stmt in Self.columnText(stmt, 0) }
        return rows.first
    }

    func nicknames(in folder: String) -> [String: String] {
        pairs("SELECT item_path, nickname FROM nicknames WHERE parent_path = ?", [.text(Self.normalized(folder))])
    }

    func allNicknames() -> [String: String] {
        pairs("SELECT item_path, nickname FROM nicknames", [])
    }

    func setNickname(_ nickname: String?, for path: String) {
        defer { bumpToken() }
        let item: String = Self.normalized(path)
        guard let raw: String = nickname, let nickname: String = NicknameRules.normalized(raw) else {
            _ = run("DELETE FROM nicknames WHERE item_path = ?", [.text(item)])
            return
        }
        _ = run("INSERT OR REPLACE INTO nicknames(item_path, parent_path, nickname) VALUES (?, ?, ?)",
                [.text(item), .text(Self.parent(of: item)), .text(nickname)])
    }

    func emoji(for folder: String) -> String? {
        let rows: [String] = query("SELECT emoji FROM emoji WHERE folder_path = ?",
                                   [.text(Self.normalized(folder))]) { stmt in Self.columnText(stmt, 0) }
        return rows.first
    }

    func setEmoji(_ emoji: String?, for folder: String) {
        defer { bumpToken() }
        let key: String = Self.normalized(folder)
        // Anything that is not one emoji (EmojiRules) clears the folder's emoji instead of storing text.
        guard let raw: String = emoji, let emoji: String = EmojiRules.normalized(raw) else {
            _ = run("DELETE FROM emoji WHERE folder_path = ?", [.text(key)])
            return
        }
        _ = run("INSERT OR REPLACE INTO emoji(folder_path, emoji) VALUES (?, ?)", [.text(key), .text(emoji)])
    }

    func relations() -> [FolderRelation] {
        query("SELECT id, a, b FROM relations ORDER BY rowid", []) { stmt in
            guard let id: UUID = Self.columnText(stmt, 0).flatMap(UUID.init(uuidString:)),
                  let a: String = Self.columnText(stmt, 1), let b: String = Self.columnText(stmt, 2) else { return nil }
            return FolderRelation(id: id, a: a, b: b)
        }
    }

    func setRelations(_ relations: [FolderRelation]) {
        defer { bumpToken() }
        transaction { () -> Bool in
            guard run("DELETE FROM relations", []) else { return false }
            for relation in relations {
                guard run("INSERT OR REPLACE INTO relations(id, a, b) VALUES (?, ?, ?)",
                          [.text(relation.id.uuidString), .text(Self.normalized(relation.a)),
                           .text(Self.normalized(relation.b))]) else { return false }
            }
            return true
        }
    }

    // MARK: - Disk events

    func itemMoved(from: String, to: String) {
        let source: String = Self.normalized(from)
        let target: String = Self.normalized(to)
        guard source != target, Self.isMovable(source), !target.isEmpty else { return }
        defer { bumpToken() }
        let newParent: String = Self.parent(of: target)
        transaction { () -> Bool in
            // parent_path first (not part of any key), then the keyed path columns with OR REPLACE so a stale row at
            // the destination is overwritten instead of aborting the whole move.
            for table in ["selections", "nicknames"] {
                guard rewrite(table: table, column: "parent_path", from: source, to: target, conflict: ""),
                      run("UPDATE \(table) SET parent_path = ? WHERE item_path = ?", [.text(newParent), .text(source)])
                else { return false }
            }
            let keyed: [(table: String, column: String)] = [
                ("selections", "item_path"), ("nicknames", "item_path"),
                ("folder_properties", "folder_path"), ("pins", "folder_path"), ("pins", "item_path"),
                ("emoji", "folder_path"), ("relations", "a"), ("relations", "b"),
            ]
            for entry in keyed {
                guard rewrite(table: entry.table, column: entry.column, from: source, to: target, conflict: " OR REPLACE")
                else { return false }
            }
            return true
        }
    }

    func itemRemoved(_ path: String) {
        let item: String = Self.normalized(path)
        guard Self.isMovable(item) else { return }
        defer { bumpToken() }
        let columns: [(table: String, column: String)] = [
            ("selections", "item_path"), ("nicknames", "item_path"), ("folder_properties", "folder_path"),
            ("pins", "folder_path"), ("pins", "item_path"), ("emoji", "folder_path"), ("relations", "a"),
            ("relations", "b"),
        ]
        transaction { () -> Bool in
            for entry in columns {
                guard run("DELETE FROM \(entry.table) WHERE \(Self.subtreeClause(entry.column))",
                          [.text(item), .text(item), .text(item)]) else { return false }
            }
            return true
        }
    }

    func changeToken() -> Int { token }

    // MARK: - Private: path helpers

    /// The stored spelling of a path: NFC (SQLite compares bytes, and a name can reach us as NFD from an old HFS+
    /// copy or a paste), runs of `/` collapsed, trailing `/` stripped (root stays `/`). Empty stays empty.
    /// Keys read back are NFC; Swift `String` equality is canonical, so `dict[entry.path]` still matches an NFD path.
    static func normalized(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        var result: String = ""
        result.reserveCapacity(path.utf8.count)
        var lastWasSlash: Bool = false
        for character in path.precomposedStringWithCanonicalMapping {
            if character == "/" {
                if lastWasSlash { continue }
                lastWasSlash = true
            } else {
                lastWasSlash = false
            }
            result.append(character)
        }
        if result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// Parent of a normalised absolute path: "/a/b" → "/a", "/a" → "/", "/" → "", "name" → "".
    private static func parent(of path: String) -> String {
        guard path != "/", let slash: String.Index = path.lastIndex(of: "/") else { return "" }
        if slash == path.startIndex { return "/" }
        return String(path[path.startIndex..<slash])
    }

    /// The root (and the empty path) would match every row; never rewrite or delete by them.
    private static func isMovable(_ path: String) -> Bool { !path.isEmpty && path != "/" }


    /// `column` is the path itself or one of its descendants. Binds the path three times.
    private static func subtreeClause(_ column: String) -> String {
        "(\(column) = ? OR substr(\(column), 1, length(?) + 1) = ? || '/')"
    }

    private func rewrite(table: String, column: String, from source: String, to target: String, conflict: String) -> Bool {
        run("UPDATE\(conflict) \(table) SET \(column) = ? || substr(\(column), length(?) + 1) WHERE \(Self.subtreeClause(column))",
            [.text(target), .text(source), .text(source), .text(source), .text(source)])
    }

    private static func validOptions(_ catalog: PropertyCatalog) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for definition in catalog.definitions {
            result[definition.id.uuidString] = Set(definition.options.map { $0.id.uuidString })
        }
        return result
    }

    private func bumpToken() { token &+= 1 }

    // MARK: - Private: grouped reads

    /// Parses repeated UUID strings once (10 000 selections share a handful of property/option ids).
    private struct UUIDCache {
        private var parsed: [String: UUID] = [:]
        mutating func uuid(_ text: String?) -> UUID? {
            guard let text else { return nil }
            if let hit: UUID = parsed[text] { return hit }
            guard let value: UUID = UUID(uuidString: text) else { return nil }
            parsed[text] = value
            return value
        }
    }

    private func groupedSelections(_ sql: String, _ args: [SQLValue]) -> [UUID: [String: UUID]] {
        var cache: UUIDCache = UUIDCache()
        var result: [UUID: [String: UUID]] = [:]
        _ = query(sql, args) { (stmt: OpaquePointer) -> Bool? in
            guard let property: UUID = cache.uuid(Self.columnText(stmt, 0)),
                  let path: String = Self.columnText(stmt, 1),
                  let option: UUID = cache.uuid(Self.columnText(stmt, 2)) else { return nil }
            result[property, default: [:]][path] = option
            return nil
        }
        return result
    }

    private func pairs(_ sql: String, _ args: [SQLValue]) -> [String: String] {
        let rows: [(String, String)] = query(sql, args) { stmt in
            guard let key: String = Self.columnText(stmt, 0), let value: String = Self.columnText(stmt, 1) else { return nil }
            return (key, value)
        }
        return Dictionary(rows, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Private: SQLite plumbing

    private enum SQLValue {
        case text(String)
        case int(Int64)
        case blob(Data)
    }

    private enum OpenOutcome {
        case opened(OpaquePointer)
        case corrupt
        case failed
    }

    private func connection() -> OpaquePointer? {
        if let db { return db }
        if openFailed { return nil }
        let directory: URL = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch Self.open(databaseURL) {
        case .opened(let handle):
            db = handle
        case .corrupt:
            Self.quarantine(databaseURL)
            if case .opened(let handle) = Self.open(databaseURL) { db = handle } else { openFailed = true }
        case .failed:
            openFailed = true
        }
        return db
    }

    /// Opens, verifies and migrates. Only "not a database" / "corrupt" outcomes are reported as `.corrupt`; any
    /// other failure (permissions, disk full) leaves the file alone.
    private static func open(_ url: URL) -> OpenOutcome {
        var handle: OpaquePointer?
        let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let openCode: Int32 = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard openCode == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            return isCorruption(openCode) ? .corrupt : .failed
        }
        sqlite3_busy_timeout(handle, 2_000)
        let setupCode: Int32 = setUp(handle)
        guard setupCode == SQLITE_OK else {
            sqlite3_close_v2(handle)
            return isCorruption(setupCode) ? .corrupt : .failed
        }
        return .opened(handle)
    }

    private static func isCorruption(_ code: Int32) -> Bool {
        let primary: Int32 = code & 0xFF
        return primary == SQLITE_NOTADB || primary == SQLITE_CORRUPT
    }

    private static let schemaSQL: String = """
        CREATE TABLE IF NOT EXISTS catalog(id INTEGER PRIMARY KEY CHECK (id = 0), json BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS selections(item_path TEXT NOT NULL, parent_path TEXT NOT NULL,
            property_id TEXT NOT NULL, option_id TEXT NOT NULL, PRIMARY KEY(item_path, property_id));
        CREATE INDEX IF NOT EXISTS selections_property ON selections(property_id);
        CREATE INDEX IF NOT EXISTS selections_parent ON selections(parent_path);
        CREATE TABLE IF NOT EXISTS folder_properties(folder_path TEXT NOT NULL, property_id TEXT NOT NULL,
            show_in_view INTEGER NOT NULL, sort_order INTEGER NOT NULL, PRIMARY KEY(folder_path, property_id));
        CREATE TABLE IF NOT EXISTS pins(folder_path TEXT NOT NULL, item_path TEXT NOT NULL,
            sort_order INTEGER NOT NULL, PRIMARY KEY(folder_path, item_path));
        CREATE TABLE IF NOT EXISTS nicknames(item_path TEXT PRIMARY KEY NOT NULL, parent_path TEXT NOT NULL,
            nickname TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS nicknames_parent ON nicknames(parent_path);
        CREATE TABLE IF NOT EXISTS emoji(folder_path TEXT PRIMARY KEY NOT NULL, emoji TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS relations(id TEXT PRIMARY KEY NOT NULL, a TEXT NOT NULL, b TEXT NOT NULL);
        """

    /// Returns the first non-OK code. `quick_check` catches a file with a valid header but damaged pages.
    private static func setUp(_ handle: OpaquePointer) -> Int32 {
        var check: String?
        let checkCode: Int32 = step(handle, "PRAGMA quick_check(1)") { stmt in check = columnText(stmt, 0) }
        guard checkCode == SQLITE_OK else { return checkCode }
        guard check == "ok" else { return SQLITE_CORRUPT }
        for sql in ["PRAGMA journal_mode=WAL", "PRAGMA synchronous=NORMAL"] {
            let code: Int32 = step(handle, sql) { _ in }
            guard code == SQLITE_OK else { return code }
        }
        var version: Int32 = 0
        let versionCode: Int32 = step(handle, "PRAGMA user_version") { stmt in version = sqlite3_column_int(stmt, 0) }
        guard versionCode == SQLITE_OK else { return versionCode }
        let schemaCode: Int32 = sqlite3_exec(handle, schemaSQL, nil, nil, nil)
        guard schemaCode == SQLITE_OK else { return schemaCode }
        if version < schemaVersion {
            return sqlite3_exec(handle, "PRAGMA user_version = \(schemaVersion)", nil, nil, nil)
        }
        return SQLITE_OK
    }

    /// Prepares and steps one parameterless statement, calling `row` for every result row.
    private static func step(_ handle: OpaquePointer, _ sql: String, row: (OpaquePointer) -> Void) -> Int32 {
        var stmt: OpaquePointer?
        let prepareCode: Int32 = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard prepareCode == SQLITE_OK, let stmt else { return prepareCode }
        defer { sqlite3_finalize(stmt) }
        while true {
            let code: Int32 = sqlite3_step(stmt)
            if code == SQLITE_ROW { row(stmt); continue }
            return code == SQLITE_DONE ? SQLITE_OK : code
        }
    }

    /// Renames the database (and its WAL/SHM side files) to `<name>.corrupt-<unix-ts>`. Never deletes.
    private static func quarantine(_ url: URL) {
        let stamp: Int = Int(Date().timeIntervalSince1970)
        let manager: FileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let source: URL = URL(fileURLWithPath: url.path + suffix)
            guard manager.fileExists(atPath: source.path) else { continue }
            var destination: URL = URL(fileURLWithPath: "\(source.path).corrupt-\(stamp)")
            var attempt: Int = 2
            while manager.fileExists(atPath: destination.path) {
                destination = URL(fileURLWithPath: "\(source.path).corrupt-\(stamp)-\(attempt)")
                attempt += 1
            }
            try? manager.moveItem(at: source, to: destination)
        }
    }

    private func prepare(_ sql: String, _ args: [SQLValue]) -> OpaquePointer? {
        guard let handle: OpaquePointer = connection() else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        for (offset, value) in args.enumerated() {
            let index: Int32 = Int32(offset + 1)
            let code: Int32
            switch value {
            case .text(let text):
                code = sqlite3_bind_text(stmt, index, text, -1, metadataStoreTransient)
            case .int(let number):
                code = sqlite3_bind_int64(stmt, index, number)
            case .blob(let data):
                code = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
                    // A zero-length blob must still be a blob, not NULL (NOT NULL column).
                    guard let base: UnsafeRawPointer = raw.baseAddress, raw.count > 0 else {
                        return sqlite3_bind_zeroblob(stmt, index, 0)
                    }
                    return sqlite3_bind_blob(stmt, index, base, Int32(raw.count), metadataStoreTransient)
                }
            }
            guard code == SQLITE_OK else { sqlite3_finalize(stmt); return nil }
        }
        return stmt
    }

    @discardableResult
    private func run(_ sql: String, _ args: [SQLValue]) -> Bool {
        guard let stmt: OpaquePointer = prepare(sql, args) else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    /// Steps a query; rows for which `row` returns nil are skipped (malformed rows never abort a read).
    private func query<T>(_ sql: String, _ args: [SQLValue], row: (OpaquePointer) -> T?) -> [T] {
        guard let stmt: OpaquePointer = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let value: T = row(stmt) { result.append(value) }
        }
        return result
    }

    /// Runs `body` inside `BEGIN IMMEDIATE`; commits when it returns true, rolls back otherwise.
    private func transaction(_ body: () -> Bool) {
        guard run("BEGIN IMMEDIATE", []) else { return }
        if body(), run("COMMIT", []) { return }
        run("ROLLBACK", [])
    }

    private static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let bytes: UnsafePointer<UInt8> = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: bytes)
    }

    private static func columnData(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        let count: Int32 = sqlite3_column_bytes(stmt, index)
        guard let base: UnsafeRawPointer = sqlite3_column_blob(stmt, index), count > 0 else {
            return sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : Data()
        }
        return Data(bytes: base, count: Int(count))
    }
}

/// Owns the store's SQLite connection and closes it when the store goes away.
private final class MetadataConnectionHandle {
    var db: OpaquePointer?

    deinit {
        if let db { sqlite3_close_v2(db) }
    }
}
