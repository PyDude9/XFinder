import SwiftUI
import AppKit

/// XF-T30 W1 — the bottom Path Bar (⌥⌘P), separate from the top Location Bar: an `NSPathControl` of the tab's folder;
/// clicking a segment opens it in the same tab. Height-capped (FileOctopus 1.0.4 fix). W1 builder (views): implement.
struct PathBarView: View {
    let pane: PaneState
    let model: BrowserWindowModel

    var body: some View {
        EmptyView()
    }
}
