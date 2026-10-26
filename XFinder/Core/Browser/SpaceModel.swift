import Foundation

/// XF-T32 W1 — stub (builder `spaces`): Spaces = one sidebar per context + its Live Groups. Contract §D.
struct Space: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var symbol: String?
    var sidebar: SidebarLayout
    var liveGroups: [LiveGroupRef]
    var workspaceIDs: [UUID]
}

struct SpaceStore: Codable, Equatable, Sendable {
    static let currentSchemaVersion: Int = 1
    var schemaVersion: Int
    var spaces: [Space]
    var activeID: UUID

    static func migrated(from layout: SidebarLayout) -> SpaceStore {
        let space = Space(id: UUID(), name: "Cá nhân", symbol: nil, sidebar: layout, liveGroups: [], workspaceIDs: [])
        return SpaceStore(schemaVersion: currentSchemaVersion, spaces: [space], activeID: space.id)
    }

    var active: Space { spaces.first { $0.id == activeID } ?? spaces[0] }

    mutating func add(name: String, cloningSidebarFrom: UUID?) -> Space { active }
    mutating func rename(_ id: UUID, to name: String) -> Bool { false }
    mutating func delete(_ id: UUID) -> Bool { false }
    mutating func activate(_ id: UUID) -> Bool { false }
    mutating func activateNext() {}
    mutating func activatePrevious() {}
    mutating func move(from: Int, to: Int) {}
    mutating func updateActiveSidebar(_ transform: (inout SidebarLayout) -> Void) {}
    mutating func toggleLiveGroup(_ ref: LiveGroupRef) {}
    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data?, fallbackLayout: SidebarLayout) -> SpaceStore { migrated(from: fallbackLayout) }
}
