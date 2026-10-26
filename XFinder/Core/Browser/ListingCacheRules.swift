import Foundation

/// XF-T32 W0 §A — pure rules of the on-disk listing cache (`ListingDiskCache`). Mechanism measured in Tilde's
/// `DirectoryListingDiskCache` (a `validation_token` per folder): a cached listing is shown only while the folder's own
/// `lstat` still matches the one taken when the listing was read.

/// A folder's fingerprint at listing time: `lstat` of the folder itself. Equal ⇒ the cached listing is still right.
struct ListingToken: Equatable, Codable, Sendable {
    let modifiedNs: Int64      // st_mtimespec
    let changedNs: Int64       // st_ctimespec
    let size: Int64            // st_size of the folder
    let inode: UInt64
}

/// One cache row ↔ `DirectoryEntry` (every stored field of the entry; `nameKey` is recomputed by `DirectoryEntry.init`).
struct ListingRow: Equatable, Codable, Sendable {
    let name: String
    let path: String
    let kind: UInt8
    let isPackage: Bool
    let isHidden: Bool
    let size: Int64
    let modified: Date
    let created: Date
    let volumeID: Int32
    let hidesExtension: Bool
    let inode: UInt64?
    let added: Date?
    let lastOpened: Date?
    let tags: [String]?

    init(_ entry: DirectoryEntry) {
        name = entry.name
        path = entry.path
        kind = entry.kind.rawValue
        isPackage = entry.isPackage
        isHidden = entry.isHidden
        size = entry.size
        modified = entry.modified
        created = entry.created
        volumeID = entry.volumeID
        hidesExtension = entry.hidesExtension
        inode = entry.inode
        added = entry.added
        lastOpened = entry.lastOpened
        tags = entry.tags
    }

    /// An unknown stored kind (a newer schema wrote it) reads back as `.other`, never a crash.
    func entry() -> DirectoryEntry {
        let resolvedKind: DirectoryEntry.Kind = DirectoryEntry.Kind(rawValue: kind) ?? .other
        var result: DirectoryEntry = DirectoryEntry(name: name, path: path, kind: resolvedKind, isPackage: isPackage,
                                                    isHidden: isHidden, size: size, modified: modified,
                                                    created: created, volumeID: volumeID)
        result.hidesExtension = hidesExtension
        result.inode = inode
        result.added = added
        result.lastOpened = lastOpened
        result.tags = tags
        return result
    }
}

enum ListingCacheRules {
    /// Larger folders are not cached: reading 100 000 entries from disk takes 101 ms, the cache would not win.
    static let maxCachedEntries: Int = 20_000
    /// Target total size of the cache database.
    static let budgetBytes: Int64 = 64 << 20
    /// `journal_size_limit` for the cache's -wal file.
    static let walLimitBytes: Int64 = 8 << 20
    static let schemaVersion: Int32 = 1

    /// `current` nil (lstat failed: folder gone or unreadable) ⇒ never fresh. A rename keeps mtime but the token of the
    /// path now belongs to another inode (or none), so any field differing ⇒ stale.
    static func isFresh(stored: ListingToken, current: ListingToken?) -> Bool {
        guard let current: ListingToken = current else { return false }
        return stored == current
    }

    /// An empty folder is worth caching (it still costs a disk read); a negative count is a caller bug ⇒ no.
    static func shouldStore(entryCount: Int) -> Bool {
        entryCount >= 0 && entryCount <= maxCachedEntries
    }

    /// Folders to drop (oldest first) so that `totalBytes` ends ≤ budget; each element is (path, updatedAt, bytes).
    /// Ties on `updatedAt` break by path so the order is deterministic. A negative byte count frees nothing.
    static func evictionOrder(folders: [(path: String, updatedAt: Date, bytes: Int64)], totalBytes: Int64) -> [String] {
        guard totalBytes > budgetBytes else { return [] }
        let oldestFirst: [(path: String, updatedAt: Date, bytes: Int64)] = folders.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.path < rhs.path
        }
        var remaining: Int64 = totalBytes
        var evicted: [String] = []
        for folder in oldestFirst {
            if remaining <= budgetBytes { break }
            evicted.append(folder.path)
            let freed: Int64 = max(0, folder.bytes)
            let (next, overflow): (Int64, Bool) = remaining.subtractingReportingOverflow(freed)
            remaining = overflow ? Int64.min : next
        }
        return evicted
    }
}
