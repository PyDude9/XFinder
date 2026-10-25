import SwiftUI

/// XF-T30 W7 — the Preview pane (⇧⌘P) at the right of each pane: Information + Tags, Show More / Show Less, image
/// thumbnail out of process, video poster with Play, never downloads cloud bytes. W7 builder (preview).
struct PreviewPaneView: View {
    let pane: PaneState
    let model: BrowserWindowModel

    var body: some View { EmptyView() }
}
