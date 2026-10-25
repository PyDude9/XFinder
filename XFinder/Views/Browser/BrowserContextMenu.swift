import AppKit

/// XF-T30 W2 — the ONE right-click menu of the browser (all four views and the toolbar's "…"), Finder's order
/// (contract docs/specs/XF-T30-w2-contract.md §3). W2 builder (menu).
@MainActor
enum BrowserContextMenu {
    /// The menu for the active tab's selection (or the background menu when nothing is selected).
    static func menu(for model: BrowserWindowModel, pane: PaneState) -> NSMenu { NSMenu() }
}
