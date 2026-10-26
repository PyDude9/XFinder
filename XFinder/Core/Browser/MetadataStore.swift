import Foundation
import SQLite3

/// XF-T32 W1 — stub (builder `store`): the sidecar SQLite for properties, pins, nicknames, emoji, relations. Contract §C.
actor MetadataStore {
    static let shared = MetadataStore(databaseURL: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XFinder/Browser/metadata.sqlite"))
    private let databaseURL: URL

    init(databaseURL: URL) { self.databaseURL = databaseURL }

    func catalog() -> PropertyCatalog { PropertyCatalog() }
    func saveCatalog(_ catalog: PropertyCatalog) {}
    func selections(property: UUID) -> [String: UUID] { [:] }
    func selections(in folder: String) -> [UUID: [String: UUID]] { [:] }
    func allSelections() -> [UUID: [String: UUID]] { [:] }
    func select(path: String, property: UUID, option: UUID?) {}
    func folderProperties(_ folder: String) -> [(property: UUID, showInView: Bool)] { [] }
    func setFolderProperties(_ folder: String, _ list: [(property: UUID, showInView: Bool)]) {}
    func pins(in folder: String) -> [String] { [] }
    func setPins(_ pins: [String], in folder: String) {}
    func nickname(for path: String) -> String? { nil }
    func nicknames(in folder: String) -> [String: String] { [:] }
    func allNicknames() -> [String: String] { [:] }
    func setNickname(_ nickname: String?, for path: String) {}
    func emoji(for folder: String) -> String? { nil }
    func setEmoji(_ emoji: String?, for folder: String) {}
    func relations() -> [FolderRelation] { [] }
    func setRelations(_ relations: [FolderRelation]) {}
    func itemMoved(from: String, to: String) {}
    func itemRemoved(_ path: String) {}
    func changeToken() -> Int { 0 }
}
