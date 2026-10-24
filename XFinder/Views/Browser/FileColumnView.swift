import AppKit
import SwiftUI

/// XF-T28 — STUB written by the integrator; the cluster agent replaces the body (contract: docs/specs/XF-T28-ui-contract.md).
struct FileColumnView: NSViewRepresentable {
    let pane: PaneState
    let model: BrowserWindowModel
    func makeNSView(context: Context) -> NSBrowser { NSBrowser() }
    func updateNSView(_ nsView: NSBrowser, context: Context) {}
}
