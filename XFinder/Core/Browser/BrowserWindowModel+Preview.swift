import AppKit

/// XF-T30 W7 — the Preview pane toggle (⇧⌘P) and the slideshow (⌥⌘Y). Contract docs/specs/XF-T30-w78-contract.md.
/// W7 builder (model).
extension BrowserWindowModel {
    func performPreviewCommand(_ command: BrowserCommand) -> Bool { false }
    func canPerformPreviewCommand(_ command: BrowserCommand) -> Bool { false }
}
