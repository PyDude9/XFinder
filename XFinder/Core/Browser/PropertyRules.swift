import Foundation

/// XF-T32 W1 — grouping a listing by a property (Tilde "Group by Status") and Live Groups (every item set to one
/// option, anywhere on disk). Contract docs/specs/XF-T32-w1-contract.md §A. Pure: callers pass the selections read
/// from `MetadataStore`; nothing here reads the disk or produces display strings.
enum PropertyRules {
    /// L10n key of the trailing section holding entries with no (or an orphaned) selection.
    static let unsetTitleKey: String = "Chưa đặt"

    struct Section: Equatable, Sendable {
        let option: PropertyOption?
        let entries: [DirectoryEntry]
    }

    struct LiveGroup: Equatable, Sendable {
        let property: PropertyDefinition
        let option: PropertyOption
        let paths: [String]
    }

    /// One section per option in the property's option order, empty sections dropped, the unset section (option nil)
    /// last and only when non-empty. Entries keep their incoming order inside each section. A selection naming an option
    /// the property no longer has counts as unset. O(entries + options).
    static func sections(_ entries: [DirectoryEntry], property: PropertyDefinition, selections: [String: UUID]) -> [Section] {
        guard !entries.isEmpty else { return [] }
        let slotByOption: [UUID: Int] = optionSlots(property)
        let optionCount: Int = property.options.count
        var buckets: [[DirectoryEntry]] = Array(repeating: [], count: optionCount + 1)   // last bucket = unset
        for entry in entries {
            let slot: Int = selections[entry.path].flatMap { slotByOption[$0] } ?? optionCount
            buckets[slot].append(entry)
        }
        var result: [Section] = []
        result.reserveCapacity(optionCount + 1)
        for slot in 0..<optionCount where !buckets[slot].isEmpty {
            result.append(Section(option: property.options[slot], entries: buckets[slot]))
        }
        if !buckets[optionCount].isEmpty {
            result.append(Section(option: nil, entries: buckets[optionCount]))
        }
        return result
    }

    /// The option `path` is set to, or nil when unset or the stored option was deleted (orphan).
    static func option(for path: String, property: PropertyDefinition, selections: [String: UUID]) -> PropertyOption? {
        guard let optionID: UUID = selections[path] else { return nil }
        return property.options.first { $0.id == optionID }
    }

    /// One group per `wanted` ref still pointing at an existing property + option (stale refs dropped, repeated refs
    /// once, in `wanted` order). Paths are every item set to that option, sorted by display name (nickname when set,
    /// else the last path component) with the same folded natural order the browser's name sort uses; ties by path.
    static func liveGroups(catalog: PropertyCatalog, selections: [UUID: [String: UUID]], nicknames: [String: String],
                           wanted: [LiveGroupRef]) -> [LiveGroup] {
        var seen: Set<LiveGroupRef> = []
        var groups: [LiveGroup] = []
        for ref in wanted where seen.insert(ref).inserted {
            guard let property: PropertyDefinition = catalog.definition(ref.propertyID),
                  let option: PropertyOption = property.options.first(where: { $0.id == ref.optionID }) else { continue }
            let byPath: [String: UUID] = selections[ref.propertyID] ?? [:]
            let members: [String] = byPath.compactMap { (path: String, optionID: UUID) -> String? in
                optionID == ref.optionID ? path : nil
            }
            groups.append(LiveGroup(property: property, option: option, paths: sortedByDisplayName(members, nicknames: nicknames)))
        }
        return groups
    }

    // MARK: - Private

    /// Option id ⇒ its index; if a damaged catalog repeats an id, the first occurrence wins.
    private static func optionSlots(_ property: PropertyDefinition) -> [UUID: Int] {
        var slots: [UUID: Int] = [:]
        slots.reserveCapacity(property.options.count)
        for (index, option) in property.options.enumerated() where slots[option.id] == nil {
            slots[option.id] = index
        }
        return slots
    }

    private static func sortedByDisplayName(_ paths: [String], nicknames: [String: String]) -> [String] {
        let keyed: [(path: String, key: [UInt8])] = paths.map { (path: String) -> (path: String, key: [UInt8]) in
            (path: path, key: displayKey(path, nicknames: nicknames))
        }
        return keyed.sorted { (a: (path: String, key: [UInt8]), b: (path: String, key: [UInt8])) -> Bool in
            let c: Int = EntryRules.naturalCompare(a.key, b.key)
            return c != 0 ? c < 0 : a.path < b.path
        }.map(\.path)
    }

    /// Folded sort key of the shown name: NFC first so NFD names (HFS+, pasted text) sort with their NFC twins.
    private static func displayKey(_ path: String, nicknames: [String: String]) -> [UInt8] {
        let nickname: String = (nicknames[path] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shown: String = nickname.isEmpty ? (path as NSString).lastPathComponent : nickname
        return EntryRules.foldBytes(shown.precomposedStringWithCanonicalMapping)
    }
}
