import Foundation

/// XF-T27 — the pure half of Chống ngủ and Lau bàn phím (symlinked into the test package).
enum CaffeineRules {

    // MARK: Chống ngủ

    enum Key {
        static let keepDisplayOn = "caffeine.keepDisplayOn"
        static let requestLidWake = "caffeine.requestLidWake"
        static let until = "caffeine.until"
        static let cleaningMinutes = "cleaning.minutes"
    }

    /// Honest state of the closed-display (lid-wake) request: distinguishes user intent from an
    /// active `PreventSystemSleep` assertion (which requires Caffeine active AND AC power).
    enum LidWakeState: Equatable {
        case off
        case active
        case waitingForCaffeine
        case waitingForACPower
        case unavailable
    }

    static func lidWakeState(requested: Bool, caffeineActive: Bool, onACPower: Bool, assertionActive: Bool) -> LidWakeState {
        guard requested else { return .off }
        guard caffeineActive else { return .waitingForCaffeine }
        guard onACPower else { return .waitingForACPower }
        return assertionActive ? .active : .unavailable
    }

    /// Stored end of a hold: seconds since 1970, `indefinite` for "until turned off", `off` for none.
    static let indefinite = -1.0
    static let off = 0.0

    static func storedUntil(start: Date, minutes: Int?) -> Double {
        guard let minutes else { return indefinite }
        return start.addingTimeInterval(Double(max(minutes, 1)) * 60).timeIntervalSince1970
    }

    enum Resume: Equatable { case none, indefinite, minutesLeft(Int) }

    /// What a relaunch should restart from the stored value: an expired or absent hold restarts nothing.
    static func resume(stored: Double, now: Date) -> Resume {
        if stored == indefinite { return .indefinite }
        guard stored > 0 else { return .none }
        let left = stored - now.timeIntervalSince1970
        guard left >= 60 else { return .none }       // less than a minute left is not worth restarting
        return .minutesLeft(Int((left / 60).rounded(.down)))
    }

    /// Battery at or below this, on battery power, ends a hold.
    static let lowBatteryPercent = 10.0

    static func shouldStopForBattery(percent: Double?, onBattery: Bool) -> Bool {
        guard onBattery, let percent else { return false }
        return percent <= lowBatteryPercent
    }

    /// The Mac's own battery among the power sources IOKit lists (a UPS is a power source too, and used to be read
    /// instead of the MacBook's battery when it came first). Each dictionary is an `IOPSGetPowerSourceDescription`.
    static func internalBattery(_ sources: [[String: Any]]) -> (percent: Double, onBattery: Bool)? {
        for d in sources where (d["Type"] as? String) == "InternalBattery" {
            guard let cur = d["Current Capacity"] as? Int, let max = d["Max Capacity"] as? Int, max > 0 else { continue }
            let onBattery = (d["Power Source State"] as? String) == "Battery Power"
            return (Double(cur) / Double(max) * 100, onBattery)
        }
        return nil
    }

    // MARK: Lau bàn phím

    static let cleaningRange = 1...5
    static let defaultCleaningMinutes = 2
    static func clampCleaning(_ minutes: Int) -> Int { min(max(minutes, cleaningRange.lowerBound), cleaningRange.upperBound) }

    /// Esc five times within three seconds unlocks; any other key, or a pause longer than that, starts the count again.
    struct EscCounter: Equatable {
        static let needed = 5
        static let window: TimeInterval = 3
        private(set) var presses: [TimeInterval] = []

        /// Returns true when this press unlocks.
        mutating func press(isEscape: Bool, at t: TimeInterval) -> Bool {
            guard isEscape else { presses = []; return false }
            presses = presses.filter { t - $0 <= Self.window } + [t]
            if presses.count >= Self.needed { presses = []; return true }
            return false
        }
    }
}
