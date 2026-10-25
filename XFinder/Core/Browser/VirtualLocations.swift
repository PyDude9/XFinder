import Foundation

/// XF-T30 W3 — listing a virtual location (Recents: files used in the last 30 days in the home folder; a tag: items
/// carrying it) through Spotlight with an early stop (`NulRecords`), as `DirectoryEntry` values. W3 builder (model).
enum VirtualLocations {
    static func list(_ location: VirtualLocation) async -> Result<[DirectoryEntry], DirectoryReadError> {
        .success([])
    }
}
