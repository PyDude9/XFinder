import Foundation

/// XF-T30 W3 — what the browser sidebar shows and in which order, the virtual locations (Recents, a tag) and their
/// path form for tabs and sessions. Pure, symlinked into the test package. Contract XF-T30-w3 §1. W3 builder (pure).
enum SidebarCategory: String, Codable, CaseIterable, Sendable {
    case recents, airDrop, favorites, iCloud, hardDisks, externalDisks, cloudStorage, connectedServers, bonjour, recentTags

    /// `fileBrowser.sidebar.<rawValue>` default (Bonjour off, as in Finder).
    var defaultVisible: Bool { self != .bonjour }
}

enum VirtualLocation: Equatable, Hashable, Sendable {
    case recents
    case tag(String)
    case allTags

    static let scheme = "xfinder-virtual://"
    /// `xfinder-virtual://recents`, `…/tag/<percent-encoded name>`, `…/all-tags`. W3 builder (pure): implement.
    var path: String { Self.scheme + "recents" }
    /// The inverse; nil for an ordinary path. W3 builder (pure): implement.
    static func parse(_ path: String) -> VirtualLocation? { nil }
}

enum LocationKind: String, Codable, CaseIterable, Sendable { case local, external, cloud, network }

enum SidebarSections {
    /// Section headers in display order for the given visibility and "Group Locations by type" option. W3 (pure).
    static func headers(visible: Set<SidebarCategory>, groupLocationsByType: Bool) -> [String] { [] }
}
