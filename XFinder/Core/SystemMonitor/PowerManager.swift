import Foundation
import IOKit

/// Nil-safe read wrapper around IOKit `AppleSmartBattery`. If no battery
/// exists (desktop) every field returns nil and the UI shows a placeholder
/// ("Không có pin") instead of fabricated data.
struct BatteryInfo {
    let healthPercent: Double?
    let cycleCount: Int?
    let watts: Double?
    let designCapacity: Int?
    let maxCapacity: Int?
}

enum PowerManager {

    static let empty = BatteryInfo(healthPercent: nil, cycleCount: nil, watts: nil, designCapacity: nil, maxCapacity: nil)

    /// Desktop Macs (no battery) and machines where AppleSmartBattery is absent
    /// return false → the Pin page renders "Không có pin" instead of zeros.
    static func hasBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return !list.isEmpty
    }

    static func read() -> BatteryInfo {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return empty }
        defer { IOObjectRelease(service) }

        var cfProps: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &cfProps, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let cfProps else { return empty }
        let dict = cfProps.takeRetainedValue() as? [String: Any]
        // Some hardware generations nest the readings under "BatteryData".
        if let info = readFromProps(dict), info.designCapacity != nil { return info }
        let nested = dict?["BatteryData"] as? [String: Any]
        if let info = readFromProps(nested) ?? readFromProps(dict) { return info }
        return empty
    }

    private static func readFromProps(_ props: [String: Any]?) -> BatteryInfo? {
        guard let props else { return nil }
        let cycle = props["CycleCount"] as? Int
        let design = props["DesignCapacity"] as? Int
        let maxCap = (props["AppleRawMaxCapacity"] as? Int) ?? (props["MaxCapacity"] as? Int)
        let amperage = (props["Amperage"] as? Int) ?? (props["InstantAmperage"] as? Int)
        let voltage = props["Voltage"] as? Int

        var health: Double? = nil
        if let d = design, let m = maxCap, d > 0 {
            health = Swift.min(Double(m) / Double(d) * 100.0, 100.0)
        }
        var watts: Double? = nil
        if let a = amperage, let v = voltage {
            watts = Double(a) / 1000.0 * Double(v) / 1000.0
        }
        if cycle == nil && design == nil && watts == nil { return nil }
        return BatteryInfo(healthPercent: health, cycleCount: cycle, watts: watts, designCapacity: design, maxCapacity: maxCap)
    }
}
