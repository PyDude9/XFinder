import Foundation

/// Applies and restores global mouse pointer scaling (`com.apple.mouse.scaling`) using `PointerAccelerationRules`.
@MainActor
enum PointerAccelerationController {
    static var isDisabled: Bool {
        UserDefaults.standard.bool(forKey: PointerAccelerationRules.enabledKey)
    }

    static func currentSystemScaling() -> Double? {
        guard let raw = CFPreferencesCopyAppValue(
            "com.apple.mouse.scaling" as CFString,
            kCFPreferencesAnyApplication
        ) as? NSNumber else {
            return nil
        }
        return raw.doubleValue
    }

    @discardableResult
    static func setDisableAcceleration(_ disable: Bool) -> Bool {
        let defaults = UserDefaults.standard
        let savedPrevious = defaults.object(forKey: PointerAccelerationRules.savedPreviousKey) as? Double
        let current = currentSystemScaling()
        let transition = PointerAccelerationRules.transition(
            enable: disable,
            currentScaling: current,
            savedPrevious: savedPrevious
        )

        defaults.set(disable, forKey: PointerAccelerationRules.enabledKey)
        if let updated = transition.updatedSavedPrevious {
            defaults.set(updated, forKey: PointerAccelerationRules.savedPreviousKey)
        } else {
            defaults.removeObject(forKey: PointerAccelerationRules.savedPreviousKey)
        }

        guard transition.needsUpdate else { return true }
        return writeSystemScaling(transition.targetScaling)
    }

    private static func writeSystemScaling(_ value: Double) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["write", "-g", "com.apple.mouse.scaling", "-float", String(value)]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
