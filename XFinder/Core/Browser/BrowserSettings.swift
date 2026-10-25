import AppKit
import Carbon

/// XF-T28 — the file browser's settings: the ONE reader of every `fileBrowser.*` key (CLAUDE.md rule 7; the page's
/// `@AppStorage` defaults must equal these — FeatureKeyDefaultsTests), and the optional global hotkey.
@MainActor
final class BrowserSettings {
    static let shared = BrowserSettings()

    /// The ONE reader of `fileBrowser.enabled` (the catalog's switch; default on — nothing runs until a window opens).
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "fileBrowser.enabled") as? Bool ?? true }
    /// The ONE reader of `fileBrowser.reopenWindows`: windows, panes, folders and Back history come back at launch.
    static var reopenWindows: Bool { UserDefaults.standard.object(forKey: "fileBrowser.reopenWindows") as? Bool ?? true }
    /// The ONE reader of `fileBrowser.showHidden`: new panes show hidden files (⇧⌘. flips one pane).
    static var showHidden: Bool { UserDefaults.standard.object(forKey: "fileBrowser.showHidden") as? Bool ?? false }
    /// The ONE reader of `fileBrowser.foldersFirst` (Finder's "Keep folders on top", off by default as in Finder).
    static var foldersFirst: Bool { UserDefaults.standard.object(forKey: "fileBrowser.foldersFirst") as? Bool ?? false }
    /// The ONE reader of `fileBrowser.defaultView`: the view a new pane opens in.
    static var defaultView: BrowserViewMode {
        BrowserViewMode(rawValue: UserDefaults.standard.string(forKey: "fileBrowser.defaultView") ?? "list") ?? .list
    }
    /// XF-T30 W1 — the ONE readers of the window bars (FileOctopus: Location Bar on, Path Bar ⌥⌘P, Status Bar ⌘/,
    /// Sidebar ⌥⌘S). The View-menu commands flip these keys; every window follows.
    static var showLocationBar: Bool { UserDefaults.standard.object(forKey: "fileBrowser.showLocationBar") as? Bool ?? true }
    static var showPathBar: Bool { UserDefaults.standard.object(forKey: "fileBrowser.showPathBar") as? Bool ?? false }
    static var showStatusBar: Bool { UserDefaults.standard.object(forKey: "fileBrowser.showStatusBar") as? Bool ?? true }
    static var showSidebar: Bool { UserDefaults.standard.object(forKey: "fileBrowser.showSidebar") as? Bool ?? true }

    /// XF-T30 W5a — the approved index folders (JSON `[IndexRoot]`; empty = nothing is indexed, FileOctopus R29). Not a
    /// toggle ⇒ no `FeatureKeyDefaultsTests` row; a damaged value reads as empty.
    static var indexRoots: [IndexRoot] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "fileBrowser.search.roots") else { return [] }
            return (try? JSONDecoder().decode([IndexRoot].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "fileBrowser.search.roots") }
    }
    /// The ONE reader of `fileBrowser.search.defaultScope`: `mac` | `folder` | `previous` (Settings ▸ Advanced).
    static var defaultSearchScope: String { UserDefaults.standard.string(forKey: "fileBrowser.search.defaultScope") ?? "mac" }
    /// The ONE reader+writer of `fileBrowser.savedSearches` (JSON `SavedSearchStore`).
    static var savedSearches: SavedSearchStore {
        get { SavedSearchStore.decode(UserDefaults.standard.data(forKey: "fileBrowser.savedSearches")) }
        set { UserDefaults.standard.set(newValue.encoded(), forKey: "fileBrowser.savedSearches") }
    }

    // MARK: XF-T30 W3 — sidebar rows (Settings ▸ Sidebar; hiding a row never deletes anything)
    static var sidebarRecents: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.recents") as? Bool ?? true }
    static var sidebarAirDrop: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.airDrop") as? Bool ?? true }
    static var sidebarFavorites: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.favorites") as? Bool ?? true }
    static var sidebarICloud: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.iCloud") as? Bool ?? true }
    static var sidebarHardDisks: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.hardDisks") as? Bool ?? true }
    static var sidebarExternalDisks: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.externalDisks") as? Bool ?? true }
    static var sidebarCloudStorage: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.cloudStorage") as? Bool ?? true }
    static var sidebarConnectedServers: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.connectedServers") as? Bool ?? true }
    static var sidebarBonjour: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.bonjour") as? Bool ?? false }
    static var sidebarRecentTags: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.recentTags") as? Bool ?? true }
    static var sidebarGroupLocationsByType: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.groupLocationsByType") as? Bool ?? false }
    static var sidebarHighlightCurrent: Bool { UserDefaults.standard.object(forKey: "fileBrowser.sidebar.highlightCurrent") as? Bool ?? false }
    /// The ONE reader+writer of `fileBrowser.recentFolders` (Go ▸ Recent Folders, local only).
    static var recentFolders: RecentFolders {
        get {
            guard let data = UserDefaults.standard.data(forKey: "fileBrowser.recentFolders") else { return RecentFolders() }
            return (try? JSONDecoder().decode(RecentFolders.self, from: data)) ?? RecentFolders()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "fileBrowser.recentFolders") }
    }

    // MARK: XF-T30 W4 — Settings window keys
    /// `home` | `desktop` | `documents` | `downloads` | `recents` | `custom` (Settings ▸ General ▸ New windows show).
    static var newWindowTarget: String { UserDefaults.standard.string(forKey: "fileBrowser.newWindowTarget") ?? "home" }
    static var newWindowCustomPath: String { UserDefaults.standard.string(forKey: "fileBrowser.newWindowCustomPath") ?? "" }
    static var returnOpens: Bool { UserDefaults.standard.object(forKey: "fileBrowser.returnOpens") as? Bool ?? false }
    static var cutWithCmdX: Bool { UserDefaults.standard.object(forKey: "fileBrowser.cutWithCmdX") as? Bool ?? false }
    static var showAllExtensions: Bool { UserDefaults.standard.object(forKey: "fileBrowser.showAllExtensions") as? Bool ?? false }
    static var onboardingDone: Bool { UserDefaults.standard.object(forKey: "fileBrowser.onboardingDone") as? Bool ?? false }
    /// The ONE reader+writer of `fileBrowser.keyBindings` (JSON `KeyBindings`; absent or damaged = Finder profile).
    static var keyBindings: KeyBindings {
        get {
            guard let data = UserDefaults.standard.data(forKey: "fileBrowser.keyBindings") else { return KeyBindings() }
            return (try? JSONDecoder().decode(KeyBindings.self, from: data)) ?? KeyBindings()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "fileBrowser.keyBindings") }
    }
    /// The ONE reader of `fileBrowser.tabSwitchesPanes` (Settings ▸ Keyboard — the Total Commander habit, off by
    /// default so plain Tab keeps doing nothing everywhere else).
    static var tabSwitchesPanes: Bool { UserDefaults.standard.object(forKey: "fileBrowser.tabSwitchesPanes") as? Bool ?? false }
    /// The ONE reader of `fileBrowser.mouseBackForward` (Settings ▸ Keyboard — side buttons 4/5: on, off, or swapped).
    static var mouseBackForward: MouseBackForward {
        MouseBackForward(rawValue: UserDefaults.standard.string(forKey: "fileBrowser.mouseBackForward") ?? "on") ?? .on
    }

    // MARK: XF-T30 W7 — Preview pane
    static var showPreview: Bool { UserDefaults.standard.object(forKey: "fileBrowser.showPreview") as? Bool ?? false }
    static var previewShowMore: Bool { UserDefaults.standard.object(forKey: "fileBrowser.previewShowMore") as? Bool ?? false }

    /// The ONE reader of `fileBrowser.globalHotkey` (default off: a global chord is taken from every app).
    static var globalHotkeyEnabled: Bool { UserDefaults.standard.object(forKey: "fileBrowser.globalHotkey") as? Bool ?? false }

    /// The ONE reader+writer of `fileBrowser.sidebarLayout` (XF-T28 Wave 4 §B) — JSON `SidebarLayout`, not a toggle,
    /// so there is no `FeatureKeyDefaultsTests` row for it; `SidebarLayout.decode` tolerates a missing/damaged value.
    static var sidebarLayout: SidebarLayout {
        get { SidebarLayout.decode(UserDefaults.standard.data(forKey: "fileBrowser.sidebarLayout")) }
        set { UserDefaults.standard.set(newValue.encoded(), forKey: "fileBrowser.sidebarLayout") }
    }

    // MARK: Global hotkey ⌃⌥⌘F (Carbon, no permission) — ShortcutCatalog `fileBrowser.open`

    /// F, and ⌃⌥⌘ — ⌃⌥F already belongs to another entry (ShortcutCatalog), ⌃⌥⌘F to nothing.
    static let hotkeyKeyCode: UInt32 = 3
    /// 'XFbr' — this feature's own signature, so the other Carbon handlers (⌘K, notes, ⇧⌘G) ignore its events.
    private static let hotkeySignature: OSType = 0x58466272
    private static let hotkeyID: UInt32 = 1
    private var hotKeyRef: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?
    /// false when the switch is on but RegisterEventHotKey refused (another app holds the chord) — the page says so.
    private(set) var hotkeyRegistered = false

    /// FeatureHub + launch + didBecomeActive.
    func applySettings() {
        if Self.isEnabled && Self.globalHotkeyEnabled {
            installCarbonHandlerIfNeeded()
            guard hotKeyRef == nil else { return }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(Self.hotkeyKeyCode, UInt32(controlKey | optionKey | cmdKey),
                                             EventHotKeyID(signature: Self.hotkeySignature, id: Self.hotkeyID),
                                             GetApplicationEventTarget(), 0, &ref)
            hotKeyRef = status == noErr ? ref : nil
            hotkeyRegistered = hotKeyRef != nil
        } else {
            if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
            hotKeyRef = nil
            hotkeyRegistered = false
        }
    }

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == BrowserSettings.hotkeySignature, id.id == BrowserSettings.hotkeyID
            else { return OSStatus(eventNotHandledErr) }
            let s = Unmanaged<BrowserSettings>.fromOpaque(userData).takeUnretainedValue()
            s.hotkeyFired()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    private nonisolated func hotkeyFired() {
        Task { @MainActor in
            guard BrowserSettings.isEnabled else { return }
            BrowserWindowController.shared.openWindow(path: nil)
        }
    }
}
