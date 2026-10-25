import AppKit

/// XF-T30 W4 — Settings window and Welcome commands, and the behaviour of the W4 keys (Return opens, ⌘X cut, new window
/// target, Tab switches panes). Contract docs/specs/XF-T30-w4-contract.md. W4 builder (model).
extension BrowserWindowModel {
    func performSettingsCommand(_ command: BrowserCommand) -> Bool { false }
    func canPerformSettingsCommand(_ command: BrowserCommand) -> Bool { false }
}
