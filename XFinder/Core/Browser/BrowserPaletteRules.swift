import Foundation

/// Bounded local usage, stable fuzzy ranking and mode filtering, independent of the window.
enum BrowserPaletteRules {
    static let usageKey = "palette.usage"
    static let usageLimit = 512
    enum Kind: String, Sendable { case location, command, move }
    struct Item: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let subtitle: String
        let target: String
        let kind: Kind
        let aliases: [String]
        var isDirectory: Bool? = nil
    }
    /// Resolve snapshot aliases once, but leave a typed target for commit-time validation.
    static func preparing(_ items: [Item], destinationsOnly: Bool, typedPath: String?,
                          knownKinds: [String: Bool], isDirectory: (String) -> Bool) -> [Item] {
        guard destinationsOnly else { return items }
        return items.map { original in
            var item = original
            if item.kind == .location, item.isDirectory == nil, item.target != typedPath {
                item.isDirectory = knownKinds[item.target] ?? isDirectory(item.target)
            }
            return item
        }
    }
    static func usage(_ data: Data) -> [String: Int] {
        let decoded = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
        return decoded.filter { !$0.key.isEmpty && $0.value > 0 }.mapValues { min($0, 1_000_000) }
    }
    static func recording(_ id: String, in data: Data) -> Data {
        var values = usage(data)
        values[id] = min((values[id] ?? 0) + 1, 1_000_000)
        let keep = values.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(usageLimit)
        return (try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) }))) ?? data
    }
    static func rank(query: String, items: [Item], usage: [String: Int], destinationsOnly: Bool, limit: Int = 50) -> [Item] {
        let mode = BrowserCommands.commandMode(query)
        return items.enumerated().compactMap { index, item -> (Int, Item, Int, Int)? in
            if destinationsOnly && (item.kind != .location || item.isDirectory == false) { return nil }
            if mode.isCommand && item.kind == .location { return nil }
            let search = mode.isCommand ? mode.rest : query
            let scores = ([item.title] + item.aliases).compactMap { BrowserCommands.score(query: search, candidate: $0) }
            guard let score = scores.max() else { return nil }
            return (index, item, score, usage[item.id] ?? 0)
        }.sorted {
            if $0.2 != $1.2 { return $0.2 > $1.2 }
            if $0.3 != $1.3 { return $0.3 > $1.3 }
            return $0.0 < $1.0
        }.prefix(max(0, limit)).map { $0.1 }
    }
}
