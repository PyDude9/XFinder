import Foundation
import IOBluetooth
import CoreBluetooth

public final class BluetoothBatteryProvider: NSObject, BatteryProvider, @unchecked Sendable {
    public let source: BatterySource = .bluetooth

    public override init() {
        super.init()
    }

    public func fetchBatteries() async -> [ConnectedDeviceBattery] {
        return await BluetoothBatteryReader.shared.scanAsync()
    }
}
