import SwiftUI

/// XF-T30 W4 — the file browser's own Settings window (⌘, while a browser window is key): General, Sidebar, Cloud,
/// Advanced, Keyboard, Search, Privacy. Contract docs/specs/XF-T30-w4-contract.md §3. W4 builder (settings).
@MainActor
final class BrowserSettingsWindowController {
    static let shared = BrowserSettingsWindowController()
    enum Tab: String, CaseIterable { case general, sidebar, cloud, advanced, keyboard, search, privacy }
    func show(tab: Tab? = nil) {}
}
