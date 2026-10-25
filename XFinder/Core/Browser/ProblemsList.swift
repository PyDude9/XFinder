import Foundation

/// XF-T30 W6 — the session's Problems list (FileOctopus): one row per failed operation with each failed item and a
/// canonical reason; Retry only for pre-write, plausibly transient failures. Pure, symlinked. W6 builder (pure).
enum ProblemReason: String, Codable, CaseIterable, Sendable {
    case permissionDenied, diskFull, fileInUse, disconnected, readWriteError, timeout, readOnlyVolume, nameTooLong, itemGone, other

    /// L10n key.
    var titleKey: String { "" }
    /// From a POSIX / Cocoa error. W6 builder (pure): implement.
    static func from(posix code: Int32) -> ProblemReason { .other }
}

struct ProblemItem: Equatable, Sendable {
    var path: String
    var reason: ProblemReason
    var systemMessage: String?
    var beforeWrite: Bool
}

struct ProblemEntry: Equatable, Identifiable, Sendable {
    var id: UUID
    var operationTitleKey: String
    var finished: Date
    var items: [ProblemItem]
    var canRetry: Bool { false }
}

struct ProblemsList: Equatable, Sendable {
    private(set) var entries: [ProblemEntry] = []
    mutating func add(_ entry: ProblemEntry) {}
    mutating func dismiss(_ id: UUID) {}
    mutating func clearAll() { entries = [] }
}
