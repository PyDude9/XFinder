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
    /// The ONE reader of `fileBrowser.globalHotkey` (default off: a global chord is taken from every app).
    static var globalHotkeyEnabled: Bool { UserDefaults.standard.object(forKey: "fileBrowser.globalHotkey") as? Bool ?? false }

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
