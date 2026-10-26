import Foundation
import SQLite3

/// XF-T32 W0 — stub (builder `cache`): SQLite listing cache. Contract §A.
actor ListingDiskCache {
    static let shared = ListingDiskCache(databaseURL: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XFinder/Browser/listing-cache.sqlite"))
    private let databaseURL: URL

    init(databaseURL: URL) { self.databaseURL = databaseURL }

    func lookup(_ folderPath: String) -> (token: ListingToken, entries: [DirectoryEntry])? { nil }
    func store(_ folderPath: String, token: ListingToken, entries: [DirectoryEntry]) {}
    func invalidate(_ folderPath: String) {}
    func removeAll() {}
    func approximateBytes() -> Int64 { 0 }

    nonisolated static func currentToken(for folderPath: String) -> ListingToken? { nil }
}
