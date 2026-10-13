import SwiftUI

/// P2 — Hẹn giờ (focus timer) tool, for the NARROW notch body (content 354 × 140, per `CONTRACT.md`/P2). Job
/// sentence: *"I am at the notch — pick a duration, start a countdown, see it, pause/extend/stop it, without
/// leaving."* All state lives on `NotchSurfaceController.shared`/`model.timer` — this page starts no timer of its
/// own and never reads `Date()` directly; `model.timerNow` is the controller's 1 s tick, so idle/paused frames stay
/// perfectly static and running frames advance with the one ticker that already exists.
///
/// Honest scope (Part 0 §6): no task name (`Countdown` is an anonymous duration), no "Full screen" mode, no
/// Pomodoro cycle arcs, no sound picker (the controller already plays "Glass" on finish). Pause/resume are real —
/// `Countdown.paused(at:)`/`resumed(at:)` freeze and restart the clock for real, unlike the OMIT note in the older
/// screen-spec draft, which predates `Countdown` gaining a pause state (CONTRACT.md overrides it here).
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
    private var now: Date { model.timerNow }

    /// Each literal is its own L10n.t argument, so the literal sweep sees all three (P2 review: a key returned from a
    /// computed property and passed as a variable is invisible to every gate).
    private var stateText: String {
        guard let timer else { return L10n.t("Chọn thời gian") }
        return timer.isPaused ? L10n.t("Đang tạm dừng") : L10n.t("Đang chạy")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .frame(height: Self.m.timerTitleHeight, alignment: .center)
            Spacer(minLength: 0).frame(height: Self.m.timerTitleGap)
            timeRow
                .frame(height: Self.m.timerTimeHeight, alignment: .center)
            Spacer(minLength: 0).frame(height: Self.m.timerTimeGap)
            rulerRow
                .frame(height: Self.m.timerRulerHeight, alignment: .center)
            Spacer(minLength: 0).frame(height: Self.m.timerRulerGap)
            controlsRow
                .frame(height: Self.m.timerControlsHeight, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Title row (16 pt): glyph + "Hẹn giờ", state right-aligned.

    private var titleRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .medium))
                .opacity(0.8)
            Text(L10n.t("Hẹn giờ"))
                .font(XFinderTokens.Font.row)
            Spacer(minLength: XFinderTokens.Space.tight)
            Text(stateText)
                .font(XFinderTokens.Font.caption)
                .opacity(0.6)
        }
    }

    // MARK: - Time row (46 pt): idle draft number, or the live countdown label.

    @ViewBuilder private var timeRow: some View {
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

    // MARK: - Ruler row (22 pt): idle = 0…120 min ticks + draft marker; running/paused = whole-duration ticks + elapsed stroke.

    private var rulerRow: some View {
        Canvas { ctx, size in
            if let timer {
                drawRunningRuler(ctx: &ctx, size: size, timer: timer)
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

    private func drawRunningRuler(ctx: inout GraphicsContext, size: CGSize, timer: LiveActivity.Countdown) {
        let w = size.width
        let h = size.height
        let baseline = h - 4
        var track = Path()
        track.move(to: CGPoint(x: 0, y: baseline))
        track.addLine(to: CGPoint(x: w, y: baseline))
        ctx.stroke(track, with: .color(N.progressTrack), lineWidth: 1)

        let progress = timer.progress(at: now)
        let elapsedX = w * CGFloat(progress)
        var elapsed = Path()
        elapsed.move(to: CGPoint(x: 0, y: baseline))
        elapsed.addLine(to: CGPoint(x: elapsedX, y: baseline))
        ctx.stroke(elapsed, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        var marker = Path()
        marker.move(to: CGPoint(x: elapsedX - 4, y: 0))
        marker.addLine(to: CGPoint(x: elapsedX + 4, y: 0))
        marker.addLine(to: CGPoint(x: elapsedX, y: 7))
        marker.closeSubpath()
        ctx.fill(marker, with: .color(accent))
    }

    // MARK: - Controls row (40 pt): idle [−][▶][+]; running [−5][⏸][+5][✕]; paused [−5][▶][+5][✕].

    @ViewBuilder private var controlsRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if let timer {
                runningOrPausedControls(timer)
            } else {
                idleControls
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

            Button {
                NotchSurfaceController.shared.startTimer(minutes: model.timerDraftMinutes)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Bắt đầu hẹn giờ"))
            .accessibilityLabel(L10n.t("Bắt đầu hẹn giờ"))

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
                Button {
                    NotchSurfaceController.shared.resumeTimer()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Tiếp tục"))
                .accessibilityLabel(L10n.t("Tiếp tục"))
            } else {
                Button {
                    NotchSurfaceController.shared.pauseTimer()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .help(L10n.t("Tạm dừng"))
                .accessibilityLabel(L10n.t("Tạm dừng"))
            }

            roundButton(systemName: "plus", help: L10n.t("Thêm 5 phút")) {
                NotchSurfaceController.shared.extendTimer(byMinutes: LiveActivity.timerStepMinutes)
            }

            roundButton(systemName: "xmark", help: L10n.t("Dừng hẹn giờ"), small: true) {
                NotchSurfaceController.shared.cancelTimer()
            }
        }
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
