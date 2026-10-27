import Foundation
import Observation

/// Synchronous UI reads over an actor-backed store. Writes are ordered; a load that crossed a local edit is retried
/// rather than publishing an obsolete snapshot over optimistic UI state.
@MainActor @Observable final class BrowserMetadata {
    static let shared = BrowserMetadata(store: .shared)

    private struct Visibility: Equatable, Sendable {
        var property: UUID
        var showInView: Bool
    }
    private struct FolderCache: Equatable {
        var pins: [String]
        var emoji: [String: String]
        var properties: [Visibility]
    }

    @ObservationIgnored private let store: MetadataStore
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private var folders: [String: FolderCache] = [:]
    @ObservationIgnored private var recent: [String] = []
    @ObservationIgnored private var emojiCache: [String: String] = [:]
    @ObservationIgnored private var nicknames: [String: String] = [:]
    @ObservationIgnored private var selections: [UUID: [String: UUID]] = [:]
    @ObservationIgnored private var relations: [FolderRelation] = []
    @ObservationIgnored private var groupRefs: [LiveGroupRef] = []
    @ObservationIgnored private var groupRevision: Int = -1
    @ObservationIgnored private var groupResult: [PropertyRules.LiveGroup] = []
    private(set) var revision: Int = 0
    private(set) var catalog = PropertyCatalog()

    init(store: MetadataStore) {
        self.store = store
        refresh(folder: nil)
    }

    /// Task creation and all cache publication occur on the main actor; SQLite work always runs on the store actor.
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await operation()
        }
    }

    func load(folder: String) {
        let key = MetadataStore.normalized(folder)
        guard !key.isEmpty, loading.insert(key).inserted else { return }
        recent.removeAll { $0 == key }
        recent.append(key)
        refresh(folder: key)
    }

    private func refresh(folder: String?) {
        let before = revision
        enqueue { [self] in
            let newCatalog = await store.catalog()
            let newNames = await store.allNicknames()
            let newSelections = await store.allSelections()
            let newRelations = await store.relations()
            var cache: FolderCache?
            if let folder {
                let pins = await store.pins(in: folder)
                let emoji = await store.emoji(in: folder)
                let properties = await store.folderProperties(folder)
                cache = FolderCache(pins: pins, emoji: emoji,
                                    properties: properties.map { Visibility(property: $0.property, showInView: $0.showInView) })
            }
            if let folder { loading.remove(folder) }
            // A mutation made while SQLite was suspended owns the UI. Its queued write precedes the retry.
            guard before == revision else {
                if let folder { load(folder: folder) } else { refresh(folder: nil) }
                return
            }
            var changed = catalog != newCatalog || nicknames != newNames || selections != newSelections || relations != newRelations
            catalog = newCatalog
            nicknames = newNames
            selections = newSelections
            relations = newRelations
            if let folder, let cache {
                // An empty first load has no user-visible difference from an uncached folder.
                let empty = FolderCache(pins: [], emoji: [:], properties: [])
                changed = changed || (folders[folder] ?? empty) != cache
                for key in folders[folder]?.emoji.keys ?? Dictionary<String, String>().keys { emojiCache[key] = nil }
                emojiCache.merge(cache.emoji) { _, new in new }
                folders[folder] = cache
            }
            if changed { revision &+= 1 }
        }
    }

    func pins(in folder: String) -> [String] { folders[MetadataStore.normalized(folder)]?.pins ?? [] }
    var paletteNicknames: [(path: String, nickname: String)] {
        _ = revision
        return nicknames.sorted { $0.key < $1.key }.prefix(1000).map { (path: $0.key, nickname: $0.value) }
    }
    func nickname(for path: String) -> String? { nicknames[MetadataStore.normalized(path)] }
    func emoji(for folder: String) -> String? {
        let key = MetadataStore.normalized(folder)
        return emojiCache[key]
    }
    func option(for path: String, property: UUID) -> PropertyOption? {
        guard let definition = catalog.definition(property) else { return nil }
        return PropertyRules.option(for: MetadataStore.normalized(path), property: definition, selections: selections[property] ?? [:])
    }
    func shownProperties(in folder: String) -> [(definition: PropertyDefinition, showInView: Bool)] {
        (folders[MetadataStore.normalized(folder)]?.properties ?? []).compactMap { item in
            catalog.definition(item.property).map { (definition: $0, showInView: item.showInView) }
        }
    }
    func visibleProperties(in folder: String) -> [PropertyDefinition] {
        shownProperties(in: folder).filter(\.showInView).map(\.definition)
    }

    private func ensureFolder(_ key: String) {
        if folders[key] == nil {
            load(folder: key)
            folders[key] = FolderCache(pins: [], emoji: [:], properties: [])
        }
    }
    func togglePin(_ path: String, in folder: String) {
        let key = MetadataStore.normalized(folder)
        ensureFolder(key)
        let value = PinRules.toggled(pins(in: key), path: MetadataStore.normalized(path))
        folders[key]?.pins = value
        revision &+= 1
        let editRevision = revision
        let path = MetadataStore.normalized(path)
        enqueue { [self] in
            let persisted = await store.pins(in: key)
            let actual = PinRules.toggled(persisted, path: path)
            await store.setPins(actual, in: key)
            if revision == editRevision, folders[key]?.pins != actual {
                folders[key]?.pins = actual
                revision &+= 1
            }
        }
    }
    func setNickname(_ nickname: String?, for path: String) {
        let key = MetadataStore.normalized(path)
        let value = nickname.flatMap(NicknameRules.normalized)
        nicknames[key] = value
        revision &+= 1
        enqueue { [store] in await store.setNickname(value, for: key) }
    }
    func setEmoji(_ emoji: String?, for folder: String) {
        let key = MetadataStore.normalized(folder)
        let value = emoji.flatMap(EmojiRules.normalized)
        ensureFolder(key)
        folders[key]?.emoji[key] = value
        emojiCache[key] = value
        let parent = Self.parent(key)
        if folders[parent] != nil { folders[parent]?.emoji[key] = value }
        revision &+= 1
        enqueue { [store] in await store.setEmoji(value, for: key) }
    }
    func select(path: String, property: UUID, option: UUID?) {
        let key = MetadataStore.normalized(path)
        selections[property, default: [:]][key] = option
        revision &+= 1
        enqueue { [store] in await store.select(path: key, property: property, option: option) }
    }
    func updateCatalog(_ change: (inout PropertyCatalog) -> Void) {
        let old = catalog
        var updated = catalog
        change(&updated)
        catalog = updated
        // Match saveCatalog's purge policy: remove only definitions/options this edit actually removed.
        for definition in old.definitions {
            if let next = updated.definition(definition.id) {
                let removed = Set(definition.options.map(\.id)).subtracting(next.options.map(\.id))
                selections[definition.id] = selections[definition.id]?.filter { !removed.contains($0.value) }
            } else {
                selections[definition.id] = nil
                for key in Array(folders.keys) { folders[key]?.properties.removeAll { $0.property == definition.id } }
            }
        }
        revision &+= 1
        let editRevision = revision
        enqueue { [self] in
            // Editing before bootstrap finishes must not erase other persisted definitions.
            var actual = await store.catalog()
            let deleted = Set(old.definitions.map(\.id)).subtracting(updated.definitions.map(\.id))
            actual.definitions.removeAll { deleted.contains($0.id) }
            for definition in updated.definitions where old.definition(definition.id) != definition {
                if let index = actual.definitions.firstIndex(where: { $0.id == definition.id }) {
                    actual.definitions[index] = definition
                } else {
                    actual.definitions.append(definition)
                }
            }
            await store.saveCatalog(actual)
            if revision == editRevision, catalog != actual {
                catalog = actual
                revision &+= 1
            }
        }
    }
    func setFolderProperties(_ folder: String, _ list: [(property: UUID, showInView: Bool)]) {
        let key = MetadataStore.normalized(folder)
        ensureFolder(key)
        var seen: Set<UUID> = []
        let value = list.filter { seen.insert($0.property).inserted }
        folders[key]?.properties = value.map { Visibility(property: $0.property, showInView: $0.showInView) }
        revision &+= 1
        enqueue { [store] in await store.setFolderProperties(key, value) }
    }
    func related(to folder: String) -> [String] {
        RelationRules.related(to: MetadataStore.normalized(folder), in: relations)
    }
    func addRelation(_ a: String, _ b: String) { editRelation(a, b, adding: true) }
    func removeRelation(_ a: String, _ b: String) { editRelation(a, b, adding: false) }
    private func editRelation(_ a: String, _ b: String, adding: Bool) {
        let a = MetadataStore.normalized(a), b = MetadataStore.normalized(b)
        func edited(_ current: [FolderRelation]) -> [FolderRelation] {
            if adding { return RelationRules.adding(current, a: a, b: b) }
            return current.filter { !(($0.a == a && $0.b == b) || ($0.a == b && $0.b == a)) }
        }
        relations = edited(relations)
        revision &+= 1
        let editRevision = revision
        enqueue { [self] in
            let actual = edited(await store.relations())
            await store.setRelations(actual)
            if revision == editRevision, relations != actual {
                relations = actual
                revision &+= 1
            }
        }
    }
    func liveGroups(_ refs: [LiveGroupRef]) -> [PropertyRules.LiveGroup] {
        if groupRevision != revision || groupRefs != refs {
            groupResult = PropertyRules.liveGroups(catalog: catalog, selections: selections, nicknames: nicknames, wanted: refs)
            groupRevision = revision
            groupRefs = refs
        }
        return groupResult
    }

    func itemMoved(from: String, to: String) {
        let source = MetadataStore.normalized(from), target = MetadataStore.normalized(to)
        guard !source.isEmpty, source != "/", !target.isEmpty, source != target else { return }
        rewrite { path in
            Self.contains(path, under: source) ? target + String(path.dropFirst(source.count)) : path
        }
        revision &+= 1
        enqueue { [store] in await store.itemMoved(from: source, to: target) }
    }
    func itemRemoved(_ path: String) {
        let key = MetadataStore.normalized(path)
        guard !key.isEmpty, key != "/" else { return }
        rewrite { Self.contains($0, under: key) ? nil : $0 }
        revision &+= 1
        enqueue { [store] in await store.itemRemoved(key) }
    }
    private func rewrite(_ transform: (String) -> String?) {
        func mapKeys<T>(_ dictionary: [String: T]) -> [String: T] {
            var result: [String: T] = [:]
            // Moved source wins over an old destination, like SQLite's OR REPLACE.
            for (key, value) in dictionary where transform(key) == key { result[key] = value }
            for (key, value) in dictionary {
                if let new = transform(key), new != key { result[new] = value }
            }
            return result
        }
        emojiCache = mapKeys(emojiCache)
        nicknames = mapKeys(nicknames)
        selections = selections.mapValues { mapKeys($0) }
        folders = mapKeys(folders).mapValues { cache in
            FolderCache(pins: cache.pins.compactMap(transform), emoji: mapKeys(cache.emoji), properties: cache.properties)
        }
        relations = relations.compactMap { relation in
            guard let a = transform(relation.a), let b = transform(relation.b) else { return nil }
            return FolderRelation(id: relation.id, a: a, b: b)
        }
        recent = recent.compactMap(transform)
    }
    func relieve(_ plan: PressureRules.Plan) {
        guard plan.dropIdleSessions else { return }
        let keep = Set(recent.suffix(8))
        folders = folders.filter { keep.contains($0.key) }
        emojiCache = folders.values.reduce(into: [:]) { $0.merge($1.emoji) { _, new in new } }
        recent = Array(recent.suffix(8))
        groupResult = []
        groupRevision = -1
        revision &+= 1
    }
    private static func parent(_ path: String) -> String {
        guard path != "/", let slash = path.lastIndex(of: "/") else { return "" }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }
    private static func contains(_ path: String, under root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
