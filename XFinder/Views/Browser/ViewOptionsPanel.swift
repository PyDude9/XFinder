import SwiftUI

/// XF-T30 W2 — Show View Options (⌘J): a floating panel for the active tab — view, icon size, text size, List columns,
/// Group By, Sort By, "Always open in this view", "Use as Defaults". W2 builder (menu).
@MainActor
final class ViewOptionsPanelController {
    static let shared = ViewOptionsPanelController()
    func toggle(for model: BrowserWindowModel) {}
}
