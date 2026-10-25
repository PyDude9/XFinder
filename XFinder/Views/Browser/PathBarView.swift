import SwiftUI
import AppKit

/// XF-T30 W1 — the bottom Path Bar (⌥⌘P), separate from the top Location Bar: an `NSPathControl` of the tab's
/// folder; clicking a segment navigates that tab there. Height-capped (FileOctopus 1.0.4 fix: "path bar could grow
/// to fill most of a window").
struct PathBarView: View {
    static let height: CGFloat = 24

    let pane: PaneState
    let model: BrowserWindowModel

    var body: some View {
        PathControlRepresentable(path: pane.path) { newPath in
            pane.navigate(to: newPath)
        }
        .frame(height: Self.height)
        .padding(.horizontal, XFinderTokens.Space.tight)
    }
}

private struct PathControlRepresentable: NSViewRepresentable {
    let path: String
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.backgroundColor = .clear
        control.target = context.coordinator
        control.action = #selector(Coordinator.clicked(_:))
        control.url = URL(fileURLWithPath: path)
        context.coordinator.onSelect = onSelect
        return control
    }

    func updateNSView(_ nsView: NSPathControl, context: Context) {
        context.coordinator.onSelect = onSelect
        let current = nsView.url?.path
        guard current != path else { return }
        nsView.url = URL(fileURLWithPath: path)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: ((String) -> Void)?

        @objc func clicked(_ sender: NSPathControl) {
            guard let clicked = sender.clickedPathItem, let url = clicked.url else { return }
            onSelect?(url.path)
        }
    }
}
