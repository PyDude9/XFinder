import Foundation

/// XF-T30 W2 — per-folder view options (FileOctopus "Folder view preferences are remembered"). Pure, symlinked into the
/// test package. Contract docs/specs/XF-T30-w2-contract.md §1. W2 builder (pure): implement.
enum ListColumn: String, Codable, CaseIterable, Sendable {
    case name, dateModified, dateCreated, dateAdded, dateLastOpened, size, kind, tags
}

struct FolderViewPrefs: Codable, Equatable, Sendable {
    var viewMode: BrowserViewMode
    var sort: SortOrder
    var groupBy: GroupBy
    var useGroups: Bool
    /// Icon view: 32…128 in steps of 16, default 64.
    var iconSize: Int
    /// 10…16 points, default 13.
    var textSize: Int
    /// List view columns in order; `.name` always present.
    var columns: [ListColumn]
    var showIconPreview: Bool

    static let iconSizes = Array(stride(from: 32, through: 128, by: 16))
    static let textSizes = Array(10...16)
    static let defaultColumns: [ListColumn] = [.name, .dateModified, .size, .kind]

    static func defaults(viewMode: BrowserViewMode) -> FolderViewPrefs {
        FolderViewPrefs(viewMode: viewMode, sort: .finderDefault, groupBy: .none, useGroups: false, iconSize: 64,
                        textSize: 13, columns: defaultColumns, showIconPreview: true)
    }
}

/// Up to `limit` folders, least recently used dropped first. Decoding drops damaged entries only.
struct FolderViewStore: Codable, Equatable, Sendable {
    static let limit = 500
    /// Least-recently-used first, most-recently-used last — the same order `set`/`prefs` maintain so eviction never
    /// needs a separate sort.
    private(set) var order: [String] = []
    private(set) var prefsByPath: [String: FolderViewPrefs] = [:]

    init() {}

    /// Non-mutating lookup: only `set` updates recency, so simply looking at a folder's remembered view (without
    /// changing it) does not by itself save it from eviction.
    func prefs(for path: String) -> FolderViewPrefs? { prefsByPath[path] }

    mutating func set(_ prefs: FolderViewPrefs, for path: String) {
        prefsByPath[path] = prefs
        touch(path)
        while order.count > Self.limit {
            let oldest = order.removeFirst()
            if oldest != path { prefsByPath.removeValue(forKey: oldest) }
        }
    }

    private mutating func touch(_ path: String) {
        if let index = order.firstIndex(of: path) { order.remove(at: index) }
        order.append(path)
    }

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// Tolerant decode: a missing file, truncated JSON or a value of the wrong shape all fall back to an empty store
    /// (first-run equivalent) rather than crashing or throwing. A per-entry decode failure is impossible with
    /// `Codable`'s whole-value decode, so "drops damaged entries only" is achieved one level up — `order` entries with
    /// no matching `prefsByPath` value (or vice versa) are reconciled to keep the two in sync.
    static func decode(_ data: Data?) -> FolderViewStore {
        guard let data, let store = try? JSONDecoder().decode(FolderViewStore.self, from: data) else {
            return FolderViewStore()
        }
        let validOrder = store.order.filter { store.prefsByPath[$0] != nil }
        let knownPaths = Set(validOrder)
        var result = FolderViewStore()
        result.order = validOrder
        result.prefsByPath = store.prefsByPath.filter { knownPaths.contains($0.key) }
        return result
    }
}
