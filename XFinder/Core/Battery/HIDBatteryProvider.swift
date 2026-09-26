import Foundation
import IOKit
import IOKit.hid

public final class HIDBatteryProvider: BatteryProvider, @unchecked Sendable {
    public let source: BatterySource = .hid

    public init() {}

    public func fetchBatteries() async -> [ConnectedDeviceBattery] {
        return await Task.detached(priority: .utility) {
            var results: [ConnectedDeviceBattery] = []
            var seen = Set<String>()

            // 1. Query IOHIDManager
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(manager, nil)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

            if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                for device in devices {
                    let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !name.isEmpty, !name.contains("Internal Keyboard") else { continue }

                    let rawBatt = IOHIDDeviceGetProperty(device, "BatteryPercent" as CFString)
                        ?? IOHIDDeviceGetProperty(device, "BatteryPercentage" as CFString)
                        ?? IOHIDDeviceGetProperty(device, "BatteryLevel" as CFString)
                        ?? IOHIDDeviceGetProperty(device, "BatteryPercentSingle" as CFString)

                    guard let percent = Self.extractPercent(from: rawBatt), percent > 0 else { continue }

                    let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue
                    let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue
                    let serial = (IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String) ?? ""
                    let id = "hid-\(name)-\(serial)"

                    if seen.contains(id) { continue }
                    seen.insert(id)

                    let kind = DeviceBatteryKind.infer(from: name, usagePage: usagePage, usage: usage)
                    results.append(ConnectedDeviceBattery(
                        id: id,
                        name: name,
                        kind: kind,
                        percent: percent,
                        isCharging: false,
                        source: .hid,
                        lastUpdated: Date(),
                        isConnected: true
                    ))
                }
            }
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

            // 2. Query IORegistry for services publishing BatteryPercent
            let serviceClasses = ["AppleDeviceManagementHIDEventService", "IOHIDDevice", "IOHIDEventService"]
            for sClass in serviceClasses {
                var iterator = io_iterator_t()
                if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(sClass), &iterator) == KERN_SUCCESS {
                    var service = IOIteratorNext(iterator)
                    while service != 0 {
                        var props: Unmanaged<CFMutableDictionary>?
                        if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                           let dict = props?.takeRetainedValue() as? [String: Any] {
                            let name = (dict["Product"] as? String ?? dict["USB Product Name"] as? String ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let rawP = dict["BatteryPercent"] ?? dict["BatteryPercentage"] ?? dict["BatteryLevel"] ?? dict["BatteryPercentSingle"]
                            let percent = Self.extractPercent(from: rawP)
                            let serial = (dict["SerialNumber"] as? String) ?? ""
                            let id = "hid-reg-\(name)-\(serial)"

                            if !name.isEmpty, !name.contains("Internal Keyboard"), let p = percent, p > 0, !seen.contains(id) {
                                seen.insert(id)
                                let kind = DeviceBatteryKind.infer(from: name)
                                results.append(ConnectedDeviceBattery(
                                    id: id,
                                    name: name,
                                    kind: kind,
                                    percent: p,
                                    isCharging: false,
                                    source: .hid,
                                    lastUpdated: Date(),
                                    isConnected: true
                                ))
                            }
                        }
                        IOObjectRelease(service)
                        service = IOIteratorNext(iterator)
                    }
                    IOObjectRelease(iterator)
                }
            }

            return results
        }.value
    }

    private static func extractPercent(from value: Any?) -> Int? {
        if let num = value as? NSNumber {
            let val = num.intValue
            return (val >= 0 && val <= 100) ? val : nil
        }
        if let i = value as? Int {
            return (i >= 0 && i <= 100) ? i : nil
        }
        if let str = value as? String, let val = Int(str) {
            return (val >= 0 && val <= 100) ? val : nil
        }
        return nil
    }
}
