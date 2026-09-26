import AppKit
import SwiftUI

/// Floating translucent HUD displaying real-time ghost text preview at the cursor position while speaking.
@MainActor
public final class VoiceGhostOverlay {
    public static let shared = VoiceGhostOverlay()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<GhostContentView>?
    private var currentText: String = ""
    private var currentRMS: Float = 0.0

    private init() {}

    public func show(near point: CGPoint? = nil) {
        let mouse = point ?? NSEvent.mouseLocation
        let width: CGFloat = 320
        let height: CGFloat = 64

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: mouse.x + 16, y: mouse.y + 16, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .popUpMenu
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true

            let content = GhostContentView(text: currentText, rms: currentRMS)
            let host = NSHostingView(rootView: content)
            host.wantsLayer = true
            p.contentView = host
            self.hostingView = host
            self.panel = p
        }

        updatePosition(near: mouse)
        panel?.alphaValue = 0.0
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel?.animator().alphaValue = 1.0
        }
    }

    public func update(text: String, rms: Float = 0.0) {
        self.currentText = text
        self.currentRMS = rms
        hostingView?.rootView = GhostContentView(text: text, rms: rms)
    }

    public func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
            self?.hostingView = nil
            self?.currentText = ""
            self?.currentRMS = 0.0
        })
    }

    private func updatePosition(near mouse: CGPoint) {
        guard let panel = panel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = mouse.x + 16
        var y = mouse.y + 16

        if x + panel.frame.width > screen.maxX - 10 {
            x = mouse.x - panel.frame.width - 16
        }
        if y + panel.frame.height > screen.maxY - 10 {
            y = mouse.y - panel.frame.height - 16
        }

        panel.setFrameOrigin(CGPoint(x: max(screen.minX + 10, x), y: max(screen.minY + 10, y)))
    }
}

private struct GhostContentView: View {
    let text: String
    let rms: Float

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing Mic Indicator
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: 24, height: 24)
                    .scaleEffect(1.0 + CGFloat(rms) * 0.4)
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
            }

            // Real-time Text Preview
            VStack(alignment: .leading, spacing: 2) {
                if text.isEmpty {
                    Text(L10n.t("Đang nghe…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                        .italic()
                } else {
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 320, height: 60)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(Color.black.opacity(0.40))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
