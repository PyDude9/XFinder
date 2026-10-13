import SwiftUI
import AppKit

/// OneNotch's "Stick on Screen": the capture floats on top of everything, movable by its background
/// (the window itself is `isMovableByWindowBackground`), with a hover ✕ and a magnification gesture
/// / ⌘+ / ⌘− to scale. Several pins can be open at once — each one is its own `PinnedImageWindow`.
struct PinnedImageView: View {
    let image: NSImage
    let onClose: () -> Void

    @State private var hovering = false
    @State private var scale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale * gestureScale)
            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Đóng"))
            }
        }
        .onHover { hovering = $0 }
        .gesture(
            MagnificationGesture()
                .onChanged { value in gestureScale = value }
                .onEnded { value in
                    scale = clampedScale(scale * value)
                    gestureScale = 1
                }
        )
        .background(ScaleKeyCatcher(onZoomIn: { scale = clampedScale(scale * 1.1) },
                                     onZoomOut: { scale = clampedScale(scale / 1.1) }))
    }

    private func clampedScale(_ s: CGFloat) -> CGFloat {
        min(4, max(0.25, s))
    }
}

/// Catches ⌘+ / ⌘− while the pinned window is key, without stealing any other key.
private struct ScaleKeyCatcher: NSViewRepresentable {
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onZoomIn = onZoomIn
        v.onZoomOut = onZoomOut
        return v
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
    }

    final class CatcherView: NSView {
        var onZoomIn: (() -> Void)?
        var onZoomOut: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Removed when the view leaves its window — a deinit cannot touch the monitor under Swift 6 isolation.
            if window == nil, let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil; return }
            if monitor == nil, window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, self.window?.isKeyWindow == true, event.modifierFlags.contains(.command) else { return event }
                    switch event.charactersIgnoringModifiers {
                    case "+", "=": self.onZoomIn?(); return nil
                    case "-": self.onZoomOut?(); return nil
                    default: return event
                    }
                }
            }
        }

    }
}
