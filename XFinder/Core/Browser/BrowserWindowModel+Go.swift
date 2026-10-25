import AppKit

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
    /// Contract §2 describes a multi-volume "this volume / all volumes" sheet and a busy/Force-Eject flow — that UI
    /// (and `EjectGuard`-driven busy detection) belongs to `BrowserSidebarView`, owned by the W3 AppKit builder, not
    /// this file. `EjectGuard` (the API this contract names) only ever *dissents* against an eject already under
    /// way (`DARegisterDisk{Unmount,Eject}ApprovalCallback`); it exposes no "eject this volume" entry point to call
    /// into. Per the task's stated fallback, this performs a plain, unconditional eject of one volume through
    /// `NSWorkspace` off main — no multi-volume prompt, no busy/Force-Eject sheet. Flagged in deviations.
    private func ejectTargetVolume() -> URL? {
        let candidatePath = active.selectedEntries.first?.path ?? active.path
        guard VirtualLocation.parse(candidatePath) == nil else { return nil }
        guard let mountPath = DirectoryReader.volumePath(of: candidatePath), mountPath != "/" else { return nil }
        return URL(fileURLWithPath: mountPath)
    }

    private func performEject() {
        guard let volume = ejectTargetVolume() else { return }
        Task.detached(priority: .userInitiated) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }
    }
}
