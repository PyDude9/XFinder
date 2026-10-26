import Foundation

/// XF-T32 W0 — stub (builder `cache` replaces the bodies; signatures fixed by docs/specs/XF-T32-w0-contract.md §A).
struct ListingToken: Equatable, Codable, Sendable {
    let modifiedNs: Int64
    let changedNs: Int64
    let size: Int64
    let inode: UInt64
}

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
        name = entry.name; path = entry.path; kind = entry.kind.rawValue; isPackage = entry.isPackage
        isHidden = entry.isHidden; size = entry.size; modified = entry.modified; created = entry.created
        volumeID = entry.volumeID; hidesExtension = entry.hidesExtension; inode = entry.inode
        added = entry.added; lastOpened = entry.lastOpened; tags = entry.tags
    }

    func entry() -> DirectoryEntry {
        var e = DirectoryEntry(name: name, path: path, kind: DirectoryEntry.Kind(rawValue: kind) ?? .other,
                               isPackage: isPackage, isHidden: isHidden, size: size, modified: modified,
                               created: created, volumeID: volumeID)
        e.hidesExtension = hidesExtension; e.inode = inode; e.added = added; e.lastOpened = lastOpened; e.tags = tags
        return e
    }
}

enum ListingCacheRules {
    static let maxCachedEntries: Int = 20_000
    static let budgetBytes: Int64 = 64 << 20
    static let schemaVersion: Int32 = 1
    static func isFresh(stored: ListingToken, current: ListingToken?) -> Bool { false }
    static func shouldStore(entryCount: Int) -> Bool { false }
    static func evictionOrder(folders: [(path: String, updatedAt: Date, bytes: Int64)], totalBytes: Int64) -> [String] { [] }
}
