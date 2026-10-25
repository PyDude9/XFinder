import AppKit

/// XF-T30 W2 — the model side of the views wave: Group By sections, per-folder view options, Make Alias, Show Original,
/// Add to Sidebar, Share, View Options, Open With, tags. Contract docs/specs/XF-T30-w2-contract.md. W2 builder (model).
extension PaneState {
    /// Rebuilds `sections` from `entries` for `groupBy` / `useGroups` (called at the end of every `applyEntries`).
    func rebuildSections() {}
}

extension BrowserWindowModel {
    func performViewsCommand(_ command: BrowserCommand) -> Bool { false }
    func canPerformViewsCommand(_ command: BrowserCommand) -> Bool { false }

    /// Opens the selection with `app` (Open With ▸).
    func openSelection(with app: URL) {}
    /// Adds (or removes when every selected item already has it) the Finder tag of `color` on the selection.
    func toggleTag(_ color: TagColor) {}
    /// Saves the active tab's view options for its folder ("Always open in this view").
    func rememberViewOptionsForFolder() {}
}
