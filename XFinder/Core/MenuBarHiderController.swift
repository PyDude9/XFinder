import AppKit
import Combine

/// Biểu tượng thanh menu.
///
/// **macOS 26/27 broke the mechanism this used to rely on — measured, not
/// assumed.** The old approach was the Bartender/Hidden-Bar trick: own an
/// expandable "separator" status item, let the user ⌘-drag icons to its left,
/// then set `separator.length = 10_000` so everything left of it is pushed off
/// the visible bar.
///
/// Probes run on macOS 27.0 (26A428), 1728 pt screen:
///
/// 1. `length = 10_000` is **clamped by the OS to ~5016 pt** — still far wider
///    than the screen, so width alone was not the problem.
/// 2. With the separator expanded, a neighbouring status item did **not** leave
///    the bar. It moved *right*, from x=952 to x=988, and stayed `ONSCREEN`
///    through a 7-second settle. macOS 27 lays the bar out ignoring the
///    oversized item instead of letting it displace its neighbours.
/// 3. `CGWindowListCopyWindowInfo` reports **0** windows at the status-item
///    layer, so an app cannot even observe other apps' items to work around it.
///
/// What still works is `NSStatusItem.isVisible`, and that only ever applied to
/// **an app's own items**. So the honest scope of this controller is now:
/// XFinder can hide *its own* status items, and nothing more. Hiding other
/// apps' icons is a macOS 26+ System Settings feature (Control Centre →
/// Menu Bar), which is where the UI now sends the user.
///
/// Per the Honesty Rule, the separator item is **not installed any more**: it
/// would put a widget in the user's menu bar that no longer does what its own
/// help text promises.
@MainActor
@Observable
final class MenuBarHiderController: NSResponder {
    static let shared = MenuBarHiderController()

    /// True while XFinder's own optional status items are hidden.
    private(set) var isHiding = false

    /// Whether the OS-level mechanism this feature needs still exists.
    /// Kept as a stored fact so the UI can explain itself rather than
    /// silently doing nothing.
    let separatorTrickAvailable = false

    private override init() { super.init() }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Settings (read at point of use)

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "menubar.hiderEnabled") as? Bool ?? false
    }

    /// Applies the saved settings. Deliberately installs nothing: there is no
    /// supported way left to hide another app's status item, so installing a
    /// separator would be a dead control sitting in the user's menu bar.
    func applySettings() {
        // Intentionally empty. Left as the single call site referenced from
        // `applicationDidFinishLaunching` so the wiring stays visible.
    }

    /// Opens the macOS pane that genuinely controls menu-bar icons (macOS 26+
    /// moved this into Control Centre settings). Falls back to the Control
    /// Centre pane, then to System Settings itself, so the button is never dead.
    func openSystemMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
