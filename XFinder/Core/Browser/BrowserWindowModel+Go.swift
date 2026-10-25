import AppKit
import Observation

/// XF-T30 W3 — the Go menu, recent folders, virtual locations (Recents, tags), Connect to Server, Eject.
/// Contract docs/specs/XF-T30-w3-contract.md. W3 builder (model).
extension BrowserWindowModel {

    /// Fixed destinations for the Go commands that just navigate the active tab. `goComputer` and
    /// `goRecents`/`goAirDrop`/`goNetwork`/`connectToServer`/`eject`/`clearRecentFolders` are handled separately
    /// below — they either have no single folder, or do something other than navigate.
    private static func fixedDestination(for command: BrowserCommand) -> String? {
        let home = NSHomeDirectory()
        switch command {
        case .goDocuments: return home + "/Documents"
        case .goDesktop: return home + "/Desktop"
        case .goDownloads: return home + "/Downloads"
        case .goHome: return home
        case .goApplications: return "/Applications"
        case .goUtilities: return "/Applications/Utilities"
        case .goICloud: return home + "/Library/Mobile Documents/com~apple~CloudDocs"
        default: return nil
        }
    }

    func performGoCommand(_ command: BrowserCommand) -> Bool {
        if let destination = Self.fixedDestination(for: command) {
            active.navigate(to: destination)
            return true
        }
        switch command {
        case .goRecents:
            open(.recents)
            return true
        case .goAirDrop:
            openFinderAirDrop()
            return true
        case .goNetwork:
            // Contract §3: "Network = the Bonjour sidebar section / /Network" — there is no single folder a Bonjour
            // share list maps to; `/Network` is the one path NetFS actually mounts discovered shares under.
            active.navigate(to: "/Network")
            return true
        case .goComputer:
            // Contract §3 / Q-T30 FileOctopus parity: "Computer disabled" — the chord stays bound (BrowserCommands),
            // the destination is simply unsupported.
            return false
        case .connectToServer:
            ConnectToServer.shared.present(on: NSApp.keyWindow) { [weak self] mountPath in
                self?.active.navigate(to: mountPath)
            }
            return true
        case .eject:
            performEject()
            return true
        case .clearRecentFolders:
            BrowserSettings.recentFolders = RecentFolders()
            return true
        default:
            return false
        }
    }

    func canPerformGoCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .goComputer:
            return false
        case .clearRecentFolders:
            return !BrowserSettings.recentFolders.paths.isEmpty
        case .eject:
            return ejectTargetVolume() != nil
        default:
            return true
        }
    }

    /// Opens a virtual location in the active tab. `PaneState.navigate(to:)` already recognizes a virtual path
    /// (`VirtualLocation.parse`, wired into `startLoad`/`installWatcher`) and lists it through `VirtualLocations`
    /// instead of `DirectoryReader` — this only has to hand it the right path string.
    func open(_ location: VirtualLocation) {
        active.navigate(to: location.path)
    }

    /// Every folder a tab navigates to (Go ▸ Recent Folders). Virtual locations are not recorded — `PaneState.navigate`
    /// calls this unconditionally, so the virtual-path guard lives here rather than at every call site.
    static func noteRecentFolder(_ path: String) {
        guard VirtualLocation.parse(path) == nil else { return }
        var recent = BrowserSettings.recentFolders
        recent.note(path)
        BrowserSettings.recentFolders = recent
    }

    // MARK: - AirDrop

    /// Contract §2 (shared by this Go command): "bấm ⇒ mở cửa sổ AirDrop của Finder (FileOctopus: macOS không cho
    /// app khác hiện thiết bị gần — ghi đúng như vậy trên UI)" — confirmed independently by the FileOctopus behaviour
    /// reference (spec-window-views-sidebar.md §7.1): "opens Finder's AirDrop window, because macOS doesn't let
    /// other apps show nearby devices... permanent architectural limitation."
    ///
    /// Measured (this builder cannot launch the GUI app, but this does not need it — `lsregister -dump` and
    /// `plutil`/`plistlib` on the bundle read without any window): `/System/Library/CoreServices/AirDropUI.app`
    /// exists, bundle id `com.apple.Sharing.AirDropUI`, `SBAppTags = [hidden]` (positive control: the same dump
    /// lists ordinary visible apps like Finder without that tag, so "hidden" here is a real, distinguishing flag,
    /// not every entry reading that way) — this is the system surface Finder's own AirDrop sidebar row launches,
    /// not a guess. Opened the CLAUDE.md-mandated way for bringing another app forward from a panel (rule 13):
    /// `NSWorkspace.openApplication(at:configuration:)`, never `activate(options:)`.
    private func openFinderAirDrop() {
        let airDropUI = URL(fileURLWithPath: "/System/Library/CoreServices/AirDropUI.app")
        if FileManager.default.fileExists(atPath: airDropUI.path) {
            NSWorkspace.shared.openApplication(at: airDropUI, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        } else {
            // Positive control failed on this machine (bundle moved/renamed in a later macOS): fall back to
            // activating Finder itself rather than doing nothing.
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
        }
    }

    // MARK: - Eject

    /// The volume to eject: the selected entries' volume if there is a selection, else the active tab's own volume.
    private func ejectTargetVolume() -> URL? {
        let candidatePath: String = active.selectedEntries.first?.path ?? active.path
        guard VirtualLocation.parse(candidatePath) == nil else { return nil }
        guard let mountPath: String = DirectoryReader.volumePath(of: candidatePath), mountPath != "/" else { return nil }
        return URL(fileURLWithPath: mountPath)
    }

    /// ⌘E goes through the SAME flow as the sidebar's eject button (multi-volume prompt, busy app with Try Again /
    /// Force Eject, refusal while an XFinder operation uses the disk) — integration audit 2026-10-25: it used to call
    /// `unmountAndEjectDevice` directly and skipped all of that. The sidebar of this window performs the request.
    private func performEject() {
        guard let volume: URL = ejectTargetVolume() else { return }
        EjectRequestCenter.shared.request(mountPath: volume.path, for: self)
    }
}

/// One pending ⌘E per window, picked up by that window's sidebar (which owns the eject sheets).
@MainActor @Observable
final class EjectRequestCenter {
    static let shared: EjectRequestCenter = EjectRequestCenter()

    struct Request: Equatable {
        let mountPath: String
        let window: ObjectIdentifier
        let serial: Int
    }

    private(set) var pending: Request?
    private var serial: Int = 0

    func request(mountPath: String, for model: BrowserWindowModel) {
        serial += 1
        pending = Request(mountPath: mountPath, window: ObjectIdentifier(model), serial: serial)
    }

    /// The sidebar of `model`'s window takes the request (nil when it is for another window or already taken).
    func take(for model: BrowserWindowModel) -> String? {
        guard let request: Request = pending, request.window == ObjectIdentifier(model) else { return nil }
        pending = nil
        return request.mountPath
    }
}
