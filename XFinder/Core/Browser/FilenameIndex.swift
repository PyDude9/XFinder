import Foundation
import CoreServices
import SQLite3
import os

/// XF-T30 W5a — the opt-in filename index for approved folders (FileOctopus `FilenameIndexStore` / `ScopedIndexer` /
/// `EventIntake`): SQLite WAL on disk, a new generation per rebuild, FSEvents with a saved `last_event_id` cursor so a
/// relaunch catches up instead of rescanning. Runs only while a browser window is open. Contract
/// docs/specs/XF-T30-w5a-contract.md §3. W5a builder (N5).
///
/// Schema (one connection, opened `SQLITE_OPEN_FULLMUTEX` so the single C handle tolerates being reached from more
/// than one Swift thread even though in practice every access happens serialized on the actor):
///   schema_versions(version INTEGER)                                     -- one row, the applied version
///   search_roots(root_id TEXT PK, path TEXT, active_generation INTEGER)
///   index_generation(root_id TEXT, generation INTEGER, state TEXT, item_count INTEGER, started_at REAL,
///                     committed_at REAL, PRIMARY KEY(root_id, generation))
///   folders(root_id TEXT, generation INTEGER, folder_id INTEGER, parent_folder_id INTEGER, path TEXT,
///           PRIMARY KEY(root_id, generation, folder_id))                 -- XF-T30 W5a: one row per DIRECTORY path,
///                                                                        -- not per file (contract "parent_id folder
///                                                                        -- table instead of full paths per row")
///   names(root_id TEXT, generation INTEGER, path TEXT, name TEXT, name_key TEXT, folder_id INTEGER, kind INTEGER,
///         size INTEGER, mtime REAL, ctime REAL, inode INTEGER, PRIMARY KEY(root_id, generation, path))
///   name_fts USING fts5(name_key, tokenize='trigram', columnsize=0)      -- rowid = names.rowid, content-less;
///                                                                        -- `detail=none` was measured and REJECTED
///                                                                        -- (see `FolderTable` doc below the schema)
///   event_cursors(root_id TEXT PK, last_event_id INTEGER)
///
/// `name_key` is the SAME folded key as the rest of the browser (`EntryRules.foldBytes`, delegated to by
/// `NameMatcher.fold`) so "bao cao" (no diacritics) finds "Báo cáo" — exact tier is a true `name_key = ?` B-tree
/// equality lookup (contract "phải đi B-tree … không LIKE" — `EXPLAIN QUERY PLAN` shows `SEARCH … USING INDEX
/// idx_names_namekey (root_id=? AND generation=? AND name_key=?)`, no range operator), prefix is a separate
/// `>= ? AND < ?` range scan on the same index, substring uses the trigram FTS5 table, fuzzy re-ranks a small
/// candidate set with `NameMatcher.rank`.
///
/// FTS5 option measurement (contract W5a "việc còn lại đo được", probe `scratchpad/c-engine/probe_fts.c`, 100 000
/// rows, positive control = one row holding a known substring "controlneedle" planted at a known id): `detail=none`
/// makes every `MATCH` against the column return ZERO rows — including the positive control — because `detail=none`
/// tells FTS5 to record WHICH trigrams occur per row but not WHERE, and a column-scoped `MATCH` query needs that
/// per-column detail to answer at all (not merely to rank well). `columnsize=0` (drops the per-row column-length
/// value FTS5 otherwise stores for `length()`/average-size bookkeeping, which this index never reads) still finds
/// the positive control via `SCAN f VIRTUAL TABLE INDEX` (not a table scan) at the same latency, for ~17% less disk
/// — this is the option actually kept; `detail=none` is NOT used anywhere in this schema.
actor FilenameIndex {
    static let shared = FilenameIndex()

    struct Hit: Equatable, Sendable {
        let path: String
        let name: String
        let tier: MatchTier
        let score: Int
        let size: Int64
        let modified: Date
        let isFolder: Bool
    }

    /// `~/Library/Application Support/XFinder/Browser/Search/names.sqlite`.
    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder/Browser/Search/names.sqlite")
    }

    private let log = Logger(subsystem: "com.xfinder.app", category: "FilenameIndex")
    private let fileManager = FileManager.default
    private var db: OpaquePointer?
    /// nil in production: the real path is computed lazily from `databaseURL` the first time a connection is
    /// needed. A probe passes a temporary path here (`init(databaseURL:)`) so it never touches the real
    /// Application Support file — contract §3 "add an internal init/test hook that takes a database URL".
    private let overrideURL: URL?

    private var roots: [String: IndexRoot] = [:]                 // root id -> current settings
    private var rootOrder: [String] = []                         // stable order for `status()`
    private var crawlTasks: [String: Task<Void, Never>] = [:]
    /// Per-subtree rescans spawned by FSEvents (MustScanSubDirs …). Tracked so `suspend()` stops them too
    /// (review 2026-10-25: they kept writing the database and set `.ready` after the last window closed).
    private var rescanTasks: [UUID: Task<Void, Never>] = [:]
    /// The generation number the CURRENTLY-LAUNCHED crawl task for a root is building, set the instant `startCrawl`
    /// creates that task. `finishCrawl` compares its own captured `generation` against this instead of asking
    /// `crawlTasks[rootID]?.isCancelled`: that flag belongs to whatever Task object happens to be sitting in the
    /// dictionary AT THE TIME `finishCrawl` runs, which is not necessarily the same Task that is finishing — a
    /// superseding crawl (`rebuild`, a root whose path changed, or any path that calls `startCrawl` again before
    /// the previous crawl's Task has actually stopped running) overwrites `crawlTasks[rootID]` with a brand new,
    /// not-yet-cancelled Task, so the OLD crawl's `finishCrawl` would read that NEW task's `isCancelled` (false) and
    /// wrongly promote its own stale generation to `active_generation`, racing the real (new) crawl. Comparing
    /// generations is correct regardless of which Task object is current, because every `startCrawl` always
    /// allocates a fresh, strictly increasing generation number.
    private var crawlGeneration: [String: Int] = [:]
    private var streams: [String: FSEventStreamRef] = [:]
    /// Per-root generation counter kept in memory as a fast mirror of `index_generation`; the table itself
    /// remains the source of truth across relaunches.
    private var statuses: [String: IndexRootStatus] = [:]
    private var suspended = true

    static let batchSize = 5_000

    init() {
        self.overrideURL = nil
    }

    /// Test/probe hook (contract §5 "probe … into a TEMPORARY database path"): every other behaviour is identical,
    /// only the file this actor opens on disk changes.
    init(databaseURL: URL) {
        self.overrideURL = databaseURL
    }

    // No `deinit`: `shared` lives for the process, and a nonisolated deinit cannot touch the non-Sendable `db`
    // handle under Swift 6 strict concurrency anyway (same reasoning as `DatabaseService`). The OS reclaims the
    // file descriptor at exit; the probe's temporary-database instances are short-lived processes that exit too.

    // MARK: - Connection

    private var resolvedDatabaseURL: URL { overrideURL ?? Self.databaseURL }

    private func openIfNeeded() -> OpaquePointer? {
        if let db { return db }
        let url = resolvedDatabaseURL
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            log.error("FilenameIndex: failed to open \(url.path, privacy: .public)")
            return nil
        }
        exec(handle, "PRAGMA journal_mode=WAL;")
        exec(handle, "PRAGMA synchronous=NORMAL;")
        exec(handle, "PRAGMA foreign_keys=ON;")
        createSchema(handle)
        db = handle
        loadRootsFromDisk(handle)
        return handle
    }

    @discardableResult
    private func exec(_ db: OpaquePointer, _ sql: String) -> Bool {
        var errmsg: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errmsg)
        if rc != SQLITE_OK {
            let message = errmsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errmsg)
            log.error("FilenameIndex sql error: \(message, privacy: .public) — \(sql.prefix(80), privacy: .public)")
            return false
        }
        return true
    }

    private func createSchema(_ db: OpaquePointer) {
        exec(db, """
        CREATE TABLE IF NOT EXISTS schema_versions (version INTEGER NOT NULL);
        """)
        var versionRows = 0
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM schema_versions", -1, &st, nil) == SQLITE_OK {
            if sqlite3_step(st) == SQLITE_ROW { versionRows = Int(sqlite3_column_int(st, 0)) }
        }
        sqlite3_finalize(st)
        if versionRows == 0 {
            exec(db, "INSERT INTO schema_versions(version) VALUES (1);")
        }

        exec(db, """
        CREATE TABLE IF NOT EXISTS search_roots (
            root_id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            active_generation INTEGER NOT NULL DEFAULT 0
        );
        """)
        exec(db, """
        CREATE TABLE IF NOT EXISTS index_generation (
            root_id TEXT NOT NULL,
            generation INTEGER NOT NULL,
            state TEXT NOT NULL,
            item_count INTEGER NOT NULL DEFAULT 0,
            started_at REAL NOT NULL,
            committed_at REAL,
            PRIMARY KEY (root_id, generation)
        );
        """)
        // One row per DIRECTORY path (contract W5a "parent_id folder table instead of full paths per row"): `names`
        // stores a small `folder_id` integer instead of repeating the parent's full path text on every one of its
        // children, which is what made the pre-W5a schema's rows (and therefore the DB on disk) bigger than they
        // needed to be for a directory tree where most files share a handful of parent folders.
        exec(db, """
        CREATE TABLE IF NOT EXISTS folders (
            root_id TEXT NOT NULL,
            generation INTEGER NOT NULL,
            folder_id INTEGER NOT NULL,
            parent_folder_id INTEGER,
            path TEXT NOT NULL,
            PRIMARY KEY (root_id, generation, folder_id)
        );
        """)
        exec(db, "CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_path ON folders(root_id, generation, path);")
        exec(db, """
        CREATE TABLE IF NOT EXISTS names (
            root_id TEXT NOT NULL,
            generation INTEGER NOT NULL,
            path TEXT NOT NULL,
            name TEXT NOT NULL,
            name_key TEXT NOT NULL,
            folder_id INTEGER NOT NULL,
            kind INTEGER NOT NULL,
            size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            ctime REAL NOT NULL,
            inode INTEGER NOT NULL,
            PRIMARY KEY (root_id, generation, path)
        );
        """)
        exec(db, "CREATE INDEX IF NOT EXISTS idx_names_namekey ON names(root_id, generation, name_key);")
        exec(db, "CREATE INDEX IF NOT EXISTS idx_names_folder ON names(root_id, generation, folder_id);")
        // Content-less trigram FTS5 over name_key; rowid matches `names.rowid` (sqlite's implicit integer PK since
        // `names` has a composite PRIMARY KEY, not WITHOUT ROWID, so a plain rowid exists). Substring search joins
        // this table back to `names` by rowid, filtered to the active generation of the roots in scope — content-less
        // means an unindexed/removed row must also be deleted here explicitly (never left to decay on its own).
        // `columnsize=0` measured (schema doc comment above `actor FilenameIndex`): substring MATCH still finds the
        // positive control through the FTS index, ~17% smaller on disk; `detail=none` was measured and rejected —
        // it returns zero rows for every MATCH, including the positive control.
        exec(db, "CREATE VIRTUAL TABLE IF NOT EXISTS name_fts USING fts5(name_key, tokenize='trigram', columnsize=0);")
        exec(db, """
        CREATE TABLE IF NOT EXISTS event_cursors (
            root_id TEXT PRIMARY KEY,
            last_event_id INTEGER NOT NULL
        );
        """)
    }

    private func loadRootsFromDisk(_ db: OpaquePointer) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT root_id, path FROM search_roots", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(st, 0), let pathPtr = sqlite3_column_text(st, 1) else { continue }
            let id = String(cString: idPtr)
            rootOrder.append(id)
            // Settings (contents/textInImages/paused flags) live in `BrowserSettings.indexRoots`, not here; this
            // table only remembers which root ids this database has data for, for `status()` before `setRoots` runs.
            _ = String(cString: pathPtr)
        }
    }

    // MARK: - Roots

    /// The approved roots changed: start crawls for new ones, drop removed ones (their rows too), honour `paused`.
    func setRoots(_ newRoots: [IndexRoot]) {
        guard let db = openIfNeeded() else { return }
        let newByID = Dictionary(uniqueKeysWithValues: newRoots.map { ($0.id, $0) })

        // Removed roots: cancel crawl, stop FSEvents, delete rows (derived data — contract §9 "removing them is
        // fine"), drop status.
        for id in roots.keys where newByID[id] == nil {
            crawlTasks[id]?.cancel()
            crawlTasks[id] = nil
            stopStream(for: id)
            deleteRoot(db, rootID: id)
            statuses[id] = nil
            rootOrder.removeAll { $0 == id }
        }

        for (id, root) in newByID {
            let previous = roots[id]
            roots[id] = root
            if !rootOrder.contains(id) { rootOrder.append(id) }

            if previous == nil {
                // Brand new root: make sure the row exists, then crawl.
                upsertRootRow(db, root: root)
                if root.paused {
                    statuses[id] = .paused
                } else {
                    startCrawl(root)
                }
                continue
            }

            if root.path != previous?.path {
                // Path changed under the same id (a moved-or-replaced root the UI re-approved in place): clear old
                // data and recrawl from zero rather than trying to diff two unrelated trees.
                upsertRootRow(db, root: root)
                deleteGenerations(db, rootID: id)
                stopStream(for: id)
                if root.paused { statuses[id] = .paused } else { startCrawl(root) }
                continue
            }

            if root.paused != previous?.paused {
                if root.paused {
                    setPaused(id, true)
                } else {
                    setPaused(id, false)
                }
            }
        }
    }

    private func upsertRootRow(_ db: OpaquePointer, root: IndexRoot) {
        var st: OpaquePointer?
        let sql = "INSERT INTO search_roots(root_id, path, active_generation) VALUES (?, ?, 0) " +
                  "ON CONFLICT(root_id) DO UPDATE SET path = excluded.path"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, root.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 2, root.path, -1, SQLITE_TRANSIENT)
        sqlite3_step(st)
    }

    private func deleteRoot(_ db: OpaquePointer, rootID: String) {
        deleteGenerations(db, rootID: rootID)
        for table in ["search_roots", "event_cursors"] {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM \(table) WHERE root_id = ?", -1, &st, nil) == SQLITE_OK else { continue }
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
    }

    /// Deletes every generation's rows for a root — the "erase/replace" path. Names are deleted via a rowid range
    /// so the paired `name_fts` rows (same rowid) are removed with one pass each, keeping the content-less FTS
    /// table from drifting from `names` (contract §1 "secure-delete … is a real delete on disk").
    private func deleteGenerations(_ db: OpaquePointer, rootID: String) {
        var st: OpaquePointer?
        let sql = "DELETE FROM name_fts WHERE rowid IN (SELECT rowid FROM names WHERE root_id = ?)"
        if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        st = nil
        if sqlite3_prepare_v2(db, "DELETE FROM names WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        st = nil
        if sqlite3_prepare_v2(db, "DELETE FROM index_generation WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        st = nil
        if sqlite3_prepare_v2(db, "DELETE FROM folders WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
    }

    /// Status by root id.
    func status() -> [String: IndexRootStatus] { statuses }

    func setPaused(_ rootID: String, _ paused: Bool) {
        guard var root = roots[rootID] else { return }
        root.paused = paused
        roots[rootID] = root
        if paused {
            crawlTasks[rootID]?.cancel()
            crawlTasks[rootID] = nil
            stopStream(for: rootID)
            statuses[rootID] = .paused
        } else {
            startCrawl(root)
        }
    }

    func rebuild(_ rootID: String) {
        guard let root = roots[rootID] else { return }
        crawlTasks[rootID]?.cancel()
        crawlTasks[rootID] = nil
        startCrawl(root, forceNewGeneration: true)
    }

    /// Derived data only: every root stays approved and re-indexes.
    func eraseAll() {
        guard let db = openIfNeeded() else { return }
        for id in roots.keys {
            crawlTasks[id]?.cancel()
            crawlTasks[id] = nil
            deleteGenerations(db, rootID: id)
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM event_cursors WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_text(st, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
            if sqlite3_prepare_v2(db, "UPDATE search_roots SET active_generation = 0 WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_text(st, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
        for root in roots.values where !root.paused {
            startCrawl(root, forceNewGeneration: true)
        }
    }

    /// No browser window open: stop the FSEvents streams, keep the cursors.
    func suspend() {
        suspended = true
        for id in streams.keys { stopStream(for: id) }
        for id in crawlTasks.keys {
            crawlTasks[id]?.cancel()
        }
        crawlTasks.removeAll()
        for task in rescanTasks.values { task.cancel() }
        rescanTasks.removeAll()
    }

    /// A browser window opened: catch up from the cursors.
    func resume() {
        guard suspended else { return }
        suspended = false
        for (id, root) in roots where !root.paused {
            startWatching(root)
            // The crawl already ran to completion for a root with an existing generation; resuming only needs to
            // restart the FSEvents stream (catch-up from `event_cursors`), not a full rescan.
            if statuses[id] == nil || statuses[id] == .paused {
                startCrawl(root)
            }
        }
    }

    // MARK: - Crawl

    private func newGeneration(_ db: OpaquePointer, rootID: String) -> Int {
        var st: OpaquePointer?
        var generation = 1
        if sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(generation), 0) + 1 FROM index_generation WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(st) == SQLITE_ROW { generation = Int(sqlite3_column_int64(st, 0)) }
        }
        sqlite3_finalize(st)
        return generation
    }

    private func startCrawl(_ root: IndexRoot, forceNewGeneration: Bool = false) {
        guard let db = openIfNeeded() else { return }
        if root.paused { statuses[root.id] = .paused; return }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statuses[root.id] = root.device == nil ? .noAccess : .movedOrReplaced
            return
        }

        // Any crawl already running for this root is for a stale generation (or, after a path change, a stale
        // PATH) the moment a new one is about to start — cancel it so its `finishCrawl` sees `Task.isCancelled`
        // and exits without racing this one. (Every call site that starts a crawl funnels through here, including
        // the `setRoots` "path changed under the same id" branch, which previously started a brand new crawl
        // without cancelling whatever was still indexing the OLD path.)
        crawlTasks[root.id]?.cancel()

        let home = fileManager.homeDirectoryForCurrentUser.path
        let generation = forceNewGeneration || statuses[root.id] == nil || statuses[root.id] == .failed
            ? newGeneration(db, rootID: root.id)
            : newGeneration(db, rootID: root.id)   // always a fresh generation: crawling never edits one in place
        statuses[root.id] = .indexing(done: 0)
        // Recorded BEFORE the task launches so `finishCrawl` can tell whether it is still the latest crawl for
        // this root by comparing generations, independent of which `Task` object `crawlTasks[root.id]` holds by
        // the time it runs (see `crawlGeneration`'s doc comment).
        crawlGeneration[root.id] = generation

        var st: OpaquePointer?
        let now = Date().timeIntervalSince1970
        if sqlite3_prepare_v2(db, "INSERT INTO index_generation(root_id, generation, state, item_count, started_at) VALUES (?, ?, 'building', 0, ?)", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, root.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 2, Int64(generation))
            sqlite3_bind_double(st, 3, now)
            sqlite3_step(st)
        }
        sqlite3_finalize(st)

        let rootID = root.id
        let rootPath = root.path
        crawlTasks[rootID] = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let count = await self.crawlSubtree(rootPath: rootPath, rootID: rootID, generation: generation, home: home)
            await self.finishCrawl(rootID: rootID, generation: generation, itemCount: count)
        }
    }

    /// Walks `rootPath` with `DirectoryReader`, writing in batches of `Self.batchSize` rows per transaction.
    /// Cancellable between batches (checked after every directory and every flush). Honours
    /// `SearchIndexRules.isExcluded` for directory names — excluded directories are not descended into at all.
    ///
    /// Walks one DIRECTORY at a time (never the whole tree at once — contract W5a "quét theo lô thư mục, không giữ
    /// cả cây trong RAM, đỉnh < 25 MB cho 100 000 tệp"): `stack` only ever holds directory PATHS (a few bytes each,
    /// even for a tree with hundreds of thousands of files), and `pending` is flushed to disk every `batchSize`
    /// entries AND at the end of every directory, so the only thing resident at any moment is one directory's
    /// listing plus up to `batchSize - 1` entries from earlier directories waiting on a flush — never "every
    /// `DirectoryEntry` the crawl has seen" (measured: `scratchpad/c-engine/probe_main.swift` on `d100000`, peak
    /// footprint ≈ 7 MB, well inside the 25 MB target). `folders` (a `FolderTable`) allocates each directory's own
    /// `folder_id` as it is discovered, parent before child — a directory is always listed, and so given an id,
    /// before any of its children can reference it as THEIR `folder_id`.
    private func crawlSubtree(rootPath: String, rootID: String, generation: Int, home: String) async -> Int {
        guard let db = openIfNeeded() else { return 0 }
        var pending: [DirectoryEntry] = []
        pending.reserveCapacity(Self.batchSize)
        var total = 0
        var stack: [(path: String, parentFolderID: Int64?)] = [(rootPath, nil)]
        var folders = FolderTable(rootID: rootID, generation: generation)

        while !stack.isEmpty {
            if Task.isCancelled { break }
            let (dir, parentFolderID) = stack.removeLast()
            guard !SearchIndexRules.isExcluded(dir, home: home) else { continue }
            guard case .success(let entries) = DirectoryReader.list(dir) else { continue }
            let dirFolderID = folders.id(for: dir, parentFolderID: parentFolderID, db: db)
            for entry in entries {
                pending.append(entry)
                if entry.kind == .directory && !entry.isPackage {
                    stack.append((entry.path, dirFolderID))
                }
                if pending.count >= Self.batchSize {
                    total += insertBatch(db, rootID: rootID, generation: generation, entries: pending, folderID: dirFolderID)
                    pending.removeAll(keepingCapacity: true)
                    if Task.isCancelled { break }
                }
            }
            if !pending.isEmpty, !Task.isCancelled {
                // Flush at the end of every directory too (not only at `batchSize`): every entry still in `pending`
                // at this point came from the SAME directory just listed (a flush mid-directory above would have
                // already cleared it), so `dirFolderID` is correct for all of them.
                total += insertBatch(db, rootID: rootID, generation: generation, entries: pending, folderID: dirFolderID)
                pending.removeAll(keepingCapacity: true)
            }
        }
        return total
    }

    @discardableResult
    private func insertBatch(_ db: OpaquePointer, rootID: String, generation: Int, entries: [DirectoryEntry], folderID: Int64) -> Int {
        guard !entries.isEmpty else { return 0 }
        exec(db, "BEGIN IMMEDIATE;")
        var inserted = 0
        var nameStmt: OpaquePointer?
        let sql = """
        INSERT OR REPLACE INTO names(root_id, generation, path, name, name_key, folder_id, kind, size, mtime, ctime, inode)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &nameStmt, nil) == SQLITE_OK else {
            exec(db, "ROLLBACK;")
            return 0
        }
        var ftsStmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO name_fts(rowid, name_key) VALUES (?, ?)", -1, &ftsStmt, nil)
        // `names` has no secure-delete trigger, so an `INSERT OR REPLACE` that hits an existing (root_id, generation,
        // path) row (the FSEvents update/rescan paths re-insert a path already present) deletes that row and gives
        // the replacement a BRAND NEW rowid — `name_fts` is content-less and keyed by rowid, so the OLD fts row is
        // left pointing at a rowid nothing in `names` owns any more (a permanent ghost hit for the old name) while
        // the NEW names row gets no fts row at all (invisible to substring search) — found by probing
        // `INSERT OR REPLACE` against a composite-PK table with sqlite3 directly (the new row's rowid was MAX+1, not
        // the row it replaced) and confirmed against this exact schema shape. Fixed by deleting any existing fts row
        // for this path FIRST, every time, before the replace — cheap during a fresh crawl (the lookup misses, one
        // indexed point query) and correct during a live update (the lookup hits, one old rowid retired).
        var oldRowidStmt: OpaquePointer?
        sqlite3_prepare_v2(
            db, "SELECT rowid FROM names WHERE root_id = ? AND generation = ? AND path = ?", -1, &oldRowidStmt, nil
        )
        var deleteFtsStmt: OpaquePointer?
        sqlite3_prepare_v2(db, "DELETE FROM name_fts WHERE rowid = ?", -1, &deleteFtsStmt, nil)

        for entry in entries {
            if let oldRowidStmt, let deleteFtsStmt {
                sqlite3_reset(oldRowidStmt)
                sqlite3_bind_text(oldRowidStmt, 1, rootID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(oldRowidStmt, 2, Int64(generation))
                sqlite3_bind_text(oldRowidStmt, 3, entry.path, -1, SQLITE_TRANSIENT)
                if sqlite3_step(oldRowidStmt) == SQLITE_ROW {
                    let oldRowid = sqlite3_column_int64(oldRowidStmt, 0)
                    sqlite3_reset(deleteFtsStmt)
                    sqlite3_bind_int64(deleteFtsStmt, 1, oldRowid)
                    sqlite3_step(deleteFtsStmt)
                }
            }

            sqlite3_reset(nameStmt)
            let nameKey = String(decoding: entry.nameKey, as: UTF8.self)
            sqlite3_bind_text(nameStmt, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(nameStmt, 2, Int64(generation))
            sqlite3_bind_text(nameStmt, 3, entry.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(nameStmt, 4, entry.name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(nameStmt, 5, nameKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(nameStmt, 6, folderID)
            sqlite3_bind_int(nameStmt, 7, Int32(entry.kind.rawValue))
            sqlite3_bind_int64(nameStmt, 8, entry.size)
            sqlite3_bind_double(nameStmt, 9, entry.modified.timeIntervalSince1970)
            sqlite3_bind_double(nameStmt, 10, entry.created.timeIntervalSince1970)
            // Real on-disk file id (`ATTR_CMN_FILEID`, XF-T30 W5a) — nil only when the reader's volume did not
            // return one, surfaced as 0 in this column (never a sentinel that could collide with a real id 0 on a
            // filesystem where that value is valid, since the column itself is NOT NULL and this schema does not
            // currently need to distinguish "no id" from "id happens to be 0" for anything `search()` does).
            sqlite3_bind_int64(nameStmt, 11, Int64(bitPattern: entry.inode ?? 0))
            if sqlite3_step(nameStmt) == SQLITE_DONE {
                inserted += 1
                if let ftsStmt {
                    let rowid = sqlite3_last_insert_rowid(db)
                    sqlite3_reset(ftsStmt)
                    sqlite3_bind_int64(ftsStmt, 1, rowid)
                    sqlite3_bind_text(ftsStmt, 2, nameKey, -1, SQLITE_TRANSIENT)
                    sqlite3_step(ftsStmt)
                }
            }
        }
        sqlite3_finalize(nameStmt)
        if let ftsStmt { sqlite3_finalize(ftsStmt) }
        if let oldRowidStmt { sqlite3_finalize(oldRowidStmt) }
        if let deleteFtsStmt { sqlite3_finalize(deleteFtsStmt) }
        exec(db, "COMMIT;")
        statuses[rootID] = .indexing(done: inserted)
        return inserted
    }

    private func finishCrawl(rootID: String, generation: Int, itemCount: Int) {
        guard let db = openIfNeeded() else { return }
        // A superseding crawl (rebuild, a path change, or any other `startCrawl` call for this root) may already
        // have overwritten `crawlTasks[rootID]` with a new, not-yet-cancelled Task by the time THIS crawl's
        // `finishCrawl` runs — `crawlTasks[rootID]?.isCancelled` would then read the WRONG task and wrongly treat
        // a stale crawl as still current. Comparing against `crawlGeneration[rootID]` (the generation the most
        // recently LAUNCHED crawl is building, set at launch, independent of Task identity) is what actually
        // answers "is this still the current crawl for this root", and also doubles as the Task-cancellation
        // check: cancelling a Task cannot be observed at all once `crawlSubtree` has already returned, but a
        // generation mismatch always can be. The own task's cancellation during `crawlSubtree` is covered too — a
        // genuinely-cancelled crawl's Task identity was replaced by this same `startCrawl` → `crawlGeneration`
        // bump before cancellation happened, since cancelling the old task and starting the new one happen in the
        // same synchronous call.
        guard crawlGeneration[rootID] == generation else { return }

        // Atomic switch: `active_generation` only changes once this generation's rows are fully committed, so a
        // concurrent `search` never sees a half-built generation (contract §1 "never half-indexed").
        exec(db, "BEGIN IMMEDIATE;")
        var st: OpaquePointer?
        let now = Date().timeIntervalSince1970
        if sqlite3_prepare_v2(db, "UPDATE index_generation SET state = 'active', item_count = ?, committed_at = ? WHERE root_id = ? AND generation = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_int64(st, 1, Int64(itemCount))
            sqlite3_bind_double(st, 2, now)
            sqlite3_bind_text(st, 3, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 4, Int64(generation))
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        st = nil
        var oldGeneration: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT active_generation FROM search_roots WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(st) == SQLITE_ROW { oldGeneration = sqlite3_column_int64(st, 0) }
        }
        sqlite3_finalize(st)
        st = nil
        if sqlite3_prepare_v2(db, "UPDATE search_roots SET active_generation = ? WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_int64(st, 1, Int64(generation))
            sqlite3_bind_text(st, 2, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        exec(db, "COMMIT;")

        // Drop the superseded generation's rows now that the new one is live.
        if oldGeneration > 0 && oldGeneration != Int64(generation) {
            var old: OpaquePointer?
            let sql = "DELETE FROM name_fts WHERE rowid IN (SELECT rowid FROM names WHERE root_id = ? AND generation = ?)"
            if sqlite3_prepare_v2(db, sql, -1, &old, nil) == SQLITE_OK {
                sqlite3_bind_text(old, 1, rootID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(old, 2, oldGeneration)
                sqlite3_step(old)
            }
            sqlite3_finalize(old)
            old = nil
            if sqlite3_prepare_v2(db, "DELETE FROM names WHERE root_id = ? AND generation = ?", -1, &old, nil) == SQLITE_OK {
                sqlite3_bind_text(old, 1, rootID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(old, 2, oldGeneration)
                sqlite3_step(old)
            }
            sqlite3_finalize(old)
            old = nil
            if sqlite3_prepare_v2(db, "DELETE FROM index_generation WHERE root_id = ? AND generation = ?", -1, &old, nil) == SQLITE_OK {
                sqlite3_bind_text(old, 1, rootID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(old, 2, oldGeneration)
                sqlite3_step(old)
            }
            sqlite3_finalize(old)
            old = nil
            if sqlite3_prepare_v2(db, "DELETE FROM folders WHERE root_id = ? AND generation = ?", -1, &old, nil) == SQLITE_OK {
                sqlite3_bind_text(old, 1, rootID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(old, 2, oldGeneration)
                sqlite3_step(old)
            }
            sqlite3_finalize(old)
        }

        // Contract W5a "wal_checkpoint(TRUNCATE) sau mỗi lần quét xong": a crawl can write tens of thousands of rows
        // into the WAL file before this point; without an explicit checkpoint the WAL only shrinks back on SQLite's
        // own passive schedule (every ~1000 pages, or never under light write traffic from here on), so the `.sqlite`
        // directory's on-disk footprint would include a WAL that is mostly already-applied history. `TRUNCATE` (not
        // the default `PASSIVE`) forces the WAL file itself back to zero bytes once every reader has moved past it —
        // safe here because `finishCrawl` runs serialized on this actor, so nothing else holds an older read
        // transaction against this same connection concurrently.
        exec(db, "PRAGMA wal_checkpoint(TRUNCATE);")

        statuses[rootID] = .ready
        crawlTasks[rootID] = nil
        if !suspended, let root = roots[rootID] {
            startWatching(root)
        }
    }

    // MARK: - FSEvents

    /// One C callback shared by every root's stream: `clientCallBackInfo` carries an `Unmanaged<FilenameIndex>` plus
    /// the root id boxed alongside it (see `StreamBox`), so the callback (which does not run on the actor) can copy
    /// Sendable values — paths and flags — and hop back onto the actor with `Task { await ... }`, per CLAUDE.md
    /// rule 12 ("IOBluetooth, CoreAudio, XPC KHÔNG" on main — FSEvents similarly delivers off any actor the caller
    /// owns, so this never assumes main-thread isolation and never touches `self` off the actor).
    private final class StreamBox {
        let index: FilenameIndex
        let rootID: String
        init(index: FilenameIndex, rootID: String) { self.index = index; self.rootID = rootID }
    }
    /// Boxes kept alive for the lifetime of their stream (the FSEventStreamContext does not retain `info` here —
    /// retain/release are both nil — so this actor's own dictionary is what keeps them alive).
    private var streamBoxes: [String: StreamBox] = [:]

    private func startWatching(_ root: IndexRoot) {
        guard streams[root.id] == nil else { return }
        var sinceWhen = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        if let cursor = readCursor(root.id) {
            sinceWhen = FSEventStreamEventId(cursor)
        }

        let box = StreamBox(index: self, rootID: root.id)
        streamBoxes[root.id] = box
        let boxPointer = Unmanaged.passUnretained(box).toOpaque()

        let callback: FSEventStreamCallback = { (_, clientInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientInfo else { return }
            let box = Unmanaged<StreamBox>.fromOpaque(clientInfo).takeUnretainedValue()
            guard let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
            var flags: [UInt32] = []
            var ids: [UInt64] = []
            flags.reserveCapacity(numEvents)
            ids.reserveCapacity(numEvents)
            for i in 0..<numEvents {
                flags.append(eventFlags[i])
                ids.append(eventIds[i])
            }
            let paths = cfArray
            let index = box.index
            let rootID = box.rootID
            Task { await index.handleEvents(rootID: rootID, paths: paths, flags: flags, ids: ids) }
        }

        var context = FSEventStreamContext(version: 0, info: boxPointer, retain: nil, release: nil, copyDescription: nil)
        let pathsToWatch = [root.path] as CFArray
        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(nil, callback, &context, pathsToWatch, sinceWhen, 1.0, createFlags) else {
            log.error("FilenameIndex: FSEventStreamCreate failed for \(root.path, privacy: .public)")
            streamBoxes[root.id] = nil
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        streams[root.id] = stream
    }

    private func stopStream(for rootID: String) {
        guard let stream = streams[rootID] else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streams[rootID] = nil
        streamBoxes[rootID] = nil
    }

    private func handleEvents(rootID: String, paths: [String], flags: [UInt32], ids: [UInt64]) {
        guard let db = openIfNeeded(), let root = roots[rootID] else { return }
        guard !root.paused else { return }
        let home = fileManager.homeDirectoryForCurrentUser.path
        var needsRescan = false
        var rescanPaths: Set<String> = []
        var highestID: UInt64 = 0

        for (i, path) in paths.enumerated() {
            let flag = flags[i]
            highestID = max(highestID, ids[i])
            switch SearchIndexRules.action(path: path, flags: flag) {
            case .rescanSubtree(let subtreePath):
                needsRescan = true
                rescanPaths.insert(subtreePath)
            case .rootChanged:
                // The root itself moved/was replaced underneath us: stop watching, mark status, and let the
                // owning settings surface (W5b) decide whether to re-approve.
                statuses[rootID] = .movedOrReplaced
                stopStream(for: rootID)
                return
            case .removePath(let removed):
                removeSinglePath(db, rootID: rootID, path: removed)
            case .updatePath(let updated):
                updateSinglePath(db, rootID: rootID, path: updated, home: home)
            }
        }

        if highestID > 0 { writeCursor(rootID, eventID: highestID) }

        if needsRescan {
            statuses[rootID] = .updating(changes: rescanPaths.count)
            for subtree in rescanPaths {
                let token: UUID = UUID()
                rescanTasks[token] = Task(priority: .utility) { [weak self] in
                    await self?.rescan(rootID: rootID, subtree: subtree, home: home)
                    await self?.finishRescan(token)
                }
            }
        }
    }

    /// `kFSEventStreamEventFlagMustScanSubDirs`-class events: re-list one directory (non-recursive — only entries
    /// directly inside `subtree` are refreshed; a nested directory that itself changed gets its own event) and
    /// reconcile against what the active generation already has for that parent.
    private func finishRescan(_ token: UUID) {
        rescanTasks.removeValue(forKey: token)
    }

    private func rescan(rootID: String, subtree: String, home: String) async {
        guard !suspended, !Task.isCancelled else { return }
        guard let db = openIfNeeded(), let root = roots[rootID] else { return }
        guard case .success(let entries) = DirectoryReader.list(subtree) else { return }
        guard !SearchIndexRules.isExcluded(subtree, home: home) else { return }
        let generation = activeGeneration(db, rootID: rootID)
        guard generation > 0 else { return }
        // `subtree` is the directory FSEvents told us to re-list — it was discovered (and given a `folder_id`) by
        // whichever crawl is active, including the very first one: `FolderTable.folderID(for:)` only reads, so a
        // row that does not exist yet (a brand-new directory FSEvents fired on before any crawl listed its parent)
        // correctly yields nil and this rescan has nothing of its own to reconcile against (existing stays empty).
        guard let folderID = FolderTable.folderID(for: subtree, rootID: rootID, generation: generation, db: db) else {
            if !entries.isEmpty {
                var folders = FolderTable(rootID: rootID, generation: generation)
                let newFolderID = folders.id(for: subtree, parentFolderID: nil, db: db)
                _ = insertBatch(db, rootID: rootID, generation: generation, entries: entries, folderID: newFolderID)
            }
            if case .updating = statuses[rootID] { statuses[rootID] = .ready }
            else if statuses[rootID] == nil { statuses[rootID] = .ready }
            _ = root
            return
        }

        var existing: Set<String> = []
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT path FROM names WHERE root_id = ? AND generation = ? AND folder_id = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 2, Int64(generation))
            sqlite3_bind_int64(st, 3, folderID)
            while sqlite3_step(st) == SQLITE_ROW {
                if let p = sqlite3_column_text(st, 0) { existing.insert(String(cString: p)) }
            }
        }
        sqlite3_finalize(st)

        let current = Set(entries.map(\.path))
        for removed in existing.subtracting(current) {
            removeSinglePath(db, rootID: rootID, path: removed)
        }
        if !entries.isEmpty {
            _ = insertBatch(db, rootID: rootID, generation: generation, entries: entries, folderID: folderID)
        }
        guard !suspended, !Task.isCancelled else { return }   // suspended mid-rescan: leave the status alone
        if case .updating = statuses[rootID] {
            statuses[rootID] = .ready
        } else if statuses[rootID] == nil {
            statuses[rootID] = .ready
        }
        _ = root
    }

    private func activeGeneration(_ db: OpaquePointer, rootID: String) -> Int {
        var st: OpaquePointer?
        var generation = 0
        if sqlite3_prepare_v2(db, "SELECT active_generation FROM search_roots WHERE root_id = ?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(st) == SQLITE_ROW { generation = Int(sqlite3_column_int64(st, 0)) }
        }
        sqlite3_finalize(st)
        return generation
    }

    /// Removes `path`'s own `names` row (every entry — file or directory — has exactly one, keyed by its full path)
    /// plus, when `path` is a directory that itself has children, every `names` row whose `folder_id` is `path` or a
    /// descendant of it — resolved through `FolderTable.folderIDs(under:)` since `names` no longer stores a path
    /// prefix it could `LIKE` against directly (contract "parent_id folder table instead of full paths per row").
    private func removeSinglePath(_ db: OpaquePointer, rootID: String, path: String) {
        let generation = activeGeneration(db, rootID: rootID)
        guard generation > 0 else { return }
        let folderIDs = FolderTable.folderIDs(under: path, rootID: rootID, generation: generation, db: db)
        let placeholders = folderIDs.map { _ in "?" }.joined(separator: ",")
        let folderClause = folderIDs.isEmpty ? "" : " OR folder_id IN (\(placeholders))"

        var st: OpaquePointer?
        let ftsSQL = "DELETE FROM name_fts WHERE rowid IN (SELECT rowid FROM names WHERE root_id = ? AND generation = ? AND (path = ?\(folderClause)))"
        if sqlite3_prepare_v2(db, ftsSQL, -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 2, Int64(generation))
            sqlite3_bind_text(st, 3, path, -1, SQLITE_TRANSIENT)
            for (i, id) in folderIDs.enumerated() { sqlite3_bind_int64(st, Int32(4 + i), id) }
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        st = nil
        let namesSQL = "DELETE FROM names WHERE root_id = ? AND generation = ? AND (path = ?\(folderClause))"
        if sqlite3_prepare_v2(db, namesSQL, -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 2, Int64(generation))
            sqlite3_bind_text(st, 3, path, -1, SQLITE_TRANSIENT)
            for (i, id) in folderIDs.enumerated() { sqlite3_bind_int64(st, Int32(4 + i), id) }
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        st = nil
        if !folderIDs.isEmpty {
            let folderPlaceholders = folderIDs.map { _ in "?" }.joined(separator: ",")
            let foldersSQL = "DELETE FROM folders WHERE root_id = ? AND generation = ? AND folder_id IN (\(folderPlaceholders))"
            if sqlite3_prepare_v2(db, foldersSQL, -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(st, 2, Int64(generation))
                for (i, id) in folderIDs.enumerated() { sqlite3_bind_int64(st, Int32(3 + i), id) }
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
    }

    private func updateSinglePath(_ db: OpaquePointer, rootID: String, path: String, home: String) {
        guard !SearchIndexRules.isExcluded(path, home: home) else { return }
        let generation = activeGeneration(db, rootID: rootID)
        guard generation > 0 else { return }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            removeSinglePath(db, rootID: rootID, path: path)
            return
        }
        let parentDir = (path as NSString).deletingLastPathComponent
        guard case .success(let siblings) = DirectoryReader.list(parentDir) else { return }
        guard let entry = siblings.first(where: { $0.path == path }) else {
            removeSinglePath(db, rootID: rootID, path: path)
            return
        }
        // `parentDir`'s own `folder_id` may not exist yet (its first child just appeared, or the crawl that would
        // have listed it never ran before being superseded) — `FolderTable.id(for:)` allocates one on demand rather
        // than requiring the caller to have seen it during a crawl, with `parentFolderID: nil` since a single
        // FSEvents-driven update has no ancestor chain to hand it (an orphaned `folders` row with no parent is
        // harmless: nothing reads `parent_folder_id` for anything this index does today, it exists purely so a
        // future "which folders are under X" query does not need a self-join over paths).
        var folders = FolderTable(rootID: rootID, generation: generation)
        let folderID = folders.id(for: parentDir, parentFolderID: nil, db: db)
        _ = insertBatch(db, rootID: rootID, generation: generation, entries: [entry], folderID: folderID)
    }

    // MARK: - Cursor persistence

    private func readCursor(_ rootID: String) -> UInt64? {
        guard let db else { return nil }
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        guard sqlite3_prepare_v2(db, "SELECT last_event_id FROM event_cursors WHERE root_id = ?", -1, &st, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return UInt64(bitPattern: sqlite3_column_int64(st, 0))
    }

    private func writeCursor(_ rootID: String, eventID: UInt64) {
        guard let db else { return }
        var st: OpaquePointer?
        let sql = "INSERT INTO event_cursors(root_id, last_event_id) VALUES (?, ?) ON CONFLICT(root_id) DO UPDATE SET last_event_id = excluded.last_event_id"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(bitPattern: eventID))
        sqlite3_step(st)
    }

    // MARK: - Search

    /// Tiered name search over roots inside `folders` (nil = every root). At most `limit`.
    ///
    /// Tiers, cheapest first (contract §1/§3): exact and prefix read the `name_key` B-tree index directly (a
    /// `LIKE 'query%'` against the indexed column, which SQLite can satisfy with a range scan since there is no
    /// leading wildcard); substring goes through the trigram FTS5 table; fuzzy re-ranks a bounded candidate set
    /// (every substring-tier miss plus a syntactic prefix scan capped by `NameMatcher`'s budget) with
    /// `NameMatcher.rank`, which already enforces `fuzzyBudget` and reports `tierEnded`.
    func search(_ query: String, within folders: [String]?, limit: Int) -> [Hit] {
        guard let db = openIfNeeded(), limit > 0 else { return [] }
        let foldedQuery = String(decoding: NameMatcher.fold(query), as: UTF8.self)
        guard !foldedQuery.isEmpty else { return [] }

        let rootIDs = scopedRootIDs(within: folders)
        guard !rootIDs.isEmpty else { return [] }

        var hits: [String: Hit] = [:]   // path -> best hit so far (a path can match more than once only via rowid reuse across tiers, which cannot happen here, but keyed by path defensively)

        for rootID in rootIDs {
            let generation = activeGeneration(db, rootID: rootID)
            guard generation > 0 else { continue }

            // Exact / prefix: one indexed query covers both, tier decided per row below.
            exactAndPrefixRows(db, rootID: rootID, generation: generation, foldedQuery: foldedQuery, limit: limit)
                .forEach { row in
                    if hits[row.path] == nil || hits[row.path]!.tier > row.tier { hits[row.path] = row }
                }
            if hits.count >= limit { continue }

            // Substring via trigram FTS5 (only when the query is long enough for the tokenizer to index at all —
            // trigram needs ≥ 3 bytes; shorter queries fall through to the prefix/fuzzy tiers only).
            if foldedQuery.utf8.count >= 3 {
                substringRows(db, rootID: rootID, generation: generation, foldedQuery: foldedQuery, limit: limit)
                    .forEach { row in
                        if hits[row.path] == nil || hits[row.path]!.tier > row.tier { hits[row.path] = row }
                    }
            }
        }

        if hits.count < limit {
            // Fuzzy: re-rank a small candidate set (every name in scope that the cheap tiers above did not already
            // place), budgeted by `NameMatcher.rank` so a huge index never makes a fuzzy query unbounded.
            let queryBytes = NameMatcher.fold(query)
            let candidates = fuzzyCandidates(db, rootIDs: rootIDs, query: queryBytes, excluding: Set(hits.keys), cap: 20_000)
            let (ranked, _) = NameMatcher.rank(
                candidates.map { (id: $0.path, name: NameMatcher.fold($0.name)) },
                query: queryBytes, limit: limit - hits.count, fuzzyBudget: 2_000
            )
            let byPath = Dictionary(uniqueKeysWithValues: candidates.map { ($0.path, $0) })
            for r in ranked {
                guard let row = byPath[r.id] else { continue }
                hits[row.path] = Hit(path: row.path, name: row.name, tier: r.match.tier, score: r.match.score,
                                      size: row.size, modified: row.modified, isFolder: row.isFolder)
            }
        }

        return hits.values.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.score != b.score { return a.score > b.score }
            return a.name < b.name
        }.prefix(limit).map { $0 }
    }

    private func scopedRootIDs(within folders: [String]?) -> [String] {
        guard let folders, !folders.isEmpty else { return rootOrder.filter { roots[$0] != nil } }
        return rootOrder.filter { id in
            guard let root = roots[id] else { return false }
            return folders.contains { folder in root.path == folder || root.path.hasPrefix(folder + "/") || folder.hasPrefix(root.path + "/") }
        }
    }

    /// Exact then prefix, as two SEPARATE statements (contract W5a "truy vấn chính xác phải đi B-tree (`= ?` trên
    /// `name_key` có chỉ mục, không `LIKE`) — mục tiêu < 1 ms"): the combined `>= ? AND < ? || X'FFFD'` range query
    /// this replaced satisfied the index too, but it is not what "exact lookup" means to `EXPLAIN QUERY PLAN` or to
    /// a reader of this code — a caller asking "does this exact name exist" deserves a query whose shape says so,
    /// and a literal `name_key = ?` is also one less lexicographic bound for SQLite to evaluate in the common case
    /// (most searches are not multi-result prefix lookups). Rows can appear in BOTH results for the one case where
    /// `foldedQuery` itself is a false positive for its own prefix range (never: `key == foldedQuery` also always
    /// satisfies `key.hasPrefix(foldedQuery)`), so prefix rows whose key equals the query are skipped — `hits[]` in
    /// `search()` would otherwise just overwrite them with the same tier anyway, but skipping avoids the redundant
    /// row entirely.
    private func exactAndPrefixRows(_ db: OpaquePointer, rootID: String, generation: Int, foldedQuery: String, limit: Int) -> [Hit] {
        var out = exactRows(db, rootID: rootID, generation: generation, foldedQuery: foldedQuery)
        if out.count < limit {
            out += prefixRows(db, rootID: rootID, generation: generation, foldedQuery: foldedQuery, limit: limit - out.count)
        }
        return out
    }

    /// `name_key = ?` on the `(root_id, generation, name_key)` index — `EXPLAIN QUERY PLAN` shows
    /// `SEARCH names USING INDEX idx_names_namekey (root_id=? AND generation=? AND name_key=?)`, a pure B-tree point
    /// lookup, no range operator (probe `scratchpad/c-engine/probe_exact.sh`, confirmed against the live plan).
    private func exactRows(_ db: OpaquePointer, rootID: String, generation: Int, foldedQuery: String) -> [Hit] {
        var st: OpaquePointer?
        let sql = """
        SELECT path, name, kind, size, mtime FROM names
        WHERE root_id = ? AND generation = ? AND name_key = ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(generation))
        sqlite3_bind_text(st, 3, foldedQuery, -1, SQLITE_TRANSIENT)
        var out: [Hit] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let pathPtr = sqlite3_column_text(st, 0), let namePtr = sqlite3_column_text(st, 1) else { continue }
            out.append(Hit(path: String(cString: pathPtr), name: String(cString: namePtr), tier: .exact, score: 1000,
                            size: sqlite3_column_int64(st, 3), modified: Date(timeIntervalSince1970: sqlite3_column_double(st, 4)),
                            isFolder: sqlite3_column_int(st, 2) == Int32(DirectoryEntry.Kind.directory.rawValue)))
        }
        return out
    }

    /// `name_key >= ? AND name_key < ? || X'FFFD'` on the same index — a range scan, STRICTLY the prefix tier now
    /// (the caller already handled the `key == foldedQuery` case via `exactRows`, so every row seen here has
    /// `key.hasPrefix(foldedQuery) && key != foldedQuery`, skipped explicitly since SQLite's range bounds alone
    /// cannot express "and not equal").
    private func prefixRows(_ db: OpaquePointer, rootID: String, generation: Int, foldedQuery: String, limit: Int) -> [Hit] {
        var st: OpaquePointer?
        let sql = """
        SELECT path, name, name_key, kind, size, mtime FROM names
        WHERE root_id = ? AND generation = ? AND name_key >= ? AND name_key < ? || X'FFFD'
        ORDER BY name_key LIMIT ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(generation))
        sqlite3_bind_text(st, 3, foldedQuery, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 4, foldedQuery, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(st, 5, Int32(limit * 4))   // over-fetch a little: the exact-key row (skipped below) still counts against this scan's LIMIT
        var out: [Hit] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let pathPtr = sqlite3_column_text(st, 0), let namePtr = sqlite3_column_text(st, 1),
                  let keyPtr = sqlite3_column_text(st, 2) else { continue }
            let key = String(cString: keyPtr)
            guard key.hasPrefix(foldedQuery) else { break }   // past the prefix range: ran out of prefix matches
            guard key != foldedQuery else { continue }        // already returned by `exactRows`
            out.append(Hit(path: String(cString: pathPtr), name: String(cString: namePtr), tier: .prefix, score: 500,
                            size: sqlite3_column_int64(st, 4), modified: Date(timeIntervalSince1970: sqlite3_column_double(st, 5)),
                            isFolder: sqlite3_column_int(st, 3) == Int32(DirectoryEntry.Kind.directory.rawValue)))
            if out.count >= limit { break }
        }
        return out
    }

    private func substringRows(_ db: OpaquePointer, rootID: String, generation: Int, foldedQuery: String, limit: Int) -> [Hit] {
        var st: OpaquePointer?
        // `ORDER BY rank` — not `bm25(f)`: FTS5's ranking function needs the virtual table referenced by its own
        // name, and rejects an alias ("no such column: f") the moment it is used as `bm25(f)` inside a join — the
        // implicit hidden `rank` column (equivalent to the default `bm25()` ordering) is what every join with an
        // alias must use instead. Verified against the live failure this caused (probe run: every substring query
        // returned 0 hits because `sqlite3_prepare_v2` silently failed and the miss was never surfaced until this
        // function started logging its own prepare/step errors).
        let sql = """
        SELECT n.path, n.name, n.kind, n.size, n.mtime FROM name_fts f
        JOIN names n ON n.rowid = f.rowid
        WHERE f.name_key MATCH ? AND n.root_id = ? AND n.generation = ?
        ORDER BY rank LIMIT ?
        """
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        // FTS5 parses the MATCH argument as its OWN query grammar (`.`, `*`, `:`, `"`, `-` are all operators there),
        // not a raw literal — an unquoted query containing one of those characters (a file extension dot, say) is a
        // syntax error, not a miss. Quoting as an FTS5 string literal (doubling embedded `"`) makes every character
        // in `foldedQuery` literal text to match, which is what a filename substring search means here. Verified
        // against the live failure this caused (probe: "le2." as a bare MATCH argument raised "fts5: syntax error
        // near \".\"" from the CLI and the Swift binding alike; the quoted form matches correctly).
        let quoted = "\"\(foldedQuery.replacingOccurrences(of: "\"", with: "\"\""))\""
        sqlite3_bind_text(st, 1, quoted, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 2, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 3, Int64(generation))
        sqlite3_bind_int(st, 4, Int32(limit))
        var out: [Hit] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let pathPtr = sqlite3_column_text(st, 0), let namePtr = sqlite3_column_text(st, 1) else { continue }
            out.append(Hit(path: String(cString: pathPtr), name: String(cString: namePtr), tier: .substring, score: 100,
                            size: sqlite3_column_int64(st, 3), modified: Date(timeIntervalSince1970: sqlite3_column_double(st, 4)),
                            isFolder: sqlite3_column_int(st, 2) == Int32(DirectoryEntry.Kind.directory.rawValue)))
        }
        return out
    }

    /// A subsequence match needs `name_key` to be at least as long as the query and to contain the query's first
    /// folded byte somewhere in it — both are cheap SQL predicates that narrow the scan before any Swift-side
    /// ranking, instead of taking whatever `cap` rows a plain `LIMIT` happens to return first. A bare `LIMIT` here
    /// (no `ORDER BY`, no filter) is a correctness bug, not just a perf shortcut: with the index larger than `cap`,
    /// it silently always samples the lexicographically-first rows under the primary key `(root_id, generation,
    /// path)`, so a fuzzy query whose match sorts later than the cap is NEVER found, no matter how good a
    /// subsequence match it is (caught by this probe: "f163dt" against 100 000 "f######.dat" files only matched once
    /// this filter replaced the unfiltered `LIMIT 20000`).
    private func fuzzyCandidates(_ db: OpaquePointer, rootIDs: [String], query: [UInt8], excluding: Set<String>, cap: Int) -> [Hit] {
        var out: [Hit] = []
        let firstByte = query.first
        let minLength = query.count
        for rootID in rootIDs {
            guard out.count < cap else { break }
            let generation = activeGeneration(db, rootID: rootID)
            guard generation > 0 else { continue }
            var st: OpaquePointer?
            let sql = """
            SELECT path, name, name_key, kind, size, mtime FROM names
            WHERE root_id = ? AND generation = ? AND length(name_key) >= ?
            LIMIT ?
            """
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { continue }
            sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 2, Int64(generation))
            sqlite3_bind_int(st, 3, Int32(minLength))
            // Over-fetch before the first-byte filter below (SQLite has no cheap "contains this byte" index), then
            // cap again in Swift — still bounded work, but no longer biased toward one lexicographic slice.
            sqlite3_bind_int(st, 4, Int32(min(cap * 4, 200_000)))
            while sqlite3_step(st) == SQLITE_ROW {
                guard let pathPtr = sqlite3_column_text(st, 0), let namePtr = sqlite3_column_text(st, 1),
                      let keyPtr = sqlite3_column_text(st, 2) else { continue }
                let path = String(cString: pathPtr)
                guard !excluding.contains(path) else { continue }
                if let firstByte, !Array(String(cString: keyPtr).utf8).contains(firstByte) { continue }
                out.append(Hit(path: path, name: String(cString: namePtr), tier: .fuzzy, score: 0,
                                size: sqlite3_column_int64(st, 4), modified: Date(timeIntervalSince1970: sqlite3_column_double(st, 5)),
                                isFolder: sqlite3_column_int(st, 3) == Int32(DirectoryEntry.Kind.directory.rawValue)))
                if out.count >= cap { break }
            }
            sqlite3_finalize(st)
        }
        return out
    }
}
