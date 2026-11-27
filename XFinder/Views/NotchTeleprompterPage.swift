import SwiftUI
import AppKit

/// Dynamic Island Teleprompter page (fits the 156 pt expanded Island body).
/// Provides local script editing, inline reader mode, playback/speed/font controls,
/// and a separate floating reader window anchored below the top edge of the active display.
struct NotchTeleprompterPage: View {
    @ObservedObject var controller: NotchTeleprompterController
    @Environment(\.notchAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var envReduceMotion
    @FocusState private var editorFocused: Bool

    private typealias N = XFinderTokens.Notch

    init(controller: NotchTeleprompterController = .shared) {
        self.controller = controller
    }

    private var state: NotchTeleprompterState { controller.state }
    private var reduceMotion: Bool { envReduceMotion || state.reduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerBar
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controlBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            controller.onIslandAppear()
        }
        .onDisappear {
            editorFocused = false
            controller.onIslandDisappear()
        }
        .onChange(of: editorFocused) { _, focused in
            controller.setEditingFocus(focused)
        }
        .onExitCommand {
            if state.isReaderWindowVisible {
                controller.closeReaderWindow()
            } else if state.mode == .reader {
                controller.pause()
                controller.setMode(.editor)
            }
        }
    }

    // MARK: - Header (Mode switcher + status + reader window toggle)

    private var headerBar: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            HStack(spacing: 2) {
                modeChip(.editor, label: L10n.t("Soạn thảo"))
                modeChip(.reader, label: L10n.t("Đọc"))
            }
            .padding(2)
            .background(Capsule().fill(N.capsule))

            if controller.wordCount > 0 {
                Text("\(controller.wordCount)\(L10n.t(" từ"))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }

            if state.reachedEnd && state.hasReadableScript {
                Text(L10n.t("Đã đọc hết kịch bản"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            } else if reduceMotion && state.isAnyReaderVisible {
                Text(L10n.t("Chế độ bước"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                controller.toggleReaderWindow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.isReaderWindowVisible ? "macwindow.badge.plus" : "macwindow")
                        .font(.system(size: 10, weight: .semibold))
                    Text(state.isReaderWindowVisible ? L10n.t("Đóng cửa sổ đọc") : L10n.t("Cửa sổ đọc"))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(state.isReaderWindowVisible ? .black : .white.opacity(0.85))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(state.isReaderWindowVisible ? Color.white : N.capsule))
            }
            .buttonStyle(.plain)
            .help(state.isReaderWindowVisible ? L10n.t("Đóng cửa sổ đọc") : L10n.t("Mở cửa sổ đọc"))
            .accessibilityLabel(state.isReaderWindowVisible ? L10n.t("Đóng cửa sổ đọc") : L10n.t("Mở cửa sổ đọc"))
        }
    }

    private func modeChip(_ target: NotchTeleprompterMode, label: String) -> some View {
        let selected = state.mode == target
        return Button {
            controller.setMode(target)
        } label: {
            Text(label)
                .font(.system(size: 10, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .black : .white.opacity(0.75))
                .padding(.horizontal, 8)
                .frame(height: 16)
                .background(Capsule().fill(selected ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Content Area (Editor vs Inline Reader)

    @ViewBuilder
    private var contentArea: some View {
        switch state.mode {
        case .editor:
            editorView
        case .reader:
            if state.hasReadableScript {
                TeleprompterScriptViewport(
                    script: state.script,
                    fontSize: max(13, state.fontSize * 0.72),
                    progress: state.progress,
                    reduceMotion: reduceMotion,
                    accent: accent,
                    onMeasureScrollableDistance: { distance in
                        controller.updateScrollableDistance(distance, isReaderWindow: false)
                    }
                )
                .background(
                    RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                        .strokeBorder(N.cardStroke, lineWidth: 1)
                )
            } else {
                emptyScriptView
            }
        }
    }

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .topLeading) {
                TextEditor(
                    text: Binding(
                        get: { state.script },
                        set: { controller.updateScript($0) }
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .accessibilityLabel(L10n.t("Soạn thảo"))

                if state.script.isEmpty {
                    Text(L10n.t("Dán hoặc nhập kịch bản tại đây…"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.38))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                    .strokeBorder(editorFocused ? accent.opacity(0.65) : N.cardStroke, lineWidth: 1)
            )

            HStack(spacing: 6) {
                Text(L10n.t("Kịch bản chỉ lưu cục bộ trên máy này."))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if state.wasTruncated {
                    Text("\(L10n.t("Kịch bản quá dài, đã rút gọn còn "))\(NotchTeleprompterLimits.maxScriptCharacters)\(L10n.t(" ký tự"))")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
    }

    private var emptyScriptView: some View {
        VStack(spacing: 5) {
            Text(L10n.t("Chưa có kịch bản"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(L10n.t("Nhập kịch bản để bắt đầu đọc."))
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
            Button(L10n.t("Chỉnh sửa")) {
                controller.setMode(.editor)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(N.cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Bottom Controls (Play/Pause, Restart, Speed, Font, Progress)

    private var controlBar: some View {
        HStack(spacing: 6) {
            Button {
                controller.togglePlayPause()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(state.isPlaying ? L10n.t("Tạm dừng") : L10n.t("Phát"))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(state.hasReadableScript ? .black : .white.opacity(0.4))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    Capsule().fill(state.hasReadableScript ? Color.white : N.capsule)
                )
            }
            .buttonStyle(.plain)
            .disabled(!state.hasReadableScript)
            .accessibilityLabel(state.isPlaying ? L10n.t("Tạm dừng") : L10n.t("Phát"))

            Button {
                controller.restart()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(state.hasReadableScript ? .white.opacity(0.85) : .white.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(N.capsule))
            }
            .buttonStyle(.plain)
            .disabled(!state.hasReadableScript)
            .help(L10n.t("Bắt đầu lại"))
            .accessibilityLabel(L10n.t("Bắt đầu lại"))

            stepperPill(
                title: L10n.t("Tốc độ"),
                valueText: String(format: "%.1f×", state.speedMultiplier),
                minusLabel: L10n.t("Giảm tốc độ"),
                plusLabel: L10n.t("Tăng tốc độ"),
                canDecrease: state.speedPointsPerSecond > NotchTeleprompterLimits.minSpeed,
                canIncrease: state.speedPointsPerSecond < NotchTeleprompterLimits.maxSpeed,
                onDecrease: { controller.decreaseSpeed() },
                onIncrease: { controller.increaseSpeed() }
            )

            stepperPill(
                title: L10n.t("Cỡ chữ"),
                valueText: "\(Int(state.fontSize.rounded()))\(L10n.t(" pt"))",
                minusLabel: L10n.t("Giảm cỡ chữ"),
                plusLabel: L10n.t("Tăng cỡ chữ"),
                canDecrease: state.fontSize > NotchTeleprompterLimits.minFontSize,
                canIncrease: state.fontSize < NotchTeleprompterLimits.maxFontSize,
                onDecrease: { controller.decreaseFontSize() },
                onIncrease: { controller.increaseFontSize() }
            )

            Spacer(minLength: 2)

            Text("\(Int((state.progress * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))
                .accessibilityLabel(L10n.t("Vị trí đọc"))
                .accessibilityValue("\(Int((state.progress * 100).rounded()))%")
        }
    }

    private func stepperPill(
        title: String,
        valueText: String,
        minusLabel: String,
        plusLabel: String,
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(canDecrease ? .white.opacity(0.85) : .white.opacity(0.3))
                    .frame(width: 16, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!canDecrease)
            .accessibilityLabel(minusLabel)

            Text(valueText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)

            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(canIncrease ? .white.opacity(0.85) : .white.opacity(0.3))
                    .frame(width: 16, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!canIncrease)
            .accessibilityLabel(plusLabel)
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(Capsule().fill(N.capsule))
        .help(title)
    }
}

// MARK: - Separate Floating Reader Window View

/// Separate floating Teleprompter reader window positioned below the top edge of the active display.
/// Shares exact reading position (`state.progress`), script, speed, and font size with the Island view.
struct NotchTeleprompterReaderWindowView: View {
    @ObservedObject var controller: NotchTeleprompterController
    @Environment(\.accessibilityReduceMotion) private var envReduceMotion

    private typealias N = XFinderTokens.Notch

    private var state: NotchTeleprompterState { controller.state }
    private var reduceMotion: Bool { envReduceMotion || state.reduceMotion }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label(L10n.t("Máy nhắc chữ"), systemImage: "text.alignleft")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                if state.reachedEnd && state.hasReadableScript {
                    Text(L10n.t("Đã đọc hết kịch bản"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                } else if reduceMotion {
                    Text(L10n.t("Chế độ bước"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Text(L10n.t("Nhấn Esc để đóng"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))

                Button {
                    controller.closeReaderWindow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(N.capsule))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Đóng cửa sổ đọc"))
                .accessibilityLabel(L10n.t("Đóng cửa sổ đọc"))
            }

            if state.hasReadableScript {
                TeleprompterScriptViewport(
                    script: state.script,
                    fontSize: state.fontSize,
                    progress: state.progress,
                    reduceMotion: reduceMotion,
                    accent: .accentColor,
                    onMeasureScrollableDistance: { distance in
                        controller.updateScrollableDistance(distance, isReaderWindow: true)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    Text(L10n.t("Chưa có kịch bản"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(L10n.t("Nhập kịch bản để bắt đầu đọc."))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                Button {
                    controller.togglePlayPause()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(state.isPlaying ? L10n.t("Tạm dừng") : L10n.t("Phát"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(state.hasReadableScript ? .black : .white.opacity(0.4))
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Capsule().fill(state.hasReadableScript ? Color.white : N.capsule))
                }
                .buttonStyle(.plain)
                .disabled(!state.hasReadableScript)

                Button {
                    controller.restart()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.hasReadableScript ? .white.opacity(0.85) : .white.opacity(0.35))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(N.capsule))
                }
                .buttonStyle(.plain)
                .disabled(!state.hasReadableScript)
                .help(L10n.t("Bắt đầu lại"))
                .accessibilityLabel(L10n.t("Bắt đầu lại"))

                Slider(
                    value: Binding(
                        get: { state.progress },
                        set: { controller.setProgress($0) }
                    ),
                    in: 0...1
                )
                .controlSize(.mini)
                .disabled(!state.hasReadableScript)
                .accessibilityLabel(L10n.t("Vị trí đọc"))

                compactAdjuster(
                    label: L10n.t("Tốc độ"),
                    value: String(format: "%.1f×", state.speedMultiplier),
                    canDecrease: state.speedPointsPerSecond > NotchTeleprompterLimits.minSpeed,
                    canIncrease: state.speedPointsPerSecond < NotchTeleprompterLimits.maxSpeed,
                    onDecrease: { controller.decreaseSpeed() },
                    onIncrease: { controller.increaseSpeed() }
                )

                compactAdjuster(
                    label: L10n.t("Cỡ chữ"),
                    value: "\(Int(state.fontSize.rounded()))\(L10n.t(" pt"))",
                    canDecrease: state.fontSize > NotchTeleprompterLimits.minFontSize,
                    canIncrease: state.fontSize < NotchTeleprompterLimits.maxFontSize,
                    onDecrease: { controller.decreaseFontSize() },
                    onIncrease: { controller.increaseFontSize() }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(
            minWidth: NotchTeleprompterLimits.minReaderSize.width,
            minHeight: NotchTeleprompterLimits.minReaderSize.height
        )
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .strokeBorder(N.cardStroke, lineWidth: 1)
        )
        .foregroundStyle(.white)
        .onExitCommand {
            controller.closeReaderWindow()
        }
    }

    private func compactAdjuster(
        label: String,
        value: String,
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(canDecrease ? .white : .white.opacity(0.3))
                    .frame(width: 18, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(!canDecrease)

            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))

            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(canIncrease ? .white : .white.opacity(0.3))
                    .frame(width: 18, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(!canIncrease)
        }
        .padding(.horizontal, 4)
        .frame(height: 24)
        .background(Capsule().fill(N.capsule))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - Shared Teleprompter Script Viewport

/// Renders the teleprompter script offset smoothly (or stepped without animation under Reduce Motion)
/// by normalized `progress` (`0...1`) and reports its measured scrollable distance back to the controller.
private struct TeleprompterScriptViewport: View {
    let script: String
    let fontSize: Double
    let progress: Double
    let reduceMotion: Bool
    let accent: Color
    let onMeasureScrollableDistance: (Double) -> Void

    @State private var measuredTextHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let viewportHeight = max(1, geo.size.height)
            let verticalLead = max(12, viewportHeight * 0.28)
            let scrollableDistance = max(0, Double(measuredTextHeight + verticalLead - viewportHeight))
            let yOffset = -CGFloat(progress * scrollableDistance)

            ZStack(alignment: .topLeading) {
                // Subtle reading-line guide near the upper third (closest to the camera).
                Rectangle()
                    .fill(accent.opacity(0.14))
                    .frame(height: max(22, CGFloat(fontSize) * 1.45))
                    .offset(y: max(6, viewportHeight * 0.22))
                    .allowsHitTesting(false)

                Text(script)
                    .font(.system(size: CGFloat(fontSize), weight: .medium))
                    .lineSpacing(max(4, CGFloat(fontSize) * 0.25))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, verticalLead)
                    .padding(.bottom, verticalLead)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .onAppear {
                                    updateHeight(textGeo.size.height, viewportHeight: viewportHeight, verticalLead: verticalLead)
                                }
                                .onChange(of: textGeo.size.height) { _, newHeight in
                                    updateHeight(newHeight, viewportHeight: viewportHeight, verticalLead: verticalLead)
                                }
                        }
                    )
                    .offset(y: yOffset)
                    .animation(reduceMotion ? nil : .linear(duration: 1.0 / 30.0), value: progress)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white, location: 0.14),
                        .init(color: .white, location: 0.86),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: geo.size.height) { _, newHeight in
                let newLead = max(12, newHeight * 0.28)
                let dist = max(0, Double(measuredTextHeight + newLead - newHeight))
                onMeasureScrollableDistance(dist)
            }
        }
    }

    private func updateHeight(_ textHeight: CGFloat, viewportHeight: CGFloat, verticalLead: CGFloat) {
        measuredTextHeight = textHeight
        let dist = max(0, Double(textHeight + verticalLead - viewportHeight))
        onMeasureScrollableDistance(dist)
    }
}
