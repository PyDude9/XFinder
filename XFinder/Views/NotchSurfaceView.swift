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
    /// Remaining/elapsed time of the active clock ("12:34"), shown in the collapsed badge (B4b + XF-ISLAND 1B).
    var timerText: String?
    var timerBadgeMode: NotchClockMode = .countdown
    var timerBadgeSymbol = "timer"
    var timerBadgePaused = false
    /// P2 + XF-ISLAND 1B: clock suite state owned by the controller; `NotchTimerPage` only reads them.
    var clockMode: NotchClockMode = .countdown
    var timer: LiveActivity.Countdown?
    var stopwatch = NotchStopwatch()
    var pomodoro = NotchPomodoro()
    var hydration = NotchHydrationReminder()
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
    /// XF-ISLAND-C: unified ordered visibility catalog covering legacy pages + extra modules.
    var tabCatalog: NotchTabCatalogState = NotchDestinationCatalog.defaultState
    /// XF-ISLAND-C: live runtime readiness decoupled from user toggle preference.
    var destinationAvailability: NotchDestinationAvailability = .builtInOnly
    /// XF-ISLAND-C: true while showing the always-accessible Settings recovery card (all destinations hidden).
    var showingAllHiddenRecovery = false
    var accent: Color?
    /// N4: the Glance page — events + timed reminders in a ±5-day window, the access state, the all-day switch.
    var calendarEvents: [GlanceEvent] = []
    var calendarEnabled = false
    var calendarAccess: CalendarGlanceMonitor.Access = .unknown
    var calendarHidesAllDay = false
    /// N3: Claude Code sessions (mirrored from `AgentSessionMonitor`), whether the feature is on, and whether the hook is installed.
    var agents: [AgentSession] = [] { didSet { recomputeAgentCache() } }
    /// P5c — terminal sessions that are no longer live, newest first (filled while the Agents page is open).
    var recentAgents: [AgentRecent.Entry] = []
    var agentsEnabled = false { didSet { recomputeAgentCache() } }
    var agentHookInstalled = false
    var openCodeOn = false
    var openCodeMissing = false
    /// P6 — the session (its `listID`) whose reply is being typed on the Agents page; nil = not composing.
    var agentReplyTarget: String?
    var agentReplyText = ""
    /// Bumped to move the keyboard into the reply field (the panel became key first).
    var agentReplyFocus = 0
    /// Last outcome per session and the messages XFinder holds until a session is free (mirrored from `AgentTalkSender`).
    var agentReplyStatus: [String: AgentTalkSender.Status] = [:]
    var agentReplyQueued: Set<String> = []
    /// P7a — the windowless session (its `listID`) whose conversation is open on the Agents page; nil = the list.
    var windowlessConversation: String?
    /// P7a — the "new windowless session" composer: open?, the folder picked, the first message, the folders offered.
    var newWindowlessOpen = false
    var newWindowlessFolder: String?
    /// P11 — which agent the "+" composer starts (Claude Code or Codex).
    var newWindowlessAgent: AgentKind = .claude
    var newWindowlessText = ""
    var newWindowlessFolders: [String] = []
    /// Bumped to move the keyboard into the composer's field.
    var newWindowlessFocus = 0
    /// The last start failure (a store key) and its detail, shown in the composer.
    var windowlessNotice: String?
    var windowlessNoticeDetail: String?
    var windowlessStarting = false
    /// P7b — the crew whose board is open on the Agents page; nil = the list.
    var crewBoard: String?
    /// Cached O(1) summaries derived from `agents` + `agentsEnabled` so Notch animation/timer frames
    /// never recompute `AgentSessionRules.wingSummary` multiple times per render pass.
    private(set) var agentsNeedingYou: Int = 0
    private(set) var agentActive: Bool = false
    private(set) var agentSummary: AgentSessionRules.WingSummary?
    var agentBusy: Bool { agentSummary?.activity.isBusy ?? false }
    var agentCount: Int { agentSummary?.live ?? 0 }

    private func recomputeAgentCache() {
        agentsNeedingYou = agents.filter { AgentSessionRules.activity(of: $0) == .waiting }.count
        agentActive = agentsEnabled && agents.contains { $0.status != .ended }
        agentSummary = agentsEnabled ? AgentSessionRules.wingSummary(agents) : nil
    }
    /// D0c: true for the first frame of a surface opening at the notch — the shape is drawn at the notch's
    /// own size and the controller flips this on the next run-loop turn, so the hub springs out of the notch.
    var appearFromNotch = false
    /// Active Section Gallery or extra telemetry/audio deck shown inside the wide expanded hub.
    var extraModule: NotchExtraModule? = nil
    var mirrorController: MirrorCaptureController?
    var isEditingTeleprompter = false
    var isEditingUtility = false
    let emoji = NotchEmojiModel()
    let links = NotchLinksModel()
    let imageConvert = NotchImageConvertModel()
    let todos = NotchTodosModel()
    let shortcuts = AppleShortcutsStore(runner: AppleShortcutsProcessRunner())
    /// Phase 2 Weather: true only when an explicit WeatherProvider is registered on NotchSurfaceController.
    var weatherAvailable = false
    var weatherViewModel: WeatherViewModel? = nil
    var isSearchingWeatherCity = false
    /// Prototype Island modules: US Stocks & App Revenue (lazy-configured via NotchSurfaceController).
    var stocksAvailable = false
    var stocksViewModel: StocksViewModel? = nil
    var isSearchingStock = false
    var revenueAvailable = false
    var revenueViewModel: RevenueViewModel? = nil
    var websiteAnalyticsViewModel: WebsiteAnalyticsViewModel? = nil
    /// EventKit Reminders module (lazy-initialized when opened; never prompts TCC on launch).
    var remindersViewModel: RemindersViewModel? = nil
    var isCreatingReminder = false
    /// Layout toggle so Ref29 shell can exercise narrow (`382 pt`) vs wide (`612 pt`) responsive layouts cleanly.
    var preferNarrowExtraModule = false
    var displayScale: NotchDisplayScale = .regular
    var inlineSettingsShowsStocks = false
    /// Multi-selection state for the Drop Tray inside the expanded Island (shared with keyboard shortcuts).
    var traySelection = DropTraySelection()
    /// Ref-29 Pin toggle (wired to `NotchSurfaceMachine.Settings.pinned`).
    var isPinned = false
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
    @State private var fileQueue = FileOperationQueue.shared
    @State private var isTargeted = false
    @State private var isAirDropTargeted = false
    @State private var pillHovered = false
    @State private var tabStripContentFrame = CGRect.zero
    @Environment(\.notchAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Page = NotchSurfaceMachine.Page
    private typealias N = XFinderTokens.Notch
    private static let m = NotchSurfaceLayout.Metrics.standard

    /// Single highest-priority signal shown on the collapsed Island / external pill.
    private var collapsedSignal: NotchCollapsedSignal {
        let visibleSet = Set(model.tabCatalog.visibleDestinations(availability: model.destinationAvailability))
        return NotchCollapsedSignal.resolve(
            itemCount: model.itemCount,
            timerActive: model.timerText != nil,
            timerPaused: model.timerBadgePaused,
            nowPlayingActive: nowPlayingActive,
            nowPlayingPlaying: model.nowPlaying?.playing == true,
            agentActive: model.agentActive,
            agentBusy: model.agentBusy,
            agentsNeedingYou: model.agentsNeedingYou,
            visibleDestinations: visibleSet
        )
    }

    private var collapsedProjection: NotchCollapsedSignal.WingProjection {
        collapsedSignal.projection(agentCount: model.agentCount)
    }

    /// The state's own size — shared directly with `NotchSurfaceLayout` (once per state, not once per animation frame).
    private var stateSize: CGSize {
        let notch = CGRect(origin: .zero, size: model.notchSize)
        let layoutState: NotchSurfaceMachine.State = {
            if case .expanded = model.state, model.extraModule != nil {
                return model.preferNarrowExtraModule && model.extraModule != .settings ? .expanded(.nowPlaying) : .expanded(.aiUsage)
            }
            return model.state
        }()
        let useCollapsed = (model.state == .collapsed)
        let proj = collapsedProjection
        return NotchSurfaceLayout.size(for: layoutState, anchor: model.anchor,
                                       itemCount: useCollapsed ? proj.itemCount : model.itemCount,
                                       notch: notch,
                                       timerActive: useCollapsed ? proj.timerActive : (model.timerText != nil),
                                       nowPlayingActive: useCollapsed ? proj.nowPlayingActive : nowPlayingActive,
                                       agentActive: useCollapsed ? proj.agentActive : model.agentActive,
                                       agentBusy: useCollapsed ? proj.agentBusy : model.agentBusy,
                                       agentCount: useCollapsed ? proj.agentCount : model.agentCount,
                                       pillOnPlainScreens: model.pillOnPlainScreens, compactActivity: compactHUD,
                                       settingsPresented: model.extraModule == .settings,
                                       metrics: Self.m.resized(model.displayScale)) ?? .zero
    }

    /// Volume / brightness feedback wears the collapsed wings' shape (glyph left, level right), not the notice strip.
    private var compactHUD: Bool { model.state == .activity && model.activity?.kind.isKeyFeedback == true }

    /// Collapsed wings, or the HUD drawn in their shape.
    private var wingShaped: Bool { collapsed || compactHUD }

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
        case .activity where compactHUD: return plainScreen ? (0, 0) : (Self.m.collapsedFillet, Self.m.collapsedFilletDepth)
        case .peek, .activity: return (0, 0)
        }
    }

    private var bottomRadius: CGFloat {
        switch model.state {
        case .collapsed: return plainScreen ? Self.m.pillHeight / 2 : Self.m.collapsedBottomRadius
        case .activity where compactHUD: return plainScreen ? Self.m.pillHeight / 2 : Self.m.collapsedBottomRadius
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

    @ViewBuilder private var surfaceBackdrop: some View {
        ZStack {
            shape.fill(Color.black)
            if !(collapsed && atNotch && !plainScreen) {
                nowPlayingAmbientWash
            }
        }
    }

    @ViewBuilder private var nowPlayingAmbientWash: some View {
        if case .expanded(.nowPlaying) = model.state, model.extraModule == nil,
           model.nowPlaying?.hasTrack == true, let artwork = model.nowPlayingArtwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .blur(radius: 30)
                .opacity(0.22)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var surfaceBorder: some View {
        if isTargeted {
            bodyShape.strokeBorder(accent, lineWidth: 2)
        } else if wingShaped && atNotch && !plainScreen {
            bodyShape.strokeBorder(Color.clear, lineWidth: 1)
        } else {
            bodyShape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.08), Color.white.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
    }

    /// Measured 2026-10-12 with `sample` during an open: the hosting view animated the WINDOW's frame to follow
    /// this view's ideal size and AppKit's window animation blocked the main thread. The root is therefore a
    /// `GeometryReader` (fixed ideal size), so the window never moves; only the shape inside animates, and the
    /// content is laid out ONCE at the state's size while the clip grows over it.
    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                surfaceBackdrop
                surfaceBorder
                    .padding(.horizontal, flare.width)
                content
                    .frame(width: stateSize.width, height: stateSize.height, alignment: .top)
                    .opacity(model.appearFromNotch ? 0 : 1)                                     // fades in as the shape grows
                    // P8: and comes into focus — Notch Crew's hover opens blurred-to-sharp (owner's screenshot,
                    // 2026-10-14), not as a hard cut. Disabled under Reduce Motion.
                    .blur(radius: NotchMotionPolicy.appearBlurRadius(appearFromNotch: model.appearFromNotch, reduceMotion: reduceMotion))
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .shadow(color: (collapsed && atNotch && !plainScreen) ? .clear : Color.black.opacity(0.42), radius: 18, x: 0, y: 8)
            // N1: the window is larger than the shape (one fixed frame for every state), so the drop target is
            // the DRAWN shape only — a file released on the transparent remainder lands on the window below.
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard model.extraModule != .imageConvert, model.extraModule != .settings else { return false }
                ClipboardSounds.playCopy()
                // Hold the tray open while async NSItemProvider URLs load, then notify the state machine with the real count.
                NotchSurfaceController.shared.beginDropImport()
                store.add(providers: providers) { NotchSurfaceController.shared.filesDropped() }
                return true
            }
            .onChange(of: isTargeted) { _, targeted in
                NotchSurfaceController.shared.setDropTargeted(targeted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Animate only size changes so page switches at the same width do not spring the shell.
            .animation(reduceMotion ? nil : (model.state == .activity ? N.activity : (collapsed ? N.close : N.tabResize)), value: stateSize)
            .animation(reduceMotion ? nil : N.open, value: model.appearFromNotch)
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
        case .activity where compactHUD: hudWings
        case .activity: activityStrip.padding(.top, model.notchSize.height)
        case .expanded(let page): hub(page)
        }
    }

    // MARK: - Collapsed: the wings beside the camera

    private var wingItems: (left: [NotchSurfaceLayout.WingItem], right: [NotchSurfaceLayout.WingItem]) {
        let proj = collapsedProjection
        return NotchSurfaceLayout.wingItems(
            itemCount: proj.itemCount,
            timerActive: proj.timerActive,
            nowPlayingActive: proj.nowPlayingActive,
            agentActive: proj.agentActive,
            agentBusy: proj.agentBusy,
            agentCount: proj.agentCount
        )
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
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(Color.white.opacity(pillHovered ? 0.08 : 0)))
            .scaleEffect(NotchMotionPolicy.pillHoverScale(hovered: pillHovered, reduceMotion: reduceMotion))
            .animation(reduceMotion ? nil : N.pageFade, value: pillHovered)
            .onHover { pillHovered = $0 }
        } else {
            let wing = NotchSurfaceLayout.wingWidth(left: items.left, right: items.right)
            HStack(spacing: 0) {
                wingSide(items.left).padding(.leading, Self.m.wingEdgePadding).frame(width: wing, alignment: .leading)
                Color.clear.frame(width: model.notchSize.width)
                wingSide(items.right).padding(.trailing, Self.m.wingEdgePadding).frame(width: wing, alignment: .trailing)
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
        case .agent, .agentCounted:
            // P8 — the agents' own tiles with the summary mark (was one generic `terminal.fill` for every agent,
            // read by the owner as "the kitty icon", and spoken as "Claude Code" even for OpenCode).
            if let summary = model.agentSummary {
                let label = AgentWingGlyph.label(summary)
                AgentWingGlyph(summary: summary)
                    .frame(width: w, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture { NotchSurfaceController.shared.reveal(page: .agents) }
                    .help(label)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(.isButton)
            }
        case .agentActivity:
            if let summary = model.agentSummary {
                let lead = summary.agents.first?.brand.tile ?? (1, 1, 1)
                // A light tile (Codex, OpenCode) reads as white on the black notch; Claude's orange stays orange.
                let tint = summary.agents.first?.brand.glyphIsDark == true ? Color.white : Color(red: lead.0, green: lead.1, blue: lead.2)
                AgentActivityGrid(tint: tint, waiting: summary.activity == .waiting)
                    .frame(width: w, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture { NotchSurfaceController.shared.reveal(page: .agents) }
                    .help(AgentWingGlyph.label(summary))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(AgentWingGlyph.label(summary))
                    .accessibilityAddTraits(.isButton)
            }
        case .files:
            HStack(spacing: 3) {
                Image(systemName: "tray.fill").font(.system(size: 10, weight: .medium))
                Text("\(model.itemCount)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
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
            let badgeTitle: String = {
                switch model.timerBadgeMode {
                case .countdown: return L10n.t("Hẹn giờ")
                case .stopwatch: return L10n.t("Bấm giờ")
                case .pomodoro: return L10n.t("Pomodoro")
                }
            }()
            HStack(spacing: 3) {
                Image(systemName: model.timerBadgeSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(model.timerBadgePaused ? .white.opacity(0.6) : .orange)
                Text(model.timerText ?? "")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: w, height: 22)
            .contentShape(Rectangle())
            .onTapGesture { NotchSurfaceController.shared.reveal(page: .timer) }
            .help("\(badgeTitle): \(model.timerText ?? "")")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(badgeTitle): \(model.timerText ?? "")")
            .accessibilityAddTraits(.isButton)
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
            }.buttonStyle(.plain).help(L10n.t("Bài trước")).accessibilityLabel(L10n.t("Bài trước"))
            Button { NotchSurfaceController.shared.nowPlayingCommand(.togglePlayPause) } label: {
                Image(systemName: model.nowPlaying?.playing == true ? "pause.fill" : "play.fill").font(.system(size: size + 2))
            }.buttonStyle(.plain).help(L10n.t("Phát hoặc tạm dừng")).accessibilityLabel(L10n.t("Phát hoặc tạm dừng"))
            Button { NotchSurfaceController.shared.nowPlayingCommand(.nextTrack) } label: {
                Image(systemName: "forward.fill").font(.system(size: size))
            }.buttonStyle(.plain).help(L10n.t("Bài tiếp")).accessibilityLabel(L10n.t("Bài tiếp"))
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

    // MARK: - Expanded: Ref-29 top header, 156-pt page body, bottom navigation bar

    /// Ref-29 expanded hub shell: top header (title + Clipboard search when active + ongoing work pill + Pin/Close),
    /// fixed 156-pt middle page container, and scrollable bottom navigation.
    private func hub(_ page: Page) -> some View {
        let isClipboard = (!model.showingAllHiddenRecovery && model.extraModule == nil && page == .clipboard)
        let isNowPlaying = (!model.showingAllHiddenRecovery && model.extraModule == nil && page == .nowPlaying)
        let isWide = model.showingAllHiddenRecovery || model.extraModule == .settings
            ? true
            : NotchNavLayout.usesWideCanvas(
                page: page,
                extraModule: model.extraModule,
                preferNarrowExtra: model.preferNarrowExtraModule
            )
        let activeID = model.showingAllHiddenRecovery
            ? "all-hidden-recovery-W"
            : (model.extraModule?.rawValue ?? page.rawValue)

        return VStack(spacing: 0) {
            ref29TopHeader(page: page, isWide: isWide)

            ZStack(alignment: .top) {
                // Existing page budgets fit inside the 156-pt middle container (NotchSurfaceLayoutTests).
                pageBody(page, isWide: isWide)
                    .padding(.horizontal, isNowPlaying ? 16 : 14)
                    .padding(.top, isClipboard ? Self.m.clipboardTopInset : 4)
                    .padding(.bottom, isClipboard ? Self.m.clipboardBottomInset : 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(activeID)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 4)),
                        removal: .opacity
                    ))
            }
            .frame(height: model.extraModule == .settings ? Self.m.settingsBodyHeight : Self.m.expandedBodyHeight)
            .clipped()
            .animation(reduceMotion ? N.pageFade : N.tabTransition, value: activeID)

            ref29BottomNavBar(page: page, isWide: isWide)
        }
        .foregroundColor(.white)
        .padding(.horizontal, flare.width)                 // the flares are outside the content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func pageBody(_ page: Page, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            if model.showingAllHiddenRecovery {
                allHiddenRecoveryBody
            } else if let extra = model.extraModule {
                switch extra {
                case .sections: NotchSectionsView(model: model)
                case .settings:
                    NotchInterfaceDetailView(embeddedInNotch: true, showStocks: model.inlineSettingsShowsStocks)
                case .home: NotchHomePage(model: model, excludedQuickDestinationID: .home)
                case .system: NotchSystemPage()
                case .audio: NotchAudioPage()
                case .reminders:
                    if let vm = model.remindersViewModel {
                        NotchRemindersPage(viewModel: vm, embedsInIsland: true)
                    }
                case .mirror:
                    if let controller = model.mirrorController {
                        NotchMirrorPage(controller: controller)
                    }
                case .teleprompter:
                    NotchTeleprompterPage(controller: .shared)
                case .notes:
                    NotchNotesPage(
                        onSearchFocusChanged: NotchSurfaceController.shared.setUtilityEditing,
                        onWillOpenEditor: NotchSurfaceController.shared.dismiss
                    )
                case .capture:
                    NotchCapturePage(
                        onPrepareForCapture: NotchSurfaceController.shared.hideForCapture,
                        onOpenCaptureSettings: {
                            NotchSurfaceController.shared.dismiss()
                            AppState.shared.navigate(to: .capture)
                        }
                    )
                case .units:
                    NotchUnitsPage(onInputFocusChanged: NotchSurfaceController.shared.setUtilityEditing)
                case .scratchpad:
                    NotchScratchpadPage(onEditingChanged: NotchSurfaceController.shared.setUtilityEditing)
                case .emoji:
                    NotchEmojiPage(model: model.emoji, onSearchFocusChanged: NotchSurfaceController.shared.setUtilityEditing)
                case .fileBrowser:
                    NotchFileBrowserPage()
                case .links:
                    NotchLinksPage(
                        model: model.links,
                        onOpenSettings: {
                            NotchSurfaceController.shared.dismiss()
                            AppState.shared.navigate(to: .finderSearch)
                        },
                        onSearchFocusChanged: NotchSurfaceController.shared.setUtilityEditing
                    )
                case .imageConvert:
                    NotchImageConvertPage(converter: model.imageConvert)
                case .sounds:
                    NotchSoundsPage()
                case .todos:
                    NotchTodosPage(model: model.todos)
                case .shortcuts:
                    NotchShortcutsPage(store: model.shortcuts)
                case .appUsage:
                    NotchAppUsagePage()
                case .localChat:
                    NotchLocalChatPage(onInputFocusChanged: { focused in
                        if focused { NotchSurfaceController.shared.ensurePanelKeyForKeyboard() }
                    })
                case .message:
                    NotchMessagePage(onInputFocusChanged: { focused in
                        if focused { NotchSurfaceController.shared.ensurePanelKeyForKeyboard() }
                    })
                case .feedback:
                    NotchFeedbackPage()
                case .weather:
                    if let vm = model.weatherViewModel {
                        NotchWeatherPage(viewModel: vm, embedsInIsland: true)
                    }
                case .stocks:
                    if let vm = model.stocksViewModel {
                        NotchStocksPage(viewModel: vm, embedsInIsland: true)
                    } else {
                        NotchStocksSetupPage()
                    }
                case .revenue:
                    if let vm = model.revenueViewModel {
                        NotchRevenuePage(viewModel: vm, embedsInIsland: true)
                    }
                case .websiteAnalytics:
                    if let vm = model.websiteAnalyticsViewModel {
                        NotchWebsiteAnalyticsPage(
                            viewModel: vm,
                            onConfigurationOpened: NotchSurfaceController.shared.ensurePanelKeyForKeyboard
                        )
                    }
                }
            } else {
                switch page {
                case .files: ref29FilesPage(isWide: isWide)
                case .clipboard: NotchClipboardView(model: model.clipboard, searchPlacement: clipboardSearchPlacement)
                case .nowPlaying: nowPlayingPage
                case .agents: NotchAgentsPage(model: model)
                case .calendar: NotchCalendarPage(model: model)
                case .timer: NotchTimerPage(model: model)
                case .aiUsage: NotchAIUsagePage(model: model)
                }
            }
        }
    }

    private var allHiddenRecoveryBody: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
            Text(L10n.t("Tất cả mục Dynamic Island đang ẩn"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(L10n.t("Bật lại ít nhất một mục trong Cài đặt để hiện trên Dynamic Island. Kéo thả tệp vào notch vẫn hoạt động bình thường."))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            Button {
                NotchSurfaceController.shared.openInlineNotchSettings()
            } label: {
                Label(L10n.t("Mở Cài đặt Dynamic Island"), systemImage: "gearshape.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Mở Cài đặt Dynamic Island"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clipboardSearchPlacement: NotchClipboardRules.SearchPlacement {
        let isWide = NotchNavLayout.usesWideCanvas(page: .clipboard, extraModule: nil)
        let bodyWidth = Double(isWide ? Self.m.wideWidth : Self.m.narrowWidth)
        return NotchClipboardRules.searchPlacement(
            onPhysicalNotch: atNotch && !plainScreen,
            isWide: isWide,
            bodyWidth: bodyWidth,
            notchWidth: Double(model.notchSize.width)
        )
    }

    @ViewBuilder private func ref29TopHeader(page: Page, isWide: Bool) -> some View {
        let onNotchWing = atNotch && !plainScreen
        let searchPlacement = clipboardSearchPlacement

        if onNotchWing {
            let notchGap = model.notchSize.width
            let inner = stateSize.width - 2 * flare.width
            let wing = max(56, (inner - notchGap - 28) / 2)
            HStack(spacing: 0) {
                ref29HeaderLeftWing(page: page, compact: !isWide, searchPlacement: searchPlacement)
                    .frame(width: wing, alignment: .leading)

                Color.clear.frame(width: notchGap)

                ref29HeaderRightWing(page: page, compact: !isWide)
                    .frame(width: wing, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(height: max(model.notchSize.height, Self.m.bandHeight) + 2)
        } else {
            HStack(spacing: 8) {
                ref29HeaderLeftWing(page: page, compact: !isWide, searchPlacement: searchPlacement)
                Spacer(minLength: 8)
                    .overlay { if !atNotch { WindowDragHandle().help(L10n.t("Kéo để dời khay")) } }
                ref29HeaderRightWing(page: page, compact: !isWide)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.m.plainHeaderHeight + 2)
        }
    }

    private func ref29HeaderLeftWing(
        page: Page,
        compact: Bool,
        searchPlacement: NotchClipboardRules.SearchPlacement
    ) -> some View {
        HStack(spacing: 6) {
            if model.extraModule == .settings {
                Button {
                    NotchSurfaceController.shared.returnFromInlineNotchSettings()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("Quay lại"))
                .accessibilityLabel(L10n.t("Quay lại"))
            }
            Text(currentDestinationTitle(page: page))
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(3)

            if model.extraModule == nil && page == .files && model.itemCount > 0 && !compact {
                Text("\(model.itemCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .fixedSize()
                    .layoutPriority(2)
            } else if model.extraModule == nil && page == .clipboard {
                switch searchPlacement {
                case .header(let maxW):
                    NotchClipboardSearchField(model: model.clipboard)
                        .frame(maxWidth: CGFloat(maxW), alignment: .leading)
                        .layoutPriority(0)
                case .contentRow:
                    ref29ClipboardHeaderSearchTrigger
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
        }
    }

    private var ref29ClipboardHeaderSearchTrigger: some View {
        let locked = ClipboardShelfController.shared.touchIDLockEnabled && !model.clipboard.unlocked
        let active = model.clipboard.searchFocused || !model.clipboard.query.isEmpty
        return Button {
            NotchSurfaceController.shared.focusClipboardSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(active ? accent : XFinderTokens.Notch.toolbarIcon)
                .frame(width: XFinderTokens.Notch.searchDiameter, height: XFinderTokens.Notch.searchDiameter)
                .background(
                    Circle()
                        .fill(active ? accent.opacity(0.16) : XFinderTokens.Notch.capsule)
                        .overlay(
                            Circle()
                                .strokeBorder(active ? accent.opacity(0.75) : Color.white.opacity(0.10), lineWidth: 0.75)
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.35 : 1)
        .help(L10n.t("Tìm kiếm (⌘F)…"))
        .accessibilityLabel(L10n.t("Tìm kiếm (⌘F)…"))
        .accessibilityIdentifier("notch.clipboard.headerSearchButton")
    }

    private func ref29HeaderRightWing(page: Page, compact: Bool) -> some View {
        HStack(spacing: 5) {
            if hasOngoingFileWork && (page != .files || model.extraModule != nil) {
                Button {
                    NotchSurfaceController.shared.closeExtraModule()
                    NotchSurfaceController.shared.switchPage(.files)
                } label: {
                    HStack(spacing: 3) {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                        if !compact {
                            Text(L10n.t("Đang xử lý"))
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, compact ? 5 : 6)
                    .frame(height: 20)
                    .background(Capsule().fill(accent.opacity(0.32)))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(L10n.t("Mở Khay thả để xem thao tác đang chạy"))
            }

            ref29HeaderControlsView
        }
        .fixedSize()
        .layoutPriority(3)
    }

    private var ref29HeaderControlsView: some View {
        HStack(spacing: 5) {
            Button {
                NotchSurfaceController.shared.togglePin()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(model.isPinned ? 0 : 35))
                    .foregroundStyle(model.isPinned ? accent : .white.opacity(0.62))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(model.isPinned ? accent.opacity(0.20) : Color.white.opacity(0.07))
                            .overlay(
                                Circle()
                                    .strokeBorder(model.isPinned ? accent.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isPinned ? L10n.t("Bỏ ghim khay") : L10n.t("Ghim khay (không đóng khi bấm ra ngoài)"))
            .accessibilityLabel(model.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))
            .accessibilityAddTraits(model.isPinned ? .isSelected : [])

            Button {
                NotchSurfaceController.shared.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("Đóng"))
            .accessibilityLabel(L10n.t("Đóng"))
        }
    }

    private func ref29BottomNavBar(page: Page, isWide: Bool) -> some View {
        let destinations = model.tabCatalog.visibleDestinations(availability: model.destinationAvailability)
        let selected: NotchDestinationID? = if model.showingAllHiddenRecovery {
            nil
        } else if let extra = model.extraModule {
            NotchDestinationID(extra: extra)
        } else {
            NotchDestinationID(page: page)
        }

        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 6) {
                if destinations.isEmpty {
                    Button(L10n.t("Mở Cài đặt…")) {
                        NotchSurfaceController.shared.openInlineNotchSettings()
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(L10n.t("Mở Cài đặt Dynamic Island"))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            HStack(spacing: isWide ? 4 : 2) {
                                ForEach(destinations) { destination in
                                    ref29BottomDestinationButton(destination, isSelected: destination == selected)
                                        .id(destination)
                                }
                            }
                            .padding(.horizontal, 2)
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .named("notchTabStrip"))
                            } action: { frame in
                                tabStripContentFrame = frame
                            }
                        }
                        .coordinateSpace(name: "notchTabStrip")
                        .scrollIndicators(.hidden)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            GeometryReader { geometry in
                                let viewport = geometry.size.width
                                let overflow = tabStripContentFrame.width - viewport
                                if viewport > 0, overflow > 1 {
                                    let thumb = min(viewport, max(18, viewport * viewport / tabStripContentFrame.width))
                                    let progress = min(1, max(0, -tabStripContentFrame.minX / overflow))
                                    Capsule()
                                        .fill(.white.opacity(0.24))
                                        .frame(width: thumb, height: 2)
                                        .offset(x: (viewport - thumb) * progress)
                                }
                            }
                            .frame(height: 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                        .onChange(of: selected, initial: true) { previous, id in
                            guard let id, destinations.contains(id) else { return }
                            if reduceMotion || previous == id {
                                proxy.scrollTo(id)
                            } else {
                                withAnimation(N.tabResize) { proxy.scrollTo(id) }
                            }
                        }
                    }

                    Button {
                        if model.extraModule == .settings {
                            NotchSurfaceController.shared.returnFromInlineNotchSettings()
                        } else {
                            NotchSurfaceController.shared.openInlineNotchSettings()
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Mở Cài đặt Dynamic Island"))
                    .accessibilityLabel(L10n.t("Mở Cài đặt Dynamic Island"))
                }
            }
            .frame(height: 31)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.m.bottomNavHeight)
    }

    private func ref29BottomDestinationButton(_ destination: NotchDestinationID, isSelected: Bool) -> some View {
        Button {
            NotchSurfaceController.shared.selectDestination(destination)
        } label: {
            Image(systemName: destination.symbol)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? accent : .white.opacity(0.65))
                .frame(width: 27, height: 26)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                            .fill(accent.opacity(0.18))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if (destination == .files && model.itemCount > 0)
                        || (destination == .agents && model.agentsNeedingYou > 0) {
                        Circle()
                            .fill(destination == .agents ? Color.orange : accent)
                            .frame(width: 4, height: 4)
                            .padding(3)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t(destination.titleKey))
        .accessibilityLabel(L10n.t(destination.titleKey))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : N.pageFade, value: isSelected)
    }

    private func shortTabTitle(_ p: Page) -> String {
        switch p {
        case .files: return L10n.t("Khay")
        default: return pageTitle(p)
        }
    }

    private func currentDestinationTitle(page: Page) -> String {
        if model.showingAllHiddenRecovery { return L10n.t("Giao diện notch") }
        if let extra = model.extraModule { return L10n.t(NotchGalleryRules.titleKey(for: extra)) }
        return shortTabTitle(page)
    }

    private var hasOngoingFileWork: Bool {
        model.task?.isRunning == true || model.task?.isAwaitingReview == true || fileQueue.hasActiveWork
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
                        Button { NotchSurfaceController.shared.openExtraModule(.audio) } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("Âm thanh"))
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
            // Ambient soft glow behind artwork when track is playing
            if np != nil, let img = model.nowPlayingArtwork {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.m.artworkSide, height: Self.m.artworkSide)
                    .blur(radius: 12)
                    .opacity(0.4)
                    .offset(y: 4)
            }
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
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            if np != nil, let icon = model.nowPlayingAppIcon {
                Button { NotchSurfaceController.shared.openPlayer() } label: {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: 4)
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
            } label: { Image(systemName: "shuffle").font(.system(size: 12)).accessibilityLabel(L10n.t("Xáo trộn")) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t("Xáo trộn"))
            Spacer(minLength: 0)
            Button { NotchSurfaceController.shared.nowPlayingCommand(.previousTrack) } label: {
                Image(systemName: "backward.fill").font(.system(size: 14))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help(L10n.t("Bài trước")).accessibilityLabel(L10n.t("Bài trước"))
            Spacer(minLength: 0)
            Button { NotchSurfaceController.shared.nowPlayingCommand(.togglePlayPause) } label: {
                ZStack {
                    Circle()
                        .fill(enabled ? Color.white : Color.white.opacity(0.18))
                        .frame(width: 32, height: 32)
                        .shadow(color: enabled ? Color.white.opacity(0.2) : .clear, radius: 4)
                    Image(systemName: model.nowPlaying?.playing == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(enabled ? .black : .white.opacity(0.4))
                }
            }.buttonStyle(.plain).help(L10n.t("Phát hoặc tạm dừng")).accessibilityLabel(L10n.t("Phát hoặc tạm dừng"))
            Spacer(minLength: 0)
            Button { NotchSurfaceController.shared.nowPlayingCommand(.nextTrack) } label: {
                Image(systemName: "forward.fill").font(.system(size: 14))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help(L10n.t("Bài tiếp")).accessibilityLabel(L10n.t("Bài tiếp"))
            Spacer(minLength: 0)
            Menu {
                ForEach(NowPlaying.RepeatMode.allCases, id: \.rawValue) { m in
                    Button(L10n.t(m.labelKey)) { NotchSurfaceController.shared.nowPlayingRepeat(m) }
                }
            } label: { Image(systemName: "repeat").font(.system(size: 12)).accessibilityLabel(L10n.t("Lặp lại")) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t("Lặp lại"))
        }
        .frame(height: 32)
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
                .overlay(MultiFileDragSource(paths: actionableTrayItems.map(\.path)))
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

    /// Volume / brightness: the glyph on the left wing, the level on the right — the same slots the collapsed wings
    /// use (`wingEdgePadding` from the outer edge, the camera between), so the HUD reads as the notch, not a panel.
    @ViewBuilder private var hudWings: some View {
        if let a = model.activity {
            let glyph = Image(systemName: a.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 22)
            let bar = NotchLevelBar(level: a.level ?? 0, width: Self.m.hudBarWidth, height: 4)
            Group {
                if plainScreen {
                    HStack(spacing: Self.m.wingSpacing * 2) { glyph; bar }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        glyph.padding(.leading, Self.m.wingEdgePadding).frame(width: Self.m.hudWing, alignment: .leading)
                        Color.clear.frame(width: model.notchSize.width)
                        bar.padding(.trailing, Self.m.wingEdgePadding).frame(width: Self.m.hudWing, alignment: .trailing)
                    }
                    .padding(.horizontal, Self.m.collapsedFillet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .foregroundColor(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(L10n.t(a.titleKey)) \(a.detail ?? "")"))
        }
    }

    /// A live activity: icon, headline, detail — one line under the notch, white on black.
    private var activityStrip: some View {
        HStack(spacing: XFinderTokens.Space.tight + 2) {
            if let a = model.activity {
                Image(systemName: a.symbol).font(XFinderTokens.Font.row).foregroundColor(tint(a.tint))
                Text(L10n.t(a.titleKey)).font(XFinderTokens.Font.row).lineLimit(1)
                if let level = a.level {
                    // A level notice (volume, brightness): the percentage keeps ONE width whatever the digits, so the
                    // centred row does not shift sideways on every key press, and the bar is drawn here rather than
                    // by AppKit's progress indicator so it glides with each step instead of jumping on its own clock.
                    if let d = a.detail {
                        Text(d).font(XFinderTokens.Font.caption.monospacedDigit()).opacity(0.7).lineLimit(1)
                            .frame(width: 34, alignment: .trailing)
                    }
                    NotchLevelBar(level: level)
                } else if let d = a.detail {
                    Text(d).font(XFinderTokens.Font.caption).opacity(0.7).lineLimit(1).truncationMode(.middle)
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
        case .handOff(_, let target): Text("\(L10n.t("Chuyển sang "))\(target.displayName)…")
        case .hydrateAck: Text(L10n.t("Đã uống"))
        case .hydrateSnooze: Text(L10n.t("Hoãn 10 phút"))
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

    private var selectedTrayItems: [DropTrayStore.Item] {
        store.items.filter { model.traySelection.contains($0.id) }
    }

    private var actionableTrayItems: [DropTrayStore.Item] {
        store.items.filter { $0.status.isActionable }
    }

    private func handleNotchTrayClick(_ item: DropTrayStore.Item) {
        NotchSurfaceController.shared.ensurePanelKeyForKeyboard()
        let flags = NSEvent.modifierFlags
        model.traySelection.click(
            item.id,
            in: store.items.map(\.id),
            command: flags.contains(.command),
            shift: flags.contains(.shift)
        )
    }

    private func dragPathsForNotchItem(_ item: DropTrayStore.Item) -> [String] {
        if model.traySelection.contains(item.id) {
            return selectedTrayItems.filter { $0.status.isActionable }.map(\.path)
        }
        return item.status.isActionable ? [item.path] : []
    }

    private func pickFilesIntoTray() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            store.add(urls: panel.urls)
            NotchSurfaceController.shared.filesDropped()
        }
    }

    private var resolvedTrayActionState: DropTrayActionResolution.Result<DropTrayStore.Item> {
        DropTrayActionResolution.resolve(
            items: store.items,
            selection: model.traySelection,
            id: \.id,
            isActionable: \.status.isActionable
        )
    }

    private func batchActions(for items: [DropTrayStore.Item]) -> [NotchActions.Action] {
        NotchActions.available(
            for: items.map { URL(fileURLWithPath: $0.path) },
            encodable: ImageRunner.encodableTypes
        ).filter { $0 != .airDrop }
    }

    /// Ref-29 Khay: AirDrop card (~28% left) + dashed drop & staging zone (~72% right), preserving
    /// drag-all out, per-card drag, multi-selection, Quick Look, Share, Atlas pane copy/move,
    /// batch `NotchActions`, `FileOperationQueue` progress, and the detail grid panel.
    @ViewBuilder private func ref29FilesPage(isWide: Bool) -> some View {
        let resolved = resolvedTrayActionState

        HStack(spacing: isWide ? 10 : 8) {
            ref29AirDropCard(isWide: isWide, resolved: resolved)

            ZStack(alignment: .topLeading) {
                if let t = model.task, t.isAwaitingReview {
                    ref29ImageReviewView(task: t)
                } else if store.items.isEmpty {
                    ref29EmptyDropZone(isWide: isWide, dropHighlight: isTargeted, resolved: resolved)
                } else {
                    ref29PopulatedDropZone(isWide: isWide, resolved: resolved)
                }

                if model.task?.isAwaitingReview != true {
                    if let n = model.notice {
                        ref29NoticeBanner(n)
                    } else if let t = model.task, !t.isRunning {
                        ref29TaskResultBanner(task: t, ocrSummary: model.ocrSummary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 146)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTargeted ? accent.opacity(0.14) : Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.15, dash: [5, 4]))
                    .foregroundStyle(isTargeted ? accent : Color.white.opacity(0.22))
            )
        }
        .frame(height: 146)
    }

    private func ref29EmptyDropZone(
        isWide: Bool,
        dropHighlight: Bool,
        resolved: DropTrayActionResolution.Result<DropTrayStore.Item>
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                Image(systemName: dropHighlight ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(dropHighlight ? accent : Color.white.opacity(0.84))

                Text(L10n.t("Thả tệp vào đây"))
                    .font(.system(size: isWide ? 12.5 : 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)

                Text(isWide ? L10n.t("Giữ tạm · Kéo ra hoặc gửi sang ngăn") : L10n.t("Kéo ra hoặc gửi ngăn"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)

                Button {
                    pickFilesIntoTray()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(L10n.t("Thêm tệp…"))
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                            .fill(Color.white.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("Thêm tệp…"))
                .accessibilityLabel(L10n.t("Thêm tệp…"))
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ref29DashedOverflowMenu(resolved: resolved, batchActions: [])
                .padding(.top, 6)
                .padding(.trailing, 7)
        }
    }

    private func ref29PopulatedDropZone(
        isWide: Bool,
        resolved: DropTrayActionResolution.Result<DropTrayStore.Item>
    ) -> some View {
        let targetActionable = resolved.targets
        let availableBatch = batchActions(for: targetActionable)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                ref29DragAllHandle(isWide: isWide, actionableItems: actionableTrayItems)
                    .padding(.leading, isWide ? 8 : 6)
                    .padding(.top, 6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.items) { item in
                            ref29FileCardView(for: item)
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.top, 6)
                }

                ref29DashedOverflowMenu(resolved: resolved, batchActions: availableBatch)
                    .padding(.top, 6)
                    .padding(.trailing, 7)
            }
            .frame(height: 98)

            ref29BottomTrayRow(isWide: isWide, resolved: resolved, batchActions: availableBatch)
                .padding(.horizontal, isWide ? 8 : 6)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ref29DragAllHandle(isWide: Bool, actionableItems: [DropTrayStore.Item]) -> some View {
        let w: CGFloat = isWide ? 48 : 42
        let dragPaths = actionableItems.map(\.path)
        return VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                Image(systemName: "tray.full.fill")
                    .font(.system(size: isWide ? 15 : 14, weight: .medium))
                    .foregroundStyle(.white.opacity(dragPaths.isEmpty ? 0.35 : 0.90))
            }
            .frame(width: 34, height: 36)

            Text("\(store.items.count)\(L10n.t(" tệp"))")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
                .lineLimit(1)

            Text(L10n.t("Kéo tất cả"))
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(width: w, height: 84)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
        .opacity(dragPaths.isEmpty ? 0.55 : 1)
        .overlay {
            if !dragPaths.isEmpty {
                MultiFileDragSource(paths: dragPaths)
            }
        }
        .help(L10n.t("Kéo cả chồng ra để dùng một lần."))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L10n.t("Kéo tất cả")) — \(store.items.count)\(L10n.t(" tệp"))")
    }

    @ViewBuilder private func ref29BottomTrayRow(
        isWide: Bool,
        resolved: DropTrayActionResolution.Result<DropTrayStore.Item>,
        batchActions: [NotchActions.Action]
    ) -> some View {
        if let t = model.task, t.isRunning {
            HStack(spacing: XFinderTokens.Space.tight + 2) {
                ProgressView(value: t.fraction).progressViewStyle(.linear).tint(.white)
                Text("\(t.done + t.failed)/\(t.total)").font(XFinderTokens.Font.caption).monospacedDigit()
                Button(L10n.t("Hủy")) { NotchSurfaceController.shared.cancelTask() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .frame(height: 28)
        } else if let job = fileQueue.queue.active {
            let jobFraction: Double = job.bytesTotal > 0
                ? min(1, max(0, Double(job.bytesDone) / Double(job.bytesTotal)))
                : (job.itemsTotal > 0 ? min(1, max(0, Double(job.itemsDone) / Double(job.itemsTotal))) : 0)
            HStack(spacing: XFinderTokens.Space.tight + 2) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text(L10n.t(fileQueue.stageLabelKey(for: job)))
                    .font(XFinderTokens.Font.caption)
                    .lineLimit(1)
                ProgressView(value: jobFraction).progressViewStyle(.linear).tint(.white)
                Text("\(job.itemsDone)/\(job.itemsTotal)").font(XFinderTokens.Font.caption).monospacedDigit()
                Button(L10n.t("Hủy")) { fileQueue.cancel(job.id) }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .frame(height: 28)
        } else {
            ref29DashedZoneActionStrip(isWide: isWide, resolved: resolved, batchActions: batchActions)
        }
    }

    private func ref29ImageReviewView(task t: NotchTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.t("Xem trước xử lý ảnh"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(L10n.t("Tạo bản mới")) { NotchSurfaceController.shared.confirmImageReview() }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
                    .disabled(t.imageReviewRows.isEmpty)
                Button(L10n.t("Hủy")) { NotchSurfaceController.shared.cancelTask() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(t.imageReviewRows.prefix(4).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6) {
                            Text(row.url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let p = row.preview?.plan {
                                Text("\(p.uprightWidth)\(L10n.t(" × "))\(p.uprightHeight)\(L10n.t(" → "))\(p.outputWidth)\(L10n.t(" × "))\(p.outputHeight)\(L10n.t(" px"))")
                                    .foregroundStyle(row.preview?.willSkip == true ? .orange : .white.opacity(0.68))
                                    .lineLimit(1)
                            } else if let failure = row.failure {
                                Text("\(L10n.t(failure.messageKey))\(failure.detail)")
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                            }
                        }
                        .font(XFinderTokens.Font.caption)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ref29FileCardView(for item: DropTrayStore.Item) -> some View {
        NotchTrayFileCard(
            item: item,
            selected: model.traySelection.contains(item.id),
            accent: accent,
            dragPaths: dragPathsForNotchItem(item),
            onClick: { handleNotchTrayClick(item) },
            onDoubleClick: { NotchSurfaceController.shared.quickLookTrayItems([item]) },
            onQuickLook: { NotchSurfaceController.shared.quickLookTrayItems([item]) },
            onShare: { NotchSurfaceController.shared.shareTrayItems([item]) },
            onCopyToPane: { NotchSurfaceController.shared.sendTrayItemsToActivePane([item], copy: true) },
            onMoveToPane: { NotchSurfaceController.shared.sendTrayItemsToActivePane([item], copy: false) },
            onRemove: {
                store.remove(item)
                model.traySelection.prune(validIDs: Set(store.items.map(\.id)))
            }
        )
    }

    private func ref29NoticeBanner(_ noticeKey: String) -> some View {
        HStack(spacing: 4) {
            Text(L10n.t(noticeKey))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
            Button { model.notice = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Đóng"))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.black.opacity(0.90))
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.45), lineWidth: 0.5))
        )
        .padding(.top, 6)
        .padding(.trailing, 38)
        .padding(.leading, 8)
    }

    private func ref29TaskResultBanner(task t: NotchTask, ocrSummary: String?) -> some View {
        HStack(spacing: 6) {
            resultLine(t)
            if let ocrSummary {
                Text(ocrSummary)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Button {
                model.task = nil
                model.ocrSummary = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Đóng"))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.black.opacity(0.90))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5))
        )
        .padding(.top, 6)
        .padding(.trailing, 38)
        .padding(.leading, 8)
    }

    private func ref29AirDropCard(
        isWide: Bool,
        resolved: DropTrayActionResolution.Result<DropTrayStore.Item>
    ) -> some View {
        let cardWidth: CGFloat = isWide ? 160 : 86
        let actionableItems = resolved.targets
        let selectionBlocked = resolved.hasSelectionWithZeroActionable
        let unselectableTrayOnly = !resolved.hasSelection && !store.items.isEmpty && actionableItems.isEmpty
        let cardDisabled = selectionBlocked || unselectableTrayOnly

        let subtitle: String = {
            if selectionBlocked {
                return isWide ? L10n.t("Mục chọn không khả dụng") : L10n.t("Không khả dụng")
            }
            if unselectableTrayOnly {
                return isWide ? L10n.t("Chưa có tệp khả dụng") : L10n.t("Không khả dụng")
            }
            if !actionableItems.isEmpty {
                return isWide
                    ? "\(actionableItems.count)\(L10n.t(" tệp")) · \(L10n.t("Gửi qua macOS"))"
                    : "\(actionableItems.count)\(L10n.t(" tệp"))"
            }
            return isWide ? L10n.t("Gửi tới thiết bị gần") : L10n.t("Thiết bị gần")
        }()

        let helpText: String = {
            if selectionBlocked || unselectableTrayOnly {
                return L10n.t("Mục đang chọn đã di chuyển hoặc không thể đọc — bỏ chọn hoặc chọn tệp khả dụng.")
            }
            if !actionableItems.isEmpty {
                return "AirDrop — \(subtitle)"
            }
            return L10n.t("Khay trống — bấm để chọn tệp gửi qua AirDrop")
        }()

        return Button {
            guard !cardDisabled else { return }
            if !actionableItems.isEmpty {
                NotchSurfaceController.shared.airDropTrayItems(actionableItems)
            } else if !resolved.hasSelection {
                NotchSurfaceController.shared.pickAndAirDropFiles()
            }
        } label: {
            VStack(spacing: 5) {
                Spacer(minLength: 0)
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: isWide ? 22 : 18, weight: .regular))
                    .foregroundStyle(cardDisabled ? .white.opacity(0.32) : (isAirDropTargeted ? accent : .white.opacity(0.90)))
                Text("AirDrop")
                    .font(.system(size: isWide ? 12 : 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(cardDisabled ? 0.44 : 0.96))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: isWide ? 10 : 9))
                    .foregroundStyle(
                        cardDisabled
                            ? Color.orange.opacity(0.82)
                            : (!actionableItems.isEmpty ? accent.opacity(0.95) : .white.opacity(0.46))
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 5)
                Spacer(minLength: 0)
            }
            .frame(width: cardWidth, height: 146)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isAirDropTargeted && !cardDisabled ? accent.opacity(0.18) : Color.white.opacity(cardDisabled ? 0.025 : 0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isAirDropTargeted && !cardDisabled
                                    ? accent
                                    : (cardDisabled ? Color.orange.opacity(0.28) : Color.white.opacity(0.09)),
                                lineWidth: isAirDropTargeted && !cardDisabled ? 1.2 : 0.6
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cardDisabled)
        .onDrop(of: [.fileURL], isTargeted: $isAirDropTargeted) { providers in
            handleAirDropProviders(providers)
        }
        .help(helpText)
        .accessibilityLabel("AirDrop, \(subtitle)")
        .accessibilityHint(helpText)
    }

    private func handleAirDropProviders(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let box = LockedURLBox()
        let group = DispatchGroup()
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier("public.file-url") else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    box.append(url)
                } else if let url = item as? URL {
                    box.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            let urls = box.values()
            if !urls.isEmpty {
                NotchSurfaceController.shared.airDropFileURLs(urls)
            }
        }
        return true
    }

    private func ref29DashedOverflowMenu(
        resolved: DropTrayActionResolution.Result<DropTrayStore.Item>,
        batchActions: [NotchActions.Action]
    ) -> some View {
        let targetActionable = resolved.targets
        return Menu {
            Button {
                pickFilesIntoTray()
            } label: {
                Label(L10n.t("Thêm tệp…"), systemImage: "plus")
            }
            if !store.items.isEmpty {
                Divider()
                Button {
                    model.traySelection.selectAll(store.items.map(\.id))
                } label: {
                    Label("\(L10n.t("Chọn tất cả")) (⌘A)", systemImage: "checkmark.circle")
                }
                if !model.traySelection.isEmpty {
                    Button {
                        model.traySelection.clear()
                    } label: {
                        Label(L10n.t("Bỏ chọn"), systemImage: "circle.slash")
                    }
                }
                Divider()
                Button {
                    NotchSurfaceController.shared.quickLookTrayItems(targetActionable)
                } label: {
                    Label("\(L10n.t("Xem nhanh")) (Space)", systemImage: "eye")
                }
                .disabled(targetActionable.isEmpty)

                Button {
                    NotchSurfaceController.shared.shareTrayItems(targetActionable)
                } label: {
                    Label(L10n.t("Chia sẻ"), systemImage: "square.and.arrow.up")
                }
                .disabled(targetActionable.isEmpty)

                if let paneName = DropTrayBrowserBridge.activePaneName {
                    Divider()
                    Button {
                        NotchSurfaceController.shared.sendTrayItemsToActivePane(targetActionable, copy: true)
                    } label: {
                        Label("\(L10n.t("Chép vào ngăn: "))\(paneName)", systemImage: "doc.on.doc")
                    }
                    .disabled(targetActionable.isEmpty)

                    Button {
                        NotchSurfaceController.shared.sendTrayItemsToActivePane(targetActionable, copy: false)
                    } label: {
                        Label("\(L10n.t("Chuyển vào ngăn: "))\(paneName)", systemImage: "folder")
                    }
                    .disabled(targetActionable.isEmpty)
                }

                if !batchActions.isEmpty {
                    Section(L10n.t("Xử lý hàng loạt")) {
                        ref29BatchActionMenuItems(batchActions)
                    }
                }

                Divider()
                Button {
                    NotchSurfaceController.shared.toggleDetail()
                } label: {
                    Label(L10n.t("Chi tiết"), systemImage: "square.grid.2x2")
                }

                Button(role: .destructive) {
                    store.clear()
                    model.traySelection.clear()
                    model.notice = nil
                    model.task = nil
                    model.ocrSummary = nil
                } label: {
                    Label(L10n.t("Xóa hết"), systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.60))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.t("Thao tác khay"))
        .accessibilityLabel(L10n.t("Thao tác khay"))
    }

    @ViewBuilder private func ref29BatchActionMenuItems(_ batchActions: [NotchActions.Action]) -> some View {
        ForEach(batchActions, id: \.self) { a in
            if case .resize = a {
                Menu {
                    ForEach(ImageEngine.resizePresets, id: \.self) { px in
                        Button("\(L10n.t("Thu nhỏ ảnh còn "))\(px) px") {
                            NotchSurfaceController.shared.run(.resize(maxPixels: px))
                        }
                    }
                } label: {
                    Label(title(a), systemImage: symbol(a))
                }
            } else {
                Button {
                    NotchSurfaceController.shared.run(a)
                } label: {
                    Label(title(a), systemImage: symbol(a))
                }
            }
        }
    }

    private func trayActionPill(
        title: String?,
        symbol: String,
        prominent: Bool = false,
        compact: Bool = false,
        enabled: Bool = true,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: compact ? 2.5 : 4) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 9 : 9.5, weight: .semibold))
                if let title {
                    Text(title)
                        .font(.system(size: compact ? 9.5 : 10.5, weight: prominent ? .semibold : .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(prominent ? Color.white : Color.white.opacity(enabled ? 0.88 : 0.4))
            .padding(.horizontal, compact ? 6 : (title == nil ? 7.5 : 8.5))
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(prominent ? accent : Color.white.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                            .strokeBorder(prominent ? Color.white.opacity(0.22) : Color.white.opacity(0.13), lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    @ViewBuilder private func ref29DashedZoneActionStrip(
        isWide: Bool,
        resolved: DropTrayActionResolution.Result<DropTrayStore.Item>,
        batchActions: [NotchActions.Action]
    ) -> some View {
        let compact = !isWide
        let targetActionable = resolved.targets
        let actionEnabled = !targetActionable.isEmpty
        let disabledReason = resolved.hasSelectionWithZeroActionable
            ? " — \(L10n.t("Mục chọn không khả dụng"))"
            : ""

        HStack(spacing: compact ? 3 : 4) {
            if !model.traySelection.isEmpty {
                Button {
                    model.traySelection.clear()
                } label: {
                    HStack(spacing: 3) {
                        Text(isWide ? "\(L10n.t("Đã chọn "))\(model.traySelection.count)" : "✓\(model.traySelection.count)")
                            .font(.system(size: compact ? 9.5 : 10, weight: .bold).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                    }
                    .foregroundStyle(resolved.hasSelectionWithZeroActionable ? .orange : accent)
                    .padding(.horizontal, compact ? 5 : 7)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                            .fill((resolved.hasSelectionWithZeroActionable ? Color.orange : accent).opacity(0.14))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(L10n.t("Bỏ chọn"))
                .accessibilityLabel("\(L10n.t("Bỏ chọn")) (\(model.traySelection.count))")
            }

            trayActionPill(
                title: L10n.t("Chia sẻ"),
                symbol: "square.and.arrow.up",
                prominent: actionEnabled,
                compact: compact,
                enabled: actionEnabled,
                helpText: "\(L10n.t("Chia sẻ"))\(disabledReason)"
            ) {
                NotchSurfaceController.shared.shareTrayItems(targetActionable)
            }

            trayActionPill(
                title: isWide ? L10n.t("Xem nhanh") : nil,
                symbol: "eye",
                compact: compact,
                enabled: actionEnabled,
                helpText: "\(L10n.t("Xem nhanh"))\(disabledReason)"
            ) {
                NotchSurfaceController.shared.quickLookTrayItems(targetActionable)
            }

            if let paneName = DropTrayBrowserBridge.activePaneName {
                trayActionPill(
                    title: L10n.t("Chép"),
                    symbol: "doc.on.doc",
                    compact: compact,
                    enabled: actionEnabled,
                    helpText: "\(L10n.t("Chép vào ngăn: "))\(paneName)\(disabledReason)"
                ) {
                    NotchSurfaceController.shared.sendTrayItemsToActivePane(targetActionable, copy: true)
                }

                trayActionPill(
                    title: L10n.t("Chuyển"),
                    symbol: "folder",
                    compact: compact,
                    enabled: actionEnabled,
                    helpText: "\(L10n.t("Chuyển vào ngăn: "))\(paneName)\(disabledReason)"
                ) {
                    NotchSurfaceController.shared.sendTrayItemsToActivePane(targetActionable, copy: false)
                }
            } else if !batchActions.isEmpty {
                Menu {
                    ref29BatchActionMenuItems(batchActions)
                } label: {
                    HStack(spacing: compact ? 2.5 : 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: compact ? 9 : 9.5, weight: .semibold))
                        Text(L10n.t("Xử lý"))
                            .font(.system(size: compact ? 9.5 : 10.5, weight: .medium))
                            .lineLimit(1)
                            .fixedSize()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, compact ? 6 : 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                            .fill(Color.white.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L10n.t("Xử lý hàng loạt"))
                .accessibilityLabel(L10n.t("Xử lý hàng loạt"))
            }

            Spacer(minLength: 0)

            if isWide && model.traySelection.isEmpty {
                Button {
                    model.traySelection.selectAll(store.items.map(\.id))
                } label: {
                    Text(L10n.t("Chọn tất cả"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 5)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(L10n.t("Chọn tất cả"))
            }
        }
        .frame(height: 28)
    }

    // MARK: Batch action titles / symbols / result line (B2d)

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

/// Compact thumbnail + name + status tile inside the expanded Dynamic Island Drop Tray.
private struct NotchTrayFileCard: View {
    let item: DropTrayStore.Item
    let selected: Bool
    let accent: Color
    let dragPaths: [String]
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onQuickLook: () -> Void
    let onShare: () -> Void
    let onCopyToPane: () -> Void
    let onMoveToPane: () -> Void
    let onRemove: () -> Void

    @State private var thumb: NSImage?

    var body: some View {
        let url: URL = URL(fileURLWithPath: item.path)
        let traits: AccessibilityTraits = selected ? [.isButton, .isSelected] : .isButton
        return cardTileCore
            .contentShape(Rectangle())
            .onTapGesture(perform: onClick)
            .contextMenu { cardContextMenu(url: url) }
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(helpText)
            .accessibilityAddTraits(traits)
            .accessibilityAction { onClick() }
            .task(id: item.path) {
                await refreshThumbnail(url: url)
            }
    }

    private var cardTileCore: some View {
        let bgFill: Color = selected ? accent.opacity(0.28) : Color.white.opacity(0.07)
        let borderColor: Color = selected ? accent : Color.white.opacity(0.11)
        let borderWidth: CGFloat = selected ? 1.5 : 0.5
        return VStack(spacing: 3) {
            cardThumbnailBadge
            cardNameAndStatus
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(width: 82, height: 84)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bgFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .overlay {
            if !dragPaths.isEmpty {
                MultiFileDragSource(paths: dragPaths, onClick: onClick, onDoubleClick: onDoubleClick)
            }
        }
    }

    private var cardThumbnailBadge: some View {
        let isUnavailable: Bool = item.status.isUnavailable
        let badgeSymbol: String = isUnavailable ? "exclamationmark.triangle.fill" : "arrow.uturn.left.circle.fill"
        let badgeColor: Color = isUnavailable ? .red : .orange
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .frame(width: 28, height: 28)
            }
            if item.status != .ready {
                Image(systemName: badgeSymbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(badgeColor)
                    .padding(2)
                    .background(Circle().fill(Color.black.opacity(0.75)))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 44, height: 44)
        .opacity(isUnavailable ? 0.45 : 1)
    }

    @ViewBuilder private var cardNameAndStatus: some View {
        let isUnavailable: Bool = item.status.isUnavailable
        Text(item.name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(isUnavailable ? 0.55 : 0.92))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: 72)

        if let statusKey = item.status.statusKey {
            Text(L10n.t(statusKey))
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(isUnavailable ? .red : .orange)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 72)
        }
    }

    @ViewBuilder private func cardContextMenu(url: URL) -> some View {
        if item.status.isActionable {
            Button(L10n.t("Xem nhanh"), action: onQuickLook)
            Button(L10n.t("Mở")) { NSWorkspace.shared.open(url) }
            Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button(L10n.t("Chia sẻ"), action: onShare)
            if let paneName = DropTrayBrowserBridge.activePaneName {
                Divider()
                Button("\(L10n.t("Chép vào ngăn: "))\(paneName)", action: onCopyToPane)
                Button("\(L10n.t("Chuyển vào ngăn: "))\(paneName)", action: onMoveToPane)
            }
            Divider()
        }
        Button(L10n.t("Bỏ khỏi khay"), action: onRemove)
    }

    @MainActor
    private func refreshThumbnail(url: URL) async {
        guard item.status.isActionable else {
            thumb = nil
            return
        }
        thumb = await FileThumbnailer.thumbnail(for: url)
    }

    private var helpText: String {
        guard let key = item.status.statusKey else { return item.path }
        if let detail = item.status.failureDetail {
            return "\(item.name) — \(L10n.t(key)): \(detail)"
        }
        return "\(item.name) — \(L10n.t(key))"
    }
}

/// Drags every staged/selected file at once via `beginDraggingSession(with:)`. Distinguishes click vs
/// drag (4 pt threshold) when `onClick` is supplied, and notifies `NotchSurfaceController` so leaving
/// the pointer during a drag-out session never closes the tray.
struct MultiFileDragSource: NSViewRepresentable {
    let paths: [String]
    var onClick: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView()
        v.paths = paths
        v.onClick = onClick
        v.onDoubleClick = onDoubleClick
        return v
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.paths = paths
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
    }

    final class DragSourceView: NSView {
        var paths: [String] = []
        var onClick: (() -> Void)?
        var onDoubleClick: (() -> Void)?

        private var mouseDownEvent: NSEvent?
        private var mouseDownPoint: NSPoint = .zero
        private var startedDrag = false

        override func mouseDown(with event: NSEvent) {
            startedDrag = false
            mouseDownEvent = event
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            if onClick == nil {
                startDragSession(with: event)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !startedDrag else { return }
            let current = convert(event.locationInWindow, from: nil)
            let dx = current.x - mouseDownPoint.x
            let dy = current.y - mouseDownPoint.y
            guard (dx * dx + dy * dy) >= 16 else { return }   // 4 pt threshold
            startedDrag = true
            startDragSession(with: mouseDownEvent ?? event)
        }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownEvent = nil; startedDrag = false }
            guard !startedDrag else { return }
            if event.clickCount >= 2, let onDoubleClick {
                onDoubleClick()
            } else {
                onClick?()
            }
        }

        private func startDragSession(with event: NSEvent) {
            let fm = FileManager.default
            let validPaths = paths.filter { fm.fileExists(atPath: $0) && fm.isReadableFile(atPath: $0) }
            guard !validPaths.isEmpty else { return }
            let items: [NSDraggingItem] = validPaths.enumerated().map { idx, path in
                let url = URL(fileURLWithPath: path) as NSURL
                let item = NSDraggingItem(pasteboardWriter: url)
                let icon = NSWorkspace.shared.icon(forFile: path)
                let offset = CGFloat(min(idx, 4)) * 3
                item.setDraggingFrame(NSRect(x: offset, y: offset, width: 44, height: 44), contents: icon)
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

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        MainActor.assumeIsolated {
            NotchSurfaceController.shared.beginDragOutSession()
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            NotchSurfaceController.shared.endDragOutSession()
        }
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
            .opacity(item.status.isUnavailable ? 0.45 : 1)

            Text(item.name)
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)

            if let statusKey = item.status.statusKey {
                Text(L10n.t(statusKey))
                    .font(.system(size: 9.5))
                    .foregroundColor(item.status.isUnavailable ? .red : .orange)
                    .lineLimit(1)
                    .frame(width: 66)
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(XFinderTokens.Fill.inset))
        .onDrag {
            guard item.status.isActionable else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            if item.status.isActionable {
                Button(L10n.t("Xem nhanh")) { NotchSurfaceController.shared.quickLookTrayItems([item]) }
                Button(L10n.t("Hiện trong Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button(L10n.t("Mở")) { NSWorkspace.shared.open(url) }
                Button(L10n.t("Chia sẻ")) { NotchSurfaceController.shared.shareTrayItems([item]) }
                if let paneName = DropTrayBrowserBridge.activePaneName {   // XF-T41: what the browser Shelf used to do
                    Divider()
                    Button("\(L10n.t("Chép vào ngăn: "))\(paneName)") { NotchSurfaceController.shared.sendTrayItemsToActivePane([item], copy: true) }
                    Button("\(L10n.t("Chuyển vào ngăn: "))\(paneName)") { NotchSurfaceController.shared.sendTrayItemsToActivePane([item], copy: false) }
                }
                Divider()
            }
            Button(L10n.t("Bỏ khỏi khay"), action: onRemove)
        }
        .help(item.status.statusKey.map { "\(item.path)\n\(L10n.t($0))" } ?? item.path)
        .task(id: item.path) {
            guard item.status.isActionable else { thumb = nil; return }
            thumb = await FileThumbnailer.thumbnail(for: url)
        }
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
                let h = max(2.5, CGFloat(l) * size.height)
                let r = CGRect(x: CGFloat(i) * (w + gap), y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(.white.opacity(0.92)))
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
            let playedWidth = max(4, g.size.width * frac)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.85), Color.white],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: playedWidth, height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: max(0, playedWidth - 4))
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

/// The volume / brightness bar on the notch (white on black, like the system square it replaces). Drawn as two
/// capsules so a new level animates with `XFinderTokens.Notch.level` and nothing else; AppKit's progress indicator
/// (the old `ProgressView`) moved on its own timing and read as a stutter under fast key repeat.
private struct NotchLevelBar: View {
    let level: Double
    var width: CGFloat = 90
    var height: CGFloat = 5
    var body: some View {
        let clamped = min(max(level, 0), 1)
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.18))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color.white],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * clamped)
        }
        .frame(width: width, height: height)
        .animation(XFinderTokens.Notch.level, value: clamped)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((clamped * 100).rounded()))%"))
    }
}

private final class LockedURLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func append(_ u: URL) { lock.lock(); urls.append(u); lock.unlock() }
    func values() -> [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}
