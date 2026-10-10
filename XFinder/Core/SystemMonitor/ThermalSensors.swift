import Foundation

/// SoC temperature from the HID thermal sensors. The pure half: turning named readings into the
/// number the UI shows, so the rules for what counts are pinned by tests.
///
/// Why this exists: the app said "no public API reads CPU/GPU temperature (SMC is private)" and
/// showed "Đang thu thập…". Measured 2026-10-10 on macOS 27 (M3 Pro, no root): the HID event
/// system lists 46 temperature services, among them `PMU tdie1…tdie10` — the SoC die sensors —
/// that read 47–49 °C at idle, plus `NAND CH0 temp` and the battery gauge (34.7 °C, equal to the
/// IORegistry battery temperature, which is an independent confirmation the scale is °C).
/// It is an undocumented SPI (loaded with `dlsym`, so a missing symbol degrades to "unavailable").
///
/// The label is **SoC**, not "CPU": die sensors sit across the whole chip, and no key says which
/// ones belong to CPU cores — claiming "CPU °C" would be a guess presented as a measurement.
enum ThermalSensors {

    struct Reading: Equatable {
        var name: String
        var celsius: Double
    }

    struct Summary: Equatable {
        /// Mean of the valid die sensors.
        var socAverage: Double
        /// Hottest valid die sensor.
        var socMax: Double
        var sensorCount: Int
    }

    /// A reading outside this window is a dead or unpopulated sensor, not a temperature
    /// (measured: `als-temp` reports NaN; an unpowered sensor can report 0 or a huge sentinel).
    static let plausible: ClosedRange<Double> = 5...125

    static func isDieSensor(_ name: String) -> Bool { name.hasPrefix("PMU tdie") }

    /// nil when no die sensor produced a plausible number — the UI then says "unavailable"
    /// instead of drawing 0 °C.
    static func summary(of readings: [Reading]) -> Summary? {
        let die = readings.filter { isDieSensor($0.name) && $0.celsius.isFinite && plausible.contains($0.celsius) }
        guard !die.isEmpty else { return nil }
        let values = die.map(\.celsius)
        return Summary(socAverage: values.reduce(0, +) / Double(values.count),
                       socMax: values.max()!, sensorCount: values.count)
    }
}
