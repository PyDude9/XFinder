import Foundation

/// XF-T30 W3 — what the browser sidebar shows and in which order, the virtual locations (Recents, a tag) and their
/// path form for tabs and sessions. Pure, symlinked into the test package. Contract XF-T30-w3 §1. W3 builder (pure).
enum SidebarCategory: String, Codable, CaseIterable, Sendable {
    case recents, airDrop, favorites, iCloud, hardDisks, externalDisks, cloudStorage, connectedServers, bonjour, recentTags

    /// `fileBrowser.sidebar.<rawValue>` default (Bonjour off, as in Finder).
    var defaultVisible: Bool { self != .bonjour }
}

/// A non-file-system location that still needs a stable, percent-encoded path string so it can be stored in a tab's
/// `path`, round-tripped through a session snapshot, and recognised again on restore (`BrowserWindowModel` routes a
/// path that parses as one of these through `VirtualLocations.list` instead of `DirectoryReader`).
enum VirtualLocation: Equatable, Hashable, Sendable {
    case recents
    case tag(String)
    case allTags

    static let scheme = "xfinder-virtual://"
    private static let tagPrefix = "tag/"
    private static let allTagsComponent = "all-tags"

    /// `xfinder-virtual://recents`, `xfinder-virtual://tag/<percent-encoded name>`, `xfinder-virtual://all-tags`.
    /// The tag name is percent-encoded with `.urlPathAllowed` (not a whole-URL encoder) so a name containing `/`
    /// (a tag can be any string the person typed into Finder) never reads back as an extra path component.
    var path: String {
        switch self {
        case .recents:
            return Self.scheme + "recents"
        case .tag(let name):
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return Self.scheme + Self.tagPrefix + encoded
        case .allTags:
            return Self.scheme + Self.allTagsComponent
        }
    }

    /// The inverse of `path`; nil for an ordinary file-system path (including one that merely starts with the scheme
    /// but names nothing this enum recognises — treated as "not a virtual location" rather than crashing a caller).
    static func parse(_ path: String) -> VirtualLocation? {
        guard path.hasPrefix(scheme) else { return nil }
        let rest = String(path.dropFirst(scheme.count))
        if rest == "recents" { return .recents }
        if rest == allTagsComponent { return .allTags }
        if rest.hasPrefix(tagPrefix) {
            let encodedName = String(rest.dropFirst(tagPrefix.count))
            guard !encodedName.isEmpty, let name = encodedName.removingPercentEncoding, !name.isEmpty else { return nil }
            return .tag(name)
        }
        return nil
    }
}

enum LocationKind: String, Codable, CaseIterable, Sendable { case local, external, cloud, network }

enum SidebarSections {
    /// Section headers in display order, for the categories currently visible (`SidebarCategory.defaultVisible`/
    /// Settings ▸ Sidebar) and whether "Nhóm Vị trí theo loại" is on. Every string is an L10n store key — the caller
    /// resolves it with `L10n.t(_:)`; this file stays Foundation-only so it can be symlinked into the test package.
    ///
    /// Order (contract §1): Gần đây, AirDrop, (Mục ưa thích — rendered by the view from `SidebarLayout`, not listed
    /// here: its header is always shown once favourites exist, independent of this category list), iCloud, Vị trí
    /// (one header, or four sub-headers — Cục bộ / Ngoài / Đám mây / Mạng — when grouped by type and that kind's own
    /// category is visible), Máy tính lân cận (Bonjour), Thẻ + "Tất cả thẻ…" at the end of Thẻ. A category entirely
    /// hidden contributes no header (hiding a row never deletes its data — CLAUDE.md — it just stops drawing it here).
    ///
    /// The Vị trí "Mạng" sub-header (connected servers, `.connectedServers`) and the Bonjour section are two
    /// different things — already-mounted network shares versus nearby computers discovered but not connected — so
    /// they use two distinct header strings; reusing "Mạng" for both would render as two adjacent, indistinguishable
    /// "Mạng" headers with different rows under them whenever both are visible at once.
    static func headers(visible: Set<SidebarCategory>, groupLocationsByType: Bool) -> [String] {
        var result: [String] = []

        if visible.contains(.recents) { result.append("Gần đây") }
        if visible.contains(.airDrop) { result.append("AirDrop") }
        if visible.contains(.iCloud) { result.append("iCloud Drive") }

        let locationCategories: [SidebarCategory] = [.hardDisks, .externalDisks, .cloudStorage, .connectedServers]
        let anyLocationVisible = locationCategories.contains { visible.contains($0) }
        if anyLocationVisible {
            if groupLocationsByType {
                if visible.contains(.hardDisks) { result.append("Cục bộ") }
                if visible.contains(.externalDisks) { result.append("Ngoài") }
                if visible.contains(.cloudStorage) { result.append("Đám mây") }
                if visible.contains(.connectedServers) { result.append("Mạng") }
            } else {
                result.append("Vị trí")
            }
        }

        if visible.contains(.bonjour) { result.append("Máy tính lân cận") }
        if visible.contains(.recentTags) {
            result.append("Thẻ")
            result.append("Tất cả thẻ…")
        }

        return result
    }
}
