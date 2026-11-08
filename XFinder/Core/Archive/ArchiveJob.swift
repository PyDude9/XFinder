import Foundation

/// The session's record of one extraction batch: what was reviewed, what happened, and what may be
/// deleted afterwards.
///
/// Why a separate type (spec §4.7, §7): the page used to hold one untracked `Task`, an `okCount` Int
/// and a log of strings. That cannot express "archive 2 of 3 completed, archive 3 failed and is
/// recoverable, archive 1 was cancelled untouched", and it is how `try?` came to hide a Trash failure
/// while the button still emptied the selection. Everything here is a value that a test can assert on.
enum ArchiveJob {

    /// One archive's path through the batch. `completed` means **fully** placed — the only state that
    /// may authorize deleting the source archive (Boss approval point 6).
    ///
    /// There is deliberately no "staged" case: the review is a separate value (`ArchiveReview`) held by
    /// the page, and a case nothing can produce or read is a claim the code does not make.
    enum Outcome: Equatable {
        /// Not started yet, or stopped before placing anything.
        case untouched
        case cancelledBeforePlacement
        case completed(outputs: [URL], renamed: [String])
        /// Some outputs exist and others do not: never reported as success.
        case partial(placed: [URL], failed: [String], recoveryRoot: URL?)
        case rejected(ArchiveRunner.Failure)

        var isCompleted: Bool { if case .completed = self { return true }; return false }
    }

    /// What "Kiểm tra" shows before anything is written (spec §4.5). Deliberately no percentage and no
    /// invented time: every number here is either counted or measured, never estimated for comfort.
    struct ArchiveReview: Equatable, Hashable {
        var archive: URL
        var destination: URL
        var entryCount: Int
        /// Declared payload, i.e. the archive's own claim — labelled as such in the page.
        var declaredBytes: Int64
        var availableBytes: Int64?
        /// Room the plan needs, including the operational reserve.
        var requiredBytes: Int64
        var conflicts: [String]
        var keepsBothRenames: [String]
        var refusals: [ArchiveSafetyRules.Reason]

        var isExtractable: Bool { refusals.isEmpty }

        /// The one sentence the page can print instead of a wall of numbers.
        var capacityVerdict: CapacityVerdict {
            guard let available = availableBytes else { return .unknown }
            return available >= requiredBytes ? .fits : .doesNotFit(short: requiredBytes - available)
        }

        enum CapacityVerdict: Equatable, Hashable {
            case fits
            case doesNotFit(short: Int64)
            /// Unknown capacity is blocked, never treated as infinite (spec §6).
            case unknown
        }
    }

    /// Build a review from an accepted inspection plus what is already in the destination.
    ///
    /// `rules` is injected only where the runtime could not be reached (tests); production passes the
    /// verdict `ArchiveSafetyRules` already computed, so the review can never disagree with the gate
    /// that actually refuses extraction.
    static func review(archive: URL, destination: URL, manifest: [ArchiveManifestEntry],
                       declaredBytes: Int64, availableBytes: Int64?,
                       requiredBytes: Int64, conflicts: [String],
                       keepsBothRenames: [String] = [],
                       refusals: [ArchiveSafetyRules.Reason] = []) -> ArchiveReview {
        ArchiveReview(archive: archive, destination: destination, entryCount: manifest.count,
                      declaredBytes: declaredBytes, availableBytes: availableBytes,
                      requiredBytes: requiredBytes, conflicts: conflicts,
                      keepsBothRenames: keepsBothRenames, refusals: refusals)
    }

    // MARK: Destination choice

    /// A destination the page must refuse rather than guess.
    ///
    /// Spec §4.2: "A custom destination is required when custom is selected: do not silently fall back
    /// to the source folder." The old helper fell back to `src.deletingLastPathComponent()`, which
    /// extracts next to the archive while the UI says "Thư mục tùy chọn" — a different folder than the
    /// one on screen. Returning the problem as a value keeps the button and the note in agreement.
    enum DestinationProblem: Equatable {
        case customFolderNotChosen

        var messageKey: String {
            switch self {
            case .customFolderNotChosen: return "Chưa chọn thư mục đích: hãy chọn một thư mục trước khi giải nén."
            }
        }
    }

    /// nil when the destination is usable. `isCustom` is passed rather than inferred so a caller cannot
    /// forget which mode it is in.
    static func destinationProblem(isCustom: Bool, folder: URL?) -> DestinationProblem? {
        isCustom && folder == nil ? .customFolderNotChosen : nil
    }

    // MARK: Source deletion ("Xóa file nén gốc", Boss approval point 6)

    /// The archives the delete action may touch: only those whose extraction **completed in this run**.
    ///
    /// Today's button trashes every selected source even when the run failed, and a `try?` hides the
    /// per-file error. Restricting the candidate list is the fix, and it is a pure function so the
    /// restriction cannot drift from the button.
    static func deletableSources(outcomes: [(archive: URL, outcome: Outcome)]) -> [URL] {
        outcomes.filter { $0.outcome.isCompleted }.map(\.archive)
    }

    /// What a delete attempt actually did, per file. Nothing here is a hard delete: only Trash.
    struct DeletionReport: Equatable {
        var trashed: [URL] = []
        /// (source, reason) — the user sees every name that stayed, with why.
        var failed: [(URL, String)] = []

        var isComplete: Bool { failed.isEmpty }

        static func == (lhs: DeletionReport, rhs: DeletionReport) -> Bool {
            lhs.trashed == rhs.trashed
                && lhs.failed.count == rhs.failed.count
                && zip(lhs.failed, rhs.failed).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
    }

    /// Trash each candidate, collecting per-file failures instead of `try?`.
    ///
    /// `trash` is injected so the failure path is testable: a real Trash failure cannot be produced on
    /// demand, and a test that only ever sees success would pin nothing. Trash, never `removeItem`:
    /// the archive is the user's own file and the action is reversible by design.
    static func trashSources(_ sources: [URL],
                             trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> DeletionReport {
        var report = DeletionReport()
        for source in sources {
            do {
                try trash(source)
                report.trashed.append(source)
            } catch {
                report.failed.append((source, "\(error)"))
            }
        }
        return report
    }

    /// The confirmation the page must show before trashing anything: the exact names, and **Cancel as
    /// the default button** (Boss approval point 6). Returned as data so the wording is testable.
    static func deleteConfirmation(names: [String]) -> (title: String, detail: String, defaultsToCancel: Bool) {
        let shown = names.prefix(6).joined(separator: "\n") + (names.count > 6 ? "\n…" : "")
        return (title: "\(names.count)\(L10n.t(" tệp nén gốc sẽ vào Thùng rác."))",
                detail: shown,
                defaultsToCancel: true)
    }
}
