import Foundation

/// XF-T32 W0 — pure decisions for `DirectoryLoadCoordinator` (contract §B, docs/specs/XF-T32-w0-contract.md).
/// Foundation-only; symlinked into `Tests/XFinderLogicTests`.
enum ListingSource: Sendable { case cache, disk }

/// One listing handed to a subscriber.
struct ListingDelivery: Sendable {
    let entries: [DirectoryEntry]
    let source: ListingSource
    let token: ListingToken?
    /// `false` = a stale cache copy; the disk read that replaces it is already on its way (stale-while-revalidate).
    let isFinal: Bool
}

enum LoadCoordinatorRules {
    /// Folds `.`, `..`, duplicate and trailing slashes without touching the file system (symlinks, `/private`
    /// stay as spelled). `..` above the root stays at the root; a relative path stays relative; "" stays "".
    static func lexicalPath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        let absolute: Bool = path.hasPrefix("/")
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..":
                if let last: Substring = parts.last, last != ".." { parts.removeLast() }
                else if !absolute { parts.append(part) }
            default: parts.append(part)
            }
        }
        let joined: String = parts.joined(separator: "/")
        if absolute { return "/" + joined }
        return joined.isEmpty ? "." : joined
    }

    /// How many folder reads may hit the disk at the same time (shared by every pane).
    static let diskReadConcurrency: Int = 4

    enum Decision: Equatable { case deliverCache(final: Bool), readDisk }

    /// What to do when a folder session starts:
    /// - no cache (or a cache row without a token) ⇒ `[.readDisk]`;
    /// - cache whose token equals the folder's current `stat` token ⇒ `[.deliverCache(final: true), .readDisk]`:
    ///   the copy is shown as fresh, but a child's size/dates change without touching the folder's own token, so a
    ///   background read still revalidates (the pane patches the difference in place);
    /// - cache whose token differs, or the current token is unknown (stat failed) ⇒ show the cache now and
    ///   read the disk right after: `[.deliverCache(final: false), .readDisk]`. A failed stat never counts as fresh —
    ///   the disk read is what reports the real error.
    static func plan(hasCache: Bool, stored: ListingToken?, current: ListingToken?) -> [Decision] {
        guard hasCache, let storedToken: ListingToken = stored else { return [.readDisk] }
        guard let currentToken: ListingToken = current, currentToken == storedToken else {
            return [.deliverCache(final: false), .readDisk]
        }
        return [.deliverCache(final: true), .readDisk]
    }

    /// Pure membership book: which subscriber ids are attached to which (already normalised) folder path.
    struct SessionBook: Equatable {
        enum Event: Equatable {
            /// First subscriber of a path — the caller must open a session (read + watcher).
            case started
            /// Another subscriber joined a live session (or the same id subscribed twice — counted once).
            case joined
            /// A subscriber left; others remain.
            case left
            /// The last subscriber left — the caller must tear the session down.
            case closed
            /// Unsubscribe of an id/path the book does not know (already left, or the session already closed).
            case unknown
        }

        private var members: [String: Set<UUID>] = [:]

        init() {}

        mutating func subscribe(path: String, id: UUID) -> Event {
            var ids: Set<UUID> = members[path] ?? []
            let wasEmpty: Bool = ids.isEmpty
            ids.insert(id)
            members[path] = ids
            return wasEmpty ? .started : .joined
        }

        mutating func unsubscribe(path: String, id: UUID) -> Event {
            guard var ids: Set<UUID> = members[path], ids.remove(id) != nil else { return .unknown }
            if ids.isEmpty {
                members[path] = nil
                return .closed
            }
            members[path] = ids
            return .left
        }

        func count(path: String) -> Int { members[path]?.count ?? 0 }
    }
}
