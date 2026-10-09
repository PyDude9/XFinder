import AppKit
import AVFoundation
import Speech

/// The live half of the Features hub. It owns NO state of its own: a feature is on or off
/// according to the same UserDefaults key its engine reads (`FeatureCatalog` is verified against
/// the engines in source), so the hub, the feature's own page and the menubar flyout can never
/// disagree — they are three views of one key.
///
/// Switching a feature writes the key and calls the engine's `applySettings()`, exactly what the
/// feature's own toggle does. Cost: the only observers exist while a hub view is on screen.
@MainActor
@Observable
final class FeatureHub {
    static let shared = FeatureHub()

    /// Bumped whenever something that affects the display may have changed.
    private(set) var revision = 0

    private var refCount = 0
    private var observers: [NSObjectProtocol] = []

    init() {}

    // MARK: Lifecycle (views call retain/release from onAppear/onDisappear)

    func retain() {
        refCount += 1
        guard refCount == 1 else { return }
        let bump: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.revision += 1 }
        }
        observers = [
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main, using: bump),
            // Returning from System Settings after granting a permission.
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: bump),
        ]
        revision += 1
    }

    func release() {
        refCount = max(0, refCount - 1)
        guard refCount == 0 else { return }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    // MARK: State

    func isOn(_ f: FeatureDef) -> Bool {
        _ = revision   // read ⇒ the view re-renders when `revision` changes
        return UserDefaults.standard.object(forKey: f.enabledKey) as? Bool ?? f.defaultOn
    }

    var states: [FeatureID: Bool] {
        Dictionary(uniqueKeysWithValues: FeatureCatalog.all.map { ($0.id, isOn($0)) })
    }

    var enabledSet: Set<FeatureID> { Set(states.filter(\.value).map(\.key)) }

    var onCount: Int { states.values.filter { $0 }.count }

    // MARK: Switching

    func set(_ id: FeatureID, on: Bool) {
        let f = FeatureCatalog.def(id)
        UserDefaults.standard.set(on, forKey: f.enabledKey)
        Self.apply(id)
        revision += 1
    }

    func setAll(_ on: Bool) {
        for f in FeatureCatalog.all { set(f.id, on: on) }
    }

    func apply(_ bundle: FeatureBundle) {
        let target = FeatureCatalog.apply(bundle, to: states)
        for (id, on) in target where on != states[id] { set(id, on: on) }
    }

    /// Re-run the engine's own `applySettings()` — the same call the feature's own toggle makes.
    static func apply(_ id: FeatureID) {
        switch id {
        case .dockPreview:     DockPreviewController.shared.applySettings()
        case .commandTab:      CommandTabController.shared.applySettings()
        case .snapZones:       SnapZoneController.shared.applySettings()
        case .quitProtection:  QuitProtectionController.shared.applySettings()
        case .clipboardShelf:  ClipboardShelfController.shared.applySettings()
        case .quickSearch:     QuickSearchPanelController.shared.applySettings()
        case .edgeNotes:       EdgeNotesController.shared.applySettings()
        case .dropTray:        NotchDropController.shared.applySettings()
        case .folderSync:      FolderSyncController.shared.applySettings()
        case .voice:           VoiceManager.shared.applySettings()
        // Read at the point of use by the clipboard engine; nothing to re-arm.
        case .cleanURLs, .suggestions: break
        }
    }

    // MARK: Permissions

    func granted() -> [AppPermission: Bool] {
        _ = revision
        return [
            .accessibility: AXIsProcessTrusted(),
            .screenRecording: CGPreflightScreenCaptureAccess(),
            .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            .speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized,
        ]
    }

    /// The action behind a "Grant…" button. macOS lists an app in a Privacy pane only AFTER the app
    /// has asked, so opening the pane alone can leave XFinder missing from it: ask first, and fall
    /// back to the pane when the system will not prompt again (already denied).
    func request(_ p: AppPermission) {
        switch p {
        case .accessibility:
            if !WindowManager.requestAccessibilityTrust() { openSettings(for: p) }
        case .screenRecording:
            if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
            openSettings(for: p)
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in self.revision += 1 } }
            } else { openSettings(for: p) }
        case .speechRecognition:
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { _ in Task { @MainActor in self.revision += 1 } }
            } else { openSettings(for: p) }
        }
    }

    func openSettings(for p: AppPermission) {
        if let url = URL(string: p.settingsURL) { NSWorkspace.shared.open(url) }
    }
}
