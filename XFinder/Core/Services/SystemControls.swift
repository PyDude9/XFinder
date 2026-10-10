import Foundation
import CoreAudio
import AppKit
import Combine

/// Lifted out of `MenubarFlyoutView` so the flyout and Điều khiển nhanh share
/// one implementation. Volume via public CoreAudio HAL scalar; brightness via
/// synthesized system brightness keys (needs Accessibility trust); dark mode
/// toggles the system appearance via System Events (needs Automation).
@MainActor
enum SystemControls {

    // MARK: Volume — public, real
    static func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr
        else { return 0 }
        return deviceID
    }

    static func isMuted() -> Bool {
        let deviceID = defaultOutputDevice()
        guard deviceID != 0 else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &addr),
              AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &muted) == noErr
        else { return false }
        return muted != 0
    }

    static func setMuted(_ on: Bool) {
        let deviceID = defaultOutputDevice()
        guard deviceID != 0 else { return }
        var value: UInt32 = on ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &addr) else { return }
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &value)
    }

    static func getVolume() -> Double {
        let deviceID = defaultOutputDevice()
        guard deviceID != 0 else { return 0.5 }
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        // Some devices expose per-channel rather than master; try master then channel 1.
        if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol) == noErr { return Double(vol) }
        addr.mElement = 1
        if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol) == noErr { return Double(vol) }
        return 0.5
    }

    static func setVolume(_ value: Double) {
        let deviceID = defaultOutputDevice()
        guard deviceID != 0 else { return }
        var vol = Float32(max(0, min(value, 1)))
        let size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(deviceID, &addr) {
            AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &vol)
            return
        }
        addr.mElement = 1
        if AudioObjectHasProperty(deviceID, &addr) {
            AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &vol)
        }
    }

    // MARK: Appearance

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case light, dark, auto
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .light: return L10n.t("Sáng")
            case .dark: return L10n.t("Tối")
            case .auto: return L10n.t("Hệ thống")
            }
        }
        var icon: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .auto: return "circle.lefthalf.filled"
            }
        }
    }

    /// `UserDefaults.standard` already falls through to NSGlobalDomain for
    /// these keys — `UserDefaults(suiteName: NSGlobalDomain)` returns nil and
    /// macOS logs "does not make sense", so it must not be used here.
    /// Writes still need `/usr/bin/defaults`, since the global domain is not
    /// writable through the app's own suite.
    static func isDarkMode() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func isAutoAppearance() -> Bool {
        UserDefaults.standard.object(forKey: "AppleInterfaceStyleSwitchesAutomatically") as? Bool ?? false
    }

    static func currentAppearance() -> AppearanceMode {
        if isAutoAppearance() { return .auto }
        return isDarkMode() ? .dark : .light
    }

    /// Result of an appearance change, so the UI can explain a failure instead
    /// of silently snapping the control back.
    enum AppearanceResult {
        case ok
        case notPermitted   // Automation denied / never granted
        case failed(String)
    }

    /// Switches the system appearance via System Events (needs Automation
    /// permission for System Events). Reads back afterwards so a silent
    /// failure is reported rather than assumed to have worked.
    @discardableResult
    static func setAppearance(_ mode: AppearanceMode) async -> AppearanceResult {
        // `dark mode` and the auto-switch flag are separate settings, and the
        // auto flag has no AppleScript equivalent — it must be written to the
        // global domain via `defaults`.
        setAutoSwitch(mode == .auto)

        // In auto mode macOS owns light/dark from here on, so only an explicit
        // choice drives the AppleScript.
        guard mode != .auto else { return .ok }

        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(mode == .dark)"
        let runResult: AppearanceResult = await Task.detached {
            guard let appleScript = NSAppleScript(source: script) else {
                return .failed("Không tạo được AppleScript.")
            }
            var err: NSDictionary?
            appleScript.executeAndReturnError(&err)
            guard let err else { return .ok }
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743 = user has not granted Automation; -600 = System Events not running.
            if code == -1743 || code == -600 {
                return .notPermitted
            }
            return .failed((err[NSAppleScript.errorMessage] as? String) ?? "\(L10n.t("Lỗi "))\(code)")
        }.value

        guard case .ok = runResult else { return runResult }

        // Read-back — AppleInterfaceStyle flips within a few hundred ms.
        // `UserDefaults.standard` caches the global domain, so re-sync before
        // each read or this always reports the pre-change value.
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            if currentAppearance() == mode {
                // Automation has no preflight API; a successful change is the
                // only evidence the grant exists. Tổng quan reads this flag.
                UserDefaults.standard.set(true, forKey: "general.automationVerified")
                return .ok
            }
        }
        return .notPermitted
    }

    /// The auto light/dark flag has no AppleScript equivalent and the global
    /// domain is not writable through the app's own suite, so shell out.
    private static func setAutoSwitch(_ on: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["write", "-g", "AppleInterfaceStyleSwitchesAutomatically", "-bool", on ? "true" : "false"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    /// Opens the Automation pane so the user can tick System Events for XFinder.
    static func openAutomationPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Brightness
    // Built-in display brightness has no public setter (DisplayServices is
    // private). Brightness is a *system-defined* NSEvent (subtype 8), not a
    // regular virtual key — posting CGKeyCode 144/145 did nothing, which is
    // why the -/+ buttons appeared dead. Needs Accessibility trust. The value
    // cannot be read back, so the UI exposes steps only, never a fake percent.
    private static let nxBrightnessUp: Int32 = 2    // NX_KEYTYPE_BRIGHTNESS_UP
    private static let nxBrightnessDown: Int32 = 3  // NX_KEYTYPE_BRIGHTNESS_DOWN

    static func adjustBrightness(up: Bool) {
        let key = up ? nxBrightnessUp : nxBrightnessDown
        postSystemDefinedKey(key, down: true)
        postSystemDefinedKey(key, down: false)
    }

    private static func postSystemDefinedKey(_ key: Int32, down: Bool) {
        let flags: NSEvent.ModifierFlags = down ? NSEvent.ModifierFlags(rawValue: 0xA00) : NSEvent.ModifierFlags(rawValue: 0xB00)
        let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
        guard let event = NSEvent.otherEvent(with: .systemDefined,
                                             location: .zero,
                                             modifierFlags: flags,
                                             timestamp: 0,
                                             windowNumber: 0,
                                             context: nil,
                                             subtype: 8,
                                             data1: data1,
                                             data2: -1),
              let cg = event.cgEvent
        else { return }
        cg.post(tap: .cghidEventTap)
    }
}

/// Publishes the system output volume and reacts to *external* changes — the
/// keyboard volume keys, Control Center, another app. Without this the slider
/// only updated when the view was rebuilt, which read as "not real-time".
@MainActor
@Observable
final class VolumeObserver {
    static let shared = VolumeObserver()

    var volume: Double = SystemControls.getVolume()
    var isMuted: Bool = SystemControls.isMuted()

    private var deviceID = AudioDeviceID(0)
    private var listening = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var refCount = 0

    private init() {}

    /// Views call this `.onAppear` / `.onDisappear` so no listener is armed
    /// while the page is off-screen (idle CPU stays 0%).
    func retain() {
        refCount += 1
        if refCount == 1 { start() }
    }

    func release() {
        refCount = max(0, refCount - 1)
        if refCount == 0 { stop() }
    }

    /// Called by the slider — writes to the device without echoing back.
    func setVolume(_ value: Double) {
        volume = value
        SystemControls.setVolume(value)
    }

    func toggleMute() {
        let next = !isMuted
        SystemControls.setMuted(next)
        isMuted = next
    }

    // MARK: Listeners
    //
    // Two kinds, with different lifetimes — keeping them apart is what fixes two bugs:
    //  * the SYSTEM-level "default output device changed" listener is registered ONCE when the
    //    observer is first retained and removed when the last retain is released. It used to be
    //    added inside `start()` and never removed, while every default change called
    //    `stop(); start()` — so each device switch ADDED another copy, doubling the callbacks per
    //    change. A switcher makes device changes routine, so that growth became reachable.
    //  * the PER-DEVICE volume/mute listeners are re-bound on every default change (`rebind`).
    //    Registering the system listener first also means an output returning after none existed
    //    (`deviceID == 0`) is still noticed; it used to bail out before registering and go deaf.

    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?

    private func start() {
        addDefaultDeviceListener()
        bindDevice()
    }

    private func stop() {
        unbindDevice()
        removeDefaultDeviceListener()
    }

    /// Diagnostic: how many times the default-device listener has re-bound. It must equal the
    /// number of default-output changes. With the old leak (one more system listener per change)
    /// it grew geometrically, which is how the harness proves the leak is gone.
    private(set) var rebindCount = 0

    /// The default output changed: move the per-device listeners to the new device.
    private func rebind() {
        rebindCount += 1
        unbindDevice()
        bindDevice()
    }

    private func addDefaultDeviceListener() {
        guard defaultDeviceBlock == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.rebind() }
        }
        defaultDeviceBlock = block
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devAddr, DispatchQueue.main, block)
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceBlock else { return }
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devAddr, DispatchQueue.main, block)
        defaultDeviceBlock = nil
    }

    private func bindDevice() {
        guard !listening else { return }
        deviceID = SystemControls.defaultOutputDevice()
        // No output device right now: stay armed on the system listener and bind when one returns.
        guard deviceID != 0 else {
            volume = SystemControls.getVolume()
            isMuted = SystemControls.isMuted()
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.volume = SystemControls.getVolume()
                self.isMuted = SystemControls.isMuted()
            }
        }
        listenerBlock = block

        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)
            // Some devices only report per-channel changes.
            addr.mElement = 1
            AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)
        }

        listening = true
        volume = SystemControls.getVolume()
        isMuted = SystemControls.isMuted()
    }

    private func unbindDevice() {
        guard listening, let block = listenerBlock, deviceID != 0 else { return }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)
            addr.mElement = 1
            AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block)
        }
        listening = false
        listenerBlock = nil
    }
}
