import Foundation
import IOKit

/// Battery readings from IOKit.
///
/// **This file was wrong twice, and both mistakes were the same mistake:
/// concluding "no API" after looking in one place.**
///
/// 1. It read `AppleSmartBattery`, whose top level carries `CycleCount` but not
///    the capacity figures. The real, complete dictionary lives in a *different*
///    service — `AppleSmartBatteryPack` → `BatteryData` — which holds cycle
///    count, design/nominal capacity, voltage, amperage **and temperature**,
///    all together. Reported as "Số chu kỳ —" because the old reader picked
///    whichever dict it found first and lost the other's keys.
///
/// 2. Health was `MaxCapacity / DesignCapacity`. On Apple Silicon `MaxCapacity`
///    is a **percentage** (100), not mAh, so 100 / 8579 rendered as **1%**.
///    Health is `NominalChargeCapacity / DesignCapacity` — measured here:
///    7993 / 8579 ≈ 93%.
///
/// 3. Battery temperature was twice declared "không có API". It is
///    `BatteryData/Temperature`, in **centi-Celsius**: 3469 → 34.7 °C.
///    (`LifetimeData/AverageTemperature` = 248 is deci-Celsius, 24.8 °C —
///    a different scale in the same tree, so each field needs its own factor.)
struct BatteryInfo {
    let healthPercent: Double?
    let cycleCount: Int?
    let designCycleCount: Int?
    let watts: Double?
    let designCapacity: Int?
    /// Usable capacity in mAh (NominalChargeCapacity), NOT the 0-100 percentage.
    let nominalCapacity: Int?
    let temperatureC: Double?
    let lifetimeMaxTempC: Double?
    let lifetimeMinTempC: Double?
    let voltage: Double?
    let amperage: Int?
    let serial: String?
    let chargeLevel: Int?
}

enum PowerManager {

    static let empty = BatteryInfo(healthPercent: nil, cycleCount: nil, designCycleCount: nil,
                                   watts: nil, designCapacity: nil, nominalCapacity: nil,
                                   temperatureC: nil, lifetimeMaxTempC: nil, lifetimeMinTempC: nil,
                                   voltage: nil, amperage: nil, serial: nil, chargeLevel: nil)

    /// Desktop Macs (no battery) return false → the Pin page renders
    /// "Không có pin" instead of zeros.
    static func hasBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return !list.isEmpty
    }

    static func read() -> BatteryInfo {
        // Merge BOTH services rather than choosing one. `AppleSmartBatteryPack`
        // is the richer source, but keep `AppleSmartBattery` as a fallback for
        // hardware that only publishes the older layout.
        var merged: [String: Any] = [:]
        var lifetime: [String: Any] = [:]

        if let pack = properties(of: "AppleSmartBatteryPack") {
            if let data = pack["BatteryData"] as? [String: Any] {
                merged.merge(data) { _, new in new }
                if let lt = data["LifetimeData"] as? [String: Any] { lifetime = lt }
            }
            merged.merge(pack.filter { !($0.value is [String: Any]) }) { old, _ in old }
        }
        if let batt = properties(of: "AppleSmartBattery") {
            if let data = batt["BatteryData"] as? [String: Any] {
                merged.merge(data) { old, _ in old }
            }
            // Existing keys win: the pack's values are the authoritative ones.
            merged.merge(batt.filter { !($0.value is [String: Any]) }) { old, _ in old }
        }
        guard !merged.isEmpty else { return empty }

        let design = merged["DesignCapacity"] as? Int
        // NOT MaxCapacity: that is a 0-100 percentage on Apple Silicon and is
        // what produced the "1%" bug.
        let nominal = (merged["NominalChargeCapacity"] as? Int)
            ?? (merged["AppleRawMaxCapacity"] as? Int)
            ?? (merged["FullChargeCapacity"] as? Int)

        var health: Double? = nil
        if let d = design, let n = nominal, d > 0 {
            health = Swift.min(Double(n) / Double(d) * 100.0, 100.0)
        }

        let amperage = (merged["Amperage"] as? Int) ?? (merged["InstantAmperage"] as? Int)
        let voltageRaw = (merged["Voltage"] as? Int) ?? (merged["AppleRawBatteryVoltage"] as? Int)
        var watts: Double? = nil
        if let a = amperage, let v = voltageRaw {
            // mA × mV → W, and use the magnitude so discharging is not negative.
            watts = abs(Double(a) / 1000.0 * Double(v) / 1000.0)
        }

        // Temperature scales differ per key in the same tree — verified:
        // Temperature 3469 → 34.69 °C (centi), AverageTemperature 248 → 24.8 °C
        // (deci), Maximum/MinimumTemperature 47 / 9 → already whole °C.
        let tempC = (merged["Temperature"] as? Int).map { Double($0) / 100.0 }
            ?? (merged["VirtualTemperature"] as? Int).map { Double($0) / 100.0 }

        return BatteryInfo(
            healthPercent: health,
            cycleCount: merged["CycleCount"] as? Int,
            designCycleCount: merged["DesignCycleCount9C"] as? Int,
            watts: watts,
            designCapacity: design,
            nominalCapacity: nominal,
            temperatureC: tempC,
            lifetimeMaxTempC: (lifetime["MaximumTemperature"] as? Int).map(Double.init),
            lifetimeMinTempC: (lifetime["MinimumTemperature"] as? Int).map(Double.init),
            voltage: voltageRaw.map { Double($0) / 1000.0 },
            amperage: amperage,
            serial: merged["Serial"] as? String,
            chargeLevel: merged["StateOfCharge"] as? Int)
    }

    private static func properties(of className: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching(className))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var cfProps: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &cfProps, kCFAllocatorDefault, 0)
                == kIOReturnSuccess, let cfProps else { return nil }
        return cfProps.takeRetainedValue() as? [String: Any]
    }
}
