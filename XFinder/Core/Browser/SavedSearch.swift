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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Tìm kiếm đã lưu" : trimmed
        let taken = Set(searches.map { $0.name.lowercased() })
        var unique = base
        if taken.contains(base.lowercased()) {
            var n = 2
            while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
            unique = "\(base) \(n)"
        }
        let saved = SavedSearch(id: UUID(), name: unique, query: query, scope: scope, folder: folder,
                                 showInSidebar: showInSidebar, created: now)
        searches.append(saved)
        return saved
    }

    /// Empty names, and a name another saved search already has (case-insensitively), are refused (nothing changes).
    @discardableResult mutating func rename(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = searches.firstIndex(where: { $0.id == id }),
              !searches.contains(where: { $0.id != id && $0.name.lowercased() == trimmed.lowercased() }) else { return false }
        searches[i].name = trimmed
        return true
    }

    mutating func delete(_ id: UUID) {
        searches.removeAll { $0.id == id }
    }

    mutating func setShowInSidebar(_ id: UUID, _ on: Bool) {
        guard let i = searches.firstIndex(where: { $0.id == id }) else { return }
        searches[i].showInSidebar = on
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(searches)) ?? Data()
    }

    /// One damaged entry costs only itself: decode the JSON array as a loose `[Any]` first, then decode each element
    /// on its own — one malformed element is skipped, the rest still load. Garbage (not even a JSON array) or empty
    /// data costs nothing (empty store, no crash). W5a builder (pure): implement.
    static func decode(_ data: Data?) -> SavedSearchStore {
        var store = SavedSearchStore()
        guard let data, !data.isEmpty,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return store }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for item in raw {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let saved = try? decoder.decode(SavedSearch.self, from: itemData) else { continue }
            store.searches.append(saved)
        }
        return store
    }
}
