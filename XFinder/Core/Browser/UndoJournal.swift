import Foundation

/// XF-T30 W6 — the browser's persistent Undo (FileOctopus: 20 steps / 24 h across quit, metadata only, revalidated
/// before replay, never partial). Pure, symlinked. Contract XF-T30-w6 §1. W6 builder (pure): implement.
struct UndoItem: Codable, Equatable, Sendable {
    var from: String
    var to: String
    var inode: UInt64?
    var size: Int64?
    var modified: Date?
}

struct UndoStep: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case move, copy, duplicate, trash, rename, newFolder, merge, compress, infoEdit }
    var id: UUID
    var kind: Kind
    var items: [UndoItem]
    var date: Date
    /// L10n key of the verb ("Hoàn tác Chuyển …").
    var titleKey: String { "" }
}

struct UndoJournal: Codable, Equatable, Sendable {
    static let limit = 20
    static let maxAge: TimeInterval = 24 * 3600
    private(set) var undo: [UndoStep] = []
    private(set) var redo: [UndoStep] = []

    enum Availability: Equatable, Sendable { case available, diskMissing, unavailable(reasonKey: String) }

    mutating func record(_ step: UndoStep, now: Date) {}
    func availability(of step: UndoStep, exists: (String) -> Bool, identity: (String) -> (inode: UInt64, size: Int64, modified: Date)?,
                      volumeMounted: (String) -> Bool) -> Availability { .unavailable(reasonKey: "") }
    mutating func popUndo() -> UndoStep? { nil }
    mutating func popRedo() -> UndoStep? { nil }
    mutating func pruned(now: Date) {}
    func encoded() -> Data { Data() }
    static func decode(_ data: Data?) -> UndoJournal { UndoJournal() }
}
