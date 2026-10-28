import Foundation

/// XF-T32 W1 §D — Spaces: one sidebar per context (Tilde: the sidebar title switches Space, page dots at its foot) plus
/// that context's Live Groups and saved workspaces. System folders/volumes (Locations) are shared by every Space and so
/// are not stored here. Pure Foundation, symlinked into `Tests/XFinderLogicTests` (`SpaceModelTests`).
///
/// Invariant kept by every mutating API: `spaces` is never empty and `activeID` names one of its members. Because the
/// stored properties are `var` (contract), reads still tolerate a value that breaks it (`active` and the activation
/// helpers fall back to the first Space, or to a synthesized one when the list is empty) instead of trapping.
struct Space: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    /// SF Symbol name, or nil for the default glyph.
    var symbol: String?
    var sidebar: SidebarLayout
    var liveGroups: [LiveGroupRef]
    /// Points into the existing `WorkspaceStore`.
    var workspaceIDs: [UUID]
    /// Source-folder groups are additive; property-backed `liveGroups` remain untouched.
    var folderLiveGroups: [FolderLiveGroup] = []
}

/// A saved, nonrecursive view over one folder. It stores criteria, never file contents or copied items.
struct FolderLiveGroup: Codable, Equatable, Identifiable, Sendable {
    enum Field: String, Codable, CaseIterable, Sendable { case name, fileExtension, kind }
    enum MatchOperator: String, Codable, CaseIterable, Sendable { case contains, equals, beginsWith, endsWith }
    enum Sort: String, Codable, CaseIterable, Sendable { case nameAscending, nameDescending, modifiedNewest, modifiedOldest }

    struct Filter: Codable, Equatable, Identifiable, Sendable {
        var id: UUID = UUID()
        var field: Field
        var operation: MatchOperator
        var value: String

        var isValid: Bool {
            let value = normalizedValue
            guard !value.isEmpty else { return false }
            return field != .kind || (operation == .equals && ["folder", "file"].contains(value))
        }

        fileprivate var normalizedValue: String {
            var value = FolderLiveGroup.folded(value.trimmingCharacters(in: .whitespacesAndNewlines))
            if field == .fileExtension { value = String(value.drop(while: { $0 == "." })) }
            return value
        }
    }

    struct Candidate: Equatable, Sendable {
        var path: String
        var name: String
        var isDirectory: Bool
        var modifiedDate: Date? = nil
    }

    var id: UUID = UUID()
    var name: String
    var sourcePath: String
    var filters: [Filter]
    var sort: Sort = .nameAscending

    var isValid: Bool { normalized != nil }

    /// No invalid criterion is silently removed: doing so would broaden the saved view unexpectedly.
    var normalized: FolderLiveGroup? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, sourcePath.hasPrefix("/"), !sourcePath.contains("\0"),
              !filters.isEmpty, filters.allSatisfy(\.isValid) else { return nil }
        var result = self
        result.name = trimmedName
        result.sourcePath = (sourcePath as NSString).standardizingPath
        result.filters = filters.map { filter in
            var result = filter
            result.value = filter.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return result
        }
        return result
    }

    func matches(name: String, isDirectory: Bool, modifiedDate: Date? = nil) -> Bool {
        guard isValid else { return false }
        return filters.allSatisfy { filter in
            let subject: String
            switch filter.field {
            case .name: subject = Self.folded(name)
            case .fileExtension: subject = isDirectory ? "" : Self.folded((name as NSString).pathExtension)
            case .kind: subject = isDirectory ? "folder" : "file"
            }
            let value = filter.normalizedValue
            switch filter.operation {
            case .contains: return subject.contains(value)
            case .equals: return subject == value
            case .beginsWith: return subject.hasPrefix(value)
            case .endsWith: return subject.hasSuffix(value)
            }
        }
    }

    func matching(_ candidates: [Candidate]) -> [Candidate] {
        candidates.filter { matches(name: $0.name, isDirectory: $0.isDirectory, modifiedDate: $0.modifiedDate) }
            .sorted { lhs, rhs in
                switch sort {
                case .nameAscending, .nameDescending:
                    let compared = lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                                                    locale: Locale(identifier: "en_US_POSIX"))
                    if compared != .orderedSame {
                        return sort == .nameAscending ? compared == .orderedAscending : compared == .orderedDescending
                    }
                case .modifiedNewest, .modifiedOldest:
                    switch (lhs.modifiedDate, rhs.modifiedDate) {
                    case (.some(let left), .some(let right)) where left != right:
                        return sort == .modifiedNewest ? left > right : left < right
                    case (.some, .none): return true
                    case (.none, .some): return false
                    default: break
                    }
                }
                return lhs.path < rhs.path
            }
    }

    fileprivate static func folded(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                           locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension FolderLiveGroup {
    private enum CodingKeys: String, CodingKey { case id, name, sourcePath, filters, sort }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        sourcePath = try values.decode(String.self, forKey: .sourcePath)
        filters = try values.decode([Filter].self, forKey: .filters)
        sort = try values.decodeIfPresent(Sort.self, forKey: .sort) ?? .nameAscending
        guard let normalized else {
            throw DecodingError.dataCorruptedError(forKey: .filters, in: values, debugDescription: "Invalid folder group criteria")
        }
        self = normalized
    }
}

extension Space {
    private enum CodingKeys: String, CodingKey { case id, name, symbol, sidebar, liveGroups, workspaceIDs, folderLiveGroups }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol)
        sidebar = try values.decode(SidebarLayout.self, forKey: .sidebar)
        liveGroups = try values.decode([LiveGroupRef].self, forKey: .liveGroups)
        workspaceIDs = try values.decode([UUID].self, forKey: .workspaceIDs)
        let groups = try values.decodeIfPresent([LossyFolderLiveGroup].self, forKey: .folderLiveGroups) ?? []
        var seen: Set<UUID> = []
        folderLiveGroups = groups.compactMap(\.value).filter { seen.insert($0.id).inserted }
    }
}

private struct LossyFolderLiveGroup: Decodable {
    let value: FolderLiveGroup?
    init(from decoder: Decoder) throws { value = try? FolderLiveGroup(from: decoder) }
}

struct SpaceStore: Codable, Equatable, Sendable {
    static let currentSchemaVersion: Int = 1
    /// L10n key of the Space that wraps the person's pre-Spaces sidebar on first launch.
    static let migratedSpaceNameKey: String = "Cá nhân"
    /// Name used when `add` receives a blank name.
    static let defaultNewSpaceName: String = "Space"

    var schemaVersion: Int
    var spaces: [Space]
    var activeID: UUID

    /// First launch: a single "Cá nhân" Space wrapping the existing `SidebarLayout`, so nothing the person pinned is lost.
    static func migrated(from layout: SidebarLayout) -> SpaceStore {
        let space: Space = Space(id: UUID(), name: migratedSpaceNameKey, symbol: nil, sidebar: layout,
                                 liveGroups: [], workspaceIDs: [])
        return SpaceStore(schemaVersion: currentSchemaVersion, spaces: [space], activeID: space.id)
    }

    // MARK: - Reading

    /// The Space whose sidebar is shown. Orphan `activeID` ⇒ first Space; empty list ⇒ a synthesized fresh Space
    /// carrying `activeID` (never a trap).
    var active: Space {
        if let index: Int = activeIndex { return spaces[index] }
        return Space(id: activeID, name: Self.migratedSpaceNameKey, symbol: nil, sidebar: SidebarLayout(),
                     liveGroups: [], workspaceIDs: [])
    }

    /// Index of the active Space; an orphan `activeID` resolves to 0; nil only when `spaces` is empty.
    private var activeIndex: Int? {
        guard !spaces.isEmpty else { return nil }
        return spaces.firstIndex { $0.id == activeID } ?? 0
    }

    private func index(of id: UUID) -> Int? {
        spaces.firstIndex { $0.id == id }
    }

    // MARK: - Add / rename / delete

    /// Appends a new Space (does not activate it — the caller decides). Blank name ⇒ "Space"; a name already used
    /// (trimmed, case- and normalization-insensitive) gets " 2", " 3", … `cloningSidebarFrom` copies that Space's
    /// sidebar with a fresh UUID on every item and group; nil or an unknown id ⇒ a fresh default sidebar.
    @discardableResult
    mutating func add(name: String, cloningSidebarFrom sourceID: UUID?) -> Space {
        let trimmed: String = SpaceNaming.trimmed(name)
        let base: String = trimmed.isEmpty ? Self.defaultNewSpaceName : trimmed
        let unique: String = SpaceNaming.uniqueName(base: base, taken: spaces.map(\.name))
        let sidebar: SidebarLayout = sourceID
            .flatMap { index(of: $0) }
            .map { SidebarCloner.cloneWithFreshIDs(spaces[$0].sidebar) } ?? SidebarLayout()
        let space: Space = Space(id: UUID(), name: unique, symbol: nil, sidebar: sidebar, liveGroups: [], workspaceIDs: [])
        spaces.append(space)
        if index(of: activeID) == nil { activeID = spaces[0].id }
        return space
    }

    /// Blank names, unknown ids, and a name another Space already uses are refused (false, nothing changes).
    @discardableResult
    mutating func rename(_ id: UUID, to name: String) -> Bool {
        let trimmed: String = SpaceNaming.trimmed(name)
        guard !trimmed.isEmpty, let target: Int = index(of: id) else { return false }
        let others: [String] = spaces.filter { $0.id != id }.map(\.name)
        guard !others.contains(where: { SpaceNaming.same($0, trimmed) }) else { return false }
        spaces[target].name = trimmed
        return true
    }

    /// Never deletes the last Space. Deleting the active one activates its right-hand neighbour, or the left one when
    /// it was last in the list.
    @discardableResult
    mutating func delete(_ id: UUID) -> Bool {
        guard spaces.count > 1, let target: Int = index(of: id) else { return false }
        let wasActive: Bool = index(of: activeID) == target
        spaces.remove(at: target)
        if wasActive || index(of: activeID) == nil {
            let neighbour: Int = min(target, spaces.count - 1)
            activeID = spaces[neighbour].id
        }
        return true
    }

    // MARK: - Activation

    @discardableResult
    mutating func activate(_ id: UUID) -> Bool {
        guard index(of: id) != nil else { return false }
        activeID = id
        return true
    }

    /// Wraps from the last Space to the first.
    mutating func activateNext() {
        step(by: 1)
    }

    /// Wraps from the first Space to the last.
    mutating func activatePrevious() {
        step(by: -1)
    }

    private mutating func step(by delta: Int) {
        guard let current: Int = activeIndex else { return }
        let count: Int = spaces.count
        let next: Int = ((current + delta) % count + count) % count
        activeID = spaces[next].id
    }

    // MARK: - Order

    /// Moves the Space at `from` so it ends up at index `to` (clamped into the list). An out-of-range `from` is a no-op.
    mutating func move(from source: Int, to destination: Int) {
        guard spaces.indices.contains(source) else { return }
        let clamped: Int = max(0, min(destination, spaces.count - 1))
        guard clamped != source else { return }
        let space: Space = spaces.remove(at: source)
        spaces.insert(space, at: clamped)
    }

    // MARK: - Active Space content

    mutating func updateActiveSidebar(_ transform: (inout SidebarLayout) -> Void) {
        guard let current: Int = activeIndex else { return }
        transform(&spaces[current].sidebar)
    }

    /// Adds the Live Group to the active Space, or removes it when already shown.
    mutating func toggleLiveGroup(_ ref: LiveGroupRef) {
        guard let current: Int = activeIndex else { return }
        if let existing: Int = spaces[current].liveGroups.firstIndex(of: ref) {
            spaces[current].liveGroups.remove(at: existing)
        } else {
            spaces[current].liveGroups.append(ref)
        }
    }

    /// Edits are scoped to the editor's captured Space, not whichever Space is active on save.
    @discardableResult
    mutating func saveFolderLiveGroup(_ group: FolderLiveGroup, in spaceID: UUID) -> Bool {
        guard let target = index(of: spaceID), let valid = group.normalized else { return false }
        if let existing = spaces[target].folderLiveGroups.firstIndex(where: { $0.id == valid.id }) {
            spaces[target].folderLiveGroups[existing] = valid
        } else {
            spaces[target].folderLiveGroups.append(valid)
        }
        return true
    }

    @discardableResult
    mutating func removeFolderLiveGroup(_ id: UUID, from spaceID: UUID) -> Bool {
        guard let target = index(of: spaceID),
              let existing = spaces[target].folderLiveGroups.firstIndex(where: { $0.id == id }) else { return false }
        spaces[target].folderLiveGroups.remove(at: existing)
        return true
    }

    // MARK: - Persistence

    func encoded() -> Data {
        var store: SpaceStore = self
        store.schemaVersion = Self.currentSchemaVersion
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(store)) ?? Data()
    }

    /// Tolerant decode: unknown fields are ignored, a damaged Space element is dropped on its own, and each sidebar goes
    /// through `SidebarLayout.decode` (which itself keeps whatever still parses). Missing/unreadable data or zero
    /// readable Spaces ⇒ `migrated(from: fallbackLayout)`; an orphan or missing `activeID` ⇒ the first Space.
    static func decode(_ data: Data?, fallbackLayout: SidebarLayout) -> SpaceStore {
        guard let data, !data.isEmpty,
              let object: [String: Any] = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return migrated(from: fallbackLayout) }

        let spaces: [Space] = SpaceDecoder.spaces(object["spaces"])
        guard let first: Space = spaces.first else { return migrated(from: fallbackLayout) }

        let storedActive: UUID? = (object["activeID"] as? String).flatMap(UUID.init(uuidString:))
        let activeID: UUID = storedActive.flatMap { id in spaces.contains { $0.id == id } ? id : nil } ?? first.id
        return SpaceStore(schemaVersion: currentSchemaVersion, spaces: spaces, activeID: activeID)
    }
}

// MARK: - Helpers (private to this file)

/// Name normalisation shared by `add` and `rename`.
private enum SpaceNaming {
    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trimmed, NFC-normalised, case-folded equality — "Dự án" typed as NFD equals the NFC one already stored.
    static func same(_ lhs: String, _ rhs: String) -> Bool {
        key(lhs) == key(rhs)
    }

    static func uniqueName(base: String, taken: [String]) -> String {
        let takenKeys: Set<String> = Set(taken.map(key))
        guard takenKeys.contains(key(base)) else { return base }
        var suffix: Int = 2
        while takenKeys.contains(key("\(base) \(suffix)")) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private static func key(_ name: String) -> String {
        trimmed(name).precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// Copies a sidebar giving every item and group a new UUID, through the layout's own tolerant decoder (which assigns
/// a fresh UUID to any entry without an `id`) — so the copy keeps paths, display names, defaults, hidden volumes and
/// tag order without reaching into `SidebarLayout`'s private initializer.
private enum SidebarCloner {
    static func cloneWithFreshIDs(_ layout: SidebarLayout) -> SidebarLayout {
        guard var object: [String: Any] = (try? JSONSerialization.jsonObject(with: layout.encoded())) as? [String: Any]
        else { return SidebarLayout() }
        object["favorites"] = strippedItems(object["favorites"])
        if let groups: [Any] = object["groups"] as? [Any] {
            object["groups"] = groups.map { entry -> Any in
                guard var group: [String: Any] = entry as? [String: Any] else { return entry }
                group.removeValue(forKey: "id")
                group["items"] = strippedItems(group["items"])
                return group
            }
        }
        guard let data: Data = try? JSONSerialization.data(withJSONObject: object) else { return SidebarLayout() }
        return SidebarLayout.decode(data)
    }

    private static func strippedItems(_ raw: Any?) -> Any {
        guard let items: [Any] = raw as? [Any] else { return [Any]() }
        return items.map { entry -> Any in
            guard var item: [String: Any] = entry as? [String: Any] else { return entry }
            item.removeValue(forKey: "id")
            return item
        }
    }
}

/// Element-by-element decoding of the `spaces` array.
private enum SpaceDecoder {
    /// Drops damaged elements and later duplicates of an id already read.
    static func spaces(_ raw: Any?) -> [Space] {
        guard let array: [Any] = raw as? [Any] else { return [] }
        var seen: Set<UUID> = []
        var result: [Space] = []
        for entry: Any in array {
            guard let space: Space = space(entry), !seen.contains(space.id) else { continue }
            seen.insert(space.id)
            result.append(space)
        }
        return result
    }

    /// A Space is damaged (nil) only when its id is not a UUID string or its name is not a string. A missing or
    /// unreadable sidebar resets to a fresh default one (the name, Live Groups and workspaces survive); a blank name
    /// reads as `defaultNewSpaceName`.
    private static func space(_ raw: Any) -> Space? {
        guard let dict: [String: Any] = raw as? [String: Any],
              let id: UUID = (dict["id"] as? String).flatMap(UUID.init(uuidString:)),
              let rawName: String = dict["name"] as? String
        else { return nil }
        let trimmed: String = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String = trimmed.isEmpty ? SpaceStore.defaultNewSpaceName : trimmed
        let sidebar: SidebarLayout = sidebar(dict["sidebar"]) ?? SidebarLayout()
        return Space(id: id, name: name, symbol: dict["symbol"] as? String, sidebar: sidebar,
                     liveGroups: liveGroups(dict["liveGroups"]), workspaceIDs: uuids(dict["workspaceIDs"]),
                     folderLiveGroups: folderLiveGroups(dict["folderLiveGroups"]))
    }

    private static func sidebar(_ raw: Any?) -> SidebarLayout? {
        guard let raw, !(raw is NSNull) else { return SidebarLayout() }
        guard let dict: [String: Any] = raw as? [String: Any],
              let data: Data = try? JSONSerialization.data(withJSONObject: dict)
        else { return nil }
        return SidebarLayout.decode(data)
    }

    private static func liveGroups(_ raw: Any?) -> [LiveGroupRef] {
        guard let array: [Any] = raw as? [Any] else { return [] }
        var result: [LiveGroupRef] = []
        for entry: Any in array {
            guard let dict: [String: Any] = entry as? [String: Any],
                  let propertyID: UUID = (dict["propertyID"] as? String).flatMap(UUID.init(uuidString:)),
                  let optionID: UUID = (dict["optionID"] as? String).flatMap(UUID.init(uuidString:))
            else { continue }
            let ref: LiveGroupRef = LiveGroupRef(propertyID: propertyID, optionID: optionID)
            if !result.contains(ref) { result.append(ref) }
        }
        return result
    }

    private static func folderLiveGroups(_ raw: Any?) -> [FolderLiveGroup] {
        guard let array = raw as? [Any] else { return [] }
        var seen: Set<UUID> = []
        return array.compactMap { entry in
            guard JSONSerialization.isValidJSONObject(entry),
                  let data = try? JSONSerialization.data(withJSONObject: entry),
                  let group = try? JSONDecoder().decode(FolderLiveGroup.self, from: data),
                  seen.insert(group.id).inserted else { return nil }
            return group
        }
    }

    private static func uuids(_ raw: Any?) -> [UUID] {
        guard let array: [Any] = raw as? [Any] else { return [] }
        return array.compactMap { ($0 as? String).flatMap(UUID.init(uuidString:)) }
    }
}
