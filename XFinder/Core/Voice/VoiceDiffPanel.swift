import AppKit
import SwiftUI

/// The "review before inserting" card.
///
/// Shown only when the user has switched review on **and** the rewrite actually changed
/// something. It presents the raw transcription against the rewritten text as a word-level
/// diff — removed words struck through in red, added words underlined in green — so the user
/// can see what the model did before it lands in their document.
///
/// Interaction is keyboard-only, and that is a deliberate limit rather than an oversight: the
/// card floats over another application, and a panel that can take a click can also swallow
/// one meant for the document underneath. Return accepts, Esc discards, and both keys arrive
/// through the same session-level event tap that starts dictation — so they work no matter
/// which app is frontmost.
@MainActor
public final class VoiceDiffPanel {
    public static let shared = VoiceDiffPanel()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<DiffCardView>?

    private init() {}

    public var isVisible: Bool { panel != nil }

    public func show(original: String, rewritten: String, mode: DictationMode) {
        let runs = VoiceTextDiff.runs(from: original, to: rewritten)

        let size = NSSize(width: 560, height: 240)
        if panel == nil {
            let created = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.level = .statusBar
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            // Same rule as the HUD: never intercept a click aimed at the document.
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let host = NSHostingView(rootView: DiffCardView(runs: runs, mode: mode, changed: VoiceTextDiff.changedTokenCount(from: original, to: rewritten)))
            host.wantsLayer = true
            created.contentView = host
            self.hostingView = host
            self.panel = created
        } else {
            hostingView?.rootView = DiffCardView(runs: runs, mode: mode, changed: VoiceTextDiff.changedTokenCount(from: original, to: rewritten))
        }

        reposition()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel?.animator().alphaValue = 1
        }
    }

    public func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Same as VoiceHUD.hide: the completion runs on the main thread, but the closure
            // is not main-actor isolated, so the isolation is stated rather than inferred.
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                self?.panel = nil
                self?.hostingView = nil
            }
        })
    }

    private func reposition() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 24
        ))
    }
}

private struct DiffCardView: View {
    let runs: [DiffRun]
    let mode: DictationMode
    let changed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.checkmark")
                    .foregroundColor(.white.opacity(0.9))
                Text(L10n.t("Xem lại trước khi chèn"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(L10n.t(mode.labelKey))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
                Spacer(minLength: 0)
                Text("\(L10n.t("Đã sửa "))\(changed)\(L10n.t(" từ"))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            ScrollView {
                Text(attributed)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)

            HStack(spacing: 14) {
                keyHint(key: "Return", label: L10n.t("Chèn"))
                keyHint(key: "Esc", label: L10n.t("Hủy"))
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(width: 560, height: 240, alignment: .topLeading)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(Color.black.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    /// Build the diff as one attributed string so the reader sees the change *in place*
    /// rather than as two columns they have to compare by eye.
    private var attributed: AttributedString {
        var output = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            switch run.status {
            case .same:
                piece.foregroundColor = .white.opacity(0.88)
            case .removed:
                piece.foregroundColor = .systemRed
                piece.strikethroughStyle = .single
            case .added:
                piece.foregroundColor = .systemGreen
                piece.underlineStyle = .single
            }
            output.append(piece)
            output.append(AttributedString(" "))
        }
        return output
    }

    private func keyHint(key: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.65))
        }
    }
}
