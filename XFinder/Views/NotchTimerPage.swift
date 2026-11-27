import SwiftUI

/// P2 + XF-ISLAND 1B — Đồng hồ (Countdown, Stopwatch, Pomodoro, and optional Hydration reminder)
/// for the NARROW notch body (content 354 × 140).
/// All state lives on `NotchSurfaceController.shared` / `model` — this page starts no timer of its
/// own and never reads `Date()` directly; `model.timerNow` is the controller's 1 s tick, so idle
/// and paused frames stay perfectly static and running frames advance with the single ticker.
struct NotchTimerPage: View {
    var model: NotchSurfaceModel
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch
    private static let m = NotchSurfaceLayout.Metrics.standard

    /// Idle ruler range (minutes) and tick spacing, matching `LiveActivity.timerMinMinutes/timerMaxMinutes`.
    private static let idleRulerMax = 120
    private static let idleMinorEvery = 5
    private static let idleMajorEvery = 15

    private var timer: LiveActivity.Countdown? { model.timer }
    private var stopwatch: NotchStopwatch { model.stopwatch }
    private var pomodoro: NotchPomodoro { model.pomodoro }
    private var hydration: NotchHydrationReminder { model.hydration }
    private var mode: NotchClockMode { model.clockMode }
    private var now: Date { model.timerNow }

    private var pomodoroPhaseText: String {
        switch pomodoro.phase {
        case .focus: return L10n.t("Tập trung")
        case .shortBreak: return L10n.t("Nghỉ ngắn")
        case .longBreak: return L10n.t("Nghỉ dài")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            modeHeaderRow
                .frame(height: Self.m.timerTitleHeight + 4, alignment: .center)
            Spacer(minLength: 0).frame(height: max(2, Self.m.timerTitleGap - 4))
            timeRow
                .frame(height: Self.m.timerTimeHeight, alignment: .center)
            Spacer(minLength: 0).frame(height: Self.m.timerTimeGap)
            middleRow
                .frame(height: Self.m.timerRulerHeight, alignment: .center)
            Spacer(minLength: 0).frame(height: Self.m.timerRulerGap)
            controlsRow
                .frame(height: Self.m.timerControlsHeight, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Top row (20 pt): mode switcher (Countdown / Stopwatch / Pomodoro) + optional Hydration toggle.

    private var modeHeaderRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            HStack(spacing: 2) {
                modeChip(.countdown, label: L10n.t("Hẹn giờ"), active: timer != nil)
                modeChip(.stopwatch, label: L10n.t("Bấm giờ"), active: stopwatch.isActive)
                modeChip(.pomodoro, label: L10n.t("Pomodoro"), active: pomodoro.isActive)
            }
            .padding(2)
            .background(Capsule().fill(N.capsule))

            Spacer(minLength: XFinderTokens.Space.tight)

            hydrationControls
        }
    }

    private func modeChip(_ target: NotchClockMode, label: String, active: Bool) -> some View {
        let selected = mode == target
        return Button {
            NotchSurfaceController.shared.selectClockMode(target)
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                if active && !selected {
                    Circle()
                        .fill(accent)
                        .frame(width: 4, height: 4)
                }
            }
            .foregroundColor(selected ? .black : .white.opacity(0.75))
            .padding(.horizontal, 7)
            .frame(height: 16)
            .background(Capsule().fill(selected ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var hydrationControls: some View {
        HStack(spacing: 3) {
            Button {
                NotchSurfaceController.shared.setHydrationEnabled(!hydration.enabled)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: hydration.enabled ? "drop.fill" : "drop")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(hydration.enabled ? .cyan : .white.opacity(0.6))
                    if hydration.enabled {
                        Text(hydration.dailyLimit.formatted())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Capsule().fill(hydration.enabled ? Color.cyan.opacity(0.22) : N.capsule))
            }
            .buttonStyle(.plain)
            .help(hydration.enabled ? L10n.t("Tắt nhắc uống nước") : L10n.t("Bật nhắc uống nước"))
            .accessibilityLabel(L10n.t("Nhắc uống nước"))
            .accessibilityValue(hydration.enabled
                                ? L10n.t("Đang bật")
                                : L10n.t("Đang tắt"))

            if hydration.enabled {
                Menu {
                    ForEach(Array(NotchHydrationReminder.dailyLimitRange), id: \.self) { limit in
                        Button(String(format: L10n.t("%d lần mỗi ngày"), limit)) {
                            NotchSurfaceController.shared.setHydrationDailyLimit(limit)
                        }
                    }
                    Divider()
                    Text(L10n.t("Giờ nhắc: 08:00–20:00"))
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .controlSize(.mini)
                .fixedSize()
                .help(L10n.t("Giới hạn nhắc uống nước mỗi ngày"))
                .accessibilityLabel(L10n.t("Giới hạn nhắc uống nước mỗi ngày"))
                .accessibilityValue(String(format: L10n.t("%d lần mỗi ngày"), hydration.dailyLimit))
            }
        }
    }

    // MARK: - Time row (46 pt)

    @ViewBuilder private var timeRow: some View {
        switch mode {
        case .countdown:
            countdownTimeRow
        case .stopwatch:
            Text(stopwatch.label(at: now))
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .opacity(stopwatch.isPaused ? 0.55 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel(L10n.t("Bấm giờ"))
                .accessibilityValue(stopwatch.label(at: now))
        case .pomodoro:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Spacer(minLength: 0)
                Text(pomodoro.label(at: now))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .opacity(pomodoro.isPaused ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pomodoroPhaseText)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.white.opacity(0.85))
                    Text("\(pomodoro.cycleSlot)/\(pomodoro.config.cyclesBeforeLongBreak)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(L10n.t("Pomodoro")) \(pomodoroPhaseText)")
            .accessibilityValue(pomodoro.label(at: now))
        }
    }

    @ViewBuilder private var countdownTimeRow: some View {
        if let timer {
            Text(timer.label(at: now))
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .opacity(timer.isPaused ? 0.5 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Spacer(minLength: 0)
                Text("\(model.timerDraftMinutes)")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Text(L10n.t("phút"))
                    .font(XFinderTokens.Font.row)
                    .opacity(0.6)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Middle row (22 pt): Countdown ruler, Stopwatch lap readout, or Pomodoro cycle bar.

    @ViewBuilder private var middleRow: some View {
        switch mode {
        case .countdown:
            countdownRulerRow
        case .stopwatch:
            stopwatchLapRow
        case .pomodoro:
            pomodoroProgressRow
        }
    }

    private var countdownRulerRow: some View {
        Canvas { ctx, size in
            if let timer {
                drawRunningRuler(ctx: &ctx, size: size, progress: timer.progress(at: now))
            } else {
                drawIdleRuler(ctx: &ctx, size: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.t("Thước thời gian hẹn giờ"))
        .accessibilityValue(timer == nil
                             ? "\(model.timerDraftMinutes) \(L10n.t("phút"))"
                             : timer!.label(at: now))
    }

    private var stopwatchLapRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            if let latest = stopwatch.laps.last {
                Text("\(L10n.t("Lượt "))\(stopwatch.laps.count)")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.white.opacity(0.6))
                Text(NotchStopwatch.formatDuration(latest))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: XFinderTokens.Space.tight)
                Text(stopwatch.isRunning ? L10n.t("Đang chạy") : L10n.t("Đang tạm dừng"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.white.opacity(0.55))
            } else {
                Text(stopwatch.isRunning ? L10n.t("Đang chạy") : stopwatch.isPaused ? L10n.t("Đang tạm dừng") : L10n.t("Chưa ghi lượt"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("Lượt bấm giờ"))
    }

    private var pomodoroProgressRow: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Canvas { ctx, size in
                drawRunningRuler(ctx: &ctx, size: size, progress: pomodoro.progress(at: now))
            }
            HStack(spacing: 4) {
                ForEach(0..<pomodoro.config.cyclesBeforeLongBreak, id: \.self) { idx in
                    Circle()
                        .fill(idx < pomodoro.completedDotsInCycle ? accent : N.progressTrack)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Tiến độ Pomodoro"))
        .accessibilityValue("\(pomodoroPhaseText) \(pomodoro.cycleSlot)/\(pomodoro.config.cyclesBeforeLongBreak)")
    }

    private func drawIdleRuler(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let baseline = h - 4
        var track = Path()
        track.move(to: CGPoint(x: 0, y: baseline))
        track.addLine(to: CGPoint(x: w, y: baseline))
        ctx.stroke(track, with: .color(N.progressTrack), lineWidth: 1)

        let maxMin = Self.idleRulerMax
        var minute = 0
        while minute <= maxMin {
            let x = w * CGFloat(minute) / CGFloat(maxMin)
            let isMajor = minute % Self.idleMajorEvery == 0
            let isMinor = minute % Self.idleMinorEvery == 0
            if isMajor || isMinor {
                let tickHeight: CGFloat = isMajor ? 8 : 4
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: baseline))
                tick.addLine(to: CGPoint(x: x, y: baseline - tickHeight))
                ctx.stroke(tick, with: .color(N.progressTrack.opacity(isMajor ? 1 : 0.7)), lineWidth: 1)
            }
            minute += Self.idleMinorEvery
        }

        let markerX = w * CGFloat(min(max(model.timerDraftMinutes, 0), maxMin)) / CGFloat(maxMin)
        var marker = Path()
        marker.move(to: CGPoint(x: markerX - 4, y: 0))
        marker.addLine(to: CGPoint(x: markerX + 4, y: 0))
        marker.addLine(to: CGPoint(x: markerX, y: 7))
        marker.closeSubpath()
        ctx.fill(marker, with: .color(accent))
    }

    private func drawRunningRuler(ctx: inout GraphicsContext, size: CGSize, progress: Double) {
        let w = size.width
        let h = size.height
        let baseline = h - 4
        var track = Path()
        track.move(to: CGPoint(x: 0, y: baseline))
        track.addLine(to: CGPoint(x: w, y: baseline))
        ctx.stroke(track, with: .color(N.progressTrack), lineWidth: 1)

        let clamped = min(max(progress, 0), 1)
        let elapsedX = w * CGFloat(clamped)
        var elapsed = Path()
        elapsed.move(to: CGPoint(x: 0, y: baseline))
        elapsed.addLine(to: CGPoint(x: elapsedX, y: baseline))
        ctx.stroke(elapsed, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let halfWidth = min(4, w / 2)
        let markerX = min(max(elapsedX, halfWidth), w - halfWidth)
        var marker = Path()
        marker.move(to: CGPoint(x: markerX - halfWidth, y: 0))
        marker.addLine(to: CGPoint(x: markerX + halfWidth, y: 0))
        marker.addLine(to: CGPoint(x: markerX, y: 7))
        marker.closeSubpath()
        ctx.fill(marker, with: .color(accent))
    }

    // MARK: - Controls row (40 pt)

    @ViewBuilder private var controlsRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            switch mode {
            case .countdown:
                if let timer {
                    runningOrPausedControls(timer)
                } else {
                    idleControls
                }
            case .stopwatch:
                stopwatchControls
            case .pomodoro:
                pomodoroControls
            }
            Spacer(minLength: 0)
        }
    }

    private var idleControls: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            roundButton(systemName: "minus", help: L10n.t("Giảm")) {
                NotchSurfaceController.shared.setTimerDraft(
                    minutes: LiveActivity.steppedMinutes(model.timerDraftMinutes, by: -1))
            }
            .disabled(model.timerDraftMinutes <= LiveActivity.timerMinMinutes)

            primaryCircleButton(systemName: "play.fill", help: L10n.t("Bắt đầu hẹn giờ")) {
                NotchSurfaceController.shared.startTimer(minutes: model.timerDraftMinutes)
            }

            roundButton(systemName: "plus", help: L10n.t("Tăng")) {
                NotchSurfaceController.shared.setTimerDraft(
                    minutes: LiveActivity.steppedMinutes(model.timerDraftMinutes, by: 1))
            }
            .disabled(model.timerDraftMinutes >= LiveActivity.timerMaxMinutes)
        }
    }

    @ViewBuilder private func runningOrPausedControls(_ timer: LiveActivity.Countdown) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            roundButton(systemName: "minus", help: L10n.t("Bớt 5 phút")) {
                NotchSurfaceController.shared.extendTimer(byMinutes: -LiveActivity.timerStepMinutes)
            }

            if timer.isPaused {
                primaryCircleButton(systemName: "play.fill", help: L10n.t("Tiếp tục")) {
                    NotchSurfaceController.shared.resumeTimer()
                }
            } else {
                primaryCircleButton(systemName: "pause.fill", help: L10n.t("Tạm dừng")) {
                    NotchSurfaceController.shared.pauseTimer()
                }
            }

            roundButton(systemName: "plus", help: L10n.t("Thêm 5 phút")) {
                NotchSurfaceController.shared.extendTimer(byMinutes: LiveActivity.timerStepMinutes)
            }

            roundButton(systemName: "xmark", help: L10n.t("Dừng hẹn giờ"), small: true) {
                NotchSurfaceController.shared.cancelTimer()
            }
        }
    }

    private var stopwatchControls: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            roundButton(systemName: "flag", help: L10n.t("Ghi lượt")) {
                NotchSurfaceController.shared.lapStopwatch()
            }
            .disabled(!stopwatch.isActive)

            if stopwatch.isRunning {
                primaryCircleButton(systemName: "pause.fill", help: L10n.t("Tạm dừng")) {
                    NotchSurfaceController.shared.pauseStopwatch()
                }
            } else if stopwatch.isPaused {
                primaryCircleButton(systemName: "play.fill", help: L10n.t("Tiếp tục")) {
                    NotchSurfaceController.shared.resumeStopwatch()
                }
            } else {
                primaryCircleButton(systemName: "play.fill", help: L10n.t("Bắt đầu bấm giờ")) {
                    NotchSurfaceController.shared.startStopwatch()
                }
            }

            roundButton(systemName: "arrow.counterclockwise", help: L10n.t("Đặt lại bấm giờ")) {
                NotchSurfaceController.shared.resetStopwatch()
            }
            .disabled(!stopwatch.isActive)
        }
    }

    private var pomodoroControls: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            roundButton(systemName: "arrow.counterclockwise", help: L10n.t("Đặt lại Pomodoro")) {
                NotchSurfaceController.shared.resetPomodoro()
            }
            .disabled(!pomodoro.isActive && pomodoro.phase == .focus && pomodoro.completedFocusSessions == 0)

            if pomodoro.isRunning {
                primaryCircleButton(systemName: "pause.fill", help: L10n.t("Tạm dừng")) {
                    NotchSurfaceController.shared.pausePomodoro()
                }
            } else if pomodoro.isPaused {
                primaryCircleButton(systemName: "play.fill", help: L10n.t("Tiếp tục")) {
                    NotchSurfaceController.shared.resumePomodoro()
                }
            } else {
                primaryCircleButton(systemName: "play.fill", help: L10n.t("Bắt đầu Pomodoro")) {
                    NotchSurfaceController.shared.startPomodoro()
                }
            }

            roundButton(systemName: "forward.end.fill", help: L10n.t("Bỏ qua giai đoạn")) {
                NotchSurfaceController.shared.skipPomodoroPhase()
            }
        }
    }

    private func primaryCircleButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// Shared round icon-only button, matching the toolbar ✕'s `N.capsule`-filled circle.
    /// `help` is already localised by the caller (a literal inside L10n.t at each call site, so the sweep sees it).
    private func roundButton(systemName: String, help: String, small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: small ? 11 : 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: small ? 28 : 32, height: small ? 28 : 32)
                .background(Circle().fill(N.capsule))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
