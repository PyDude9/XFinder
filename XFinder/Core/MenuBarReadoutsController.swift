import AppKit

/// The live half of menu-bar readouts: owns the ONE timer (only while enabled), asks
/// `SystemMonitorManager` for a one-shot sample on each tick, and writes the title next to the
/// status-item icon. Formatting and width rules are `MenuBarReadouts` (pure, tested).
///
/// Cost model, honest: off ⇒ no timer, no title. On ⇒ one full metrics sample every N seconds
/// (user-chosen, default 15). While a metrics page or the popover is open the monitor already
/// ticks at 1–5 s, so the readouts follow that cadence instead of sampling twice.
@MainActor
@Observable
final class MenuBarReadoutsController {
    static let shared = MenuBarReadoutsController()

    static let intervalKey = "menubar.readoutInterval"

    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private(set) var isRunning = false
    private(set) var lastTitle = ""

    private init() {}

    /// Called once by `MenubarController.setup()`.
    func attach(_ button: NSStatusBarButton) {
        self.button = button
        SystemMonitorManager.shared.onUpdate = { [weak self] in self?.render() }
        applySettings()
    }

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "menubar.readoutsEnabled") as? Bool ?? false }

    var selection: [MenuBarReadouts.Kind] {
        get { MenuBarReadouts.decode(UserDefaults.standard.string(forKey: MenuBarReadouts.selectionKey)) }
        set { UserDefaults.standard.set(MenuBarReadouts.encode(newValue), forKey: MenuBarReadouts.selectionKey); render() }
    }

    var interval: Int {
        get { MenuBarReadouts.validInterval(UserDefaults.standard.object(forKey: "menubar.readoutInterval") as? Int ?? 15) }
        set { UserDefaults.standard.set(MenuBarReadouts.validInterval(newValue), forKey: Self.intervalKey); if isRunning { start() } }
    }

    func applySettings() {
        if isEnabled { start() } else { stop() }
    }

    private func start() {
        timer?.invalidate()
        isRunning = true
        let t = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Seed first, render a second later: CPU is a delta since the previous sample, and right
        // after launch that previous sample is the launch itself — measured, the first title read
        // "CPU 89%" for one whole interval on an idle machine. One quiet sample fixes the baseline.
        let m = SystemMonitorManager.shared
        if !m.hasConsumers { m.sampleNow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        isRunning = false
        lastTitle = ""
        button?.attributedTitle = NSAttributedString(string: "")
        button?.imagePosition = .imageOnly
    }

    private func tick() {
        let m = SystemMonitorManager.shared
        // A page/popover already samples at its own cadence; do not sample twice.
        if !m.hasConsumers { m.sampleNow() }
        render()
    }

    private func render() {
        guard isRunning, let button else { return }
        let x = SystemMonitorManager.shared.currentMetrics
        let snap = MenuBarReadouts.Snapshot(
            cpuPercent: x.cpuUsage, memoryUsedBytes: x.memoryTotal > 0 ? x.memoryUsed : nil,
            gpuPercent: x.gpuUsage, socTemperature: x.socTempMax,
            batteryPercent: x.batteryLevel > 0 ? x.batteryLevel : nil,
            downKBs: x.networkDownload, upKBs: x.networkUpload)
        let title = MenuBarReadouts.title(for: selection, snapshot: snap, label: { L10n.t($0) })
        lastTitle = title
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font, .baselineOffset: 0.5])
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    }
}
