import AppKit
import Observation

/// XF-T30 W3 — the live sources of the sidebar: volumes (mount/unmount/rename notifications), cloud storage folders,
/// iCloud Drive, connected servers, Bonjour computers (only while that row is on). W3 builder (AppKit).
///
/// Measured (2026-10-25): `NSWorkspaceDidMountNotification` / `NSWorkspaceDidUnmountNotification` /
/// `NSWorkspaceDidRenameVolumeNotification` fire from an ordinary process with no entitlement — XF-T28's own
/// `BrowserSidebarView.loadVolumes()` only refreshed on `.onAppear`, so plugging a USB drive in left every already-open
/// window stale until it was reopened; this class refreshes `volumes` from the notification handler itself so every
/// window sees the change immediately (contract XF-T30-w3 §2, fixing the gap the task names explicitly).
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

    private var observers: [NSObjectProtocol] = []
    private var refCount = 0
    private var netServiceBrowser: NetServiceBrowser?
    private var netServiceBrowserDelegate: BonjourDelegate?
    private var resolvingServices: Set<NetService> = []

    private init() {}

    /// Starts observing (first browser window); `stop()` when the last one closes. Reference-counted so N windows
    /// share one observation (CLAUDE.md IdleCost: no window open ⇒ nothing registered, nothing scanned).
    func start() {
        refCount += 1
        guard refCount == 1 else { return }
        reloadVolumesAndCloud()
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reloadVolumesAndCloud()
            }
        }
        applyBonjourSetting()
    }

    func stop() {
        refCount = max(0, refCount - 1)
        guard refCount == 0 else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
        stopBonjour()
    }

    /// Re-reads the Mạng (Bonjour) sidebar toggle and starts/stops browsing to match — called from `start()` and by
    /// the settings view whenever the person flips the toggle (CLAUDE.md rule: an opt-in feature costs nothing while
    /// off, so Bonjour browsing must not run merely because a browser window is open).
    func applyBonjourSetting() {
        if BrowserSettings.sidebarBonjour {
            startBonjour()
        } else {
            stopBonjour()
        }
    }

    // MARK: - Volumes + cloud (off the main actor: `mountedVolumeURLs`/`contentsOfDirectory` are disk I/O)

    private func reloadVolumesAndCloud() {
        Task.detached(priority: .userInitiated) {
            let volumes = Self.loadVolumes()
            let cloud = Self.loadCloudProviders()
            let iCloud = Self.loadICloudDrivePath()
            await MainActor.run {
                self.volumes = volumes
                self.cloud = cloud
                self.iCloudDrive = iCloud
            }
        }
    }

    private nonisolated static func loadVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeUUIDStringKey, .volumeIsInternalKey,
                                      .volumeIsLocalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes])
        else { return [] }
        return urls.compactMap { url -> Volume? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let name = values.volumeName ?? url.lastPathComponent
            let isLocal = values.volumeIsLocal ?? true
            let isInternal = values.volumeIsInternal ?? true
            let kind: LocationKind
            if !isLocal {
                kind = .network
            } else if CloudProviders.provider(containing: url.path, in: loadCloudProviders()) != nil {
                kind = .cloud
            } else if isInternal {
                kind = .local
            } else {
                kind = .external
            }
            return Volume(path: url.path, name: name, kind: kind,
                         ejectable: values.volumeIsEjectable ?? false, uuid: values.volumeUUIDString)
        }
    }

    private nonisolated static func loadCloudProviders() -> [CloudProvider] {
        let home = NSHomeDirectory()
        let root = home + "/Library/CloudStorage"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        return entries.sorted().compactMap { CloudProviders.parse(folderName: $0, root: root) }
    }

    private nonisolated static func loadICloudDrivePath() -> String? {
        let path = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    // MARK: - Bonjour (only while the Mạng row is on — CLAUDE.md IdleCost)

    /// `_smb._tcp` / `_afpovertcp._tcp` — the two share protocols Finder's own Network view resolves (spec
    /// XF-T30-w3-contract §2); resolved host names are what gets listed, duplicates collapsed.
    private static let bonjourServiceTypes = ["_smb._tcp.", "_afpovertcp._tcp."]

    private func startBonjour() {
        guard netServiceBrowser == nil else { return }
        let delegate = BonjourDelegate(owner: self)
        netServiceBrowserDelegate = delegate
        let browser = NetServiceBrowser()
        browser.delegate = delegate
        netServiceBrowser = browser
        for type in Self.bonjourServiceTypes {
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }

    private func stopBonjour() {
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        netServiceBrowserDelegate = nil
        resolvingServices.removeAll()
        bonjourHosts = []
    }

    fileprivate func noteResolving(_ service: NetService) {
        resolvingServices.insert(service)
    }

    fileprivate func noteResolved(_ service: NetService, hostName: String?) {
        resolvingServices.remove(service)
        guard let hostName, !bonjourHosts.contains(hostName) else { return }
        bonjourHosts.append(hostName)
        bonjourHosts.sort()
    }

    fileprivate func noteRemoved(_ name: String) {
        bonjourHosts.removeAll { $0 == name }
    }
}

/// `NetServiceBrowserDelegate`/`NetServiceDelegate` callbacks land on the main run loop (the browser/service were
/// scheduled on the default run loop from `@MainActor startBonjour()`) — `@MainActor` on the class is safe, not a
/// guess (CLAUDE.md rule 12: only trust "already on main" when the posting source is actually main-run-loop-driven,
/// as these Foundation networking classes are when left on their default scheduling).
@MainActor
private final class BonjourDelegate: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private weak var owner: SidebarSources?

    init(owner: SidebarSources) {
        self.owner = owner
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        owner?.noteResolving(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        owner?.noteRemoved(service.name)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        owner?.noteResolved(sender, hostName: sender.hostName ?? sender.name)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        owner?.noteResolved(sender, hostName: nil)
    }
}
