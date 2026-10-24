import Foundation
import Observation

/// XF-T28 cluster B — STUB (contract: docs/specs/XF-T28-ui-contract.md).
struct ConflictPrompt: Identifiable, Equatable {
    struct Side: Equatable { let path: String; let size: Int64; let modified: Date; let isFolder: Bool; let isNewer: Bool }
    let id: UUID
    let jobID: UUID
    let source: Side
    let destination: Side
    let replaceAllowed: Bool
    let remaining: Int
}

@MainActor @Observable final class FileOperationQueue {
    static let shared = FileOperationQueue()
    private(set) var queue = FileJobQueue()
    private(set) var pendingConflict: ConflictPrompt?
    private(set) var speed: Double?
    private(set) var eta: TimeInterval?
    private(set) var recovery: [RecoveryItem] = []
    private(set) var lastErrorKey: String?
    var hasActiveWork: Bool { queue.active != nil }

    @discardableResult func enqueue(_ kind: FileOperationKind, sources: [String], destination: String?) -> UUID? { nil }
    func pause(_ id: UUID) {}
    func resume(_ id: UUID) {}
    func cancel(_ id: UUID) {}
    func pauseAll() {}
    func resumeAll() {}
    func runNext(_ id: UUID) {}
    func moveUp(_ id: UUID) {}
    func moveDown(_ id: UUID) {}
    func clearFinished() {}
    func resolveConflict(_ choice: ConflictChoice, applyToAll: Bool) {}
    func loadRecovery() {}
    func clearRecovery() {}
    func undoLast() -> String? { nil }
}
