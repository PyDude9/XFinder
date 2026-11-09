import Foundation

/// XF-T28 (2026-10-24) — the pure rules behind the file browser's copy/move/duplicate/trash queue: naming for
/// "Keep Both" and duplicate, same-volume vs. cross-volume strategy, the job state machine, the journal → recovery
/// report, and progress/ETA smoothing. Everything here is data in, data out — the actual `copyfile`/`FSEventStream`/
/// DiskArbitration work lives in `FileOperationQueue.swift` (AppKit side), which calls these rules at each decision
/// point so the decisions themselves have tests.
///
/// Measurements this file encodes (spec §1, M3 Pro, macOS 27.0.1, APFS): `copyfile` with
/// `COPYFILE_STATE_STATUS_CB` can be paused by blocking inside the callback (500 ms asked, 505 ms measured) and
/// cancelled with `COPYFILE_QUIT` → `ECANCELED` without leaving a half file — so "Pause" only has to be offered
/// while that callback is the thing running (the copy phase), never during verify or the trash step that follows a
/// cross-volume move. `copyfile(COPYFILE_ALL)` does **not** clone on APFS by itself (115 ms/256 MiB); only
/// `+COPYFILE_CLONE` does (0.16 ms) — so same-volume copies pass that flag, cross-volume ones cannot clone and copy
/// bytes instead. SHA-256 verify runs at essentially disk speed (2 360 MB/s vs. 2 256 MB/s for a byte compare, and a
/// positive control confirmed a single flipped byte is caught), so a cross-volume move always verifies by hash
/// before the source is trashed (Q-T28-4: XFinder has no undelete story for a hard delete, so the source goes to
/// Trash — never removed outright — even after a verified move).
enum FileOperationKind: String, Codable, Sendable {
    case copy, move, duplicate, trash
    /// XF-T30 W6 — merge one folder into another (`sources = [source folder]`, `destination` = folder merged into,
    /// `FileJob.mergePolicy` set). Runs through the queue like every other job (panel, pause, problems, undo).
    case merge
}

enum ConflictChoice: String, Codable, Sendable {
    case keepBoth, skip, replace, stop
}

enum MoveStrategy: Equatable, Sendable {
    case rename
    case cloneOrCopy
    case copyVerifyTrash
    case trash
}

enum JobState: String, Codable, Sendable {
    case waiting, running, pausing, paused, verifying, finishing, done, failed, cancelled
}

struct FileJob: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: FileOperationKind
    let sources: [String]
    let destination: String?
    var state: JobState
    var bytesDone: Int64
    var bytesTotal: Int64
    var itemsDone: Int
    var itemsTotal: Int
    var errorKey: String?
    var errorDetail: String?
    /// Only for `.merge`: how name collisions resolve. Optional so journals written before W6 still decode.
    var mergePolicy: MergePolicy?

    init(id: UUID, kind: FileOperationKind, sources: [String], destination: String?, mergePolicy: MergePolicy? = nil) {
        self.id = id
        self.kind = kind
        self.sources = sources
        self.destination = destination
        self.mergePolicy = mergePolicy
        self.state = .waiting
        self.bytesDone = 0
        self.bytesTotal = 0
        self.itemsDone = 0
        self.itemsTotal = 0
        self.errorKey = nil
        self.errorDetail = nil
    }

    var isActive: Bool {
        switch state {
        case .running, .pausing, .paused, .verifying, .finishing: return true
        case .waiting, .done, .failed, .cancelled: return false
        }
    }

    var isFinished: Bool {
        switch state {
        case .done, .failed, .cancelled: return true
        case .waiting, .running, .pausing, .paused, .verifying, .finishing: return false
        }
    }
}

struct FileJobQueue: Codable, Equatable, Sendable {
    private(set) var jobs: [FileJob] = []

    init() {}

    /// At most one job is ever active (spec §2.1.9 "một việc một lúc") — `isActive` is true for exactly 0 or 1 job.
    var active: FileJob? {
        jobs.first(where: { $0.isActive })
    }

    mutating func enqueue(_ job: FileJob) {
        jobs.append(job)
    }

    /// If nothing is active, the first `.waiting` job (queue order) becomes `.running` and its id is returned.
    /// A job that is merely `.paused` still counts as active, so pausing never lets a second job sneak in.
    @discardableResult
    mutating func startNextIfIdle() -> UUID? {
        guard active == nil else { return nil }
        guard let index = jobs.firstIndex(where: { $0.state == .waiting }) else { return nil }
        jobs[index].state = .running
        return jobs[index].id
    }

    @discardableResult
    mutating func pause(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running else { return false }
        jobs[index].state = .pausing
        return true
    }

    @discardableResult
    mutating func didPause(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .pausing else { return false }
        jobs[index].state = .paused
        return true
    }

    @discardableResult
    mutating func resume(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return false }
        switch jobs[index].state {
        case .paused, .pausing:
            jobs[index].state = .running
            return true
        default:
            return false
        }
    }

    @discardableResult
    mutating func cancel(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return false }
        switch jobs[index].state {
        case .waiting:
            jobs[index].state = .cancelled
            return true
        default:
            if jobs[index].isActive {
                jobs[index].state = .cancelled
                return true
            }
            return false
        }
    }

    /// Advances the copy-phase state machine: `running` → `verifying` → `finishing`. A job that is `.pausing` must
    /// not slip into `.verifying` — the pause request has to be honoured (become `.paused`) before verify starts,
    /// otherwise "Pause" during the last instant of a copy could silently turn into "keep going through verify".
    @discardableResult
    mutating func setPhase(_ id: UUID, _ state: JobState) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return false }
        if state == .verifying, jobs[index].state == .pausing { return false }
        jobs[index].state = state
        return true
    }

    mutating func finish(_ id: UUID, failedWith errorKey: String?, detail: String?) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let errorKey {
            jobs[index].state = .failed
            jobs[index].errorKey = errorKey
            jobs[index].errorDetail = detail
        } else {
            jobs[index].state = .done
        }
    }

    mutating func progress(_ id: UUID, bytesDone: Int64, itemsDone: Int) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].bytesDone = bytesDone
        jobs[index].itemsDone = itemsDone
    }

    /// "Pause all": only the one `running` job can actually be mid-copy, so only it moves to `.pausing`; every
    /// `.waiting` job is left exactly as is (there is nothing running in it to pause).
    mutating func pauseAll() {
        for index in jobs.indices where jobs[index].state == .running {
            jobs[index].state = .pausing
        }
    }

    mutating func resumeAll() {
        for index in jobs.indices where jobs[index].state == .paused || jobs[index].state == .pausing {
            jobs[index].state = .running
        }
    }

    /// "Chạy kế tiếp": moves a `.waiting` job to the front of the waiting group, so it is the one `startNextIfIdle`
    /// picks up next — without disturbing whatever is currently active or already finished ahead of it.
    @discardableResult
    mutating func runNext(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .waiting else { return false }
        let job = jobs.remove(at: index)
        let waitingStart = jobs.firstIndex(where: { $0.state == .waiting }) ?? jobs.count
        jobs.insert(job, at: waitingStart)
        return true
    }

    @discardableResult
    mutating func moveUp(_ id: UUID) -> Bool {
        let waitingIndices = jobs.indices.filter { jobs[$0].state == .waiting }
        guard let position = waitingIndices.firstIndex(where: { jobs[$0].id == id }), position > 0 else { return false }
        let a = waitingIndices[position]
        let b = waitingIndices[position - 1]
        jobs.swapAt(a, b)
        return true
    }

    @discardableResult
    mutating func moveDown(_ id: UUID) -> Bool {
        let waitingIndices = jobs.indices.filter { jobs[$0].state == .waiting }
        guard let position = waitingIndices.firstIndex(where: { jobs[$0].id == id }), position < waitingIndices.count - 1 else { return false }
        let a = waitingIndices[position]
        let b = waitingIndices[position + 1]
        jobs.swapAt(a, b)
        return true
    }

    mutating func clearFinished() {
        jobs.removeAll(where: { $0.isFinished })
    }
}

enum JournalPhase: String, Codable, Sendable {
    case started, copied, verified, trashing, sourceRemoved, done
}

struct JournalEntry: Codable, Equatable, Sendable {
    let job: UUID
    let kind: FileOperationKind
    let source: String
    let destination: String?
    var phase: JournalPhase
    let at: Date
}

struct RecoveryItem: Equatable, Sendable {
    let source: String
    let destination: String?
    let messageKey: String
}

enum FileOperationRules {
    // MARK: Naming

    /// Finder's "Keep Both": "Report.pdf" → "Report 2.pdf", "Report 3.pdf"… — the number always counts from the
    /// plain name, so if "Report 2.pdf" is already taken the next try is "Report 3.pdf", never "Report 2 2.pdf".
    /// A name with no extension (or a folder) gets the suffix with no extension to preserve; a dotfile like
    /// ".zshrc" has no extension by this rule either, so it becomes ".zshrc 2". Only the last extension counts:
    /// "a.tar.gz" → "a.tar 2.gz".
    static func keepBothName(for name: String, existing: Set<String>) -> String {
        numberedName(for: name, existing: existing, suffix: nil)
    }

    /// A name for something NEW ("untitled folder", "untitled.txt", "Report alias"): the name itself when nothing has it,
    /// else Keep Both's numbering. `keepBothName` never returns the plain name — it is for a conflict, where the plain
    /// name is taken by definition — so New Folder used to create "untitled folder 2" in an empty folder (measured in the
    /// Atlas helper 2026-11-09 with New File: "untitled 2.txt" with no "untitled.txt" present).
    static func freshName(for name: String, existing: Set<String>) -> String {
        existing.contains(name) ? keepBothName(for: name, existing: existing) : name
    }

    /// Finder's ⌘D: "Report.pdf" → "Report copy.pdf", "Report copy 2.pdf"… — duplicating an already-duplicated name
    /// keeps counting from the same base ("Report copy.pdf" → "Report copy 2.pdf", not "Report copy copy.pdf").
    static func duplicateName(for name: String, existing: Set<String>) -> String {
        numberedName(for: name, existing: existing, suffix: "copy")
    }

    /// Shared engine for both naming rules above. `suffix` is inserted once (if not already present right before a
    /// trailing number) and then a counter is appended/incremented until the name is free. For `duplicateName`, a
    /// base that is ALREADY a numbered duplicate ("Report copy 2") is recognized by `existingSuffixNumber` so the
    /// search starts at the NEXT number ("Report copy 3") instead of stacking a second "copy" token onto it
    /// ("Report copy 2 copy") — real Finder keeps counting forward from a duplicate's own number, it never resets
    /// back down to the bare "<stem> copy" even when that bare name happens to be free.
    private static func numberedName(for name: String, existing: Set<String>, suffix: String?) -> String {
        let (base, ext) = splitExtension(name)
        let stem: String
        let startNumber: Int
        if let suffix {
            if let (strippedStem, existingNumber) = existingSuffixNumber(suffix, in: base) {
                stem = strippedStem
                startNumber = existingNumber + 1
            } else {
                stem = base.hasSuffix(" \(suffix)") || base == suffix ? base : "\(base) \(suffix)"
                startNumber = 2
            }
        } else {
            stem = base
            startNumber = 2
        }
        func candidate(_ n: Int?) -> String {
            let withNumber = n.map { "\(stem) \($0)" } ?? stem
            return ext.isEmpty ? withNumber : "\(withNumber).\(ext)"
        }
        // First attempt: the bare suffix (no number) — this is what Finder offers on the very first duplicate/keep-both.
        // Skipped when `base` was already a numbered duplicate (startNumber > 2): the bare name was superseded the
        // moment a numbered copy of it was made, so offering it again would be a step backwards, not a new name.
        if suffix != nil, startNumber == 2 {
            let first = candidate(nil)
            if !existing.contains(first) { return first }
        }
        var n = startNumber
        while existing.contains(candidate(n)) {
            n += 1
        }
        return candidate(n)
    }

    /// Recognizes `"<stem> <suffix> <digits>"` (e.g. `suffix` = "copy", base = "Report copy 2") and returns the stem
    /// WITH the suffix token still attached ("Report copy") plus the parsed trailing number, so the caller can
    /// append " <n+1>" directly to continue counting. Returns nil for a bare `"<stem> <suffix>"` (no number yet —
    /// handled by the normal "insert suffix, start at 2" path) or for a base that does not contain the suffix token.
    private static func existingSuffixNumber(_ suffix: String, in base: String) -> (stem: String, number: Int)? {
        guard let range = base.range(of: " \(suffix) ", options: .backwards) else { return nil }
        let digits = base[range.upperBound...]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let number = Int(digits) else { return nil }
        return (String(base[base.startIndex..<range.upperBound].dropLast()), number)
    }

    /// Splits off the last extension only: "a.tar.gz" → ("a.tar", "gz"); ".zshrc" → (".zshrc", "") because a name
    /// that starts with "." and has no other dot is a dotfile, not "<empty> + zshrc".
    private static func splitExtension(_ name: String) -> (base: String, ext: String) {
        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else { return (name, "") }
        let base = String(name[name.startIndex..<dotIndex])
        let ext = String(name[name.index(after: dotIndex)...])
        return ext.isEmpty ? (name, "") : (base, ext)
    }

    // MARK: Nesting

    /// Path containment by normalized path components, not string prefix — "/a/bc" is not inside "/a/b" even though
    /// "/a/bc" has the string "/a/b" as a prefix.
    static func isInside(_ path: String, ancestor: String) -> Bool {
        let pathParts = normalizedComponents(path)
        let ancestorParts = normalizedComponents(ancestor)
        guard ancestorParts.count < pathParts.count else { return false }
        return Array(pathParts.prefix(ancestorParts.count)) == ancestorParts
    }

    private static func normalizedComponents(_ path: String) -> [String] {
        (path as NSString).standardizingPath.split(separator: "/").map(String.init)
    }

    /// Copying/moving a folder into itself (or into one of its own children) must be blocked before the job is even
    /// queued, not discovered mid-copy. Returns the first offending source, or nil if every source is fine.
    static func nestingViolation(sources: [String], destination: String) -> String? {
        let destinationStandard = (destination as NSString).standardizingPath
        for source in sources {
            let sourceStandard = (source as NSString).standardizingPath
            if sourceStandard == destinationStandard || isInside(destinationStandard, ancestor: sourceStandard) {
                return source
            }
        }
        return nil
    }

    // MARK: Strategy

    /// Same volume: a copy can be a cheap APFS clone (`COPYFILE_CLONE`, measured 0.16 ms vs. 115 ms/256 MiB without
    /// it) and a move is a plain rename. Cross volume: a copy has to copy bytes, and a move has to copy bytes, verify
    /// by hash, then trash the source (never delete it outright — Q-T28-4) because there is no atomic cross-volume
    /// rename. Duplicate and trash do not depend on the destination volume at all.
    static func strategy(kind: FileOperationKind, sameVolume: Bool) -> MoveStrategy {
        switch kind {
        case .trash:
            return .trash
        case .duplicate, .copy:
            return .cloneOrCopy
        case .move, .merge:
            return sameVolume ? .rename : .copyVerifyTrash
        }
    }

    // MARK: Conflict dialog

    /// "Newer" with a timestamp tolerance: ordinary APFS/HFS+ comparisons need at least 1 s of separation to count,
    /// but FAT/exFAT only stores 2 s resolution, so a tolerance below that would call two writes "different" when
    /// the filesystem itself cannot tell them apart.
    static func isNewer(_ a: Date, than b: Date, coarseTimestamps: Bool) -> Bool {
        let tolerance: TimeInterval = coarseTimestamps ? 2 : 1
        return a.timeIntervalSince(b) >= tolerance
    }

    /// "Replace" is only offered file-for-file. Replacing a folder with a file (or vice versa) silently destroys a
    /// whole tree the user may not have looked inside, so the dialog only offers Keep Both / Skip for that case —
    /// matching the "ca hỏng" row in spec §4.
    static func replaceAllowed(sourceIsFolder: Bool, destinationIsFolder: Bool) -> Bool {
        !sourceIsFolder && !destinationIsFolder
    }

    // MARK: Recovery

    /// Pause is only safe while the `copyfile` status callback is the thing running — that is the one place the
    /// measurement (§1) showed blocking is observed and clean. Once a job has moved to `.verifying` (hashing) or
    /// `.finishing` (trashing the source after a verified cross-volume move), there is no callback to block inside,
    /// so the control must already be disabled rather than accept a pause request that cannot be honoured in time.
    static func canPause(_ state: JobState) -> Bool {
        state == .running
    }

    static func smoothedSpeed(previous: Double?, sample: Double) -> Double {
        guard let previous else { return sample }
        let alpha = 0.2
        return alpha * sample + (1 - alpha) * previous
    }

    static func eta(bytesDone: Int64, bytesTotal: Int64, bytesPerSecond: Double) -> TimeInterval? {
        guard bytesPerSecond > 0 else { return nil }
        // `&-` instead of `-`: a caller passing malformed byte counts (e.g. a negative `bytesDone` from a corrupted
        // progress update) must not crash the whole queue with an Int64 overflow trap — it should just fail the
        // "remaining > 0" guard below like any other nonsensical input.
        let remaining = bytesTotal &- bytesDone
        guard remaining > 0 else { return nil }
        return Double(remaining) / bytesPerSecond
    }

    /// Reduces a journal (one append-only log, possibly interleaved across jobs) to one recovery row per
    /// (job, source) that did not reach `.done` — "mới nhất" means the latest entry **in append order**, not by
    /// `at` (two entries can share a timestamp at clock resolution, and the log is only ever appended to, so array
    /// order already is chronological order). A `.sourceRemoved` tail means the whole operation completed in every
    /// way that matters (the final `.done` entry may simply not have been written before the process died), so it
    /// is dropped rather than reported as something to check.
    static func recoveryReport(_ entries: [JournalEntry]) -> [RecoveryItem] {
        struct Key: Hashable { let job: UUID; let source: String }
        var latest: [Key: JournalEntry] = [:]
        var order: [Key] = []
        for entry in entries {
            let key = Key(job: entry.job, source: entry.source)
            if latest[key] == nil { order.append(key) }
            latest[key] = entry
        }
        var items: [RecoveryItem] = []
        for key in order {
            guard let entry = latest[key] else { continue }
            guard let messageKey = recoveryMessageKey(for: entry.phase) else { continue }
            items.append(RecoveryItem(source: entry.source, destination: entry.destination, messageKey: messageKey))
        }
        return items
    }

    /// One L10n key (the Vietnamese source sentence itself, per the repo's string convention) per unfinished phase.
    /// `.done` and `.sourceRemoved` need no follow-up: `.sourceRemoved` means the risky step (deleting/trashing the
    /// original after a verified copy) already happened, so nothing is still "in flight".
    private static func recoveryMessageKey(for phase: JournalPhase) -> String? {
        switch phase {
        case .started: return "Có thể còn tệp chép dở ở đích"
        case .copied: return "Bản sao chưa được kiểm"
        case .verified: return "Bản gốc vẫn còn ở chỗ cũ"
        case .trashing: return "Bản gốc có thể đã vào Thùng rác — kiểm tra trước khi coi là mất"
        case .sourceRemoved, .done: return nil
        }
    }

    // MARK: Compress (XF-T30 W6 — spec §4 / R11–R16)

    /// Single-item compress: append `.zip` to the FULL original name, extension and all — "notes.txt" becomes
    /// "notes.txt.zip" (R11), never replacing the original extension the way a plain rename-the-extension approach
    /// would. Multi-item compress uses the generic "Archive.zip", "Archive 2.zip"… scheme (R12), sharing the same
    /// counting rule as Keep Both/Duplicate (first try bare, then numbered from 2, never doubled).
    static func zipName(for selection: [String], existing: Set<String>) -> String {
        if selection.count == 1, let only = selection.first {
            let full = "\(only).zip"
            guard existing.contains(full) else { return full }
            // A single-item name collision (rare: compressing the same item twice into the same folder) falls back
            // to the same numbered scheme Keep Both uses, rooted at the full "<name>.zip" so the thing being counted
            // is the archive, not the original file's own extension.
            return numberedZipName(base: full, existing: existing)
        }
        return numberedZipName(base: "Archive.zip", existing: existing)
    }

    /// Shared counting engine for `zipName`'s collision fallback: "Archive.zip" → "Archive 2.zip" → "Archive 3.zip"…
    /// by inserting the number directly before the LAST extension, matching `keepBothName`'s "only the last
    /// extension counts" rule so "Archive.tar.zip" would number as "Archive.tar 2.zip", not "Archive 2.tar.zip".
    private static func numberedZipName(base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        let (stem, ext) = splitExtension(base)
        var n = 2
        func candidate(_ n: Int) -> String { ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)" }
        while existing.contains(candidate(n)) { n += 1 }
        return candidate(n)
    }

    /// A pure description of "build off to the side, validate, only then reveal" (R13): the caller builds the
    /// archive at `stagingPath`, lists/opens it to confirm it is not corrupt, and only on success moves it to
    /// `finalPath` — a failed or interrupted build leaves only the staging file behind, never a partial `.zip` at
    /// the name the user expects to see. This type carries no behavior itself (AppKit side does the actual
    /// `NSFileCoordinator`/`ditto` work); it exists so the "never reveal before validated" contract has a named,
    /// testable shape instead of being an implicit convention of the imperative code.
    struct ZipBuildPlan: Equatable, Sendable {
        var stagingPath: String
        var finalPath: String
    }

    /// `stagingPath` lives in the SAME directory as `finalPath` (not a shared temp directory) so the final move is a
    /// same-volume rename — the one move in this whole plan that must be atomic and cannot itself fail partway
    /// with a corrupt result sitting at the destination name.
    static func zipBuildPlan(finalPath: String) -> ZipBuildPlan {
        let directory = (finalPath as NSString).deletingLastPathComponent
        let name = (finalPath as NSString).lastPathComponent
        let staging = (directory as NSString).appendingPathComponent(".\(name).xfinder-building-\(UUID().uuidString)")
        return ZipBuildPlan(stagingPath: staging, finalPath: finalPath)
    }

    /// Compress is disabled (R15) for a selection that is EXACTLY one existing `.zip` file (compressing an archive
    /// into another archive of the same thing is not useful), or when ANY selected item is a cloud placeholder that
    /// has not been downloaded yet (nothing is pulled from the cloud just to zip it).
    static func compressDisabled(selection: [(path: String, isCloudPlaceholder: Bool)]) -> Bool {
        if selection.contains(where: { $0.isCloudPlaceholder }) { return true }
        if selection.count == 1, let only = selection.first {
            return (only.path as NSString).pathExtension.lowercased() == "zip"
        }
        return false
    }

    // MARK: Trash-resident item gating (XF-T30 W6 — spec §13 / changelog 1.0.4 fix)

    /// Share, Duplicate, Compress, and Make Alias must be disabled for anything already sitting in the Trash (the
    /// bug FileOctopus itself had to fix in 1.0.4) — none of those verbs make sense for a trashed item, and running
    /// them risks operating on a path that is about to be permanently reclaimed by the system.
    enum TrashGatedCommand: Sendable { case share, duplicate, compress, makeAlias }

    static func isDisabledForTrashedItem(_ command: TrashGatedCommand, isInTrash: Bool) -> Bool {
        isInTrash
    }

    // MARK: New Folder with Selection (XF-T30 W6 — spec §3 / R7)

    /// "Thư mục mới chứa mục" (Finder's "New Folder With Items/Selection"): a bare name when nothing by that name
    /// exists yet at the destination, else the familiar numbered fallback — sharing `keepBothName`'s counting
    /// scheme so a second "New Folder with Selection" in the same place becomes "Thư mục mới chứa mục 2", not a
    /// silent collision. `baseName` defaults to the Vietnamese source string (the view passes `L10n.t(...)` through
    /// in the live UI; the default lets pure tests exercise the counting logic without a localization dependency).
    static func newFolderWithSelectionName(existing: Set<String>, baseName: String = "Thư mục mới chứa mục") -> String {
        freshName(for: baseName, existing: existing)
    }
}
