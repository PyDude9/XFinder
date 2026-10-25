import Foundation

/// XF-T30 W3 — Go ▸ Recent Folders: the last 10 distinct folders opened in any pane, newest first, local only
/// (`fileBrowser.recentFolders`, `BrowserSettings` is the ONE reader/writer). Pure, symlinked into the test package.
///
/// FileOctopus spec (`spec-productivity.md` §4): fixed MRU-10, "Clear Menu" wipes the whole list, "kept on this Mac
/// only" — `RecentFolders` itself has no network/sync awareness; that guarantee just falls out of it being plain
/// `UserDefaults` JSON like every other `fileBrowser.*` key, nothing here opts it into iCloud sync.
struct RecentFolders: Codable, Equatable, Sendable {
    static let limit = 10
    private(set) var paths: [String] = []

    /// Moves `path` to the top (deduplicated — reopening an already-listed folder re-bumps it, the FileOctopus guide
    /// leaves this unspecified but it is the only reading consistent with "the last ten folders you opened"), keeps
    /// at most `limit` by dropping the oldest; a virtual location (`VirtualLocation.parse(path) != nil`) is never
    /// recorded — Go ▸ Recent Folders is real folders only, same rule `BrowserWindowModel` already applies to history.
    mutating func note(_ path: String) {
        guard !path.isEmpty, VirtualLocation.parse(path) == nil else { return }
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.limit {
            paths.removeLast(paths.count - Self.limit)
        }
    }

    /// "Clear Menu".
    mutating func clear() { paths = [] }

    /// Drops folders that no longer exist, keeping the remaining order (newest first) — called before the Go menu
    /// draws the list, so a folder deleted or on an unmounted volume never shows as a dead row the person can click.
    func existing(_ exists: (String) -> Bool) -> [String] { paths.filter(exists) }
}
