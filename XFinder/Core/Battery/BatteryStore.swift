import Foundation
import Combine

@MainActor
@Observable
public final class BatteryStore: ObservableObject {
    public static let shared = BatteryStore()

    public private(set) var macBattery: ConnectedDeviceBattery?
    public private(set) var connectedDevices: [ConnectedDeviceBattery] = []
    public private(set) var allDevices: [ConnectedDeviceBattery] = []
    public private(set) var isPolling: Bool = false
    public private(set) var lastRefresh: Date = .distantPast

    private var retainCount = 0
    private var macTask: Task<Void, Never>?
    private var bluetoothTask: Task<Void, Never>?
    private var hidTask: Task<Void, Never>?

    private var cachedMagicDevices: [ConnectedDeviceBattery] = []
    private var cachedBluetoothDevices: [ConnectedDeviceBattery] = []
    private var cachedHIDDevices: [ConnectedDeviceBattery] = []

    private let macProvider: BatteryProvider
    private let hidProvider: BatteryProvider
    private let bluetoothProvider: BatteryProvider
    private let magicReader: (@Sendable () -> [MagicBatteryItem])?

    public init(
        macProvider: BatteryProvider = MacPowerSourceProvider(),
        hidProvider: BatteryProvider = HIDBatteryProvider(),
        bluetoothProvider: BatteryProvider = BluetoothBatteryProvider(),
        magicReader: (@Sendable () -> [MagicBatteryItem])? = nil
    ) {
        self.macProvider = macProvider
        self.hidProvider = hidProvider
        self.bluetoothProvider = bluetoothProvider
        self.magicReader = magicReader
    }

    // MARK: - Lifecycle

    public func start() {
        BLEBatteryGATT.shared.startScan()
        Task {
            await refresh()
        }
    }

    public func updateGATTDevice(deviceID: String, name: String, percent: Int) {
        NSLog("BatteryStore GATT level: %d for %@", percent, name)
        let lowerName = name.lowercased()
        if let idx = cachedBluetoothDevices.firstIndex(where: { $0.name.lowercased() == lowerName || $0.id.contains(deviceID) }) {
            let existing = cachedBluetoothDevices[idx]
            cachedBluetoothDevices[idx] = ConnectedDeviceBattery(
                id: existing.id,
                name: existing.name,
                kind: existing.kind != .other ? existing.kind : DeviceBatteryKind.infer(from: name),
                percent: percent,
                isCharging: existing.isCharging,
                source: .bluetooth,
                lastUpdated: Date(),
                isConnected: true,
                leftPercent: existing.leftPercent,
                rightPercent: existing.rightPercent,
                casePercent: existing.casePercent
            )
        } else {
            let kind = DeviceBatteryKind.infer(from: name)
            cachedBluetoothDevices.append(ConnectedDeviceBattery(
                id: "ble-\(deviceID)",
                name: name,
                kind: kind,
                percent: percent,
                isCharging: false,
                source: .bluetooth,
                lastUpdated: Date(),
                isConnected: true
            ))
        }
        rebuildConnectedDevices()
    }

    public func retain() {
        retainCount += 1
        if retainCount == 1 {
            startPolling()
        }
    }

    public func release() {
        retainCount = max(0, retainCount - 1)
        if retainCount == 0 {
            stopPolling()
        }
    }

    public func refresh() async {
        async let mac = macProvider.fetchBatteries()
        async let bt = bluetoothProvider.fetchBatteries()
        async let hid = hidProvider.fetchBatteries()

        let magicItems: [ConnectedDeviceBattery] = {
            if let customReader = magicReader {
                return customReader().map { m in
                    ConnectedDeviceBattery(
                        id: m.deviceID,
                        name: m.name,
                        kind: m.kind,
                        percent: m.percent,
                        isCharging: m.isCharging,
                        source: .hid,
                        lastUpdated: Date(),
                        isConnected: true
                    )
                }
            } else if macProvider is MacPowerSourceProvider {
                return MagicBatteryReader.shared.scanDevices().map { m in
                    ConnectedDeviceBattery(
                        id: m.deviceID,
                        name: m.name,
                        kind: m.kind,
                        percent: m.percent,
                        isCharging: m.isCharging,
                        source: .hid,
                        lastUpdated: Date(),
                        isConnected: true
                    )
                }
            } else {
                return []
            }
        }()

        let (mList, bList, hList) = await (mac, bt, hid)
        updateMac(mList)
        updateMagic(magicItems)
        updateBluetooth(bList)
        updateHID(hList)
        lastRefresh = Date()
    }

    // MARK: - Background Polling

    private func startPolling() {
        guard !isPolling else { return }
        isPolling = true

        BLEBatteryGATT.shared.startScan()

        // Initial fetch
        Task { [weak self] in
            await self?.refresh()
        }

        // Mac battery: 5s interval
        macTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self = self else { break }
                let items = await self.macProvider.fetchBatteries()
                await MainActor.run {
                    self.updateMac(items)
                }
            }
        }

        // Bluetooth devices & Magic devices: 30s interval
        bluetoothTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self = self else { break }
                let magic = await MainActor.run { () -> [ConnectedDeviceBattery] in
                    if let custom = self.magicReader {
                        return custom().map { m in
                            ConnectedDeviceBattery(
                                id: m.deviceID,
                                name: m.name,
                                kind: m.kind,
                                percent: m.percent,
                                isCharging: m.isCharging,
                                source: .hid,
                                lastUpdated: Date(),
                                isConnected: true
                            )
                        }
                    } else if self.macProvider is MacPowerSourceProvider {
                        return MagicBatteryReader.shared.scanDevices().map { m in
                            ConnectedDeviceBattery(
                                id: m.deviceID,
                                name: m.name,
                                kind: m.kind,
                                percent: m.percent,
                                isCharging: m.isCharging,
                                source: .hid,
                                lastUpdated: Date(),
                                isConnected: true
                            )
                        }
                    }
                    return []
                }
                let btItems = await self.bluetoothProvider.fetchBatteries()
                await MainActor.run {
                    self.updateMagic(magic)
                    self.updateBluetooth(btItems)
                }
            }
        }

        // HID devices: 60s interval
        hidTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self = self else { break }
                let items = await self.hidProvider.fetchBatteries()
                await MainActor.run {
                    self.updateHID(items)
                }
            }
        }
    }

    private func stopPolling() {
        isPolling = false
        macTask?.cancel()
        macTask = nil
        bluetoothTask?.cancel()
        bluetoothTask = nil
        hidTask?.cancel()
        hidTask = nil
    }

    // MARK: - Internal Updates

    private func updateMac(_ items: [ConnectedDeviceBattery]) {
        macBattery = items.first
        rebuildAllDevices()
    }

    private func updateMagic(_ items: [ConnectedDeviceBattery]) {
        cachedMagicDevices = items
        rebuildConnectedDevices()
    }

    private func updateBluetooth(_ items: [ConnectedDeviceBattery]) {
        cachedBluetoothDevices = items
        rebuildConnectedDevices()
    }

    private func updateHID(_ items: [ConnectedDeviceBattery]) {
        cachedHIDDevices = items
        rebuildConnectedDevices()
    }

    private func mergePeripheralDevices() -> [ConnectedDeviceBattery] {
        var merged: [ConnectedDeviceBattery] = []
        var nameToIndex: [String: Int] = [:]

        func mergeDevice(_ dev: ConnectedDeviceBattery) {
            let key = dev.name.lowercased()
            if let existingIdx = nameToIndex[key] {
                let existing = merged[existingIdx]
                let bestPercent: Int
                if existing.percent >= 0 {
                    bestPercent = existing.percent
                } else if dev.percent >= 0 {
                    bestPercent = dev.percent
                } else {
                    bestPercent = -1
                }
                let bestCharging = dev.isCharging || existing.isCharging
                let bestConnected = dev.isConnected || existing.isConnected
                let bestKind = dev.kind != .other ? dev.kind : existing.kind
                let bestLeft = dev.leftPercent ?? existing.leftPercent
                let bestRight = dev.rightPercent ?? existing.rightPercent
                let bestCase = dev.casePercent ?? existing.casePercent
                merged[existingIdx] = ConnectedDeviceBattery(
                    id: existing.id,
                    name: existing.name,
                    kind: bestKind,
                    percent: bestPercent,
                    isCharging: bestCharging,
                    source: existing.source,
                    lastUpdated: Date(),
                    isConnected: bestConnected,
                    leftPercent: bestLeft,
                    rightPercent: bestRight,
                    casePercent: bestCase
                )
            } else {
                nameToIndex[key] = merged.count
                merged.append(dev)
            }
        }

        // Priority 1: Magic Devices (Direct IOKit with accurate % and charge flag)
        for dev in cachedMagicDevices { mergeDevice(dev) }
        // Priority 2: Bluetooth Devices (system_profiler + IOBluetooth)
        for dev in cachedBluetoothDevices { mergeDevice(dev) }
        // Priority 3: Generic HID
        for dev in cachedHIDDevices { mergeDevice(dev) }

        return merged
    }

    private func rebuildConnectedDevices() {
        let merged = mergePeripheralDevices()
        let onlyConnected = merged.filter { $0.isConnected }
        connectedDevices = onlyConnected.sorted { a, b in
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        rebuildAllDevices(with: merged)
    }

    private func rebuildAllDevices(with peripherals: [ConnectedDeviceBattery]? = nil) {
        var all: [ConnectedDeviceBattery] = []
        if let mac = macBattery {
            all.append(mac)
        }
        let items = peripherals ?? mergePeripheralDevices()

        all.append(contentsOf: items.sorted { a, b in
            if a.isConnected != b.isConnected {
                return a.isConnected && !b.isConnected
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        })
        allDevices = all
    }
}
