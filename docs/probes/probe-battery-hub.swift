import Foundation
import IOKit.ps
import IOBluetooth
import CoreBluetooth
import IOKit.hid

public enum DeviceBatteryKind: String, Codable, Sendable, CaseIterable {
    case mac, mouse, keyboard, headphones, earbuds, caseCharging, watch, tablet, phone, other

    public var iconName: String {
        switch self {
        case .mac:          return "macbook"
        case .mouse:        return "magicmouse"
        case .keyboard:     return "keyboard"
        case .headphones:   return "headphones"
        case .earbuds:      return "airpodspro"
        case .caseCharging: return "airpodspro.chargingcase"
        case .watch:        return "applewatch"
        case .tablet:       return "ipad"
        case .phone:        return "iphone"
        case .other:        return "battery.100"
        }
    }

    public static func infer(from name: String, usagePage: Int? = nil, usage: Int? = nil) -> DeviceBatteryKind {
        let lower = name.lowercased()
        if lower.contains("case") { return .caseCharging }
        if lower.contains("airpods max") || lower.contains("beats studio") || lower.contains("headphone") || lower.contains("headset") {
            return .headphones
        }
        if lower.contains("airpods") || lower.contains("buds") || lower.contains("earbud") {
            return .earbuds
        }
        if lower.contains("watch") { return .watch }
        if lower.contains("ipad") { return .tablet }
        if lower.contains("iphone") { return .phone }
        if lower.contains("mouse") || lower.contains("trackpad") || lower.contains("bskv3p") || lower.contains("mx master") || (usagePage == 1 && (usage == 2 || usage == 1)) {
            return .mouse
        }
        if lower.contains("keyboard") || lower.contains("keychron") || (usagePage == 1 && usage == 6) {
            return .keyboard
        }
        if lower.contains("macbook") || lower.contains("internalbattery") { return .mac }
        return .other
    }
}

public enum BatterySource: String, Codable, Sendable {
    case mac, hid, bluetooth
}

public struct ConnectedDeviceBattery: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: DeviceBatteryKind
    public let percent: Int
    public let isCharging: Bool
    public let source: BatterySource
    public let lastUpdated: Date
    public let isConnected: Bool
    public let leftPercent: Int?
    public let rightPercent: Int?
    public let casePercent: Int?

    public var isLowBattery: Bool { percent > 0 && percent < 20 }
    public var hasMultiBattery: Bool { leftPercent != nil || rightPercent != nil || casePercent != nil }
    public var multiBatterySubtitle: String {
        let l = leftPercent.map { "\($0)%" } ?? "--"
        let r = rightPercent.map { "\($0)%" } ?? "--"
        let c = casePercent.map { "\($0)%" } ?? "--"
        return "L:\(l)  R:\(r)  Case:\(c)"
    }

    public init(
        id: String,
        name: String,
        kind: DeviceBatteryKind,
        percent: Int,
        isCharging: Bool = false,
        source: BatterySource,
        lastUpdated: Date = Date(),
        isConnected: Bool = true,
        leftPercent: Int? = nil,
        rightPercent: Int? = nil,
        casePercent: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.percent = max(0, min(100, percent))
        self.isCharging = isCharging
        self.source = source
        self.lastUpdated = lastUpdated
        self.isConnected = isConnected
        self.leftPercent = leftPercent.map { max(0, min(100, $0)) }
        self.rightPercent = rightPercent.map { max(0, min(100, $0)) }
        self.casePercent = casePercent.map { max(0, min(100, $0)) }
    }
}

// 1. Mac Provider
func fetchMacBatteries() -> [ConnectedDeviceBattery] {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return [] }
    guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef], !list.isEmpty else { return [] }
    var results: [ConnectedDeviceBattery] = []
    for item in list {
        guard let desc = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any] else { continue }
        guard let cur = desc[kIOPSCurrentCapacityKey] as? Int,
              let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
        let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        let rawPercent = Int(round(Double(cur) / Double(maxCap) * 100.0))
        let name = (desc[kIOPSNameKey] as? String) ?? "MacBook Battery"
        let psId = (desc["Power Source ID"] as? Int).map { "mac-ps-\($0)" } ?? "internal-battery"
        results.append(ConnectedDeviceBattery(
            id: psId, name: name, kind: .mac, percent: rawPercent,
            isCharging: isCharging, source: .mac, isConnected: true
        ))
    }
    return results
}

// 2. Bluetooth Provider
func fetchBluetoothBatteries() -> [ConnectedDeviceBattery] {
    var results: [ConnectedDeviceBattery] = []
    var seenIds = Set<String>()

    if let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
        for device in pairedDevices {
            let name = (device.nameOrAddress ?? device.name ?? "Bluetooth Device").trimmingCharacters(in: .whitespacesAndNewlines)
            let address = device.addressString ?? UUID().uuidString
            let isConnected = device.isConnected()
            let anyObj = device as AnyObject
            let single = (anyObj.value(forKey: "batteryPercentSingle") as? NSNumber)?.intValue ?? 0
            let left = (anyObj.value(forKey: "batteryPercentLeft") as? NSNumber)?.intValue ?? 0
            let right = (anyObj.value(forKey: "batteryPercentRight") as? NSNumber)?.intValue ?? 0
            let caseBatt = (anyObj.value(forKey: "batteryPercentCase") as? NSNumber)?.intValue ?? 0
            let combined = (anyObj.value(forKey: "batteryPercentCombined") as? NSNumber)?.intValue ?? 0
            let headset = (anyObj.value(forKey: "headsetBatteryPercent") as? NSNumber)?.intValue ?? 0

            if left > 0 || right > 0 || caseBatt > 0 {
                let id = "bt-\(address)"
                let components = [left > 0 ? left : nil, right > 0 ? right : nil, caseBatt > 0 ? caseBatt : nil].compactMap { $0 }
                let maxPercent = components.max() ?? 0
                results.append(ConnectedDeviceBattery(
                    id: id, name: name, kind: .earbuds, percent: maxPercent,
                    isCharging: false, source: .bluetooth, isConnected: isConnected,
                    leftPercent: left > 0 ? left : nil,
                    rightPercent: right > 0 ? right : nil,
                    casePercent: caseBatt > 0 ? caseBatt : nil
                ))
                seenIds.insert(id)
            } else if single > 0 || combined > 0 || headset > 0 {
                let percent = single > 0 ? single : (combined > 0 ? combined : headset)
                let id = "bt-\(address)"
                let kind = DeviceBatteryKind.infer(from: name)
                results.append(ConnectedDeviceBattery(
                    id: id, name: name, kind: kind, percent: percent,
                    isCharging: false, source: .bluetooth, isConnected: isConnected
                ))
                seenIds.insert(id)
            } else {
                let id = "bt-\(address)"
                let kind = DeviceBatteryKind.infer(from: name)
                results.append(ConnectedDeviceBattery(
                    id: id, name: name, kind: kind, percent: 0,
                    isCharging: false, source: .bluetooth, isConnected: isConnected
                ))
                seenIds.insert(id)
            }
        }
    }
    return results
}

// 3. HID Provider
func fetchHIDBatteries() -> [ConnectedDeviceBattery] {
    var results: [ConnectedDeviceBattery] = []
    var seen = Set<String>()
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

    if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
        for device in devices {
            let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, !name.contains("Internal Keyboard") else { continue }
            let rawBatt = IOHIDDeviceGetProperty(device, "BatteryPercent" as CFString)
                ?? IOHIDDeviceGetProperty(device, "BatteryPercentage" as CFString)
                ?? IOHIDDeviceGetProperty(device, "BatteryLevel" as CFString)
                ?? IOHIDDeviceGetProperty(device, "BatteryPercentSingle" as CFString)
            guard let num = rawBatt as? NSNumber, num.intValue > 0 && num.intValue <= 100 else { continue }
            let id = "hid-\(name)"
            if seen.contains(id) { continue }
            seen.insert(id)
            results.append(ConnectedDeviceBattery(
                id: id, name: name, kind: DeviceBatteryKind.infer(from: name),
                percent: num.intValue, source: .hid, isConnected: true
            ))
        }
    }
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    return results
}

// Main execution
print("=== PROBING LIVE BATTERY SOURCES ===")
let macs = fetchMacBatteries()
print("Mac batteries: \(macs.count)")
for m in macs {
    print("  - \(m.name): \(m.percent)% (charging: \(m.isCharging))")
}

let bts = fetchBluetoothBatteries()
print("Bluetooth batteries: \(bts.count)")
for b in bts {
    let sub = b.hasMultiBattery ? " [\(b.multiBatterySubtitle)]" : ""
    print("  - \(b.name) [\(b.kind.rawValue)]: \(b.percent)%\(sub) (connected: \(b.isConnected))")
}

let hids = fetchHIDBatteries()
print("HID batteries: \(hids.count)")
for h in hids {
    print("  - \(h.name) [\(h.kind.rawValue)]: \(h.percent)%")
}

// Merging logic matching BatteryStore
var merged: [ConnectedDeviceBattery] = []
var seenNames = Set<String>()

for dev in bts {
    let key = dev.name.lowercased()
    if !seenNames.contains(key) {
        seenNames.insert(key)
        merged.append(dev)
    }
}
for dev in hids {
    let key = dev.name.lowercased()
    if !seenNames.contains(key) {
        seenNames.insert(key)
        merged.append(dev)
    }
}

let connectedDevices = merged.filter { $0.isConnected }
var allDevices = [ConnectedDeviceBattery]()
if let mac = macs.first { allDevices.append(mac) }
allDevices.append(contentsOf: merged)

print("\n=== BATTERY STORE MERGED STATE ===")
if let mac = macs.first {
    print("Mac Battery: \(mac.name) - \(mac.percent)% (isLow: \(mac.isLowBattery))")
}
print("Connected Devices: \(connectedDevices.count)")
print("connectedDevices=\(connectedDevices.count)")
for dev in connectedDevices {
    let sub = dev.hasMultiBattery ? " [\(dev.multiBatterySubtitle)]" : ""
    print("  * \(dev.name) (\(dev.kind.rawValue)) -> \(dev.percent)%\(sub) | connected: \(dev.isConnected)")
}
print("All Devices: \(allDevices.count)")
print("allDevices=\(allDevices.count)")
