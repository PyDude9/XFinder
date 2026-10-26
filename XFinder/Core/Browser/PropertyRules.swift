import Foundation

/// XF-T32 W1 — stub (builder `properties`): grouping by a property and Live Groups. Contract §A.
enum PropertyRules {
    struct Section: Equatable, Sendable {
        let option: PropertyOption?
        let entries: [DirectoryEntry]
    }

    struct LiveGroup: Equatable, Sendable {
        let property: PropertyDefinition
        let option: PropertyOption
        let paths: [String]
    }

    static func sections(_ entries: [DirectoryEntry], property: PropertyDefinition, selections: [String: UUID]) -> [Section] {
        [Section(option: nil, entries: entries)]
    }

    static func option(for path: String, property: PropertyDefinition, selections: [String: UUID]) -> PropertyOption? { nil }

    static func liveGroups(catalog: PropertyCatalog, selections: [UUID: [String: UUID]], nicknames: [String: String],
                           wanted: [LiveGroupRef]) -> [LiveGroup] { [] }
}
