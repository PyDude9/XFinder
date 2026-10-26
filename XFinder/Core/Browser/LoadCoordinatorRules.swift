import Foundation

/// XF-T32 W0 — stub (builder `coordinator`): pure decisions for DirectoryLoadCoordinator. Contract §B.
enum ListingSource: Sendable { case cache, disk }

struct ListingDelivery: Sendable {
    let entries: [DirectoryEntry]
    let source: ListingSource
    let token: ListingToken?
    let isFinal: Bool
}

enum LoadCoordinatorRules {
    static let diskReadConcurrency: Int = 4

    enum Decision: Equatable { case deliverCache(final: Bool), readDisk }

    static func plan(hasCache: Bool, stored: ListingToken?, current: ListingToken?) -> [Decision] { [.readDisk] }

    struct SessionBook: Equatable {
        enum Event: Equatable { case started, joined, left, closed, unknown }
        private var members: [String: Set<UUID>] = [:]
        init() {}
        mutating func subscribe(path: String, id: UUID) -> Event { .started }
        mutating func unsubscribe(path: String, id: UUID) -> Event { .unknown }
        func count(path: String) -> Int { 0 }
    }
}
