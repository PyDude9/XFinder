import Foundation
import IOBluetooth
import CoreBluetooth
import IOKit.ps

/// Dedicated CoreBluetooth GATT battery reader for generic BLE peripherals (mice, keyboards, etc.)
public final class BLEBatteryGATT: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    public static let shared = BLEBatteryGATT()

    private var centralManager: CBCentralManager?
    private var activePeripherals: [UUID: CBPeripheral] = [:]
    private var bleDevices: [String: (name: String, percent: Int, lastUpdated: Date)] = [:]
    private let lock = NSLock()
    private var isScanning = false
    private let queue = DispatchQueue.global(qos: .utility)

    public override init() {
        super.init()
    }

    public func startScan() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.centralManager == nil {
                self.centralManager = CBCentralManager(
                    delegate: self,
                    queue: self.queue,
                    options: [CBCentralManagerOptionShowPowerAlertKey: false]
                )
            } else if self.centralManager?.state == .poweredOn {
                self.performScan()
            }
        }
    }

    private func performScan() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        guard !central.isScanning && !isScanning else { return }
        isScanning = true

        let batteryUUID = CBUUID(string: "180F")

        // 1. Retrieve already connected peripherals with 180F (Battery Service)
        let connected = central.retrieveConnectedPeripherals(withServices: [batteryUUID])
        for p in connected {
            lock.withLock {
                activePeripherals[p.identifier] = p
            }
            p.delegate = self
            central.connect(p, options: nil)
            if p.state == .connected {
                p.discoverServices([batteryUUID])
            }
        }

        // 2. Scan for peripherals with 180F for 5 seconds
        central.scanForPeripherals(withServices: [batteryUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // 3. Stop scanning after 5s to keep 0% idle CPU
        queue.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            self.centralManager?.stopScan()
            self.isScanning = false
        }
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            performScan()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        let devID = peripheral.identifier.uuidString
        let alreadyCached = lock.withLock { bleDevices[devID] != nil }
        guard !alreadyCached else { return }

        lock.withLock {
            activePeripherals[peripheral.identifier] = peripheral
        }
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: "180F")])
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services where service.uuid == CBUUID(string: "180F") {
            peripheral.discoverCharacteristics([CBUUID(string: "2A19")], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for char in chars where char.uuid == CBUUID(string: "2A19") {
            peripheral.readValue(for: char)
            peripheral.setNotifyValue(true, for: char)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == CBUUID(string: "2A19"),
              let data = characteristic.value, !data.isEmpty else { return }
        let level = Int(data[0])
        guard level <= 100 else { return }

        let name = peripheral.name ?? "BLE Mouse"
        let deviceID = peripheral.identifier.uuidString
        NSLog("BatteryStore GATT level: %d for %@", level, name)

        lock.withLock {
            bleDevices[deviceID] = (name: name, percent: level, lastUpdated: Date())
        }

        Task { @MainActor in
            BatteryStore.shared.updateGATTDevice(deviceID: deviceID, name: name, percent: level)
        }
    }

    public func getReadings() -> [String: (name: String, percent: Int, lastUpdated: Date)] {
        return lock.withLock { bleDevices }
    }
}

public final class BluetoothBatteryReader: NSObject, @unchecked Sendable {
    public static let shared = BluetoothBatteryReader()

    private var lastScanTime: Date = .distantPast
    private var cachedItems: [ConnectedDeviceBattery] = []
    private let lock = NSLock()

    public override init() {
        super.init()
    }

    public func scanAsync() async -> [ConnectedDeviceBattery] {
        let (cached, isFresh) = lock.withLock { () -> ([ConnectedDeviceBattery], Bool) in
            let elapsed = Date().timeIntervalSince(lastScanTime)
            return (cachedItems, elapsed < 60.0 && !cachedItems.isEmpty)
        }

        if isFresh {
            return cached
        }

        return await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return [] }
            var results: [ConnectedDeviceBattery] = []
            var seenIDs = Set<String>()

            // 1. Check IOBluetooth paired devices (Fast, in-process for AirPods and classic BT)
            if let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
                for device in pairedDevices {
                    let name = (device.nameOrAddress ?? device.name ?? "Bluetooth Device")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let address = device.addressString ?? UUID().uuidString
                    let isConnected = device.isConnected()
                    let anyObj = device as AnyObject

                    let single = (anyObj.value(forKey: "batteryPercentSingle") as? NSNumber)?.intValue ?? 0
                    let left = (anyObj.value(forKey: "batteryPercentLeft") as? NSNumber)?.intValue ?? 0
                    let right = (anyObj.value(forKey: "batteryPercentRight") as? NSNumber)?.intValue ?? 0
                    let caseBatt = (anyObj.value(forKey: "batteryPercentCase") as? NSNumber)?.intValue ?? 0
                    let combined = (anyObj.value(forKey: "batteryPercentCombined") as? NSNumber)?.intValue ?? 0
                    let headset = (anyObj.value(forKey: "headsetBatteryPercent") as? NSNumber)?.intValue ?? 0

                    let id = "bt-\(address)"
                    seenIDs.insert(id)

                    if left > 0 || right > 0 || caseBatt > 0 {
                        let components = [left > 0 ? left : nil, right > 0 ? right : nil, caseBatt > 0 ? caseBatt : nil].compactMap { $0 }
                        let maxPercent = components.max() ?? 0
                        results.append(ConnectedDeviceBattery(
                            id: id,
                            name: name,
                            kind: .earbuds,
                            percent: maxPercent,
                            isCharging: false,
                            source: .bluetooth,
                            lastUpdated: Date(),
                            isConnected: isConnected,
                            leftPercent: left > 0 ? left : nil,
                            rightPercent: right > 0 ? right : nil,
                            casePercent: caseBatt > 0 ? caseBatt : nil
                        ))
                    } else if single > 0 || combined > 0 || headset > 0 {
                        let percent = single > 0 ? single : (combined > 0 ? combined : headset)
                        let kind = DeviceBatteryKind.infer(from: name)
                        results.append(ConnectedDeviceBattery(
                            id: id,
                            name: name,
                            kind: kind,
                            percent: percent,
                            isCharging: false,
                            source: .bluetooth,
                            lastUpdated: Date(),
                            isConnected: isConnected
                        ))
                    } else {
                        let kind = DeviceBatteryKind.infer(from: name)
                        results.append(ConnectedDeviceBattery(
                            id: id,
                            name: name,
                            kind: kind,
                            percent: -1,
                            isCharging: false,
                            source: .bluetooth,
                            lastUpdated: Date(),
                            isConnected: isConnected
                        ))
                    }
                }
            }

            // 2. Query system_profiler SPBluetoothDataType -json (Captures BLE mice, keyboards, etc.)
            let spItems = self.querySystemProfilerBluetooth()
            for spItem in spItems {
                if let idx = results.firstIndex(where: { $0.name.lowercased() == spItem.name.lowercased() }) {
                    let existing = results[idx]
                    let updatedConnected = existing.isConnected || spItem.isConnected
                    let updatedPercent = existing.percent >= 0 ? existing.percent : spItem.percent
                    results[idx] = ConnectedDeviceBattery(
                        id: existing.id,
                        name: existing.name,
                        kind: existing.kind != .other ? existing.kind : spItem.kind,
                        percent: updatedPercent,
                        isCharging: existing.isCharging || spItem.isCharging,
                        source: .bluetooth,
                        lastUpdated: Date(),
                        isConnected: updatedConnected,
                        leftPercent: existing.leftPercent,
                        rightPercent: existing.rightPercent,
                        casePercent: existing.casePercent
                    )
                } else if !seenIDs.contains(spItem.id) {
                    seenIDs.insert(spItem.id)
                    results.append(spItem)
                }
            }

            // 3. Layer 3: Merge CoreBluetooth active GATT readings (0x180F / 0x2A19)
            let gattReadings = BLEBatteryGATT.shared.getReadings()
            for (deviceID, info) in gattReadings {
                let lowerName = info.name.lowercased()
                if let idx = results.firstIndex(where: { $0.name.lowercased() == lowerName || $0.id.contains(deviceID) }) {
                    let existing = results[idx]
                    results[idx] = ConnectedDeviceBattery(
                        id: existing.id,
                        name: existing.name,
                        kind: existing.kind != .other ? existing.kind : DeviceBatteryKind.infer(from: info.name),
                        percent: info.percent,
                        isCharging: existing.isCharging,
                        source: .bluetooth,
                        lastUpdated: info.lastUpdated,
                        isConnected: true,
                        leftPercent: existing.leftPercent,
                        rightPercent: existing.rightPercent,
                        casePercent: existing.casePercent
                    )
                } else if !seenIDs.contains("ble-\(deviceID)") {
                    seenIDs.insert("ble-\(deviceID)")
                    let kind = DeviceBatteryKind.infer(from: info.name)
                    results.append(ConnectedDeviceBattery(
                        id: "ble-\(deviceID)",
                        name: info.name,
                        kind: kind,
                        percent: info.percent,
                        isCharging: false,
                        source: .bluetooth,
                        lastUpdated: info.lastUpdated,
                        isConnected: true
                    ))
                }
            }

            self.lock.withLock {
                self.cachedItems = results
                self.lastScanTime = Date()
            }

            // Trigger GATT scan in background (5s)
            BLEBatteryGATT.shared.startScan()

            return results
        }.value
    }

    // MARK: - Layer 2: system_profiler SPBluetoothDataType -json

    private func querySystemProfilerBluetooth() -> [ConnectedDeviceBattery] {
        var items: [ConnectedDeviceBattery] = []

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["SPBluetoothDataType"] as? [[String: Any]],
                  let first = list.first else {
                return []
            }

            // Parse connected devices
            if let connected = first["device_connected"] as? [[String: [String: Any]]] {
                for dict in connected {
                    for (devName, info) in dict {
                        let addr = (info["device_address"] as? String) ?? UUID().uuidString
                        let rawLevel = (info["device_batteryLevelMain"] as? String)
                            ?? (info["device_batteryLevelCase"] as? String)
                        let percent = rawLevel.flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) } ?? -1
                        let kind = DeviceBatteryKind.infer(from: devName)
                        items.append(ConnectedDeviceBattery(
                            id: "spbt-\(addr)",
                            name: devName,
                            kind: kind,
                            percent: percent,
                            isCharging: false,
                            source: .bluetooth,
                            lastUpdated: Date(),
                            isConnected: true
                        ))
                    }
                }
            }

            // Parse disconnected devices
            if let disconnected = first["device_not_connected"] as? [[String: [String: Any]]] {
                for dict in disconnected {
                    for (devName, info) in dict {
                        let addr = (info["device_address"] as? String) ?? UUID().uuidString
                        let kind = DeviceBatteryKind.infer(from: devName)
                        items.append(ConnectedDeviceBattery(
                            id: "spbt-\(addr)",
                            name: devName,
                            kind: kind,
                            percent: -1,
                            isCharging: false,
                            source: .bluetooth,
                            lastUpdated: Date(),
                            isConnected: false
                        ))
                    }
                }
            }
        } catch {
            // Ignore error
        }

        return items
    }
}
