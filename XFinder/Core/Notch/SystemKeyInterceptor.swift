import AppKit
import CoreGraphics

/// Swallows the brightness / volume system keys so macOS stops drawing its own square, and applies the
/// change itself — the notch becomes the only readout.
///
/// Owner's request, 2026-10-15: *"khi tôi sử dụng báo tình trạng thực trên Notch thì tôi muốn ẩn luôn cái
/// Status Brightness, Volume mặc định popover mặc định của MacOS, chỉ dùng trong Notch là đủ."*
///
/// Measured by the agent that built it (probe run from a terminal, 2026-10-15, macOS 27):
///   * a `.cghidEventTap` tap on `systemDefined` (type 14, subtype 8) **receives** the brightness and volume
///     keys — `data1` carries the key type in bits 16+ and the phase in bits 8…15 (0xA down, 0xB up);
///   * returning `nil` **suppresses the native OSD** for volume *and* brightness (the layer-101
///     `MenuBarAgent` window never appears), while the change applied by us really lands;
///   * a bare programmatic change (CoreAudio / `DisplayServices`) **never** draws the OSD on its own.
///
/// So every "may I?" is `LiveActivity.HUDSuppression.decide` (pure, tested); this type only does the I/O.
/// It is armed only while the user asked for it (`notch.activity.hideSystemHUD`) **and** Accessibility is
/// granted — without trust `CGEvent.tapCreate` returns nil and macOS keeps its own HUD, which is the honest
/// fallback. When a notice cannot be drawn (notch off, that kind switched off, brightness not writable) the
/// key is passed through for the same reason: XFinder must never swallow the only feedback.
///
/// Live behaviour is **not verified inside the app** — T-HUD in docs/PENDING_TESTS_AND_DECISIONS.md.
@MainActor
final class SystemKeyInterceptor {
    static let shared = SystemKeyInterceptor()

    /// `NX_SYSDEFINED` is CGEvent type 14 — it has no `CGEventType` case in the SDK, so it is compared by raw
    /// value. Its events carry `subtype 8` (probe-measured).
    private nonisolated static let systemDefinedType: UInt32 = 14
    private nonisolated static let nxSubtype = NSEvent.EventSubtype(rawValue: 8)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    /// The single canonical reader for this key (`FeatureKeyDefaultsTests` wants exactly one). It must stay
    /// `nonisolated` so the tap thread can read it without hopping to the main actor.
    nonisolated static var hideSystemHUDEnabled: Bool {
        UserDefaults.standard.object(forKey: "notch.activity.hideSystemHUD") as? Bool ?? true
    }

    /// Called at launch, on `didBecomeActive` (Accessibility granted later) and from the page's switch.
    func applySettings() {
        guard Self.hideSystemHUDEnabled, WindowManager.isTrusted else { teardown(); return }
        setup()
    }

    // MARK: - Tap

    private func setup() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1) << Self.systemDefinedType
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<SystemKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }                       // no trust: macOS keeps its own HUD
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func teardown() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func rearm() {
        if let tap = eventTap, CFMachPortIsValid(tap) { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: - The tap callback

    /// The DOWN/UP bookkeeping (`HUDSuppression.Pairing`); main-actor state, read only from `handle`.
    private var pairing = LiveActivity.HUDSuppression.Pairing()

    /// The tap's run-loop source is added to the MAIN run loop in `setup()` (which is main-actor), so this
    /// runs on the main thread and can decide synchronously with the app's own readers — no stand-in copies
    /// of `notch.activities`, `notch.activity.volume`/`brightness` or `dropTray.notchEnabled` here. The
    /// *work* is deferred so the event returns at once.
    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // A tap disabled by timeout must be re-armed or XFinder stops seeing the keys (they then reach macOS).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if type == .tapDisabledByTimeout { DiagnosticsLog.record("eventTap", "timeout.systemKeys") }
            MainActor.assumeIsolated { self.rearm() }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.systemDefinedType else { return Unmanaged.passUnretained(event) }
        // Our own NX fallback (when `DisplayServices` is unavailable) posts these keys — never swallow those.
        if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier) {
            return Unmanaged.passUnretained(event)
        }
        guard let ns = NSEvent(cgEvent: event), ns.subtype == Self.nxSubtype else {
            return Unmanaged.passUnretained(event)
        }
        let data1 = ns.data1
        let phase = LiveActivity.HUDSuppression.phase(data1: data1)
        let keyType = (data1 >> 16) & 0xFFFF
        let modifiersHeld = !event.flags.intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand]).isEmpty
        let decision = MainActor.assumeIsolated {
            self.resolve(keyType: keyType, phase: phase, modifiersHeld: modifiersHeld)
        }
        guard case .consume = decision else { return Unmanaged.passUnretained(event) }
        return nil
    }

    private func resolve(keyType: Int, phase: LiveActivity.HUDSuppression.Phase,
                         modifiersHeld: Bool) -> LiveActivity.HUDSuppression.Decision {
        let decision = pairing.resolve(keyType: keyType, phase: phase) {
            guard let key = LiveActivity.MediaKey(rawValue: keyType) else { return .passThrough }
            return LiveActivity.HUDSuppression.decide(keyType: keyType, phase: phase,
                                                      context: context(for: key, modifiersHeld: modifiersHeld))
        }
        if phase == .down, case .consume(let key) = decision {
            Task { @MainActor in self.apply(key) }
        }
        return decision
    }

    /// The writability checks cost a CoreAudio / DisplayServices round trip, so only the one the key needs
    /// is asked; the other is irrelevant to `decide` for that key and left false.
    private func context(for key: LiveActivity.MediaKey, modifiersHeld: Bool) -> LiveActivity.HUDSuppression.Context {
        let monitor = LiveActivityMonitor.shared
        let volumeWritable: Bool
        switch key {
        case .mute: volumeWritable = SystemControls.canSetMute()
        case .volumeUp, .volumeDown: volumeWritable = SystemControls.canSetVolume()
        case .brightnessUp, .brightnessDown: volumeWritable = false
        }
        return .init(hideSystemHUD: Self.hideSystemHUDEnabled,
                     canPresent: NotchSurfaceController.shared.canPresentActivities,
                     masterOn: monitor.master,
                     volumeOn: monitor.volumeOn,
                     brightnessOn: monitor.brightnessOn,
                     brightnessWritable: key.isVolume ? false : ScreenBrightness.canSetDirectly,
                     volumeWritable: volumeWritable,
                     modifiersHeld: modifiersHeld)
    }

    // MARK: - Apply

    private func apply(_ key: LiveActivity.MediaKey) {
        switch key {
        case .volumeUp:   stepVolume(up: true)
        case .volumeDown: stepVolume(up: false)
        case .mute:       SystemControls.setMuted(!SystemControls.isMuted())   // VolumeObserver reports it
        case .brightnessUp:   stepBrightness(up: true)
        case .brightnessDown: stepBrightness(up: false)
        }
    }

    /// One 1/16 step, as the system's own keys do (probe-measured `0.0625`). Volume-up on a muted device
    /// unmutes first, which is what macOS does. A changed level reaches the notch through CoreAudio
    /// (`VolumeObserver` → `LiveActivityMonitor`); an unchanged one (already at 0 or 1) is reported here,
    /// because CoreAudio then says nothing and the key would look dead.
    private func stepVolume(up: Bool) {
        if up, SystemControls.isMuted() { SystemControls.setMuted(false); return }
        let before = SystemControls.getVolume()
        let step = 1.0 / 16.0
        SystemControls.setVolume(before + (up ? step : -step))
        let after = SystemControls.getVolume()
        if abs(after - before) < 0.005 {
            LiveActivityMonitor.shared.volumeKeyedWithoutChange(.init(level: after, muted: SystemControls.isMuted()))
        }
    }

    /// Steps from the LIVE level, not the cached one: `ScreenBrightness.level` only refreshes while a page
    /// retains it, so after a Control Centre or auto-brightness change it can be minutes stale.
    private func stepBrightness(up: Bool) {
        let brightness = ScreenBrightness.shared
        brightness.refresh()
        guard let current = brightness.level else { return }
        let step = 1.0 / 16.0
        brightness.setLevel(min(max(current + (up ? step : -step), 0), 1))
        LiveActivityMonitor.shared.brightnessKeyed(level: brightness.level ?? current)
    }
}
