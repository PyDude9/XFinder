import AppKit

/// XF-T30 W4 — Settings window and Welcome commands, and the behaviour of the W4 keys (Return opens, ⌘X cut, new window
/// target, Tab switches panes). Contract docs/specs/XF-T30-w4-contract.md. W4 builder (model).
extension BrowserWindowModel {
    /// `.openBrowserSettings` / `.showWelcome` — the only two W4 commands routed through the shared dispatcher
    /// (contract: "⌘, (openBrowserSettings) và showWelcome via performSettingsCommand").
    func performSettingsCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .openBrowserSettings:
            BrowserSettingsWindowController.shared.show(tab: nil)
            return true
        case .showWelcome:
            BrowserWindowModel.showWelcome()
            return true
        default:
            return false
        }
    }

    func canPerformSettingsCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .openBrowserSettings, .showWelcome: return true
        default: return false
        }
    }

    /// Opens the Welcome window (first browser window of a fresh install, or replayed from Settings ▸ Privacy ▸
    /// "Hiện cửa sổ Chào…" — contract §3). `opened(layout)` is the Welcome window's own callback once the person
    /// picks a layout; it opens a brand-new window showing that layout, one allowed folder per pane (repeating the
    /// list when the layout has more panes than allowed folders, same as a single-folder install only ever seeing
    /// that one folder in every pane).
    static func showWelcome() {
        OnboardingWindowController.shared.show { preset, allowed in
            openWindow(withLayout: preset, allowed: allowed)
        }
    }

    /// `BrowserWindowController.openWindow(path:)` calls this once, right before opening the browser's very first
    /// window of a fresh install (`windows.isEmpty && fileBrowser.onboardingDone == false`) — NOT at app launch:
    /// `restoreSessionAtLaunch()` goes straight through `openWindow(snapshot:)`, which never passes through this
    /// gate, so an install with a saved session never shows Welcome again even on a later crash-relaunch before
    /// `onboardingDone` got set.
    static func showWelcomeIfFirstRun() {
        guard !BrowserSettings.onboardingDone else { return }
        showWelcome()
    }

    /// Builds a fresh window for `preset` (Q-T30-9's layout step), one pane per leaf, each showing one of the
    /// folders the person already allowed — `SidebarLayout`'s own favorites (Home/Desktop/Documents/Downloads/
    /// Applications by default) double as "folders the person allowed" here, since granting TCC access to a folder
    /// and keeping it pinned are the same act the Welcome window's own folder-access step already performs (its
    /// controller is W4's `OnboardingWindowController`, not this file). Folders that no longer exist fall back to
    /// Home, same as a dead session-restore pane would.
    private static func openWindow(withLayout preset: PanePreset, allowed: [String]) {
        var tree = PaneTree()
        tree.apply(preset)
        let paneIDs = tree.panes
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        // The folders the person allowed in the Welcome window come first; the sidebar favourites fill in otherwise.
        var allowedFolders = (allowed + BrowserSettings.sidebarLayout.favorites.map(\.path)).filter { fm.fileExists(atPath: $0) }
        var seen = Set<String>()
        allowedFolders = allowedFolders.filter { seen.insert($0).inserted }
        if allowedFolders.isEmpty { allowedFolders = [home] }
        var paneSnapshots: [PaneSnapshot] = []
        for (index, paneID) in paneIDs.enumerated() {
            let folder = allowedFolders[index % allowedFolders.count]
            let tab = TabSnapshot(path: folder, viewMode: BrowserSettings.defaultView, sort: .finderDefault,
                                  history: PaneHistory(current: folder), showHidden: BrowserSettings.showHidden)
            paneSnapshots.append(PaneSnapshot(id: paneID, tabs: [tab], selectedTab: 0))
        }
        let snapshot = WindowSnapshot(frame: nil, tree: tree, panes: paneSnapshots,
                                      activePane: paneIDs.first ?? PaneID(raw: 0), shelfVisible: false)
        BrowserWindowController.shared.openRestoredWindow(snapshot)
    }

    // MARK: - New window / new tab target (Settings ▸ General ▸ "Cửa sổ mới hiện")

    /// `BrowserSettings.newWindowTarget` resolved to an actual folder — `home` when the stored value is unknown
    /// (a damaged default or a future target this build does not know yet), matching every other `ONE reader`'s
    /// own "unreadable ⇒ default" rule. `custom` with an empty/missing path also falls back to Home rather than
    /// opening nothing.
    static func resolvedNewWindowTarget() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        switch BrowserSettings.newWindowTarget {
        case "home": return home
        case "desktop": return existingOrHome(home + "/Desktop", home: home, fm: fm)
        case "documents": return existingOrHome(home + "/Documents", home: home, fm: fm)
        case "downloads": return existingOrHome(home + "/Downloads", home: home, fm: fm)
        case "recents":
            let recent = BrowserSettings.recentFolders.paths.first { fm.fileExists(atPath: $0) }
            return recent ?? home
        case "custom":
            let custom = BrowserSettings.newWindowCustomPath
            return !custom.isEmpty && fm.fileExists(atPath: custom) ? custom : home
        default:
            return home
        }
    }

    private static func existingOrHome(_ path: String, home: String, fm: FileManager) -> String {
        fm.fileExists(atPath: path) ? path : home
    }

    // MARK: - File name display (Settings ▸ Advanced ▸ "Hiện mọi đuôi tệp")

    /// `fileBrowser.showAllExtensions`'s ONE display-name helper — the views that actually show file/folder names
    /// (list, icon, column, gallery; NOT this file's job per contract §"showAllExtensions honoured where names are
    /// displayed is NOT yours (views)") call this instead of reading `entry.name` directly, so the setting has
    /// exactly one place that decides what a name looks like.
    ///
    /// `true`: always show the extension, even one Finder would normally hide (same as Finder's own global
    /// "Show all filename extensions"). `false`: today this returns the plain name unchanged — `DirectoryEntry`
    /// does not yet carry the per-file `kLSItemHideExtension`/`hasHiddenExtension` flag the contract's "trừ khi
    /// tệp có cờ ẩn đuôi riêng" clause needs (that flag is a `URLResourceValues` disk read, out of reach from a
    /// synchronous, non-isolated name formatter with no cache to read from yet — `FileMetadataCache`/W2 owns that
    /// cache and has not implemented it). Recorded as a deviation for the integrator.
    func displayName(for entry: DirectoryEntry) -> String {
        Self.displayName(for: entry, showAllExtensions: BrowserSettings.showAllExtensions)
    }

    /// Finder's rule: with "Show all filename extensions" off, a file whose own hide-extension flag is set shows its
    /// name without the extension; folders, packages and names without an extension never change.
    nonisolated static func displayName(for entry: DirectoryEntry, showAllExtensions: Bool) -> String {
        EntryRules.displayName(entry, showAllExtensions: showAllExtensions)
    }
}
