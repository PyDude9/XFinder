import SwiftUI

/// P2 — "Hạn mức AI" toolbar page. Two tabs over the same `AgentUsageMonitor.shared.snapshot` the controller keeps
/// scanning while this page is open: **Hạn mức** (Claude's real 5h/7d % once the opt-in statusLine is installed and
/// has reported, Codex's own rate-limit windows) and **Token** (what was actually burned — today / 7 days, out +
/// in). Never draws a ring the data does not back: no 0 %-looking ring before a quota exists, no "Hôm nay" built
/// from the 5-hour window, no stale % once a window's reset time has passed.
struct NotchAIUsagePage: View {
    var model: NotchSurfaceModel
    @State private var tab: Tab = .quota
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch
    private static let m = NotchSurfaceLayout.Metrics.standard

    private enum Tab: Equatable { case quota, tokens }

    private var snapshot: AgentUsageMonitor.Snapshot { AgentUsageMonitor.shared.snapshot }
    private var comma: Bool { !L10n.isEnglish }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.m.usageHeaderGap) {
            header
            columns
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            tabSwitch
            Spacer(minLength: XFinderTokens.Space.tight)
            if let at = snapshot.scannedAt {
                Text("\(L10n.t("Cập nhật "))\(Self.timeLabel(at))")
                    .font(XFinderTokens.Font.caption).opacity(0.6).lineLimit(1)
            }
        }
        .frame(height: Self.m.usageHeaderHeight)
    }

    private var tabSwitch: some View {
        HStack(spacing: 2) {
            tabButton(L10n.t("Hạn mức"), selected: tab == .quota) { tab = .quota }
            tabButton(L10n.t("Token"), selected: tab == .tokens) { tab = .tokens }
        }
        .padding(2)
        .background(Capsule().fill(N.capsule))
    }

    private func tabButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(XFinderTokens.Font.caption).fontWeight(.medium)
                .foregroundStyle(selected ? Color.black : N.toolbarIcon)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(selected ? 1 : 0)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Columns

    private var columns: some View {
        HStack(spacing: 0) {
            column(provider: .claude)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                .padding(.vertical, XFinderTokens.Space.tight)
            column(provider: .codex)
        }
        .frame(height: Self.m.usageColumnsHeight)
    }

    private enum Provider { case claude, codex }

    private func column(provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            columnHeader(provider)
            switch (tab, provider) {
            case (.quota, .claude): claudeQuotaBody
            case (.quota, .codex): codexQuotaBody
            case (.tokens, .claude): claudeTokensBody
            case (.tokens, .codex): codexTokensBody
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, XFinderTokens.Space.tight)
    }

    private func columnHeader(_ provider: Provider) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: provider == .claude ? "terminal" : "cpu").font(.system(size: 12)).opacity(0.75)
            Text(provider == .claude ? "Claude Code" : "Codex").font(XFinderTokens.Font.row)
        }
    }

    // MARK: - Quota tab — Claude

    @ViewBuilder private var claudeQuotaBody: some View {
        if let quota = snapshot.claudeQuota {
            HStack(spacing: XFinderTokens.Space.row) {
                quotaRing(label: L10n.t("5 giờ"), window: quota.fiveHour)
                quotaRing(label: L10n.t("7 ngày"), window: quota.sevenDay)
            }
            claudeTokenFallbackLine
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if !snapshot.statusLineInstalled {
                    Text(L10n.t("Chưa đọc % hạn mức Claude.")).font(XFinderTokens.Font.caption).opacity(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.t("Bật trong Cài đặt")) { NotchSurfaceController.shared.openAgentSettings() }
                        .buttonStyle(NotchPillButtonStyle(primary: false))
                        .accessibilityLabel(L10n.t("Bật trong Cài đặt"))
                } else {
                    Text(L10n.t("Chưa nhận được % — Claude Code chỉ gửi nó cho phiên claude trong terminal, tài khoản Pro/Max, sau câu trả lời đầu."))
                        .font(XFinderTokens.Font.caption).opacity(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            claudeTokenFallbackLine
        }
    }

    /// The honest fallback, shown alongside the rings too (not only before the opt-in): Claude Code's statusLine
    /// gives a %, never a token count, so the two facts are complementary, not alternatives.
    @ViewBuilder private var claudeTokenFallbackLine: some View {
        if snapshot.claude7d.messages > 0 {
            Text("\(L10n.t("5 giờ: "))\(AgentUsage.compact(snapshot.claude5h.output, decimalComma: comma))\(L10n.t(" token"))\(L10n.t(" · 7 ngày: "))\(AgentUsage.compact(snapshot.claude7d.output, decimalComma: comma))")
                .font(XFinderTokens.Font.caption).opacity(0.55).lineLimit(1)
        }
    }

    private func quotaRing(label: String, window: ClaudeStatusLine.Window?) -> some View {
        VStack(spacing: 2) {
            if let window, ClaudeStatusLine.isCurrent(window, now: Date()) {
                usageRing(percent: window.usedPercent)
                Text(Self.resetLine(window.resetsAt))
                    .font(XFinderTokens.Font.caption).opacity(0.5).lineLimit(1)
                    .frame(width: 60)
            } else if window != nil {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 16)).opacity(0.4)
                Text(L10n.t("đã qua giờ reset")).font(XFinderTokens.Font.caption).opacity(0.5)
                    .multilineTextAlignment(.center).frame(width: 60)
            } else {
                Color.clear.frame(width: 52, height: 52)
            }
            Text(label).font(XFinderTokens.Font.caption).opacity(0.65)
        }
    }

    // MARK: - Quota tab — Codex

    @ViewBuilder private var codexQuotaBody: some View {
        if let c = snapshot.codex {
            HStack(spacing: XFinderTokens.Space.row) {
                // Codex says how long each window is (window_minutes): label it from that, not from a guess.
                codexRing(label: Self.windowLabel(c.primary?.windowMinutes, fallback: L10n.t("5 giờ")), window: c.primary)
                codexRing(label: Self.windowLabel(c.secondary?.windowMinutes, fallback: L10n.t("tuần")), window: c.secondary)
            }
            Text("\(L10n.t("lúc "))\(Self.timeLabel(c.observedAt))")
                .font(XFinderTokens.Font.caption).opacity(0.5)
        } else {
            Text(L10n.t("Chưa có dữ liệu Codex trên máy này.")).font(XFinderTokens.Font.caption).opacity(0.65)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "5 giờ", "7 ngày", "90 phút" from a window length in minutes; the fallback only when Codex gave no length.
    static func windowLabel(_ minutes: Int?, fallback: String) -> String {
        guard let m = minutes, m > 0 else { return fallback }
        if m % 1440 == 0 { return "\(m / 1440) \(L10n.t("ngày"))" }
        if m % 60 == 0 { return "\(m / 60) \(L10n.t("giờ"))" }
        return "\(m) \(L10n.t("phút"))"
    }

    private func codexRing(label: String, window: AgentUsage.CodexWindow?) -> some View {
        VStack(spacing: 2) {
            if let window, AgentUsage.isCurrent(window, now: Date()) {
                usageRing(percent: window.usedPercent)
                Text(Self.resetLine(window.resetsAt))
                    .font(XFinderTokens.Font.caption).opacity(0.5).lineLimit(1)
                    .frame(width: 60)
            } else if window != nil {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 16)).opacity(0.4)
                Text(L10n.t("đã qua giờ reset — số mới có sau lần dùng Codex kế tiếp"))
                    .font(XFinderTokens.Font.caption).opacity(0.5)
                    .multilineTextAlignment(.center).frame(width: 64)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Color.clear.frame(width: 52, height: 52)
            }
            Text(label).font(XFinderTokens.Font.caption).opacity(0.65)
        }
    }

    // MARK: - Ring (no Gauge, per CLAUDE.md — a Path on a track, like StatBarView)

    private func usageRing(percent: Double) -> some View {
        let clamped = min(100, max(0, percent))
        return ZStack {
            Circle().stroke(N.progressTrack, lineWidth: 4)
            Circle()
                .trim(from: 0, to: clamped / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(clamped.rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .frame(width: 52, height: 52)
    }

    // MARK: - Tokens tab

    @ViewBuilder private var claudeTokensBody: some View {
        if snapshot.claude7d.messages > 0 {
            tokenStat(title: L10n.t("Hôm nay"), totals: snapshot.claudeToday)
            tokenStat(title: L10n.t("7 ngày"), totals: snapshot.claude7d)
        } else {
            Text(L10n.t("Không có hoạt động trong 7 ngày.")).font(XFinderTokens.Font.caption).opacity(0.6)
        }
    }

    @ViewBuilder private var codexTokensBody: some View {
        if snapshot.codex7d.messages > 0 {
            tokenStat(title: L10n.t("Hôm nay"), totals: snapshot.codexToday)
            tokenStat(title: L10n.t("7 ngày"), totals: snapshot.codex7d)
        } else {
            Text(L10n.t("Không có hoạt động trong 7 ngày.")).font(XFinderTokens.Font.caption).opacity(0.6)
        }
    }

    private func tokenStat(title: String, totals: AgentUsage.Totals) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(XFinderTokens.Font.caption).opacity(0.55)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(AgentUsage.compact(totals.output, decimalComma: comma))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                Text(L10n.t(" token ra")).font(XFinderTokens.Font.caption).opacity(0.6)
            }
            Text("\(L10n.t("vào "))\(AgentUsage.compact(totals.input, decimalComma: comma))")
                .font(XFinderTokens.Font.caption).opacity(0.5)
        }
    }

    // MARK: - Pure formatting helpers

    private static func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "Đặt lại sau 4 giờ" / "Đặt lại sau 2 ngày" — a short, rounded duration until reset. nil (no reset time known)
    /// renders nothing rather than guessing.
    private static func resetLine(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "" }
        let seconds = max(0, resetsAt.timeIntervalSinceNow)
        let hours = Int((seconds / 3600).rounded(.up))
        if hours < 1 {
            let minutes = max(1, Int((seconds / 60).rounded(.up)))
            return "\(L10n.t("Đặt lại sau "))\(minutes)\(L10n.t(" phút nữa"))"
        } else if hours < 24 {
            return "\(L10n.t("Đặt lại sau "))\(hours)\(L10n.t(" giờ nữa"))"
        } else {
            let days = Int((Double(hours) / 24).rounded(.up))
            return "\(L10n.t("Đặt lại sau "))\(days)\(L10n.t(" ngày nữa"))"
        }
    }
}
