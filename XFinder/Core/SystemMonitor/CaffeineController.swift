import Foundation
import IOKit.pwr_mgt
import IOKit.ps

/// Prevents idle sleep/screensaver for a bounded duration. Public API only:
/// `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep)`, plus (XF-T27, default on)
/// `PreventUserIdleDisplaySleep` so the SCREEN stays on too. A hold survives a relaunch or an update (its end is stored
/// in `caffeine.until`) and ends on its own when the Mac runs on battery at ≤ 10 % (power-source notifications only
/// while a hold is on). Rules: `CaffeineRules`.
@MainActor
@Observable
final class CaffeineController {
    static let shared = CaffeineController()

    var isActive = false
    var remainingSeconds: Int? = nil

    private var assertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var lidAssertionID: IOPMAssertionID = 0
    /// ONE reader (XF-T27 §2.1b): default false.
    private(set) var requestLidWake: Bool = UserDefaults.standard.object(forKey: "caffeine.requestLidWake") as? Bool ?? false
    private(set) var lidAssertionActive = false
    private(set) var isOnACPower: Bool = CaffeineController.currentACPower()
    private var timer: Timer?

    var lidWakeState: CaffeineRules.LidWakeState {
        CaffeineRules.lidWakeState(
            requested: requestLidWake,
            caffeineActive: isActive,
            onACPower: isOnACPower,
            assertionActive: lidAssertionActive
        )
    }
    private var powerSource: CFRunLoopSource?
    /// Why the last hold ended on its own (the page and the menu show it once).
    var endedForBattery = false

    /// ONE reader (the System page's toggle binds the same key, default true).
    var keepDisplayOn: Bool { UserDefaults.standard.object(forKey: "caffeine.keepDisplayOn") as? Bool ?? true }
    private var storedUntil: Double { UserDefaults.standard.object(forKey: "caffeine.until") as? Double ?? 0 }

    private init() {}

    enum Duration {
        case indefinite
        case minutes(Int)
        var seconds: Int? {
            switch self {
            case .indefinite: return nil
            case .minutes(let m): return m * 60
            }
        }
    }

    /// At launch: a hold that was running when the app quit (or was updated) carries on for what is left.
    func restoreIfNeeded() {
        switch CaffeineRules.resume(stored: storedUntil, now: Date()) {
        case .none: UserDefaults.standard.set(CaffeineRules.off, forKey: CaffeineRules.Key.until)
        case .indefinite: activate(duration: .indefinite)
        case .minutesLeft(let m): activate(duration: .minutes(m))
        }
    }

    /// The display half follows the toggle at once while a hold runs.
    func applyDisplaySetting() {
        guard isActive else { return }
        if keepDisplayOn, displayAssertionID == 0 {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "XFinder: Chống ngủ (màn hình)" as CFString, &id) == kIOReturnSuccess { displayAssertionID = id }
        } else if !keepDisplayOn, displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID); displayAssertionID = 0
        }
    }

    func activate(duration: Duration) {
        if isActive { deactivate() }
        if Self.batteryTooLow() { endedForBattery = true; return }
        endedForBattery = false
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "XFinder: Chống ngủ" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isActive = true
        applyDisplaySetting()
        applyLidSetting()
        UserDefaults.standard.set(CaffeineRules.storedUntil(start: Date(), minutes: duration.seconds.map { $0 / 60 }),
                                  forKey: CaffeineRules.Key.until)
        watchPower()
        if let s = duration.seconds {
            remainingSeconds = s
            scheduleCountdown()
        } else {
            remainingSeconds = nil
        }
    }

    func deactivate() {
        if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
        if displayAssertionID != 0 { IOPMAssertionRelease(displayAssertionID); displayAssertionID = 0 }
        releaseLidAssertion()
        timer?.invalidate(); timer = nil
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        UserDefaults.standard.set(CaffeineRules.off, forKey: CaffeineRules.Key.until)
        isActive = false
        remainingSeconds = nil
    }

    private func scheduleCountdown() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remainingSeconds != nil {
                    let remaining = Int(ceil(self.storedUntil - Date().timeIntervalSince1970))
                    if remaining <= 0 { self.deactivate() }
                    else { self.remainingSeconds = remaining }
                }
            }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    /// Power-source changes (plugged / unplugged / percentage), only while a hold is on. The source is added to the MAIN
    /// run loop, so the callback runs on the main thread.
    private func watchPower() {
        guard powerSource == nil else { return }
        guard let src = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated {
                CaffeineController.shared.checkBattery()
                CaffeineController.shared.applyLidSetting()
            }
        }, nil)?.takeRetainedValue() else { return }
        powerSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    private func checkBattery() {
        guard isActive, Self.batteryTooLow() else { return }
        deactivate()
        endedForBattery = true
        CaffeineController.toast.show(symbol: "battery.25", title: L10n.t("Đã tắt Chống ngủ vì pin yếu."), duration: 3.0)
    }

    func setLidWakeRequested(_ requested: Bool) {
        requestLidWake = requested
        UserDefaults.standard.set(requested, forKey: CaffeineRules.Key.requestLidWake)
        applyLidSetting()
    }

    func refreshPowerState() {
        isOnACPower = Self.currentACPower()
        applyLidSetting()
    }

    private func applyLidSetting() {
        isOnACPower = Self.currentACPower()
        guard isActive, requestLidWake, isOnACPower else {
            releaseLidAssertion()
            return
        }
        guard lidAssertionID == 0 else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "XFinder: Closed-display wake request" as CFString, &id)
        if result == kIOReturnSuccess {
            lidAssertionID = id
            lidAssertionActive = true
        }
    }

    private static func currentACPower() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() else {
            return false
        }
        return (source as String) == kIOPSACPowerValue
    }

    private func releaseLidAssertion() {
        if lidAssertionID != 0 { IOPMAssertionRelease(lidAssertionID); lidAssertionID = 0 }
        lidAssertionActive = false
    }

    static let toast = ToastSurface(style: .toast)

    static func batteryTooLow() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        let descs = list.compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
        let b = CaffeineRules.internalBattery(descs)
        return CaffeineRules.shouldStopForBattery(percent: b?.percent, onBattery: b?.onBattery ?? false)
    }

    // No `deinit` release: this is a `shared` singleton that lives for the
    // whole process, so the deinit never runs — and touching main-actor state
    // from a nonisolated deinit is an error under strict concurrency anyway.
    // macOS drops the power assertion automatically when the process exits.
}
