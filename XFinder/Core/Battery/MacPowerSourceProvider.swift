import Foundation
import IOKit.ps

public final class MacPowerSourceProvider: BatteryProvider, @unchecked Sendable {
    public let source: BatterySource = .mac

    public init() {}

    public func fetchBatteries() async -> [ConnectedDeviceBattery] {
        return await Task.detached(priority: .utility) {
            guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return [] }
            guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef], !list.isEmpty else {
                return []
            }

            var results: [ConnectedDeviceBattery] = []

            for item in list {
                guard let desc = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any] else {
                    continue
                }
                guard let cur = desc[kIOPSCurrentCapacityKey] as? Int,
                      let maxCap = desc[kIOPSMaxCapacityKey] as? Int,
                      maxCap > 0 else {
                    continue
                }
                let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
                let rawPercent = Int(round(Double(cur) / Double(maxCap) * 100.0))
                let rawName = (desc[kIOPSNameKey] as? String) ?? ""
                let name: String = {
                    if let host = Host.current().localizedName, !host.isEmpty, !host.contains("Internal") {
                        return host
                    }
                    if !rawName.isEmpty && !rawName.contains("Internal") {
                        return rawName
                    }
                    return "MacBook Pro"
                }()
                let psId = (desc["Power Source ID"] as? Int).map { "mac-ps-\($0)" } ?? "internal-battery"

                results.append(ConnectedDeviceBattery(
                    id: psId,
                    name: name,
                    kind: .mac,
                    percent: rawPercent,
                    isCharging: isCharging,
                    source: .mac,
                    lastUpdated: Date(),
                    isConnected: true
                ))
            }

            return results
        }.value
    }
}
