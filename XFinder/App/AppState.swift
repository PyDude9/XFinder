import Foundation
import Combine
import AppKit

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var selection: SidebarDestination = .dashboard
    var caffeineActive = false

    private init() {
        // Debug affordance: `-startPage <rawValue>` opens straight to a page,
        // so a specific screen can be inspected without clicking through.
        if let raw = UserDefaults.standard.string(forKey: "startPage"),
           let dest = SidebarDestination(rawValue: raw) {
            selection = dest
        }
    }

    func navigate(to destination: SidebarDestination) {
        selection = destination
        bringMainWindowFront()
    }

    /// The app's real settings/browser window — NOT one of our floating panels.
    ///
    /// `NSApp.windows` also contains the edge-notes strip, the clipboard shelf
    /// and the Dock-hover preview. Taking `.first` of that array raised a
    /// borderless panel instead, which looked exactly like "clicking the Dock
    /// icon does nothing". An `NSPanel` is never the main window, and a real
    /// window can take key/main status — that pair identifies it reliably.
    static func mainAppWindow() -> NSWindow? {
        NSApp.windows.first {
            !($0 is NSPanel) && $0.canBecomeMain && $0.contentView != nil
        }
    }

    func bringMainWindowFront() {
        guard let window = Self.mainAppWindow() else { return }
        // `deminiaturize` first: a minimised window ignores makeKeyAndOrderFront
        // and stays in the Dock, which was another way this appeared dead.
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
