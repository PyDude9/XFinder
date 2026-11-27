import Foundation

/// Pure rules for Fixed Space Order (macOS `com.apple.dock` `mru-spaces`).
/// When enabled, saves the user's previous `mru-spaces` preference and sets it to `false`
/// so macOS stops rearranging Spaces by most recent use. When disabled, restores the saved
/// value (defaulting to `true`, macOS's standard behavior).
enum SpacesOrderRules {
    static let enabledKey = "spacesOrder.fixedEnabled"
    static let savedPreviousKey = "spacesOrder.previousMRUSpaces"
    static let dockDomain = "com.apple.dock"
    static let dockMRUSpacesKey = "mru-spaces"

    struct Transition: Equatable, Sendable {
        /// The boolean value to write to `com.apple.dock mru-spaces`.
        let targetDockMRUSpaces: Bool
        /// The value to store in `savedPreviousKey`, or `nil` to remove the saved key.
        let updatedSavedPrevious: Bool?
        /// Whether `defaults write` + Dock reload is needed (skip if Dock already matches).
        let needsDockUpdate: Bool
    }

    /// Compute the exact state transition when the user toggles Fixed Space Order.
    /// - Parameters:
    ///   - enable: `true` to lock Space order (`mru-spaces = false`), `false` to restore.
    ///   - currentDockMRUSpaces: Current value of `com.apple.dock mru-spaces` (`nil` means macOS default `true`).
    ///   - savedPrevious: Previously saved value from `savedPreviousKey`, if any.
    static func transition(
        enable: Bool,
        currentDockMRUSpaces: Bool?,
        savedPrevious: Bool?
    ) -> Transition {
        let effectiveCurrent = currentDockMRUSpaces ?? true
        if enable {
            let preserved = savedPrevious ?? effectiveCurrent
            return Transition(
                targetDockMRUSpaces: false,
                updatedSavedPrevious: preserved,
                needsDockUpdate: effectiveCurrent != false
            )
        } else {
            let restoreTarget = savedPrevious ?? true
            return Transition(
                targetDockMRUSpaces: restoreTarget,
                updatedSavedPrevious: nil,
                needsDockUpdate: effectiveCurrent != restoreTarget
            )
        }
    }
}
