import Foundation

/// A bounded metadata-only projection; the shared listing remains the source of truth.
enum BrowserDownloadsRules {
    static let limit = 20
    static func recent(_ entries: [DirectoryEntry]) -> [DirectoryEntry] {
        entries.filter { !$0.isHidden }.sorted {
            $0.modified != $1.modified ? $0.modified > $1.modified : $0.path < $1.path
        }.prefix(limit).map { $0 }
    }
}
