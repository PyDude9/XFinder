import Foundation

/// XF-T30 W8 — cloud providers as `~/Library/CloudStorage/<Provider>-<account>` folders (Google Drive per account, Dropbox,
/// OneDrive, Box…) plus iCloud Drive. Pure parsing, symlinked into the test package. W8 builder (pure): implement.
struct CloudProvider: Equatable, Hashable, Sendable {
    enum Kind: String, Sendable { case iCloud, googleDrive, dropbox, oneDrive, box, other }
    var kind: Kind
    var account: String?
    var displayName: String
    var rootPath: String
}

enum CloudProviders {
    /// One folder name under CloudStorage → provider (nil for names that are not provider roots).
    static func parse(folderName: String, root: String) -> CloudProvider? { nil }
    /// Whether `path` is inside any provider root (cloud rules apply).
    static func provider(containing path: String, in providers: [CloudProvider]) -> CloudProvider? { nil }
}
