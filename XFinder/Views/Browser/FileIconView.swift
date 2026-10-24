import AppKit
import SwiftUI

/// XF-T28 — STUB written by the integrator; the cluster agent replaces the body (contract: docs/specs/XF-T28-ui-contract.md).
struct FileIconView: NSViewRepresentable {
    let pane: PaneState
    let model: BrowserWindowModel
    func makeNSView(context: Context) -> NSScrollView { NSScrollView() }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
