import Foundation
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)

actor DatabaseService {
    static let shared = DatabaseService()

    private var db: OpaquePointer?
    private let dbPath: String
    private let fileManager = FileManager.default

    /// Private on purpose: `shared` must be the only instance. A second one
    /// would open its own sqlite handle that nothing ever closes (see the note
    /// where `deinit` used to be).
    private init() {
        let fm = fileManager
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let appDir = appSupport.appendingPathComponent("XFinder", isDirectory: true)

        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.dbPath = appDir.appendingPathComponent("xfinder.db").path
    }

    func initialize() {
        guard db == nil else { return }                     // idempotent: `openIfNeeded` may have run first
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("❌ Failed to open database")
            return
        }

        createTables()
        print("✅ Database initialized at \(dbPath)")
    }

    /// Every query goes through this, not through `db` directly. Measured 2026-10-11: `ClipboardManager`
    /// is created in `applicationDidFinishLaunching` and schedules its history fetch at once, while
    /// `initialize()` runs in a separate Task — whichever reached this actor first won. When the fetch
    /// won, `db` was nil, it returned `[]`, nothing retried, and the app ran all day with an EMPTY
    /// history while every later copy was written fine (the DB had opened by then): 1 826 rows on
    /// disk, 1 on screen. Opening on first use makes the order irrelevant.
    private func openIfNeeded() -> OpaquePointer? {
        if db == nil { initialize() }
        return db
    }

    private func createTables() {
        let queries = [
            // Clipboard records
            """
            CREATE TABLE IF NOT EXISTS clipboard_records (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                sourceBundleID TEXT,
                sourceAppName TEXT,
                textSnippet TEXT,
                thumbnailPath TEXT,
                payloadPath TEXT,
                ocrText TEXT,
                pinboardID TEXT,
                metadata TEXT
            );
            """,

            // Pinboards
            """
            CREATE TABLE IF NOT EXISTS pinboards (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color TEXT NOT NULL,
                icon TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
                isBuiltIn INTEGER DEFAULT 0
            );
            """,

            // Pinboard items junction
            """
            CREATE TABLE IF NOT EXISTS pinboard_items (
                pinboardID TEXT NOT NULL,
                recordID TEXT NOT NULL,
                PRIMARY KEY (pinboardID, recordID),
                FOREIGN KEY (pinboardID) REFERENCES pinboards(id),
                FOREIGN KEY (recordID) REFERENCES clipboard_records(id)
            );
            """,

            // Quick notes
            """
            CREATE TABLE IF NOT EXISTS quick_notes (
                id TEXT PRIMARY KEY,
                title TEXT,
                content TEXT NOT NULL,
                color TEXT NOT NULL,
                createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
                updatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
                isPinned INTEGER DEFAULT 0,
                isArchived INTEGER DEFAULT 0
            );
            """,

            // System metrics history
            """
            CREATE TABLE IF NOT EXISTS system_metrics (
                id TEXT PRIMARY KEY,
                cpuTemperature REAL,
                gpuTemperature REAL,
                cpuUsage REAL,
                gpuUsage REAL,
                memoryUsed INTEGER,
                memoryTotal INTEGER,
                diskUsed INTEGER,
                diskTotal INTEGER,
                networkDownload REAL,
                networkUpload REAL,
                batteryLevel REAL,
                batteryTimeRemaining INTEGER,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                isCharging INTEGER
            );
            """,

            // Create indexes for performance
            "CREATE INDEX IF NOT EXISTS idx_clipboard_timestamp ON clipboard_records(timestamp DESC);",
            "CREATE INDEX IF NOT EXISTS idx_clipboard_type ON clipboard_records(type);",
            "CREATE INDEX IF NOT EXISTS idx_notes_archived ON quick_notes(isArchived);",
            "CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON system_metrics(timestamp DESC);"
        ]

        for query in queries {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ Table/Index created: \(query.prefix(50))")
                }
                sqlite3_finalize(statement)
            } else {
                print("❌ Error creating table: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    func insertClipboardRecord(_ record: ClipboardRecord) async -> Bool {
        guard let db = openIfNeeded() else { return false }

        let query = """
        INSERT OR REPLACE INTO clipboard_records
        (id, type, timestamp, sourceBundleID, sourceAppName, textSnippet, thumbnailPath, payloadPath, ocrText, pinboardID, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return false }

        defer { sqlite3_finalize(statement) }

        let metadataJSON = try? JSONSerialization.data(withJSONObject: record.metadata)
        let metadataString = metadataJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        sqlite3_bind_text(statement, 1, record.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, record.type.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, record.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(statement, 4, record.sourceBundleID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, record.sourceAppName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, record.textSnippet, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 7, record.thumbnailPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 8, record.payloadPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 9, record.ocrText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 10, record.pinboardID?.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 11, metadataString, -1, SQLITE_TRANSIENT)

        return sqlite3_step(statement) == SQLITE_DONE
    }

    func insertQuickNote(_ note: QuickNote) async -> Bool {
        guard let db = openIfNeeded() else { return false }

        let query = """
        INSERT OR REPLACE INTO quick_notes
        (id, title, content, color, createdAt, updatedAt, isPinned, isArchived)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return false }

        defer { sqlite3_finalize(statement) }

        let colorJSON = try? JSONSerialization.data(withJSONObject: [
            "red": note.color.red,
            "green": note.color.green,
            "blue": note.color.blue,
            "alpha": note.color.alpha
        ])
        let colorString = colorJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        sqlite3_bind_text(statement, 1, note.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, note.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, note.content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, colorString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 5, note.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, note.updatedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 7, note.isPinned ? 1 : 0)
        sqlite3_bind_int(statement, 8, note.isArchived ? 1 : 0)

        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// Shared row mapper for every clipboard SELECT below, so the capped fetch and the
    /// library's uncapped fetch cannot drift apart on column order or JSON decoding.
    /// `statement` must have been stepped to a row (`sqlite3_step == SQLITE_ROW`) and must
    /// select exactly: id, type, timestamp, sourceBundleID, sourceAppName, textSnippet,
    /// thumbnailPath, payloadPath, ocrText, pinboardID, metadata (in that column order).
    private nonisolated static func mapClipboardRow(_ statement: OpaquePointer?) -> ClipboardRecord {
        func col(_ i: Int32) -> String? {
            guard let p = sqlite3_column_text(statement, i) else { return nil }
            return String(cString: p)
        }
        let type = ContentType(rawValue: col(1) ?? "") ?? .text
        var meta: [String: String] = [:]
        if let m = col(10),
           let d = m.data(using: .utf8),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
            meta = j
        }
        return ClipboardRecord(
            id: UUID(uuidString: col(0) ?? "") ?? UUID(),
            type: type,
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            sourceBundleID: col(3), sourceAppName: col(4),
            textSnippet: col(5), thumbnailPath: col(6),
            payloadPath: col(7), ocrText: col(8),
            pinboardID: col(9).flatMap(UUID.init(uuidString:)),
            metadata: meta
        )
    }

    private static let clipboardSelectColumns = """
    id, type, timestamp, sourceBundleID, sourceAppName, textSnippet,
           thumbnailPath, payloadPath, ocrText, pinboardID, metadata
    """

    func fetchClipboardRecords(limit: Int = 1000) -> [ClipboardRecord] {
        guard let db = openIfNeeded() else { return [] }
        let query = "SELECT \(Self.clipboardSelectColumns) FROM clipboard_records ORDER BY timestamp DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var out: [ClipboardRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out.append(Self.mapClipboardRow(statement))
        }
        return out
    }

    /// One row by id, for callers (D4 board-lock sealing) that need a record `ClipboardManager`'s
    /// capped in-memory `history` may have already trimmed away. Same row mapper as every other
    /// clipboard SELECT, so it cannot drift on column order or JSON decoding.
    func fetchClipboardRecord(id: UUID) -> ClipboardRecord? {
        guard let db = openIfNeeded() else { return nil }
        let query = "SELECT \(Self.clipboardSelectColumns) FROM clipboard_records WHERE id = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Self.mapClipboardRow(statement)
    }

    /// Every row, newest first, no cap — backs the Clipboard Library page (D3), which must see
    /// everything in SQLite, not just `ClipboardManager`'s capped in-memory history.
    func fetchAllClipboardRecords() -> [ClipboardRecord] {
        guard let db = openIfNeeded() else { return [] }
        let query = "SELECT \(Self.clipboardSelectColumns) FROM clipboard_records ORDER BY timestamp DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var out: [ClipboardRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out.append(Self.mapClipboardRow(statement))
        }
        return out
    }


    /// Persist a row the library edited in place (pin toggle on a record outside `ClipboardManager`'s
    /// capped history). Same column list and `INSERT OR REPLACE` shape as `insertClipboardRecord` —
    /// this is that function under another name, kept separate because the Library contract calls
    /// for one, but it must never drift from it, so it forwards there.
    @discardableResult
    func updateClipboardRecord(_ record: ClipboardRecord) async -> Bool {
        await insertClipboardRecord(record)
    }

    func deleteClipboardRecord(_ id: UUID) {
        guard let db = openIfNeeded() else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_records WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    func deleteClipboardRecords(olderThan cutoff: Date) {
        guard let db = openIfNeeded() else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_records WHERE timestamp < ?", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    // No `deinit`. This is a singleton (`shared`) that lives for the whole
    // process, so its deinit never ran — the `sqlite3_close` here was dead
    // code, and Swift 6 rejects touching the non-Sendable handle from a
    // nonisolated deinit anyway. The OS closes the file descriptor at exit,
    // and every write is committed by its own statement, so nothing is lost.
}
