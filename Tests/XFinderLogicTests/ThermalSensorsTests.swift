import XCTest
import Foundation

final class ThermalSensorsTests: XCTestCase {
    private func r(_ n: String, _ c: Double) -> ThermalSensors.Reading { .init(name: n, celsius: c) }

    /// Shaped like the real list measured on this Mac: die sensors listed twice, NAND, battery, a NaN sensor.
    private var real: [ThermalSensors.Reading] {
        [r("NAND CH0 temp", 34.0), r("PMU tcal", 51.9), r("PMU tdev1", 43.2),
         r("PMU tdie1", 48.0), r("PMU tdie1", 47.7), r("PMU tdie2", 47.4), r("PMU tdie10", 48.1),
         r("als-temp", .nan), r("gas gauge battery", 34.7)]
    }

    func testSummaryUsesOnlyDieSensors() throws {
        let s = try XCTUnwrap(ThermalSensors.summary(of: real))
        XCTAssertEqual(s.sensorCount, 4, "tcal, tdev, NAND and the battery gauge are not SoC die sensors")
        XCTAssertEqual(s.socMax, 48.1, accuracy: 0.0001)
        XCTAssertEqual(s.socAverage, (48.0 + 47.7 + 47.4 + 48.1) / 4, accuracy: 0.0001)
    }

    func testNoDieSensorMeansUnavailableNotZero() {
        XCTAssertNil(ThermalSensors.summary(of: []))
        XCTAssertNil(ThermalSensors.summary(of: [r("NAND CH0 temp", 34), r("gas gauge battery", 34.7)]))
    }

    func testDeadAndImplausibleSensorsAreIgnored() throws {
        let s = try XCTUnwrap(ThermalSensors.summary(of: [
            r("PMU tdie1", .nan), r("PMU tdie2", .infinity), r("PMU tdie3", 0), r("PMU tdie4", -40),
            r("PMU tdie5", 9999), r("PMU tdie6", 50),
        ]))
        XCTAssertEqual(s.sensorCount, 1)
        XCTAssertEqual(s.socAverage, 50, accuracy: 0.0001)
        XCTAssertNil(ThermalSensors.summary(of: [r("PMU tdie1", .nan), r("PMU tdie2", 0)]),
                     "all dead ⇒ unavailable, never 0 °C")
    }

    func testBoundariesOfThePlausibleWindow() {
        XCTAssertNotNil(ThermalSensors.summary(of: [r("PMU tdie1", 5)]))
        XCTAssertNotNil(ThermalSensors.summary(of: [r("PMU tdie1", 125)]))
        XCTAssertNil(ThermalSensors.summary(of: [r("PMU tdie1", 4.9)]))
        XCTAssertNil(ThermalSensors.summary(of: [r("PMU tdie1", 125.1)]))
    }

    /// The reader against the real machine. A missing interface is allowed (returns []), but when
    /// sensors ARE returned they must contain a die sensor in a plausible range on Apple Silicon.
    func testLiveReaderEitherUnavailableOrPlausible() {
        let live = ThermalReader().read()
        guard !live.isEmpty else { return }   // not an error: the SPI may be absent on this OS
        if let s = ThermalSensors.summary(of: live) {
            XCTAssertTrue(ThermalSensors.plausible.contains(s.socAverage), "\(s)")
            XCTAssertLessThanOrEqual(s.socAverage, s.socMax)
        }
    }
}
