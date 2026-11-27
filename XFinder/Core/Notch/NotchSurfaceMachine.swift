import Foundation

/// The pure state machine of the Notch surface. Job: *"the tray opens when I mean it to — a file
/// drag reaching the notch, a shake, a deliberate hover over files I am holding, a click — and gets
/// out of the way otherwise, without ever losing what I staged."*
///
/// Every rule lives here with no AppKit, so the ways this feature failed before are each pinned by
/// a test: opening on any drag, opening an empty tray on hover, never closing, and throwing away
/// the files the user just dropped.
enum NotchSurfaceMachine {

    /// N3 agents · N4 calendar · P2 timer + aiUsage (toolbar tools, like the calendar).
    enum Page: String, Equatable, Codable, CaseIterable { case files, clipboard, nowPlaying, agents, calendar, timer, aiUsage }

    enum State: Equatable {
        /// Nothing drawn — except, when files are held on a notched screen, a count badge under the notch.
        case collapsed
        /// A compact strip under the notch: file count, a drag handle, click to open.
        case peek
        /// The full surface with a page.
        case expanded(Page)
        /// A live activity (B4): a short notice under the notch. Only replaces `collapsed`; it ends on
        /// its own timer, never because the pointer is elsewhere (it usually is).
        case activity

        var isOpen: Bool { if case .collapsed = self { return false }; return true }
        /// Collapsed or showing a notice — i.e. the user has not opened anything.
        var isIdle: Bool { self == .collapsed || self == .activity }
    }

    /// Where the open surface lives. A shake opens it where the hand already is (ShakePin), so an
    /// in-flight drag has the shortest way to go; every other trigger opens it at the notch.
    enum Anchor: Equatable { case notch, pointer }

    struct Settings: Equatable {
        var enabled = true
        var hoverToPeek = true
        /// N2: what a dwelt hover opens — `.peek` (files / track only, the B1 rule) or a hub page, decided by
        /// `NotchHoverOpen` from the activity below. Replaces B5's one-case Bool (`hoverOpensClipboard`).
        var hoverOpens: NotchHoverOpen = .peek
        /// N3: a Claude Code session is waiting for the person (feeds `.activity`).
        var agentNeedsYou = false
        /// The hub page that was open last (feeds `.lastPage`).
        var lastPage: Page? = nil
        /// The user's page order; a hover never opens a hidden page.
        var shownPages: [Page] = NotchPages.defaultOrder
        /// XF-ISLAND-C: true when every Island destination is hidden or unavailable.
        /// Hover must not open a dead hub, while file drag/drop intake remains active.
        var allDestinationsHidden = false
        /// B6: a track is known (and the Now Playing switch is on). Hover may then peek it even with no
        /// files held — a playing track is never "empty" — and the peek survives the tray emptying.
        var nowPlayingActive = false
        /// §3b #33: the notice on screen has buttons — a hover must not replace it.
        var activityHoldsHover = false
        /// P6: the person is typing a reply to an agent session on the Agents page. Like a running task, the hub does not
        /// collapse on its own while this holds — a pointer drifting off the notch must not throw the half-typed text away.
        /// Esc, ✕ and sending end it. A fact (re-read on every event), not an event, so the exhaustive walk is unchanged.
        var composing = false
        /// Active file drag-in, drop-hover, async drop import, or drag-out session: leaving the pointer
        /// away mid-drag must never collapse the tray while a drag is in progress.
        var dragging = false
        /// Ref-29 Pin toggle: when pinned by the user, `pointerAway` never auto-collapses the hub;
        /// explicit `dismiss` or `disabled` still closes it.
        var pinned = false
        /// P10 — `notch.agentEdgeHover`: pointing at the agent wing opens the Agents page.
        var agentEdgeHover = false
        /// P10 — a fact, like `nowPlayingActive`: the pointer is over the agent item of the collapsed left wing.
        var pointerOnAgentEdge = false
        var dragIntoNotchOpens = true
        var shakeOpens = true
        /// Pointer must rest in the notch zone this long before hover counts (accidental passes are shorter).
        var hoverDwell: TimeInterval = 0.14

        /// B7: the "Độ nhạy rê chuột" picker. Unknown values read as medium, never as 0.
        static func hoverDwell(forSpeed speed: String) -> TimeInterval {
            switch speed {
            case "fast": return 0.06
            case "slow": return 0.35
            default: return 0.14
            }
        }
        /// Pointer must be away this long before the surface collapses.
        var leaveGrace: TimeInterval = 0.38
    }

    enum Event: Equatable {
        /// Pointer is inside the notch hover zone (no button down). `since` = when it entered.
        case hoverInZone(since: Date)
        /// Pointer left both the zone and the open surface. `since` = when it left.
        case pointerAway(since: Date)
        /// Pointer is over the open surface — keeps it open.
        case pointerOnSurface
        /// A drag that carries FILES entered the notch drag zone.
        case fileDragInZone
        /// A shake gesture was detected during a file drag.
        case shake
        /// Deliberate open: a click on the badge / peek strip, or the Finder-extension URL.
        case activate
        /// A tab in the open hub (B5). Only changes the page of an EXPANDED surface — never opens one.
        case switchPage(Page)
        /// Deliberate open straight ONTO a page (⌘⇧V → clipboard, badge click → Now Playing). One
        /// transition: `activate` + `switchPage` rendered the 440-pt tray first and let the wider hub grow
        /// from the tray's origin — measured 2026-10-12 as a window at x 649 that jumped to x 488.
        case activateOn(Page)
        /// XF-ISLAND-C: Open or switch to an inline extra module (including `.sections` gallery) under machine authority.
        case openExtra(NotchExtraModule)
        /// XF-ISLAND-C: Close the active extra module and return to the expanded page.
        case closeExtra
        /// XF-ISLAND-C: Deliberately open the all-hidden recovery surface so the user can always reach Settings.
        case openAllHiddenRecovery
        /// XF-ISLAND-C: Reconcile when the active page or extra module is hidden/unconfigured in Settings.
        /// Preserves active file drag or running file tasks on `.files`; otherwise falls back to `fallback`
        /// or enters all-hidden recovery when `fallback == nil`.
        case reconcileVisibility(fallback: NotchGalleryDestination?, allowAllHiddenRecovery: Bool)
        /// Files were dropped onto the surface; `count` is the tray's new total.
        case dropped(count: Int)
        /// The tray's item count changed elsewhere (the Khay thả page, "Xóa hết", the extension).
        case itemsChanged(count: Int)
        /// A hub action started / ended (B2d). While one runs the surface does not collapse on its own,
        /// or its progress would vanish mid-job.
        case taskStarted
        case taskEnded
        /// A live activity is ready / its time is up.
        case activityShown
        case activityEnded
        /// Key feedback (volume / brightness) is ready. Unlike a notice it also replaces a PEEK — the peek is passive
        /// (a hover, a playing track) and the key was swallowed, so this is the only answer the person gets. It never
        /// takes over the open hub: there the key is passed to macOS instead (`canShowKeyFeedback`).
        case feedbackShown
        /// The close button.
        case dismiss
        /// The feature was switched off.
        case disabled
    }

    struct Machine: Equatable {
        var state: State = .collapsed
        var anchor: Anchor = .notch
        var itemCount = 0
        var taskRunning = false
        /// XF-ISLAND-C: Active inline extra module (or `.sections` gallery) owned by the machine so lifecycle
        /// transitions, fallback, and lazy-module cleanup have a single authority.
        var activeExtra: NotchExtraModule? = nil
        /// XF-ISLAND-C: True while the expanded surface is showing the always-accessible Settings recovery card
        /// because all user destinations are hidden or unconfigured.
        var showingAllHiddenRecovery = false
        /// Key feedback replaced a PEEK: when it ends the peek comes back, if it still has files or a track to show. It
        /// went to `collapsed` — the Now Playing strip the person was looking at vanished after one volume press, until the
        /// pointer moved again. Only meaningful while the state is `.activity`; cleared on every other state.
        var peekUnderFeedback = false

        /// Advance. `now` makes dwell/grace decisions deterministic.
        mutating func handle(_ e: Event, settings s: Settings, now: Date) {
            defer { if state != .activity { peekUnderFeedback = false } }
            guard s.enabled else { collapse(); return }
            switch e {
            case .disabled, .dismiss:
                collapse()
            case .activityShown:
                if state.isIdle { state = .activity; anchor = .notch }   // never interrupts a peek or the hub
            case .feedbackShown:
                if state == .peek { peekUnderFeedback = true }
                if state.isIdle || state == .peek { state = .activity; anchor = .notch }
            case .activityEnded:
                guard state == .activity else { return }
                state = peekUnderFeedback && (itemCount > 0 || s.nowPlayingActive) ? .peek : .collapsed
            case .taskStarted:
                taskRunning = true
            case .taskEnded:
                taskRunning = false
            case .activate:
                if case .expanded = state { return }
                open(at: .notch)
            case .activateOn(let page):
                activeExtra = nil
                showingAllHiddenRecovery = false
                if case .expanded = state { state = .expanded(page); return }   // already open ⇒ just the page, keep the anchor
                open(at: .notch, page: page)
            case .switchPage(let page):
                if case .expanded = state {
                    activeExtra = nil
                    showingAllHiddenRecovery = false
                    state = .expanded(page)
                }
            case .openExtra(let extra):
                showingAllHiddenRecovery = false
                if case .expanded = state {
                    activeExtra = extra
                } else {
                    open(at: .notch, page: s.shownPages.first ?? .files)
                    activeExtra = extra
                }
            case .closeExtra:
                activeExtra = nil
            case .openAllHiddenRecovery:
                activeExtra = nil
                showingAllHiddenRecovery = true
                if case .expanded = state {
                    state = .expanded(.files)
                } else {
                    open(at: .notch, page: .files)
                    showingAllHiddenRecovery = true
                }
            case .reconcileVisibility(let fallback, let allowAllHiddenRecovery):
                guard case .expanded(let currentPage) = state else {
                    activeExtra = nil
                    showingAllHiddenRecovery = false
                    return
                }
                // Preserve automatic file drop intake and active drag / running file task on `.files`.
                if currentPage == .files && activeExtra == nil && (s.dragging || taskRunning) {
                    showingAllHiddenRecovery = false
                    return
                }
                if let fallback {
                    showingAllHiddenRecovery = false
                    switch fallback {
                    case .page(let p):
                        activeExtra = nil
                        state = .expanded(p)
                    case .extra(let e):
                        activeExtra = e
                    }
                } else if allowAllHiddenRecovery {
                    activeExtra = nil
                    showingAllHiddenRecovery = true
                    state = .expanded(.files)
                } else {
                    collapse()
                }
            case .fileDragInZone:
                guard s.dragIntoNotchOpens else { return }
                // A tray already open at the pointer stays put: moving it under a live drag would
                // pull the target away from the hand.
                if case .expanded = state, anchor == .pointer {
                    activeExtra = nil
                    showingAllHiddenRecovery = false
                    state = .expanded(.files)
                    return
                }
                open(at: .notch)                     // also from .activity: the notice yields
            case .shake:
                guard s.shakeOpens else { return }
                if case .expanded = state { return }
                open(at: .pointer)
            case .dropped(let n):
                itemCount = n
                activeExtra = nil
                showingAllHiddenRecovery = false
                state = .expanded(.files)           // dropping is the START of the task — stay open
            case .itemsChanged(let n):
                itemCount = n
                // The peek shows held files or the playing track; with neither left it has nothing to say.
                if n == 0, state == .peek, !s.nowPlayingActive { collapse() }
            case .hoverInZone(let since):
                guard s.hoverToPeek, state.isIdle, now.timeIntervalSince(since) >= s.hoverDwell else { return }
                if state == .activity && s.activityHoldsHover { return }   // the pointer came to press a button
                if s.allDestinationsHidden { return }                      // all tabs hidden ⇒ hover never pops a dead hub
                // P10: pointing at the agent's own wing opens the agents, whatever "hover opens" says elsewhere.
                if s.agentEdgeHover, s.pointerOnAgentEdge, s.shownPages.contains(.agents) {
                    open(at: .notch, page: .agents)
                    return
                }
                let activity = NotchHoverOpen.Activity(itemCount: itemCount, trackPlaying: s.nowPlayingActive,
                                                       agentNeedsYou: s.agentNeedsYou, lastPage: s.lastPage)
                if let page = s.hoverOpens.page(for: activity, shown: s.shownPages) {
                    open(at: .notch, page: page)         // N2: clips / agents / the player are never "empty"
                } else if (itemCount > 0 && s.shownPages.contains(.files)) || (s.nowPlayingActive && s.shownPages.contains(.nowPlaying)) {
                    // Hover reveals files already held, or the track that is playing — never an empty
                    // tray (CLAUDE.md Part 3c).
                    state = .peek
                    anchor = .notch
                }
            case .pointerOnSurface:
                break                               // whatever is open stays open
            case .pointerAway(let since):
                guard state.isOpen, state != .activity, now.timeIntervalSince(since) >= s.leaveGrace else { return }
                guard activeExtra != .settings else { return }
                if taskRunning || s.composing { return }
                if s.dragging { return }
                if s.pinned { return }
                // The shaken-open tray holding files never auto-closes: the user dropped them to
                // act on them next, and a tray that vanished mid-task was a reported bug. At the
                // notch the files are not lost either — the collapsed badge keeps showing them.
                if case .expanded = state, anchor == .pointer, itemCount > 0 { return }
                collapse()
            }
        }

        private mutating func open(at a: Anchor, page: Page = .files) {
            state = .expanded(page)
            anchor = a
            activeExtra = nil
            showingAllHiddenRecovery = false
        }

        private mutating func collapse() {
            state = .collapsed
            anchor = .notch
            activeExtra = nil
            showingAllHiddenRecovery = false
        }
    }
}
