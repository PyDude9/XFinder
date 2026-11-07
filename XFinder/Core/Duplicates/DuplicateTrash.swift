import Foundation

struct DuplicateTrashOutcome: Sendable {
    var moved: [String] = []
    var failed: [String] = []
    var skipped: [String] = []
    var cancelled = false
}
struct DuplicatePreparation: Sendable {
    var moves: [DuplicateMove] = []
    var rejected = 0
    var rejectedPaths: [String] = []
    var cancelled = false
}

/// The sole destructive boundary for this task. No permanent-delete fallback.
enum DuplicateTrash {
    static func prepare(_ plan: [DuplicateMove]) async -> DuplicatePreparation {
        let worker = Task.detached(priority: .utility) {
            var result = DuplicatePreparation()
            let groups = Dictionary(grouping: plan, by: { $0.keeper.id })
            for key in groups.keys.sorted() {
                let moves = groups[key]!
                var valid = true
                for move in moves {
                    if Task.isCancelled { result.cancelled = true; valid = false; break }
                    do { if try !DuplicateScanEngine.verify(move) { valid = false } }
                    catch { valid = false }
                }
                if valid { result.moves.append(contentsOf: moves) }
                else {
                    result.rejected += moves.count
                    result.rejectedPaths.append(contentsOf: moves.map { $0.file.id })
                }
                if result.cancelled { break }
            }
            if Task.isCancelled { result.cancelled = true }
            return result
        }
        return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }

    static func run(_ plan: [DuplicateMove], selected: Set<String>) async -> DuplicateTrashOutcome {
        let worker = Task.detached(priority: .utility) { execute(plan, selected: selected) }
        return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }

    /// Injection is for fixture tests: production always uses the synchronous system Trash operation.
    static func execute(_ plan: [DuplicateMove], selected: Set<String>,
                        cancelled: () -> Bool = { Task.isCancelled },
                        moveToTrash: (URL) throws -> Void = { url in
                            _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        }) -> DuplicateTrashOutcome {
        var outcome = DuplicateTrashOutcome()
        var handled = Set<String>()
        for move in plan {
            if cancelled() { outcome.cancelled = true; break }
            guard handled.insert(move.file.id).inserted else { continue }
            let authorized = selected.contains(move.file.id) && !selected.contains(move.keeper.id)
            guard DuplicateRules.mayMove(selected: authorized, cancelled: cancelled(), fingerprintsMatch: true,
                                         hasKeeper: move.file.fingerprint.identity != move.keeper.fingerprint.identity) else {
                outcome.skipped.append(move.file.id); continue
            }
            do {
                guard try DuplicateScanEngine.verify(move, cancelled: cancelled) else {
                    outcome.skipped.append(move.file.id); continue
                }
                // Recheck both paths immediately before each synchronous trashItem. A path-based API still has
                // a residual TOCTOU boundary; this is not an atomic batch or a hostile-filesystem guarantee.
                let unchanged = try DuplicateScanEngine.fingerprint(move.file.url) == move.file.fingerprint &&
                    DuplicateScanEngine.fingerprint(move.keeper.url) == move.keeper.fingerprint
                guard DuplicateRules.mayMove(selected: authorized, cancelled: cancelled(), fingerprintsMatch: unchanged,
                                             hasKeeper: !selected.contains(move.keeper.id)) else {
                    outcome.skipped.append(move.file.id); continue
                }
            } catch {
                if cancelled() { outcome.cancelled = true; break }
                outcome.skipped.append(move.file.id)
                continue
            }
            do {
                try moveToTrash(move.file.url)
                outcome.moved.append(move.file.id)
            } catch {
                outcome.failed.append(move.file.id)
            }
        }
        return outcome
    }
}
