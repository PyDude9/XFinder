import SwiftUI

/// XF-T30 W1 — the Status Bar (⌘/): "N mục, X còn trống" like Finder; with a selection "M trên N mục được chọn".
/// Free space comes from a cache refreshed off the main thread, never from `statfs` inside `body`. W1 builder (views).
struct StatusBarView: View {
    let pane: PaneState

    var body: some View {
        EmptyView()
    }
}
