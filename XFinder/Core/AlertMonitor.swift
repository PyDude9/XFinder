import AppKit
import UserNotifications
import IOKit.ps

/// The live half of system alerts: a 30 s timer that exists ONLY while `alerts.enabled` is on,
/// its own cheap readers (it must not retain the 2 s metrics tick for a background rule), and
/// delivery. Every decision is `AlertRules.Engine`.
///
/// Delivery is XFinder's OWN banner (`AlertBanner`), with Notification Center as a best-effort
/// extra. Measured 2026-10-10 on macOS 27: for builds signed with the self-signed `XFinder Dev`
/// certificate, `usernoted` reports `authorizationStatus: Denied` without ever prompting, drops
/// every posted record as `sourceIneligibleForIndexing`, lists nothing under System Settings ▸
/// Notifications, and a minimal test app with the same signature gets "Notifications are not
/// allowed for this application". A banner the app draws itself needs no permission, so an alert
/// can never be silently lost — and a Developer-ID build later gets Notification Center for free.
@MainActor
@Observable
final class AlertMonitor: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertMonitor()

    static let enabledKey = "alerts.enabled"
    static let thresholdsKey = "alerts.thresholds"
    /// Cooldown survives relaunch: `[kind: lastFired]`, so restarting the app cannot re-alert on a
    /// condition that was already announced minutes ago.
    static let lastFiredKey = "alerts.lastFired"
    static let tickSeconds: TimeInterval = 30

    private(set) var lastSample: AlertRules.Sample?
    private(set) var lastTick: Date?
    private(set) var recent: [AlertRules.Event] = []
    private(set) var notificationsAuthorized: Bool?   // nil until asked
    private(set) var isRunning = false

    private var timer: Timer?
    private var engine = AlertRules.Engine()
    private var prevTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private let thermal = ThermalReader()
    private let banner = AlertBanner()

    private override init() { super.init() }

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "alerts.enabled") as? Bool ?? false }

    var thresholds: AlertRules.Thresholds {
        get {
            guard let d = UserDefaults.standard.data(forKey: Self.thresholdsKey),
                  let t = try? JSONDecoder().decode(AlertRules.Thresholds.self, from: d) else { return AlertRules.Thresholds() }
            return t.validated()
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue.validated()), forKey: Self.thresholdsKey)
            // Changed rules start fresh so a lowered threshold cannot inherit an "armed off" state.
            engine = AlertRules.Engine()
        }
    }

    func applySettings() {
        if isEnabled { start() } else { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        isRunning = true
        UNUserNotificationCenter.current().delegate = self
        requestAuthorizationIfNeeded()
        prevTicks = Self.readTicks()   // seed so the first tick has a delta
        engine = Self.loadEngine()
        let t = Timer(timeInterval: Self.tickSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        isRunning = false
        engine = AlertRules.Engine()
    }

    func requestAuthorizationIfNeeded() {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                var granted = false
                granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
                notificationsAuthorized = granted
            case .authorized, .provisional: notificationsAuthorized = true
            default: notificationsAuthorized = false
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    /// Delivers one notification right now so the user can see what an alert looks like.
    func sendTest() {
        deliver(.init(kind: .cpu, value: 97, at: Date()), test: true)
    }

    // MARK: Tick

    func tick() {
        let now = Date()
        let sample = readSample()
        lastSample = sample
        lastTick = now
        for e in engine.step(sample: sample, thresholds: thresholds, at: now) {
            recent.insert(e, at: 0)
            if recent.count > 20 { recent.removeLast() }
            deliver(e, test: false)
        }
        Self.saveLastFired(engine)
    }

    private static func loadEngine() -> AlertRules.Engine {
        var e = AlertRules.Engine()
        let saved = UserDefaults.standard.dictionary(forKey: lastFiredKey) as? [String: Double] ?? [:]
        for (raw, t) in saved {
            if let k = AlertRules.Kind(rawValue: raw) { e.states[k] = AlertRules.State(metSince: nil, lastFired: Date(timeIntervalSince1970: t), armedOff: false) }
        }
        return e
    }

    private static func saveLastFired(_ e: AlertRules.Engine) {
        var out: [String: Double] = [:]
        for (k, s) in e.states { if let t = s.lastFired { out[k.rawValue] = t.timeIntervalSince1970 } }
        UserDefaults.standard.set(out, forKey: lastFiredKey)
    }

    private func deliver(_ e: AlertRules.Event, test: Bool) {
        let title = (test ? L10n.t("Thử: ") : "") + L10n.t(e.kind.titleKey)
        let (key, value) = AlertRules.bodyKeyAndValue(for: e)
        let body = "\(L10n.t(key))\(value)"
        // B4: at the notch when the surface is on and the user keeps alert notices there; the banner
        // stays the fallback, so turning the notch off never silences an alert.
        if LiveActivityMonitor.shared.routesAlertsToNotch {
            NotchSurfaceController.shared.present(LiveActivity.Item(kind: .alert, symbol: e.kind.symbol, titleKey: e.kind.titleKey,
                                                                    detail: test ? "\(L10n.t("Thử: "))\(body)" : body,
                                                                    tint: .warning, duration: 6))
        } else {
            banner.show(symbol: e.kind.symbol, title: title, body: body)
        }
        // Best effort only: refused for self-signed builds (see the type comment).
        guard notificationsAuthorized == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: "xfinder.alert.\(e.kind.rawValue).\(Int(e.at.timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Show the banner even while XFinder is frontmost (the user may be on the Alerts page).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: Readers (cheap, no subprocess, no permission)

    private func readSample() -> AlertRules.Sample {
        var s = AlertRules.Sample()
        if let cur = Self.readTicks(), let prev = prevTicks {
            let busy = Double((cur.user &- prev.user) &+ (cur.system &- prev.system) &+ (cur.nice &- prev.nice))
            let total = busy + Double(cur.idle &- prev.idle)
            if total > 0 { s.cpuPercent = busy / total * 100 }
            prevTicks = cur
        }
        var level: Int32 = 0; var len = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &len, nil, 0) == 0 { s.memoryPressureLevel = Int(level) }
        if let a = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = a[.systemSize] as? Int64, let free = a[.systemFreeSize] as? Int64, total > 0 {
            s.diskFreePercent = Double(free) / Double(total) * 100
        }
        s.socTemperature = ThermalSensors.summary(of: thermal.read())?.socMax
        if let b = Self.readBattery() { s.batteryPercent = b.percent; s.isCharging = b.charging }
        return s
    }

    private static func readTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return (UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3))
    }

    /// nil when there is no battery (desktop Mac): the rule is then skipped, not evaluated as 0 %.
    private static func readBattery() -> (percent: Double, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (Double(cur) / Double(max) * 100, (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return nil
    }
}
