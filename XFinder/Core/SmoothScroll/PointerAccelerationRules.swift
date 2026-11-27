import Foundation

/// Pure rules for disabling macOS mouse pointer acceleration (`com.apple.mouse.scaling`).
/// Saves the user's previous scaling preference when enabled and restores it when disabled.
enum PointerAccelerationRules {
    static let enabledKey = "mouse.disableAcceleration"
    static let savedPreviousKey = "mouse.previousScaling"
    static let defaultScaling: Double = 0.6875
    static let disabledScaling: Double = -1.0

    struct Transition: Equatable, Sendable {
        let targetScaling: Double
        let updatedSavedPrevious: Double?
        let needsUpdate: Bool
    }

    static func transition(
        enable: Bool,
        currentScaling: Double?,
        savedPrevious: Double?
    ) -> Transition {
        let effectiveCurrent = currentScaling ?? defaultScaling
        if enable {
            let preserved = savedPrevious ?? effectiveCurrent
            return Transition(
                targetScaling: disabledScaling,
                updatedSavedPrevious: preserved,
                needsUpdate: abs(effectiveCurrent - disabledScaling) > 0.0001
            )
        } else {
            let restoreTarget = savedPrevious ?? defaultScaling
            return Transition(
                targetScaling: restoreTarget,
                updatedSavedPrevious: nil,
                needsUpdate: abs(effectiveCurrent - restoreTarget) > 0.0001
            )
        }
    }
}
