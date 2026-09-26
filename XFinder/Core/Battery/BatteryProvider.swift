import Foundation

public protocol BatteryProvider: Sendable {
    var source: BatterySource { get }
    func fetchBatteries() async -> [ConnectedDeviceBattery]
}

public final class MockBatteryProvider: BatteryProvider, @unchecked Sendable {
    public let source: BatterySource
    public var mockBatteries: [ConnectedDeviceBattery]

    public init(source: BatterySource, mockBatteries: [ConnectedDeviceBattery] = []) {
        self.source = source
        self.mockBatteries = mockBatteries
    }

    public func fetchBatteries() async -> [ConnectedDeviceBattery] {
        return mockBatteries
    }
}
