import AppKit

/// XF-T30 W6 — New Folder with Selection, ⌘X cut, Redo, Clear Operation History; persistent undo through `UndoJournal`.
/// Contract docs/specs/XF-T30-w6-contract.md. W6 builder (model).
extension BrowserWindowModel {
    func performFileOpsCommand(_ command: BrowserCommand) -> Bool { false }
    func canPerformFileOpsCommand(_ command: BrowserCommand) -> Bool { false }

    /// ⌘V with a pending ⌘X cut (CutBoard): moves the cut items into the active folder and returns true; false = no
    /// pending cut, the ordinary paste runs.
    func pasteCutItems() -> Bool { false }
}
