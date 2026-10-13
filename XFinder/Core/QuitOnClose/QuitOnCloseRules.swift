import Foundation

/// F3 — "When I close the last window of Preview / TextEdit, the app should quit instead of sitting in the Dock."
/// Pure: which apps are watched, and when a closed window means "quit now".
///
/// Measured with a two-window harness app and an AX observer (2026-10-13, macOS 27, Stage Manager on):
/// * closing a window delivers `kAXUIElementDestroyedNotification` within ~0.05 s and `kAXWindows` is updated at once;
/// * closing the LAST window leaves `kAXWindows` empty while the app keeps running (AppKit's default) — the moment
///   this feature exists for;
/// * a HIDDEN app still lists its windows, but their subrole changes from `AXStandardWindow` to `AXDialog` — so the
///   rule counts EVERY window and never filters by subrole (a subrole filter would quit a merely hidden app);
/// * minimizing could not be produced here (neither the AX minimize button nor `NSWindow.miniaturize` took the window
///   off screen with Stage Manager on), so "a minimized window keeps the app" rests on `kAXWindows` listing minimized
///   windows, which Apple documents but this pass did not measure.
enum QuitOnCloseRules {

    static let enabledKey = "quitOnClose.enabled"
    static let appsKey = "quitOnClose.apps"
    /// Re-count this long after a window closes: ⌘W then ⌘N, or a document that closes one window and opens another,
    /// must not quit the app in between.
    static let grace: TimeInterval = 1.0

    /// Never quit these, whatever the list says: closing the last Finder window is normal, and the others are the
    /// system or XFinder itself.
    static let neverQuit: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
                                         "com.apple.systemuiserver", "com.apple.controlcenter"]

    static func parseApps(_ raw: String?) -> Set<String> {
        Set((raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func encodeApps(_ ids: Set<String>) -> String { ids.sorted().joined(separator: ",") }

    static func isWatched(_ bundleID: String?, enabled: Bool, apps: Set<String>, ownBundleID: String) -> Bool {
        guard enabled, let bid = bundleID, !bid.isEmpty, bid != ownBundleID, !neverQuit.contains(bid) else { return false }
        return apps.contains(bid)
    }

    /// Asked `grace` seconds after a window of a watched app was destroyed. Quit only when nothing is left at all —
    /// no window of any kind (a palette or an open dialog keeps the app) — and the app is still there to quit.
    static func shouldQuit(windowCount: Int?, stillRunning: Bool, watched: Bool) -> Bool {
        guard watched, stillRunning, let n = windowCount else { return false }   // nil: AX could not read ⇒ do nothing
        return n == 0
    }
}
