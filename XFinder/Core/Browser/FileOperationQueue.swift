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
///
/// XF-T30 W6 (contract docs/specs/XF-T30-w6-contract.md §2) adds: a batch keeps going when one item fails, recording
/// a `ProblemEntry` instead of aborting the job (§8 spec-file-operations R45/R50); speed/ETA over a 5 s sliding
/// window of byte samples, hidden per `isProgressVisible(for:)`; the seven stage labels via `stageLabelKey(for:)`
/// (Waiting/Preparing are both `JobState.waiting` — "preparing" is the brief pre-walk the job does before its first
/// item starts, tracked here, not a new `JobState` case, since that enum is `FileOperationRules`' contract); pause
/// disabled only for the LAST item's Verify/Finish (`canPauseNow`); and the browser's own persistent `UndoJournal`
/// (JSON at `~/Library/Application Support/XFinder/Browser/undo.json`, read/written off main) replacing
/// `ActionHistoryStore` for this queue's own jobs — `undoLast()`/`redoLast()` revalidate via `UndoJournal
/// .availability` before touching any file, and an undo requested while its own source job is still running is
/// queued (`pendingUndoAfterJobs`) rather than raced or dropped.
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

    /// W6: the session's Problems list (one `ProblemEntry` per finished operation that had ≥1 failing item).
    private(set) var problems = ProblemsList()
    /// W6: the most recently finished operation's problems, shown as one alert dialog; the panel clears this after
    /// presenting it (`dismissProblemAlert()`) — `problems.entries` itself is unaffected, so the row stays in the list.
    private(set) var problemAlert: ProblemEntry?
    /// W6: the browser's own persistent Undo/Redo (distinct from `ActionHistoryStore`, which other browser-unrelated
    /// features still use). Loaded at init off the main thread's hot path is unnecessary — the file is tiny (≤20
    /// steps) — but every WRITE after that happens off main via `Self.ioQueue`.
    private(set) var undoJournal = UndoJournal()
    /// Undo (or redo) requests made while the step's OWN originating job is still running/active are queued here
    /// (spec R53) and replayed in `startNextIfNeeded`'s completion path once that job actually finishes.
    private var pendingUndoAfterJobs: [UUID: [Bool]] = [:]  // jobID -> queue of (true = undo, false = redo) requests

    var hasActiveWork: Bool { queue.active != nil }

    /// One application-support directory for both the journal and this launch's own bookkeeping.
    private static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("XFinder/Browser", isDirectory: true)
    }()
    private static let journalURL = supportDirectory.appendingPathComponent("operations.jsonl")
    private static let undoJournalURL = supportDirectory.appendingPathComponent("undo.json")
    private static let ioQueue = DispatchQueue(label: "com.xfinder.browser.undo-journal-io", qos: .utility)

    /// Per-job runtime state not part of the pure `FileJob` (threads, control flags, conflict continuations).
    private final class Runtime {
        let control = JobControl()
        var sourcesRemaining: [String] = []     // top-level sources not yet started/finished this job
        var conflictPolicy: ConflictChoice?      // set by "apply to all" after the first conflict of a job
        var continuation: CheckedContinuation<ConflictChoice, Never>?
        var startedAt = Date()
        var lastSampleBytes: Int64 = 0
        var createdForUndo: [String] = []        // copy/duplicate: paths actually created (for undo = trash them)
        var movedPairs: [(from: String, to: String)] = []   // rename/move: for undo = move back
        var trashedPairs: [(trashedAt: String, original: String)] = []   // trash kind: for undo = move back from Trash
        var failedItems: [ProblemItem] = []      // W6: items that failed this job but let the batch keep going
        var currentItemIndex = 0                 // W6: index into the job's `sources`, for "is this the last item"
        var totalItemCount = 0
        /// W6: byte-sample ring buffer for the 5 s sliding-window speed, newest last. `(uptime seconds, bytesDone)`.
        var samples: [(t: TimeInterval, bytes: Int64)] = []
        var lastProgressAt = Date()              // W6: for "stalled > 3 s" (speed/ETA hidden)
    }
    private var runtimes: [UUID: Runtime] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        undoJournal = Self.loadUndoJournal()
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
        guard canPauseNow(id) else { return }
        guard queue.pause(id) else { return }
        runtimes[id]?.control.requestPause()
    }

    /// W6: pause is refused once the job's CURRENT item is its last one and that item has reached Verify/Finish —
    /// there is no remaining safe point before the whole job ends (spec R37 / contract §2 "không cho tạm dừng ở bước
    /// Kiểm/Hoàn tất của mục cuối"). Earlier items' Verify/Finish still allow pausing: the per-item loop in `run`
    /// already checks for a pending pause BETWEEN items, so a pause requested mid-verify of a non-last item simply
    /// takes effect once that item's `.done`/`.failed` outcome lands, before the next item starts.
    func canPauseNow(_ id: UUID) -> Bool {
        guard let job = currentJob(id), let runtime = runtimes[id] else { return false }
        guard FileOperationRules.canPause(job.state) || job.state == .verifying || job.state == .finishing else {
            return false
        }
        let isLastItem = runtime.totalItemCount > 0 && runtime.currentItemIndex == runtime.totalItemCount - 1
        if isLastItem && (job.state == .verifying || job.state == .finishing) { return false }
        return job.state == .running || job.state == .pausing || job.state == .verifying || job.state == .finishing
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

    // MARK: - W6: stage labels, progress visibility (contract §2)

    /// Exactly the seven stage labels in the contract: Waiting, Preparing, Copying, Pausing, Verifying, Finishing,
    /// and a terminal group (Done / Error / Stopped) — `JobState` has more raw cases than that (e.g. `.paused` is
    /// still shown as "Đang tạm dừng" alongside `.pausing`, matching FileOctopus's own Pausing→Paused pair, which
    /// the spec's stage-name table lists as one color-coded group, not two separate labels).
    func stageLabelKey(for job: FileJob) -> String {
        switch job.state {
        case .waiting:
            // "Preparing" is the pre-walk this queue itself does (computing `bytesTotal`, checking conflicts)
            // before the first item of an ALREADY-STARTED job moves any bytes — a job still `.waiting` in the queue
            // (behind another one) is "Waiting", not "Preparing".
            return "Đang chờ"
        case .running:
            guard let runtime = runtimes[job.id] else { return "Đang chờ" }
            return runtime.lastProgressAt.timeIntervalSinceNow > -0.001 && job.bytesDone == 0 && job.itemsDone == 0
                ? "Đang chuẩn bị" : "Đang chép"
        case .pausing, .paused: return "Đang tạm dừng"
        case .verifying: return "Đang kiểm"
        case .finishing: return "Đang hoàn tất"
        case .done: return "Xong"
        case .failed: return "Lỗi"
        case .cancelled: return "Đã dừng"
        }
    }

    /// Speed/ETA are hidden (contract §2 / spec R35): while Pausing/Paused, Verifying, Finishing, stalled > 3 s with
    /// no byte progress, or for a zero-byte operation (rename-only moves, same-disk trash — `bytesTotal == 0`).
    func isProgressVisible(for job: FileJob) -> Bool {
        guard job.state == .running else { return false }
        guard job.bytesTotal > 0 else { return false }
        guard let runtime = runtimes[job.id] else { return false }
        return Date().timeIntervalSince(runtime.lastProgressAt) <= 3
    }

    // MARK: - W6: Problems list (contract §2 / spec §8)

    /// Dismisses the one-shot alert without touching `problems.entries` — the row stays in the panel's Problems
    /// section until the user dismisses/clears/retries it there.
    func dismissProblemAlert() {
        problemAlert = nil
    }

    func dismissProblem(_ id: UUID) {
        problems.dismiss(id)
    }

    func clearAllProblems() {
        problems.clearAll()
    }

    /// Retry (spec R48): a brand-new job scoped to just the failed items of one `ProblemEntry`, re-validated against
    /// current disk state — the normal conflict dialog reappears if a new collision exists. `destination` is the
    /// folder the original operation targeted; trash/rename problems (no destination) are not retryable (`canRetry`
    /// already reflects this via `beforeWrite`), so this is only ever called for copy/move/duplicate problems.
    @discardableResult
    func retryProblem(_ entry: ProblemEntry, kind: FileOperationKind, destination: String?) -> UUID? {
        guard entry.canRetry else { return nil }
        let paths = entry.items.map(\.path)
        guard !paths.isEmpty else { return nil }
        problems.dismiss(entry.id)
        return enqueue(kind, sources: paths, destination: destination)
    }

    // MARK: - W6: persistent Undo / Redo (contract §2 / spec §9)

    /// Undo for the browser's own last finished action. Revalidates with `UndoJournal.availability` BEFORE touching
    /// any file (spec R56/R58): identity (inode/size/modified), existence, and — for a step whose paths live on a
    /// volume that is not currently mounted — refuses with "Can't Undo…" rather than failing partway. If the step's
    /// own originating job is still active, the request is queued (`pendingUndoAfterJobs`) and replayed once that
    /// job's `run(job:runtime:)` finishes, instead of racing a copy that is still writing.
    @discardableResult
    /// Returns `nil` ONLY when this queue's journal has nothing to undo at all — `BrowserWindowModel`'s `.undo`
    /// command relies on that exact contract (pre-W6 behavior, kept unchanged) to fall through to its own
    /// `lastCompressedArchive` undo path when this queue has nothing of its own. A step that exists but could not be
    /// undone (unavailable, partial failure) still returns a rendered message, same as the old `ActionHistoryStore`-
    /// backed version always did once an entry existed.
    func undoLast() -> String? {
        guard let step = undoJournal.undo.first else { return nil }
        if let jobID = activeJobID(producing: step), currentJob(jobID)?.isActive == true {
            pendingUndoAfterJobs[jobID, default: []].append(true)
            return L10n.t("Sẽ hoàn tác sau khi việc đang chạy xong")
        }
        return performUndo(step)
    }

    /// Redo (spec R52: same scrutiny as Undo). Queued the same way if its step's job is still active. `nil` only
    /// when there is nothing in the redo stack (same contract as `undoLast()`).
    @discardableResult
    func redoLast() -> String? {
        guard let step = undoJournal.redo.first else { return nil }
        if let jobID = activeJobID(producing: step), currentJob(jobID)?.isActive == true {
            pendingUndoAfterJobs[jobID, default: []].append(false)
            return L10n.t("Sẽ làm lại sau khi việc đang chạy xong")
        }
        return performRedo(step)
    }

    /// Title for the Edit menu (spec R52: "Undo Move of 3 Items" style — verb + target already baked into
    /// `UndoStep.titleKey` by whichever side records the step).
    var undoTitleKey: String? { undoJournal.undo.first?.titleKey }
    var redoTitleKey: String? { undoJournal.redo.first?.titleKey }

    /// A step references a still-running job only in the narrow window between that job's `recordHistory` call and
    /// its `runtimes.removeValue` cleanup — in practice this only matters for a multi-job queue where the user asks
    /// to undo the MOST RECENT step while a LATER job is already running; `activeJobID` finds that case by matching
    /// paths, not by storing a job id on `UndoStep` (which is `FileOperationRules`' contract, not mine to extend).
    private func activeJobID(producing step: UndoStep) -> UUID? {
        let stepPaths = Set(step.items.flatMap { [$0.from, $0.to] })
        for job in queue.jobs where job.isActive {
            if job.sources.contains(where: stepPaths.contains) { return job.id }
            if let destination = job.destination, stepPaths.contains(where: { $0.hasPrefix(destination) }) { return job.id }
        }
        return nil
    }

    /// Undo moves `from → to` for every kind except copy/duplicate, which have no "original location": undoing one
    /// of those trashes the item `copyOnly`/`performItem` created (`to` is the empty-string sentinel `recordHistory`
    /// stores for these two kinds) — never a hard delete (spec R9 "Dữ liệu người dùng").
    private func performUndo(_ step: UndoStep) -> String {
        let availability = undoJournal.availability(
            of: step, exists: { FileManager.default.fileExists(atPath: $0) },
            identity: Self.fileIdentity, volumeMounted: Self.volumeMounted
        )
        guard case .available = availability else {
            return Self.unavailableMessage(availability)
        }
        let fm = FileManager.default
        var ok = 0
        for item in step.items {
            do {
                switch step.kind {
                case .copy, .duplicate:
                    guard fm.fileExists(atPath: item.from) else { ok += 1; continue }
                    try fm.trashItem(at: URL(fileURLWithPath: item.from), resultingItemURL: nil)
                    ok += 1
                default:
                    if fm.fileExists(atPath: item.to) { continue }
                    try fm.moveItem(atPath: item.from, toPath: item.to)
                    ok += 1
                }
            } catch { /* spec R55: a partial failure here still leaves `ok < step.items.count`, reported below */ }
        }
        guard ok == step.items.count else {
            return L10n.t("Không thể hoàn tác thao tác này.")
        }
        _ = undoJournal.popUndo()
        Self.saveUndoJournal(undoJournal)
        return "\(L10n.t("Đã hoàn tác "))\(step.items.count)\(L10n.t(" mục"))"
    }

    /// Redo re-applies the original direction (`to → from` for move/trash/rename). A copy/duplicate's redo has no
    /// safe one-step replay (the original source location is not part of `UndoItem`, and re-running the whole copy
    /// risks a different conflict outcome than the first time), so it is refused with its own reason rather than
    /// guessed at — consistent with spec R58 "Redo faces the identical scrutiny".
    private func performRedo(_ step: UndoStep) -> String {
        guard step.kind != .copy, step.kind != .duplicate else {
            return L10n.t("Không thể làm lại thao tác này.")
        }
        let availability = undoJournal.availability(
            of: step, exists: { FileManager.default.fileExists(atPath: $0) },
            identity: Self.fileIdentity, volumeMounted: Self.volumeMounted
        )
        guard case .available = availability else {
            return Self.unavailableMessage(availability)
        }
        let fm = FileManager.default
        var redone = 0
        for item in step.items {
            do {
                if fm.fileExists(atPath: item.from) { continue }
                try fm.moveItem(atPath: item.to, toPath: item.from)
                redone += 1
            } catch { }
        }
        guard redone == step.items.count else {
            return L10n.t("Không thể hoàn tác thao tác này.")
        }
        _ = undoJournal.popRedo()
        Self.saveUndoJournal(undoJournal)
        return "\(L10n.t("Đã làm lại "))\(step.items.count)\(L10n.t(" mục"))"
    }

    private static func unavailableMessage(_ availability: UndoJournal.Availability) -> String {
        switch availability {
        case .available: return ""
        case .diskMissing: return L10n.t("Không hoàn tác được…")
        case .unavailable(let reasonKey): return reasonKey.isEmpty ? L10n.t("Không thể hoàn tác thao tác này.") : L10n.t(reasonKey)
        }
    }

    private static func fileIdentity(_ path: String) -> (inode: UInt64, size: Int64, modified: Date)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        guard let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date) ?? .distantPast
        return (inode, size, modified)
    }

    private static func volumeMounted(_ path: String) -> Bool {
        guard let mount = DirectoryReader.volumePath(of: path) else { return false }
        return FileManager.default.fileExists(atPath: mount)
    }

    /// Replays any undo/redo requests that were queued because this job (as the step's own source) was still
    /// running when the user asked. Called once per finished job, after `runtimes` still has the job's runtime
    /// (so `activeJobID` for a DIFFERENT still-running job keeps working) but after this job itself is no longer
    /// active.
    private func drainPendingUndo(for jobID: UUID) {
        guard let requests = pendingUndoAfterJobs.removeValue(forKey: jobID), !requests.isEmpty else { return }
        for isUndo in requests {
            if isUndo {
                if let step = undoJournal.undo.first { _ = performUndo(step) }
            } else {
                if let step = undoJournal.redo.first { _ = performRedo(step) }
            }
        }
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
        runtime.totalItemCount = originalJob.sources.count
        updateProgress(jobID, bytesDone: 0, itemsDone: 0, bytesTotal: bytesTotal, itemsTotal: originalJob.sources.count)
        appendJournal(job: jobID, kind: originalJob.kind, source: originalJob.sources.first ?? "", destination: originalJob.destination, phase: .started)

        var existingNamesCache: [String: Set<String>] = [:]
        func existingNames(in folder: String) -> Set<String> {
            if let cached = existingNamesCache[folder] { return cached }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)).map(Set.init) ?? []
            existingNamesCache[folder] = names
            return names
        }

        itemLoop: for (index, source) in originalJob.sources.enumerated() {
            runtime.currentItemIndex = index
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
                // W6 (spec R45/R50): one failing item no longer aborts the whole batch — it is recorded as a
                // `ProblemItem` and the loop moves on to the next source. The job itself still finishes as `.done`
                // once every item has been attempted; `lastErrorKey` is kept for the (rare) case nothing in the job
                // ever got a chance to run at all (e.g. `enqueue`'s own up-front checks), not for per-item failures.
                let reason = ProblemReason.from(posix: Self.posixCode(fromDetail: detail))
                runtime.failedItems.append(ProblemItem(path: source, reason: reason, systemMessage: detail, beforeWrite: true))
                itemsDone += 1
                updateProgress(jobID, bytesDone: bytesDone, itemsDone: itemsDone, bytesTotal: bytesTotal, itemsTotal: originalJob.sources.count)
                _ = key // the per-item L10n key is folded into `reason`/`systemMessage` on the Problems row, not surfaced again here
            }
        }

        // `cancel(_:)` already set the job's state to `.cancelled` (either from the loop's own check or from the
        // `.stopped` branch above) — `finish()` only distinguishes `.done`/`.failed`, so calling it here would
        // overwrite a legitimate cancellation with a false "done".
        if currentState(of: jobID) != .cancelled {
            recordHistory(job: originalJob, runtime: runtime)
            queue.finish(jobID, failedWith: nil, detail: nil)
            recordProblems(job: originalJob, runtime: runtime)
        }
        runtimes.removeValue(forKey: jobID)
        updateEjectGuard()
        drainPendingUndo(for: jobID)
        startNextIfNeeded()
    }

    /// W6 (spec R45): one `ProblemEntry` per finished operation that had ≥1 failing item, surfaced once as an alert
    /// (`problemAlert`) in addition to the persistent list row.
    private func recordProblems(job: FileJob, runtime: Runtime) {
        guard !runtime.failedItems.isEmpty else { return }
        let entry = ProblemEntry(
            id: UUID(), operationTitleKey: operationTitleKey(for: job), finished: Date(), items: runtime.failedItems
        )
        problems.add(entry)
        problemAlert = entry
    }

    private func operationTitleKey(for job: FileJob) -> String {
        switch job.kind {
        case .copy: return "Sao chép"
        case .move: return "Di chuyển"
        case .duplicate: return "Nhân bản"
        case .trash: return "Chuyển vào Thùng rác"
        }
    }

    /// `performItem`'s `detail` string is free-form (`"\(error)"`, `"errno \(n)"`, or a hash-mismatch message) — this
    /// pulls out a POSIX code when the detail happens to carry one so `ProblemReason.from(posix:)` can classify it;
    /// anything else (including no match) maps to `.other`, which is still reported with the raw system text.
    private static func posixCode(fromDetail detail: String?) -> Int32 {
        guard let detail, let range = detail.range(of: "errno ") else { return 0 }
        let digits = detail[range.upperBound...].prefix(while: \.isNumber)
        return Int32(digits) ?? 0
    }

    private func currentState(of id: UUID) -> JobState? {
        queue.jobs.first(where: { $0.id == id })?.state
    }

    private func currentJob(_ id: UUID) -> FileJob? {
        queue.jobs.first(where: { $0.id == id })
    }

    /// W6 (contract §2 "tốc độ/ETA = byte qua cửa sổ trượt 5 s"): `runtime.samples` keeps every progress tick from
    /// the last 5 real seconds (wall clock, not `elapsed` since the last sample — a slow filesystem can go a full
    /// second between callback ticks); the rate is total bytes moved across that whole window divided by the
    /// window's actual span, so a single huge tick right after a stall does not spike the reading the way the old
    /// per-tick EMA could. `ProcessInfo.processInfo.systemUptime` (monotonic) is used instead of `Date()` for the
    /// window math so a wall-clock adjustment mid-copy cannot corrupt it; `Date()` is still used for `lastProgressAt`
    /// (the "stalled" check only needs this process's own data, and `isProgressVisible` compares it with `Date()`).
    private func updateProgress(_ id: UUID, bytesDone: Int64, itemsDone: Int, bytesTotal: Int64, itemsTotal: Int) {
        queue.progress(id, bytesDone: bytesDone, itemsDone: itemsDone)
        guard let runtime = runtimes[id] else { return }
        if bytesDone > runtime.lastSampleBytes { runtime.lastProgressAt = Date() }
        runtime.lastSampleBytes = bytesDone
        let now = ProcessInfo.processInfo.systemUptime
        runtime.samples.append((t: now, bytes: bytesDone))
        let windowStart = now - 5
        // Keep one sample AT OR BEFORE `windowStart` (if any) as the window's anchor, plus everything newer — never
        // drop every sample just because the whole run so far is older than 5 s (a short copy must still get a rate
        // once it has ≥ 2 ticks, from its own start to now, not wait for a full 5 s window to accumulate).
        if let cutoff = runtime.samples.lastIndex(where: { $0.t < windowStart }) {
            runtime.samples.removeFirst(cutoff)
        }
        guard let oldest = runtime.samples.first, now - oldest.t > 0.2 else { return }
        let sample = Double(bytesDone - oldest.bytes) / (now - oldest.t)
        speed = max(sample, 0)
        eta = FileOperationRules.eta(bytesDone: bytesDone, bytesTotal: bytesTotal, bytesPerSecond: speed ?? 0)
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

    /// W6: records into the browser's own persistent `UndoJournal` (20 steps / 24 h, JSON off main) instead of the
    /// app-wide `ActionHistoryStore` — spec §9 "Thay `ActionHistoryStore` chỉ trong trình duyệt". `UndoItem.from`/`to`
    /// mean "undo moves FROM here TO here" for every kind except copy/duplicate, which have no natural pair (the
    /// created item has no "original location" to move back to) — those store `from: <created path>, to: ""` and
    /// `performUndo`/`performRedo` special-case `.copy`/`.duplicate` to trash-on-undo / refuse-on-redo accordingly.
    private func recordHistory(job: FileJob, runtime: Runtime) {
        let count = job.sources.count
        guard count > 0 else { return }
        let step: UndoStep
        switch job.kind {
        case .move:
            guard !runtime.movedPairs.isEmpty else { return }
            step = UndoStep(
                id: UUID(), kind: .move,
                items: runtime.movedPairs.map { pair in
                    UndoItem(from: pair.from, to: pair.to, inode: Self.fileIdentity(pair.from)?.inode,
                             size: Self.fileIdentity(pair.from)?.size, modified: Self.fileIdentity(pair.from)?.modified)
                },
                date: Date()
            )
        case .copy, .duplicate:
            guard !runtime.createdForUndo.isEmpty else { return }
            step = UndoStep(
                id: UUID(), kind: job.kind == .copy ? .copy : .duplicate,
                items: runtime.createdForUndo.map { path in
                    UndoItem(from: path, to: "", inode: Self.fileIdentity(path)?.inode,
                             size: Self.fileIdentity(path)?.size, modified: Self.fileIdentity(path)?.modified)
                },
                date: Date()
            )
        case .trash:
            // The browser knows the exact Trash URL `trashItem` produced for each source, so its own trash jobs CAN
            // be undone — a plain move back from that URL to the original path.
            guard !runtime.trashedPairs.isEmpty else { return }
            step = UndoStep(
                id: UUID(), kind: .trash,
                items: runtime.trashedPairs.map { pair in
                    UndoItem(from: pair.trashedAt, to: pair.original, inode: Self.fileIdentity(pair.trashedAt)?.inode,
                             size: Self.fileIdentity(pair.trashedAt)?.size, modified: Self.fileIdentity(pair.trashedAt)?.modified)
                },
                date: Date()
            )
        }
        undoJournal.pruned(now: Date())
        undoJournal.record(step, now: Date())
        Self.saveUndoJournal(undoJournal)
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

    // MARK: - W6: persistent UndoJournal (JSON, writes off main)

    /// Read once at launch (`init`) — `UndoJournal.decode(_:)` is the pure side's contract for turning missing/
    /// corrupt data into an empty journal, so a damaged file never crashes startup, it just starts fresh.
    private static func loadUndoJournal() -> UndoJournal {
        UndoJournal.decode(try? Data(contentsOf: undoJournalURL))
    }

    /// Every write after launch goes through `ioQueue` (a background serial queue), never the main thread — the
    /// value is captured before hopping off so the write sees a consistent snapshot even if `undoJournal` on the
    /// main actor changes again before this queue gets to run.
    private static func saveUndoJournal(_ journal: UndoJournal) {
        let data = journal.encoded()
        ioQueue.async {
            try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try? data.write(to: undoJournalURL, options: .atomic)
        }
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
