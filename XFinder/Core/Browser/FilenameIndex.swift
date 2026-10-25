import Foundation

/// XF-T30 W5a — the opt-in filename index for approved folders (FileOctopus `FilenameIndexStore` / `ScopedIndexer` /
/// `EventIntake`): SQLite WAL on disk, a new generation per rebuild, FSEvents with a saved `last_event_id` cursor so a
/// relaunch catches up instead of rescanning. Runs only while a browser window is open. Contract
/// docs/specs/XF-T30-w5a-contract.md §3. W5a builder (N5): implement.
actor FilenameIndex {
    static let shared = FilenameIndex()

    struct Hit: Equatable, Sendable {
        let path: String
        let name: String
        let tier: MatchTier
        let score: Int
        let size: Int64
        let modified: Date
        let isFolder: Bool
    }

    /// `~/Library/Application Support/XFinder/Browser/Search/names.sqlite`.
    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder/Browser/Search/names.sqlite")
    }

    /// The approved roots changed: start crawls for new ones, drop removed ones (their rows too), honour `paused`.
    func setRoots(_ roots: [IndexRoot]) {}

    /// Status by root id.
    func status() -> [String: IndexRootStatus] { [:] }

    /// Tiered name search over roots inside `folders` (nil = every root). At most `limit`.
    func search(_ query: String, within folders: [String]?, limit: Int) -> [Hit] { [] }

    func setPaused(_ rootID: String, _ paused: Bool) {}
    func rebuild(_ rootID: String) {}
    /// Derived data only: every root stays approved and re-indexes.
    func eraseAll() {}

    /// No browser window open: stop the FSEvents streams, keep the cursors.
    func suspend() {}
    /// A browser window opened: catch up from the cursors.
    func resume() {}
}
