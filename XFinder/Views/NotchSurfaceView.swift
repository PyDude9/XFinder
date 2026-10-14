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
    /// P2: the countdown itself (running or paused) for the Hẹn giờ page, the tick that drives its progress, and the
    /// idle stepper's minutes (`notch.timer.minutes`). The controller owns all three; the page only reads them.
    var timer: LiveActivity.Countdown?
    var timerNow = Date()
    var timerDraftMinutes = LiveActivity.timerDefaultMinutes
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
    /// P5c — terminal sessions that are no longer live, newest first (filled while the Agents page is open).
    var recentAgents: [AgentRecent.Entry] = []
    var agentsEnabled = false
    var agentHookInstalled = false
    /// P6 — the session (its `listID`) whose reply is being typed on the Agents page; nil = not composing.
    var agentReplyTarget: String?
    var agentReplyText = ""
    /// Bumped to move the keyboard into the reply field (the panel became key first).
    var agentReplyFocus = 0
    /// Last outcome per session and the messages XFinder holds until a session is free (mirrored from `AgentTalkSender`).
    var agentReplyStatus: [String: AgentTalkSender.Status] = [:]
    var agentReplyQueued: Set<String> = []
    var agentsNeedingYou: Int { agents.filter(\.needsYou).count }
    /// P1: a Claude Code session is alive (running or waiting) — the left wing of the collapsed notch shows it.
    var agentActive: Bool { agentsEnabled && agents.contains { $0.status != .ended } }
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

/// Root of the Notch surface window. The window is ONE fixed frame (N1); this view draws a black shape of the
/// layout size for the current state, top-centred, and animates between states — the open spring overshoots a
/// little, the close is quick (P1, OneNotch measured). White-on-black on purpose: it must read as part of the
/// notch, not as a floating card.
///
/// P1 grammar (measured on OneNotch): collapsed = the notch's own height with a WING each side of the camera
/// (left: agent / held files, right: track / countdown); expanded = a 32-pt band (page dots + search in the left
/// wing, the toolbar in the right one) over one of two bodies, 382 or 612 wide. A page switch cross-fades.
struct NotchSurfaceView: View {
    var model: NotchSurfaceModel
    @State private var store = DropTrayStore.shared
    @State private var isTargeted = false
    @Environment(\.notchAccent) private var accent

    private typealias Page = NotchSurfaceMachine.Page
    private typealias N = XFinderTokens.Notch
    private static let m = NotchSurfaceLayout.Metrics.standard

    /// The state's own size — what the content is laid out at (once per state, not once per animation frame).
    private var stateSize: CGSize {
        let notch = CGRect(origin: .zero, size: model.notchSize)
        return NotchSurfaceLayout.size(for: model.state, anchor: model.anchor,
                                       itemCount: model.itemCount, notch: notch,
                                       timerActive: model.timerText != nil,
                                       nowPlayingActive: nowPlayingActive,
                                       agentActive: model.agentActive,
                                       pillOnPlainScreens: model.pillOnPlainScreens) ?? .zero
    }

    /// The drawn (animated) size: the notch itself on the first frame of an opening (D0c), else the state's.
    private var size: CGSize {
        model.appearFromNotch ? model.notchSize : stateSize
    }

    /// A screen without a notch: the surface hangs from the top edge over a VIRTUAL notch (D0c).
    private var plainScreen: Bool { model.notchSize.height == 0 }

    private var nowPlayingActive: Bool { model.nowPlaying?.hasTrack == true }

    /// At the notch the top edge is flush with the screen; a tray opened at the pointer is rounded all round.
    private var atNotch: Bool { model.anchor == .notch }

    private var collapsed: Bool { model.state == .collapsed }

    /// The flare into the top edge (P1): the hub's 19 × 8, the collapsed wings' 6.5 × 4. None for a peek / activity
    /// strip (their sizes carry no flare), a pointer tray (no top edge), the pill, or the first frame of an opening
    /// (drawn at the notch's own size — the flare grows in with the shape).
    private var flare: (width: CGFloat, depth: CGFloat) {
        guard atNotch, !model.appearFromNotch else { return (0, 0) }
        switch model.state {
        case .collapsed: return plainScreen ? (0, 0) : (Self.m.collapsedFillet, Self.m.collapsedFilletDepth)
        case .expanded: return (Self.m.topFillet, Self.m.topFilletDepth)
        case .peek, .activity: return (0, 0)
        }
    }

    private var bottomRadius: CGFloat {
        switch model.state {
        case .collapsed: return plainScreen ? Self.m.pillHeight / 2 : Self.m.collapsedBottomRadius
        case .peek, .activity: return 14
        case .expanded: return Self.m.expandedBottomRadius
        }
    }

    private var shape: NotchShape {
        let f = flare
        return NotchShape(bottomRadius: bottomRadius, topRadius: atNotch ? 0 : bottomRadius,
                          flareWidth: f.width, flareDepth: f.depth)
    }

    /// The body without the flares — what the hairline follows (stroking the flared outline would draw lines where
    /// the flare subpaths meet the body).
    private var bodyShape: NotchShape {
        NotchShape(bottomRadius: bottomRadius, topRadius: atNotch ? 0 : bottomRadius)
    }

    /// Measured 2026-10-12 with `sample` during an open: the hosting view animated the WINDOW's frame to follow
    /// this view's ideal size and AppKit's window animation blocked the main thread. The root is therefore a
    /// `GeometryReader` (fixed ideal size), so the window never moves; only the shape inside animates, and the
    /// content is laid out ONCE at the state's size while the clip grows over it.
    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                // No hairline on the collapsed wings: they sit in the menu bar beside the camera and must read as
                // part of the hardware notch, which has no outline.
                bodyShape.strokeBorder(isTargeted ? accent : Color.white.opacity(collapsed ? 0 : 0.10),
                                       lineWidth: isTargeted ? 2 : 1)
                    .padding(.horizontal, flare.width)
                content
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
            // Opening overshoots a little; collapsing is quick and never bounces (P1, OneNotch measured).
            .animation(collapsed ? N.close : N.open, value: model.state)
            .animation(N.open, value: model.appearFromNotch)
        }
        .environment(\.notchAccent, model.accent ?? .accentColor)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .collapsed: wings
        case .peek:
            // The machine peeks only with files or a track.
            Group { if model.itemCount > 0 { peek } else { nowPlayingStrip } }
                .padding(.top, model.notchSize.height)
        case .activity: activityStrip.padding(.top, model.notchSize.height)
        case .expanded(let page): hub(page)
        }
    }

    // MARK: - Collapsed: the wings beside the camera

    private var wingItems: (left: [NotchSurfaceLayout.WingItem], right: [NotchSurfaceLayout.WingItem]) {
        NotchSurfaceLayout.wingItems(itemCount: model.itemCount, timerActive: model.timerText != nil,
                                     nowPlayingActive: nowPlayingActive, agentActive: model.agentActive)
    }

    /// Each side's items sit at the OUTER edge of their wing (OneNotch measured ~9 pt in), so nothing crowds the
    /// camera. On a screen without a notch both sides sit together in the middle of the pill.
    @ViewBuilder private var wings: some View {
        let items = wingItems
        if plainScreen {
            HStack(spacing: Self.m.wingSpacing * 2) {
                wingSide(items.left)
                wingSide(items.right)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let wing = NotchSurfaceLayout.wingWidth(left: items.left, right: items.right)
            HStack(spacing: 0) {
                wingSide(items.left).padding(.leading, 9).frame(width: wing, alignment: .leading)
                Color.clear.frame(width: model.notchSize.width)
                wingSide(items.right).padding(.trailing, 9).frame(width: wing, alignment: .trailing)
            }
            .padding(.horizontal, Self.m.collapsedFillet)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func wingSide(_ items: [NotchSurfaceLayout.WingItem]) -> some View {
        HStack(spacing: Self.m.wingSpacing) {
            ForEach(items, id: \.self) { wingItem($0) }
        }
        .foregroundColor(.white)
    }

    @ViewBuilder private func wingItem(_ item: NotchSurfaceLayout.WingItem) -> some View {
        let w = Self.m.wingItemWidth(item)
        switch item {
        case .agent:
            // Each literal is its own `L10n.t` argument so the literal sweep sees both (a ternary INSIDE t() hides them).
            let label = model.agentsNeedingYou > 0 ? L10n.t("Claude Code đang chờ bạn") : L10n.t("Claude Code đang chạy")
            Image(systemName: "terminal.fill").font(.system(size: 12, weight: .semibold))
                .foregroundColor(model.agentsNeedingYou > 0 ? .orange : .white.opacity(0.85))
                .frame(width: w, height: 22)
                .contentShape(Rectangle())
                .onTapGesture { NotchSurfaceController.shared.reveal(page: .agents) }
                .help(label)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        case .files:
            HStack(spacing: 3) {
                Image(systemName: "tray.fill").font(.system(size: 11))
                Text("\(model.itemCount)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: w, height: 22)
            .contentShape(Rectangle())
            .onTapGesture { NotchSurfaceController.shared.reveal() }
            .help("\(model.itemCount)\(L10n.t(" tệp đang giữ"))")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.itemCount)\(L10n.t(" tệp đang giữ"))")
            .accessibilityAddTraits(.isButton)
        case .music:
            Group {
                // The live bars only while the tap really hears the player; otherwise the artwork (Honesty Rule:
                // bars are never animated from nothing).
                if AudioTapMonitor.shared.isRunning && !AudioTapMonitor.shared.looksDenied {
                    WaveformBars().frame(width: 22, height: 11)
                } else {
                    artworkThumb(size: 18)
                }
            }
            .frame(width: w, height: 22)
            .opacity(model.nowPlaying?.playing == true ? 1 : 0.55)
            .contentShape(Rectangle())
            .onTapGesture { NotchSurfaceController.shared.reveal(page: .nowPlaying) }
            .help(model.nowPlaying?.headline ?? "")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(L10n.t("Đang phát")): \(model.nowPlaying?.headline ?? "")")
            .accessibilityAddTraits(.isButton)
        case .timer:
            HStack(spacing: 3) {
                Image(systemName: model.timer?.isPaused == true ? "pause.fill" : "timer").font(.system(size: 11))
                Text(model.timerText ?? "").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: w, height: 22)
        }
    }

    @ViewBuilder private func artworkThumb(size: CGFloat) -> some View {
        if let img = model.nowPlayingArtwork {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: max(2, size / 6), style: .continuous))
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
            if AudioTapMonitor.shared.isRunning { WaveformBars().frame(width: 46, height: 18) }
            nowPlayingControls(size: 11)
        }
        .padding(.horizontal, XFinderTokens.Space.inline)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: Self.m.peekDrop)
    }

    // MARK: - Expanded: one band over the page

    /// Band + page. The page body cross-fades on a page change (P1: ~200 ms measured) while the shape springs
    /// between the two widths; a ZStack, so the outgoing and incoming pages overlap instead of stacking.
    private func hub(_ page: Page) -> some View {
        VStack(spacing: 0) {
            band(page)
            ZStack(alignment: .top) {
                // The budgets live in Metrics and a test proves they fill each body (the clipboard is the tightest).
                pageBody(page)
                    .padding(.horizontal, page == .nowPlaying ? 16 : 14)
                    .padding(.top, page == .clipboard ? Self.m.clipboardTopInset : Self.m.pageTopInset)
                    .padding(.bottom, page == .clipboard ? Self.m.clipboardBottomInset : Self.m.pageBottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(page)
                    .transition(.opacity)
            }
            .animation(N.pageFade, value: page)
        }
        .foregroundColor(.white)
        .padding(.horizontal, flare.width)                 // the flares are outside the content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func pageBody(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            switch page {
            case .files: filesPage
            case .clipboard: NotchClipboardView(model: model.clipboard)
            case .nowPlaying: nowPlayingPage
            case .agents: NotchAgentsPage(model: model)
            case .calendar: NotchCalendarPage(model: model)
            case .timer: NotchTimerPage(model: model)
            case .aiUsage: NotchAIUsagePage(model: model)
            }
        }
    }

    /// The 32-pt band, symmetric about the camera: page dots (+ search on the clipboard page) in the left wing,
    /// the toolbar in the right one; nothing is drawn under the notch. At the pointer or on a screen without a
    /// notch the gap is 0 and the band is one row; at the pointer the empty part of the band is also a drag strip.
    private func band(_ page: Page) -> some View {
        let bandHeight = max(model.notchSize.height, Self.m.bandHeight)
        let notchGap: CGFloat = (atNotch && !plainScreen) ? model.notchSize.width : 0
        let inner = stateSize.width - 2 * flare.width
        let wing = NotchSurfaceLayout.bandWingWidth(bodyWidth: inner, notchWidth: notchGap)
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                dotsCapsule(current: page)
                if page == .clipboard {
                    NotchClipboardSearchField(model: model.clipboard).layoutPriority(1)
                }
                // The empty part of the band moves a pointer-anchored tray (B1b rule: never over controls — an
                // NSView overlay wins AppKit hit-testing over every SwiftUI control under it).
                Spacer(minLength: 0)
                    .overlay { if !atNotch { WindowDragHandle().help(L10n.t("Kéo để dời khay")) } }
            }
            .frame(width: wing, alignment: .leading)
            Color.clear.frame(width: notchGap)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                toolbarCapsule(current: page)
            }
            .frame(width: wing, alignment: .trailing)
        }
        .padding(.horizontal, Self.m.bandInset)
        .frame(height: bandHeight)
    }

    /// A page the hub can show right now: Now Playing needs its switch (B6), Agents and the calendar theirs.
    /// The timer needs nothing; AI usage rides the "Agent AI trên notch" switch (it reads the agents' own files).
    private func available(_ p: Page) -> Bool {
        switch p {
        case .files, .clipboard, .timer: return true
        case .nowPlaying: return model.nowPlayingAvailability != .off
        case .agents, .aiUsage: return model.agentsEnabled
        case .calendar: return model.calendarEnabled
        }
    }

    private func pageTitle(_ p: Page) -> String { L10n.t(NotchPages.titleKey(p)) }

    /// One dot per swipeable page in the user's order (D1 #44); the lit dot is the current page (OneNotch measured:
    /// dot 1 on Clipboard, dot 3 on Agents). Each dot is a button — the tooltip / VoiceOver label names the page
    /// the dot alone cannot. An Agents dot turns orange while a session waits for you.
    private func dotsCapsule(current: Page) -> some View {
        let pages = NotchPages.dots(model.pages).filter(available)
        return HStack(spacing: 0) {
            ForEach(pages, id: \.self) { p in
                Button { NotchSurfaceController.shared.switchPage(p) } label: {
                    Circle().fill(dotColor(p, current: current))
                        .frame(width: N.dotSize, height: N.dotSize)
                        .frame(width: N.dotPitch, height: N.dotsCapsuleHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pageTitle(p))
                .accessibilityLabel(pageTitle(p))
                .accessibilityAddTraits(p == current ? .isSelected : [])
            }
        }
        .padding(.horizontal, Self.m.dotsCapsulePadding)   // NotchSurfaceLayout.dotsCapsuleWidth: 15 n + 9
        .background(Capsule().fill(N.capsule))
    }

    private func dotColor(_ p: Page, current: Page) -> Color {
        if p == current { return N.dotLit }
        if p == .agents, model.agentsNeedingYou > 0 { return .orange }
        return N.dotDim
    }

    /// The toolbar: fixed destinations (the calendar now; the timer and AI usage in P2), lit while current.
    /// The tools, then the ✕ as the capsule's last slot. On every page and at the notch too: Esc closes only the
    /// clipboard page (its key monitor), so elsewhere the ✕ is the one immediate way out besides leaving (P1 review).
    /// Width = `NotchSurfaceLayout.toolbarCapsuleWidth(slots: tools + 1)` — tested to fit a narrow page's wing (P2 review).
    private func toolbarCapsule(current: Page) -> some View {
        let tools = NotchPages.toolbar(model.pages).filter(available)
        return HStack(spacing: 0) {
            ForEach(tools, id: \.self) { p in
                Button { NotchSurfaceController.shared.switchPage(p) } label: {
                    Image(systemName: toolIcon(p)).font(.system(size: 11, weight: .semibold))
                        .foregroundColor(p == current ? N.dotLit : N.toolbarIcon)
                        .frame(width: Self.m.toolbarSlot, height: N.toolbarHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pageTitle(p))
                .accessibilityLabel(pageTitle(p))
                .accessibilityAddTraits(p == current ? .isSelected : [])
            }
            Button { NotchSurfaceController.shared.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .foregroundColor(N.toolbarIcon)
                    .frame(width: Self.m.toolbarSlot, height: N.toolbarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("Đóng"))
            .accessibilityLabel(L10n.t("Đóng"))
        }
        .padding(.horizontal, Self.m.toolbarCapsulePadding)
        .background(Capsule().fill(N.capsule))
    }

    private func toolIcon(_ p: Page) -> String { NotchPages.symbol(p) }
    // MARK: - Now Playing (B6; P1 layout after OneNotch)

    /// Artwork (with the player's icon on its corner — click it to open the player), title, artist, the live bars
    /// top-right, the transport row; under them the seekable progress bar and the times. With nothing playing the
    /// same frame stays, with a placeholder artwork and inert controls, so the page does not jump.
    @ViewBuilder private var nowPlayingPage: some View {
        let np = model.nowPlaying.flatMap { $0.hasTrack ? $0 : nil }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                nowPlayingArtwork(np)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(np?.headline ?? L10n.t("Không có gì đang phát."))
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        waveformGlyph
                    }
                    if let np {
                        if !np.subline.isEmpty {
                            Text(np.subline).font(XFinderTokens.Font.caption).opacity(0.6).lineLimit(1).truncationMode(.tail)
                        }
                    } else if model.nowPlayingAvailability != .ready {
                        Text(L10n.t(model.nowPlayingAvailability.messageKey)).font(XFinderTokens.Font.caption).opacity(0.5)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    transportRow(enabled: np != nil)
                }
                .frame(height: Self.m.artworkSide)
            }
            Spacer(minLength: Self.m.artworkToProgressGap)
            progressArea(np)
        }
    }

    @ViewBuilder private func nowPlayingArtwork(_ np: NowPlaying.Snapshot?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if np != nil, let img = model.nowPlayingArtwork {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        N.capsule
                        Image(systemName: "music.note").font(.system(size: 28)).foregroundColor(N.toolbarIcon)
                    }
                }
            }
            .frame(width: Self.m.artworkSide, height: Self.m.artworkSide)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if np != nil, let icon = model.nowPlayingAppIcon {
                Button { NotchSurfaceController.shared.openPlayer() } label: {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: 6)
                .help(model.nowPlayingAppName.map { "\(L10n.t("Mở "))\($0)" } ?? "")
            }
        }
        .frame(width: Self.m.artworkSide, height: Self.m.artworkSide)
    }

    /// §3b #21 — live bars from the player's own audio; a slashed glyph (its tooltip says why) when the tap hears
    /// only digital silence. Nothing at all while the tap is off.
    @ViewBuilder private var waveformGlyph: some View {
        if AudioTapMonitor.shared.isRunning {
            if AudioTapMonitor.shared.looksDenied {
                Image(systemName: "waveform.slash").font(.system(size: 11)).foregroundColor(N.toolbarIcon)
                    .help(L10n.t("Sóng nhạc chỉ nhận được im lặng — có thể chưa cấp quyền Ghi âm thanh hệ thống."))
            } else {
                WaveformBars().frame(width: 30, height: 14)
            }
        }
    }

    /// Shuffle / repeat are menus of the three modes (N8): the player's current mode is not readable from the Now
    /// Playing info, so nothing here pretends to show it. Play/pause is the big one.
    private func transportRow(enabled: Bool) -> some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(NowPlaying.ShuffleMode.allCases, id: \.rawValue) { m in
                    Button(L10n.t(m.labelKey)) { NotchSurfaceController.shared.nowPlayingShuffle(m) }
                }
            } label: { Image(systemName: "shuffle").font(.system(size: 12)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t("Xáo trộn"))
            Spacer(minLength: 0)
            Button { NotchSurfaceController.shared.nowPlayingCommand(.previousTrack) } label: {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }.buttonStyle(.plain).help(L10n.t("Bài trước"))
            Spacer(minLength: 0)
            Button { NotchSurfaceController.shared.nowPlayingCommand(.togglePlayPause) } label: {
                Image(systemName: model.nowPlaying?.playing == true ? "pause.fill" : "play.fill").font(.system(size: 22))
                    .frame(width: 28)
            }.buttonStyle(.plain).help(L10n.t("Phát hoặc tạm dừng"))
            Spacer(minLength: 0)
            Button { NotchSurfaceController.shared.nowPlayingCommand(.nextTrack) } label: {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }.buttonStyle(.plain).help(L10n.t("Bài tiếp"))
            Spacer(minLength: 0)
            Menu {
                ForEach(NowPlaying.RepeatMode.allCases, id: \.rawValue) { m in
                    Button(L10n.t(m.labelKey)) { NotchSurfaceController.shared.nowPlayingRepeat(m) }
                }
            } label: { Image(systemName: "repeat").font(.system(size: 12)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t("Lặp lại"))
        }
        .frame(height: 28)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    /// The full-width seek bar (N8: release to seek — `MRMediaRemoteSetElapsedTime`, measured to reach the player)
    /// and the times. A fixed height either way, so a stream with no duration does not move the controls.
    @ViewBuilder private func progressArea(_ np: NowPlaying.Snapshot?) -> some View {
        VStack(spacing: 5) {
            if let np, let d = np.duration, d > 0 {
                let pos = min(d, model.nowPlayingPosition ?? NowPlaying.position(of: np, at: Date()) ?? 0)
                NowPlayingSeekBar(position: pos, duration: d) { NotchSurfaceController.shared.nowPlayingSeek(to: $0) }
                    .frame(height: 10)
                HStack {
                    Text(NowPlaying.timeLabel(pos)).monospacedDigit()
                    Spacer()
                    if !np.playing { Text(L10n.t("Đang tạm dừng")) }
                    Spacer()
                    Text(NowPlaying.timeLabel(d)).monospacedDigit()
                }
                .font(.system(size: 10)).opacity(0.6)
            } else if let np, !np.playing {
                Text(L10n.t("Đang tạm dừng")).font(.system(size: 10)).opacity(0.6)
            }
        }
        .frame(height: Self.m.progressAreaHeight, alignment: .bottom)
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
        case .openAgents: Text(L10n.t("Xem"))
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

/// The surface's outline. Bottom corners are continuous curves; the top is square where the shape meets the
/// screen edge (`topRadius` 0 at the notch) and rounded on a pointer tray. P1 (OneNotch measured): at the notch
/// the body FLARES into the top edge — a short concave fillet `flareWidth` wide that settles `flareDepth` below
/// the edge (19 × 8 on a hub, 6.5 × 4 on the collapsed wings). A quarter circle fitted the measured edge badly
/// (it is snappy, not round), so the fillet is a quadratic curve. The flares sit outside the body, which is why
/// the layout's sizes carry `2 × flareWidth` beyond their content.
struct NotchShape: InsettableShape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 0
    var flareWidth: CGFloat = 0
    var flareDepth: CGFloat = 0
    var inset: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(bottomRadius, AnimatablePair(flareWidth, flareDepth)) }
        set { bottomRadius = newValue.first; flareWidth = newValue.second.first; flareDepth = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let f = max(0, min(flareWidth, r.width / 4))
        let d = max(0, min(flareDepth, r.height / 2))
        let body = CGRect(x: r.minX + f, y: r.minY, width: r.width - 2 * f, height: r.height)
        let radius = min(bottomRadius, body.height / 2, body.width / 2)
        let top = min(topRadius, body.height / 2, body.width / 2)
        var p = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: radius,
                                       bottomTrailingRadius: radius, topTrailingRadius: top,
                                       style: .continuous).path(in: body)
        guard f > 0, d > 0 else { return p }
        // Left flare: along the top edge from the outer corner to the body, down the body edge by the depth, then a
        // concave curve back up to the outer corner (control point at the body's top corner). Mirrored on the right.
        var left = Path()
        left.move(to: CGPoint(x: r.minX, y: r.minY))
        left.addLine(to: CGPoint(x: body.minX, y: r.minY))
        left.addLine(to: CGPoint(x: body.minX, y: r.minY + d))
        left.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: body.minX, y: r.minY))
        left.closeSubpath()
        var right = Path()
        right.move(to: CGPoint(x: r.maxX, y: r.minY))
        right.addLine(to: CGPoint(x: body.maxX, y: r.minY))
        right.addLine(to: CGPoint(x: body.maxX, y: r.minY + d))
        right.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: body.maxX, y: r.minY))
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
/// It reads the meter ITSELF so only this view re-renders 30 times a second. Passing `levels` in from the page made
/// the whole Now Playing page observe the meter — measured live 2026-10-13: 1.77 s of CPU over 30 s with the page open.
struct WaveformBars: View {
    var body: some View {
        let levels = AudioTapMonitor.shared.meter.levels
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

/// The Now Playing progress bar (P1): a thin track (#818184, OneNotch measured) with the played part in white.
/// Dragging scrubs locally and seeks on release, so the controller's 1 s ticker cannot yank the thumb mid-drag.
struct NowPlayingSeekBar: View {
    let position: Double
    let duration: Double
    let onCommit: (Double) -> Void
    @State private var scrub: Double?

    var body: some View {
        GeometryReader { g in
            let shown = scrub ?? position
            let frac = duration > 0 ? max(0, min(1, shown / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(XFinderTokens.Notch.progressTrack).frame(height: 4)
                Capsule().fill(Color.white.opacity(0.9)).frame(width: max(4, g.size.width * frac), height: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in scrub = Self.time(at: v.location.x, width: g.size.width, duration: duration) }
                .onEnded { v in
                    let t = Self.time(at: v.location.x, width: g.size.width, duration: duration)
                    scrub = nil
                    onCommit(t)
                })
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.t("Tiến độ phát"))
        .accessibilityValue(NowPlaying.timeLabel(scrub ?? position))
    }

    private static func time(at x: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard width > 0 else { return 0 }
        return Double(max(0, min(1, x / width))) * duration
    }
}
