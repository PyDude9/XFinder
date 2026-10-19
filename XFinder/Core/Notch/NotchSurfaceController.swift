import AppKit
import AVFoundation
import LocalAuthentication
import NaturalLanguage
import SwiftUI

/// The Notch surface — one floating surface that lives at the notch (or the top centre of a screen
/// without one). Phase B1 hosts the file shelf (Khay thả); later phases add pages to it.
///
/// Three states, decided by the pure `NotchSurfaceMachine`: collapsed (nothing, or a count badge
/// while files are held), peek (strip under the notch) and expanded (the hub). Triggers:
/// * a FILE drag reaching the notch drag zone (`dropTray.notchDropEnabled`),
/// * a shake during a file drag — opens the hub at the pointer, ShakePin-style (`dropTray.shakeEnabled`),
/// * resting on the notch while files are held (`dropTray.hoverEnabled`),
/// * a click on the badge / peek strip, or `reveal()` from the Finder-extension URL.
///
/// Every drag-based path asks `NotchDragSession` whether THIS press is a file drag; the drag
/// pasteboard keeps old file types forever, so reading its types alone opened the tray for window
/// and text drags (measured — see that type).
///
/// Cost model: one global + one local NSEvent monitor (the mandatory pair — a global monitor goes
/// silent while any XFinder window is frontmost) that fire only on real pointer activity. The only
/// timers are one-shot work items (hover dwell, leave grace, shrink) alive while that state is
/// live. No polling. Feature off ⇒ no monitors, no panel, nothing on screen.
@MainActor
@Observable
final class NotchSurfaceController {
    static let shared = NotchSurfaceController()

    /// SwiftUI-facing state; the view reads this, never the machine.
    let model = NotchSurfaceModel()
    private(set) var state: NotchSurfaceMachine.State = .collapsed

    private var machine = NotchSurfaceMachine.Machine()
    private var panel: SurfacePanel?
    private var detailPanel: NSPanel?
    private var monitors: [Any] = []
    /// The screen the open surface is on; set when it opens, kept until it collapses.
    private var surfaceScreen: NSScreen?
    /// Where the pointer was when a shake opened the tray (the pointer anchor's reference point).
    private var shakePoint: CGPoint = .zero
    /// The anchor the panel is currently drawn at; an anchor change jumps instead of animating.
    private var renderedAnchor: NotchSurfaceMachine.Anchor = .notch

    // Drag / shake tracking — only populated while the left button is down.
    private var dragSession = NotchDragSession(currentChangeCount: NSPasteboard(name: .drag).changeCount)
    private var samples: [(point: CGPoint, time: Date)] = []
    // Hover / leave tracking.
    private var zoneEnteredAt: Date?
    private var leftAt: Date?
    private var dwellWork: DispatchWorkItem?
    private var graceWork: DispatchWorkItem?

    private init() {
        machine.itemCount = DropTrayStore.shared.items.count
        DropTrayStore.shared.onItemsChanged = { [weak self] count in
            self?.dispatch(.itemsChanged(count: count))
        }
    }

    // MARK: Settings (read at point of use — canonical form, see FeatureKeyDefaultsTests)

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "dropTray.notchEnabled") as? Bool ?? true
    }
    /// Resting on the notch while files are held peeks them.
    private var hoverEnabled: Bool {
        UserDefaults.standard.object(forKey: "dropTray.hoverEnabled") as? Bool ?? true
    }
    /// Dragging files into the notch opens the hub there.
    private var notchDropEnabled: Bool {
        UserDefaults.standard.object(forKey: "dropTray.notchDropEnabled") as? Bool ?? true
    }
    /// B5: resting on the notch with NO files held opens the clipboard page. Off by default.
    /// N2 — the ONE reader of `notch.hoverOpens` (what a dwelt hover opens). The D1 Bool it replaces is migrated
    /// once in `applySettings()`.
    private var hoverOpensRaw: String { UserDefaults.standard.string(forKey: "notch.hoverOpens") ?? "peek" }
    /// The hub page that was open last, for `NotchHoverOpen.lastPage`.
    private var lastHubPage: NotchSurfaceMachine.Page?
    /// B7: keep the surface out of screenshots, recordings and screen sharing (`NSWindow.sharingType = .none`;
    /// measured as `kCGWindowSharingState = 0`). OFF by default since 2026-10-14: the owner could not screenshot
    /// the notch; hiding it is an opt-in for people who share their screen.
    private var hideFromCapture: Bool {
        UserDefaults.standard.object(forKey: "notch.hideFromCapture") as? Bool ?? false
    }
    /// B7: on a screen without a notch, draw the collapsed state as a pill under the menu bar.
    private var pillOnPlainScreens: Bool {
        UserDefaults.standard.object(forKey: "notch.pillOnPlainScreens") as? Bool ?? true
    }
    /// B7: "fast" | "medium" | "slow" — how long the pointer must rest before a hover counts.
    private var hoverSpeed: String {
        UserDefaults.standard.string(forKey: "notch.hoverSpeed") ?? "medium"
    }
    /// Shaking a file drag opens the hub at the pointer.
    private var shakeEnabled: Bool {
        UserDefaults.standard.object(forKey: "dropTray.shakeEnabled") as? Bool ?? true
    }
    /// "low" | "medium" | "high" — how many reversals a shake needs.
    private var reversalsNeeded: Int {
        switch UserDefaults.standard.string(forKey: "dropTray.shakeSensitivity") ?? "medium" {
        case "low": return 6
        case "high": return 3
        default: return 4
        }
    }
    private var settings: NotchSurfaceMachine.Settings {
        NotchSurfaceMachine.Settings(enabled: enabled, hoverToPeek: hoverEnabled, hoverOpens: NotchHoverOpen.parse(hoverOpensRaw),
                                     agentNeedsYou: model.agentsNeedingYou > 0, lastPage: lastHubPage, shownPages: model.pages,
                                     nowPlayingActive: NowPlayingMonitor.shared.hasTrack,
                                     activityHoldsHover: !(model.activity?.buttons.isEmpty ?? true),
                                     composing: model.agentReplyTarget != nil || model.newWindowlessOpen,
                                     agentEdgeHover: agentEdgeHover, pointerOnAgentEdge: pointerOnAgentEdge,
                                     dragIntoNotchOpens: notchDropEnabled, shakeOpens: shakeEnabled,
                                     hoverDwell: NotchSurfaceMachine.Settings.hoverDwell(forSpeed: hoverSpeed))
    }

    /// Something is on the collapsed surface (badge or pill): files, a countdown, a track.
    private var badgeShown: Bool { machine.itemCount > 0 || countdown != nil || NowPlayingMonitor.shared.hasTrack || model.agentActive }

    /// P10 — the ONE reader of `notch.agentEdgeHover` (OneNotch's "AI edge": point at the agent wing to open the agents).
    private var agentEdgeHover: Bool { UserDefaults.standard.object(forKey: "notch.agentEdgeHover") as? Bool ?? true }
    /// P10 — set on every pointer tick, read by the machine through `settings`.
    private var pointerOnAgentEdge = false

    /// D1 #44 — the ONE reader of `notch.pages` (order + visibility, a comma list).
    private var pageOrderRaw: String { UserDefaults.standard.string(forKey: "notch.pages") ?? "files,clipboard,nowPlaying,agents,calendar,timer,aiUsage" }
    /// D1 #47 — the ONE reader of `notch.accent`.
    private var accentName: String { UserDefaults.standard.string(forKey: "notch.accent") ?? "system" }
    /// For the ⌘⇧V router: a hidden clipboard tab means the hotkey falls back to the floating shelf.
    var showsClipboardPage: Bool { model.pages.contains(.clipboard) }

    func applySettings() {
        // N2 migration: a D1 user who turned "hover opens the clipboard" on keeps that behaviour under the new key.
        let d = UserDefaults.standard
        if d.string(forKey: NotchHoverOpen.key) == nil, d.object(forKey: NotchHoverOpen.legacyKey) as? Bool == true {
            d.set(NotchHoverOpen.migrated(raw: nil, legacyClipboard: true).rawValue, forKey: NotchHoverOpen.key)
        }
        if enabled {
            start()
            panel?.sharingType = hideFromCapture ? .none : .readOnly   // B7, live
            model.pillOnPlainScreens = pillOnPlainScreens
            model.pages = NotchPages.parse(pageOrderRaw)
            model.timerDraftMinutes = timerDraftMinutes          // P2: the Hẹn giờ page's idle minutes
            model.accent = NotchAccent.rgb(named: accentName).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
            if case .expanded(let page) = machine.state, !model.pages.contains(page) {
                dispatch(.switchPage(NotchPages.resolve(page, shown: model.pages)))   // the open page was just hidden
            }
            render()
            NowPlayingMonitor.shared.applySettings()      // B6: its own switch, under the master
            AgentSessionMonitor.shared.applySettings(underMaster: true)   // N3: its own switch, under the master
            CalendarGlanceMonitor.shared.applySettings(underMaster: true)  // N4: same
            model.calendarEnabled = CalendarGlanceMonitor.shared.isEnabled
            calendarChanged()
            model.agentsEnabled = AgentSessionMonitor.shared.isEnabled
            model.agents = AgentSessionMonitor.shared.sessions
            refreshAgentHookStatus()
        } else {
            stop()
            AgentSessionMonitor.shared.applySettings(underMaster: false)
            CalendarGlanceMonitor.shared.applySettings(underMaster: false)
        }
    }

    private func start() {
        if panel == nil { prepare() }
        NowPlayingMonitor.shared.onChange = { [weak self] in self?.nowPlayingChanged() }
        AgentSessionMonitor.shared.onChange = { [weak self] in self?.agentsChanged() }
        CrewManager.shared.onCapReached = { [weak self] id in self?.presentCrewNotice(crewID: id) }
        CrewManager.shared.startIfNeeded()          // P7b: the relay listens to windowless sessions; stale crew folders go
        AgentTalkSender.shared.onChange = { [weak self] in self?.agentRepliesChanged() }
        CalendarGlanceMonitor.shared.onChange = { [weak self] in self?.calendarChanged() }
        if monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                let type = event.type
                runOnMainActor { self?.handle(type) }
            }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                let type = event.type
                MainActor.assumeIsolated { self?.handle(type) }
                return event   // a local monitor must return the event or it swallows the input
            }) {
                monitors.append(local)
            }
            dragSession = NotchDragSession(currentChangeCount: NSPasteboard(name: .drag).changeCount)
        }
        render()   // a tray that already holds files shows its badge right away
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        cancelWork()
        if let m = clipboardKeyMonitor { NSEvent.removeMonitor(m); clipboardKeyMonitor = nil }
        if let m = swipeMonitor { NSEvent.removeMonitor(m); swipeMonitor = nil }
        activityWork?.cancel(); activityWork = nil
        activityQueue.clear()
        countdownTicker?.invalidate(); countdownTicker = nil; countdown = nil
        model.timerText = nil; model.timer = nil
        NowPlayingMonitor.shared.stop()
        nowPlayingTicker?.invalidate(); nowPlayingTicker = nil
        model.nowPlaying = nil; model.nowPlayingArtwork = nil; model.nowPlayingPosition = nil
        model.nowPlayingAvailability = .off
        samples.removeAll()
        machine.handle(.disabled, settings: settings, now: Date())
        state = machine.state
        // P6 review: stop() bypasses dispatch(), so a reply being composed when the notch is switched off must be
        // ended here, or its Esc monitor stays installed and the stale draft comes back with the notch.
        model.agentReplyTarget = nil
        model.agentReplyText = ""
        model.newWindowlessOpen = false
        model.newWindowlessText = ""
        model.crewBoard = nil      // P7b review: like the other transient Agents-page states
        syncAgentReplyKeyboard()
        panel?.hide()
        panel = nil
        detailPanel?.orderOut(nil)
    }

    // MARK: Public intents

    /// Deliberate open: badge / peek click, or the Finder-extension URL. `page` lands on that page.
    func reveal(page: NotchSurfaceMachine.Page = .files) {
        if !state.isOpen { surfaceScreen = WindowManager.screenUnderPointer() }
        dispatch(.activateOn(NotchPages.resolve(page, shown: model.pages)))   // ONE transition — see the machine's note on activateOn
    }

    /// A tab in the open hub (B5). A hidden page (D1 #44) resolves to the first shown one.
    func switchPage(_ page: NotchSurfaceMachine.Page) { dispatch(.switchPage(NotchPages.resolve(page, shown: model.pages))) }

    func dismiss() { dispatch(.dismiss) }

    /// The view calls this after files were dropped on the surface.
    func filesDropped() { dispatch(.dropped(count: DropTrayStore.shared.items.count)) }

    // MARK: Detection

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            dragSession.pressBegan(changeCount: NSPasteboard(name: .drag).changeCount)
            samples.removeAll()
        case .leftMouseUp:
            samples.removeAll()
        default:
            break
        }
        tick()
    }

    private func tick() {
        let point = NSEvent.mouseLocation
        let now = Date()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? WindowManager.screenUnderPointer()
        let notch = Self.notch(on: screen)
        let onSurface = (panel?.isVisible ?? false)
            && drawnFrame.insetBy(dx: -12, dy: -12).contains(point)   // N1: the drawn shape, never the (larger) window

        if NSEvent.pressedMouseButtons & 1 == 1 {
            // Never collapse mid-drag — the drag may come back; the leave clock restarts after the release.
            leftAt = nil; graceWork?.cancel(); graceWork = nil
            zoneEnteredAt = nil; dwellWork?.cancel(); dwellWork = nil
            // Neither drag trigger on ⇒ nothing to decide, so never touch the drag pasteboard (a
            // pasteboard-server round trip) on the user's window and text drags.
            let s = settings
            guard s.dragIntoNotchOpens || s.shakeOpens else { return }
            let pb = NSPasteboard(name: .drag)
            guard dragSession.carriesFiles(now: now, changeCount: { pb.changeCount },
                                           types: { (pb.types ?? []).map(\.rawValue) }) else { return }
            samples.append((point, now))
            let cutoff = now.addingTimeInterval(-0.6)          // keep ~0.6 s of movement for the shake
            samples.removeAll { $0.time < cutoff }
            if !state.isOpen { surfaceScreen = screen }
            if NotchSurfaceLayout.dragZone(notch: notch, screen: screen.frame).contains(point) {
                dispatch(.fileDragInZone)
            } else if detectShake() {        // the machine ignores a shake while already expanded
                samples.removeAll()
                shakePoint = point
                dispatch(.shake)
            }
            return
        }

        let zone = NotchSurfaceLayout.hoverZone(notch: notch, screen: screen.frame, itemCount: machine.itemCount,
                                                nowPlayingActive: NowPlayingMonitor.shared.hasTrack,
                                                timerActive: countdown != nil, agentActive: model.agentActive, agentBusy: model.agentBusy, agentCount: model.agentCount,
                                                visible: screen.visibleFrame,
                                                pillShown: pillOnPlainScreens && badgeShown && machine.state == .collapsed)
        let wings = NotchSurfaceLayout.wingItems(itemCount: machine.itemCount, timerActive: countdown != nil,
                                                 nowPlayingActive: NowPlayingMonitor.shared.hasTrack, agentActive: model.agentActive,
                                                 agentBusy: model.agentBusy, agentCount: model.agentCount)
        pointerOnAgentEdge = NotchSurfaceLayout.agentEdgeRect(notch: notch, left: wings.left, right: wings.right)?.contains(point) ?? false
        if zone.contains(point) {
            leftAt = nil; graceWork?.cancel(); graceWork = nil
            if zoneEnteredAt == nil {
                zoneEnteredAt = now
                armRetick(after: settings.hoverDwell, slot: \.dwellWork)
            }
            if !state.isOpen { surfaceScreen = screen }
            dispatch(.hoverInZone(since: zoneEnteredAt ?? now))
            return
        }
        zoneEnteredAt = nil; dwellWork?.cancel(); dwellWork = nil

        if onSurface {
            leftAt = nil; graceWork?.cancel(); graceWork = nil
            dispatch(.pointerOnSurface)
            return
        }
        guard state.isOpen else { return }
        if leftAt == nil {
            leftAt = now
            armRetick(after: settings.leaveGrace, slot: \.graceWork)
        }
        dispatch(.pointerAway(since: leftAt ?? now))
    }

    /// Dwell and grace are decided by the machine from timestamps, but the pointer may simply stop
    /// moving — so ONE one-shot item re-runs `tick()` once the interval has elapsed. It is cancelled
    /// the moment the pointer leaves the state that armed it.
    private func armRetick(after seconds: TimeInterval,
                           slot: ReferenceWritableKeyPath<NotchSurfaceController, DispatchWorkItem?>) {
        self[keyPath: slot]?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        self[keyPath: slot] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.03, execute: work)
    }

    private func cancelWork() {
        zoneEnteredAt = nil; leftAt = nil
    }

    /// A shake is N horizontal direction reversals with enough travel.
    private func detectShake() -> Bool {
        guard samples.count >= 6 else { return false }
        var reversals = 0
        var lastSign = 0
        for i in 1..<samples.count {
            let dx = samples[i].point.x - samples[i - 1].point.x
            guard abs(dx) > 6 else { continue }
            let sign = dx > 0 ? 1 : -1
            if lastSign != 0, sign != lastSign { reversals += 1 }
            lastSign = sign
        }
        return reversals >= reversalsNeeded
    }

    private static func notch(on screen: NSScreen) -> CGRect {
        NotchSurfaceLayout.notch(screen: screen.frame,
                                 auxLeft: screen.auxiliaryTopLeftArea,
                                 auxRight: screen.auxiliaryTopRightArea)
    }

    /// The badge prefers a screen that HAS a notch: on a notch-less screen there is nothing to hang it from.
    private static var notchedScreen: NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
    }

    // MARK: Machine → screen

    private func dispatch(_ event: NotchSurfaceMachine.Event) {
        let before = machine
        machine.handle(event, settings: settings, now: Date())
        guard machine != before else { return }
        state = machine.state
        if case .expanded(let p) = machine.state { lastHubPage = p }   // N2: for "Trang mở lần cuối"
        CalendarGlanceMonitor.shared.setPageOpen(machine.state == .expanded(.calendar))   // N4: the minute ticker only while shown
        // §3b #37 / P2: the usage scan runs only while the Agents page or the AI usage tool is on screen.
        AgentUsageMonitor.shared.setPageOpen(machine.state == .expanded(.agents) || machine.state == .expanded(.aiUsage))
        AgentSessionMonitor.shared.setAgentsPageOpen(machine.state == .expanded(.agents))
        if machine.state != .expanded(.agents), model.agentReplyTarget != nil { endAgentReply() }   // P6: leaving the page ends composing
        if machine.state != .expanded(.agents), model.newWindowlessOpen { cancelNewWindowless() }   // P7a: same for the composer
        render()
        syncClipboardKeyboard()
        syncAgentReplyKeyboard()
        syncHubSwipe()
        syncNowPlayingTicker()
        syncWaveform()
    }

    /// §3b #21 — the tap runs only while a waveform is on screen (the Now Playing page, or the peek showing the track).
    func syncWaveform() {
        let shown = machine.state == .expanded(.nowPlaying) || (machine.state == .peek && machine.itemCount == 0)
        AudioTapMonitor.shared.update(waveformVisible: shown)
    }

    // MARK: - D1 #43: two-finger swipe over the tab band changes page

    private var swipeMonitor: Any?
    private var swipe = NotchPages.SwipeAccumulator()

    /// A LOCAL scroll-wheel monitor only while the hub is open. Scroll events reach the window under the
    /// pointer whether or not it is key, so the local monitor sees them without making the panel key.
    /// Only the top band (tabs / search) is a swipe area — the clipboard deck and chip row scroll
    /// sideways themselves and must keep their gesture.
    private func syncHubSwipe() {
        if case .expanded = machine.state {
            guard swipeMonitor == nil else { return }
            swipe.reset()
            swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let panel = self.panel, e.window === panel else { return e }
                if e.phase == .ended || e.phase == .cancelled || e.momentumPhase == .ended { self.swipe.reset(); return e }
                let bandTop = self.drawnFrame.maxY - panel.frame.minY          // N1: the drawn shape's top, in window space
                // P1: every page's dots sit IN the 32-pt band now, so the band is the whole swipe area. (It used to
                // reach 28 pt lower for the old tab row — on the clipboard hub that swallowed the chip row's scroll.)
                let bandBottom = bandTop - max(self.model.notchSize.height, 32)
                guard e.locationInWindow.y >= bandBottom, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { return e }
                if let dir = self.swipe.feed(deltaX: e.scrollingDeltaX),
                   case .expanded(let page) = self.machine.state,
                   let next = NotchPages.swipeTarget(from: page, direction: dir, pages: self.model.pages) {   // P1: the dots are the sequence; a tool does not swipe
                    self.switchPage(next)
                }
                return nil
            }
        } else if let m = swipeMonitor {
            NSEvent.removeMonitor(m)
            swipeMonitor = nil
        }
    }

    // MARK: - Now Playing (B6)

    // MARK: - Calendar glance (N4)

    private func calendarChanged() {
        let m = CalendarGlanceMonitor.shared
        model.calendarEvents = m.events + m.reminders
        model.calendarAccess = m.eventAccess
        model.calendarHidesAllDay = m.hidesAllDay
    }

    func requestCalendarAccess() { CalendarGlanceMonitor.shared.requestAccess() }
    func openCalendar(on day: Date) { CalendarGlanceMonitor.shared.openCalendarApp(on: day) }

    // MARK: - AI agent sessions (N3)

    /// The monitor rebuilt its sessions: mirror them and redraw (the tab badge counts those waiting for you).
    private func agentsChanged() {
        model.agents = AgentSessionMonitor.shared.sessions
        model.recentAgents = AgentSessionMonitor.shared.recent
        refreshAgentHookStatus()      // OpenCode found / missing is learnt when its monitor starts
        // P6: the session being replied to left the list — end composing, or `Settings.composing` would hold the hub open
        // with no compose bar (and no ✕) on screen.
        // P7a: a conversation whose session left the list closes too — otherwise it reopens by itself when the row returns.
        if let id = model.windowlessConversation, !model.agents.contains(where: { $0.listID == id }) { model.windowlessConversation = nil }
        // P7b review: a board whose crew is gone (forgotten from Settings, say) closes instead of lingering as state.
        if let id = model.crewBoard, !CrewManager.shared.crews.contains(where: { $0.id == id }) { model.crewBoard = nil }
        if let id = model.agentReplyTarget, !model.agents.contains(where: { $0.listID == id }) { endAgentReply(); return }
        render()
    }

    func refreshAgentHookStatus() {
        model.agentHookInstalled = AgentSessionMonitor.shared.anyHookInstalled
        model.agentsEnabled = AgentSessionMonitor.shared.isEnabled
        model.openCodeOn = OpenCodeMonitor.shared.isEnabled
        model.openCodeMissing = OpenCodeMonitor.shared.state == .binaryMissing
    }

    func answerAgent(_ p: AgentSession.PendingPermission, of session: AgentSession, allow: Bool) {
        AgentSessionMonitor.shared.answer(p, of: session, allow: allow)
    }

    /// P2: the AI usage tool's "set up %" link — the statusLine install lives on the Agent AI settings page (P3)
    /// (installing edits ~/.claude/settings.json, so it is a deliberate button there, never a switch on the notch).
    func openAgentSettings() {
        dismiss()
        AppState.shared.navigate(to: .aiAgents)
        AppState.shared.bringMainWindowFront()
    }

    func openAgentTerminal(_ session: AgentSession) {
        AgentSessionMonitor.shared.openTerminal(of: session)
    }

    // MARK: - Replies to agent sessions (P6)

    private var agentReplyKeyMonitor: Any?

    /// "Nhắn" on a row: the reply field opens under the list and takes the keyboard. The panel becomes key WITHOUT
    /// `NSApp.activate` (the clipboard page's rule); the hub stays open while composing (`Settings.composing`).
    func beginAgentReply(_ session: AgentSession) {
        model.agentReplyTarget = session.listID
        model.agentReplyText = ""
        render()
        syncAgentReplyKeyboard()
        model.agentReplyFocus += 1
    }

    func endAgentReply() {
        model.agentReplyTarget = nil
        model.agentReplyText = ""
        syncAgentReplyKeyboard()
        render()
    }

    /// Return in the field / the send button.
    func sendAgentReply() {
        guard let id = model.agentReplyTarget, let s = model.agents.first(where: { $0.listID == id }) else { endAgentReply(); return }
        guard AgentTalk.clean(model.agentReplyText) != nil else { return }     // Return on an empty field keeps it open
        AgentTalkSender.shared.send(model.agentReplyText, to: s)
        endAgentReply()
    }

    func cancelQueuedReply(_ session: AgentSession) { AgentTalkSender.shared.cancelQueued(for: session) }

    private func agentRepliesChanged() {
        model.agentReplyStatus = AgentTalkSender.shared.status
        model.agentReplyQueued = Set(AgentTalkSender.shared.outbox.keys)
        render()
    }

    /// Esc ends composing (a reply, or the P7a "new windowless session" composer). A LOCAL monitor is enough: it only
    /// matters while our panel is key.
    private func syncAgentReplyKeyboard() {
        if model.agentReplyTarget != nil || model.newWindowlessOpen, machine.state == .expanded(.agents) {
            panel?.makeKeyAndOrderFront(nil)
            guard agentReplyKeyMonitor == nil else { return }
            agentReplyKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.panel?.isKeyWindow == true,
                      self.model.agentReplyTarget != nil || self.model.newWindowlessOpen else { return e }
                if e.keyCode == 53 {                                                   // Esc
                    if self.model.agentReplyTarget != nil { self.endAgentReply() } else { self.cancelNewWindowless() }
                    return nil
                }
                return e
            }
        } else if let m = agentReplyKeyMonitor {
            NSEvent.removeMonitor(m)
            agentReplyKeyMonitor = nil
        }
    }

    // MARK: - Windowless sessions (P7a)

    /// The conversation of a hosted session (its rows come from `WindowlessSessionManager`, read by the view).
    func openConversation(_ session: AgentSession) {
        model.windowlessConversation = session.listID
        render()
    }

    func closeConversation() {
        if let id = model.windowlessConversation, model.agentReplyTarget == id { endAgentReply() }
        model.windowlessConversation = nil
        render()
    }

    /// "+" on the Agents page: a folder from the ones offered, an optional first message, Start.
    func beginNewWindowless() {
        if model.agentReplyTarget != nil { endAgentReply() }
        let live = model.agents.compactMap(\.cwd)
        let recent = model.recentAgents.compactMap(\.cwd)
        model.newWindowlessFolders = WindowlessSessionManager.shared.folderChoices(extra: live + recent)
        model.newWindowlessFolder = model.newWindowlessFolders.first
        model.newWindowlessText = ""
        model.windowlessNotice = nil
        model.windowlessNoticeDetail = nil
        model.newWindowlessOpen = true
        render()
        syncAgentReplyKeyboard()
        model.newWindowlessFocus += 1
    }

    /// The launch started from the composer or a recent row; Hủy/Esc cancels it before the process starts (review).
    private var windowlessTask: Task<Void, Never>?

    func cancelNewWindowless() {
        windowlessTask?.cancel()
        windowlessTask = nil
        model.newWindowlessOpen = false
        model.newWindowlessText = ""
        model.windowlessStarting = false
        syncAgentReplyKeyboard()
        render()
    }

    /// Start: a Claude Code session in the folder picked, the message as its first turn (none ⇒ it waits for one).
    func startNewWindowless() {
        guard !model.windowlessStarting, let path = model.newWindowlessFolder else { return }
        let text = model.newWindowlessText
        model.windowlessStarting = true
        model.windowlessNotice = nil
        render()
        windowlessTask = Task { @MainActor in
            do {
                let agent = model.newWindowlessAgent
                let folder = URL(fileURLWithPath: path)
                let id = agent == .codex
                    ? try await WindowlessSessionManager.shared.startCodex(folder: folder, firstMessage: text)
                    : try await WindowlessSessionManager.shared.startClaude(folder: folder, firstMessage: text)
                windowlessTask = nil
                model.windowlessStarting = false
                cancelNewWindowless()
                model.windowlessConversation = "\(agent.rawValue):\(id)"
                render()
            } catch let e as WindowlessSessionManager.StartError {
                windowlessTask = nil
                model.windowlessStarting = false
                model.windowlessNotice = e.key
                model.windowlessNoticeDetail = e.detail
                render()
            } catch is CancellationError {
                windowlessTask = nil                       // backed out: nothing to report
            } catch {
                windowlessTask = nil
                model.windowlessStarting = false
                model.windowlessNotice = WindowlessSessionManager.StartError.launchFailed("").key
                model.windowlessNoticeDetail = error.localizedDescription
                render()
            }
        }
    }

    /// "Phiên gần đây": reopen a Claude Code conversation windowless, in its folder.
    func resumeWindowless(_ entry: AgentRecent.Entry) {
        guard entry.agent == .claude, let cwd = entry.cwd else { return }
        windowlessTask?.cancel()
        windowlessTask = Task { @MainActor in
            do {
                try await WindowlessSessionManager.shared.resumeClaude(sessionID: entry.sessionID, folder: URL(fileURLWithPath: cwd),
                                                                       liveSessions: AgentSessionMonitor.shared.sessions)
                model.windowlessConversation = "\(AgentKind.claude.rawValue):\(entry.sessionID.lowercased())"
                render()
            } catch let e as WindowlessSessionManager.StartError {
                model.windowlessNotice = e.key
                model.windowlessNoticeDetail = e.detail
                render()
            } catch {}
        }
    }

    func interruptWindowless(_ session: AgentSession) { WindowlessSessionManager.shared.interrupt(session.id) }
    func stopWindowless(_ session: AgentSession) { WindowlessSessionManager.shared.stop(session.id) }
    func forgetWindowless(_ session: AgentSession) {
        if model.windowlessConversation == session.listID { closeConversation() }
        WindowlessSessionManager.shared.forget(session.id)
    }

    /// P5c — an agent notice, unless the person is already looking at the Agents page (the row is right there).
    /// P7b — the crew reached its message-hop cap and paused: say so even while the person is elsewhere.
    func presentCrewNotice(crewID: String) {
        guard let crew = CrewManager.shared.crews.first(where: { $0.id == crewID }) else { return }
        let detail = "\(crew.relay.relays)\(L10n.t(" chặng tin")) · \((crew.folder as NSString).lastPathComponent)"
        present(LiveActivity.Item(kind: .agent, symbol: "pause.circle.fill", titleKey: "Crew tạm dừng — chờ bạn",
                                  detail: detail, tint: .warning, duration: 8, buttons: [.openAgents]))
    }

    /// P7b — the crew board on the Agents page (nil = the list).
    func openCrew(_ crewID: String) {
        model.windowlessConversation = nil
        model.crewBoard = crewID
        // P7b review: a reply being composed for another session would otherwise stay pinned under the board.
        if model.agentReplyTarget != nil { endAgentReply(); return }
        render()
    }

    func closeCrew() {
        model.crewBoard = nil
        render()
    }

    /// The crew is being forgotten elsewhere (Settings): close its board if the notch shows it.
    func closeCrewIfShowing(_ crewID: String) {
        if model.crewBoard == crewID { closeCrew() }
    }

    func presentAgentNotice(_ item: LiveActivity.Item) {
        guard machine.state != .expanded(.agents) else { return }
        present(item)
    }

    /// P5c — "Phiên gần đây" on the notch's empty Agents page: copy the command that reopens a session.
    func copyResumeCommand(_ entry: AgentRecent.Entry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.resumeCommand, forType: .string)
    }

    private var nowPlayingTicker: Timer?

    /// The helper reported something (or went away): mirror it into the model, let the machine
    /// re-decide (a peek that showed only the track collapses when it ends), and redraw — the
    /// collapsed badge appears or disappears with the track.
    private func nowPlayingChanged() {
        let m = NowPlayingMonitor.shared
        model.nowPlaying = m.liveSnapshot          // nil unless the helper is alive (review 2026-10-11)
        model.nowPlayingArtwork = m.liveArtwork
        model.nowPlayingAvailability = m.availability
        let app = m.playerApp
        model.nowPlayingAppName = app?.localizedName
        model.nowPlayingAppIcon = app?.icon
        model.nowPlayingPosition = m.snapshot.flatMap { NowPlaying.position(of: $0, at: Date()) }
        dispatch(.itemsChanged(count: machine.itemCount))
        render()
        syncNowPlayingTicker()
        syncWaveform()                              // §3b #21: a new pid, or play/pause
    }

    /// A 1 s ticker exists ONLY while the Now Playing page is open and the track is moving — it drives
    /// the progress bar from the last report (the helper never ticks). Otherwise none.
    private func syncNowPlayingTicker() {
        let wanted = machine.state == .expanded(.nowPlaying) && model.nowPlaying?.playing == true
        if wanted, nowPlayingTicker == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let s = self.model.nowPlaying else { return }
                    self.model.nowPlayingPosition = NowPlaying.position(of: s, at: Date())
                }
            }
            RunLoop.main.add(t, forMode: .common)
            nowPlayingTicker = t
        } else if !wanted, let t = nowPlayingTicker {
            t.invalidate(); nowPlayingTicker = nil
        }
    }

    func nowPlayingCommand(_ c: NowPlayingMonitor.Command) { NowPlayingMonitor.shared.send(c) }
    // N8
    func nowPlayingSeek(to seconds: Double) {
        NowPlayingMonitor.shared.seek(to: seconds)
        model.nowPlayingPosition = seconds          // the helper's next notification confirms; until then the slider stays put
    }
    func nowPlayingShuffle(_ m: NowPlaying.ShuffleMode) { NowPlayingMonitor.shared.setShuffle(m) }
    func nowPlayingRepeat(_ m: NowPlaying.RepeatMode) { NowPlayingMonitor.shared.setRepeat(m) }

    func openPlayer() { NowPlayingMonitor.shared.openPlayer() }

    // MARK: - Clipboard page (B5; D0: the ⌘⇧V shelf lives here)

    private var clipboardKeyMonitor: Any?
    private let quickLook = ClipboardQLController()

    /// The surface's master switch, for the ⌘⇧V router in `ClipboardShelfController`.
    var isEnabled: Bool { enabled }

    /// ⌘⇧V, routed here while `clipboard.hotkeySurface` is "notch": toggles the clipboard page. The app
    /// to paste back into is captured NOW, before anything appears (the shelf's `targetPID` rule);
    /// pressing the hotkey from inside XFinder falls back to the last external app.
    func toggleClipboardFromHotkey() {
        if case .expanded(.clipboard) = state { dismiss(); return }
        let front = NSWorkspace.shared.frontmostApplication
        let pid = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? ClipboardManager.shared.lastExternalPID : front?.processIdentifier
        model.clipboard.beginSession(lockOn: ClipboardShelfController.shared.touchIDLockEnabled, targetPID: pid)
        reveal(page: .clipboard)
    }

    /// The clipboard page needs typing (its search field) and the keys the shelf had. The panel becomes
    /// key WITHOUT `NSApp.activate` (which would raise every XFinder window); `orderOut` on collapse
    /// gives the keyboard back. A LOCAL monitor is enough: the keys matter only while our panel is key.
    private func syncClipboardKeyboard() {
        if case .expanded(.clipboard) = machine.state {
            guard clipboardKeyMonitor == nil else { return }
            model.clipboard.armLock(ClipboardShelfController.shared.touchIDLockEnabled)
            panel?.makeKeyAndOrderFront(nil)
            clipboardKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.panel?.isKeyWindow == true else { return e }
                return self.handleClipboardKey(e) ? nil : e
            }
        } else if let m = clipboardKeyMonitor {
            NSEvent.removeMonitor(m)
            clipboardKeyMonitor = nil
        }
    }

    /// Esc · ←/→/↑/↓ · Return (⇧ = plain text) · Space Quick Look (unless typing) · ⌘1–9 scope ·
    /// ⌘P pin · ⌘⌫ delete · ⌘F search — the shelf's table, on the grid. Returns true when consumed.
    private func handleClipboardKey(_ e: NSEvent) -> Bool {
        let m = model.clipboard
        let cmd = e.modifierFlags.contains(.command), shift = e.modifierFlags.contains(.shift)
        let locked = ClipboardShelfController.shared.touchIDLockEnabled && !m.unlocked
        if e.keyCode == 53 {                                                      // Esc: clear the search first, then close
            if !m.query.isEmpty, !locked { m.query = "" } else { dismiss() }
            return true
        }
        if locked { return false }
        let items = m.items(from: ClipboardManager.shared)
        if cmd, let slot = NotchClipboardRules.slot(forKeyCode: e.keyCode) {
            let boards = ClipboardManager.shared.pinboards.filter { !$0.isBuiltIn }.map(\.id)
            if let s = NotchClipboardRules.scope(forSlot: slot, boardIDs: boards) { m.scope = s; m.selectedID = nil }
            return true
        }
        switch e.keyCode {
        case 123: m.move(.left, in: items); return true
        case 124: m.move(.right, in: items); return true
        case 126: m.move(.up, in: items); return true
        case 125: m.move(.down, in: items); return true
        case 36:                                                                  // Return
            guard let r = m.selected(in: items) else { return false }
            pasteFromClipboardPage(r, plainText: shift); return true
        case 49 where !m.searchFocused:                                           // Space
            if let r = m.selected(in: items) { quickLook(r) }
            return true
        case 35 where cmd:                                                        // ⌘P
            if let r = m.selected(in: items) { ClipboardManager.shared.togglePin(r.id) }
            return true
        case 51 where cmd:                                                        // ⌘⌫
            if let r = m.selected(in: items) { deleteFromClipboardPage(r) }
            return true
        case 3 where cmd:                                                         // ⌘F
            m.focusSearchRequest += 1; return true
        default: return false
        }
    }

    /// Whether the shelf's event tap is alive — the Paste Stack can then intercept ⌘V system-wide.
    /// (The tap stays with `ClipboardShelfController` on purpose: it is the engine, the shelf panel is
    /// only one of its two surfaces.)
    var pasteStackInterceptsCommandV: Bool { ClipboardShelfController.shared.tapIsLive }

    /// Paste into the app the user came from and get out of the way. Without Accessibility (or
    /// with auto-paste off) the item is copied and the page says to press ⌘V — never a silent nothing.
    /// D4: a locked clip cannot be pasted, previewed, spoken or edited from the notch — it opens the
    /// Library at its board instead (the only place that can prompt Touch ID and show it).
    func openLibraryForLocked(_ record: ClipboardRecord) {
        dismiss()
        AppState.shared.navigate(to: .clipboard)
        AppState.shared.bringMainWindowFront()
        if let boardID = record.lockedBoardID {
            ClipboardLibraryStore.shared.query.scope = .board(boardID)
        }
    }

    func pasteFromClipboardPage(_ record: ClipboardRecord, plainText: Bool = false) {
        guard !record.isLocked else { openLibraryForLocked(record); return }
        let pid = model.clipboard.targetPID ?? ClipboardManager.shared.lastExternalPID
        ClipboardManager.shared.incrementUsage(record.id)
        if ClipboardShelfController.shared.autoPasteAfterSelection, WindowManager.isTrusted {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                ClipboardPasteEngine.paste(record: record, to: pid, plainText: plainText)
            }
        } else {
            ClipboardPasteEngine.writeToPasteboard(record: record, plainText: plainText)
            ClipboardSounds.playCopy()
            model.clipboard.notice = "Đã sao chép — dán bằng ⌘V."
        }
    }

    func pasteNextFromStack() { ClipboardManager.shared.pasteNextManually() }

    /// Space: the system Quick Look panel for clips that have a file (images, files, long text payloads).
    /// A short text clip has nothing to preview and says so, instead of a silent key press.
    func quickLook(_ record: ClipboardRecord) {
        guard !record.isLocked else { openLibraryForLocked(record); return }   // the payload path IS the sealed envelope
        if let path = record.payloadPath ?? record.thumbnailPath, FileManager.default.fileExists(atPath: path) {
            quickLook.present(url: URL(fileURLWithPath: path))
        } else {
            model.clipboard.notice = "Mục này không có tệp để xem nhanh."
        }
    }

    /// ⌘⌫ / "Xóa": remove the record and keep the selection on the card that slid into its place.
    func deleteFromClipboardPage(_ record: ClipboardRecord) {
        let before = model.clipboard.items(from: ClipboardManager.shared)
        let index = before.firstIndex { $0.id == record.id } ?? 0
        ClipboardManager.shared.deleteRecord(record.id)
        let after = model.clipboard.items(from: ClipboardManager.shared)
        if let i = NotchClipboardRules.selectionAfterDeleting(index: index, newCount: after.count) {
            model.clipboard.selectedID = after[i].id
        } else {
            model.clipboard.selectedID = nil
        }
    }

    /// OCR text of an image clip (or any text) → the pasteboard; the monitor records it as a new clip.
    func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(text, forType: .string)
        ClipboardSounds.playCopy()
        model.clipboard.notice = "Đã sao chép kết quả."
    }

    /// `clipboard.touchIDLock`: Touch ID or the login password, once per opening of the page. A Mac
    /// without biometrics that cannot evaluate the policy is not locked out — the shelf's rule.
    func unlockClipboard() {
        let context = LAContext()
        var error: NSError?
        let reason = L10n.t("Xác thực bằng Touch ID hoặc mật khẩu để xem lịch sử clipboard")
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            model.clipboard.unlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            Task { @MainActor in if success { NotchSurfaceController.shared.model.clipboard.unlocked = true } }
        }
    }

    /// "Tạo bảng ghim mới": boards are made on the Cài đặt Clipboard page (one place, not an overlay
    /// inside a 440 pt hub); the hub closes so the window is not behind it.
    func openClipboardSettings() {
        dismiss()
        AppState.shared.navigate(to: .settingsClipboard)
        AppState.shared.bringMainWindowFront()
    }

    /// P1: the chip row's Library button — every clip, beyond the capped history the deck draws from (D3).
    func openLibrary() {
        dismiss()
        AppState.shared.navigate(to: .clipboard)
        AppState.shared.bringMainWindowFront()
    }

    // MARK: - D1: speak, edit

    private let speech = AVSpeechSynthesizer()
    var isSpeaking: Bool { speech.isSpeaking }

    /// D1 #36 — read a clip aloud with the system voice (on-device `AVSpeechSynthesizer`; the voice follows
    /// the text's dominant language when a matching voice is installed). Pressing again stops.
    func speak(_ record: ClipboardRecord) {
        guard !record.isLocked else { openLibraryForLocked(record); return }
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate); return }
        guard let text = NotchTextCache.fullText(snippet: record.textSnippet, payloadPath: record.payloadPath),
              !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        if let lang = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
           let voice = AVSpeechSynthesisVoice(language: lang) {
            utterance.voice = voice
        }
        speech.speak(utterance)
    }

    private var editorPanel: SurfacePanel?
    private let editorModel = NotchTextEditorModel()

    // MARK: - P9 — hand a session over to another agent

    private var handoffPanel: SurfacePanel?
    private let handoffModel = AgentHandoffModel()
    private var handoffSession: AgentSession?
    private var handoffDraft: AgentHandoffRunner.Draft?
    private var handoffTask: Task<Void, Never>?

    /// Read the session, show the message for the person to read / edit; nothing is sent until "Gửi".
    func beginHandoff(_ session: AgentSession, to target: AgentKind) {
        handoffSession = session
        handoffModel.source = session.agent
        handoffModel.sourceName = session.displayName
        handoffModel.noticeKey = nil
        handoffModel.sending = false
        handoffModel.onClose = { [weak self] in self?.endHandoff() }
        handoffModel.onSend = { [weak self] in self?.sendHandoff() }
        handoffModel.onRetarget = { [weak self] kind in
            self?.handoffModel.target = kind
            self?.handoffDraft?.target = kind
        }
        handoffModel.target = target
        handoffModel.loading = true
        handoffModel.text = ""
        if handoffPanel == nil {
            let p = SurfacePanel(kind: .interactive, size: CGSize(width: 600, height: 440))
            p.host(AgentHandoffView(model: handoffModel))
            handoffPanel = p
        }
        dismiss()
        handoffPanel?.show(anchor: .spotlight)
        handoffTask?.cancel()
        handoffTask = Task { [weak self] in
            let draft = await AgentHandoffRunner.shared.prepare(session, target: target)
            guard let self, !Task.isCancelled, self.handoffSession?.listID == session.listID else { return }
            var d = draft
            d.target = self.handoffModel.target       // the person may have picked another target while it read
            self.handoffDraft = d
            self.handoffModel.text = d.text
            self.handoffModel.turnCount = d.turnCount
            self.handoffModel.loading = false
        }
    }

    private func sendHandoff() {
        guard var d = handoffDraft, !handoffModel.sending else { return }
        d.text = handoffModel.text            // what the person edited is what goes
        d.target = handoffModel.target
        handoffModel.sending = true
        handoffModel.noticeKey = nil
        handoffTask = Task { [weak self] in
            let outcome = await AgentHandoffRunner.shared.send(d)
            guard let self else { return }
            self.handoffModel.sending = false
            switch outcome {
            case .started:
                self.endHandoff()
                self.present(LiveActivity.Item(kind: .agent, symbol: "arrow.triangle.branch", titleKey: "Đã chuyển phiên",
                                               detail: "\(d.source.displayName) → \(d.target.displayName)", tint: .good,
                                               duration: 4, buttons: [.openAgents]))
            case .copiedCommand:
                self.endHandoff()
                self.present(LiveActivity.Item(kind: .agent, symbol: "doc.on.clipboard", titleKey: "Đã chép lệnh mở Codex",
                                               detail: L10n.t("Dán vào terminal để bắt đầu."), tint: .good, duration: 5, buttons: []))
            case .failed(let key):
                self.handoffModel.noticeKey = key
            }
        }
    }

    func endHandoff() {
        handoffTask?.cancel(); handoffTask = nil
        handoffSession = nil
        handoffDraft = nil
        handoffPanel?.hide()
    }

    /// D1 #9 — open the clip's full text in the editor panel (built once, Spotlight position); "Sao chép"
    /// copies the edited text, which the monitor records as a new clip. The hub closes first.
    func editText(_ record: ClipboardRecord) {
        guard !record.isLocked else { openLibraryForLocked(record); return }
        editorModel.text = NotchTextCache.fullText(snippet: record.textSnippet, payloadPath: record.payloadPath) ?? ""
        editorModel.sourceType = record.type
        editorModel.onCopy = { [weak self] text in self?.copyText(text); self?.editorPanel?.hide() }
        editorModel.onClose = { [weak self] in self?.editorPanel?.hide() }
        if editorPanel == nil {
            let p = SurfacePanel(kind: .interactive, size: CGSize(width: 560, height: 380))
            p.host(NotchTextEditorView(model: editorModel))
            editorPanel = p
        }
        dismiss()
        editorPanel?.show(anchor: .spotlight)
        editorPanel?.installClickOutside { [weak self] in self?.editorPanel?.hide() }
    }

    /// Runs a transform on the record's FULL text (the snippet is a 200-character preview; long
    /// clips live in a payload file) and copies the result, which the monitor then records as a
    /// new clip. A transform that changes nothing says so instead of pretending.
    func applyTransform(_ t: ClipboardTransform, to record: ClipboardRecord) {
        let text = ClipboardText.fullText(snippet: record.textSnippet, payloadPath: record.payloadPath) ?? ""
        switch t.apply(to: text) {
        case .success(let out):
            let pb = NSPasteboard.general
            pb.clearContents(); pb.setString(out, forType: .string)
            ClipboardSounds.playCopy()
            model.clipboard.notice = "Đã sao chép kết quả."
        case .failure(let f):
            model.clipboard.notice = f.messageKey
        }
    }

    /// "Đi tới nguồn": bring the source app forward (always possible from a bundle id).
    func openSourceApp(bundleID: String) {
        AgentSessionMonitor.bringForward(bundleID: bundleID)   // activate(options:) is ignored from the notch (macOS 14+)
    }

    /// Build the panel ONCE — a hosting controller created on the way to the screen cost 0.15–0.65 s
    /// in QuitProtection. `sizingOptions = []` so SwiftUI never resizes the window to its content:
    /// the frame is owned by `NotchSurfaceLayout`, and the drawn shape animates inside it.
    private func prepare() {
        let p = SurfacePanel(kind: .notch, size: CGSize(width: 440, height: 222))
        p.sharingType = hideFromCapture ? .none : .readOnly          // B7; off by default since 2026-10-14 (owner could not screenshot it)
        // The surface is black in every state; system controls on it (menus, text-field placeholders,
        // selection colours) must think they are in Dark mode. Measured on the Light-appearance panel:
        // the search placeholder rendered (13,13,13) on (25,25,25) — 1.1:1 (review row 1).
        p.appearance = NSAppearance(named: .darkAqua)
        // A hosting VIEW subclass, not a controller: it must answer acceptsFirstMouse = true or every
        // control needs two clicks while another app is frontmost (the panel is never made key).
        let host = FirstMouseHostingView(rootView: NotchSurfaceView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: p.frame.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        panel = p
    }

    /// Size of the DRAWN shape for the rendered state (nil while nothing is drawn). N1: the window itself is
    /// bigger than the shape, so hit-tests and the drop target must use this, never `panel.frame`.
    private var drawnSize: CGSize?

    /// The drawn shape in screen space: the view lays it out top-centred in the window, so it follows the
    /// window even after a pointer tray has been dragged aside by its title strip.
    private var drawnFrame: CGRect {
        guard let panel, panel.isVisible, let s = drawnSize else { return .zero }
        return CGRect(x: panel.frame.midX - s.width / 2, y: panel.frame.maxY - s.height, width: s.width, height: s.height)
    }

    /// N1 (2026-10-13, after measuring OneNotch 2.0.5: its notch window is ONE fixed 700×745 frame that did not
    /// move a pixel across 20 s of polling while the content animated inside it). The window now has ONE
    /// frame per anchor — `NotchSurfaceLayout.panelFrame` at the notch, the same size top-centred on the
    /// state's frame at the pointer — big enough for every state, so a state change never calls `setFrame`.
    /// The D0c grow / shrink-after-0.32 s / union dance is gone with it. The transparent remainder of the
    /// window passes clicks through (measured with `NSWindow.windowNumber(at:)` before this shipped).
    private func render() {
        guard let panel else { return }
        guard enabled else { panel.hide(); drawnSize = nil; return }
        var screen = surfaceScreen ?? WindowManager.screenUnderPointer()
        if machine.state == .collapsed, let notched = Self.notchedScreen { screen = notched }
        let notch = Self.notch(on: screen)

        guard let target = NotchSurfaceLayout.frame(for: machine.state, anchor: machine.anchor,
                                                    itemCount: machine.itemCount, notch: notch,
                                                    screen: screen.frame, visible: screen.visibleFrame,
                                                    pointer: shakePoint, timerActive: countdown != nil,
                                                    nowPlayingActive: NowPlayingMonitor.shared.hasTrack,
                                                    agentActive: model.agentActive, agentBusy: model.agentBusy, agentCount: model.agentCount,
                                                    pillOnPlainScreens: pillOnPlainScreens) else {
            model.state = .collapsed
            model.itemCount = machine.itemCount
            panel.hide()
            drawnSize = nil
            renderedAnchor = .notch
            return
        }
        drawnSize = target.size
        let wasVisible = panel.isVisible
        let anchorChanged = machine.anchor != renderedAnchor
        renderedAnchor = machine.anchor
        panel.hasShadow = machine.anchor == .pointer      // at the notch a shadow would reveal the rect

        let fixed: CGRect
        switch machine.anchor {
        case .notch:
            fixed = NotchSurfaceLayout.panelFrame(notch: notch, screen: screen.frame)
        case .pointer:
            // A tray at the pointer may have been dragged aside by its title strip: while it stays visible at
            // the pointer, every update (a file added, a page change) keeps it where the user put it.
            if wasVisible && !anchorChanged { applyModel(notch: notch); return }
            let size = NotchSurfaceLayout.panelSize(notch: notch)
            fixed = SurfaceGeometry.clamp(CGRect(x: target.midX - size.width / 2, y: target.maxY - size.height,
                                                 width: size.width, height: size.height), into: screen.visibleFrame)
        }
        if panel.frame != fixed { panel.setFrame(fixed, display: true) }   // first show, anchor change or screen change only

        if !wasVisible || anchorChanged {
            // D0c: at the notch the surface GROWS OUT OF THE NOTCH — the shape starts at the notch's own size and
            // springs to the state's size on the next run-loop turn. At the pointer (a shake) it appears at once.
            let grow = !wasVisible && machine.anchor == .notch
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                model.appearFromNotch = grow
                applyModel(notch: notch)
            }
            if !wasVisible { panel.orderFrontRegardless() }   // never key: the user's app keeps focus
            if grow {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.model.appearFromNotch = false }
                }
            }
            return
        }
        applyModel(notch: notch)
    }

    private func applyModel(notch: CGRect) {
        model.notchSize = notch.size
        model.anchor = machine.anchor
        model.itemCount = machine.itemCount
        model.state = machine.state
    }

    // MARK: - Live activities (B4)

    private var activityQueue = LiveActivity.Queue()
    private var activityWork: DispatchWorkItem?

    /// True when a notice can actually be drawn (the surface exists and is on). Callers with a
    /// fallback (AlertMonitor's banner) check this first.
    var canPresentActivities: Bool { enabled && panel != nil }

    /// Volume / brightness feedback can be drawn right now: everywhere but the open hub. The key interceptor swallows
    /// a key only when this is true, so inside the hub the key reaches macOS and its own square answers.
    var canShowKeyFeedback: Bool {
        guard canPresentActivities else { return false }
        if case .expanded = machine.state { return false }
        return true
    }

    func present(_ item: LiveActivity.Item) {
        guard canPresentActivities else { return }
        // A level that could not be drawn now would surface later as stale news (the CoreAudio path reports changes
        // made inside the hub, where the key went to macOS).
        if item.kind.isKeyFeedback, !canShowKeyFeedback { return }
        if activityQueue.push(item) { showCurrentActivity() }
    }

    private func showCurrentActivity() {
        activityWork?.cancel(); activityWork = nil
        guard let item = activityQueue.current else { return }
        model.activity = item
        if machine.state == .activity { render() }
        else if item.kind.isKeyFeedback { dispatch(.feedbackShown) }
        else if machine.state.isIdle { dispatch(.activityShown) }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.activityTimeUp() } }
        activityWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + item.duration, execute: work)
    }

    /// §3b #33 — a button on the notice was pressed: end the notice at once, then do what it says.
    func pressActivityButton(_ b: LiveActivity.Button) {
        activityWork?.cancel(); activityWork = nil
        activityTimeUp()
        switch b {
        case .join(let url): NSWorkspace.shared.open(url)
        case .snooze(let key): CalendarGlanceMonitor.shared.snooze(key: key)
        case .openCalendar: reveal(page: .calendar)
        case .openAgents: reveal(page: .agents)
        case .handOff(let listID, let target):
            // Opens the same preview as the row's "Chuyển sang…" menu — the person still reads it and presses Send.
            if let s = AgentSessionMonitor.shared.sessions.first(where: { $0.listID == listID }) { beginHandoff(s, to: target) }
            else { reveal(page: .agents) }
        }
    }

    private func activityTimeUp() {
        activityWork = nil
        if activityQueue.advance() != nil {
            showCurrentActivity()
        } else {
            model.activity = nil
            dispatch(.activityEnded)
        }
    }

    // MARK: - Countdown timer (B4b)

    private var countdown: LiveActivity.Countdown? {
        didSet { model.timer = countdown }      // P2: the Hẹn giờ page reads the countdown itself (pause, progress)
    }
    private var countdownTicker: Timer?

    var timerRunning: Bool { countdown != nil }

    /// P2: the idle stepper's minutes (`notch.timer.minutes`, ONE reader here; the page writes through `setTimerDraft`).
    static let timerDraftKey = "notch.timer.minutes"
    var timerDraftMinutes: Int {
        LiveActivity.validTimerMinutes(UserDefaults.standard.object(forKey: Self.timerDraftKey) as? Int ?? LiveActivity.timerDefaultMinutes)
    }

    func setTimerDraft(minutes: Int) {
        let m = LiveActivity.validTimerMinutes(minutes)
        UserDefaults.standard.set(m, forKey: Self.timerDraftKey)
        model.timerDraftMinutes = m
    }

    /// A 1 s ticker exists ONLY while a countdown RUNS (it drives the badge's seconds); none while paused or idle.
    func startTimer(minutes: Int) {
        guard enabled, panel != nil else { return }
        countdown = LiveActivity.Countdown(minutes: minutes, now: Date())
        armCountdownTicker()
        tickCountdown()
    }

    /// P2: freeze / restart the clock. A paused countdown keeps its wing (the time left, with a pause glyph) and no ticker.
    func pauseTimer() {
        guard let c = countdown, !c.isPaused else { return }
        countdown = c.paused(at: Date())
        countdownTicker?.invalidate(); countdownTicker = nil
        tickCountdown()
    }

    func resumeTimer() {
        guard let c = countdown, c.isPaused else { return }
        countdown = c.resumed(at: Date())
        armCountdownTicker()
        tickCountdown()
    }

    /// P2: "−5 / +5" on a running or paused countdown (what is left stays within 1 minute … the maximum).
    func extendTimer(byMinutes minutes: Int) {
        guard let c = countdown else { return }
        countdown = c.extended(byMinutes: minutes, now: Date())
        tickCountdown()
    }

    func cancelTimer() {
        countdownTicker?.invalidate(); countdownTicker = nil
        countdown = nil
        model.timerText = nil
        render()
    }

    private func armCountdownTicker() {
        countdownTicker?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tickCountdown() } }
        RunLoop.main.add(t, forMode: .common)
        countdownTicker = t
    }

    private func tickCountdown() {
        guard let c = countdown else { return }
        let now = Date()
        if c.isFinished(at: now) {
            cancelTimer()
            NSSound(named: "Glass")?.play()
            present(LiveActivity.timerFinishedItem(c))
            return
        }
        let wasHidden = model.timerText == nil
        model.timerText = c.label(at: now)
        model.timerNow = now                  // the page's progress ring follows the same tick, never its own timer
        if wasHidden { render() }        // the badge appears; afterwards only its text changes
    }

    // MARK: - Hub actions (B2d)

    private var job: Task<Void, Never>?

    /// Runs one action on the held files. One job at a time; progress is counted in files done.
    func run(_ action: NotchActions.Action) {
        guard model.task?.isRunning != true else { return }
        let items = DropTrayStore.shared.items.filter { !$0.isMissing }.map { URL(fileURLWithPath: $0.path) }
        model.notice = nil
        if action == .airDrop { shareViaAirDrop(items); return }
        let inputs = NotchActions.inputs(for: action, from: items)
        guard !inputs.isEmpty else { return }
        model.task = NotchTask(action: action, total: NotchActions.stepCount(for: action, inputs: inputs.count))
        model.ocrSummary = nil
        dispatch(.taskStarted)
        job = Task { [weak self] in
            await self?.execute(action, inputs: inputs)
            self?.finishJob()
        }
    }

    func cancelTask() {
        job?.cancel()                       // ArchiveRunner terminates its child; per-file loops stop
        model.task?.cancel()
        dispatch(.taskEnded)
    }

    func revealResults() {
        guard let outs = model.task?.outputs, !outs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outs)
    }

    private func execute(_ action: NotchActions.Action, inputs: [URL]) async {
        let exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
        switch action {
        case .zip:
            let base = inputs[0].deletingLastPathComponent().appendingPathComponent("XFinder.zip")
            guard case .write(let out) = ArchiveEngine.destination(base: base, policy: .keepBoth, exists: exists) else { return }
            switch await ArchiveRunner.compress(sources: inputs, format: .zip, output: out) {
            case .success(let url): model.task?.stepSucceeded(output: url)
            case .failure(let f):
                DiagnosticsLog.record("archive", "notchZip." + f.diagnosticCode)
                model.task?.stepFailed(key: f.messageKey, detail: f.detail ?? "")
            }
        case .mergePDFs:
            let folder = inputs[0].deletingLastPathComponent()
            switch await Task.detached(priority: .userInitiated, operation: { PdfRunner.merge(inputs, into: folder) }).value {
            case .success(let o): model.task?.stepSucceeded(output: o.url)
            case .failure(let f): model.task?.stepFailed(key: f.messageKey, detail: f.detail)
            }
        case .convert, .removeBackground:
            for url in inputs {
                if Task.isCancelled || model.task?.isRunning != true { break }
                let r = await Task.detached(priority: .userInitiated, operation: { () -> Result<URL, ImageRunner.Failure> in
                    if case .convert(let t) = action { return ImageRunner.convert(url, to: t) }
                    return ImageRunner.removeBackground(url)
                }).value
                switch r {
                case .success(let out): model.task?.stepSucceeded(output: out)
                case .failure(let f): model.task?.stepFailed(key: f.messageKey, detail: f.detail)
                }
            }
        case .toPDF:
            switch await Task.detached(priority: .userInitiated, operation: { PDFAssembler.assemble(inputs) }).value {
            case .success(let out): model.task?.stepSucceeded(output: out)
            case .failure(let f): model.task?.stepFailed(key: f.messageKey, detail: f.detail)
            }
        case .resize(let px):
            for url in inputs {
                if Task.isCancelled || model.task?.isRunning != true { break }
                switch await Task.detached(priority: .userInitiated, operation: { ImageRunner.resize(url, maxPixels: px) }).value {
                case .success(let out): model.task?.stepSucceeded(output: out)
                case .failure(let f): model.task?.stepFailed(key: f.messageKey, detail: f.detail)
                }
            }
        case .ocr:
            // Each image's text goes beside it as .txt; all of it, in order, goes on the clipboard (the monitor
            // records it as a clip). The summary line carries the one number that is measured: characters.
            var texts: [String] = []
            for url in inputs {
                if Task.isCancelled || model.task?.isRunning != true { break }
                switch await Task.detached(priority: .userInitiated, operation: { ImageTextOCR.recognize(url) }).value {
                case .success(let text):
                    let out = ImageTextOCR.outputURL(for: url, exists: exists)
                    do { try text.write(to: out, atomically: true, encoding: .utf8); texts.append(text); model.task?.stepSucceeded(output: out) }
                    catch { model.task?.stepFailed(key: "Không ghi được: ", detail: out.lastPathComponent) }
                case .failure(let f): model.task?.stepFailed(key: f.messageKey, detail: f.detail)
                }
            }
            if !texts.isEmpty {
                let all = texts.joined(separator: "\n\n")
                let pb = NSPasteboard.general; pb.clearContents(); pb.setString(all, forType: .string)
                model.ocrSummary = "\(L10n.t("Đã nhận dạng "))\(all.count)\(L10n.t(" ký tự, đã sao chép và lưu .txt cạnh ảnh."))"
            }
        case .airDrop:
            break
        }
    }

    private func finishJob() {
        job = nil
        if let t = model.task, !t.outputs.isEmpty {
            ActionHistoryStore.shared.record(kind: Self.historyKind(t.action),
                                             summary: "\(L10n.t("Từ notch: "))\(t.outputs.count)\(L10n.t(" tệp kết quả"))",
                                             detail: t.outputs.map(\.path).joined(separator: "\n"))
        }
        dispatch(.taskEnded)
    }

    private static func historyKind(_ a: NotchActions.Action) -> String {
        switch a {
        case .zip: return "compress"
        case .mergePDFs: return "pdf"
        case .convert, .removeBackground, .resize: return "image"
        case .toPDF: return "pdf"
        case .ocr, .airDrop: return "other"
        }
    }

    /// AirDrop through the system sharing service. NOT verified live yet: whether the AirDrop picker
    /// opens from a non-activating status-bar panel needs a human at the screen.
    private func shareViaAirDrop(_ items: [URL]) {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        guard service.canPerform(withItems: items) else {
            model.notice = "AirDrop không khả dụng cho các tệp này trên máy này."
            return
        }
        service.perform(withItems: items)
    }

    // MARK: - Detail window (grid of every staged file)

    func toggleDetail() {
        if let d = detailPanel, d.isVisible {
            d.orderOut(nil)
        } else {
            showDetailPanel()
        }
    }

    private func showDetailPanel() {
        if detailPanel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
            p.title = L10n.t("Khay thả")
            p.contentView = NSHostingView(rootView: DropTrayDetailGrid())
            p.isReleasedWhenClosed = false
            detailPanel = p
        }
        detailPanel?.center()
        detailPanel?.makeKeyAndOrderFront(nil)
    }
}
