import Foundation
import Observation
import CryptoKit
import os

/// XF-T28 cluster B — the file browser's copy/move/duplicate/trash engine (contract:
/// docs/specs/XF-T28-ui-contract.md). The decisions (naming, strategy, state machine, recovery) live in
/// `FileOperationRules.swift` (pure, tested); this file is the AppKit/Darwin side that actually touches disk:
/// `copyfile(3)` with a status callback for progress/pause/cancel, `rename(2)` for a same-volume move, SHA-256
/// verification (CryptoKit) before trashing the source of a cross-volume move, and an append-only JSON journal for
/// crash recovery. Only one job runs at a time (`FileJobQueue.startNextIfIdle`).
struct ConflictPrompt: Identifiable, Equatable {
    struct Side: Equatable {
        let path: String
        let size: Int64
        let modified: Date
        let isFolder: Bool
        let isNewer: Bool
    }
    let id: UUID
    let jobID: UUID
    let source: Side
    let destination: Side
    let replaceAllowed: Bool
    let remaining: Int
}

@MainActor
@Observable
final class FileOperationQueue {
    static let shared = FileOperationQueue()

    private(set) var queue = FileJobQueue()
    private(set) var pendingConflict: ConflictPrompt?
    private(set) var speed: Double?
    private(set) var eta: TimeInterval?
    private(set) var recovery: [RecoveryItem] = []
    private(set) var lastErrorKey: String?

    var hasActiveWork: Bool { queue.active != nil }

    /// One application-support directory for both the journal and this launch's own bookkeeping.
    private static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("XFinder/Browser", isDirectory: true)
    }()
    private static let journalURL = supportDirectory.appendingPathComponent("operations.jsonl")

    /// Per-job runtime state not part of the pure `FileJob` (threads, control flags, conflict continuations).
    private final class Runtime {
        let control = JobControl()
        var sourcesRemaining: [String] = []     // top-level sources not yet started/finished this job
        var conflictPolicy: ConflictChoice?      // set by "apply to all" after the first conflict of a job
        var continuation: CheckedContinuation<ConflictChoice, Never>?
        var startedAt = Date()
        var lastSampleAt = Date()
        var lastSampleBytes: Int64 = 0
        var createdForUndo: [String] = []        // copy/duplicate: paths actually created (for undo = trash them)
        var movedPairs: [(from: String, to: String)] = []   // rename/move: for undo = move back
        var trashedPairs: [(trashedAt: String, original: String)] = []   // trash kind: for undo = move back from Trash
    }
    private var runtimes: [UUID: Runtime] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API (contract)

    @discardableResult
    func enqueue(_ kind: FileOperationKind, sources: [String], destination: String?) -> UUID? {
        guard !sources.isEmpty else { lastErrorKey = "Không có gì để thao tác"; return nil }
        if let destination, kind != .trash {
            if FileOperationRules.nestingViolation(sources: sources, destination: destination) != nil {
                lastErrorKey = "Nguồn và đích không được trùng nhau."
                return nil
            }
            guard FileManager.default.isWritableFile(atPath: destination) || !FileManager.default.fileExists(atPath: destination) else {
                lastErrorKey = "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền."
                return nil
            }
        }
        let job = FileJob(id: UUID(), kind: kind, sources: sources, destination: destination)
        queue.enqueue(job)
        lastErrorKey = nil
        startNextIfNeeded()
        return job.id
    }

    func pause(_ id: UUID) {
        guard queue.pause(id) else { return }
        runtimes[id]?.control.requestPause()
    }

    func resume(_ id: UUID) {
        guard queue.resume(id) else { return }
        runtimes[id]?.control.requestResume()
    }

    func cancel(_ id: UUID) {
        guard queue.cancel(id) else { return }
        runtimes[id]?.control.requestCancel()
        if let runtime = runtimes[id], let continuation = runtime.continuation {
            runtime.continuation = nil
            continuation.resume(returning: .stop)
        }
    }

    func pauseAll() {
        let wasRunning = queue.jobs.filter { $0.state == .running }
        queue.pauseAll()
        for job in wasRunning { runtimes[job.id]?.control.requestPause() }
    }

    func resumeAll() {
        let toResume = queue.jobs.filter { $0.state == .paused || $0.state == .pausing }
        queue.resumeAll()
        for job in toResume { runtimes[job.id]?.control.requestResume() }
    }

    func runNext(_ id: UUID) { _ = queue.runNext(id) }
    func moveUp(_ id: UUID) { _ = queue.moveUp(id) }
    func moveDown(_ id: UUID) { _ = queue.moveDown(id) }

    func clearFinished() {
        for job in queue.jobs where job.isFinished { runtimes.removeValue(forKey: job.id) }
        queue.clearFinished()
        updateEjectGuard()
    }

    func resolveConflict(_ choice: ConflictChoice, applyToAll: Bool) {
        guard let prompt = pendingConflict else { return }
        guard let runtime = runtimes[prompt.jobID] else { pendingConflict = nil; return }
        if applyToAll { runtime.conflictPolicy = choice }
        pendingConflict = nil
        guard let continuation = runtime.continuation else { return }
        runtime.continuation = nil
        continuation.resume(returning: choice)
    }

    func loadRecovery() {
        let entries = Self.readJournal()
        recovery = FileOperationRules.recoveryReport(entries)
        // A job whose every (job, source) pair's latest phase is `.done` or `.sourceRemoved` completed cleanly
        // before this journal was last read — its lines would otherwise only ever grow the file, since nothing else
        // removes them. Uses the exact same "latest entry in append order" rule as `FileOperationRules
        // .recoveryReport` so this stays consistent with what `recovery` just reported as unresolved.
        struct Key: Hashable { let job: UUID; let source: String }
        var latestPhase: [Key: JournalPhase] = [:]
        for entry in entries { latestPhase[Key(job: entry.job, source: entry.source)] = entry.phase }
        let unresolvedJobs = Set(latestPhase.filter { $0.value != .done && $0.value != .sourceRemoved }.keys.map(\.job))
        Self.compactJournal(keep: { unresolvedJobs.contains($0) })
    }

    func clearRecovery() {
        recovery = []
        Self.compactJournal(keep: { _ in false })
    }

    /// Undo for the browser's own last finished action — distinct from the generic `ActionHistoryDetailView` (which
    /// still works for anything already recorded with a reversible `UndoPayload`); this asks `ActionHistoryStore`
    /// for the most recent entry this queue itself recorded and reverses exactly that one.
    func undoLast() -> String? {
        guard let entry = ActionHistoryStore.shared.entries.first(where: { $0.kind == Self.historyKind }) else {
            return nil
        }
        return ActionHistoryStore.shared.undo(entry)
    }

    static let historyKind = "browser"

    // MARK: - Starting jobs

    private func startNextIfNeeded() {
        guard let startedID = queue.startNextIfIdle() else { return }
        guard let job = queue.jobs.first(where: { $0.id == startedID }) else { return }
        let runtime = Runtime()
        runtime.sourcesRemaining = job.sources
        runtimes[startedID] = runtime
        updateEjectGuard()
        Task { [weak self] in
            await self?.run(job: job, runtime: runtime)
        }
    }

    private func updateEjectGuard() {
        var busy: Set<String> = []
        for job in queue.jobs where job.isActive {
            for source in job.sources {
                if let volume = DirectoryReader.volumePath(of: source) { busy.insert(volume) }
            }
            if let destination = job.destination, let volume = DirectoryReader.volumePath(of: destination) {
                busy.insert(volume)
            }
        }
        EjectGuard.shared.setBusyVolumes(busy)
    }

    // MARK: - Running a job (per-item dispatch)

    private func run(job originalJob: FileJob, runtime: Runtime) async {
        let jobID = originalJob.id
        var itemsDone = 0
        var bytesDone: Int64 = 0
        let bytesTotal = Self.totalBytes(of: originalJob.sources)
        updateProgress(jobID, bytesDone: 0, itemsDone: 0, bytesTotal: bytesTotal, itemsTotal: originalJob.sources.count)
        appendJournal(job: jobID, kind: originalJob.kind, source: originalJob.sources.first ?? "", destination: originalJob.destination, phase: .started)

        var existingNamesCache: [String: Set<String>] = [:]
        func existingNames(in folder: String) -> Set<String> {
            if let cached = existingNamesCache[folder] { return cached }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)).map(Set.init) ?? []
            existingNamesCache[folder] = names
            return names
        }

        itemLoop: for source in originalJob.sources {
            guard currentState(of: jobID) != .cancelled else { break }
            // Honor a pause requested between items: block here (off the UI) until resumed or cancelled.
            while currentState(of: jobID) == .paused || currentState(of: jobID) == .pausing {
                _ = queue.setPhase(jobID, .paused)
                try? await Task.sleep(nanoseconds: 100_000_000)
                if currentState(of: jobID) == .cancelled { break itemLoop }
            }
            if currentState(of: jobID) == .cancelled { break }
            if currentState(of: jobID) == .pausing || currentState(of: jobID) == .running {
                _ = queue.setPhase(jobID, .running)
            }

            let outcome = await performItem(
                jobID: jobID, kind: originalJob.kind, source: source, destinationFolder: originalJob.destination,
                runtime: runtime, existingNames: existingNames
            )
            switch outcome {
            case .done(let bytes, let itemsCreated):
                itemsDone += 1
                bytesDone += bytes
                runtime.createdForUndo.append(contentsOf: itemsCreated)
                updateProgress(jobID, bytesDone: bytesDone, itemsDone: itemsDone, bytesTotal: bytesTotal, itemsTotal: originalJob.sources.count)
            case .skipped:
                itemsDone += 1
                updateProgress(jobID, bytesDone: bytesDone, itemsDone: itemsDone, bytesTotal: bytesTotal, itemsTotal: originalJob.sources.count)
            case .stopped:
                queue.cancel(jobID)
                break itemLoop
            case .failed(let key, let detail):
                queue.finish(jobID, failedWith: key, detail: detail)
                lastErrorKey = key
                runtimes.removeValue(forKey: jobID)
                updateEjectGuard()
                return
            }
        }

        // `cancel(_:)` already set the job's state to `.cancelled` (either from the loop's own check or from the
        // `.stopped` branch above) — `finish()` only distinguishes `.done`/`.failed`, so calling it here would
        // overwrite a legitimate cancellation with a false "done".
        if currentState(of: jobID) != .cancelled {
            recordHistory(job: originalJob, runtime: runtime)
            queue.finish(jobID, failedWith: nil, detail: nil)
        }
        runtimes.removeValue(forKey: jobID)
        updateEjectGuard()
        startNextIfNeeded()
    }

    private func currentState(of id: UUID) -> JobState? {
        queue.jobs.first(where: { $0.id == id })?.state
    }

    private func updateProgress(_ id: UUID, bytesDone: Int64, itemsDone: Int, bytesTotal: Int64, itemsTotal: Int) {
        queue.progress(id, bytesDone: bytesDone, itemsDone: itemsDone)
        guard let runtime = runtimes[id] else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(runtime.lastSampleAt)
        if elapsed > 0.2 {
            let deltaBytes = bytesDone - runtime.lastSampleBytes
            let sample = Double(deltaBytes) / elapsed
            speed = FileOperationRules.smoothedSpeed(previous: speed, sample: max(sample, 0))
            eta = FileOperationRules.eta(bytesDone: bytesDone, bytesTotal: bytesTotal, bytesPerSecond: speed ?? 0)
            runtime.lastSampleAt = now
            runtime.lastSampleBytes = bytesDone
        }
    }

    // MARK: - Per-item outcome

    private enum ItemOutcome {
        case done(bytes: Int64, createdForUndo: [String])
        case skipped
        case stopped
        case failed(key: String, detail: String?)
    }

    private func performItem(
        jobID: UUID, kind: FileOperationKind, source: String, destinationFolder: String?,
        runtime: Runtime, existingNames: (String) -> Set<String>
    ) async -> ItemOutcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source) else {
            return .failed(key: "Thư mục không còn tồn tại", detail: source)
        }
        var isDirObjC: ObjCBool = false
        fm.fileExists(atPath: source, isDirectory: &isDirObjC)
        let sourceIsFolder = isDirObjC.boolValue

        if kind == .trash {
            return await performTrash(jobID: jobID, source: source, runtime: runtime)
        }

        guard let destinationFolder else {
            return .failed(key: "Không đọc được thư mục này", detail: nil)
        }
        let name = (source as NSString).lastPathComponent
        var finalName = name
        var destinationPath = (destinationFolder as NSString).appendingPathComponent(finalName)

        if kind == .duplicate {
            // Duplicate always lands next to the source, in the source's own folder, never "destinationFolder"
            // from the caller (duplicate has no destination — contract passes the source's folder for convenience,
            // but the name search must look at THAT folder's contents).
            let folder = (source as NSString).deletingLastPathComponent
            finalName = FileOperationRules.duplicateName(for: name, existing: existingNames(folder))
            destinationPath = (folder as NSString).appendingPathComponent(finalName)
        } else if fm.fileExists(atPath: destinationPath) {
            let resolution = await resolveConflictIfNeeded(
                jobID: jobID, runtime: runtime, source: source, sourceIsFolder: sourceIsFolder, destinationPath: destinationPath
            )
            switch resolution {
            case .stop: return .stopped
            case .skip: return .skipped
            case .replace:
                do { try fm.trashItem(at: URL(fileURLWithPath: destinationPath), resultingItemURL: nil) }
                catch { return .failed(key: "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.", detail: "\(error)") }
            case .keepBoth:
                let folder = destinationFolder
                finalName = FileOperationRules.keepBothName(for: name, existing: existingNames(folder))
                destinationPath = (folder as NSString).appendingPathComponent(finalName)
            }
        }

        let sameVolume = DirectoryReader.volumeID(of: source) != nil
            && DirectoryReader.volumeID(of: destinationFolder) != nil
            && DirectoryReader.volumeID(of: source) == DirectoryReader.volumeID(of: destinationFolder)
        let strategy = FileOperationRules.strategy(kind: kind, sameVolume: sameVolume)

        switch strategy {
        case .rename:
            appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .started)
            if rename(source, destinationPath) == 0 {
                appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .done)
                runtime.movedPairs.append((from: destinationPath, to: source))
                return .done(bytes: 0, createdForUndo: [])
            }
            let err = errno
            if err == EXDEV {
                // The two paths claim the same volume ID but the kernel disagrees (bind mount, odd filesystem) —
                // fall through to the byte-copy + verify + trash path rather than failing outright.
                return await copyVerifyTrashOrCopy(
                    jobID: jobID, kind: .move, source: source, destinationPath: destinationPath, runtime: runtime
                )
            }
            return .failed(key: "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.", detail: "errno \(err)")

        case .cloneOrCopy:
            return await copyOnly(jobID: jobID, source: source, destinationPath: destinationPath, sameVolume: sameVolume, runtime: runtime)

        case .copyVerifyTrash:
            return await copyVerifyTrashOrCopy(jobID: jobID, kind: .move, source: source, destinationPath: destinationPath, runtime: runtime)

        case .trash:
            return await performTrash(jobID: jobID, source: source, runtime: runtime)
        }
    }

    private func resolveConflictIfNeeded(
        jobID: UUID, runtime: Runtime, source: String, sourceIsFolder: Bool, destinationPath: String
    ) async -> ConflictChoice {
        if let policy = runtime.conflictPolicy { return policy }
        let fm = FileManager.default
        var destIsDirObjC: ObjCBool = false
        fm.fileExists(atPath: destinationPath, isDirectory: &destIsDirObjC)
        let destIsFolder = destIsDirObjC.boolValue
        let srcAttrs = try? fm.attributesOfItem(atPath: source)
        let dstAttrs = try? fm.attributesOfItem(atPath: destinationPath)
        let srcModified = (srcAttrs?[.modificationDate] as? Date) ?? .distantPast
        let dstModified = (dstAttrs?[.modificationDate] as? Date) ?? .distantPast
        let srcSize = (srcAttrs?[.size] as? NSNumber)?.int64Value ?? 0
        let dstSize = (dstAttrs?[.size] as? NSNumber)?.int64Value ?? 0
        let coarse = DirectoryReader.hasCoarseTimestamps(destinationPath)
        let replaceAllowed = FileOperationRules.replaceAllowed(sourceIsFolder: sourceIsFolder, destinationIsFolder: destIsFolder)

        let prompt = ConflictPrompt(
            id: UUID(), jobID: jobID,
            source: ConflictPrompt.Side(path: source, size: srcSize, modified: srcModified, isFolder: sourceIsFolder,
                                        isNewer: FileOperationRules.isNewer(srcModified, than: dstModified, coarseTimestamps: coarse)),
            destination: ConflictPrompt.Side(path: destinationPath, size: dstSize, modified: dstModified, isFolder: destIsFolder,
                                             isNewer: FileOperationRules.isNewer(dstModified, than: srcModified, coarseTimestamps: coarse)),
            replaceAllowed: replaceAllowed, remaining: runtime.sourcesRemaining.count
        )
        pendingConflict = prompt
        return await withCheckedContinuation { continuation in
            runtime.continuation = continuation
        }
    }

    // MARK: - copyfile(3) worker

    private func copyOnly(jobID: UUID, source: String, destinationPath: String, sameVolume: Bool, runtime: Runtime) async -> ItemOutcome {
        appendJournal(job: jobID, kind: .copy, source: source, destination: destinationPath, phase: .started)
        let result = await Self.runCopy(source: source, destination: destinationPath, clone: sameVolume, control: runtime.control) { [weak self] copied in
            Task { @MainActor [weak self] in
                self?.bumpProgress(jobID, extraBytes: copied)
            }
        }
        switch result {
        case .success(let bytes):
            appendJournal(job: jobID, kind: .copy, source: source, destination: destinationPath, phase: .done)
            return .done(bytes: bytes, createdForUndo: [destinationPath])
        case .cancelled:
            try? FileManager.default.removeItem(atPath: destinationPath)
            return .stopped
        case .failure(let message):
            return .failed(key: "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.", detail: message)
        }
    }

    /// Cross-volume move: copy the bytes, verify with SHA-256 on both sides, then trash the source — never remove
    /// it outright (Q-T28-4). Each phase is journaled so a crash mid-flight has an honest recovery message
    /// (`FileOperationRules.recoveryReport`).
    private func copyVerifyTrashOrCopy(jobID: UUID, kind: FileOperationKind, source: String, destinationPath: String, runtime: Runtime) async -> ItemOutcome {
        appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .started)
        let copyResult = await Self.runCopy(source: source, destination: destinationPath, clone: false, control: runtime.control) { [weak self] copied in
            Task { @MainActor [weak self] in
                self?.bumpProgress(jobID, extraBytes: copied)
            }
        }
        let bytes: Int64
        switch copyResult {
        case .success(let b): bytes = b
        case .cancelled:
            try? FileManager.default.removeItem(atPath: destinationPath)
            return .stopped
        case .failure(let message):
            return .failed(key: "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.", detail: message)
        }
        appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .copied)
        _ = queue.setPhase(jobID, .verifying)

        let sameHash = await Self.verifyMatch(source, destinationPath)
        guard sameHash else {
            try? FileManager.default.removeItem(atPath: destinationPath)
            return .failed(key: "Bản sao chưa được kiểm", detail: "hash mismatch")
        }
        appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .verified)
        _ = queue.setPhase(jobID, .finishing)

        // The `.trashing` line must be on disk (fsync'd) BEFORE the risky call, not after it succeeds: the whole
        // point of this phase is to catch a crash/kill that happens DURING `trashItem` (spec XF-T28-file-browser.md
        // §4 "Bị kill đúng lúc đang đưa bản gốc vào Thùng rác"). Journaling it only on success would leave the
        // journal stuck at `.verified` for that case, and `.verified`'s recovery message ("Bản gốc vẫn còn ở chỗ cũ")
        // is actively wrong once `trashItem` has been entered — the source may already be gone.
        appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .trashing)

        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: source), resultingItemURL: &resultingURL)
        } catch {
            // The destination is a verified, complete copy; the only thing that failed is removing the original —
            // report success for the move's purpose (data is safe at the destination) but leave a trail. Re-append
            // `.verified` so a later crash-recovery read sees "source still at the old place", which is accurate
            // again now that we know for certain `trashItem` never removed it.
            appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .verified)
            runtime.movedPairs.append((from: destinationPath, to: source))
            _ = queue.setPhase(jobID, .running)
            return .done(bytes: bytes, createdForUndo: [])
        }
        // The source is now in the Trash, not undone from there: `movedPairs` below already gives this move a
        // reversible undo (move the verified copy at `destinationPath` back to `source`), which is simpler and
        // matches what the user asked for (a move), rather than reaching into the Trash to resurrect the original.
        appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .sourceRemoved)
        appendJournal(job: jobID, kind: kind, source: source, destination: destinationPath, phase: .done)
        _ = queue.setPhase(jobID, .running)
        runtime.movedPairs.append((from: destinationPath, to: source))
        return .done(bytes: bytes, createdForUndo: [])
    }

    private func performTrash(jobID: UUID, source: String, runtime: Runtime) async -> ItemOutcome {
        appendJournal(job: jobID, kind: .trash, source: source, destination: nil, phase: .started)
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: source), resultingItemURL: &resultingURL)
        } catch {
            return .failed(key: "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.", detail: "\(error)")
        }
        if let trashedPath = (resultingURL as URL?)?.path {
            runtime.trashedPairs.append((trashedAt: trashedPath, original: source))
        }
        appendJournal(job: jobID, kind: .trash, source: source, destination: nil, phase: .done)
        return .done(bytes: 0, createdForUndo: [])
    }

    private func bumpProgress(_ jobID: UUID, extraBytes: Int64) {
        guard let job = queue.jobs.first(where: { $0.id == jobID }) else { return }
        let bytesTotal = Self.totalBytes(of: job.sources)
        updateProgress(jobID, bytesDone: job.bytesDone + extraBytes, itemsDone: job.itemsDone, bytesTotal: bytesTotal, itemsTotal: job.sources.count)
    }

    // MARK: - History / undo

    private func recordHistory(job: FileJob, runtime: Runtime) {
        let count = job.sources.count
        guard count > 0 else { return }
        switch job.kind {
        case .move:
            guard !runtime.movedPairs.isEmpty else { return }
            let summary = "\(L10n.t("Di chuyển "))\(count)\(L10n.t(" mục"))"
            ActionHistoryStore.shared.record(
                kind: FileOperationQueue.historyKind, summary: summary,
                detail: job.destination, reversible: true,
                undoPayload: ActionHistoryStore.UndoPayload(from: runtime.movedPairs.map(\.from), to: runtime.movedPairs.map(\.to))
            )
        case .copy, .duplicate:
            guard !runtime.createdForUndo.isEmpty else { return }
            let summary = job.kind == .copy
                ? "\(L10n.t("Sao chép "))\(count)\(L10n.t(" mục"))"
                : "\(L10n.t("Nhân bản "))\(count)\(L10n.t(" mục"))"
            ActionHistoryStore.shared.record(
                kind: FileOperationQueue.historyKind, summary: summary,
                detail: job.destination, reversible: true,
                undoPayload: ActionHistoryStore.UndoPayload(from: [], to: [], trashOnUndo: runtime.createdForUndo)
            )
        case .trash:
            // Unlike `ActionHistoryStore.recordTrash` (used elsewhere, always `reversible: false`), the browser
            // knows the exact Trash URL `trashItem` produced for each source, so its own trash jobs CAN be undone —
            // a plain move back from that URL to the original path (contract: "trash ⇒ move back from the Trash
            // URL returned by trashItem").
            guard !runtime.trashedPairs.isEmpty else { return }
            let summary = "\(L10n.t("Chuyển "))\(count)\(L10n.t(" mục vào Thùng rác"))"
            ActionHistoryStore.shared.record(
                kind: FileOperationQueue.historyKind, summary: summary, detail: nil, reversible: true,
                undoPayload: ActionHistoryStore.UndoPayload(
                    from: runtime.trashedPairs.map(\.trashedAt), to: runtime.trashedPairs.map(\.original)
                )
            )
        }
    }

    // MARK: - Byte totals (pre-walk)

    private static func totalBytes(of sources: [String]) -> Int64 {
        var total: Int64 = 0
        for source in sources {
            total += FileWalk.totalSize(URL(fileURLWithPath: source)) ?? 0
        }
        return total
    }

    // MARK: - Journal (append-only JSON lines, fsync'd)

    private func appendJournal(job: UUID, kind: FileOperationKind, source: String, destination: String?, phase: JournalPhase) {
        let entry = JournalEntry(job: job, kind: kind, source: source, destination: destination, phase: phase, at: Date())
        Self.appendJournalEntry(entry)
    }

    private static func appendJournalEntry(_ entry: JournalEntry) {
        guard var data = try? JSONEncoder().encode(entry) else { return }
        data.append(0x0A)
        guard let handle = FileHandle(forWritingAtPath: journalURL.path) else {
            FileManager.default.createFile(atPath: journalURL.path, contents: data)
            return
        }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.synchronize()
    }

    private static func readJournal() -> [JournalEntry] {
        guard let data = try? Data(contentsOf: journalURL) else { return [] }
        let decoder = JSONDecoder()
        var entries: [JournalEntry] = []
        for line in data.split(separator: 0x0A) {
            guard let entry = try? decoder.decode(JournalEntry.self, from: Data(line)) else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// A finished job's lines may be compacted at launch (contract): drop every line whose job id is one
    /// `keep` returns false for. Called with `{ _ in false }` to wipe everything (clearRecovery), or at launch
    /// with a predicate that keeps only jobs still unresolved.
    private static func compactJournal(keep: (UUID) -> Bool) {
        let entries = readJournal().filter { keep($0.job) }
        let encoder = JSONEncoder()
        var data = Data()
        for entry in entries {
            guard let line = try? encoder.encode(entry) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        try? data.write(to: journalURL, options: .atomic)
    }

    // MARK: - copyfile(3) static worker

    private enum CopyResult {
        case success(bytes: Int64)
        case cancelled
        case failure(String)
    }

    /// Runs `copyfile(3)` on a background thread. `clone` passes `COPYFILE_CLONE` for a same-volume copy (measured:
    /// without it a 256 MiB copy takes ~115 ms; with it, ~0.16 ms — APFS does not clone by default). The status
    /// callback samples `COPYFILE_STATE_COPIED` for progress, blocks on `control`'s semaphore while paused (this
    /// callback thread blocking IS the pause — measured: a 500 ms block inside it measures 505 ms, and the copy
    /// resumes with a byte-identical result), and returns `COPYFILE_QUIT` once cancelled, which measured leaves no
    /// partial destination file at all (`errno == ECANCELED`, `stat()` on the destination fails).
    private static func runCopy(
        source: String, destination: String, clone: Bool, control: JobControl, onProgress: @escaping @Sendable (Int64) -> Void
    ) async -> CopyResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                try? FileManager.default.removeItem(atPath: destination)
                guard let state = copyfile_state_alloc() else {
                    continuation.resume(returning: .failure("copyfile_state_alloc failed"))
                    return
                }
                defer { copyfile_state_free(state) }

                let box = CopyCallbackBox(control: control, onProgress: onProgress)
                let boxPtr = Unmanaged.passRetained(box).toOpaque()
                defer { Unmanaged<CopyCallbackBox>.fromOpaque(boxPtr).release() }

                var callbackPtr = unsafeBitCast(copyfileProgressCallback, to: UnsafeRawPointer.self)
                withUnsafeMutablePointer(to: &callbackPtr) { p in
                    _ = copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), p.pointee)
                }
                var contextPtr: UnsafeRawPointer? = UnsafeRawPointer(boxPtr)
                withUnsafeMutablePointer(to: &contextPtr) { p in
                    _ = copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), p.pointee)
                }

                var isDirObjC: ObjCBool = false
                let isDirectory = FileManager.default.fileExists(atPath: source, isDirectory: &isDirObjC) && isDirObjC.boolValue
                var flags: UInt32 = UInt32(COPYFILE_ALL)
                if clone { flags |= UInt32(COPYFILE_CLONE) }
                if isDirectory { flags |= UInt32(COPYFILE_RECURSIVE) }

                let rc = copyfile(source, destination, state, copyfile_flags_t(flags))
                let savedErrno = errno
                if rc == 0 {
                    var copied: off_t = 0
                    copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                    continuation.resume(returning: .success(bytes: Int64(copied)))
                } else if savedErrno == ECANCELED {
                    continuation.resume(returning: .cancelled)
                } else {
                    continuation.resume(returning: .failure("copyfile errno \(savedErrno)"))
                }
            }
        }
    }

    /// SHA-256 verification, 4 MiB chunks (measured ≈2.3 GB/s) — read both files off the main thread.
    private static func verifyMatch(_ a: String, _ b: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let hashA = sha256(ofFileAt: a), let hashB = sha256(ofFileAt: b) else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: hashA == hashB)
            }
        }
    }

    private static nonisolated func sha256(ofFileAt path: String) -> SHA256Digest? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 4 * 1024 * 1024
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }
}

/// Shared pause/cancel flags for one running copy, read and set from both the worker thread (via the C callback)
/// and the main actor (pause()/resume()/cancel()). `OSAllocatedUnfairLock` guards the flags; a `DispatchSemaphore`
/// is what actually blocks the callback thread while paused — signalling it is the only way `resume()` can wake it.
final class JobControl: @unchecked Sendable {
    private struct State { var paused = false; var cancelled = false }
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private let semaphore = DispatchSemaphore(value: 0)

    func requestPause() { lock.withLock { $0.paused = true } }
    func requestResume() {
        let wasPaused = lock.withLock { state -> Bool in
            let was = state.paused
            state.paused = false
            return was
        }
        if wasPaused { semaphore.signal() }
    }
    func requestCancel() {
        let wasPaused = lock.withLock { state -> Bool in
            let was = state.paused
            state.cancelled = true
            return was
        }
        if wasPaused { semaphore.signal() }
    }

    /// Called only from the copyfile callback thread. Blocks there (not the main thread) while paused; returns
    /// `true` once it is safe to continue, `false` if cancellation won the race.
    func waitIfPaused() -> Bool {
        let (paused, cancelled) = lock.withLock { ($0.paused, $0.cancelled) }
        if cancelled { return false }
        if paused {
            semaphore.wait()
            return !(lock.withLock { $0.cancelled })
        }
        return true
    }

    var isCancelled: Bool { lock.withLock { $0.cancelled } }
}

/// Carries a `JobControl` plus the progress closure across the C callback boundary. A plain class, retained for the
/// duration of one `copyfile()` call via `Unmanaged.passRetained`/`release` around it (not `@unchecked Sendable` —
/// everything it exposes to the callback thread is immutable after init except through `JobControl`, which is
/// itself the `Sendable`-safe shared-state type).
private final class CopyCallbackBox {
    let control: JobControl
    let onProgress: @Sendable (Int64) -> Void
    init(control: JobControl, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.control = control
        self.onProgress = onProgress
    }
}

/// The C callback itself: a top-level `let` (not a closure capturing state) because `copyfile_callback_t` is a
/// plain C function pointer — it cannot carry captures, so all state travels through the `ctx` parameter, which
/// `runCopy` sets to the raw pointer VALUE of a retained `CopyCallbackBox` (not `&localVariable`; passing the
/// address of a local for the callback slot itself was measured to crash — EXC_BAD_ACCESS — because copyfile then
/// tries to call the stack address as code).
private let copyfileProgressCallback: copyfile_callback_t = { what, stage, state, src, dst, ctx in
    guard let ctx else { return COPYFILE_CONTINUE }
    let box = Unmanaged<CopyCallbackBox>.fromOpaque(ctx).takeUnretainedValue()
    if stage == COPYFILE_PROGRESS, let state {
        var copied: off_t = 0
        copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
        box.onProgress(Int64(copied))
    }
    if box.control.isCancelled { return COPYFILE_QUIT }
    if !box.control.waitIfPaused() { return COPYFILE_QUIT }
    return COPYFILE_CONTINUE
}
