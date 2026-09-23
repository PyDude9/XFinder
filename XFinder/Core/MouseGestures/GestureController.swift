import AppKit
import Observation

/// UI/persistence boundary. Only compact command/result values cross to the worker.
@MainActor @Observable
final class GestureController {
    static let shared = GestureController()
    private(set) var configuration = GestureConfiguration()
    /// Status strings are **L10n keys**, not sentences. This type lives in `Core/`
    /// and is created on the gesture queue; it has no business deciding what
    /// language the user reads. Holding the Vietnamese literal here is exactly how
    /// it used to reach an English UI un-translated. The view resolves it.
    private(set) var status = "Đã tắt"
    /// Whether the event tap is actually armed. The UI must not infer readiness
    /// from `status` text — a tap can fail to open while the switch is on.
    private(set) var tapActive = false
    /// Why the last tap attempt failed ("" when it did not). Lets the page name the
    /// real cause instead of a generic "it did not work".
    private(set) var tapFailure = ""
    /// Whether this process currently holds Accessibility trust, sampled at the
    /// moment the tap was attempted. Not a live poll — see `refreshTrust()`.
    private(set) var trusted = false
    private(set) var recording = false
    private(set) var activeBundle = ""
    private(set) var lastExternalBundle = ""
    /// The machine's own hotkeys for the system actions a gesture can dispatch (Mission
    /// Control, App Exposé, Show Desktop, the two Space moves), read from
    /// `com.apple.symbolichotkeys`. Published here so the page resolves exactly the keys the
    /// engine will post — one read, one resolver, and no second copy that can disagree.
    private(set) var systemBindings = GestureSystemBindings.empty
    private let storageKey = "mouseGestures.configuration.v1"
    // Legacy key that may hold a full copy of every preset. Migrated on first launch.
    private let migrationFlagKey = "mouseGestures.migrated.v1"
    /// One-shot flag for the middle-click → side-button trigger migration.
    private let triggerMigrationKey = "mouseGestures.triggerMigrated.v2"
    private var observers: [NSObjectProtocol] = []
    private var engineStarted = false
    @ObservationIgnored private lazy var engine = GestureEngine { [weak self] result in
        Task { @MainActor [weak self] in self?.receive(result) }
    }

    private init() {
        // A decode failure must NOT silently erase the user's overrides. `try?`
        // used to make any missing/renamed key (e.g. a field added in a later
        // build) drop the entire configuration, including every custom mapping —
        // measured: a payload with one known key removed decodes to nil and the
        // overrides are gone. So: try the real model, then a lenient pass that
        // recovers whatever fields are present, and only warn when even that
        // fails. The old data is left on disk either way, so nothing is destroyed.
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            if let saved = try? JSONDecoder().decode(GestureConfiguration.self, from: data) {
                configuration = saved
            } else if let recovered = Self.recover(from: data) {
                NSLog("[XFinder] mouse-gestures config decoded with missing fields; recovered what was readable")
                configuration = recovered
            } else {
                NSLog("[XFinder] mouse-gestures config could not be read; keeping defaults, original data left intact")
            }
        }
        configuration.validate()
        migrateIfNeeded()
        migrateMiddleClickTriggerIfNeeded()
    }

    /// Best-effort read of a configuration envelope whose shape drifted.
    ///
    /// Field-by-field so one unknown/missing key cannot discard the rest. **Every new
    /// field must be added here**, or a configuration saved by an older build stops
    /// decoding entirely and the user's overrides vanish — see the note on
    /// `GestureConfiguration.scrollButtonEnabled`, where that was caught on a real
    /// payload rather than reasoned about.
    private static func recover(from data: Data) -> GestureConfiguration? {
        struct Envelope: Decodable {
            var enabled: Bool?
            var deadzone: Double?
            var tiltEnabled: Bool?
            var tiltAvailable: Bool?
            var debug: Bool?
            var trigger: TriggerSource?
            var scrollButtonEnabled: Bool?
            var scrollButton: Int?
            var overrides: [String: [GestureDirection: GestureAction]]?
        }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        guard env.enabled != nil || env.overrides != nil || env.trigger != nil else { return nil }
        var out = GestureConfiguration()
        if let v = env.enabled { out.enabled = v }
        if let v = env.deadzone { out.deadzone = v }
        if let v = env.tiltEnabled { out.tiltEnabled = v }
        if let v = env.tiltAvailable { out.tiltAvailable = v }
        if let v = env.debug { out.debug = v }
        if let v = env.trigger { out.trigger = v }
        if let v = env.scrollButtonEnabled { out.scrollButtonEnabled = v }
        if let v = env.scrollButton { out.scrollButton = v }
        if let v = env.overrides { out.overrides = v }
        return out
    }

    /// If an older build pre-filled `overrides` with every factory default (one
    /// entry per built-in bundle), prune entries that merely echo the default.
    /// Keeps genuine user overrides and explicit `.unassigned` choices.
    ///
    /// Called from `init` **and** from `start()`. The flag alone is not enough:
    /// the controller is a lazily created singleton, so `init` may run long after
    /// the user's preferences were written by another build.
    func migrateIfNeeded() {
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

    /// Repair the one shipped default that made the feature unusable, without touching a
    /// deliberate choice.
    ///
    /// Measured on this machine: the stored trigger was `mouseButton(2)` — the wheel click —
    /// with `overrides` empty. Holding the wheel while dragging is not a motion a hand
    /// performs, and the user reported it twice ("không hiển thị gì cả"). `validate()` could
    /// not fix it, because B2 is a *valid* trigger; it was simply the wrong default left by
    /// an older build.
    ///
    /// Guarded on `overrides.isEmpty` on purpose: a user who deliberately set the wheel as
    /// their hold button keeps it. Only an untouched default is migrated. One-shot, so a
    /// user who moves *back* to the wheel is not moved again on the next launch.
    func migrateMiddleClickTriggerIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: triggerMigrationKey) else { return }
        UserDefaults.standard.set(true, forKey: triggerMigrationKey)
        guard configuration.overrides.isEmpty,
              configuration.trigger == .mouseButton(2) else { return }
        configuration.trigger = GestureConfiguration.defaultTrigger
        configuration.validate()
        persist()
    }

    /// Re-read the machine's own symbolic hotkeys and publish them to the engine.
    ///
    /// Called at launch, on every app activation, and when the page appears — because the
    /// user changes symbolic hotkeys in System Settings, i.e. while XFinder is *not*
    /// frontmost, and the old binding would otherwise stay in force until a relaunch.
    /// A `UserDefaults` read plus a command send, so calling it eagerly is cheap.
    func refreshSystemBindings() {
        systemBindings = SpaceBinding.currentBindings()
        guard engineStarted else { return }
        engine.send(.systemBindings(systemBindings))
    }

    func start() {
        guard observers.isEmpty else { return }
        // `init` ran the migration, but `GestureController.shared` is only
        // instantiated when the page actually appears, and a legacy profile
        // restored *after* first launch (a preferences sync, a copied plist, or a
        // previous build that wrote the full dictionary) would otherwise keep a
        // frozen copy of the presets forever. Re-running is idempotent and cheap:
        // it is a no-op once the flag is set, and a no-op when there is nothing
        // to migrate. Measured: without this, a seeded legacy payload survived a
        // full launch untouched.
        migrateIfNeeded()
        migrateMiddleClickTriggerIfNeeded()
        refreshTrust()
        refreshSystemBindings()
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
        // Granting Accessibility happens in System Settings, i.e. while XFinder is
        // not frontmost. Re-check on every activation so the tap arms immediately
        // instead of needing a relaunch or a manual toggle.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.engineStarted else { return }
                self.refreshTrust(); self.refreshSystemBindings(); self.apply()
            }
        })
        apply()
    }
    private func resume() {
        if engineStarted { engine.send(.resume) }
        refreshTrust()
        refreshSystemBindings()
        updateFrontmost(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
        apply()
    }
    /// Re-read Accessibility trust and re-arm the tap. Called on app activation so
    /// granting the permission in System Settings takes effect without a relaunch.
    func refreshTrust() {
        trusted = WindowManager.isTrusted
        if engineStarted { engine.send(.configure(configuration)) }
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
        // Nothing to arm when gestures are off and no recording is in flight — but
        // `tapActive` must still be reported false so the page never shows a stale
        // "ready" badge from a previous session.
        guard configuration.enabled || recording || engineStarted else {
            status = "Đã tắt"
            tapActive = false
            return
        }
        engineStarted = true
        engine.send(.frontmost(activeBundle))
        engine.send(.systemBindings(systemBindings))
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

    /// Drop one direction's override so it falls back to the built-in preset.
    ///
    /// The detail panel's "Về mặc định" sits under a single direction heading, so
    /// calling `resetProfile` there reset the *whole app* while the label promised
    /// only that row — the user's other custom directions vanished with no undo.
    /// A per-row control must change only that row.
    func resetDirection(bundle: String, direction: GestureDirection) {
        update {
            guard var directions = $0.overrides[bundle] else { return }
            directions.removeValue(forKey: direction)
            // An emptied dictionary is the same as no override at all; leaving it
            // behind would mark every other direction of this app as customised
            // and keep the app in the "you set some directions" copy.
            if directions.isEmpty {
                $0.overrides.removeValue(forKey: bundle)
            } else {
                $0.overrides[bundle] = directions
            }
        }
    }

    func resetProfile(_ bundle: String) { update { $0.overrides.removeValue(forKey: bundle) } }
    /// The engine's recent activity, as plain values. The page renders it; the
    /// controller only carries it, because a `Core/` type has no business deciding
    /// which language the user reads.
    private(set) var diagnostics: [GestureDiagnostic] = []
    /// The button number of the most recent mouse press the engine's tap saw, whatever
    /// that press turned out to be. Published because it answers the one question no API
    /// can: "which number is my side button?" `CGEventField` carries no vendor/product
    /// field, so the only honest way to learn it is to observe a real press.
    private(set) var observedPress: Int?

    private func receive(_ result: GestureResult) {
        switch result {
        case .status(let value): status = value
        case .tap(let active):
            tapActive = active
            // A tap change invalidates the previous activity list: those lines
            // describe a session that has ended, and leaving them on screen would
            // make a stale success look current.
            diagnostics.removeAll()
            // Mirror to UserDefaults so an outside probe can read the *measured*
            // tap state. AppleScript cannot inspect this app (no AX grant for the
            // shell), so this is the only trustworthy external signal.
            UserDefaults.standard.set(["active": active, "failure": tapFailure, "trusted": trusted],
                                      forKey: "mouseGestures.lastTapState")
        case .tapFailure(let reason):
            tapFailure = reason
            diagnostics.removeAll()
            UserDefaults.standard.set(["active": tapActive, "failure": reason, "trusted": trusted],
                                      forKey: "mouseGestures.lastTapState")
        case .recordingEnded: recording = false
        case .trigger(let source):
            configuration.trigger = source
            // Persist, and repair the scroll button if the new trigger now collides
            // with it. Without this the two features would fight over one button and
            // the only symptom would be "sometimes it scrolls instead of gestures".
            configuration.validate()
            persist(); apply()
        case .shortcut(let bundle, let direction, let shortcut):
            configuration.overrides[bundle, default: [:]][direction] = .shortcut(shortcut)
            persist()
            engine.send(.configure(configuration))
        case .diagnostics(let entries):
            diagnostics = entries
        case .observedPress(let button):
            observedPress = button
        }
    }
}
