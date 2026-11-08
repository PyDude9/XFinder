import Foundation

/// XF-T37 L5 — "Warn before quitting (⌘Q)" for the file browser (FileOctopus 1.0.10: "When on, hold ⌘Q or press it
/// twice to quit. Closing the last window never quits"). In XFinder it matters more than in a plain file manager: ⌘Q
/// in a browser window quits the whole app — the notch, clipboard history, agents and every other feature with it.
///
/// Pure: the caller supplies where the quit came from. Only a ⌘Q typed while a browser window is key is guarded; Quit
/// from XFinder's menu-bar menu, the Dock, logout/restart, or another XFinder window quits at once.
enum QuitGuardRules {
    /// A second ⌘Q within this many seconds of the warning quits. Holding ⌘Q repeats the key (the menu's key equivalent
    /// fires on every repeat), so a hold lands inside the window as well — one rule covers "press twice" and "hold".
    static let confirmWindow: TimeInterval = 1.5

    enum Decision: Equatable, Sendable { case quit, warn }

    static func decide(enabled: Bool, typedCommandQ: Bool, browserWindowIsKey: Bool, lastWarning: Date?,
                       now: Date) -> Decision {
        guard enabled, typedCommandQ, browserWindowIsKey else { return .quit }
        if let lastWarning {
            let elapsed = now.timeIntervalSince(lastWarning)
            if elapsed >= 0, elapsed <= confirmWindow { return .quit }
        }
        return .warn
    }

    /// The keyDown that triggered the quit is ⌘Q (with or without Shift/Option — the menu's key equivalent matches on
    /// the character with ⌘), not a click on a menu item or an Apple event.
    static func isCommandQ(isKeyDown: Bool, charactersIgnoringModifiers: String?, hasCommand: Bool) -> Bool {
        isKeyDown && hasCommand && charactersIgnoringModifiers?.lowercased() == "q"
    }
}
