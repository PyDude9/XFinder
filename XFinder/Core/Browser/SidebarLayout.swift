import Foundation

/// XF-T28 Wave 4 §B — the Browser sidebar's own layout: which folders are pinned, which custom groups the person made,
/// and which volumes they hid. Pure and symlinked (`Tests/XFinderLogicTests/SidebarLayoutTests.swift`); `BrowserSettings`
/// is the ONE reader/writer of the `fileBrowser.sidebarLayout` key that stores this as JSON.
///
/// `schemaVersion` is written from day one (FileOctopus pitfall, read from their changelog: a user who reverted to an
/// older build after trying a newer one lost every sidebar customization, because the old build's decoder choked on
/// the whole blob and fell back to a blank layout instead of keeping what it could read). `decode(_:)` here never does
/// that: a damaged or future-shaped item is dropped on its own, everything else survives, and fields from a newer
/// schema are ignored rather than rejecting the document.
///
/// Schema 2 (XF-T30 W3) adds two fields on top of schema 1's shape, both optional on the wire so a schema-1 document
/// (no `isDefault`, no `userTagOrder`) still decodes in full: `Item.isDefault` marks the five favourites a fresh
/// layout ships with, so "Đặt lại" (Reset) can restore exactly those entries, in that order, without guessing which
/// of the person's current favourites were ever the shipped ones; `userTagOrder` is the order the person dragged
/// Finder tags into inside the sidebar (tag identity/colour themselves live in Finder's own tag store, read by
/// `TagLibrary` — this layout only remembers a user-chosen order by tag name). A schema-1 document decodes with
/// `isDefault = false` on every item (safe: "Đặt lại" simply has nothing of its own to restore for that person until
/// they get a schema-2 write) and an empty `userTagOrder` (Finder's own order is the fallback — see `SidebarSections`).
struct SidebarLayout: Codable, Equatable, Sendable {
    /// Bumped only when a change would make an old reader's fields mean something else; a newer minor addition should
    /// arrive as an optional field instead, so an older binary (lower `knownSchemaVersion`) still reads it.
    static let currentSchemaVersion = 2

    /// A path pinned in Mục ưa thích or inside a custom group.
    struct Item: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var path: String
        /// nil = show the folder's own name; set by "Đổi tên…", cleared by "Đặt lại tên".
        var displayName: String?
        /// Schema 2: this item is one of the five favourites a fresh layout ships with (AirDrop, Desktop,
        /// Applications, Documents, Downloads), so "Đặt lại" knows to restore it. A custom group item is never
        /// default. Decoding a schema-1 document (field absent) reads as `false`.
        var isDefault: Bool

        init(id: UUID = UUID(), path: String, displayName: String? = nil, isDefault: Bool = false) {
            self.id = id
            self.path = path
            self.displayName = displayName
            self.isDefault = isDefault
        }
    }

    /// A user-made group under Mục ưa thích (e.g. "Dự án"). The built-in Mục ưa thích list is not a `Group` — it is
    /// `favorites` below — so deleting a custom group can never touch it.
    struct Group: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        var items: [Item]

        init(id: UUID = UUID(), name: String, items: [Item] = []) {
            self.id = id
            self.name = name
            self.items = items
        }
    }

    private(set) var schemaVersion: Int
    private(set) var favorites: [Item]
    private(set) var groups: [Group]
    /// Volume UUIDs (not mount paths — a path is only valid while the volume is mounted) the person hid from Vị trí.
    private(set) var hiddenVolumeUUIDs: Set<String>
    /// Schema 2: tag names in the order the person last dragged them into the sidebar. A name with no match in
    /// `TagLibrary.tags` (tag renamed/deleted in Finder) is simply skipped by `SidebarSections`, never an error.
    /// Empty means "no custom order yet" — Finder's own order is used.
    private(set) var userTagOrder: [String]

    /// A fresh layout: the same five defaults Finder ships with, in the same order (all marked `isDefault` so "Đặt
    /// lại" can restore exactly this set), no custom groups, nothing hidden, no tag reorder yet.
    init() {
        let home = NSHomeDirectory()
        self.schemaVersion = Self.currentSchemaVersion
        self.favorites = Self.defaultFavorites(home: home)
        self.groups = []
        self.hiddenVolumeUUIDs = []
        self.userTagOrder = []
    }

    private static func defaultFavorites(home: String) -> [Item] {
        [
            Item(path: home, isDefault: true),
            Item(path: home + "/Desktop", isDefault: true),
            Item(path: home + "/Documents", isDefault: true),
            Item(path: home + "/Downloads", isDefault: true),
            Item(path: "/Applications", isDefault: true),
        ]
    }

    private init(schemaVersion: Int, favorites: [Item], groups: [Group], hiddenVolumeUUIDs: Set<String>,
                 userTagOrder: [String]) {
        self.schemaVersion = schemaVersion
        self.favorites = favorites
        self.groups = groups
        self.hiddenVolumeUUIDs = hiddenVolumeUUIDs
        self.userTagOrder = userTagOrder
    }

    // MARK: - Groups

    /// Group names are compared trimmed and case-insensitively so "Dự án" and "dự án " are the same group to a person
    /// typing into a text field. Empty or already-taken names are refused (nothing changes, caller shows no new group).
    @discardableResult
    mutating func addGroup(named name: String) -> Group? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groups.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return nil }
        let group = Group(name: trimmed)
        groups.append(group)
        return group
    }

    @discardableResult
    mutating func renameGroup(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }),
              !groups.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return false }
        groups[index].name = trimmed
        return true
    }

    /// Deleting a group never deletes its folders: every item moves back to Mục ưa thích, then duplicates (same path
    /// already pinned) are dropped so the same folder never appears twice in the list it lands in.
    mutating func deleteGroup(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let returning = groups.remove(at: index).items
        var seenPaths = Set(favorites.map(\.path))
        for item in returning where !seenPaths.contains(item.path) {
            favorites.append(item)
            seenPaths.insert(item.path)
        }
    }

    // MARK: - Items

    /// Adds `path` to a group (nil = Mục ưa thích); a path already present anywhere in that same list is not duplicated.
    mutating func addItem(path: String, toGroup groupID: UUID?) {
        guard !path.isEmpty else { return }
        if let groupID {
            guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
            guard !groups[index].items.contains(where: { $0.path == path }) else { return }
            groups[index].items.append(Item(path: path))
        } else {
            guard !favorites.contains(where: { $0.path == path }) else { return }
            favorites.append(Item(path: path))
        }
    }

    /// Removes an item from Mục ưa thích or any custom group, wherever its id is found.
    mutating func removeItem(_ id: UUID) {
        favorites.removeAll { $0.id == id }
        for index in groups.indices { groups[index].items.removeAll { $0.id == id } }
    }

    /// Moves an item between lists (nil = Mục ưa thích), to `index` (clamped) in the destination, preserving it
    /// otherwise — this is also how a same-list reorder happens (source list == destination list).
    mutating func moveItem(_ id: UUID, toGroup destinationGroupID: UUID?, index destinationIndex: Int) {
        guard let item = takeItem(id) else { return }
        if let destinationGroupID {
            guard let groupIndex = groups.firstIndex(where: { $0.id == destinationGroupID }) else {
                // The destination group vanished between the drag starting and ending; do not drop the item on the floor.
                favorites.append(item)
                return
            }
            let clamped = max(0, min(destinationIndex, groups[groupIndex].items.count))
            groups[groupIndex].items.insert(item, at: clamped)
        } else {
            let clamped = max(0, min(destinationIndex, favorites.count))
            favorites.insert(item, at: clamped)
        }
    }

    private mutating func takeItem(_ id: UUID) -> Item? {
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            return favorites.remove(at: index)
        }
        for groupIndex in groups.indices {
            if let itemIndex = groups[groupIndex].items.firstIndex(where: { $0.id == id }) {
                return groups[groupIndex].items.remove(at: itemIndex)
            }
        }
        return nil
    }

    /// "Đổi tên…": the displayed name only — `BrowserSidebarView` never touches the real folder (CLAUDE.md: renaming a
    /// sidebar item is never a file-system rename). An empty name is treated as "Đặt lại tên" (nil) rather than stored.
    mutating func setDisplayName(_ id: UUID, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            favorites[index].displayName = resolved
            return
        }
        for groupIndex in groups.indices {
            if let itemIndex = groups[groupIndex].items.firstIndex(where: { $0.id == id }) {
                groups[groupIndex].items[itemIndex].displayName = resolved
                return
            }
        }
    }

    /// "Đặt lại tên": back to the folder's own name.
    mutating func resetDisplayName(_ id: UUID) {
        setDisplayName(id, to: nil)
    }

    // MARK: - Reset (schema 2)

    /// "Đặt lại" on Mục ưa thích: restores exactly the five shipped defaults, in their shipped order — using
    /// `isDefault` rather than re-running `init()` blind, so a person who pinned a *sixth* folder next to the
    /// defaults and only wants the defaults back gets a clean, predictable result (every current favourite is
    /// dropped, custom groups are untouched: "Đặt lại" is scoped to Mục ưa thích only).
    mutating func resetFavoritesToDefault() {
        favorites = Self.defaultFavorites(home: NSHomeDirectory())
    }

    // MARK: - Tag order (schema 2)

    /// Moves `name` to `index` (clamped) in the user's tag order, inserting it if not already present — this is also
    /// how a drag-to-reorder of an already-ordered tag happens (remove then reinsert at the new index).
    mutating func moveTag(_ name: String, toIndex index: Int) {
        guard !name.isEmpty else { return }
        userTagOrder.removeAll { $0 == name }
        let clamped = max(0, min(index, userTagOrder.count))
        userTagOrder.insert(name, at: clamped)
    }

    /// Drops a tag from the remembered order (e.g. the tag itself was deleted in Finder) — harmless to call for a
    /// name that was never ordered.
    mutating func forgetTagOrder(_ name: String) {
        userTagOrder.removeAll { $0 == name }
    }

    /// Orders `tagNames` (Finder's current tag names) by the user's remembered order, with any name the user never
    /// touched — a brand-new Finder tag, or the first run before any reorder — appended afterwards in the order
    /// `tagNames` already arrived in (Finder's own order, per `SidebarSections` contract). A remembered name with no
    /// match in `tagNames` (renamed or deleted in Finder) is dropped rather than conjuring a row for it.
    func orderedTags(_ tagNames: [String]) -> [String] {
        guard !userTagOrder.isEmpty else { return tagNames }
        let known = Set(tagNames)
        let ordered = userTagOrder.filter { known.contains($0) }
        let orderedSet = Set(ordered)
        let rest = tagNames.filter { !orderedSet.contains($0) }
        return ordered + rest
    }

    // MARK: - Hidden volumes

    /// Keyed by volume UUID, not mount path, so hiding a drive survives an eject-and-remount (a new mount path, same
    /// UUID) — spec XF-T28 Wave 4 §B.
    mutating func hideVolume(uuid: String) {
        guard !uuid.isEmpty else { return }
        hiddenVolumeUUIDs.insert(uuid)
    }

    mutating func showVolume(uuid: String) {
        hiddenVolumeUUIDs.remove(uuid)
    }

    func isVolumeHidden(uuid: String) -> Bool {
        hiddenVolumeUUIDs.contains(uuid)
    }

    // MARK: - Tolerant decode

    /// Decodes a stored layout, keeping every part that still parses: a damaged or unknown-shaped group or item is
    /// dropped on its own rather than failing the whole document, and fields only a newer build understands are
    /// ignored (plain `Codable` already does that for unknown keys) rather than refused. Empty/missing data starts a
    /// fresh default layout — never an empty one, so Mục ưa thích is never blank just because nothing was saved yet.
    static func decode(_ data: Data?) -> SidebarLayout {
        guard let data, !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return SidebarLayout() }

        let schemaVersion = (object["schemaVersion"] as? Int) ?? currentSchemaVersion
        let favorites = decodeItems(object["favorites"])
        let groups = decodeGroups(object["groups"])
        let hiddenVolumeUUIDs = Set((object["hiddenVolumeUUIDs"] as? [Any])?.compactMap { $0 as? String } ?? [])
        // Schema 1 never wrote this key — absent reads as "no custom order yet" (Finder's own order is used).
        let userTagOrder = (object["userTagOrder"] as? [Any])?.compactMap { $0 as? String } ?? []

        // A document with no readable favorites at all (not merely "the person removed every one of them", which
        // would also read back as an empty *array*, not a missing/unparsable key) falls back to the shipped defaults
        // rather than presenting an unexplained blank Mục ưa thích.
        if object["favorites"] == nil {
            return SidebarLayout(schemaVersion: schemaVersion, favorites: SidebarLayout().favorites,
                                 groups: groups, hiddenVolumeUUIDs: hiddenVolumeUUIDs, userTagOrder: userTagOrder)
        }
        return SidebarLayout(schemaVersion: schemaVersion, favorites: favorites, groups: groups,
                             hiddenVolumeUUIDs: hiddenVolumeUUIDs, userTagOrder: userTagOrder)
    }

    private static func decodeItems(_ raw: Any?) -> [Item] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap { entry -> Item? in
            guard let dict = entry as? [String: Any], let path = dict["path"] as? String, !path.isEmpty else { return nil }
            let id = (dict["id"] as? String).flatMap(UUID.init) ?? UUID()
            let displayName = dict["displayName"] as? String
            // Schema 1 never wrote this key — absent reads as `false` (not one of today's shipped defaults).
            let isDefault = (dict["isDefault"] as? Bool) ?? false
            return Item(id: id, path: path, displayName: displayName, isDefault: isDefault)
        }
    }

    private static func decodeGroups(_ raw: Any?) -> [Group] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap { entry -> Group? in
            guard let dict = entry as? [String: Any], let name = dict["name"] as? String, !name.isEmpty else { return nil }
            let id = (dict["id"] as? String).flatMap(UUID.init) ?? UUID()
            return Group(id: id, name: name, items: decodeItems(dict["items"]))
        }
    }

    func encoded() -> Data {
        var layout = self
        layout.schemaVersion = Self.currentSchemaVersion
        return (try? JSONEncoder().encode(layout)) ?? Data()
    }
}
