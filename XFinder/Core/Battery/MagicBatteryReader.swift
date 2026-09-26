import Foundation
import IOKit

public struct MagicBatteryItem: Sendable {
    public let deviceID: String
    public let name: String
    public let kind: DeviceBatteryKind
    public let percent: Int
    public let isCharging: Bool

    public init(deviceID: String, name: String, kind: DeviceBatteryKind, percent: Int, isCharging: Bool) {
        self.deviceID = deviceID
        self.name = name
        self.kind = kind
        self.percent = max(0, min(100, percent))
        self.isCharging = isCharging
    }
}

public final class MagicBatteryReader: @unchecked Sendable {
    public static let shared = MagicBatteryReader()

    public init() {}

    public func scanDevices() -> [MagicBatteryItem] {
        var items: [MagicBatteryItem] = []
        var seenIDs = Set<String>()

        let serviceClasses = [
            "AppleDeviceManagementHIDEventService",
            "AppleBluetoothHIDKeyboard",
            "BNBTrackpadDevice",
            "BNBMouseDevice"
        ]

        for sClass in serviceClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(sClass), &iterator) == KERN_SUCCESS else {
                continue
            }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let item = readMagicBattery(service: service), !seenIDs.contains(item.deviceID) {
                    seenIDs.insert(item.deviceID)
                    items.append(item)
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        return items
    }

    private func readMagicBattery(service: io_object_t) -> MagicBatteryItem? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let rawPercent = dict["BatteryPercent"] ?? dict["BatteryPercentage"] ?? dict["BatteryLevel"]
        guard let percent = extractPercent(from: rawPercent), percent > 0 else {
            return nil
        }

        let product = (dict["Product"] as? String ?? dict["USB Product Name"] as? String ?? "Apple Device")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !product.contains("Internal Keyboard") else { return nil }

        let address = (dict["DeviceAddress"] as? String ?? dict["SerialNumber"] as? String ?? UUID().uuidString)
        let statusFlags = (dict["BatteryStatusFlags"] as? Int) ?? (dict["BatteryStatusFlags"] as? NSNumber)?.intValue ?? 0
        let isCharging = (statusFlags & 1 != 0) || (statusFlags == 4)

        let kind = DeviceBatteryKind.infer(from: product)
        return MagicBatteryItem(
            deviceID: "magic-\(address)-\(product)",
            name: product,
            kind: kind,
            percent: percent,
            isCharging: isCharging
        )
    }

    private func extractPercent(from value: Any?) -> Int? {
        if let num = value as? NSNumber {
            let val = num.intValue
            return (val >= 0 && val <= 100) ? val : nil
        }
        if let i = value as? Int {
            return (i >= 0 && i <= 100) ? i : nil
        }
        if let str = value as? String, let val = Int(str.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
            return (val >= 0 && val <= 100) ? val : nil
        }
        return nil
    }
}
