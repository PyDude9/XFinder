import SwiftUI
import AppKit
@preconcurrency import AVFoundation
import QuartzCore

/// Dynamic Island Camera Mirror page (Reference 7 preview workflow in XFinder visual style).
///
/// - Mirrored, video-only live preview that stays strictly on-device.
/// - Explicit Start and Stop controls; camera access is requested only on explicit Start.
/// - Adapts between Ref29 wide (`612 pt`) and narrow (`382 pt`) Island bodies inside the `156 pt` height budget.
/// - Releases the capture session on disappear, backgrounding, or coordinator-driven `close()`.
struct NotchMirrorPage: View {
    @ObservedObject var controller: MirrorCaptureController
    var embedsInIsland: Bool = true

    @Environment(\.notchAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase

    private typealias N = XFinderTokens.Notch

    var body: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < 460
            Group {
                if controller.state.isPreviewVisible {
                    activePreviewBody(isNarrow: isNarrow)
                } else {
                    standbyBody(isNarrow: isNarrow)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if !embedsInIsland {
                controller.onAppear()
            }
        }
        .onDisappear {
            controller.close()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                controller.close()
            }
        }
    }

    // MARK: - Active mirrored preview (running / interrupted)

    @ViewBuilder
    private func activePreviewBody(isNarrow: Bool) -> some View {
        if isNarrow {
            narrowPreviewCard
        } else {
            HStack(spacing: XFinderTokens.Space.row) {
                previewSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                wideControlCard
                    .frame(width: 176)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var previewSurface: some View {
        ZStack {
            MirrorPreviewRepresentable(
                controller: controller,
                isRunning: controller.state == .running
            )

            if controller.state == .interrupted {
                Color.black.opacity(0.55)
                VStack(spacing: XFinderTokens.Space.tight) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(L10n.t(controller.state.statusMessageKey))
                        .font(XFinderTokens.Font.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .strokeBorder(N.cardStroke, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if let badgeKey = controller.state.statusBadgeKey {
                statusBadge(
                    label: L10n.t(badgeKey),
                    tint: controller.state == .running ? .green : .orange
                )
                .padding(8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Xem trước camera trực tiếp"))
    }

    private var wideControlCard: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(L10n.t("Gương"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            if let deviceName = controller.activeDeviceName, !deviceName.isEmpty {
                Text(deviceName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Text(L10n.t("Chỉ xem trực tiếp trên máy, không ghi hình."))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: XFinderTokens.Space.tight) {
                if controller.state == .interrupted {
                    Button(L10n.t("Thử lại")) {
                        controller.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.mini)
                    .accessibilityLabel(L10n.t("Thử lại"))
                }

                Button {
                    controller.stop()
                } label: {
                    Label(L10n.t("Tắt camera"), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .accessibilityLabel(L10n.t("Tắt camera"))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                        .strokeBorder(N.cardStroke, lineWidth: 1)
                )
        )
    }

    private var narrowPreviewCard: some View {
        previewSurface
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if controller.state == .interrupted {
                        Button(L10n.t("Thử lại")) {
                            controller.start()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent))
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("Thử lại"))
                    }

                    Button {
                        controller.stop()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text(L10n.t("Tắt camera"))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red.opacity(0.88)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Tắt camera"))
                }
                .padding(8)
            }
            .overlay(alignment: .bottom) {
                Text(L10n.t("Chỉ xem trực tiếp trên máy, không ghi hình."))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
    }

    private func statusBadge(label: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.62)))
    }

    // MARK: - Standby / permission / error states

    private func standbyBody(isNarrow: Bool) -> some View {
        VStack(spacing: isNarrow ? 5 : XFinderTokens.Space.tight) {
            Image(systemName: standbySymbol)
                .font(XFinderTokens.Font.pageIcon)
                .foregroundStyle(standbySymbolColor)

            Text(L10n.t(controller.state.statusMessageKey))
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, isNarrow ? 8 : 24)

            standbyControls

            if controller.state == .idle {
                Text(L10n.t("Chỉ xem trực tiếp trên máy, không ghi hình."))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                        .strokeBorder(N.cardStroke, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var standbyControls: some View {
        if controller.state.isBusy {
            HStack(spacing: XFinderTokens.Space.row) {
                ProgressView()
                    .controlSize(.small)
                Button(L10n.t("Hủy")) {
                    controller.stop()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel(L10n.t("Hủy"))
            }
        } else if controller.state.showsOpenSettings {
            HStack(spacing: XFinderTokens.Space.tight) {
                Button(L10n.t("Mở Cài đặt hệ thống")) {
                    controller.openPrivacySettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.mini)
                .accessibilityLabel(L10n.t("Mở Cài đặt hệ thống"))

                Button(L10n.t("Thử lại")) {
                    controller.start()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel(L10n.t("Thử lại"))
            }
        } else if let actionKey = controller.state.primaryActionTitleKey {
            Button(L10n.t(actionKey)) {
                controller.start()
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.small)
            .accessibilityLabel(L10n.t(actionKey))
        }
    }

    private var standbySymbol: String {
        switch controller.state {
        case .idle, .requesting, .starting, .running:
            return "video.fill"
        case .interrupted:
            return "pause.circle.fill"
        case .denied:
            return "exclamationmark.shield"
        case .restricted:
            return "lock.fill"
        case .unavailable:
            return "video.slash.fill"
        case .deviceRemoved:
            return "cable.connector.slash"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .misconfigured:
            return "wrench.and.screwdriver.fill"
        }
    }

    private var standbySymbolColor: Color {
        switch controller.state {
        case .idle, .requesting, .starting, .running:
            return accent
        case .interrupted, .denied, .deviceRemoved, .failed:
            return .orange
        case .restricted, .unavailable, .misconfigured:
            return .white.opacity(0.55)
        }
    }
}

// MARK: - Mirrored AVCaptureVideoPreviewLayer host

private struct MirrorPreviewRepresentable: NSViewRepresentable {
    let controller: MirrorCaptureController
    let isRunning: Bool

    func makeNSView(context: Context) -> MirrorPreviewNSView {
        MirrorPreviewNSView(preview: controller.makePreviewLayer())
    }

    func updateNSView(_ nsView: MirrorPreviewNSView, context: Context) {
        if isRunning {
            nsView.applyMirroring()
        }
    }

    static func dismantleNSView(_ nsView: MirrorPreviewNSView, coordinator: ()) {
        nsView.preview.session = nil
    }
}

private final class MirrorPreviewNSView: NSView {
    let preview: AVCaptureVideoPreviewLayer

    init(preview: AVCaptureVideoPreviewLayer) {
        self.preview = preview
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        applyMirroring()
        CATransaction.commit()
    }

    func applyMirroring() {
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            if connection.automaticallyAdjustsVideoMirroring {
                connection.automaticallyAdjustsVideoMirroring = false
            }
            if !connection.isVideoMirrored {
                connection.isVideoMirrored = true
            }
            preview.sublayerTransform = CATransform3DIdentity
        } else {
            // Fallback horizontal mirror when a virtual/external camera connection does not support native mirroring.
            preview.sublayerTransform = CATransform3DMakeScale(-1, 1, 1)
        }
    }
}
