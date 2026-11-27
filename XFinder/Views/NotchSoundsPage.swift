import SwiftUI

/// Ambient sounds page for the narrow Dynamic Island body (354 × 140 pt content budget).
///
/// All playback and timer state lives in `NotchSoundsEngine.shared`, so collapsing the notch
/// or switching pages never interrupts playback or the fade-out countdown. This view starts no
/// timers of its own and never calls `stopAll` in `onDisappear`.
struct NotchSoundsPage: View {
    var engine: NotchSoundsEngine = .shared
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch

    // Exact narrow-tool body budget (140 pt): 20 + 6 + (3 × 26 + 2 × 4) + 6 + 22 = 140.
    private static let headerHeight: CGFloat = 20
    private static let sectionGap: CGFloat = 6
    private static let channelRowHeight: CGFloat = 26
    private static let channelSpacing: CGFloat = 4
    private static let timerRowHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .frame(height: Self.headerHeight, alignment: .center)
            Spacer(minLength: 0).frame(height: Self.sectionGap)
            channelsStack
                .frame(height: Self.channelRowHeight * 3 + Self.channelSpacing * 2, alignment: .center)
            Spacer(minLength: 0).frame(height: Self.sectionGap)
            sleepTimerRow
                .frame(height: Self.timerRowHeight, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header (20 pt): icon + title, honest status/error, Stop All button.

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: engine.isPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(engine.isPlaying ? accent : .white.opacity(0.75))
            Text(L10n.t("Âm nền"))
                .font(XFinderTokens.Font.row)
            Spacer(minLength: XFinderTokens.Space.tight)
            statusLabel
            stopAllButton
        }
    }

    @ViewBuilder private var statusLabel: some View {
        if let err = engine.lastError {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text(errorMessage(err))
                    .font(XFinderTokens.Font.caption)
                    .lineLimit(1)
            }
            .foregroundColor(.orange)
        } else if engine.isFadingOut, let rem = engine.remainingTimerText {
            Text("\(L10n.t("Đang tắt dần "))\(rem)")
                .font(XFinderTokens.Font.caption.monospacedDigit())
                .opacity(0.75)
                .lineLimit(1)
        } else if engine.isPlaying {
            Text("\(engine.activeCount)\(L10n.t(" âm đang phát"))")
                .font(XFinderTokens.Font.caption.monospacedDigit())
                .opacity(0.65)
                .lineLimit(1)
        } else {
            Text(L10n.t("Đang tắt"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.55)
                .lineLimit(1)
        }
    }

    private var stopAllButton: some View {
        Button {
            engine.stopAll(reason: .user)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(L10n.t("Dừng tất cả"))
                    .font(XFinderTokens.Font.caption)
            }
            .foregroundColor(engine.isPlaying ? .white : .white.opacity(0.35))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(N.capsule))
        }
        .buttonStyle(.plain)
        .disabled(!engine.isPlaying)
        .help(L10n.t("Dừng tất cả âm nền"))
        .accessibilityLabel(L10n.t("Dừng tất cả âm nền"))
    }

    // MARK: - Channels (86 pt): White, Pink, Brown noise rows.

    private var channelsStack: some View {
        VStack(spacing: Self.channelSpacing) {
            ForEach(NotchSoundsRules.NoiseKind.allCases) { kind in
                channelRow(kind)
                    .frame(height: Self.channelRowHeight)
            }
        }
    }

    private func channelRow(_ kind: NotchSoundsRules.NoiseKind) -> some View {
        let active = engine.isActive(kind)
        let vol = engine.volume(for: kind)
        let pct = Int((vol * 100).rounded())

        return HStack(spacing: 8) {
            Button {
                engine.toggle(kind)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14)
                    Text(noiseName(kind))
                        .font(XFinderTokens.Font.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundColor(active ? .white : .white.opacity(0.75))
                .padding(.horizontal, 8)
                .frame(width: 152, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                        .fill(active ? accent.opacity(0.85) : N.capsule)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(noiseName(kind))
            .accessibilityAddTraits(active ? .isSelected : [])

            NotchSoundSlider(
                value: vol,
                tint: active ? accent : .white.opacity(0.45),
                accessibilityLabel: "\(L10n.t("Âm lượng "))\(noiseName(kind))"
            ) { newValue in
                engine.setVolume(newValue, for: kind)
            }

            Text("\(pct)%")
                .font(XFinderTokens.Font.caption.monospacedDigit())
                .opacity(active ? 0.85 : 0.4)
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Sleep / Fade-Out Timer Row (22 pt)

    private var sleepTimerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(engine.sleepTimer != nil ? 0.9 : 0.55)
                Text(L10n.t("Tắt dần"))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.7)
            }

            HStack(spacing: 4) {
                ForEach(NotchSoundsRules.SleepPreset.allCases) { preset in
                    presetChip(preset)
                }
            }

            Spacer(minLength: 0)

            if let rem = engine.remainingTimerText, !engine.isFadingOut {
                Text(rem)
                    .font(XFinderTokens.Font.caption.monospacedDigit())
                    .opacity(0.75)
                    .lineLimit(1)
            }
        }
    }

    private func presetChip(_ preset: NotchSoundsRules.SleepPreset) -> some View {
        let selected = engine.selectedPreset == preset && (preset == .off || engine.sleepTimer != nil)
        let disabled = preset != .off && !engine.isPlaying
        return Button {
            engine.setSleepPreset(preset)
        } label: {
            Text(presetLabel(preset))
                .font(XFinderTokens.Font.caption.monospacedDigit())
                .foregroundColor(selected ? .white : .white.opacity(disabled ? 0.3 : 0.7))
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(
                    Capsule().fill(selected ? accent.opacity(0.85) : N.capsule)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(presetAccessibilityLabel(preset))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Direct L10n Literals (visible to scripts/audit-l10n-literals.py)

    private func noiseName(_ kind: NotchSoundsRules.NoiseKind) -> String {
        switch kind {
        case .white: return L10n.t("Tiếng ồn trắng")
        case .pink: return L10n.t("Tiếng ồn hồng")
        case .brown: return L10n.t("Tiếng ồn nâu")
        }
    }

    private func presetLabel(_ preset: NotchSoundsRules.SleepPreset) -> String {
        switch preset {
        case .off: return L10n.t("Tắt")
        case .min15: return L10n.t("15p")
        case .min30: return L10n.t("30p")
        case .min60: return L10n.t("60p")
        }
    }

    private func presetAccessibilityLabel(_ preset: NotchSoundsRules.SleepPreset) -> String {
        switch preset {
        case .off: return L10n.t("Tắt hẹn giờ tắt dần")
        case .min15: return L10n.t("Tắt dần sau 15 phút")
        case .min30: return L10n.t("Tắt dần sau 30 phút")
        case .min60: return L10n.t("Tắt dần sau 60 phút")
        }
    }

    private func errorMessage(_ error: NotchSoundsRules.EngineError) -> String {
        switch error {
        case .noOutputDevice: return L10n.t("Không có thiết bị phát âm thanh.")
        case .engineStartFailed: return L10n.t("Không khởi động được bộ phát âm thanh.")
        }
    }
}

/// Slim Notch-styled horizontal volume slider matching `NotchLevelBar` / `NowPlayingSeekBar`.
private struct NotchSoundSlider: View {
    let value: Double
    let tint: Color
    let accessibilityLabel: String
    let onChange: (Double) -> Void

    private typealias N = XFinderTokens.Notch

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let clamped = NotchSoundsRules.clampVolume(value)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(N.progressTrack)
                    .frame(height: 4)
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, w * CGFloat(clamped)), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 9, height: 9)
                    .offset(x: min(max(0, w * CGFloat(clamped) - 4.5), max(0, w - 9)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let next = NotchSoundsRules.clampVolume(Double(drag.location.x / w))
                        onChange(next)
                    }
            )
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int((NotchSoundsRules.clampVolume(value) * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(NotchSoundsRules.clampVolume(value + 0.1))
            case .decrement: onChange(NotchSoundsRules.clampVolume(value - 0.1))
            @unknown default: break
            }
        }
    }
}
