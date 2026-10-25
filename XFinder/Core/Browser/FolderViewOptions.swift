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
    private(set) var order: [String] = []
    private(set) var prefsByPath: [String: FolderViewPrefs] = [:]

    func prefs(for path: String) -> FolderViewPrefs? { prefsByPath[path] }
    mutating func set(_ prefs: FolderViewPrefs, for path: String) {}
    func encoded() -> Data { Data() }
    static func decode(_ data: Data?) -> FolderViewStore { FolderViewStore() }
}
