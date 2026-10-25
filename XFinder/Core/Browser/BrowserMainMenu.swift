import AppKit

/// XF-T30 W1 (Q-T30-13) — the browser's own menus (File, Edit, View, Go, Window items) while a browser window is key,
/// built from `BrowserCommands` (titles + chords) and dispatched to that window's model. Probe first: if SwiftUI's
/// menu management overwrites inserted menus, ship the fallback (no menu changes) and record it. W1 builder (chrome).
@MainActor
final class BrowserMainMenu {
    static let shared = BrowserMainMenu()

    /// A browser window became key: show menus for `model`.
    func activate(for model: BrowserWindowModel) {}

    /// No browser window is key any more: remove the browser menus.
    func deactivate() {}
}
