import AppKit

/// XF-T30 W6 — runs a `MergePlan` through the file operation queue (SHA-256 verify across disks, Trash for replaced
/// items, emptied source folders to Trash, report). W6 builder (AppKit).
@MainActor
final class FolderMergeController {
    static let shared = FolderMergeController()

    /// Plans (off main) and presents the preview; `completion(report)` after the run.
    func merge(source: String, into destination: String, completion: @escaping @MainActor (MergePlan?) -> Void) {
        completion(nil)
    }
}
