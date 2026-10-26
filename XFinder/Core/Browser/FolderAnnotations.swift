import Foundation

/// XF-T32 W1 — stub (builder `pins`): pins, nicknames, emoji, path rewrites, folder relations. Contract §B.
enum PinRules {
    static let maxPinsPerFolder: Int = 50
    static func split(_ entries: [DirectoryEntry], folder: String, pins: [String])
        -> (pinned: [DirectoryEntry], rest: [DirectoryEntry], stale: [String], pinsFolderItself: Bool) {
        ([], entries, [], false)
    }
    static func toggled(_ pins: [String], path: String) -> [String] { pins }
    static func moved(_ pins: [String], from: Int, to: Int) -> [String] { pins }
}

enum NicknameRules {
    static let maxLength: Int = 60
    static func normalized(_ raw: String) -> String? { nil }
    static func searchKey(name: String, nickname: String?) -> [UInt8] { EntryRules.foldBytes(name) }
}

enum EmojiRules {
    static func normalized(_ raw: String) -> String? { nil }
}

enum PathRewrite {
    static func rewritten(_ path: String, from: String, to: String) -> String? { nil }
}

struct FolderRelation: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var a: String
    var b: String
}

enum RelationRules {
    static func adding(_ relations: [FolderRelation], a: String, b: String) -> [FolderRelation] { relations }
    static func related(to folder: String, in relations: [FolderRelation]) -> [String] { [] }
}
