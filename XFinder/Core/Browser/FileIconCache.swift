import AppKit

/// XF-T28 cluster A — STUB (contract: docs/specs/XF-T28-ui-contract.md).
@MainActor final class FileIconCache {
    static let shared = FileIconCache()
    func icon(for entry: DirectoryEntry) -> NSImage { NSWorkspace.shared.icon(forFile: entry.path) }
    func icon(forPath path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
    func kindName(for entry: DirectoryEntry) -> String { entry.ext }
    func thumbnail(forPath path: String, side: CGFloat, scale: CGFloat, completion: @escaping @MainActor (NSImage?) -> Void) { completion(nil) }
    func purge() {}
}
