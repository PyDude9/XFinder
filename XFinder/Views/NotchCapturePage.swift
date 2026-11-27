import SwiftUI
import AppKit

/// Dynamic Island Capture page (`XF-ISLAND-CAPTURE`, fits the 156 pt expanded Island body).
/// Reuses `CaptureController.shared` settings, permission flow, Pro gating, and recent history.
/// Delegates in-flight hide-before-capture handoff state to `NotchCaptureHandoffCoordinator`
/// so unmounting this view on `dismiss()` never drops or duplicates the requested capture.
struct NotchCapturePage: View {
    /// Coordinator contract: hide/collapse the Island panel before starting a capture so the panel
    /// is never captured in the screenshot, then invoke the completion closure on MainActor.
    var onPrepareForCapture: (@escaping @MainActor () -> Void) -> Void
    /// Optional coordinator callback to navigate to Settings → Capture (`xfinder://settings?page=capture`).
    var onOpenCaptureSettings: (() -> Void)?
    /// Shared handoff coordinator owning the in-flight capture token outside this transient view.
    var handoff: NotchCaptureHandoffCoordinator

    @State private var controller = CaptureController.shared

    private typealias N = XFinderTokens.Notch

    init(
        onPrepareForCapture: @escaping (@escaping @MainActor () -> Void) -> Void = { completion in
            completion()
        },
        onOpenCaptureSettings: (() -> Void)? = nil,
        handoff: NotchCaptureHandoffCoordinator = .shared
    ) {
        self.onPrepareForCapture = onPrepareForCapture
        self.onOpenCaptureSettings = onOpenCaptureSettings
        self.handoff = handoff
    }

    private var session: NotchCaptureSessionMachine.State {
        handoff.session
    }

    private var availability: NotchCaptureAvailability {
        NotchCaptureAvailability(
            isFeatureEnabled: controller.isEnabled,
            isScreenRecordingGranted: controller.isScreenRecordingGranted,
            allowsScrollingCapture: LicenseManager.shared.allows(.scrollingCapture)
        )
    }

    private var recentItems: [CaptureItem] {
        NotchCaptureRules.recentItems(from: controller.visibleHistory.visible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !controller.isEnabled {
                disabledView
            } else {
                headerRow
                modesStrip
                recentHistoryRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            handoff.handleIslandReappeared()
        }
        .onDisappear {
            handoff.handleIslandDisappeared()
        }
        .onChange(of: controller.history.first?.id) { _, _ in
            handoff.handleCaptureOutcomeObserved()
        }
        .onChange(of: controller.lastError) { _, _ in
            handoff.handleCaptureOutcomeObserved()
        }
    }

    // MARK: - Disabled State

    private var disabledView: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(L10n.t("Tính năng chụp đang tắt."))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(L10n.t("Bật trong Cài đặt để chụp từ Dynamic Island."))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button(L10n.t("Mở Cài đặt Chụp")) {
                openCaptureSettings()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header & Permission Banner

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            if !controller.isScreenRecordingGranted {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(L10n.t("Cần quyền Ghi màn hình"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(L10n.t("Mở Cài đặt")) {
                    openScreenRecordingPrivacy()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(Capsule().fill(Color.white))
            } else {
                Label(L10n.t("Chụp màn hình"), systemImage: "camera.viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if session.isPreparing {
                    Text(L10n.t("Đang chuẩn bị chụp…"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                } else if let error = controller.lastError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    openCaptureSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 20, height: 18)
                        .background(Capsule().fill(N.capsule))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Mở Cài đặt Chụp"))
                .accessibilityLabel(L10n.t("Mở Cài đặt Chụp"))
            }
        }
        .frame(height: 20)
    }

    // MARK: - Capture Modes

    private var modesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NotchCaptureRules.supportedModes, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        }
        .frame(height: 58)
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        let block = NotchCaptureRules.blockReason(
            for: mode,
            availability: availability,
            isBusy: session.isBusy
        )
        let isProLocked = (block == .proRequired)
        let isPermissionMissing = (block == .permissionDenied)
        let shortcutLabel = controller.shortcut(for: mode)?.label

        return Button {
            handleModeTap(mode)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPermissionMissing || isProLocked ? .white.opacity(0.45) : .white)
                    Spacer(minLength: 2)
                    if isProLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.orange)
                    } else if let shortcutLabel {
                        Text(shortcutLabel)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Text(L10n.t(mode.titleKey))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isPermissionMissing || isProLocked ? .white.opacity(0.55) : .white)
                    .lineLimit(1)
                Text(L10n.t(mode.descriptionKey))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: 112, height: 54, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                    .fill(Color.white.opacity(isPermissionMissing || isProLocked ? 0.04 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                    .strokeBorder(N.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(session.isBusy)
        .help(L10n.t(mode.descriptionKey))
        .accessibilityLabel(L10n.t(mode.titleKey))
    }

    // MARK: - Recent History Strip

    private var recentHistoryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(L10n.t("Ảnh chụp gần đây"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if session.lastCopiedItemID != nil {
                    Text(L10n.t("Đã sao chép"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }

            if recentItems.isEmpty {
                Text(L10n.t("Chưa có ảnh chụp nào."))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recentItems) { item in
                            historyThumb(item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func historyThumb(_ item: CaptureItem) -> some View {
        let thumb = controller.thumbnail(for: item, maxPixel: 120)
        let copied = (session.lastCopiedItemID == item.id)

        return Button {
            copyHistoryItem(item)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                if let thumb {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(copied ? .green : .white)
                    .padding(3)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .padding(3)
            }
            .frame(width: 68, height: 42)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .strokeBorder(copied ? Color.green.opacity(0.8) : N.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L10n.t("Sao chép ảnh chụp"))
        .accessibilityLabel(L10n.t("Sao chép ảnh chụp"))
    }

    // MARK: - Actions & Handoff

    private func handleModeTap(_ mode: CaptureMode) {
        let captureController = controller
        handoff.requestCapture(
            mode: mode,
            availability: {
                NotchCaptureAvailability(
                    isFeatureEnabled: captureController.isEnabled,
                    isScreenRecordingGranted: captureController.isScreenRecordingGranted,
                    allowsScrollingCapture: LicenseManager.shared.allows(.scrollingCapture)
                )
            },
            prepareToHide: onPrepareForCapture,
            launchCapture: { resolvedMode in
                captureController.capture(resolvedMode)
            },
            handleBlocked: { blockedMode, _ in
                // Respect CaptureController's own permission prompt / Pro toast without hiding the Island.
                captureController.capture(blockedMode)
            }
        )
    }

    private func copyHistoryItem(_ item: CaptureItem) {
        controller.copy(item)
        handoff.recordCopied(itemID: item.id)
    }

    private func openScreenRecordingPrivacy() {
        if let url = URL(string: AppPermission.screenRecording.settingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openCaptureSettings() {
        if let onOpenCaptureSettings {
            onOpenCaptureSettings()
        } else if let url = URL(string: "xfinder://settings?page=capture") {
            NSWorkspace.shared.open(url)
        }
    }
}
