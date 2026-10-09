import XCTest
@testable import XFinderLogicTests

/// Counts scan requests instead of touching CoreBluetooth.
final class SpyGATTScanner: BatteryGATTScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var startScanCount: Int { lock.withLock { count } }
    func startScan() { lock.withLock { count += 1 } }
}

final class BatteryStoreTests: XCTestCase {

    // MARK: - Model & Clamping Tests

    func testBatteryPercentClamping() {
        let negBattery = ConnectedDeviceBattery(
            id: "test-1",
            name: "Mouse",
            kind: .mouse,
            percent: -10,
            source: .hid
        )
        XCTAssertEqual(negBattery.percent, 0)

        let overBattery = ConnectedDeviceBattery(
            id: "test-2",
            name: "Keyboard",
            kind: .keyboard,
            percent: 150,
            source: .bluetooth
        )
        XCTAssertEqual(overBattery.percent, 100)

        let normalBattery = ConnectedDeviceBattery(
            id: "test-3",
            name: "Headphones",
            kind: .headphones,
            percent: 45,
            source: .bluetooth
        )
        XCTAssertEqual(normalBattery.percent, 45)
    }

    func testLowBatteryThreshold() {
        let crit = ConnectedDeviceBattery(id: "1", name: "Mouse", kind: .mouse, percent: 19, source: .bluetooth)
        XCTAssertTrue(crit.isLowBattery, "Battery below 20% should be considered low")

        let five = ConnectedDeviceBattery(id: "2", name: "Mouse", kind: .mouse, percent: 5, source: .bluetooth)
        XCTAssertTrue(five.isLowBattery, "5% should be considered low")

        let zero = ConnectedDeviceBattery(id: "3", name: "Mouse", kind: .mouse, percent: 0, source: .bluetooth)
        XCTAssertFalse(zero.isLowBattery, "0% (unreported/unknown) should not be considered low")

        let edge = ConnectedDeviceBattery(id: "4", name: "Mouse", kind: .mouse, percent: 20, source: .bluetooth)
        XCTAssertFalse(edge.isLowBattery, "20% should not be considered low")

        let full = ConnectedDeviceBattery(id: "5", name: "Mouse", kind: .mouse, percent: 100, source: .bluetooth)
        XCTAssertFalse(full.isLowBattery, "100% should not be considered low")
    }

    func testKindInference() {
        XCTAssertEqual(DeviceBatteryKind.infer(from: "BSKV3P 35K"), .mouse)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Logitech MX Master 3S"), .mouse)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Magic Trackpad"), .mouse)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Keychron K2"), .keyboard)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Magic Keyboard"), .keyboard)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Trần’s AirPods Pro"), .earbuds)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Trần’s AirPods Pro (Case)"), .caseCharging)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Phan’s AirPods Max"), .headphones)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Beats Studio Pro"), .headphones)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Apple Watch Ultra"), .watch)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "iPad Pro"), .tablet)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Wulong’s iPhone"), .phone)
        XCTAssertEqual(DeviceBatteryKind.infer(from: "Random Accessory"), .other)
    }

    func testKindIcons() {
        for kind in DeviceBatteryKind.allCases {
            XCTAssertFalse(kind.iconName.isEmpty, "Icon name for \(kind) should not be empty")
        }
    }

    // MARK: - BatteryStore Tests

    @MainActor
    func testBatteryStoreLifecycle() async {
        let macMock = MockBatteryProvider(source: .mac)
        let hidMock = MockBatteryProvider(source: .hid)
        let btMock = MockBatteryProvider(source: .bluetooth)
        // Never the real scanner: a real CBCentralManager in the test process makes the OS
        // abort it (signal 6) a moment later, in whichever test class happens to be running.
        let scanner = SpyGATTScanner()

        let store = BatteryStore(macProvider: macMock, hidProvider: hidMock,
                                 bluetoothProvider: btMock, gattScanner: scanner)

        XCTAssertFalse(store.isPolling)
        XCTAssertEqual(scanner.startScanCount, 0, "creating a store must not start a BLE scan")

        store.retain()
        XCTAssertTrue(store.isPolling)
        XCTAssertEqual(scanner.startScanCount, 1, "the first retain starts polling and one scan")

        store.retain()
        XCTAssertTrue(store.isPolling)
        XCTAssertEqual(scanner.startScanCount, 1, "a second retain must not start another scan")

        store.release()
        XCTAssertTrue(store.isPolling, "Should remain polling when retain count > 0")

        store.release()
        XCTAssertFalse(store.isPolling, "Should stop polling when retain count reaches 0")
        XCTAssertEqual(scanner.startScanCount, 1, "stopping must not scan")
    }

    @MainActor
    func testBatteryStoreRefreshAndDeduplication() async {
        let macDev = ConnectedDeviceBattery(id: "mac-1", name: "Internal Battery", kind: .mac, percent: 85, isCharging: true, source: .mac)
        let macMock = MockBatteryProvider(source: .mac, mockBatteries: [macDev])

        let btAirPods = ConnectedDeviceBattery(id: "bt-airpods-l", name: "AirPods Pro (L)", kind: .earbuds, percent: 75, source: .bluetooth)
        let btMouse = ConnectedDeviceBattery(id: "bt-mouse", name: "BSKV3P 35K", kind: .mouse, percent: 65, source: .bluetooth)
        let btMock = MockBatteryProvider(source: .bluetooth, mockBatteries: [btAirPods, btMouse])

        // Same mouse name reported via HID
        let hidMouse = ConnectedDeviceBattery(id: "hid-mouse", name: "BSKV3P 35K", kind: .mouse, percent: 65, source: .hid)
        let hidKeyboard = ConnectedDeviceBattery(id: "hid-kb", name: "Keychron K2", kind: .keyboard, percent: 90, source: .hid)
        let hidMock = MockBatteryProvider(source: .hid, mockBatteries: [hidMouse, hidKeyboard])

        let store = BatteryStore(macProvider: macMock, hidProvider: hidMock, bluetoothProvider: btMock)

        await store.refresh()

        XCTAssertEqual(store.macBattery?.name, "Internal Battery")
        XCTAssertEqual(store.macBattery?.percent, 85)

        // Deduplication: "BSKV3P 35K" should only appear ONCE in connectedDevices
        let mouseOccurrences = store.connectedDevices.filter { $0.name == "BSKV3P 35K" }
        XCTAssertEqual(mouseOccurrences.count, 1, "Duplicate device reported via both HID and Bluetooth must be deduplicated")

        // Total connected devices: AirPods Pro (L), BSKV3P 35K, Keychron K2 -> 3
        XCTAssertEqual(store.connectedDevices.count, 3)

        // All devices: Mac (1) + Connected (3) -> 4
        XCTAssertEqual(store.allDevices.count, 4)
    }

    @MainActor
    func testBatteryStoreConnectedSorting() async {
        let disconnected = ConnectedDeviceBattery(id: "d1", name: "A-Disconnected", kind: .mouse, percent: 50, source: .bluetooth, isConnected: false)
        let connected = ConnectedDeviceBattery(id: "c1", name: "Z-Connected", kind: .mouse, percent: 50, source: .bluetooth, isConnected: true)

        let btMock = MockBatteryProvider(source: .bluetooth, mockBatteries: [disconnected, connected])
        let store = BatteryStore(macProvider: MockBatteryProvider(source: .mac), hidProvider: MockBatteryProvider(source: .hid), bluetoothProvider: btMock)

        await store.refresh()

        // connectedDevices must ONLY contain connected devices
        XCTAssertEqual(store.connectedDevices.count, 1)
        XCTAssertEqual(store.connectedDevices.first?.name, "Z-Connected")

        // allDevices contains both, sorted connected first
        XCTAssertEqual(store.allDevices.count, 2)
        XCTAssertEqual(store.allDevices.first?.name, "Z-Connected", "Connected devices should sort before disconnected devices in allDevices")
        XCTAssertEqual(store.allDevices.last?.name, "A-Disconnected")
    }

    func testAirPodsMultiBatteryModel() {
        let airPods = ConnectedDeviceBattery(
            id: "bt-airpods",
            name: "Trần’s AirPods Pro",
            kind: .earbuds,
            percent: 100,
            source: .bluetooth,
            isConnected: true,
            leftPercent: 37,
            rightPercent: nil,
            casePercent: 100
        )

        XCTAssertTrue(airPods.hasMultiBattery)
        XCTAssertEqual(airPods.leftPercent, 37)
        XCTAssertNil(airPods.rightPercent)
        XCTAssertEqual(airPods.casePercent, 100)
        XCTAssertEqual(airPods.multiBatterySubtitle, "L:37%  R:--  Case:100%")
    }

    @MainActor
    func testBatteryStoreGATTUpdateAndPriority() async {
        let spMouse = ConnectedDeviceBattery(id: "spbt-ca2084", name: "BSKV3P 35K", kind: .mouse, percent: -1, source: .bluetooth, isConnected: false)
        let btMock = MockBatteryProvider(source: .bluetooth, mockBatteries: [spMouse])
        let store = BatteryStore(macProvider: MockBatteryProvider(source: .mac), hidProvider: MockBatteryProvider(source: .hid), bluetoothProvider: btMock)

        await store.refresh()

        XCTAssertEqual(store.connectedDevices.count, 0)
        XCTAssertEqual(store.allDevices.count, 1)
        XCTAssertEqual(store.allDevices.first?.percent, -1)

        store.updateGATTDevice(deviceID: "ca-20-84", name: "BSKV3P 35K", percent: 80)

        XCTAssertEqual(store.connectedDevices.count, 1)
        XCTAssertEqual(store.connectedDevices.first?.name, "BSKV3P 35K")
        XCTAssertEqual(store.connectedDevices.first?.percent, 80)
        XCTAssertTrue(store.connectedDevices.first?.isConnected == true)
    }
}

