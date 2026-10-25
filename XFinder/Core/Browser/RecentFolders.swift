import Foundation

/// XF-T30 W3 — Go ▸ Recent Folders: the last 10 distinct folders opened in any pane, newest first, local only.
/// Pure, symlinked into the test package. W3 builder (pure): implement.
struct RecentFolders: Codable, Equatable, Sendable {
    static let limit = 10
    private(set) var paths: [String] = []

    /// Moves `path` to the top (deduplicated), keeps at most `limit`; virtual locations are not recorded.
    mutating func note(_ path: String) {}
    mutating func clear() { paths = [] }
    /// Drops folders that no longer exist.
    func existing(_ exists: (String) -> Bool) -> [String] { paths.filter(exists) }
}
