import AppKit

/// XF-T30 W3 — the Go menu, recent folders, virtual locations (Recents, tags), Connect to Server, Eject.
/// Contract docs/specs/XF-T30-w3-contract.md. W3 builder (model).
extension BrowserWindowModel {
    func performGoCommand(_ command: BrowserCommand) -> Bool { false }
    func canPerformGoCommand(_ command: BrowserCommand) -> Bool { false }

    /// Opens a virtual location in the active tab.
    func open(_ location: VirtualLocation) {}

    /// Every folder a tab navigates to (Go ▸ Recent Folders). Virtual locations are not recorded.
    static func noteRecentFolder(_ path: String) {}
}
