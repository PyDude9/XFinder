import SwiftUI
import AppKit

/// P7b — a pending permission's summary, rewritten for a crew's own `xfinder-crew send` command: "→ to: text"
/// reads as what the member is about to tell a crewmate, instead of the raw shell line. nil keeps the caller's
/// own fallback (the raw summary / tool name).
private func crewSendSummary(_ p: AgentSession.PendingPermission) -> String? {
    guard p.toolName == "Bash", let sum = p.summary, let (to, text) = CrewRules.describeSend(command: sum) else { return nil }
    return "→ \(to): \(text)"
}

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

    /// P7a — the windowless session named by `model.windowlessConversation`, when it is still in the list.
    private var windowlessSession: AgentSession? {
        guard let id = model.windowlessConversation else { return nil }
        return model.agents.first { $0.listID == id }
    }

    /// P7b — the crew named by `model.crewBoard`, when it still exists.
    private var openCrew: CrewManager.Crew? {
        guard let id = model.crewBoard else { return nil }
        return CrewManager.shared.crews.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: Self.m.agentsHeaderGap)
            if model.newWindowlessOpen {
                NewWindowlessComposer(model: model)
            } else if let crew = openCrew {
                CrewBoardView(crew: crew, model: model)
            } else if let session = windowlessSession {
                WindowlessConversationView(session: session, model: model)
            } else {
                rows
            }
            if let session = composingSession {
                AgentReplyComposeBar(session: session, model: model)
                    .frame(height: Self.composeBarHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header: session count (+ "needing you") left, a compact usage readout right, "+" new windowless session

    private var header: some View {
        HStack(alignment: .center, spacing: XFinderTokens.Space.tight) {
            Text(sessionCountText)
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            if model.agentsNeedingYou > 0 {
                // number last, so one string reads right for any count ("1 need you" was the old English).
                Text(" · \(L10n.t("Chờ bạn: "))\(model.agentsNeedingYou)")          // the separator is a glyph, not a word
                    .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                    .lineLimit(1)
            }
            Spacer(minLength: XFinderTokens.Space.tight)
            if let usage = usageReadout {
                Text(usage)
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.6))
                    .lineLimit(1).truncationMode(.tail).monospacedDigit()
            }
            // P7a: a new windowless session, hosted by XFinder itself (no terminal).
            Button { NotchSurfaceController.shared.beginNewWindowless() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.6))
            .help(L10n.t("Phiên mới không cửa sổ"))
            .accessibilityLabel(L10n.t("Phiên mới không cửa sổ"))
        }
        .frame(height: Self.m.agentsHeaderHeight)
    }

    private var sessionCountText: String {
        "\(L10n.t("Phiên: "))\(model.agents.count)"      // number last: one string reads right for 1 and for 5
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

    /// P7b — crews above the plain rows (contract §1): a session belonging to a crew gets ONE `CrewRow` for the
    /// whole crew instead of its own `AgentRow`.
    private var crews: [CrewManager.Crew] { CrewManager.shared.crews }

    @ViewBuilder private var rows: some View {
        let ungrouped = model.agents.filter { CrewManager.shared.membership(of: $0.id) == nil }
        if crews.isEmpty && ungrouped.isEmpty {
            emptyState
        } else {
            let visible = Array(ungrouped.prefix(max(0, 6 - crews.count)))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Self.m.agentRowGap) {
                    ForEach(crews) { crew in
                        CrewRow(crew: crew, agents: model.agents)
                    }
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
            if let reason = AgentSessionRules.emptyReasonKey(enabled: model.agentsEnabled, hookInstalled: model.agentHookInstalled,
                                                              openCodeOn: model.openCodeOn, openCodeMissing: model.openCodeMissing) {
                VStack(spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t(reason))
                        .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    Button(L10n.t("Mở cài đặt")) { NotchSurfaceController.shared.openAgentSettings() }
                        .buttonStyle(NotchPillButtonStyle(primary: false))
                        .accessibilityLabel(L10n.t("Mở cài đặt"))
                }
            } else {
                Text(L10n.t("Chưa có phiên agent nào."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                if !model.recentAgents.isEmpty { recentList }
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
                    AgentBrandTile(kind: e.agent, size: 12)          // P8: Notch Crew's recent list leads with the agent tile
                    Text(e.displayName).font(XFinderTokens.Font.caption).foregroundColor(.white)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(minWidth: 0, alignment: .leading).layoutPriority(-1)   // a long folder name gives way first
                    Text(e.agent.displayName).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.45))
                        .lineLimit(1).fixedSize()
                    Text(NotchClipCardView.ageLabel(e.updated, now: Date()))
                        .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.45)).monospacedDigit()
                    Spacer(minLength: 4)
                    // P7a: reopen a Claude Code conversation windowless, in its own folder — icon-only so the
                    // row (already tight with a long folder name) does not overflow.
                    if e.agent == .claude, e.cwd != nil {
                        Button { NotchSurfaceController.shared.resumeWindowless(e) } label: {
                            Image(systemName: "play.rectangle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.6))
                        .help(L10n.t("Mở lại không cửa sổ"))
                        .accessibilityLabel(L10n.t("Mở lại không cửa sổ"))
                    }
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
            // P8 (Notch Crew's row, owner's screenshot 2026-10-14): a status mark, then where it runs (the terminal's
            // own icon) › which agent (its tile), then the name. The activity grid replaces the dot while it works.
            statusMark
            if let icon = terminalIcon {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    .help(session.terminal.termProgram ?? "")
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35)).accessibilityHidden(true)
            }
            AgentBrandTile(kind: session.agent, size: 14)
            Text(session.displayName)
                .font(XFinderTokens.Font.row).foregroundColor(.white).lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 0, alignment: .leading).layoutPriority(-1)       // OpenCode titles can be long
            // P7a: a session XFinder itself is running, with no terminal — a small glyph says so. Once the process has
            // ended the wording must not say XFinder is still running it (review).
            if session.terminal.windowless {
                if session.hostedByXFinder {
                    Image(systemName: "rectangle.dashed")
                        .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.45))
                        .help(L10n.t("Phiên không cửa sổ — XFinder đang chạy nó"))
                        .accessibilityLabel(L10n.t("Phiên không cửa sổ — XFinder đang chạy nó"))
                } else {
                    Image(systemName: "rectangle.dashed")
                        .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.3))
                        .help(L10n.t("Phiên không cửa sổ — đã dừng"))
                        .accessibilityLabel(L10n.t("Phiên không cửa sổ — đã dừng"))
                }
            }
            statusCapsule
            Text(NotchClipCardView.ageLabel(session.updatedAt, now: Date()))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .lineLimit(1).monospacedDigit()
            Spacer(minLength: 2)
            // P7a: a hosted session's own conversation — this is where a reply actually goes.
            if WindowlessSessionManager.shared.records[session.id] != nil {
                Button {
                    NotchSurfaceController.shared.openConversation(session)
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Xem hội thoại"))
                .accessibilityLabel(L10n.t("Xem hội thoại"))
            }
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
            if let crewSend = crewSendSummary(p) {
                Text(crewSend).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.85))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            } else {
                Text(p.toolName).font(XFinderTokens.Font.caption).bold().foregroundColor(.white).lineLimit(1)
                if let sum = p.summary {
                    Text(sum).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
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

    /// P7a: for a hosted session the record's last agent line is more useful than the last-tool name — first
    /// line only, so a multi-line answer does not push the row taller.
    private var secondaryText: String {
        if let record = WindowlessSessionManager.shared.records[session.id],
           let text = record.lastAgentText?.split(separator: "\n", maxSplits: 1).first {
            return String(text)
        }
        return session.lastTool ?? statusText
    }

    private var statusText: String {
        if case .running(let tool) = session.status, let tool {
            return L10n.t(AgentSessionRules.statusKey(session.status)) + tool
        }
        return L10n.t(AgentSessionRules.statusKey(session.status))
    }

    /// The terminal (or app) the session runs in — kitty, Terminal, the Claude desktop app — as its own icon. Not for
    /// a windowless session (XFinder runs it) and not when no bundle id was recorded (OpenCode via its API).
    private var terminalIcon: NSImage? {
        guard !session.terminal.windowless else { return nil }
        return ClipboardAppIcon.icon(forBundleID: session.terminal.bundleID)
    }

    @ViewBuilder private var statusMark: some View {
        let a = AgentSessionRules.activity(of: session)
        if a == .thinking || a == .working || a == .waiting {
            AgentActivityGrid(tint: accent, waiting: a == .waiting, cell: 2.4, gap: 1)
                .frame(width: 10, height: 10)
        } else {
            Circle().fill(tint).frame(width: 8, height: 8)
        }
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

/// P7b — one row per crew, shown above the plain `AgentRow`s (contract §1). Tapping the row opens the crew's
/// board; the row never shows its members as separate `AgentRow`s.
private struct CrewRow: View {
    let crew: CrewManager.Crew
    let agents: [AgentSession]

    private static let m = NotchSurfaceLayout.Metrics.standard

    private var waitingForYou: Bool {
        crew.members.values.contains { sid in
            agents.first { $0.id.lowercased() == sid.lowercased() }.map { if case .waitingForPermission = $0.status { true } else { false } } ?? false
        }
    }

    var body: some View {
        Button {
            NotchSurfaceController.shared.openCrew(crew.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                line1
                line2
            }
            .padding(.horizontal, 8)
            .frame(height: Self.m.agentRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private var line1: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "person.3")
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
            Text(L10n.t(crew.template.titleKey))
                .font(XFinderTokens.Font.row).foregroundColor(.white).lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 0, alignment: .leading).layoutPriority(-1)
            Text((crew.folder as NSString).lastPathComponent)
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.45))
                .lineLimit(1).truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: 90, alignment: .leading)
            Spacer(minLength: 2)
            statusCapsule
            Text("\(crew.relay.relays)/\(crew.relay.cap)")
                .font(XFinderTokens.Font.mono).monospacedDigit()
                .foregroundColor(.white.opacity(0.5))
        }
    }

    @ViewBuilder private var line2: some View {
        if crew.relay.pause == .capReached {
            Text(L10n.t(CrewRules.boardKindKey(.capped)))
                .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                .lineLimit(1).truncationMode(.tail)
        } else {
            Text(crew.template.roles.map(\.name).joined(separator: " · "))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private var statusCapsule: some View {
        let (text, color): (String, Color) = {
            if crew.stopped { return (L10n.t("Đã dừng"), .white) }
            if waitingForYou { return (L10n.t("Chờ bạn duyệt"), .orange) }
            if crew.relay.pause != nil { return (L10n.t("Tạm dừng"), .orange) }
            return (L10n.t("Đang chạy"), .white)
        }()
        return Text(text)
            .font(XFinderTokens.Font.caption).foregroundColor(color.opacity(color == .white ? 0.75 : 1))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// P7b — a crew's board: header (back, title, status, relays, cost, controls), member chips with a live status
/// dot (tap to open that member's own conversation), the one pending permission among the members if any, and
/// the relay's message board.
private struct CrewBoardView: View {
    let crew: CrewManager.Crew
    var model: NotchSurfaceModel

    private static let m = NotchSurfaceLayout.Metrics.standard

    private func session(for role: String) -> AgentSession? {
        guard let sid = crew.members[role] else { return nil }
        return model.agents.first { $0.id.lowercased() == sid.lowercased() }
    }

    /// At most one member can be waiting for permission at a time in practice (the relay frees a role as soon
    /// as its turn ends), but the board shows whichever comes first if more than one ever is.
    private var waitingMember: (role: String, session: AgentSession, p: AgentSession.PendingPermission)? {
        for role in crew.template.roles.map(\.name) {
            if let s = session(for: role), case .waitingForPermission(let p) = s.status { return (role, s, p) }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            header
            membersStrip
            if let w = waitingMember { permissionLine(w.role, w.p, w.session) }
            board
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Button { NotchSurfaceController.shared.closeCrew() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.7))
            .help(L10n.t("Quay lại danh sách"))
            .accessibilityLabel(L10n.t("Quay lại danh sách"))
            Text(L10n.t(crew.template.titleKey))
                .font(XFinderTokens.Font.row).foregroundColor(.white)
                .lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 0, alignment: .leading).layoutPriority(-1)
            statusCapsule
            Text("\(crew.relay.relays)/\(crew.relay.cap)")
                .font(XFinderTokens.Font.mono).monospacedDigit()
                .foregroundColor(.white.opacity(0.5))
            if let cost = CrewManager.shared.costUSD(crew) {
                Text("≈ $" + String(format: "%.2f", cost))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1).fixedSize()
                    .help(L10n.t("Ước tính của Claude Code, không phải hoá đơn"))
            }
            Spacer(minLength: 2)
            controls
        }
    }

    private var statusCapsule: some View {
        let waiting = waitingMember != nil
        let (text, isAccent): (String, Bool) = {
            if crew.stopped { return (L10n.t("Đã dừng"), false) }
            if waiting { return (L10n.t("Chờ bạn duyệt"), true) }
            if crew.relay.pause != nil { return (L10n.t("Tạm dừng"), true) }
            return (L10n.t("Đang chạy"), false)
        }()
        return Text(text)
            .font(XFinderTokens.Font.caption).foregroundColor(isAccent ? .orange : .white.opacity(0.75))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .fixedSize()
    }

    @ViewBuilder private var controls: some View {
        if !crew.stopped {
            if crew.relay.pause == nil {
                Button { CrewManager.shared.pause(crew.id) } label: { Image(systemName: "pause.circle") }
                    .buttonStyle(.plain).foregroundColor(.white.opacity(0.6))
                    .help(L10n.t("Tạm dừng crew")).accessibilityLabel(L10n.t("Tạm dừng crew"))
            } else {
                Button { CrewManager.shared.resume(crew.id) } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.plain).foregroundColor(.white.opacity(0.6))
                    .help(L10n.t("Cho crew chạy tiếp")).accessibilityLabel(L10n.t("Cho crew chạy tiếp"))
            }
            Button { CrewManager.shared.stop(crew.id) } label: { Image(systemName: "xmark.octagon") }
                .buttonStyle(.plain).foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Dừng crew")).accessibilityLabel(L10n.t("Dừng crew"))
        } else {
            Button {
                NotchSurfaceController.shared.closeCrew()
                CrewManager.shared.forget(crew.id)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Xoá khỏi danh sách")).accessibilityLabel(L10n.t("Xoá khỏi danh sách"))
        }
    }

    private var membersStrip: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            ForEach(crew.template.roles, id: \.name) { role in
                memberChip(role.name)
            }
            Spacer(minLength: 0)
        }
    }

    private func memberChip(_ role: String) -> some View {
        let s = session(for: role)
        let dot: Color = {
            guard let s else { return .white.opacity(0.3) }
            switch s.status {
            case .running: return .accentColor
            case .waitingForInput: return .yellow
            case .waitingForPermission: return .orange
            case .ended: return .white.opacity(0.3)
            }
        }()
        return Button {
            guard let s else { return }
            NotchSurfaceController.shared.closeCrew()
            NotchSurfaceController.shared.openConversation(s)
        } label: {
            HStack(spacing: 4) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(role).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.8)).lineLimit(1)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(s == nil)
    }

    private func permissionLine(_ role: String, _ p: AgentSession.PendingPermission, _ s: AgentSession) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Text(role).font(XFinderTokens.Font.caption).bold().foregroundColor(.white).lineLimit(1)
            if let crewSend = crewSendSummary(p) {
                Text(crewSend).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            } else if let sum = p.summary {
                Text(sum).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            } else {
                Text(p.toolName).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            Button(L10n.t("Từ chối")) {
                NotchSurfaceController.shared.answerAgent(p, of: s, allow: false)
            }
            .buttonStyle(NotchPillButtonStyle(primary: false))
            Button(L10n.t("Cho phép")) {
                NotchSurfaceController.shared.answerAgent(p, of: s, allow: true)
            }
            .buttonStyle(NotchPillButtonStyle(primary: true))
        }
    }

    @ViewBuilder private var board: some View {
        if crew.relay.board.isEmpty {
            Text(L10n.t("Chưa có tin nào giữa các thành viên."))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(crew.relay.board) { entry in
                            boardRow(entry).id(entry.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onChange(of: crew.relay.board) { if let last = crew.relay.board.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onAppear { if let last = crew.relay.board.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder private func boardRow(_ entry: CrewRules.BoardEntry) -> some View {
        switch entry.kind {
        case .message:
            Text("\(entry.from ?? "") \(L10n.t(CrewRules.boardKindKey(.message))) \(entry.to ?? ""): \(entry.text)")
                .font(XFinderTokens.Font.caption).foregroundColor(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .reply:
            Text("\(entry.from ?? "") \(L10n.t(CrewRules.boardKindKey(.reply))) \(entry.to ?? ""): \(entry.text)")
                .font(XFinderTokens.Font.caption).foregroundColor(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed:
            Text(L10n.t(CrewRules.boardKindKey(.failed)) + (entry.to.map { " (\($0))" } ?? ""))
                .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paused, .resumed, .capped, .stopped:
            Text(L10n.t(CrewRules.boardKindKey(entry.kind)))
                .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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

/// P7a — "+" on the Agents page: pick a folder, optionally type the first message, Start. Replaces the row list
/// while open (the page's frame is fixed; this view fits the same budget the rows use).
private struct NewWindowlessComposer: View {
    var model: NotchSurfaceModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            folderRow
            TextField("", text: Bindable(model).newWindowlessText,
                      prompt: Text(L10n.t("Việc đầu tiên cho Claude Code (không bắt buộc)…")).foregroundColor(.white.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.white)
                .focused($fieldFocused)
                .onSubmit { NotchSurfaceController.shared.startNewWindowless() }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.white.opacity(0.08)))
            HStack(spacing: XFinderTokens.Space.tight) {
                Button(L10n.t("Bắt đầu")) { NotchSurfaceController.shared.startNewWindowless() }
                    .buttonStyle(NotchPillButtonStyle(primary: true))
                    .disabled(model.newWindowlessFolder == nil || model.windowlessStarting)
                Button(L10n.t("Hủy")) { NotchSurfaceController.shared.cancelNewWindowless() }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                Spacer(minLength: 2)
            }
            if let notice = model.windowlessNotice {
                HStack(spacing: 4) {
                    Text(L10n.t(notice))
                        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                        .lineLimit(1).truncationMode(.tail)
                    if let detail = model.windowlessNoticeDetail, !detail.isEmpty {
                        // The tool's own words — not translated.
                        Text(" · \(detail)")
                            .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            } else {
                Text(L10n.t("Mỗi tin là một lượt dùng gói Claude của bạn."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.newWindowlessFocus) { fieldFocused = true }
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder private var folderRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Text(L10n.t("Thư mục"))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.6))
            if model.newWindowlessFolders.isEmpty {
                Text(L10n.t("Chưa có thư mục nào — chọn thư mục ở trang Agent AI."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, alignment: .leading).layoutPriority(-1)
                Button(L10n.t("Mở cài đặt")) { NotchSurfaceController.shared.openAgentSettings() }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
            } else {
                Menu {
                    ForEach(model.newWindowlessFolders, id: \.self) { path in
                        Button {
                            model.newWindowlessFolder = path
                        } label: {
                            Text((path as NSString).lastPathComponent)
                        }
                        .help(path)
                    }
                } label: {
                    Text(model.newWindowlessFolder.map { ($0 as NSString).lastPathComponent } ?? L10n.t("Chọn thư mục"))
                        .font(XFinderTokens.Font.row).foregroundColor(.white)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(minWidth: 0, maxWidth: 160, alignment: .leading)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help(model.newWindowlessFolder ?? "")
            }
            Spacer(minLength: 0)
        }
    }
}

/// P7a — the open conversation of a hosted session: header (back, name, phase, actions), the transcript,
/// and either a "Nhắn" button or, once the process has ended, a way to reopen it in a terminal.
private struct WindowlessConversationView: View {
    let session: AgentSession
    var model: NotchSurfaceModel

    private var record: WindowlessRules.Record? { WindowlessSessionManager.shared.records[session.id] }
    private var isComposingThisSession: Bool { model.agentReplyTarget == session.listID }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            conversationHeader
            transcript
            if !isComposingThisSession { footer }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var conversationHeader: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Button { NotchSurfaceController.shared.closeConversation() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.7))
            .help(L10n.t("Quay lại danh sách"))
            .accessibilityLabel(L10n.t("Quay lại danh sách"))
            Text(session.displayName)
                .font(XFinderTokens.Font.row).foregroundColor(.white)
                .lineLimit(1).truncationMode(.middle)
                .frame(minWidth: 0, alignment: .leading).layoutPriority(-1)
            if case .waitingForPermission = session.status {
                Text(L10n.t("Chờ bạn duyệt"))
                    .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .fixedSize()
            } else if let record {
                Text(L10n.t(WindowlessRules.phaseKey(record.phase)))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .fixedSize()
            }
            Spacer(minLength: 2)
            if case .working = record?.phase {
                Button { NotchSurfaceController.shared.interruptWindowless(session) } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Ngắt lượt"))
                .accessibilityLabel(L10n.t("Ngắt lượt"))
            }
            if session.status != .ended {
                Button { NotchSurfaceController.shared.stopWindowless(session) } label: {
                    Image(systemName: "xmark.octagon")
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Dừng phiên"))
                .accessibilityLabel(L10n.t("Dừng phiên"))
            } else {
                Button { NotchSurfaceController.shared.forgetWindowless(session) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .help(L10n.t("Xoá khỏi danh sách"))
                .accessibilityLabel(L10n.t("Xoá khỏi danh sách"))
            }
        }
    }

    @ViewBuilder private var transcript: some View {
        let entries = record?.transcript ?? []
        if entries.isEmpty {
            Text(L10n.t("Chưa có tin nào — gửi việc đầu tiên."))
                .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { entry in
                            transcriptRow(entry).id(entry.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onChange(of: entries) { if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onAppear { if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder private func transcriptRow(_ entry: WindowlessRules.Entry) -> some View {
        switch entry.role {
        case .person:
            HStack {
                Spacer(minLength: 24)
                Text(entry.text)
                    .font(XFinderTokens.Font.caption).foregroundColor(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.white.opacity(0.14)))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .agent:
            Text(entry.text)
                .font(XFinderTokens.Font.caption).foregroundColor(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .note:
            Text(entry.text)
                .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var footer: some View {
        if case .waitingForPermission(let p) = session.status {
            // Review: a pending permission must be answerable right here — the row's card is not on screen.
            HStack(spacing: XFinderTokens.Space.tight) {
                if let crewSend = crewSendSummary(p) {
                    Text(crewSend).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.85))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(p.toolName).font(XFinderTokens.Font.caption).bold().foregroundColor(.white).lineLimit(1)
                    if let sum = p.summary {
                        Text(sum).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.7))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                Button(L10n.t("Từ chối")) { NotchSurfaceController.shared.answerAgent(p, of: session, allow: false) }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                Button(L10n.t("Cho phép")) { NotchSurfaceController.shared.answerAgent(p, of: session, allow: true) }
                    .buttonStyle(NotchPillButtonStyle(primary: true))
            }
        } else if session.status != .ended {
            Button(L10n.t("Nhắn")) { NotchSurfaceController.shared.beginAgentReply(session) }
                .buttonStyle(NotchPillButtonStyle(primary: true))
        } else {
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Phiên đã dừng — hội thoại vẫn lưu trong Claude Code."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.tail)
                Button(L10n.t("Sao chép lệnh mở lại")) {
                    let entry = AgentRecent.Entry(agent: .claude, sessionID: session.id, cwd: session.cwd,
                                                  updated: session.updatedAt, title: nil)
                    NotchSurfaceController.shared.copyResumeCommand(entry)
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
            }
        }
    }
}

// MARK: - P8 — agent glyphs (OneNotch / Notch Crew, measured 2026-10-14)

/// The agent's own tile: a coloured rounded square with its glyph (`AgentKind.brand`). Notch Crew draws one per row
/// ("kitty › [OpenCode tile] name"); OneNotch keys each provider to a symbol and a tint. XFinder's tiles are SF Symbols.
struct AgentBrandTile: View {
    let kind: AgentKind
    var size: CGFloat = 14

    var body: some View {
        let b = kind.brand
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(red: b.tile.0, green: b.tile.1, blue: b.tile.2))
            .overlay(
                Image(systemName: b.glyph)
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundColor(b.glyphIsDark ? Color.black.opacity(0.85) : .white)
            )
            .frame(width: size, height: size)
            .help(kind.displayName)
            .accessibilityLabel(kind.displayName)
    }
}

/// A 3×3 dot grid. Running: one lit dot circles the ring with a short fading trail (OneNotch's right wing while an
/// agent works — owner's screenshot 2026-10-14). Waiting for the person: the whole ring breathes in orange.
///
/// Drawn by Core Animation, not SwiftUI: the first version used `TimelineView(.periodic)` at ~8 Hz and every tick
/// re-laid out the WHOLE notch hosting view (`NSWindow layoutIfNeeded` → `_layoutViewTree`) — measured 6.3 s of CPU
/// per 30 s (21 %). Here nine layers carry repeating `CAKeyframeAnimation`s that the render server runs on its own,
/// so the app does no work per frame.
struct AgentActivityGrid: NSViewRepresentable {
    var tint: Color
    var waiting: Bool
    var cell: CGFloat = 3.6
    var gap: CGFloat = 1.4

    func makeNSView(context: Context) -> GridView { GridView() }

    func updateNSView(_ v: GridView, context: Context) {
        v.configure(tint: NSColor(tint), waiting: waiting, cell: cell, gap: gap)
    }

    final class GridView: NSView {
        private var cells: [CALayer] = []
        private var signature = ""
        /// The ring around the centre, clockwise from the top-left (index = row * 3 + column, row 0 at the TOP).
        private static let ring = [0, 1, 2, 5, 8, 7, 6, 3]
        private static let step: CFTimeInterval = 0.12

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for _ in 0..<9 { let l = CALayer(); layer?.addSublayer(l); cells.append(l) }
        }
        required init?(coder: NSCoder) { nil }
        override var isFlipped: Bool { true }
        override var intrinsicContentSize: NSSize { .init(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

        private var tint: NSColor = .white
        private var waiting = false
        private var cell: CGFloat = 3.6
        private var gap: CGFloat = 1.4
        private var laidOutFor: CGSize = .zero

        func configure(tint: NSColor, waiting: Bool, cell: CGFloat, gap: CGFloat) {
            let sig = "\(tint)|\(waiting)|\(cell)|\(gap)"
            guard sig != signature else { return }      // same look ⇒ leave the running animations alone
            signature = sig
            self.tint = tint; self.waiting = waiting; self.cell = cell; self.gap = gap
            rebuild()
        }

        override func layout() {
            super.layout()
            guard bounds.size != laidOutFor, !signature.isEmpty else { return }
            rebuild()       // new size: re-centre the cells (animations restart, once)
        }

        private func rebuild() {
            laidOutFor = bounds.size
            let side = cell * 3 + gap * 2
            let ox = (bounds.width - side) / 2, oy = (bounds.height - side) / 2
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for (i, l) in cells.enumerated() {
                let r = CGFloat(i / 3), c = CGFloat(i % 3)
                l.frame = CGRect(x: ox + c * (cell + gap), y: oy + r * (cell + gap), width: cell, height: cell)
                l.cornerRadius = cell * 0.3
                l.removeAllAnimations()
                l.backgroundColor = (waiting ? NSColor.systemOrange : tint).cgColor
                if i == 4 { l.opacity = waiting ? 0.15 : 0.12; continue }
                if waiting {
                    l.opacity = 1
                    let a = CABasicAnimation(keyPath: "opacity")
                    a.fromValue = 1.0; a.toValue = 0.4; a.duration = 0.5
                    a.autoreverses = true; a.repeatCount = .infinity
                    l.add(a, forKey: "breathe")
                } else if let pos = Self.ring.firstIndex(of: i) {
                    let n = Self.ring.count
                    l.opacity = 0.12
                    let a = CAKeyframeAnimation(keyPath: "opacity")
                    // 8 discrete steps per loop; this cell is lit at its own step, then fades over the next two.
                    a.values = (0..<n).map { step -> Float in
                        switch (step - pos + n) % n { case 0: return 1; case 1: return 0.55; case 2: return 0.25; default: return 0.12 }
                    }
                    a.keyTimes = (0..<n).map { NSNumber(value: Double($0) / Double(n)) }
                    a.calculationMode = .discrete
                    a.duration = Self.step * Double(n)
                    a.repeatCount = .infinity
                    l.add(a, forKey: "chase")
                }
            }
            CATransaction.commit()
        }
    }
}

/// The left wing's agent glyph: up to two agent tiles (most urgent in front), a small mark for the summary activity
/// (orange dot = waiting on you, green check = finished, your turn) and a count when more sessions are live than tiles.
struct AgentWingGlyph: View {
    let summary: AgentSessionRules.WingSummary

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(summary.agents.enumerated().reversed()), id: \.offset) { i, kind in
                AgentBrandTile(kind: kind, size: 14)
                    .offset(x: CGFloat(i) * 6)
                    .opacity(i == 0 ? 1 : 0.8)
            }
        }
        .frame(width: 20, height: 22, alignment: .leading)
        .overlay(alignment: .topTrailing) { mark.offset(x: 2, y: 2) }
        .overlay(alignment: .bottomTrailing) {
            if summary.live > summary.agents.count {
                Text("\(summary.live)").font(.system(size: 8, weight: .bold)).monospacedDigit()
                    .foregroundColor(.white).padding(.horizontal, 2)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .offset(x: 3, y: -1)
            }
        }
    }

    @ViewBuilder private var mark: some View {
        switch summary.activity {
        case .waiting: Circle().fill(Color.orange).frame(width: 6, height: 6)
        case .yourTurn:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 7, weight: .bold)).foregroundColor(.green)
        default: EmptyView()
        }
    }

    /// "Claude Code, OpenCode đang chờ bạn" — Notch Crew names who is waiting; the count follows when more are live.
    static func label(_ s: AgentSessionRules.WingSummary) -> String {
        s.agents.map(\.displayName).joined(separator: ", ") + L10n.t(AgentSessionRules.wingLabelKey(s.activity))
    }
}
