import Foundation

/// The pure half of system alerts. Job: *"tell me when the machine is in trouble while I am not
/// looking at it — once, not every 30 seconds."*
///
/// Everything that decides WHETHER a notification is sent lives here, with no timer and no
/// notification centre, so the three rules that stop it from being spam are pinned by tests:
///
/// 1. **Sustained, not instantaneous.** A condition must hold for `sustainedSeconds` before an
///    alert fires. One CPU spike while a page loads is not an alert.
/// 2. **Hysteresis.** After firing, the condition must CLEAR (fall back past the threshold by a
///    margin) before the same alert can fire again. A value hovering at the threshold would
///    otherwise fire on every tick.
/// 3. **Cooldown.** Even after clearing, the same alert does not re-fire within `cooldownSeconds`.
enum AlertRules {

    enum Kind: String, CaseIterable, Codable, Equatable {
        case cpu, memoryPressure, diskSpace, temperature, battery

        var titleKey: String {
            switch self {
            case .cpu:            return "CPU cao kéo dài"
            case .memoryPressure: return "Áp lực bộ nhớ"
            case .diskSpace:      return "Ổ đĩa sắp đầy"
            case .temperature:    return "Nhiệt độ SoC cao"
            case .battery:        return "Pin yếu"
            }
        }
        var symbol: String {
            switch self {
            case .cpu: return "cpu"
            case .memoryPressure: return "memorychip"
            case .diskSpace: return "internaldrive"
            case .temperature: return "thermometer.medium"
            case .battery: return "battery.25"
            }
        }
    }

    /// One tick's readings. nil = that reading is unavailable on this machine; its rule is skipped,
    /// never evaluated against 0.
    struct Sample: Equatable {
        var cpuPercent: Double?
        /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
        var memoryPressureLevel: Int?
        var diskFreePercent: Double?
        var socTemperature: Double?
        var batteryPercent: Double?
        var isCharging: Bool = false
    }

    struct Thresholds: Codable, Equatable {
        var cpuPercent: Double = 85
        /// 2 = warn on "warning", 4 = only on "critical".
        var memoryPressureLevel: Int = 4
        var diskFreePercent: Double = 10
        var socTemperature: Double = 95
        var batteryPercent: Double = 15
        var sustainedSeconds: TimeInterval = 120
        var cooldownSeconds: TimeInterval = 30 * 60
        var enabled: Set<Kind> = Set(Kind.allCases)

        /// Clamp hand-edited values into ranges where the rule still means something.
        func validated() -> Thresholds {
            var t = self
            t.cpuPercent = min(100, max(10, t.cpuPercent))
            t.memoryPressureLevel = [2, 4].contains(t.memoryPressureLevel) ? t.memoryPressureLevel : 4
            t.diskFreePercent = min(50, max(1, t.diskFreePercent))
            t.socTemperature = min(120, max(50, t.socTemperature))
            t.batteryPercent = min(50, max(5, t.batteryPercent))
            t.sustainedSeconds = min(3600, max(0, t.sustainedSeconds))
            t.cooldownSeconds = min(24 * 3600, max(60, t.cooldownSeconds))
            return t
        }
    }

    struct Event: Equatable {
        var kind: Kind
        var value: Double
        var at: Date
    }

    /// Is the condition met right now? nil when the reading is unavailable (rule skipped).
    static func exceeds(_ kind: Kind, sample: Sample, thresholds t: Thresholds) -> (met: Bool, value: Double)? {
        switch kind {
        case .cpu:
            guard let v = sample.cpuPercent else { return nil }
            return (v >= t.cpuPercent, v)
        case .memoryPressure:
            guard let v = sample.memoryPressureLevel else { return nil }
            return (v >= t.memoryPressureLevel, Double(v))
        case .diskSpace:
            guard let v = sample.diskFreePercent else { return nil }
            return (v <= t.diskFreePercent, v)
        case .temperature:
            guard let v = sample.socTemperature else { return nil }
            return (v >= t.socTemperature, v)
        case .battery:
            guard let v = sample.batteryPercent else { return nil }
            // Plugged in and charging is not "low battery", whatever the number.
            return (v <= t.batteryPercent && !sample.isCharging, v)
        }
    }

    /// Has the condition clearly gone away? Uses a margin so a value sitting at the threshold does
    /// not flip between met/cleared on every tick.
    static func cleared(_ kind: Kind, sample: Sample, thresholds t: Thresholds) -> Bool {
        switch kind {
        case .cpu:            return (sample.cpuPercent ?? 0) < t.cpuPercent - 10
        case .memoryPressure: return (sample.memoryPressureLevel ?? 1) < t.memoryPressureLevel
        case .diskSpace:      return (sample.diskFreePercent ?? 100) > t.diskFreePercent + 2
        case .temperature:    return (sample.socTemperature ?? 0) < t.socTemperature - 5
        case .battery:        return sample.isCharging || (sample.batteryPercent ?? 100) > t.batteryPercent + 5
        }
    }

    /// Per-kind state. Value type so a tick is a pure function of (state, sample, time).
    struct State: Equatable {
        /// When the condition was first seen met in the current stretch; nil when not met.
        var metSince: Date?
        var lastFired: Date?
        /// Fired and the condition has not cleared yet — do not fire again.
        var armedOff = false
    }

    struct Engine: Equatable {
        var states: [Kind: State] = [:]

        /// Advance one tick. Returns the alerts to deliver NOW.
        mutating func step(sample: Sample, thresholds: Thresholds, at now: Date) -> [Event] {
            var fired: [Event] = []
            for kind in Kind.allCases {
                var s = states[kind] ?? State()
                defer { states[kind] = s }
                guard thresholds.enabled.contains(kind), let (met, value) = AlertRules.exceeds(kind, sample: sample, thresholds: thresholds) else {
                    s.metSince = nil
                    continue
                }
                if s.armedOff {
                    if AlertRules.cleared(kind, sample: sample, thresholds: thresholds) { s.armedOff = false; s.metSince = nil }
                    continue
                }
                guard met else { s.metSince = nil; continue }
                if s.metSince == nil { s.metSince = now }
                guard now.timeIntervalSince(s.metSince!) >= thresholds.sustainedSeconds else { continue }
                if let last = s.lastFired, now.timeIntervalSince(last) < thresholds.cooldownSeconds { continue }
                s.lastFired = now
                s.armedOff = true
                fired.append(Event(kind: kind, value: value, at: now))
            }
            return fired
        }
    }

    /// Notification text. Title is the rule, body carries the measured value.
    static func bodyKeyAndValue(for e: Event) -> (key: String, value: String) {
        switch e.kind {
        case .cpu:            return ("CPU đã ở mức ", String(format: "%.0f%%", e.value))
        case .memoryPressure: return ("Áp lực bộ nhớ ở mức ", e.value >= 4 ? "critical" : "warning")
        case .diskSpace:      return ("Ổ khởi động chỉ còn trống ", String(format: "%.0f%%", e.value))
        case .temperature:    return ("Nhiệt độ SoC ", String(format: "%.0f °C", e.value))
        case .battery:        return ("Pin còn ", String(format: "%.0f%%", e.value))
        }
    }
}
