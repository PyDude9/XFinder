import AppKit
import Observation

/// XF-T30 W2 — Finder tags, Date Last Opened and the default application of files, read in the background in batches
/// and cached (LRU 20 000). `version` changes whenever a batch lands so views can refresh. W2 builder (reader).
@MainActor @Observable
final class FileMetadataCache {
    static let shared = FileMetadataCache()
    private(set) var version = 0

    func tags(for path: String) -> [FinderTag]? { nil }
    func lastOpened(for path: String) -> Date? { nil }
    func appName(for path: String) -> String? { nil }
    /// Queues a background read for `paths` (only what is missing).
    func prefetch(_ paths: [String], tags: Bool, lastOpened: Bool, appName: Bool) {}
    func purge() {}
}
