import AppKit
import Observation

/// XF-T30 W3 — the live sources of the sidebar: volumes (mount/unmount/rename notifications), cloud storage folders,
/// iCloud Drive, connected servers, Bonjour computers (only while that row is on). W3 builder (AppKit).
@MainActor @Observable
final class SidebarSources {
    static let shared = SidebarSources()

    struct Volume: Equatable, Identifiable {
        var id: String { path }
        let path: String
        let name: String
        let kind: LocationKind
        let ejectable: Bool
        let uuid: String?
    }

    private(set) var volumes: [Volume] = []
    private(set) var cloud: [CloudProvider] = []
    private(set) var iCloudDrive: String?
    private(set) var bonjourHosts: [String] = []

    /// Starts observing (first browser window); `stop()` when the last one closes.
    func start() {}
    func stop() {}
}
