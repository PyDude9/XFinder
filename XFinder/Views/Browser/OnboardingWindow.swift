import SwiftUI

/// XF-T30 W4 — the Welcome window (Q-T30-9: Welcome · Folder access · Full Disk Access (skippable) · Layout).
/// W4 builder (settings).
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    /// First browser window of a fresh install, or Privacy ▸ "Show Welcome Window…". `opened(layout)` lets the caller
    /// open the chosen layout.
    func show(opened: @escaping @MainActor (PanePreset) -> Void) {}
}
