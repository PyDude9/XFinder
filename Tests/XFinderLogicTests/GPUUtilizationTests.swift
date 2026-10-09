import XCTest
import Foundation

/// Pins the honesty contract of the GPU meter: a number only when the registry publishes a
/// number, `nil` (rendered "Không khả dụng") otherwise — never a fabricated 0 %.
final class GPUUtilizationTests: XCTestCase {

    func testReadsTheDeviceUtilizationKeyAsPublishedByTheRegistry() {
        // The exact shape measured on this machine: Int under an NSDictionary bridge.
        let stats: [String: Any] = [
            "Device Utilization %": NSNumber(value: 51),
            "Renderer Utilization %": NSNumber(value: 51),
            "Tiler Utilization %": NSNumber(value: 51),
            "In use system memory": NSNumber(value: 1_269_972_992),
        ]
        XCTAssertEqual(GPUUtilization.percent(from: stats), 51)
        XCTAssertEqual(GPUUtilization.percent(from: ["Device Utilization %": 100]), 100)
        XCTAssertEqual(GPUUtilization.percent(from: ["Device Utilization %": 0]), 0,
                       "a real 0 from the registry is a measurement, not an absence")
    }

    func testAbsentOrNonNumericIsNilNeverZero() {
        XCTAssertNil(GPUUtilization.percent(from: nil), "no PerformanceStatistics at all")
        XCTAssertNil(GPUUtilization.percent(from: [:]), "dictionary without the key")
        XCTAssertNil(GPUUtilization.percent(from: ["Renderer Utilization %": 40]),
                     "a sibling key must not be mistaken for device utilization")
        XCTAssertNil(GPUUtilization.percent(from: ["Device Utilization %": "51"]),
                     "a string is not a number")
        XCTAssertNil(GPUUtilization.percent(from: ["Device Utilization %": Double.nan]))
    }

    func testOutOfRangeValuesAreClampedToThePercentScale() {
        XCTAssertEqual(GPUUtilization.percent(from: ["Device Utilization %": 140]), 100)
        XCTAssertEqual(GPUUtilization.percent(from: ["Device Utilization %": -3]), 0)
    }

    func testKeyNamesMatchWhatMacOSPublishes() {
        // These strings are the contract with the OS; a typo here is a silent "Không khả dụng".
        XCTAssertEqual(GPUUtilization.deviceUtilizationKey, "Device Utilization %")
        XCTAssertEqual(GPUUtilization.performanceStatisticsKey, "PerformanceStatistics")
        XCTAssertEqual(GPUUtilization.serviceClass, "IOAccelerator")
    }
}
