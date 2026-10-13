import SwiftUI

/// P2 — Agents page restyle, in OneNotch's grammar (dark rows, compact usage readout at the top-right of the
/// header) with Notch Crew's agent behaviour (an inline amber-tinted permission card with Allow/Deny, a live
/// elapsed badge while a request waits). Ports the working behaviour of `agentsPage` / `agentUsageStrip` /
/// `agentSessions` / `agentRow` / `agentStatusText` / `agentTint` in `NotchSurfaceView.swift` (read-only
/// reference; the main session deletes that old code after integration) — nothing here changes what data is
/// shown, only how.
///
/// Job sentence: "I am at the notch because a Claude Code session needs me right now — show me which one, let
/// me answer it without leaving, and tell me when it is just working so I don't have to watch it."
struct NotchAgentsPage: View {
    var model: NotchSurfaceModel
    @Environment(\.notchAccent) private var accent

    private static let m = NotchSurfaceLayout.Metrics.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: Self.m.agentsHeaderGap)
            rows
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header: session count (+ "needing you") left, a compact usage readout right

    private var header: some View {
        HStack(alignment: .center, spacing: XFinderTokens.Space.tight) {
            Text(sessionCountText)
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            if model.agentsNeedingYou > 0 {
                // " · " and " chờ bạn" are both new fragments (joined to the runtime count) — listed in the final message.
                Text(" · \(model.agentsNeedingYou)\(L10n.t(" chờ bạn"))")          // the separator is a glyph, not a word
                    .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                    .lineLimit(1)
            }
            Spacer(minLength: XFinderTokens.Space.tight)
            if let usage = usageReadout {
                Text(usage)
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.6))
                    .lineLimit(1).truncationMode(.tail).monospacedDigit()
            }
        }
        .frame(height: Self.m.agentsHeaderHeight)
    }

    private var sessionCountText: String {
        "\(model.agents.count)\(L10n.t(" phiên"))"
    }

    /// `AgentUsageMonitor.shared.snapshot` is read once per render — no timer of its own, matching the
    /// 60 s-while-open cadence the controller already drives. Only the ONE most relevant figure is shown here;
    /// the full breakdown belongs to the `aiUsage` toolbar page (contract §2), kept in sync, not duplicated.
    private var usageReadout: String? {
        let u = AgentUsageMonitor.shared.snapshot
        // "Claude" and "Claude Code" are proper nouns, identical in both languages (contract: may be plain strings).
        if let five = u.claudeQuota?.fiveHour, ClaudeStatusLine.isCurrent(five, now: Date()) {
            return "Claude\(L10n.t(" · 5 giờ "))\(Int(five.usedPercent.rounded()))%"
        }
        if u.claude5h.messages > 0 {
            let comma = !L10n.isEnglish
            return "Claude Code\(L10n.t(" · 5 giờ: "))\(AgentUsage.compact(u.claude5h.output, decimalComma: comma))\(L10n.t(" token ra"))"
        }
        return nil
    }

    // MARK: - Rows

    @ViewBuilder private var rows: some View {
        if model.agents.isEmpty {
            emptyState
        } else {
            let visible = Array(model.agents.prefix(6))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Self.m.agentRowGap) {
                    ForEach(visible) { s in
                        AgentRow(session: s, accent: accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var emptyState: some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "terminal").font(XFinderTokens.Font.pageIcon).opacity(0.5)
            if model.agentHookInstalled {
                Text(L10n.t("Chưa có phiên Claude Code nào."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t("Chưa cài hook — mở Notch & Khay thả để cài."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    Button(L10n.t("Mở cài đặt")) { NotchSurfaceController.shared.openAgentSettings() }
                        .buttonStyle(NotchPillButtonStyle(primary: false))
                        .accessibilityLabel(L10n.t("Mở cài đặt"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One session row: status dot + name + status capsule + age + optional "open terminal" button on line 1;
/// for a pending permission, the tool/summary/elapsed badge/Allow-Deny on line 2 — otherwise the last tool
/// or the status text, dimmed. A row that needs the user gets a subtle fill so it reads as "look here".
private struct AgentRow: View {
    let session: AgentSession
    let accent: Color

    private static let m = NotchSurfaceLayout.Metrics.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line1
            line2
        }
        .padding(.horizontal, 8)
        .frame(height: Self.m.agentRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(session.needsYou ? Color.white.opacity(0.06) : Color.clear)
        )
    }

    private var line1: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(session.displayName)
                .font(XFinderTokens.Font.row).foregroundColor(.white).lineLimit(1)
            statusCapsule
            Text(NotchClipCardView.ageLabel(session.updatedAt, now: Date()))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .lineLimit(1).monospacedDigit()
            Spacer(minLength: 2)
            if session.terminal.bundleID != nil, session.status != .ended {
                Button {
                    NotchSurfaceController.shared.openAgentTerminal(session)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Mở terminal"))
                .accessibilityLabel(L10n.t("Mở terminal"))
            }
        }
    }

    private var statusCapsule: some View {
        Text(statusText)
            .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.75))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    @ViewBuilder private var line2: some View {
        if case .waitingForPermission(let p) = session.status {
            permissionLine(p)
        } else {
            Text(secondaryText)
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private func permissionLine(_ p: AgentSession.PendingPermission) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Text(p.toolName).font(XFinderTokens.Font.caption).bold().foregroundColor(.white).lineLimit(1)
            if let sum = p.summary {
                Text(sum).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            elapsedBadge(since: p.since)
            Button(L10n.t("Từ chối")) {
                NotchSurfaceController.shared.answerAgent(p, of: session, allow: false)
            }
            .buttonStyle(NotchPillButtonStyle(primary: false))
            Button(L10n.t("Cho phép")) {
                NotchSurfaceController.shared.answerAgent(p, of: session, allow: true)
            }
            .buttonStyle(NotchPillButtonStyle(primary: true))
        }
    }

    /// Wraps ONLY this badge in a 1 Hz timeline, so nothing else on the page re-renders every second.
    private func elapsedBadge(since: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(elapsedLabel(from: since, to: ctx.date))
                .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                .foregroundColor(.orange)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
        }
    }

    private func elapsedLabel(from: Date, to: Date) -> String {
        let secs = max(0, Int(to.timeIntervalSince(from)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m\(secs % 60)s"
    }

    private var secondaryText: String {
        session.lastTool ?? statusText
    }

    private var statusText: String {
        if case .running(let tool) = session.status, let tool {
            return L10n.t(AgentSessionRules.statusKey(session.status)) + tool
        }
        return L10n.t(AgentSessionRules.statusKey(session.status))
    }

    private var tint: Color {
        switch session.status {
        case .running: return accent
        case .waitingForInput: return .yellow
        case .waitingForPermission: return .orange
        case .ended: return .white.opacity(0.3)
        }
    }
}
