import AppKit
import SwiftUI

/// The floating dictation pill.
///
/// Replaces the earlier `VoiceGhostOverlay`, which was a fixed 320×60 box that appeared next
/// to the mouse and showed one line of text. Three things were wrong with it, and each is
/// fixed by a specific decision here:
///
/// 1. **The waveform was a scaled circle.** It moved on an RMS value but had no history, so
///    it could not show the *shape* of speech. `WaveformView` now draws a rolling window of
///    levels, and it advances **on each audio buffer** — there is no timer anywhere in this
///    file, which is what keeps an idle app at 0 % CPU (see CLAUDE.md).
/// 2. **It only knew one position.** The anchor is now a choice: `caret` follows the pointer,
///    `notch` pins the pill to the top of whichever screen the pointer is on.
/// 3. **It had no state beyond "listening".** The pill now distinguishes listening,
///    refining (with the mode name), and failure, and while refining it shows the two keys
///    that matter: Space to insert the raw transcription immediately, Esc to cancel.
///
/// It is `ignoresMouseEvents = true` on purpose: the pill floats over whatever the user is
/// working in, and a floating panel that can swallow a click is worse than one that cannot
/// be clicked. The interactions are keyboard-driven, through the same event tap that starts
/// the session.
@MainActor
public final class VoiceHUD {
    public static let shared = VoiceHUD()

    /// What the pill is showing.
    public enum Phase: Equatable {
        case listening
        case refining(mode: DictationMode)
        case failed(String)
    }

    private var panel: NSPanel?
    private var hostingView: NSHostingView<HUDRootView>?

    private var phase: Phase = .listening
    private var partialText: String = ""
    private var levels: [Float] = Array(repeating: 0, count: VoiceHUD.waveformBarCount)
    private var anchor: VoiceHUDAnchor = .caret
    private var showWaveform: Bool = true

    /// 34 bars is what fits a 420 pt pill at 5 pt per bar with 7 pt gaps.
    public static let waveformBarCount = 34

    private init() {}

    public var isVisible: Bool { panel != nil }

    public func configure(anchor: VoiceHUDAnchor, showWaveform: Bool) {
        self.anchor = anchor
        self.showWaveform = showWaveform
        if panel != nil { reposition() }
    }

    public func show(anchor: VoiceHUDAnchor, showWaveform: Bool) {
        self.anchor = anchor
        self.showWaveform = showWaveform
        self.phase = .listening
        self.partialText = ""
        self.levels = Array(repeating: 0, count: Self.waveformBarCount)
        ensurePanel()
        render()
        reposition()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel?.animator().alphaValue = 1
        }
    }

    /// Advance the waveform. Called once per captured audio buffer — **not** on a timer.
    public func pushLevel(_ normalized: Float) {
        guard panel != nil else { return }
        levels.removeFirst()
        levels.append(max(0, min(1, normalized)))
        render()
    }

    public func updatePartial(_ text: String) {
        guard panel != nil else { return }
        partialText = text
        render()
    }

    public func enterRefining(mode: DictationMode) {
        guard panel != nil else { return }
        phase = .refining(mode: mode)
        // Collapse the waveform to a flat line: the microphone is closed, and leaving a live
        // waveform on screen would say the opposite.
        levels = Array(repeating: 0, count: Self.waveformBarCount)
        render()
    }

    public func showFailure(_ message: String) {
        // This can be called *after* `hide()` — the fallback notice is shown once the raw
        // text has already been inserted and the pill torn down. Re-create it in that case,
        // otherwise the message is silently dropped and the user is never told the model
        // failed.
        let wasHidden = panel == nil
        if wasHidden {
            phase = .failed(message)
            ensurePanel()
            reposition()
            panel?.alphaValue = 0
            panel?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel?.animator().alphaValue = 1
            }
            render()
            return
        }
        phase = .failed(message)
        render()
    }

    public func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // AppKit invokes this on the main thread, but the closure is not main-actor
            // isolated, so the compiler cannot see that. Stating the isolation is what keeps
            // the panel teardown from reading as a concurrency hazard.
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                self?.panel = nil
                self?.hostingView = nil
            }
        })
    }

    // MARK: - Panel plumbing

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = NSSize(width: 420, height: 78)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // A pill that can be clicked is a pill that can steal a click from the app underneath.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: HUDRootView(
            phase: phase, partialText: partialText, levels: levels, showWaveform: showWaveform
        ))
        host.wantsLayer = true
        panel.contentView = host
        self.hostingView = host
        self.panel = panel
    }

    private func render() {
        hostingView?.rootView = HUDRootView(
            phase: phase, partialText: partialText, levels: levels, showWaveform: showWaveform
        )
    }

    private func reposition() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let frame = screen?.frame else { return }

        let size = panel.frame.size
        switch anchor {
        case .notch:
            // Top-centre of the active screen, just under the menu bar.
            let x = frame.midX - size.width / 2
            let y = frame.maxY - size.height - 12
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        case .caret:
            var x = mouse.x + 18
            var y = mouse.y - size.height - 18
            if x + size.width > frame.maxX - 12 { x = mouse.x - size.width - 18 }
            if y < frame.minY + 12 { y = mouse.y + 18 }
            panel.setFrameOrigin(NSPoint(x: max(frame.minX + 12, x), y: y))
        }
    }
}

// MARK: - Views

private struct HUDRootView: View {
    let phase: VoiceHUD.Phase
    let partialText: String
    let levels: [Float]
    let showWaveform: Bool

    var body: some View {
        HStack(spacing: 12) {
            leadingGlyph
            VStack(alignment: .leading, spacing: 3) {
                headline
                if showWaveform, case .listening = phase {
                    WaveformView(levels: levels)
                        .frame(height: 20)
                } else {
                    secondaryLine
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 420, height: 78, alignment: .leading)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(Color.black.opacity(0.42))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch phase {
        case .listening:
            ZStack {
                Circle().fill(Color.red.opacity(0.22)).frame(width: 30, height: 30)
                Circle().fill(Color.red).frame(width: 11, height: 11)
            }
        case .refining:
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(.orange)
                .frame(width: 30, height: 30)
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch phase {
        case .listening:
            if partialText.isEmpty {
                Text(L10n.t("Đang nghe…"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
                    .italic()
            } else {
                Text(partialText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.96))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        case .refining(let mode):
            HStack(spacing: 6) {
                Text(L10n.t("Đang tút lại văn bản…"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                Text(L10n.t(mode.labelKey))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var secondaryLine: some View {
        switch phase {
        case .listening:
            Text(L10n.t("Thả phím để chèn · Esc để hủy"))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        case .refining:
            Text(L10n.t("Space để chèn ngay bản gốc · Esc để hủy"))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        case .failed:
            Text(L10n.t("Thử lại hoặc kiểm tra quyền trong trang Nhập bằng giọng nói."))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
    }
}

/// A rolling window of audio levels drawn in one `Canvas`.
///
/// `Canvas` rather than a stack of `Shape`s: the earlier `SparklineView` was rewritten for the
/// same reason (see CLAUDE.md) — one reused drawing surface instead of a layer per bar, which
/// matters when the view is redrawn on every audio buffer.
private struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            let count = max(levels.count, 1)
            let barWidth: CGFloat = 3
            let gap: CGFloat = (size.width - barWidth * CGFloat(count)) / CGFloat(max(count - 1, 1))
            let midY = size.height / 2

            for (index, level) in levels.enumerated() {
                // A quiet room still shows a dot, so the pill reads as "alive and listening"
                // rather than "frozen".
                let amplitude = max(0.06, CGFloat(level))
                let barHeight = max(3, amplitude * size.height)
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                // Older bars fade out, which is what makes the direction of travel readable.
                let age = CGFloat(index) / CGFloat(count)
                context.fill(path, with: .color(.white.opacity(0.35 + 0.6 * age)))
            }
        }
    }
}
