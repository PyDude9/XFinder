import AppKit

/// XF-T30 W1 — the browser window's native `NSToolbar` (FileOctopus order: Back/Forward, View, Group, Pane Layout,
/// Share, Action, Search; customizable, plus Enclosing Folder, Go to Folder, Workspaces, Shelf, Operations).
/// Contract docs/specs/XF-T30-w1-contract.md §5. W1 builder (chrome): implement.
@MainActor
final class BrowserToolbarController: NSObject, NSToolbarDelegate, BrowserChrome {
    let model: BrowserWindowModel
    weak var window: NSWindow?

    init(model: BrowserWindowModel, window: NSWindow) {
        self.model = model
        self.window = window
        super.init()
    }

    /// Builds the toolbar, attaches it to `window`, and becomes `model.chrome`.
    func install() {
        model.chrome = self
    }

    func focusSearchField() {}
    func toggleToolbarShown() { window?.toggleToolbarShown(nil) }
    func runToolbarCustomization() { window?.runToolbarCustomizationPalette(nil) }
}
