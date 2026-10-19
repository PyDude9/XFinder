import AppKit
import IOKit.ps
import Network
import IOBluetooth
import os

/// Feeds live activities to the Notch surface (B4). Every source is an OS event, armed only while
/// its switch is on: the IOPS power notification, NWPathMonitor, a flagsChanged monitor pair for
/// Caps Lock, and IOBluetooth connect / disconnect notifications. No polling.
///
/// Each switch is read at point of use with its own default (FeatureKeyDefaultsTests pins them).
/// The first reading of every source is a baseline, so launching the app announces nothing.
@MainActor
final class LiveActivityMonitor: NSObject {
    static let shared = LiveActivityMonitor()

    // MARK: Settings

    /// Read by `SystemKeyInterceptor` too, so these three are not private — one reader per key.
    var master: Bool { UserDefaults.standard.object(forKey: "notch.activities") as? Bool ?? true }
    private var powerOn: Bool { UserDefaults.standard.object(forKey: "notch.activity.power") as? Bool ?? true }
    private var networkOn: Bool { UserDefaults.standard.object(forKey: "notch.activity.network") as? Bool ?? true }
    private var capsLockOn: Bool { UserDefaults.standard.object(forKey: "notch.activity.capsLock") as? Bool ?? true }
    private var bluetoothOn: Bool { UserDefaults.standard.object(forKey: "notch.activity.bluetooth") as? Bool ?? true }
    private var alertsOn: Bool { UserDefaults.standard.object(forKey: "notch.activity.alerts") as? Bool ?? true }
    var volumeOn: Bool { UserDefaults.standard.object(forKey: "notch.activity.volume") as? Bool ?? true }
    var brightnessOn: Bool { UserDefaults.standard.object(forKey: "notch.activity.brightness") as? Bool ?? true }

    /// AlertMonitor asks this before choosing between the notch and its own banner.
    var routesAlertsToNotch: Bool { master && alertsOn && NotchSurfaceController.shared.canPresentActivities }

    func applySettings() {
        let on = master
        on && powerOn ? startPower() : stopPower()
        on && networkOn ? startNetwork() : stopNetwork()
        on && capsLockOn ? startCapsLock() : stopCapsLock()
        on && bluetoothOn ? startBluetooth() : stopBluetooth()
        on && volumeOn ? startVolume() : stopVolume()
    }

    private func present(_ item: LiveActivity.Item?) {
        guard let item else { return }
        NotchSurfaceController.shared.present(item)
    }

    // MARK: Power — IOPSNotificationCreateRunLoopSource fires on any power-source change

    private var powerSource: CFRunLoopSource?
    private var lastPower: LiveActivity.PowerState?

    private func startPower() {
        guard powerSource == nil else { return }
        lastPower = Self.readPower()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<LiveActivityMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.powerChanged() }        // delivered on the main run loop
        }, ctx)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        powerSource = src
    }

    private func stopPower() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil; lastPower = nil
    }

    private func powerChanged() {
        guard let now = Self.readPower() else { return }
        for item in LiveActivity.powerItems(old: lastPower, new: now) { present(item) }
        lastPower = now
    }

    private static func readPower() -> LiveActivity.PowerState? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int, max = d[kIOPSMaxCapacityKey] as? Int
            let pct = (cur != nil && max != nil && max! > 0) ? Int((Double(cur!) / Double(max!) * 100).rounded()) : nil
            return LiveActivity.PowerState(onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                                           percent: pct,
                                           charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                           charged: d[kIOPSIsChargedKey] as? Bool ?? false)
        }
        return nil                                          // a desktop Mac: no battery, no power notices
    }

    // MARK: Network — NWPathMonitor

    private var pathMonitor: NWPathMonitor?
    private var lastOnline: Bool?

    private func startNetwork() {
        guard pathMonitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online) }
        }
        m.start(queue: .main)
        pathMonitor = m
    }

    private func stopNetwork() {
        pathMonitor?.cancel(); pathMonitor = nil; lastOnline = nil
    }

    private func networkChanged(_ online: Bool) {
        present(LiveActivity.networkItem(wasOnline: lastOnline, isOnline: online))
        lastOnline = online
    }

    // MARK: Caps Lock — the mandatory global + local monitor pair (CLAUDE.md Part 3c)

    private var capsMonitors: [Any] = []
    private var lastCaps: Bool?

    private func startCapsLock() {
        guard capsMonitors.isEmpty else { return }
        lastCaps = NSEvent.modifierFlags.contains(.capsLock)
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            let on = e.modifierFlags.contains(.capsLock)
            runOnMainActor { self?.capsChanged(on) }
        }) { capsMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            let on = e.modifierFlags.contains(.capsLock)
            MainActor.assumeIsolated { self?.capsChanged(on) }
            return e
        }) { capsMonitors.append(l) }
    }

    private func stopCapsLock() {
        capsMonitors.forEach { NSEvent.removeMonitor($0) }; capsMonitors.removeAll(); lastCaps = nil
    }

    private func capsChanged(_ on: Bool) {
        present(LiveActivity.capsLockItem(wasOn: lastCaps, isOn: on))
        lastCaps = on
    }

    // MARK: Volume — VolumeObserver's CoreAudio listeners (ref-counted; held only while this switch is on)

    private var volumeRetained = false
    private var lastVolume: LiveActivity.VolumeState?

    private func startVolume() {
        guard !volumeRetained else { return }
        let obs = VolumeObserver.shared
        obs.retain()
        volumeRetained = true
        lastVolume = .init(level: obs.volume, muted: obs.isMuted)
        obs.onChange = { [weak self] level, muted in self?.volumeChanged(level, muted) }
    }

    private func stopVolume() {
        guard volumeRetained else { return }
        VolumeObserver.shared.onChange = nil
        VolumeObserver.shared.release()
        volumeRetained = false; lastVolume = nil
    }

    private func volumeChanged(_ level: Double, _ muted: Bool) {
        let now = LiveActivity.VolumeState(level: level, muted: muted)
        present(LiveActivity.volumeItem(old: lastVolume, new: now))
        lastVolume = now
    }

    // MARK: Brightness / volume keys XFinder took (`SystemKeyInterceptor`)

    /// Nothing observes brightness, so the key XFinder just applied reports the level it landed on. The
    /// native square is swallowed for that key, so this is the ONLY readout — it answers even at 0 or 1.
    func brightnessKeyed(level: Double) {
        guard master, brightnessOn, NotchSurfaceController.shared.canShowKeyFeedback else { return }
        present(LiveActivity.brightnessItem(level: level))
    }

    /// A volume key XFinder took. Presented at once with the level just set, instead of waiting for CoreAudio's
    /// change notification (6–14 ms later, measured) — and it is the only answer when the level could not move
    /// (already at 0 or 1), because CoreAudio reports nothing then. The notification that follows carries the
    /// same item and simply replaces it.
    func volumeKeyed(_ state: LiveActivity.VolumeState) {
        guard master, volumeOn, NotchSurfaceController.shared.canShowKeyFeedback else { return }
        present(LiveActivity.volumeItem(state))
    }

    // MARK: Bluetooth — connect notification, then a per-device disconnect notification

    private var connectNote: IOBluetoothUserNotification?
    /// Per-device disconnect registrations. They are created inside the IOBluetooth callback (not on
    /// the main actor), so they live behind a lock; only Sendable values (a name, a flag) cross to main.
    private nonisolated let disconnectNotes = OSAllocatedUnfairLock<[IOBluetoothUserNotification]>(uncheckedState: [])
    private var armedAt = Date.distantFuture

    private func startBluetooth() {
        guard connectNote == nil else { return }
        // IOBluetooth reports every ALREADY-connected device right after registering; those are
        // the baseline, not news. Anything in the first second is treated as such.
        armedAt = Date().addingTimeInterval(1)
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    private func stopBluetooth() {
        connectNote?.unregister(); connectNote = nil
        disconnectNotes.withLockUnchecked { notes in notes.forEach { $0.unregister() }; notes.removeAll() }
    }

    // IOBluetooth does NOT always call back on the main thread. Measured 2026-10-11 (crash report
    // XFinder-2026-10-11-061620): a real connect arrived on `com.apple.bluetooth.iobluetooth.coordinatorQueue`
    // (CoreBluetooth's XPC path), and `MainActor.assumeIsolated` here trapped the whole app the moment
    // the user's Bluetooth device reconnected. Registration and bookkeeping stay here (lock-protected);
    // only the device NAME crosses, through `runOnMainActor` — synchronous on main, a hop otherwise.
    @objc nonisolated private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let n = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
            disconnectNotes.withLockUnchecked { $0.append(n) }
        }
        let name = device.name ?? "Bluetooth"
        runOnMainActor { [weak self] in
            guard let self, Date() >= self.armedAt else { return }   // already connected at registration: baseline
            self.present(LiveActivity.bluetoothItem(name: name, connected: true))
        }
    }

    @objc nonisolated private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        disconnectNotes.withLockUnchecked { notes in notes.removeAll { $0 === note } }
        let name = device.name ?? "Bluetooth"
        runOnMainActor { [weak self] in self?.present(LiveActivity.bluetoothItem(name: name, connected: false)) }
    }
}
