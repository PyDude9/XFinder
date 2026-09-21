import AppKit
import Observation

/// UI/persistence boundary. Only compact command/result values cross to the worker.
@MainActor @Observable
final class GestureController {
    static let shared = GestureController()
    private(set) var configuration = GestureConfiguration()
    private(set) var status = "Đã tắt"
    private(set) var recording = false
    private(set) var activeBundle = ""
    private(set) var lastExternalBundle = ""
    private let storageKey = "mouseGestures.configuration.v1"
    // Legacy key that may hold a full copy of every preset. Migrated on first launch.
    private let migrationFlagKey = "mouseGestures.migrated.v1"
    private var observers: [NSObjectProtocol] = []
    private var engineStarted = false
    @ObservationIgnored private lazy var engine = GestureEngine { [weak self] result in
        Task { @MainActor [weak self] in self?.receive(result) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(GestureConfiguration.self, from: data) {
            configuration = saved
        }
        configuration.validate()
        migrateIfNeeded()
    }

    /// If an older build pre-filled `overrides` with every factory default (one
    /// entry per built-in bundle), prune entries that merely echo the default.
    /// Keeps genuine user overrides and explicit `.unassigned` choices.
    private func migrateIfNeeded() {
        guard !configuration.overrides.isEmpty else { return }
        // Only run once per install.
        if UserDefaults.standard.bool(forKey: migrationFlagKey) { return }
        var pruned: [String: [GestureDirection: GestureAction]] = [:]
        for (bundle, dict) in configuration.overrides {
            // Unknown bundle IDs are user real data — keep all.
            guard GestureProfiles.all.contains(where: { $0.id == bundle }) else {
                pruned[bundle] = dict; continue
            }
            let factory = GestureProfiles.all.first { $0.id == bundle }?.defaults ?? [:]
            var keep: [GestureDirection: GestureAction] = [:]
            for (dir, action) in dict {
                if factory[dir] == action { continue } // untouched default — drop
                // Also drop an `.unassigned` that merely echoed an empty factory slot.
                if case .unassigned = action, factory[dir] == nil { continue }
                keep[dir] = action
            }
            if !keep.isEmpty { pruned[bundle] = keep }
        }
        let before = configuration.overrides
        configuration.overrides = pruned
        if before != pruned { persist() }
        UserDefaults.standard.set(true, forKey: migrationFlagKey)
    }

    func start() {
        guard observers.isEmpty else { return }
        updateFrontmost(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                             object:nil, queue:.main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
            Task { @MainActor [weak self] in self?.updateFrontmost(id) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                             object:nil, queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                             object:nil, queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                             object:nil, queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                             object:nil, queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
        })
        apply()
    }
    private func resume() {
        if engineStarted { engine.send(.resume) }
        updateFrontmost(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
        apply()
    }
    private func updateFrontmost(_ id: String) {
        activeBundle = id
        if !id.isEmpty && id != Bundle.main.bundleIdentifier { lastExternalBundle = id }
        if engineStarted { engine.send(.frontmost(id)) }
    }
    private func suspend() {
        if engineStarted { engine.send(.suspend) }
    }
    func apply() {
        // No worker/tap at all until the user enables gestures or starts recording.
        guard configuration.enabled || recording || engineStarted else { status = "Đã tắt"; return }
        engineStarted = true
        engine.send(.frontmost(activeBundle))
        engine.send(.configure(configuration))
    }
    func update(_ change: (inout GestureConfiguration) -> Void) {
        change(&configuration); configuration.validate()
        persist(); apply()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    func recordTrigger() {
        ensureRecordingEngine(); engine.send(.recordTrigger)
    }
    func recordShortcut(bundle: String, direction: GestureDirection) {
        ensureRecordingEngine(); engine.send(.recordShortcut(bundle,direction))
    }
    private func ensureRecordingEngine() {
        recording = true; apply()
    }
    func cancelRecording() { if engineStarted { engine.send(.cancelRecording) } }
    func setAction(_ action: GestureAction, bundle: String, direction: GestureDirection) {
        update { $0.overrides[bundle, default: [:]][direction] = action }
    }
    func resetProfile(_ bundle: String) { update { $0.overrides.removeValue(forKey: bundle) } }
    private func receive(_ result: GestureResult) {
        switch result {
        case .status(let value): status = value
        case .recordingEnded: recording = false
        case .trigger(let source):
            configuration.trigger = source; persist()
        case .shortcut(let bundle, let direction, let shortcut):
            configuration.overrides[bundle, default: [:]][direction] = .shortcut(shortcut)
            persist()
            engine.send(.configure(configuration))
        }
    }
}
