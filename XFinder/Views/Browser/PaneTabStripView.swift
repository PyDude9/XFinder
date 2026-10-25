import SwiftUI

/// XF-T30 W1 — a pane's tab strip (FileOctopus: every pane has one, with + and two split buttons at its right end).
/// Contract docs/specs/XF-T30-w1-contract.md §4. W1 builder (views): implement.
struct PaneTabStripView: View {
    let paneID: PaneID
    let model: BrowserWindowModel
    let isActive: Bool

    static let height: CGFloat = 28

    var body: some View {
        EmptyView()
    }
}
