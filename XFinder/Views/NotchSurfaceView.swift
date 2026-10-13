import SwiftUI
import AppKit
import QuickLookThumbnailing

/// What the Notch surface shows. Mutated only by `NotchSurfaceController.render()`.
@MainActor
@Observable
final class NotchSurfaceModel {
    var state: NotchSurfaceMachine.State = .collapsed
    var anchor: NotchSurfaceMachine.Anchor = .notch
    var itemCount = 0
    /// Size of the physical notch (height 0 on a screen without one).
    var notchSize = CGSize(width: 185, height: 32)
    /// The hub action that is running or last finished (B2d).
    var task: NotchTask?
    /// A one-line store key shown under the action row (e.g. AirDrop unavailable).
    var notice: String?
    /// N6: the OCR result line, already localised (it carries a number).
    var ocrSummary: String?
    /// The live activity on screen (B4).
    var activity: LiveActivity.Item?
    /// Remaining time of a running countdown ("12:34"), shown in the collapsed badge (B4b).
    var timerText: String?
    /// The clipboard page's own state (B5).
    let clipboard = NotchClipboardModel()
    /// What is playing (B6), as the helper last reported it; nil ⇒ nothing / feature off.
    var nowPlaying: NowPlaying.Snapshot?
    var nowPlayingArtwork: NSImage?
    /// Playhead in seconds, interpolated by the controller's ticker while the page is open.
    var nowPlayingPosition: Double?
    var nowPlayingAppName: String?
    var nowPlayingAppIcon: NSImage?
    var nowPlayingAvailability: NowPlaying.Availability = .off
    /// B7: whether a screen without a notch gets a pill (mirrors the `notch.pillOnPlainScreens` reader).
    var pillOnPlainScreens = true
    /// D1 #44: the pages the hub shows, in order (`notch.pages`); #47: the accent, nil = the app's own.
    var pages: [NotchSurfaceMachine.Page] = NotchPages.defaultOrder
    var accent: Color?
    /// N4: the Glance page — events + timed reminders in a ±5-day window, the access state, the all-day switch.
    var calendarEvents: [GlanceEvent] = []
    var calendarEnabled = false
    var calendarAccess: CalendarGlanceMonitor.Access = .unknown
    var calendarHidesAllDay = false
    /// N3: Claude Code sessions (mirrored from `AgentSessionMonitor`), whether the feature is on, and whether the hook is installed.
    var agents: [AgentSession] = []
    var agentsEnabled = false
    var agentHookInstalled = false
    var agentsNeedingYou: Int { agents.filter(\.needsYou).count }
    /// D0c: true for the first frame of a surface opening at the notch — the shape is drawn at the notch's
    /// own size and the controller flips this on the next run-loop turn, so the hub springs out of the notch.
    var appearFromNotch = false
}

/// D1 #47 — the notch's accent, read by every notch view instead of `Color.accentColor`.
private struct NotchAccentKey: EnvironmentKey { static let defaultValue: Color = .accentColor }
extension EnvironmentValues {
    var notchAccent: Color {
        get { self[NotchAccentKey.self] }
        set { self[NotchAccentKey.self] = newValue }
    }
}

/// Root of the Notch surface window. The window is sized by `NotchSurfaceLayout`; this view draws
/// a black shape of the SAME layout size for the current state and animates between states with
/// `Motion.surface`, so the surface appears to grow out of the notch. Everything is white-on-black
/// on purpose — it must read as part of the notch, not as a floating card.
struct NotchSurfaceView: View {
    var model: NotchSurfaceModel
    @State private var store = DropTrayStore.shared
    @State private var isTargeted = false
    @Environment(\.notchAccent) private var accent

    /// The state's own size — what the content is laid out at (once per state, not once per animation frame).
    private var stateSize: CGSize {
        let notch = CGRect(origin: .zero, size: model.notchSize)
        return NotchSurfaceLayout.size(for: model.state, anchor: model.anchor,
                                       itemCount: model.itemCount, notch: notch,
                                       timerActive: model.timerText != nil,
                                       nowPlayingActive: nowPlayingActive,
                                       pillOnPlainScreens: model.pillOnPlainScreens) ?? .zero
    }

    /// The drawn (animated) size: the notch itself on the first frame of an opening (D0c), else the state's.
    private var size: CGSize {
        model.appearFromNotch ? model.notchSize : stateSize
    }

    /// A screen without a notch: the surface hangs under the menu bar as a free-standing card / pill.
    private var plainScreen: Bool { model.notchSize.height == 0 }

    private var nowPlayingActive: Bool { model.nowPlaying?.hasTrack == true }

    /// At the notch the top edge is flush with the screen (the notch has no top edge); a tray opened
    /// at the pointer is a free-standing card, rounded on all four corners.
    private var atNotch: Bool { model.anchor == .notch }
    /// At the notch — real or virtual (D0c: a plain screen's surface hangs from the top edge too) — the top
    /// edge is flush with the bezel; a tray opened at the pointer is a free-standing card, rounded all round.
    private var shape: NotchShape {
        NotchShape(bottomRadius: bottomRadius, topRadius: atNotch ? 0 : bottomRadius, topFillet: filletNow)
    }

    /// The hub's body without the flares — what strokes and content insets are measured against.
    private var bodyShape: NotchShape {
        NotchShape(bottomRadius: bottomRadius, topRadius: atNotch ? 0 : bottomRadius)
    }

    /// D1: the expanded hub at a notch (real or virtual) flares into the top edge; a pointer tray does not.
    private var filletNow: CGFloat {
        if case .expanded = model.state, atNotch { return NotchSurfaceLayout.Metrics.standard.topFillet }
        return 0
    }

    private var bottomRadius: CGFloat {
        switch model.state {
        case .collapsed: return plainScreen ? NotchSurfaceLayout.Metrics.standard.pillHeight / 2 : 9
        case .peek, .activity: return 14
        case .expanded: return XFinderTokens.Radius.hub
        }
    }

    /// Measured 2026-10-12 with `sample` during an open: 214 of 565 main-thread samples sat in
    /// `-[NSAnimation _runBlocking]` under `NSHostingView.layout` — the hosting view was ANIMATING THE
    /// WINDOW'S FRAME to follow this view's ideal size (`sizingOptions = []` does not stop it), and
    /// AppKit's window animation blocks the main thread, so the SwiftUI spring could not render: the
    /// hub grew in steps and the whole app stalled ~200 ms per open. The root is therefore a
    /// `GeometryReader`, whose ideal size is fixed, so the window (sized by the controller before it is
    /// shown) never moves; only the shape inside animates, and the content is laid out ONCE at the
    /// state's size while the clip grows over it.
    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                // The hairline / drop ring follows the BODY: stroking the flared outline would draw lines where
                // the flare subpaths meet the body.
                bodyShape.strokeBorder(isTargeted ? accent : Color.white.opacity(0.12), lineWidth: isTargeted ? 2 : 1)
                    .padding(.horizontal, filletNow)
                content
                    .padding(.top, (atNotch && !isClipboardHub) ? model.notchSize.height : 0)   // D0: that hub USES the notch band
                    .frame(width: stateSize.width, height: stateSize.height, alignment: .top)
                    .opacity(model.appearFromNotch ? 0 : 1)                                     // fades in as the shape grows
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            // N1: the window is larger than the shape (one fixed frame for every state), so the drop target is
            // the DRAWN shape only — a file released on the transparent remainder lands on the window below.
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                ClipboardSounds.playCopy()
                // The URLs load asynchronously; report the drop only once they are in the store, so the
                // machine sees the real count (a shaken tray with files must not think it is empty).
                // Dropping keeps the surface open: it is the START of the task.
                store.add(providers: providers) { NotchSurfaceController.shared.filesDropped() }
                return true
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(XFinderTokens.Motion.surface, value: model.state)
            .animation(XFinderTokens.Motion.surface, value: model.appearFromNotch)
        }
        .environment(\.notchAccent, model.accent ?? .accentColor)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .collapsed: badge
        case .peek: if model.itemCount > 0 { peek } else { nowPlayingStrip }   // the machine peeks only with files or a track
        case .activity: activityStrip
        case .expanded(.clipboard): clipboardShell
        case .expanded(let page): hubShell(page)
        }
    }

    private var isClipboardHub: Bool { model.state == .expanded(.clipboard) }

    /// D0, after the OneNotch reference the user supplied: the clipboard hub is wide enough to use the
    /// band EITHER SIDE of the notch — page tabs on the left wing, search + close on the right — then
    /// the chip row, one horizontal row of cards and the footer. The wings are symmetric so nothing is
    /// drawn under the notch; at the pointer (a shaken tray switched to this tab) or on a screen without a
    /// notch the gap is zero and the band is one continuous row.
    private var clipboardShell: some View {
        let inset = XFinderTokens.Space.inline + filletNow     // the flares are outside the content
        let notchGap: CGFloat = (atNotch && !plainScreen) ? model.notchSize.width : 0
        let bandHeight: CGFloat = max(model.notchSize.height, 32)
        let wing = max(0, (size.width - notchGap) / 2 - inset)
        return VStack(alignment: .leading, spacing: XFinderTokens.Space.tight + 2) {
            HStack(spacing: 0) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    pageTabs(current: .clipboard)
                    // The empty part of the band moves a pointer-anchored tray (B1b rule: never over controls).
                    Spacer(minLength: 0)
                        .overlay { if !atNotch { WindowDragHandle().help(L10n.t("Kéo để dời khay")) } }
                }
                .frame(width: wing, alignment: .leading)
                Color.clear.frame(width: notchGap)
                HStack(spacing: XFinderTokens.Space.tight) {
                    NotchClipboardSearchField(model: model.clipboard)
                    Button { NotchSurfaceController.shared.dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").opacity(0.65)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Đóng"))
                }
                .frame(width: wing, alignment: .trailing)
            }
            .frame(height: bandHeight)

            NotchClipboardView(model: model.clipboard)
        }
        .foregroundColor(.white)
        .padding(.horizontal, inset)
        .padding(.bottom, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The three page tabs (Now Playing only while its switch is on), shared by both hub shells.
    /// D1 #44: in the user's order, hidden ones left out; Now Playing additionally needs its own switch (B6).
    @ViewBuilder private func pageTabs(current page: NotchSurfaceMachine.Page) -> some View {
        ForEach(model.pages, id: \.self) { p in
            switch p {
            case .files:
                pageTab(.files, icon: "tray.and.arrow.down.fill", title: L10n.t("Khay"),
                        badge: store.items.isEmpty ? nil : "\(store.items.count)", current: page)
            case .clipboard:
                pageTab(.clipboard, icon: "doc.on.clipboard.fill", title: "Clipboard", badge: nil, current: page)
            case .nowPlaying:
                if model.nowPlayingAvailability != .off {
                    pageTab(.nowPlaying, icon: "music.note", title: L10n.t("Đang phát"), badge: nil, current: page)
                }
            case .agents:
                if model.agentsEnabled {
                    pageTab(.agents, icon: "terminal", title: L10n.t("Agent AI"),
                            badge: model.agentsNeedingYou > 0 ? "\(model.agentsNeedingYou)" : nil, current: page)
                }
            case .calendar:
                if model.calendarEnabled {
                    pageTab(.calendar, icon: "calendar", title: L10n.t("Lịch"), badge: nil, current: page)
                }
            }
        }
    }

    /// Count hanging under the notch while files are held and the surface is collapsed.
    private var badge: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            if model.itemCount > 0 {
                Image(systemName: "tray.fill").font(XFinderTokens.Font.caption)
                Text("\(model.itemCount)").font(XFinderTokens.Font.caption).monospacedDigit()
            }
            if let t = model.timerText {
                Image(systemName: "timer").font(XFinderTokens.Font.caption)
                Text(t).font(XFinderTokens.Font.caption).monospacedDigit()
            }
            if let np = model.nowPlaying, np.hasTrack {
                // B6: the track, as small as the lip allows — artwork (or a note) and the headline.
                artworkThumb(size: 14)
                Text(np.headline).font(XFinderTokens.Font.caption).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 110)
                    .layoutPriority(-1)                      // the count and the timer keep their digits; the title truncates
                    .opacity(np.playing ? 1 : 0.6)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: plainScreen ? NotchSurfaceLayout.Metrics.standard.pillHeight : NotchSurfaceLayout.Metrics.standard.badgeLip)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.itemCount > 0 { NotchSurfaceController.shared.reveal() }
            else if nowPlayingActive { NotchSurfaceController.shared.reveal(page: .nowPlaying) }
        }
        .help(model.itemCount > 0 || nowPlayingActive ? L10n.t("Bấm để mở") : "")
    }

    @ViewBuilder private func artworkThumb(size: CGFloat) -> some View {
        if let img = model.nowPlayingArtwork {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: max(2, size / 8)))
        } else if let icon = model.nowPlayingAppIcon {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "music.note").font(.system(size: size * 0.75))
                .frame(width: size, height: size)
        }
    }

    /// Prev / play-pause / next. Plain white glyphs — they sit on the black surface.
    private func nowPlayingControls(size: CGFloat) -> some View {
        HStack(spacing: XFinderTokens.Space.tight + 2) {
            Button { NotchSurfaceController.shared.nowPlayingCommand(.previousTrack) } label: {
                Image(systemName: "backward.fill").font(.system(size: size))
            }.buttonStyle(.plain).help(L10n.t("Bài trước"))
            Button { NotchSurfaceController.shared.nowPlayingCommand(.togglePlayPause) } label: {
                Image(systemName: model.nowPlaying?.playing == true ? "pause.fill" : "play.fill").font(.system(size: size + 2))
            }.buttonStyle(.plain).help(L10n.t("Phát hoặc tạm dừng"))
            Button { NotchSurfaceController.shared.nowPlayingCommand(.nextTrack) } label: {
                Image(systemName: "forward.fill").font(.system(size: size))
            }.buttonStyle(.plain).help(L10n.t("Bài tiếp"))
        }
    }

    /// The hover peek when no files are held but a track plays: artwork, title/artist, controls.
    private var nowPlayingStrip: some View {
        HStack(spacing: XFinderTokens.Space.tight + 2) {
            artworkThumb(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.nowPlaying?.headline ?? "").font(XFinderTokens.Font.row).lineLimit(1).truncationMode(.tail)
                let sub = model.nowPlaying?.subline ?? ""
                if !sub.isEmpty { Text(sub).font(XFinderTokens.Font.caption).opacity(0.65).lineLimit(1).truncationMode(.tail) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { NotchSurfaceController.shared.reveal(page: .nowPlaying) }
            if AudioTapMonitor.shared.isRunning { WaveformBars(levels: AudioTapMonitor.shared.meter.levels).frame(width: 46, height: 18) }
            nowPlayingControls(size: 11)
        }
        .padding(.horizontal, XFinderTokens.Space.inline)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: NotchSurfaceLayout.Metrics.standard.peekDrop)
    }

    /// The hub page (B6): artwork, titles, a progress bar from the last report, controls, open the player.
    // MARK: - N4: Glance (calendar)

    /// OneNotch's calendar page re-derived: weekday + lunar date, a nine-day strip with dots, the greeting and
    /// "up next" line, then today's list — a meeting link gets a Tham gia button. Access is asked from here,
    /// never on the switch (the sheet must come from a click).
    @ViewBuilder private var calendarPage: some View {
        let now = Date()
        let cal = Calendar.current
        if model.calendarAccess != .granted {
            VStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "calendar.badge.exclamationmark").font(XFinderTokens.Font.pageIcon).opacity(0.65)
                Text(L10n.t(model.calendarAccess == .notDetermined || model.calendarAccess == .unknown
                            ? "Chưa có quyền Lịch. Cấp quyền để thấy sự kiện hôm nay." : "Quyền Lịch bị từ chối — mở Cài đặt hệ thống ▸ Quyền riêng tư ▸ Lịch."))
                    .font(XFinderTokens.Font.caption).opacity(0.65).multilineTextAlignment(.center)
                Button(L10n.t("Cấp quyền Lịch")) { NotchSurfaceController.shared.requestCalendarAccess() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let strip = GlanceRules.weekStrip(around: now, calendar: cal)
            let dots = GlanceRules.daysWithEvents(model.calendarEvents, strip: strip, calendar: cal)
            let today = GlanceRules.dayEvents(model.calendarEvents, on: now, hideAllDay: model.calendarHidesAllDay, calendar: cal)
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack(alignment: .firstTextBaseline) {
                    Text(now.formatted(.dateTime.weekday(.wide))).font(XFinderTokens.Font.row).bold()
                    Text("\(GlanceRules.lunarLabel(for: now)) \(L10n.t("ÂL"))").font(XFinderTokens.Font.caption).opacity(0.65)
                    Spacer()
                    Text(now.formatted(.dateTime.month(.abbreviated).year())).font(XFinderTokens.Font.caption).opacity(0.65)
                    Button { NotchSurfaceController.shared.openCalendar(on: now) } label: { Image(systemName: "arrow.up.forward.app") }
                        .buttonStyle(.plain).opacity(0.65).help(L10n.t("Mở Lịch"))
                }
                HStack(spacing: 0) {
                    ForEach(strip, id: \.self) { d in
                        let isToday = cal.isDate(d, inSameDayAs: now)
                        VStack(spacing: 1) {
                            Text("\(cal.component(.day, from: d))").font(XFinderTokens.Font.caption).monospacedDigit()
                                .opacity(isToday ? 1 : 0.6)
                            Circle().fill(dots.contains(d) ? accent : Color.clear).frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(isToday ? Color.white.opacity(0.18) : Color.clear))
                    }
                }
                let hour = cal.component(.hour, from: now)
                if let next = GlanceRules.upNext(model.calendarEvents, now: now) {
                    HStack(spacing: XFinderTokens.Space.tight) {
                        Text("\(L10n.t(GlanceRules.greetingKey(hour: hour))) \(L10n.t("Tiếp theo: "))\(next.title) · \(next.start.formatted(date: .omitted, time: .shortened))")
                            .font(XFinderTokens.Font.caption).lineLimit(1).truncationMode(.tail)
                        if let c = GlanceRules.countdown(to: next.start, now: now) {
                            Text("\(L10n.t("trong "))\(c.number) \(L10n.t(c.unitKey))").font(XFinderTokens.Font.caption).opacity(0.65)
                        }
                        if let u = GlanceRules.meetingURL(in: next) {
                            Button(L10n.t("Tham gia")) { NSWorkspace.shared.open(u) }.buttonStyle(.borderedProminent).controlSize(.mini)
                        }
                    }
                } else {
                    Text("\(L10n.t(GlanceRules.greetingKey(hour: hour))) \(L10n.t("Hôm nay không còn gì nữa."))")
                        .font(XFinderTokens.Font.caption).opacity(0.75)
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(today) { e in
                            HStack(spacing: XFinderTokens.Space.tight) {
                                Text(e.isAllDay ? L10n.t("Cả ngày") : e.start.formatted(date: .omitted, time: .shortened))
                                    .font(XFinderTokens.Font.caption).monospacedDigit().opacity(0.65).frame(width: 52, alignment: .leading)
                                Image(systemName: e.isReminder ? "checklist" : "circle.fill").font(.system(size: 6)).opacity(0.65)
                                Text(e.title).font(XFinderTokens.Font.caption).lineLimit(1).truncationMode(.tail)
                                    .opacity(e.end < now ? 0.45 : 1)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - N3: AI agent sessions

    /// Up to six sessions, those waiting for the person first. A permission request shows the tool and the one
    /// input field that matters, with Cho phép / Từ chối — the hook is blocking on that file right now.
    @ViewBuilder private var agentsPage: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            agentUsageStrip
            agentSessions
        }
    }

    /// §3b #37 — what the agents themselves wrote on this Mac: Claude Code tokens (not a percentage — Claude Code keeps
    /// no allowance figure locally) and Codex's own rate-limit windows, marked stale once their reset time has passed.
    @ViewBuilder private var agentUsageStrip: some View {
        let u = AgentUsageMonitor.shared.snapshot
        let comma = !L10n.isEnglish
        if u.scannedAt != nil {
            VStack(alignment: .leading, spacing: 1) {
                if u.claude7d.messages > 0 {
                    Text("Claude Code\(L10n.t(" · 5 giờ: "))\(AgentUsage.compact(u.claude5h.output, decimalComma: comma))\(L10n.t(" token ra"))\(L10n.t(" · 7 ngày: "))\(AgentUsage.compact(u.claude7d.output, decimalComma: comma))\(L10n.t(" token ra"))")
                        .help(L10n.t("Token đọc từ lịch sử phiên trên máy này. Claude Code không ghi phần trăm hạn mức ra máy, nên đây không phải %."))
                }
                if let c = u.codex {
                    if let p = c.primary, AgentUsage.isCurrent(p, now: Date()) {
                        let week = c.secondary.flatMap { AgentUsage.isCurrent($0, now: Date()) ? $0 : nil }
                        Text("Codex\(L10n.t(" · 5 giờ "))\(Int(p.usedPercent.rounded()))%\(week.map { "\(L10n.t(" · tuần "))\(Int($0.usedPercent.rounded()))%" } ?? "")")
                            .help(L10n.t("Hạn mức do chính Codex ghi vào log của nó, ở lần dùng gần nhất."))
                    } else {
                        Text("Codex\(L10n.t(" · đã qua giờ reset — số mới có sau lần dùng Codex kế tiếp"))")
                    }
                }
            }
            .font(XFinderTokens.Font.caption).opacity(0.7).lineLimit(1).truncationMode(.tail)
        }
    }

    @ViewBuilder private var agentSessions: some View {
        if model.agents.isEmpty {
            VStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "terminal").font(XFinderTokens.Font.pageIcon).opacity(0.65)
                if model.agentHookInstalled {
                    Text(L10n.t("Chưa có phiên Claude Code nào.")).font(XFinderTokens.Font.caption).opacity(0.65)
                } else {
                    Text(L10n.t("Chưa cài hook — mở Notch & Khay thả để cài.")).font(XFinderTokens.Font.caption).opacity(0.65)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                    ForEach(Array(model.agents.prefix(6))) { s in agentRow(s) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func agentRow(_ s: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Circle().fill(agentTint(s.status)).frame(width: 8, height: 8)
                Text(s.displayName).font(XFinderTokens.Font.row).lineLimit(1)
                Text(agentStatusText(s)).font(XFinderTokens.Font.caption).opacity(0.65).lineLimit(1).truncationMode(.tail)
                Spacer()
                if s.terminal.bundleID != nil, s.status != .ended {
                    Button(L10n.t("Mở terminal")) { NotchSurfaceController.shared.openAgentTerminal(s) }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }
            if case .waitingForPermission(let p) = s.status {
                HStack(spacing: XFinderTokens.Space.tight) {
                    Text(p.toolName).font(XFinderTokens.Font.caption).bold()
                    if let sum = p.summary {
                        Text(sum).font(XFinderTokens.Font.caption).opacity(0.75).lineLimit(1).truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    } else { Spacer() }
                    Button(L10n.t("Từ chối")) { NotchSurfaceController.shared.answerAgent(p, of: s, allow: false) }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button(L10n.t("Cho phép")) { NotchSurfaceController.shared.answerAgent(p, of: s, allow: true) }
                        .buttonStyle(.borderedProminent).controlSize(.mini)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func agentStatusText(_ s: AgentSession) -> String {
        if case .running(let tool) = s.status, let tool { return L10n.t(AgentSessionRules.statusKey(s.status)) + tool }
        return L10n.t(AgentSessionRules.statusKey(s.status))
    }

    private func agentTint(_ st: AgentSession.Status) -> Color {
        switch st {
        case .running: return accent
        case .waitingForInput: return .yellow
        case .waitingForPermission: return .orange
        case .ended: return .white.opacity(0.3)
        }
    }

    @ViewBuilder private var nowPlayingPage: some View {
        if let np = model.nowPlaying, np.hasTrack {
            HStack(alignment: .top, spacing: XFinderTokens.Space.inline + 2) {
                artworkThumb(size: 72)
                VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                    Text(np.headline).font(XFinderTokens.Font.row).lineLimit(2)
                    if !np.subline.isEmpty {
                        Text(np.subline).font(XFinderTokens.Font.caption).opacity(0.65).lineLimit(1).truncationMode(.tail)
                    }
                    // §3b #21 — live bars from the player's own audio; a hint when the tap gets only digital silence.
                    if AudioTapMonitor.shared.isRunning {
                        if AudioTapMonitor.shared.looksDenied {
                            Text(L10n.t("Sóng nhạc chỉ nhận được im lặng — có thể chưa cấp quyền Ghi âm thanh hệ thống."))
                                .font(XFinderTokens.Font.caption).opacity(0.65).lineLimit(2)
                        } else {
                            WaveformBars(levels: AudioTapMonitor.shared.meter.levels).frame(height: 18)
                        }
                    }
                    if let d = np.duration, d > 0 {
                        let pos = model.nowPlayingPosition ?? NowPlaying.position(of: np, at: Date()) ?? 0
                        // N8: the bar is a slider — release to seek (MRMediaRemoteSetElapsedTime, measured to reach the player)
                        Slider(value: Binding(get: { min(pos, d) }, set: { model.nowPlayingPosition = $0 }), in: 0...d,
                               onEditingChanged: { editing in if !editing { NotchSurfaceController.shared.nowPlayingSeek(to: model.nowPlayingPosition ?? pos) } })
                            .controlSize(.mini).tint(.white).frame(height: 14)
                        HStack {
                            Text(NowPlaying.timeLabel(pos)).font(XFinderTokens.Font.caption).monospacedDigit().opacity(0.65)
                            Spacer()
                            if !np.playing { Text(L10n.t("Đang tạm dừng")).font(XFinderTokens.Font.caption).opacity(0.65) }
                            Spacer()
                            Text(NowPlaying.timeLabel(d)).font(XFinderTokens.Font.caption).monospacedDigit().opacity(0.65)
                        }
                    } else if !np.playing {
                        Text(L10n.t("Đang tạm dừng")).font(XFinderTokens.Font.caption).opacity(0.65)
                    }
                    HStack {
                        nowPlayingControls(size: 14)
                        // N8: shuffle / repeat as menus of the three modes — the player's current mode is not readable
                        // from the Now Playing info, so nothing here pretends to show it.
                        Menu {
                            ForEach(NowPlaying.ShuffleMode.allCases, id: \.rawValue) { m in
                                Button(L10n.t(m.labelKey)) { NotchSurfaceController.shared.nowPlayingShuffle(m) }
                            }
                        } label: { Image(systemName: "shuffle").font(.system(size: 12)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t("Xáo trộn"))
                        Menu {
                            ForEach(NowPlaying.RepeatMode.allCases, id: \.rawValue) { m in
                                Button(L10n.t(m.labelKey)) { NotchSurfaceController.shared.nowPlayingRepeat(m) }
                            }
                        } label: { Image(systemName: "repeat").font(.system(size: 12)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t("Lặp lại"))
                        Spacer()
                        if let app = model.nowPlayingAppName {
                            Button("\(L10n.t("Mở "))\(app)") { NotchSurfaceController.shared.openPlayer() }
                                .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "music.note").font(XFinderTokens.Font.pageIcon).opacity(0.65)
                Text(L10n.t("Không có gì đang phát.")).font(XFinderTokens.Font.caption).opacity(0.65)
                if model.nowPlayingAvailability != .ready {
                    Text(L10n.t(model.nowPlayingAvailability.messageKey)).font(XFinderTokens.Font.caption).opacity(0.5)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Peek only exists while files are held (the machine never peeks an empty tray). The left icon
    /// is a drag handle for EVERY held file — so files stay one drag away even collapsed — and the
    /// text opens the hub. They are separate regions because one press cannot be both a drag and a click.
    private var peek: some View {
        HStack(spacing: XFinderTokens.Space.tight + 2) {
            Image(systemName: "tray.full.fill")
                .font(XFinderTokens.Font.row)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(Color.white.opacity(0.12)))
                .overlay(MultiFileDragSource(paths: store.items.map(\.path)))
                .help(L10n.t("Kéo cả chồng ra để dùng một lần."))
            HStack(spacing: XFinderTokens.Space.tight) {
                Text("\(model.itemCount)\(L10n.t(" tệp đang giữ"))").font(XFinderTokens.Font.row)
                Text(L10n.t("Bấm để mở")).font(XFinderTokens.Font.caption).opacity(0.65)
            }
            .contentShape(Rectangle())
            .onTapGesture { NotchSurfaceController.shared.reveal() }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: NotchSurfaceLayout.Metrics.standard.peekDrop)
    }

    /// A live activity: icon, headline, detail — one line under the notch, white on black.
    private var activityStrip: some View {
        HStack(spacing: XFinderTokens.Space.tight + 2) {
            if let a = model.activity {
                Image(systemName: a.symbol).font(XFinderTokens.Font.row).foregroundColor(tint(a.tint))
                Text(L10n.t(a.titleKey)).font(XFinderTokens.Font.row).lineLimit(1)
                if let d = a.detail { Text(d).font(XFinderTokens.Font.caption).opacity(0.7).lineLimit(1).truncationMode(.middle) }
                if let level = a.level {
                    ProgressView(value: level).progressViewStyle(.linear).tint(.white).frame(width: 90)
                }
                ForEach(Array(a.buttons.enumerated()), id: \.offset) { _, b in
                    Button { NotchSurfaceController.shared.pressActivityButton(b) } label: {
                        activityButtonLabel(b).font(XFinderTokens.Font.caption).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: NotchSurfaceLayout.Metrics.standard.activityDrop)
        .padding(.horizontal, XFinderTokens.Space.inline)
    }

    @ViewBuilder private func activityButtonLabel(_ b: LiveActivity.Button) -> some View {
        switch b {
        case .join: Text(L10n.t("Tham gia"))
        case .snooze: Text(L10n.t("Hoãn 5 phút"))
        case .openCalendar: Text(L10n.t("Mở Lịch"))
        }
    }

    private func tint(_ t: LiveActivity.Tint) -> Color {
        switch t {
        case .neutral: return .white
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        }
    }

    /// The hub: one header with two page tabs (files / clipboard) and the close button, then the page.
    private func hubShell(_ page: NotchSurfaceMachine.Page) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            HStack(spacing: XFinderTokens.Space.tight) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    pageTabs(current: page)
                    // A tray opened at the pointer often lands on the very window the files are going
                    // to; the EMPTY part of its title strip moves it out of the way. Only that part:
                    // an NSView overlay wins AppKit hit-testing, so one laid over the tabs swallowed
                    // their clicks (review 2026-10-11), and one over the deck would swallow file drags.
                    Spacer()
                        .overlay { if !atNotch { WindowDragHandle().help(L10n.t("Kéo để dời khay")) } }
                }
                Button { NotchSurfaceController.shared.dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").opacity(0.65)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Đóng"))
            }

            switch page {
            case .files: filesPage
            case .clipboard: NotchClipboardView(model: model.clipboard)
            case .nowPlaying: nowPlayingPage
            case .agents: agentsPage
            case .calendar: calendarPage
            }
        }
        .foregroundColor(.white)
        .padding(XFinderTokens.Space.inline)
        .padding(.horizontal, filletNow)                  // D1: the flares are outside the content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageTab(_ page: NotchSurfaceMachine.Page, icon: String, title: String, badge: String?,
                         current: NotchSurfaceMachine.Page) -> some View {
        Button { NotchSurfaceController.shared.switchPage(page) } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(XFinderTokens.Font.caption)
                Text(title).font(XFinderTokens.Font.caption)
                if let badge { Text(badge).font(XFinderTokens.Font.caption).opacity(0.7).monospacedDigit() }
            }
            .padding(.horizontal, XFinderTokens.Space.tight + 2).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                .fill(current == page ? Color.white.opacity(0.18) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var filesPage: some View {
        if store.items.isEmpty {
            VStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "arrow.down.doc").font(XFinderTokens.Font.pageIcon).opacity(0.65)
                Text(L10n.t("Thả file vào đây để giữ tạm"))
                    .font(XFinderTokens.Font.caption).opacity(0.65)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            stackedDeck
            actionArea
        }
    }

    /// Overlapping deck + a count; dragging the deck hands over EVERY held file at once, which is
    /// the whole point of staging them together.
    private var stackedDeck: some View {
        HStack(spacing: XFinderTokens.Space.inline + 2) {
            ZStack {
                ForEach(Array(store.items.prefix(4).enumerated().reversed()), id: \.element.id) { index, item in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable()
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.white.opacity(0.08)))
                        .rotationEffect(.degrees(Double(index) * -4))
                        .offset(x: CGFloat(index) * 7, y: CGFloat(index) * -3)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                }
            }
            .frame(width: 78, height: 62)
            // SwiftUI's `.onDrag` vends ONE provider and `.itemProviders` does not exist on
            // macOS 14 — the whole stack needs an AppKit drag session.
            .overlay(MultiFileDragSource(paths: store.items.map(\.path)))

            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                Text("\(store.items.count)\(L10n.t(" tệp đang giữ"))")
                    .font(XFinderTokens.Font.row)
                Text(L10n.t("Kéo cả chồng ra để dùng một lần."))
                    .font(XFinderTokens.Font.caption).opacity(0.65)
                HStack(spacing: XFinderTokens.Space.tight + 2) {
                    Button(L10n.t("Xem chi tiết")) { NotchSurfaceController.shared.toggleDetail() }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button(L10n.t("Xóa hết")) { store.removePaths(store.items.map(\.path)) }
                        .buttonStyle(.plain)
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.65)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: Action row (B2d)

    private var actions: [NotchActions.Action] {
        NotchActions.available(for: store.items.filter { !$0.isMissing }.map { URL(fileURLWithPath: $0.path) },
                               encodable: ImageRunner.encodableTypes)
    }

    private func title(_ a: NotchActions.Action) -> String {
        switch a {
        case .zip: return L10n.t("Nén ZIP")
        case .mergePDFs: return L10n.t("Gộp PDF")
        case .convert(let t): return "\(L10n.t("Sang "))\(t.label)"
        case .removeBackground: return L10n.t("Tách nền")
        case .airDrop: return "AirDrop"
        case .toPDF: return L10n.t("Sang PDF")
        case .ocr: return "OCR"
        case .resize(let px): return "\(L10n.t("Thu nhỏ ảnh còn "))\(px) px"
        }
    }

    private func symbol(_ a: NotchActions.Action) -> String {
        switch a {
        case .zip: return "archivebox"
        case .mergePDFs: return "doc.on.doc"
        case .convert: return "photo"
        case .removeBackground: return "person.crop.rectangle"
        case .airDrop: return "airplayaudio"
        case .toPDF: return "doc.richtext"
        case .ocr: return "text.viewfinder"
        case .resize: return "arrow.down.right.and.arrow.up.left"
        }
    }

    @ViewBuilder private var actionArea: some View {
        if let t = model.task, t.isRunning {
            HStack(spacing: XFinderTokens.Space.tight + 2) {
                ProgressView(value: t.fraction).progressViewStyle(.linear).tint(.white)
                Text("\(t.done + t.failed)/\(t.total)").font(XFinderTokens.Font.caption).monospacedDigit()
                Button(L10n.t("Hủy")) { NotchSurfaceController.shared.cancelTask() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    ForEach(actions, id: \.self) { a in
                        if case .resize = a {
                            // N6 "Drop to apply · Hold for options" (OneNotch): a click runs the default preset,
                            // press-and-hold lists the others. Menu(primaryAction:) is exactly that control.
                            Menu {
                                ForEach(ImageEngine.resizePresets, id: \.self) { px in
                                    Button("\(L10n.t("Thu nhỏ ảnh còn "))\(px) px") { NotchSurfaceController.shared.run(.resize(maxPixels: px)) }
                                }
                            } label: {
                                Label(title(a), systemImage: symbol(a)).labelStyle(.iconOnly)
                            } primaryAction: {
                                NotchSurfaceController.shared.run(a)
                            }
                            .menuStyle(.borderedButton).controlSize(.small).fixedSize()
                            .help("\(title(a)) — \(L10n.t("Giữ để chọn cỡ hoặc định dạng."))")
                        } else {
                            Button { NotchSurfaceController.shared.run(a) } label: {
                                Label(title(a), systemImage: symbol(a)).labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .help(title(a))
                        }
                    }
                }
                if let t = model.task {
                    resultLine(t)
                    if let s = model.ocrSummary { Text(s).font(XFinderTokens.Font.caption).opacity(0.75).lineLimit(1) }
                } else if let n = model.notice {
                    Text(L10n.t(n)).font(XFinderTokens.Font.caption).opacity(0.65)
                }
            }
        }
    }

    @ViewBuilder private func resultLine(_ t: NotchTask) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            if t.phase == .cancelled {
                Text(L10n.t("Đã hủy.")).font(XFinderTokens.Font.caption).opacity(0.65)
            } else {
                Text("\(L10n.t("Xong: "))\(t.outputs.count)/\(t.total)").font(XFinderTokens.Font.caption)
                if let f = t.firstFailure {
                    Text("\(L10n.t(f.key))\(f.detail)").font(XFinderTokens.Font.caption).foregroundColor(.orange).lineLimit(1)
                }
            }
            if !t.outputs.isEmpty {
                Button(L10n.t("Hiện trong Finder")) { NotchSurfaceController.shared.revealResults() }
                    .buttonStyle(.plain).font(XFinderTokens.Font.caption).underline()
            }
        }
    }
}

/// Flush with the top of the screen at the notch (`topRadius` 0); fully rounded at the pointer.
/// The surface's outline. Bottom corners are continuous curves; the top is square where the shape meets
/// the screen edge. `topFillet` (D1, OneNotch reference) adds the Dynamic-Island flare: two concave
/// quarter-circles that blend the body's vertical edges INTO the top edge, so the hub looks poured out of
/// the bezel instead of pasted under it. The fillets take `topFillet` pt on each side of the body, which is
/// why the expanded widths carry `2 × Metrics.topFillet` beyond their content.
struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 0
    var topFillet: CGFloat = 0
    var inset: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topFillet) }
        set { bottomRadius = newValue.first; topFillet = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let f = min(topFillet, r.width / 4, r.height / 2)
        let body = CGRect(x: r.minX + f, y: r.minY, width: r.width - 2 * f, height: r.height)
        var p = UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: bottomRadius,
                                       bottomTrailingRadius: bottomRadius, topTrailingRadius: topRadius,
                                       style: .continuous).path(in: body)
        guard f > 0 else { return p }
        // Left flare: top edge from the outer corner to the body, down the body edge to (f, f), then the
        // concave arc (centre (0, f), radius f) back up to the outer corner. Mirrored on the right.
        var left = Path()
        left.move(to: CGPoint(x: r.minX, y: r.minY))
        left.addLine(to: CGPoint(x: body.minX, y: r.minY))
        left.addLine(to: CGPoint(x: body.minX, y: r.minY + f))
        left.addArc(center: CGPoint(x: r.minX, y: r.minY + f), radius: f,
                    startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        left.closeSubpath()
        var right = Path()
        right.move(to: CGPoint(x: r.maxX, y: r.minY))
        right.addLine(to: CGPoint(x: body.maxX, y: r.minY))
        right.addLine(to: CGPoint(x: body.maxX, y: r.minY + f))
        right.addArc(center: CGPoint(x: r.maxX, y: r.minY + f), radius: f,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        right.closeSubpath()
        p.addPath(left)
        p.addPath(right)
        return p
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var s = self
        s.inset += amount
        return s
    }
}

/// Moves its window when pressed and dragged. A separate view so the window drag is confined to the
/// strip it covers: blanket-forwarding `mouseDown` swallowed every file drag once (CLAUDE.md Part 3c).
struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}
}

/// The surface's hosting view. `NSHostingView.acceptsFirstMouse` is `false` (measured by the B1
/// review), and the panel is ordered front without becoming key, so every control needed TWO clicks
/// while another app was frontmost. The deleted tray overrode this on its container; so does this.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Shared tray pieces (also used by the detail grid window)

/// Drags every staged file at once via `beginDraggingSession(with:)`.
struct MultiFileDragSource: NSViewRepresentable {
    let paths: [String]

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView()
        v.paths = paths
        return v
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.paths = paths
    }

    final class DragSourceView: NSView {
        var paths: [String] = []

        override func mouseDown(with event: NSEvent) {
            guard !paths.isEmpty else { return super.mouseDown(with: event) }
            let items: [NSDraggingItem] = paths.compactMap { path in
                let url = URL(fileURLWithPath: path) as NSURL
                let item = NSDraggingItem(pasteboardWriter: url)
                let icon = NSWorkspace.shared.icon(forFile: path)
                // Every item needs a frame + image or the session shows nothing.
                item.setDraggingFrame(NSRect(x: 0, y: 0, width: 48, height: 48), contents: icon)
                return item
            }
            guard !items.isEmpty else { return }
            beginDraggingSession(with: items, event: event, source: self)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

extension MultiFileDragSource.DragSourceView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // `.copy` outside the app: the tray keeps its files — "Kéo ra sẽ sao chép file và giữ các mục trong khay".
        [.copy]
    }
}

/// One staged file with a real QuickLook thumbnail, so "Screenshot 1, Screenshot 2" stay tellable apart.
struct TrayFileTile: View {
    let item: DropTrayStore.Item
    let url: URL
    let onRemove: () -> Void

    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(Color.primary.opacity(0.05))
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable().frame(width: 30, height: 30)
                }
            }
            .frame(width: 62, height: 62)

            Text(item.name)
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(XFinderTokens.Fill.inset))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button(L10n.t("Hiện trong Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button(L10n.t("Mở")) { NSWorkspace.shared.open(url) }
            Divider()
            Button(L10n.t("Bỏ khỏi khay"), action: onRemove)
        }
        .help(item.path)
        .task { thumb = await FileThumbnailer.thumbnail(for: url) }
    }
}

/// QuickLook thumbnails, off the main thread; falls back to the type icon when a format has no previewer.
enum FileThumbnailer {
    static func thumbnail(for url: URL) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 120, height: 120),
            scale: scale,
            representationTypes: .all)
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.nsImage)
            }
        }
    }
}

/// Detail window of the tray — a grid of every file (each draggable on its own). Capped so a
/// thousand-file tray does not draw a thousand tiles at once.
struct DropTrayDetailGrid: View {
    @State private var store = DropTrayStore.shared
    private let cap = 400

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(store.items.prefix(cap)) { item in
                    TrayFileTile(item: item, url: URL(fileURLWithPath: item.path)) {
                        store.remove(item)
                    }
                }
            }
            .padding(XFinderTokens.Space.inline)
        }
        .frame(minWidth: 480, minHeight: 360)
        .overlay(alignment: .bottom) {
            if store.items.count > cap {
                Text("\(L10n.t("Hiện "))\(cap)/\(store.items.count)\(L10n.t(" mục — kéo cả chồng ở khay để thao tác cả lô."))")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .padding(.vertical, XFinderTokens.Space.tight)
                    .frame(maxWidth: .infinity)
                    .background(XFinderTokens.Fill.surface.opacity(0.9))
            }
        }
    }
}

/// §3b #21 — the live waveform: one Canvas, `AudioWaveform.bars` rounded bars, newest on the right.
struct WaveformBars: View {
    let levels: [Float]
    var body: some View {
        Canvas { ctx, size in
            let n = max(1, levels.count)
            let gap: CGFloat = 2
            let w = max(1, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            for (i, l) in levels.enumerated() {
                let h = max(2, CGFloat(l) * size.height)
                let r = CGRect(x: CGFloat(i) * (w + gap), y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(.white.opacity(0.85)))
            }
        }
        .accessibilityHidden(true)
    }
}
