import AppKit

/// XF-T30 W8 — cloud actions: Download Now / Remove Download for one or many items, blocking copies of cloud-only items
/// out of a cloud folder, provider links only when measured. Contract docs/specs/XF-T30-w5b-w8-contract.md. W8 builder.
extension BrowserWindowModel {
    /// The provider holding `path`, if any.
    func cloudProvider(for path: String) -> CloudProvider? { nil }
}
