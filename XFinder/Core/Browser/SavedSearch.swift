import Foundation

/// XF-T30 W5a — saved searches (FileOctopus: a saved search keeps the QUERY and the place, never a frozen result list;
/// relative dates re-evaluate on every run). Pure, symlinked into the test package.
struct SavedSearch: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var query: String
    /// `PaneSearchState.Scope` raw value.
    var scope: String
    /// The folder a `folder` scope searched.
    var folder: String?
    var showInSidebar: Bool
    var created: Date
}

struct SavedSearchStore: Codable, Equatable, Sendable {
    private(set) var searches: [SavedSearch] = []

    /// Unique, trimmed, never empty (like `WorkspaceStore.save`). W5a builder (pure): implement.
    mutating func add(name: String, query: String, scope: String, folder: String?, showInSidebar: Bool, now: Date) -> SavedSearch {
        SavedSearch(id: UUID(), name: name, query: query, scope: scope, folder: folder, showInSidebar: showInSidebar, created: now)
    }
    @discardableResult mutating func rename(_ id: UUID, to name: String) -> Bool { false }
    mutating func delete(_ id: UUID) {}
    mutating func setShowInSidebar(_ id: UUID, _ on: Bool) {}
    func encoded() -> Data { Data() }
    /// One damaged entry costs only itself. W5a builder (pure): implement.
    static func decode(_ data: Data?) -> SavedSearchStore { SavedSearchStore() }
}
