import SwiftUI

/// P2 — Agents page restyle, in OneNotch's grammar (dark rows, compact usage readout at the top-right of the
/// header) with Notch Crew's agent behaviour (an inline amber-tinted permission card with Allow/Deny, a live
/// elapsed badge while a request waits). Ports the working behaviour of `agentsPage` / `agentUsageStrip` /
/// `agentSessions` / `agentRow` / `agentStatusText` / `agentTint` in `NotchSurfaceView.swift` (read-only
/// reference; the main session deletes that old code after integration) — nothing here changes what data is
/// shown, only how.
///
/// Job sentence: "I am at the notch because a coding-agent session (Claude Code, Codex) needs me right now — show me which one, let
/// me answer it without leaving, and tell me when it is just working so I don't have to watch it."
///
/// P6 adds "Nhắn phiên": a small "Nhắn" button on a live row opens a compose bar pinned at the bottom of this
/// page (the page's own frame is fixed — `wideDrop` — so the bar takes a fixed slice and the rows' ScrollView
/// shrinks around it; the page never grows). The compose bar, the queued/status line-2 state and the send
/// button all read `AgentTalk`/`AgentTalkSender` through the shared model fields only — nothing here decides
/// routing or delivery itself.
struct NotchAgentsPage: View {
    var model: NotchSurfaceModel
    @Environment(\.notchAccent) private var accent

    private static let m = NotchSurfaceLayout.Metrics.standard
    /// Fixed height of the compose bar + its caption line, taken out of the rows' ScrollView so the page
    /// never grows (spec §3: "shrink the rows' ScrollView, do not grow the page").
    private static let composeBarHeight: CGFloat = 54

    private var composingSession: AgentSession? {
        guard let id = model.agentReplyTarget else { return nil }
        return model.agents.first { $0.listID == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: Self.m.agentsHeaderGap)
            rows
            if let session = composingSession {
                AgentReplyComposeBar(session: session, model: model)
                    .frame(height: Self.composeBarHeight)
            }
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
                    ForEach(visible, id: \.listID) { s in
                        AgentRow(session: s, accent: accent, model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var emptyState: some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            if model.recentAgents.isEmpty {        // the recent list needs the height (Agents body: 150 pt)
                Image(systemName: "terminal").font(XFinderTokens.Font.pageIcon).opacity(0.5)
            }
            if model.agentHookInstalled || !model.recentAgents.isEmpty {
                Text(L10n.t("Chưa có phiên agent nào."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                if !model.recentAgents.isEmpty { recentList }
            } else {
                VStack(spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t("Chưa cài hook — mở trang Agent AI để cài."))
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

    /// P5c — up to three terminal sessions that are no longer live; one button copies the command that reopens one.
    private var recentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Gần đây")).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
            ForEach(model.recentAgents.prefix(3)) { e in
                HStack(spacing: XFinderTokens.Space.tight) {
                    Text(e.displayName).font(XFinderTokens.Font.caption).foregroundColor(.white)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(minWidth: 0, alignment: .leading).layoutPriority(-1)   // a long folder name gives way first
                    Text(e.agent.displayName).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.45))
                        .lineLimit(1).fixedSize()
                    Text(NotchClipCardView.ageLabel(e.updated, now: Date()))
                        .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.45)).monospacedDigit()
                    Spacer(minLength: 4)
                    Button(L10n.t("Sao chép lệnh")) { NotchSurfaceController.shared.copyResumeCommand(e) }
                        .buttonStyle(NotchPillButtonStyle(primary: false))
                        .help(e.resumeCommand)
                }
            }
        }
        .padding(.horizontal, XFinderTokens.Space.inline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One session row: status dot + name + status capsule + age + optional "open terminal" button on line 1;
/// for a pending permission, the tool/summary/elapsed badge/Allow-Deny on line 2 — otherwise the last tool
/// or the status text, dimmed. A row that needs the user gets a subtle fill so it reads as "look here".
private struct AgentRow: View {
    let session: AgentSession
    let accent: Color
    var model: NotchSurfaceModel

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
                .font(XFinderTokens.Font.row).foregroundColor(.white).lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 0, alignment: .leading).layoutPriority(-1)       // OpenCode titles can be long
            // P5: which agent — a product name, identical in both languages.
            Text(session.agent.displayName)
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.45))
                .lineLimit(1).fixedSize()
            statusCapsule
            Text(NotchClipCardView.ageLabel(session.updatedAt, now: Date()))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .lineLimit(1).monospacedDigit()
            Spacer(minLength: 2)
            if session.status != .ended {
                Button {
                    NotchSurfaceController.shared.beginAgentReply(session)
                } label: {
                    Image(systemName: "text.bubble")
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Nhắn phiên này"))
                .accessibilityLabel(L10n.t("Nhắn phiên này"))
            }
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

    /// P6: the permission line always wins (spec §2). Below it, a queued reply beats a send status, which beats
    /// the row's ordinary secondary text — each is "newer info" than the one after it.
    @ViewBuilder private var line2: some View {
        if case .waitingForPermission(let p) = session.status {
            permissionLine(p)
        } else if model.agentReplyQueued.contains(session.listID) {
            queuedLine
        } else if let status = model.agentReplyStatus[session.listID] {
            replyStatusLine(status)
        } else {
            Text(secondaryText)
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private var queuedLine: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "clock").font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
            Text(L10n.t("Tin đang chờ — gửi khi phiên rảnh"))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            Button(L10n.t("Hủy")) {
                NotchSurfaceController.shared.cancelQueuedReply(session)
            }
            .buttonStyle(.plain)
            .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
        }
    }

    private func replyStatusLine(_ status: AgentTalkSender.Status) -> some View {
        HStack(spacing: 4) {
            Text(L10n.t(status.key))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(status.isError ? .orange : .white.opacity(0.5))
                .lineLimit(1).truncationMode(.tail)
            if let detail = status.detail {
                Text(" · \(detail)")                                       // a glyph and the CLI's own words
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(status.isError ? .orange : .white.opacity(0.5))
                    .lineLimit(1).truncationMode(.tail)
            }
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

/// P6 — the reply compose bar, pinned at the bottom of the Agents page while `model.agentReplyTarget` names a
/// still-listed session (spec §3). A leading label names the target, a plain `TextField` takes the text, the
/// send button's title follows the measured route (`AgentTalk.routeLabelKey`), and one caption line below
/// explains what pressing it will actually do — queued, blocked, or copy-and-activate — so the person is never
/// surprised by where their words land.
private struct AgentReplyComposeBar: View {
    let session: AgentSession
    var model: NotchSurfaceModel
    @FocusState private var fieldFocused: Bool

    private var route: AgentTalk.Route { AgentTalk.route(for: session) }
    private var decision: AgentTalk.Decision { AgentTalk.decision(for: session, route: route) }
    private var canSend: Bool { AgentTalk.clean(model.agentReplyText) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().overlay(Color.white.opacity(0.10))
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(session.displayName)
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.6))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: 96, alignment: .leading)
                TextField("", text: Bindable(model).agentReplyText, prompt: Text(L10n.t("Nhắn cho phiên…")).foregroundColor(.white.opacity(0.4)))
                    .textFieldStyle(.plain)
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.white)
                    .focused($fieldFocused)
                    .onSubmit { NotchSurfaceController.shared.sendAgentReply() }
                    .frame(minWidth: 0, maxWidth: .infinity)
                Button(L10n.t(AgentTalk.sendLabelKey(for: session))) {
                    NotchSurfaceController.shared.sendAgentReply()
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
                .disabled(!canSend)
                Button {
                    NotchSurfaceController.shared.endAgentReply()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Hủy"))
                .accessibilityLabel(L10n.t("Hủy"))
            }
            captionLine
        }
        .onChange(of: model.agentReplyFocus) { fieldFocused = true }
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder private var captionLine: some View {
        switch decision {
        case .queue:
            Text(L10n.t("Phiên đang chạy — tin sẽ được gửi khi phiên rảnh."))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .lineLimit(1).truncationMode(.tail)
        case .blocked(let key):
            Text(L10n.t(key))
                .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                .lineLimit(1).truncationMode(.tail)
        case .copyInstead(let key):
            Text(L10n.t(key))
                .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                .lineLimit(1).truncationMode(.tail)
                .help(L10n.t("XFinder không gõ vào hộp thoại: tin được chép và terminal được đưa lên trước."))
        case .sendNow:
            if case .copyAndActivate = route {
                Text(L10n.t("Terminal này chưa gõ được tự động — XFinder chép tin và mở terminal."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }
}
