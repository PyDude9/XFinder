import Foundation
import SQLite3

/// XF-T30 W5a — maps a directory path to the small integer `folder_id` the `names` table stores instead of
/// repeating the parent path as text on every row inside it (contract "parent_id folder table instead of full
/// paths per row"). One responsibility: allocate/look up/delete rows in the `folders` table for one
/// `(root_id, generation)` pair. Not an actor itself — every method takes the caller's already-open `db` handle and
/// runs synchronously, so `FilenameIndex` (the only caller) stays the single place serializing access to that
/// handle; this type holds no mutable state of its own beyond a per-crawl in-memory cache that exists purely to
/// avoid a redundant SELECT for a folder this same crawl already allocated an id for.
struct FolderTable {
    let rootID: String
    let generation: Int

    /// Path -> folder_id already allocated or looked up during the LIFETIME OF THIS `FolderTable` VALUE. A fresh
    /// `FolderTable` is made per crawl (see `FilenameIndex.crawlSubtree`) so this cache never spans generations or
    /// roots and is always correctly empty at the start of a rebuild.
    private var cache: [String: Int64] = [:]

    init(rootID: String, generation: Int) {
        self.rootID = rootID
        self.generation = generation
    }

    /// The `folder_id` for `path`, creating a new row (with `parentFolderID` from the caller, who already knows its
    /// own ancestor chain from walking the tree top-down) if one does not exist yet for this root/generation.
    mutating func id(for path: String, parentFolderID: Int64?, db: OpaquePointer) -> Int64 {
        if let cached = cache[path] { return cached }
        if let existing = lookupRow(path: path, db: db) {
            cache[path] = existing
            return existing
        }
        let newID = nextFolderID(db: db)
        insertRow(folderID: newID, parentFolderID: parentFolderID, path: path, db: db)
        cache[path] = newID
        return newID
    }

    private func lookupRow(path: String, db: OpaquePointer) -> Int64? {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        let sql = "SELECT folder_id FROM folders WHERE root_id = ? AND generation = ? AND path = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(generation))
        sqlite3_bind_text(st, 3, path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(st, 0)
    }

    private func nextFolderID(db: OpaquePointer) -> Int64 {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        let sql = "SELECT COALESCE(MAX(folder_id), 0) + 1 FROM folders WHERE root_id = ? AND generation = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return 1 }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(generation))
        guard sqlite3_step(st) == SQLITE_ROW else { return 1 }
        return sqlite3_column_int64(st, 0)
    }

    private func insertRow(folderID: Int64, parentFolderID: Int64?, path: String, db: OpaquePointer) {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        let sql = "INSERT INTO folders(root_id, generation, folder_id, parent_folder_id, path) VALUES (?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(generation))
        sqlite3_bind_int64(st, 3, folderID)
        if let parentFolderID { sqlite3_bind_int64(st, 4, parentFolderID) } else { sqlite3_bind_null(st, 4) }
        sqlite3_bind_text(st, 5, path, -1, SQLITE_TRANSIENT)
        sqlite3_step(st)
    }

    /// Every `(path, folder_id)` row for this root/generation that is `path` itself or lives under it — used by
    /// `FilenameIndex.removeSinglePath`/`rescan` to translate a directory SUBTREE back into the set of `folder_id`
    /// values whose `names` rows must be deleted, since `names` no longer stores a path prefix it could `LIKE`
    /// against directly.
    static func folderIDs(under path: String, rootID: String, generation: Int, db: OpaquePointer) -> [Int64] {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        let sql = """
        SELECT folder_id FROM folders
        WHERE root_id = ? AND generation = ? AND (path = ? OR path LIKE ? || '/%')
        """
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(generation))
        sqlite3_bind_text(st, 3, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(st, 4, path, -1, SQLITE_TRANSIENT)
        var out: [Int64] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(sqlite3_column_int64(st, 0)) }
        return out
    }

    /// The `folder_id` for exactly `path` in this root/generation, if a row exists — used by `rescan`/
    /// `updateSinglePath` to resolve a single directory's own id without allocating a new one (the directory was
    /// already seen during the crawl that is now reconciling against a live FSEvents change).
    static func folderID(for path: String, rootID: String, generation: Int, db: OpaquePointer) -> Int64? {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        let sql = "SELECT folder_id FROM folders WHERE root_id = ? AND generation = ? AND path = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(st, 1, rootID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(st, 2, Int64(generation))
        sqlite3_bind_text(st, 3, path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(st, 0)
    }
}
