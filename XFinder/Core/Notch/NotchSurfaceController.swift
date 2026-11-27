import AppKit
import AVFoundation
import LocalAuthentication
import NaturalLanguage
import SwiftUI
import ImageIO
import os

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
    private static let perfLog = Logger(subsystem: "com.xfinder.app", category: "perf")
    private var loggedFirstIslandOpen = false

    /// SwiftUI-facing state; the view reads this, never the machine.
    let model = NotchSurfaceModel()
    private(set) var state: NotchSurfaceMachine.State = .collapsed

    private var machine = NotchSurfaceMachine.Machine()
    private var panel: SurfacePanel?
    private var detailPanel: NSPanel?
    private var monitors: [Any] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private struct FullscreenInspection {
        var frontmostPID: Int32?
        var fullscreenOwnerPID: Int32?
    }
    private var fullscreenInspections: [UInt32: FullscreenInspection] = [:]
    /// The screen the open surface is on; set when it opens, kept until it collapses.
    private var surfaceScreen: NSScreen?
    /// User-selected owner for the single notch surface. Unknown values are treated as automatic.
    private var displayTargetRaw: String { UserDefaults.standard.string(forKey: "notch.displayTarget") ?? "automatic" }
    /// A CGDirectDisplayID persisted as an integer; zero means no explicit screen has been selected.
    private var selectedDisplayID: UInt32? {
        let value = UserDefaults.standard.integer(forKey: "notch.displayTargetID")
        guard value > 0, let displayID = UInt32(exactly: value) else { return nil }
        return displayID
    }
    /// Where the pointer was when a shake opened the tray (the pointer anchor's reference point).
    private var shakePoint: CGPoint = .zero
    /// The anchor the panel is currently drawn at; an anchor change jumps instead of animating.
    private var renderedAnchor: NotchSurfaceMachine.Anchor = .notch
    private var renderedDisplayID: UInt32?
    private var isSystemSleeping = false

    // Drag / shake tracking — only populated while the left button is down.
    private var dragSession = NotchDragSession(currentChangeCount: NSPasteboard(name: .drag).changeCount)
    private var samples: [(point: CGPoint, time: Date)] = []
    private var isDragOutActive = false
    private var isDropTargeted = false
    private var isDropImporting = false
    // Hover / leave tracking.
    private var zoneEnteredAt: Date?
    private var leftAt: Date?
    private var dwellWork: DispatchWorkItem?
    private var graceWork: DispatchWorkItem?

    private init() {
        machine.itemCount = DropTrayStore.shared.items.count
        NotchMessageModel.shared.onShowNotice = { [weak self] payload in
            self?.showLocalMessage(payload)
        }
        NotchMessageModel.shared.onDismissNotice = { [weak self] id in
            self?.dismissLocalMessage(id: id)
        }
        let feedback = NotchFeedbackModel.shared
        feedback.onCopyText = { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
        feedback.onOpenIssuesPage = { NSWorkspace.shared.open($0) }
        feedback.onOpenDiagnostics = { [weak self] in
            self?.dismiss()
            AppState.shared.navigate(to: .about)
            return true
        }
        model.todos.onRequestPanelKey = { [weak self] in self?.ensurePanelKeyForKeyboard() }
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
    /// Deliberate opens use their own preference; explicit page intents continue to bypass it.
    private var clickOpensRaw: String { UserDefaults.standard.string(forKey: "notch.clickOpens") ?? "files" }
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
    /// Fullscreen policy is best-effort and defaults to the existing always-visible behavior.
    private var fullscreenVisibilityRaw: String {
        UserDefaults.standard.string(forKey: "notch.fullscreenVisibility") ?? "show"
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
        let visible = model.tabCatalog.visibleDestinations(availability: destinationAvailability)
        return NotchSurfaceMachine.Settings(enabled: enabled, hoverToPeek: hoverEnabled, hoverOpens: NotchHoverOpen.parse(hoverOpensRaw),
                                     agentNeedsYou: model.agentsNeedingYou > 0, lastPage: lastHubPage,
                                     shownPages: model.tabCatalog.visibleLegacyPages(availability: destinationAvailability),
                                     allDestinationsHidden: visible.isEmpty,
                                     nowPlayingActive: NowPlayingMonitor.shared.hasTrack,
                                     activityHoldsHover: !(model.activity?.buttons.isEmpty ?? true),
                                     composing: model.agentReplyTarget != nil || model.newWindowlessOpen || (model.extraModule == .weather && model.isSearchingWeatherCity) || (model.extraModule == .stocks && model.isSearchingStock) || (model.extraModule == .reminders && (model.isCreatingReminder || remindersViewModel?.isRequestingAccess == true)) || (model.extraModule == .teleprompter && model.isEditingTeleprompter) || ([.notes, .units, .scratchpad, .emoji, .links].contains(model.extraModule) && model.isEditingUtility) || (model.extraModule == .websiteAnalytics && websiteAnalyticsViewModel?.isShowingConfiguration == true) || (model.extraModule == .message && NotchMessageModel.shared.isComposing) || (model.extraModule == .feedback && NotchFeedbackModel.shared.isComposing) || (model.extraModule == .localChat && (NotchLocalChatModel.shared.isComposing || NotchLocalChatModel.shared.isGenerating)) || (model.extraModule == .todos && model.todos.isComposing) || (model.extraModule == .imageConvert && (model.imageConvert.state.isRunning || model.imageConvert.isPickingFiles)),
                                     dragging: (NSEvent.pressedMouseButtons & 1 == 1) || isDragOutActive || isDropTargeted || isDropImporting,
                                     pinned: model.isPinned,
                                     agentEdgeHover: agentEdgeHover, pointerOnAgentEdge: pointerOnAgentEdge,
                                     dragIntoNotchOpens: notchDropEnabled, shakeOpens: shakeEnabled,
                                     hoverDwell: NotchSurfaceMachine.Settings.hoverDwell(forSpeed: hoverSpeed))
    }

    /// Single highest-priority signal rendered on the collapsed Dynamic Island / external pill.
    private var collapsedProjection: NotchCollapsedSignal.WingProjection {
        let visibleSet = Set(model.tabCatalog.visibleDestinations(availability: destinationAvailability))
        let badge = clockSuite.collapsedBadge(at: Date())
        let signal = NotchCollapsedSignal.resolve(
            itemCount: machine.itemCount,
            timerActive: badge != nil,
            timerPaused: badge?.isPaused == true,
            nowPlayingActive: NowPlayingMonitor.shared.hasTrack,
            nowPlayingPlaying: model.nowPlaying?.playing == true,
            agentActive: model.agentActive,
            agentBusy: model.agentBusy,
            agentsNeedingYou: model.agentsNeedingYou,
            visibleDestinations: visibleSet
        )
        return signal.projection(agentCount: model.agentCount)
    }

    /// Something is on the collapsed surface (badge or pill): the single highest-priority active signal.
    private var badgeShown: Bool { collapsedProjection.isVisible }

    /// P10 — the ONE reader of `notch.agentEdgeHover` (OneNotch's "AI edge": point at the agent wing to open the agents).
    private var agentEdgeHover: Bool { UserDefaults.standard.object(forKey: "notch.agentEdgeHover") as? Bool ?? true }
    /// P10 — set on every pointer tick, read by the machine through `settings`.
    private var pointerOnAgentEdge = false

    /// D1 #44 — the ONE reader of `notch.pages` (order + visibility, a comma list; kept as legacy migration input).
    private var pageOrderRaw: String { UserDefaults.standard.string(forKey: "notch.pages") ?? "files,clipboard,nowPlaying,agents,calendar,timer,aiUsage" }
    /// XF-ISLAND-C — the ONE reader of `notch.tabCatalog.v1` (unified ordered visibility for legacy + extra modules).
    private var tabCatalogRaw: String { UserDefaults.standard.string(forKey: "notch.tabCatalog.v1") ?? "" }
    /// D1 #47 — the ONE reader of `notch.accent`.
    private var accentName: String { UserDefaults.standard.string(forKey: "notch.accent") ?? "system" }
    /// For the ⌘⇧V router: a hidden clipboard tab means the hotkey falls back to the floating shelf.
    var showsClipboardPage: Bool { model.tabCatalog.isEnabled(.clipboard) }

    /// Live runtime readiness for every destination (decoupled from user enable/disable preference).
    var destinationAvailability: NotchDestinationAvailability {
        NotchDestinationAvailability(
            nowPlayingReady: model.nowPlayingAvailability != .off,
            agentsReady: model.agentsEnabled,
            calendarReady: model.calendarEnabled,
            weatherConfigured: isWeatherAvailable,
            stocksConfigured: isStocksAvailable,
            revenueConfigured: isRevenueAvailable
        )
    }

    private func resolvedCatalog() -> NotchTabCatalogState {
        let rawCatalog = tabCatalogRaw
        let legacyRaw = UserDefaults.standard.string(forKey: NotchPages.key)
        return NotchDestinationCatalog.parse(
            catalogRaw: rawCatalog.isEmpty ? nil : rawCatalog,
            legacyPagesRaw: legacyRaw
        )
    }

    private func activeDestinationID() -> NotchDestinationID? {
        if let extra = machine.activeExtra {
            return NotchDestinationID(extra: extra)
        }
        if case .expanded(let page) = machine.state {
            return NotchDestinationID(page: page)
        }
        return nil
    }

    private func reconcileActiveDestinationIfNeeded() {
        let avail = destinationAvailability
        model.destinationAvailability = avail
        guard case .expanded = machine.state else { return }
        if machine.activeExtra == .sections || machine.activeExtra == .settings { return }
        let current = activeDestinationID() ?? .files
        let stillOpenable = model.tabCatalog.isOpenable(current, availability: avail)
        if !stillOpenable || (machine.showingAllHiddenRecovery && !model.tabCatalog.visibleDestinations(availability: avail).isEmpty) {
            let fallbackID = model.tabCatalog.fallbackDestination(from: current, availability: avail)
            dispatch(.reconcileVisibility(fallback: fallbackID?.destination, allowAllHiddenRecovery: true))
        }
    }

    func openNotchSettings() {
        dismiss()
        AppState.shared.navigate(to: .notchInterface)
    }

    private var notchSettingsReturnDestination: NotchDestinationID?

    func openInlineNotchSettings(showStocks: Bool = false) {
        guard enabled else { openNotchSettings(); return }
        guard machine.activeExtra != .settings else { return }
        notchSettingsReturnDestination = machine.showingAllHiddenRecovery ? nil : activeDestinationID()
        model.inlineSettingsShowsStocks = showStocks
        dispatch(.openExtra(.settings))
        ensurePanelKeyForKeyboard()
    }

    func returnFromInlineNotchSettings() {
        guard machine.activeExtra == .settings else { return }
        let available = destinationAvailability
        let destination = notchSettingsReturnDestination.flatMap {
            model.tabCatalog.fallbackDestination(from: $0, availability: available)
        } ?? model.tabCatalog.visibleDestinations(availability: available).first
        if let destination { openResolvedDestination(destination) }
        else { dispatch(.openAllHiddenRecovery) }
    }

    func commitNotchCatalog(_ catalog: NotchTabCatalogState) {
        let defaults = UserDefaults.standard
        let legacy = catalog.enabledLegacyPages
        if !legacy.isEmpty { defaults.set(NotchPages.serialize(legacy), forKey: NotchPages.key) }
        defaults.set(NotchDestinationCatalog.serialize(catalog), forKey: "notch.tabCatalog.v1")
        applySettings()
    }

    func displayScale(for id: UInt32) -> NotchDisplayScale {
        let saved = UserDefaults.standard.dictionary(forKey: "notch.displayScale.v1")
        return (saved?[String(id)] as? String).flatMap(NotchDisplayScale.init(rawValue:)) ?? .regular
    }

    func setDisplayScale(_ scale: NotchDisplayScale, for id: UInt32) {
        let defaults = UserDefaults.standard
        var saved = defaults.dictionary(forKey: "notch.displayScale.v1") ?? [:]
        saved[String(id)] = scale.rawValue
        defaults.set(saved, forKey: "notch.displayScale.v1")
        render()
    }

    func applySettings() {
        fullscreenInspections.removeAll()
        // N2 migration: a D1 user who turned "hover opens the clipboard" on keeps that behaviour under the new key.
        let d = UserDefaults.standard
        if d.string(forKey: NotchHoverOpen.key) == nil, d.object(forKey: NotchHoverOpen.legacyKey) as? Bool == true {
            d.set(NotchHoverOpen.migrated(raw: nil, legacyClipboard: true).rawValue, forKey: NotchHoverOpen.key)
        }
        if enabled {
            start()
            panel?.sharingType = hideFromCapture ? .none : .readOnly   // B7, live
            model.pillOnPlainScreens = pillOnPlainScreens
            let catalog = resolvedCatalog()
            if model.tabCatalog.isEnabled(.teleprompter) != catalog.isEnabled(.teleprompter) {
                if catalog.isEnabled(.teleprompter) {
                    NotchTeleprompterController.shared.handleTabEnabled()
                } else {
                    NotchTeleprompterController.shared.handleTabDisabled()
                }
            }
            if model.tabCatalog.isEnabled(.sounds) != catalog.isEnabled(.sounds) {
                NotchSoundsEngine.shared.applyTabVisibility(isEnabled: catalog.isEnabled(.sounds))
            }
            if model.tabCatalog.isEnabled(.capture), !catalog.isEnabled(.capture) {
                NotchCaptureHandoffCoordinator.shared.cancelInFlight()
            }
            if model.tabCatalog.isEnabled(.localChat), !catalog.isEnabled(.localChat) {
                NotchLocalChatModel.shared.handleTabDisabled()
            }
            if model.tabCatalog.isEnabled(.message), !catalog.isEnabled(.message) {
                NotchMessageModel.shared.handleTabDisabled()
            }
            if model.tabCatalog.isEnabled(.feedback), !catalog.isEnabled(.feedback) {
                NotchFeedbackModel.shared.handleTabDisabled()
            }
            if model.tabCatalog.isEnabled(.websiteAnalytics) != catalog.isEnabled(.websiteAnalytics) {
                websiteAnalyticsViewModel?.setDestinationEnabled(catalog.isEnabled(.websiteAnalytics))
            }
            model.tabCatalog = catalog
            model.pages = catalog.enabledLegacyPages
            model.timerDraftMinutes = timerDraftMinutes          // P2: the Hẹn giờ page's idle minutes
            model.accent = NotchAccent.rgb(named: accentName).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
            NowPlayingMonitor.shared.applySettings()      // B6: its own switch, under the master
            AgentSessionMonitor.shared.applySettings(underMaster: true)   // N3: its own switch, under the master
            CalendarGlanceMonitor.shared.applySettings(underMaster: true)  // N4: same
            model.calendarEnabled = CalendarGlanceMonitor.shared.isEnabled
            calendarChanged()
            model.agentsEnabled = AgentSessionMonitor.shared.isEnabled
            model.agents = AgentSessionMonitor.shared.sessions
            refreshAgentHookStatus()
            syncRevenueFromSavedAccounts()
            model.destinationAvailability = destinationAvailability
            reconcileActiveDestinationIfNeeded()
            render()
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
        installFullscreenObserversIfNeeded()
        restoreClockStateIfNeeded()
        render()   // a tray that already holds files shows its badge right away
    }

    private func installFullscreenObserversIfNeeded() {
        guard workspaceObservers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                runOnMainActor { self?.refreshFullscreenVisibility() }
            })
        }
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            runOnMainActor {
                guard let self else { return }
                self.isSystemSleeping = true
                self.render()
            }
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            runOnMainActor {
                guard let self else { return }
                self.isSystemSleeping = false
                self.handleSystemWake()
                self.render()
            }
        })
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            runOnMainActor { self?.refreshFullscreenVisibility() }
        }
        if terminateObserver == nil {
            terminateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                runOnMainActor {
                    self?.persistClockState()
                    self?.closeMirror()
                    self?.websiteAnalyticsViewModel?.prepareForTermination()
                }
            }
        }
    }

    private func refreshFullscreenVisibility() {
        fullscreenInspections.removeAll()
        render()
    }

    func stop() {
        NotchMessageModel.shared.handleTabDisabled()
        NotchFeedbackModel.shared.handleTabDisabled()
        NotchLocalChatModel.shared.handleTabDisabled()
        model.todos.endTransientState()
        model.shortcuts.onCloseOrTabSwitch()
        NotchCaptureHandoffCoordinator.shared.cancelInFlight()
        model.imageConvert.handleSurfaceClosed()
        NotchSoundsEngine.shared.stopAll()
        persistClockState()
        if model.extraModule == .scratchpad { NotchScratchpadStore.shared.flush() }
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver); self.terminateObserver = nil }
        fullscreenInspections.removeAll()
        cancelWork()
        if let m = clipboardKeyMonitor { NSEvent.removeMonitor(m); clipboardKeyMonitor = nil }
        if let m = galleryKeyMonitor { NSEvent.removeMonitor(m); galleryKeyMonitor = nil }
        if let m = hubKeyMonitor { NSEvent.removeMonitor(m); hubKeyMonitor = nil }
        if let m = swipeMonitor { NSEvent.removeMonitor(m); swipeMonitor = nil }
        isDragOutActive = false
        isDropTargeted = false
        isDropImporting = false
        activityWork?.cancel(); activityWork = nil
        activityQueue.clear()
        countdownTicker?.invalidate(); countdownTicker = nil
        hydrationWork?.cancel(); hydrationWork = nil
        clockSuite = NotchClockSuite()
        didRestoreClockState = false
        syncClockModel(at: Date())
        NowPlayingMonitor.shared.stop()
        nowPlayingTicker?.invalidate(); nowPlayingTicker = nil
        model.nowPlaying = nil; model.nowPlayingArtwork = nil; model.nowPlayingPosition = nil
        model.nowPlayingAvailability = .off
        samples.removeAll()
        machine.handle(.disabled, settings: settings, now: Date())
        syncEscapeShortcut()
        state = machine.state
        // P6 review: stop() bypasses dispatch(), so a reply being composed when the notch is switched off must be
        // ended here, or its Esc monitor stays installed and the stale draft comes back with the notch.
        model.agentReplyTarget = nil
        model.agentReplyText = ""
        model.newWindowlessOpen = false
        model.newWindowlessText = ""
        model.crewBoard = nil      // P7b review: like the other transient Agents-page states
        model.isPinned = false
        model.isSearchingWeatherCity = false
        weatherViewModel?.close()
        wasWeatherOpen = false
        model.isSearchingStock = false
        stocksViewModel?.close()
        wasStocksOpen = false
        revenueViewModel?.close()
        wasRevenueOpen = false
        websiteAnalyticsViewModel?.prepareForTermination()
        wasWebsiteAnalyticsOpen = false
        model.isCreatingReminder = false
        remindersViewModel?.close()
        wasRemindersOpen = false
        closeMirror()
        if wasTeleprompterOpen { NotchTeleprompterController.shared.handleIslandClosed() }
        NotchTeleprompterController.shared.closeReaderWindow()
        wasTeleprompterOpen = false
        model.isEditingUtility = false
        model.isEditingTeleprompter = false
        isSystemSleeping = false
        renderedDisplayID = nil
        syncAgentReplyKeyboard()
        panel?.hide()
        panel = nil
        detailPanel?.orderOut(nil)
    }

    // MARK: Public intents

    /// Deliberate open: an explicit destination wins; otherwise active file work prioritizes `.files`;
    /// otherwise use the configured click rule. Respects the unified tab catalog and opens Settings recovery
    /// when every destination is hidden or unavailable.
    func reveal(page: NotchSurfaceMachine.Page? = nil) {
        reveal(destination: page.map(NotchDestinationID.init(page:)))
    }

    func reveal(destination: NotchDestinationID?) {
        if !state.isOpen {
            let pointerScreen = WindowManager.screenUnderPointer()
            surfaceScreen = resolveSurfaceScreen(pointerScreen: pointerScreen, busy: false) ?? pointerScreen
        }
        let avail = destinationAvailability
        model.destinationAvailability = avail
        let visibleAll = model.tabCatalog.visibleDestinations(availability: avail)

        guard !visibleAll.isEmpty else {
            dispatch(.openAllHiddenRecovery)
            if NSEvent.pressedMouseButtons == 0 {
                panel?.makeKeyAndOrderFront(nil)
            }
            return
        }

        if let explicit = destination {
            if let resolved = model.tabCatalog.fallbackDestination(from: explicit, availability: avail) {
                openResolvedDestination(resolved)
            } else {
                dispatch(.openAllHiddenRecovery)
            }
            if NSEvent.pressedMouseButtons == 0 {
                panel?.makeKeyAndOrderFront(nil)
            }
            return
        }

        let visibleLegacy = model.tabCatalog.visibleLegacyPages(availability: avail)
        let activeFileOp = model.task?.isRunning == true
            || model.task?.isAwaitingReview == true
            || FileOperationQueue.shared.hasActiveWork
        if activeFileOp, visibleLegacy.contains(.files) {
            DropTrayStore.shared.refreshStatuses()
            dispatch(.activateOn(.files))
        } else if !visibleLegacy.isEmpty {
            let activity = NotchHoverOpen.Activity(itemCount: machine.itemCount,
                                                  trackPlaying: NowPlayingMonitor.shared.hasTrack,
                                                  agentNeedsYou: model.agentsNeedingYou > 0,
                                                  lastPage: lastHubPage)
            let target = NotchExpandPriority.resolveOpenPage(
                explicitPage: nil,
                clickRule: NotchClickOpen.parse(clickOpensRaw),
                activity: activity,
                shown: visibleLegacy,
                hasActiveFileOperation: false
            )
            if target == .files {
                DropTrayStore.shared.refreshStatuses()
            }
            dispatch(.activateOn(target))
        } else if let firstExtra = visibleAll.first {
            openResolvedDestination(firstExtra)
        }
        if NSEvent.pressedMouseButtons == 0 {
            panel?.makeKeyAndOrderFront(nil)
        }
    }

    private func openResolvedDestination(_ id: NotchDestinationID) {
        if let page = id.legacyPage {
            if page == .files {
                DropTrayStore.shared.refreshStatuses()
            }
            dispatch(.activateOn(page))
        } else if let extra = id.extraModule {
            dispatch(.openExtra(extra))
        }
    }

    /// A tab in the open hub (B5). A hidden page resolves via the unified catalog (or recovery when all-hidden).
    func switchPage(_ page: NotchSurfaceMachine.Page) {
        let avail = destinationAvailability
        if let resolved = model.tabCatalog.fallbackDestination(from: NotchDestinationID(page: page), availability: avail) {
            if let p = resolved.legacyPage {
                dispatch(.switchPage(p))
            } else if let e = resolved.extraModule {
                dispatch(.openExtra(e))
            }
        } else {
            dispatch(.openAllHiddenRecovery)
        }
    }

    func togglePin() {
        model.isPinned.toggle()
        render()
    }

    func focusClipboardSearch() {
        guard case .expanded(.clipboard) = machine.state, model.extraModule == nil else { return }
        panel?.makeKeyAndOrderFront(nil)
        model.clipboard.focusSearchRequest += 1
    }

    func dismiss() {
        model.isPinned = false
        dispatch(.dismiss)
    }

    func setUtilityEditing(_ editing: Bool) {
        model.isEditingUtility = editing
        if editing { ensurePanelKeyForKeyboard() }
    }

    func hideForCapture(then completion: @escaping @MainActor () -> Void) {
        dismiss()
        panel?.hide()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            completion()
        }
    }

    // MARK: - Section Gallery, Extra Modules & Phase 2 Weather Registration

    private var galleryKeyMonitor: Any?
    private var weatherCoordinator: WeatherCoordinator?
    private(set) var weatherViewModel: WeatherViewModel?
    private var wasWeatherOpen = false
    var isWeatherAvailable: Bool { weatherViewModel != nil }

    private var stocksCoordinator: StocksCoordinator?
    private(set) var stocksViewModel: StocksViewModel?
    private var wasStocksOpen = false
    var isStocksAvailable: Bool { stocksViewModel != nil }

    private var revenueCoordinator: RevenueCoordinator?
    private(set) var revenueViewModel: RevenueViewModel?
    private var isLiveRevenueAttached = false
    private var wasRevenueOpen = false
    var isRevenueAvailable: Bool { revenueViewModel != nil }
    private(set) var websiteAnalyticsViewModel: WebsiteAnalyticsViewModel?
    private var wasWebsiteAnalyticsOpen = false

    /// Explicitly registers or removes a WeatherProvider.
    /// Production starts unconfigured (`nil`), registering neither fixture nor Open-Meteo Free API by default,
    /// and making zero network requests at launch.
    func configureWeather(
        provider: WeatherProvider?,
        cache: WeatherCacheStore = WeatherCacheStore(),
        locationStore: WeatherLocationStore? = UserDefaultsWeatherLocationStore(),
        locationService: WeatherLocationService = DefaultWeatherLocationService(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        weatherViewModel?.close()
        wasWeatherOpen = false
        model.isSearchingWeatherCity = false

        guard let provider else {
            weatherCoordinator = nil
            weatherViewModel = nil
            model.weatherViewModel = nil
            model.weatherAvailable = false
            model.destinationAvailability = destinationAvailability
            reconcileActiveDestinationIfNeeded()
            render()
            syncWeatherLifecycle()
            return
        }

        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            locationStore: locationStore,
            locationService: locationService,
            clock: clock
        )
        let vm = WeatherViewModel(coordinator: coordinator)
        vm.onSearchVisibilityChanged = { [weak self] open in
            guard let self else { return }
            self.model.isSearchingWeatherCity = open
            if open {
                self.ensurePanelKeyForKeyboard()
            }
        }
        weatherCoordinator = coordinator
        weatherViewModel = vm
        model.weatherViewModel = vm
        model.weatherAvailable = true
        model.destinationAvailability = destinationAvailability
        render()
        syncWeatherLifecycle()
    }

    func reloadStocksProvider() {
        let choice = UserDefaults.standard.string(forKey: StocksAPIKey.Source.preferenceKey)
            .flatMap(StocksAPIKey.Source.init(rawValue:)) ?? .twelveData
        if choice == .massive {
            configureStocks(provider: StocksAPIKey.read(for: .massive).map { MassiveStocksProvider(apiKey: $0) })
            return
        }
        var key = StocksAPIKey.read()
        #if DEBUG
        if key == nil { key = "demo" }
        #endif
        configureStocks(provider: key.map { TwelveDataStocksProvider(apiKey: $0) })
    }

    /// Registers a source without requesting quotes until Stocks is opened.
    func configureStocks(
        provider: StocksProvider?,
        watchlistStore: StocksWatchlistStore = UserDefaultsStocksWatchlistStore(),
        cache: StocksCacheStore = StocksCacheStore(),
        isConfigured: Bool = true,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        stocksViewModel?.close()
        wasStocksOpen = false
        model.isSearchingStock = false

        guard let provider else {
            stocksCoordinator = nil
            stocksViewModel = nil
            model.stocksViewModel = nil
            model.stocksAvailable = false
            model.destinationAvailability = destinationAvailability
            reconcileActiveDestinationIfNeeded()
            render()
            syncExtraModulesLifecycle()
            return
        }

        let coordinator = StocksCoordinator(
            provider: provider,
            watchlistStore: watchlistStore,
            cache: cache,
            isConfigured: isConfigured,
            clock: clock
        )
        let vm = StocksViewModel(coordinator: coordinator, clock: clock)
        vm.onSearchVisibilityChanged = { [weak self] open in
            guard let self else { return }
            self.model.isSearchingStock = open
            if open { self.ensurePanelKeyForKeyboard() }
        }
        vm.onOpenSettingsRequested = { [weak self] in
            self?.openInlineNotchSettings(showStocks: true)
        }
        stocksCoordinator = coordinator
        stocksViewModel = vm
        model.stocksViewModel = vm
        model.stocksAvailable = true
        model.destinationAvailability = destinationAvailability
        render()
        syncExtraModulesLifecycle()
    }

    /// Propagates watchlist edits made in Settings into the active Dynamic Island Stocks coordinator/view model.
    func reloadStocksWatchlist() {
        guard let coordinator = stocksCoordinator else { return }
        Task { [weak self] in
            await coordinator.reloadWatchlistFromStore()
            await MainActor.run {
                guard let self else { return }
                Task { await self.stocksViewModel?.syncState() }
            }
        }
    }

    /// Explicitly registers or removes a RevenueProvider (lazy nil by default in production).
    func configureRevenue(
        provider: RevenueProvider?,
        accountStore: RevenueAccountStore = InMemoryRevenueAccountStore(),
        cache: RevenueCacheStore = RevenueCacheStore(),
        credentialStore: RevenueCredentialStore? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        revenueViewModel?.close()
        wasRevenueOpen = false

        guard let provider else {
            revenueCoordinator = nil
            revenueViewModel = nil
            isLiveRevenueAttached = false
            model.revenueViewModel = nil
            model.revenueAvailable = false
            model.destinationAvailability = destinationAvailability
            reconcileActiveDestinationIfNeeded()
            render()
            syncExtraModulesLifecycle()
            return
        }

        let coordinator = RevenueCoordinator(
            provider: provider,
            accountStore: accountStore,
            cache: cache,
            credentialStore: credentialStore,
            clock: clock
        )
        let vm = RevenueViewModel(coordinator: coordinator, clock: clock)
        vm.onOpenSettingsRequested = { [weak self] in
            self?.dismiss()
            AppState.shared.navigate(to: .revenue)
        }
        revenueCoordinator = coordinator
        revenueViewModel = vm
        isLiveRevenueAttached = (provider is LiveRevenueProvider)
        model.revenueViewModel = vm
        model.revenueAvailable = true
        model.destinationAvailability = destinationAvailability
        render()
        syncExtraModulesLifecycle()
    }

    /// Reconciles live Revenue adapter registration from saved non-secret account configs + account-scoped Keychain.
    /// Starts disconnected (no network calls) when no account has both a saved config and a stored Keychain token.
    func syncRevenueFromSavedAccounts(
        accountStore: RevenueAccountStore = UserDefaultsRevenueAccountStore(),
        credentialStore: RevenueCredentialStore = RevenueKeychainStore.shared
    ) {
        let saved = accountStore.loadConfigs()
        let active = saved.filter { _, cfg in
            credentialStore.hasToken(for: cfg.source, accountId: cfg.accountId)
        }
        if active.isEmpty {
            if isLiveRevenueAttached {
                configureRevenue(provider: nil)
            }
            return
        }
        if !isLiveRevenueAttached || revenueCoordinator == nil {
            let liveProvider = LiveRevenueProvider(credentialStore: credentialStore)
            configureRevenue(
                provider: liveProvider,
                accountStore: accountStore,
                credentialStore: credentialStore
            )
        }
    }

    /// Explicit Settings action: saves account-scoped token to Keychain + metadata to UserDefaults and activates live adapter.
    func connectRevenueAccount(
        _ config: SourceAccountConfig,
        token: String,
        accountStore: RevenueAccountStore = UserDefaultsRevenueAccountStore(),
        credentialStore: RevenueCredentialStore = RevenueKeychainStore.shared
    ) -> Bool {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingConfigs = accountStore.loadConfigs()
        let previousAccountId = existingConfigs[config.source]?.accountId

        if !trimmedToken.isEmpty {
            guard credentialStore.setToken(trimmedToken, for: config.source, accountId: config.accountId) else {
                return false
            }
        } else if !credentialStore.hasToken(for: config.source, accountId: config.accountId) {
            return false
        }

        if let previousAccountId, previousAccountId != config.accountId {
            credentialStore.deleteToken(for: config.source, accountId: previousAccountId)
        }
        accountStore.saveConfig(config)

        if isLiveRevenueAttached, let coord = revenueCoordinator {
            Task { await coord.configureSource(config) }
        } else {
            syncRevenueFromSavedAccounts(accountStore: accountStore, credentialStore: credentialStore)
        }
        return true
    }

    /// Explicit Settings action: cancels in-flight sync, deletes account-scoped Keychain token, clears cache and config.
    func disconnectRevenueAccount(
        _ source: RevenueSourceKind,
        accountStore: RevenueAccountStore = UserDefaultsRevenueAccountStore(),
        credentialStore: RevenueCredentialStore = RevenueKeychainStore.shared
    ) {
        let existing = accountStore.loadConfigs()
        if let prevId = existing[source]?.accountId {
            credentialStore.deleteToken(for: source, accountId: prevId)
        }
        accountStore.removeConfig(for: source)
        let remaining = accountStore.loadConfigs().filter { _, cfg in
            credentialStore.hasToken(for: cfg.source, accountId: cfg.accountId)
        }
        if let coord = revenueCoordinator, isLiveRevenueAttached {
            Task {
                await coord.disconnectSource(source)
                await MainActor.run {
                    if remaining.isEmpty {
                        self.configureRevenue(provider: nil)
                    }
                }
            }
        } else if remaining.isEmpty && isLiveRevenueAttached {
            configureRevenue(provider: nil)
        }
    }

    private func syncWeatherLifecycle() {
        syncExtraModulesLifecycle()
    }

    private func syncExtraModulesLifecycle() {
        let isExpanded: Bool = {
            if case .expanded = machine.state { return true }
            return false
        }()

        let weatherOpen = isExpanded && isWeatherAvailable && model.extraModule == .weather
        if weatherOpen && !wasWeatherOpen {
            wasWeatherOpen = true
            weatherViewModel?.onAppear()
        } else if !weatherOpen && wasWeatherOpen {
            wasWeatherOpen = false
            model.isSearchingWeatherCity = false
            weatherViewModel?.close()
        }

        let stocksOpen = isExpanded && isStocksAvailable && model.extraModule == .stocks
        if stocksOpen && !wasStocksOpen {
            wasStocksOpen = true
            stocksViewModel?.onAppear()
        } else if !stocksOpen && wasStocksOpen {
            wasStocksOpen = false
            model.isSearchingStock = false
            stocksViewModel?.close()
        }

        let revenueOpen = isExpanded && isRevenueAvailable && model.extraModule == .revenue
        if revenueOpen && !wasRevenueOpen {
            wasRevenueOpen = true
            revenueViewModel?.onAppear()
        } else if !revenueOpen && wasRevenueOpen {
            wasRevenueOpen = false
            revenueViewModel?.close()
        }

        let analyticsOpen = isExpanded && model.extraModule == .websiteAnalytics
        if analyticsOpen && !wasWebsiteAnalyticsOpen {
            wasWebsiteAnalyticsOpen = true
            ensureWebsiteAnalyticsViewModel().onAppear()
        } else if !analyticsOpen && wasWebsiteAnalyticsOpen {
            wasWebsiteAnalyticsOpen = false
            websiteAnalyticsViewModel?.close()
        }

        let teleprompterOpen = isExpanded && model.extraModule == .teleprompter
        if teleprompterOpen && !wasTeleprompterOpen {
            NotchTeleprompterController.shared.onEditingStateChanged = { [weak self] editing in
                guard let self else { return }
                self.model.isEditingTeleprompter = editing
                if editing { self.ensurePanelKeyForKeyboard() }
            }
        } else if !teleprompterOpen && wasTeleprompterOpen {
            NotchTeleprompterController.shared.handleIslandClosed()
        }
        wasTeleprompterOpen = teleprompterOpen

        let remindersOpen = isExpanded && model.extraModule == .reminders
        if remindersOpen && !wasRemindersOpen {
            wasRemindersOpen = true
            ensureRemindersViewModel().onAppear()
        } else if !remindersOpen && wasRemindersOpen {
            wasRemindersOpen = false
            model.isCreatingReminder = false
            remindersViewModel?.close()
        }
    }

    private var remindersViewModel: RemindersViewModel?
    private var wasRemindersOpen = false
    private var wasTeleprompterOpen = false

    @discardableResult
    func ensureWebsiteAnalyticsViewModel() -> WebsiteAnalyticsViewModel {
        if let existing = websiteAnalyticsViewModel {
            model.websiteAnalyticsViewModel = existing
            return existing
        }
        let viewModel = WebsiteAnalyticsViewModel.makeDefault()
        viewModel.onOpenSettingsRequested = { [weak self] in
            self?.dismiss()
            AppState.shared.navigate(to: .websiteAnalytics)
        }
        websiteAnalyticsViewModel = viewModel
        model.websiteAnalyticsViewModel = viewModel
        viewModel.setDestinationEnabled(model.tabCatalog.isEnabled(.websiteAnalytics))
        return viewModel
    }

    @discardableResult
    private func ensureRemindersViewModel() -> RemindersViewModel {
        if let existing = remindersViewModel {
            model.remindersViewModel = existing
            return existing
        }
        let vm = RemindersViewModel(store: RemindersEventKitStore())
        vm.onComposerStateChanged = { [weak self] open in
            guard let self else { return }
            self.model.isCreatingReminder = open
            if open { self.ensurePanelKeyForKeyboard() }
        }
        remindersViewModel = vm
        model.remindersViewModel = vm
        return vm
    }

    func toggleSectionsGallery() {
        if machine.activeExtra == .sections {
            dispatch(.closeExtra)
            reconcileActiveDestinationIfNeeded()
        } else {
            dispatch(.openExtra(.sections))
        }
    }

    func openExtraModule(_ extra: NotchExtraModule) {
        if extra == .sections {
            dispatch(.openExtra(.sections))
            return
        }
        guard let id = NotchDestinationID(extra: extra),
              model.tabCatalog.isOpenable(id, availability: destinationAvailability) else { return }
        dispatch(.openExtra(extra))
    }

    func closeExtraModule() {
        if machine.activeExtra == .settings { returnFromInlineNotchSettings(); return }
        guard machine.activeExtra != nil else { return }
        dispatch(.closeExtra)
        reconcileActiveDestinationIfNeeded()
    }

    func selectGalleryDestination(_ dest: NotchGalleryDestination) {
        guard let id = NotchDestinationID(destination: dest) else { return }
        selectDestination(id)
    }

    func selectDestination(_ id: NotchDestinationID) {
        guard model.tabCatalog.isOpenable(id, availability: destinationAvailability) else { return }
        openResolvedDestination(id)
    }

    private func syncGalleryKeyboard() {
        let wantsKeys = model.extraModule == .sections && machine.state.isOpen
        if wantsKeys {
            panel?.makeKeyAndOrderFront(nil)
            guard galleryKeyMonitor == nil else { return }
            galleryKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.panel?.isKeyWindow == true,
                      self.model.extraModule == .sections, self.machine.state.isOpen else { return e }
                if e.keyCode == 53 { // Esc
                    self.closeExtraModule()
                    return nil
                }
                let mods = e.modifierFlags.intersection([.command, .control, .option])
                if mods.isEmpty, let chars = e.charactersIgnoringModifiers,
                   let dest = NotchGalleryRules.destination(
                       forKeyCharacter: chars,
                       catalog: self.model.tabCatalog,
                       availability: self.destinationAvailability
                   ) {
                    self.selectGalleryDestination(dest)
                    return nil
                }
                return e
            }
        } else if let m = galleryKeyMonitor {
            NSEvent.removeMonitor(m)
            galleryKeyMonitor = nil
        }
    }

    /// The view calls this after files were dropped on the surface.
    func filesDropped() {
        isDropImporting = false
        dispatch(.dropped(count: DropTrayStore.shared.items.count))
    }

    func setDropTargeted(_ targeted: Bool) {
        guard isDropTargeted != targeted else { return }
        isDropTargeted = targeted
        if targeted {
            leftAt = nil; graceWork?.cancel(); graceWork = nil
        } else {
            tick()
        }
    }

    func beginDropImport() {
        isDropImporting = true
        leftAt = nil; graceWork?.cancel(); graceWork = nil
    }

    func endDropImport() {
        isDropImporting = false
    }

    func beginDragOutSession() {
        isDragOutActive = true
        leftAt = nil; graceWork?.cancel(); graceWork = nil
    }

    func endDragOutSession() {
        isDragOutActive = false
        leftAt = nil; graceWork?.cancel(); graceWork = nil
        tick()
    }

    func ensurePanelKeyForKeyboard() {
        guard machine.state.isOpen, NSEvent.pressedMouseButtons == 0 else { return }
        panel?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Drop Tray actions (XF-T41: Quick Look, Share, Browser Pane Queue)

    func quickLookTrayItems(_ items: [DropTrayStore.Item]) {
        DropTrayStore.shared.refreshStatuses()
        let liveIDs = Set(items.map(\.id))
        let urls = DropTrayStore.shared.items
            .filter { liveIDs.contains($0.id) && $0.status.isActionable }
            .map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else {
            model.notice = "Không thể xem nhanh — tệp đã di chuyển hoặc thiếu quyền."
            return
        }
        model.notice = nil
        quickLook.present(urls: urls)
    }

    func shareTrayItems(_ items: [DropTrayStore.Item], from anchorView: NSView? = nil) {
        DropTrayStore.shared.refreshStatuses()
        let liveIDs = Set(items.map(\.id))
        let urls = DropTrayStore.shared.items
            .filter { liveIDs.contains($0.id) && $0.status.isActionable }
            .map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else {
            model.notice = "Không có tệp hợp lệ để chia sẻ."
            return
        }
        model.notice = nil
        let picker = NSSharingServicePicker(items: urls)
        if let view = anchorView ?? panel?.contentView {
            let rect = NSRect(x: view.bounds.midX - 1, y: view.bounds.midY - 1, width: 2, height: 2)
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        } else {
            airDropFileURLs(urls)
        }
    }

    func airDropTrayItems(_ items: [DropTrayStore.Item]) {
        DropTrayStore.shared.refreshStatuses()
        let liveIDs = Set(items.map(\.id))
        let urls = DropTrayStore.shared.items
            .filter { liveIDs.contains($0.id) && $0.status.isActionable }
            .map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else {
            model.notice = "Không có tệp hợp lệ để chia sẻ."
            return
        }
        airDropFileURLs(urls)
    }

    func airDropFileURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            model.notice = "AirDrop không khả dụng cho các tệp này trên máy này."
            return
        }
        model.notice = nil
        service.perform(withItems: urls)
    }

    func pickAndAirDropFiles() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = true
        if openPanel.runModal() == .OK, !openPanel.urls.isEmpty {
            airDropFileURLs(openPanel.urls)
        }
    }

    func sendTrayItemsToActivePane(_ items: [DropTrayStore.Item], copy: Bool) {
        DropTrayStore.shared.refreshStatuses()
        let liveIDs = Set(items.map(\.id))
        let paths = DropTrayStore.shared.items
            .filter { liveIDs.contains($0.id) && $0.status.isActionable }
            .map(\.path)
        guard !paths.isEmpty else {
            model.notice = "Không có tệp hợp lệ để thao tác."
            return
        }
        model.notice = nil
        let started = DropTrayBrowserBridge.send(paths, copy: copy) { [weak self] completion in
            guard let self else { return }
            let failedCount = completion.failedReasons.count + completion.skippedSources.count
            if failedCount > 0 {
                self.model.notice = copy
                    ? "Một số tệp sao chép thất bại — các mục vẫn được giữ trong khay."
                    : "Một số tệp chuyển thất bại — các mục chưa chuyển vẫn được giữ trong khay."
            } else if completion.state == .cancelled {
                self.model.notice = "Thao tác đã dừng — các mục chưa chuyển vẫn được giữ trong khay."
            }
        }
        if !started {
            model.notice = FileOperationQueue.shared.lastErrorKey
                ?? "Không thể gửi sang ngăn trình duyệt hiện tại."
        }
    }

    // MARK: - Expanded Hub Keyboard (Files selection, Quick Look, Tab Switch, Esc)

    private var hubKeyMonitor: Any?
    private var escapeKeyMonitors: [Any] = []

    private func syncEscapeShortcut() {
        guard case .expanded = machine.state else {
            escapeKeyMonitors.forEach(NSEvent.removeMonitor)
            escapeKeyMonitors.removeAll()
            return
        }
        guard escapeKeyMonitors.isEmpty else { return }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard Self.isPlainEscape(event), let self, case .expanded = self.machine.state else { return event }
            let wasKey = self.panel?.isKeyWindow == true
            self.dismiss()
            return wasKey ? nil : event
        }) {
            escapeKeyMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard Self.isPlainEscape(event) else { return }
            runOnMainActor {
                guard let self, case .expanded = self.machine.state else { return }
                self.dismiss()
            }
        }) {
            escapeKeyMonitors.append(global)
        }
    }

    private nonisolated static func isPlainEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53 && !event.isARepeat &&
            event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
    }

    private func syncHubKeyboard() {
        let onClipboard = (machine.state == .expanded(.clipboard) && model.extraModule == nil)
        let onGallery = (model.extraModule == .sections)
        let composingAgent = (machine.state == .expanded(.agents) && (model.agentReplyTarget != nil || model.newWindowlessOpen))
        let wantsKeys: Bool = {
            guard case .expanded = machine.state else { return false }
            return !onClipboard && !onGallery && !composingAgent
        }()
        if wantsKeys {
            guard hubKeyMonitor == nil else { return }
            hubKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.panel?.isKeyWindow == true else { return e }
                if e.keyCode == 53, self.model.extraModule == .weather, self.weatherViewModel?.isShowingSearch == true {
                    self.weatherViewModel?.closeSearch()
                    return nil
                }
                if e.keyCode == 53, self.model.extraModule == .stocks, self.stocksViewModel?.isShowingSearch == true {
                    self.stocksViewModel?.closeSearch()
                    return nil
                }
                if self.model.extraModule == .emoji {
                    if e.keyCode == 53 {
                        if self.model.emoji.query.isEmpty {
                            self.closeExtraModule()
                        } else {
                            self.model.emoji.clearSearch()
                        }
                        return nil
                    }
                    if e.charactersIgnoringModifiers == "f", e.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
                        self.model.emoji.focusSearchRequest += 1
                        return nil
                    }
                }
                if self.model.extraModule == .todos, e.window === self.panel,
                   e.modifierFlags.intersection([.option, .control]).isEmpty {
                    let outcome = self.model.todos.handleKeyEvent(NotchTodoKeyEvent(
                        keyCode: e.keyCode,
                        command: e.modifierFlags.contains(.command),
                        shift: e.modifierFlags.contains(.shift)
                    ))
                    switch outcome {
                    case .handled: return nil
                    case .ignored: return e
                    case .dismissSurface:
                        self.closeExtraModule()
                        return nil
                    }
                }
                if self.model.extraModule == .links {
                    if e.keyCode == 53 {
                        if self.model.links.query.isEmpty {
                            self.closeExtraModule()
                        } else {
                            self.model.links.clearSearch()
                        }
                        return nil
                    }
                    if e.charactersIgnoringModifiers == "f", e.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
                        self.model.links.focusSearchRequest += 1
                        return nil
                    }
                }
                if e.keyCode == 53, self.model.extraModule == .scratchpad {
                    if NotchScratchpadStore.shared.confirmingClear {
                        NotchScratchpadStore.shared.cancelClear()
                    } else {
                        self.closeExtraModule()
                    }
                    return nil
                }
                // Never intercept keystrokes while a text editor / field editor has focus.
                if self.panel?.firstResponder is NSTextView { return e }
                return self.handleHubKey(e) ? nil : e
            }
        } else if let m = hubKeyMonitor {
            NSEvent.removeMonitor(m)
            hubKeyMonitor = nil
        }
    }

    private func handleHubKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags
        let onFiles = (machine.state == .expanded(.files) && model.extraModule == nil)
        guard let action = NotchHubKeyAction.decode(
            keyCode: e.keyCode,
            characters: e.charactersIgnoringModifiers,
            command: mods.contains(.command),
            shift: mods.contains(.shift),
            option: mods.contains(.option),
            control: mods.contains(.control),
            onFilesPage: onFiles
        ) else { return false }

        switch action {
        case .escape:
            if model.extraModule == .weather, weatherViewModel?.isShowingSearch == true {
                weatherViewModel?.closeSearch()
            } else if model.extraModule == .stocks, stocksViewModel?.isShowingSearch == true {
                stocksViewModel?.closeSearch()
            } else if model.extraModule != nil {
                closeExtraModule()
            } else if onFiles && !model.traySelection.isEmpty {
                model.traySelection.clear()
            } else {
                dismiss()
            }
            return true
        case .toggleMoreGallery:
            toggleSectionsGallery()
            return true
        case .switchToSlot(let slot):
            let visible = model.tabCatalog.visibleDestinations(availability: destinationAvailability)
            guard slot >= 1, slot <= visible.count else { return false }
            openResolvedDestination(visible[slot - 1])
            return true
        case .selectAll:
            model.traySelection.selectAll(DropTrayStore.shared.items.map(\.id))
            return true
        case .moveSelection(let delta, let extend):
            model.traySelection.move(delta: delta, in: DropTrayStore.shared.items.map(\.id), extend: extend)
            return true
        case .quickLook:
            let selected = selectedOrAllTrayItems(fallbackToFirst: true)
            if !selected.isEmpty { quickLookTrayItems(selected) }
            return true
        case .openSelected:
            let selected = selectedOrAllTrayItems(fallbackToFirst: true).filter { $0.status.isActionable }
            guard !selected.isEmpty else { return false }
            for item in selected.prefix(10) { NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) }
            return true
        case .removeSelected:
            let ids = model.traySelection.selectedIDs
            guard !ids.isEmpty else { return false }
            let paths = DropTrayStore.shared.items.filter { ids.contains($0.id) }.map(\.path)
            DropTrayStore.shared.removePaths(paths)
            model.traySelection.prune(validIDs: Set(DropTrayStore.shared.items.map(\.id)))
            return true
        }
    }

    private func selectedOrAllTrayItems(fallbackToFirst: Bool) -> [DropTrayStore.Item] {
        let items = DropTrayStore.shared.items
        if !model.traySelection.isEmpty {
            return items.filter { model.traySelection.contains($0.id) }
        }
        if fallbackToFirst, let first = items.first { return [first] }
        return []
    }

    private func isPageAvailable(_ p: NotchSurfaceMachine.Page) -> Bool {
        switch p {
        case .files, .clipboard, .timer: return true
        case .nowPlaying: return model.nowPlayingAvailability != .off
        case .agents, .aiUsage: return model.agentsEnabled
        case .calendar: return model.calendarEnabled
        }
    }

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

        if NSEvent.pressedMouseButtons & 1 == 1 || isDragOutActive || isDropTargeted || isDropImporting {
            // Never collapse mid-drag — the drag may come back; the leave clock restarts after the release.
            leftAt = nil; graceWork?.cancel(); graceWork = nil
            zoneEnteredAt = nil; dwellWork?.cancel(); dwellWork = nil
            guard NSEvent.pressedMouseButtons & 1 == 1, !isDragOutActive else { return }
            guard model.extraModule != .imageConvert else { return }
            // Neither drag trigger on ⇒ nothing to decide, so never touch the drag pasteboard (a
            // pasteboard-server round trip) on the user's window and text drags.
            let s = settings
            guard s.dragIntoNotchOpens || s.shakeOpens else { return }
            let pb = NSPasteboard(name: .drag)
            guard dragSession.carriesFiles(now: now, changeCount: { pb.changeCount },
                                           types: { (pb.types ?? []).map(\.rawValue) }) else { return }
            guard pointerScreenCanOpenSurface(screen) else { return }
            samples.append((point, now))
            let cutoff = now.addingTimeInterval(-0.6)          // keep ~0.6 s of movement for the shake
            samples.removeAll { $0.time < cutoff }
            if NotchSurfaceLayout.dragZone(notch: notch, screen: screen.frame).contains(point) {
                if !state.isOpen { surfaceScreen = resolveSurfaceScreen(pointerScreen: screen, busy: false) ?? screen }
                dispatch(.fileDragInZone)
            } else if detectShake() {        // the machine ignores a shake while already expanded
                samples.removeAll()
                shakePoint = point
                if !state.isOpen { surfaceScreen = resolveSurfaceScreen(pointerScreen: screen, busy: false) ?? screen }
                dispatch(.shake)
            }
            return
        }

        let wingProj = collapsedProjection
        let zone = NotchSurfaceLayout.hoverZone(notch: notch, screen: screen.frame, itemCount: wingProj.itemCount,
                                                nowPlayingActive: wingProj.nowPlayingActive,
                                                timerActive: wingProj.timerActive, agentActive: wingProj.agentActive,
                                                agentBusy: wingProj.agentBusy, agentCount: wingProj.agentCount,
                                                visible: screen.visibleFrame,
                                                pillShown: pillOnPlainScreens && badgeShown && machine.state == .collapsed)
        let wings = NotchSurfaceLayout.wingItems(itemCount: wingProj.itemCount, timerActive: wingProj.timerActive,
                                                 nowPlayingActive: wingProj.nowPlayingActive, agentActive: wingProj.agentActive,
                                                 agentBusy: wingProj.agentBusy, agentCount: wingProj.agentCount)
        pointerOnAgentEdge = NotchSurfaceLayout.agentEdgeRect(notch: notch, left: wings.left, right: wings.right)?.contains(point) ?? false
        if zone.contains(point), pointerScreenCanOpenSurface(screen) {
            leftAt = nil; graceWork?.cancel(); graceWork = nil
            if zoneEnteredAt == nil {
                zoneEnteredAt = now
                armRetick(after: settings.hoverDwell, slot: \.dwellWork)
            }
            if !state.isOpen { surfaceScreen = resolveSurfaceScreen(pointerScreen: screen, busy: false) ?? screen }
            dispatch(.hoverInZone(since: zoneEnteredAt ?? now))
            return
        }
        if zone.contains(point), !state.isOpen { return }
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

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private var surfaceIsBusy: Bool {
        machine.state != .collapsed || machine.taskRunning || model.agentReplyTarget != nil || model.newWindowlessOpen
    }

    private func resolveSurfaceScreen(pointerScreen: NSScreen? = nil, busy: Bool) -> NSScreen? {
        let screens = NSScreen.screens
        let displays = screens.compactMap { screen -> NotchDisplayTargetRules.Display? in
            guard let id = Self.displayID(for: screen) else { return nil }
            return NotchDisplayTargetRules.Display(
                id: id,
                isMain: screen == NSScreen.screens.first,
                hasPhysicalNotch: screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
            )
        }
        let activeID = surfaceScreen.flatMap(Self.displayID(for:))
        let resolution = NotchDisplayTargetRules.resolve(
            target: NotchDisplayTargetRules.Target.parse(displayTargetRaw),
            selectedDisplayID: selectedDisplayID,
            displays: displays,
            pointerDisplayID: pointerScreen.flatMap(Self.displayID(for:)),
            activeDisplayID: busy ? activeID : nil,
            busy: busy
        )
        guard let id = resolution?.displayID else { return nil }
        return screens.first { Self.displayID(for: $0) == id }
    }

    /// A fixed display policy only accepts hover/drag triggers on its resolved target. Automatic mode
    /// continues to follow the pointer, while an open surface keeps its current display until it closes.
    private func pointerScreenCanOpenSurface(_ pointerScreen: NSScreen) -> Bool {
        guard let target = resolveSurfaceScreen(pointerScreen: pointerScreen, busy: surfaceIsBusy),
              let pointerID = Self.displayID(for: pointerScreen),
              let targetID = Self.displayID(for: target) else { return false }
        return pointerID == targetID
    }

    // MARK: Machine → screen

    private func dispatch(_ event: NotchSurfaceMachine.Event) {
        if case .openExtra(.websiteAnalytics) = event {
            _ = ensureWebsiteAnalyticsViewModel()
        }
        let openStart = !loggedFirstIslandOpen ? ContinuousClock.now : nil
        let before = machine
        machine.handle(event, settings: settings, now: Date())
        guard machine != before else { return }
        state = machine.state
        model.extraModule = machine.activeExtra
        if before.activeExtra == .settings, machine.activeExtra != .settings {
            notchSettingsReturnDestination = nil
        }
        if before.activeExtra == .message, machine.activeExtra != .message {
            NotchMessageModel.shared.isInputFocused = false
        }
        if before.activeExtra == .localChat, machine.activeExtra != .localChat {
            NotchLocalChatModel.shared.handleTabDisabled()
        }
        if before.activeExtra == .todos, machine.activeExtra != .todos {
            model.todos.endTransientState()
        }
        if before.activeExtra == .shortcuts, machine.activeExtra != .shortcuts {
            model.shortcuts.onCloseOrTabSwitch()
        }
        if before.activeExtra == .imageConvert, machine.activeExtra != .imageConvert {
            model.imageConvert.handleSurfaceClosed()
        }
        model.showingAllHiddenRecovery = machine.showingAllHiddenRecovery
        if case .expanded = machine.state {
        } else {
            model.traySelection.clear()
            model.isPinned = false
        }
        if case .itemsChanged = event {
            model.traySelection.prune(validIDs: Set(DropTrayStore.shared.items.map(\.id)))
        }
        if case .expanded(let p) = machine.state, machine.activeExtra == nil, !machine.showingAllHiddenRecovery {
            lastHubPage = p   // N2: for "Trang mở lần cuối"
            if p == .files { DropTrayStore.shared.refreshStatuses() }
        }
        let pageVisible = machine.activeExtra == nil && !machine.showingAllHiddenRecovery
        CalendarGlanceMonitor.shared.setPageOpen(pageVisible && machine.state == .expanded(.calendar))   // N4: the minute ticker only while shown
        // §3b #37 / P2: the usage scan runs only while the Agents page or the AI usage tool is on screen.
        AgentUsageMonitor.shared.setPageOpen(pageVisible && (machine.state == .expanded(.agents) || machine.state == .expanded(.aiUsage)))
        AgentSessionMonitor.shared.setAgentsPageOpen(pageVisible && machine.state == .expanded(.agents))
        if !(pageVisible && machine.state == .expanded(.agents)), model.agentReplyTarget != nil { endAgentReply() }   // P6: leaving the page ends composing
        if !(pageVisible && machine.state == .expanded(.agents)), model.newWindowlessOpen { cancelNewWindowless() }   // P7a: same for the composer
        render()
        if !loggedFirstIslandOpen, let start = openStart, case .expanded(let page) = machine.state {
            loggedFirstIslandOpen = true
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            Self.perfLog.info("island_first_open page=\(page.rawValue, privacy: .public) ms=\(ms)")
        }
        if machine.activeExtra == .todos, before.activeExtra != .todos {
            ensurePanelKeyForKeyboard()
        }
        syncWeatherLifecycle()
        syncEscapeShortcut()
        syncClipboardKeyboard()
        syncGalleryKeyboard()
        syncHubKeyboard()
        syncAgentReplyKeyboard()
        syncHubSwipe()
        syncNowPlayingTicker()
        syncWaveform()
        // A notice held while the hub was open comes back now.
        if machine.state.isIdle, activityQueue.resume() != nil { showCurrentActivity() }
    }

    /// §3b #21 — the tap runs only while a waveform is on screen (the Now Playing page, or the peek showing the track).
    func syncWaveform() {
        let onNowPlaying = machine.state == .expanded(.nowPlaying) && machine.activeExtra == nil && !machine.showingAllHiddenRecovery
        let shown = onNowPlaying || (machine.state == .peek && machine.itemCount == 0 && model.tabCatalog.isEnabled(.nowPlaying))
        AudioTapMonitor.shared.update(waveformVisible: shown)
    }

    // MARK: - D1 #43: two-finger swipe over the tab band changes page

    private var swipeMonitor: Any?
    private var swipe = NotchPages.SwipeAccumulator()

    /// A LOCAL scroll-wheel monitor only while the hub is open. Scroll events reach the window under the
    /// pointer whether or not it is key, so the local monitor sees them without making the panel key.
    /// Only the top band changes the active page on swipe. The bottom tab strip
    /// and page scrollers need their own horizontal scroll events.
    private func syncHubSwipe() {
        if case .expanded = machine.state {
            guard swipeMonitor == nil else { return }
            swipe.reset()
            swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let panel = self.panel, e.window === panel else { return e }
                if e.phase == .ended || e.phase == .cancelled || e.momentumPhase == .ended { self.swipe.reset(); return e }
                let drawnTop = self.drawnFrame.maxY - panel.frame.minY          // N1: the drawn shape's top, in window space
                let metrics = NotchSurfaceLayout.Metrics.standard
                let headerHeight: CGFloat = self.model.notchSize.height > 0
                    ? max(self.model.notchSize.height, metrics.bandHeight) + 2
                    : metrics.plainHeaderHeight + 2
                let inHeader = e.locationInWindow.y >= drawnTop - headerHeight
                let inHorizontalBounds = e.locationInWindow.x >= (self.drawnFrame.minX - panel.frame.minX)
                    && e.locationInWindow.x <= (self.drawnFrame.maxX - panel.frame.minX)
                guard inHorizontalBounds, inHeader, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { return e }
                if let dir = self.swipe.feed(deltaX: e.scrollingDeltaX),
                   self.machine.activeExtra == nil,
                   !self.machine.showingAllHiddenRecovery,
                   case .expanded(let page) = self.machine.state,
                   let next = NotchPages.swipeTarget(
                       from: page,
                       direction: dir,
                       pages: self.model.tabCatalog.visibleLegacyPages(availability: self.destinationAvailability)
                   ) {   // P1: the dots are the sequence; a tool or hidden tab does not swipe
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
        if case .expanded(.clipboard) = machine.state, model.extraModule == nil {
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
        let p = SurfacePanel(kind: .notch, size: CGSize(width: 650, height: 228))
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

    private func closeMirror() {
        model.mirrorController?.close()
        model.mirrorController = nil
    }

    private func synchronizeMirrorVisibility() {
        guard case .expanded = machine.state, machine.activeExtra == .mirror,
              panel?.isVisible == true, !isSystemSleeping else {
            closeMirror()
            return
        }
        if model.mirrorController == nil {
            let controller = MirrorCaptureController()
            controller.onAppear()
            model.mirrorController = controller
        }
    }

    private func hideSurface(_ panel: SurfacePanel) {
        if model.extraModule == .localChat {
            NotchLocalChatModel.shared.handleTabDisabled()
        }
        closeMirror()
        panel.hide()
        drawnSize = nil
    }

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
        guard enabled, !isSystemSleeping else { hideSurface(panel); return }
        guard let screen = resolveSurfaceScreen(busy: surfaceIsBusy) else {
            hideSurface(panel)
            return
        }
        // Keep a live NSScreen reference for the open session. If it disconnects, the resolver
        // returns a connected fallback and this reference is refreshed without discarding page/task state.
        surfaceScreen = screen
        if shouldHideForFullscreen(on: screen) {
            hideSurface(panel)
            return
        }
        let notch = Self.notch(on: screen)

        let settingsPresented = machine.activeExtra == .settings
        let scale = Self.displayID(for: screen).map { displayScale(for: $0) } ?? .regular
        let metrics = NotchSurfaceLayout.Metrics.standard.resized(scale)
        model.displayScale = scale
        let layoutState: NotchSurfaceMachine.State = {
            if case .expanded = machine.state, model.extraModule != nil {
                return model.preferNarrowExtraModule && !settingsPresented ? .expanded(.nowPlaying) : .expanded(.aiUsage)
            }
            return machine.state
        }()
        let wingProj = collapsedProjection
        let useCollapsedProjection = (machine.state == .collapsed)
        guard let target = NotchSurfaceLayout.frame(for: layoutState, anchor: machine.anchor,
                                                    itemCount: useCollapsedProjection ? wingProj.itemCount : machine.itemCount,
                                                    notch: notch,
                                                    screen: screen.frame, visible: screen.visibleFrame,
                                                    pointer: shakePoint,
                                                    timerActive: useCollapsedProjection ? wingProj.timerActive : clockSuite.hasAnyActiveClock,
                                                    nowPlayingActive: useCollapsedProjection ? wingProj.nowPlayingActive : NowPlayingMonitor.shared.hasTrack,
                                                    agentActive: useCollapsedProjection ? wingProj.agentActive : model.agentActive,
                                                    agentBusy: useCollapsedProjection ? wingProj.agentBusy : model.agentBusy,
                                                    agentCount: useCollapsedProjection ? wingProj.agentCount : model.agentCount,
                                                    pillOnPlainScreens: pillOnPlainScreens,
                                                    compactActivity: model.activity?.kind.isKeyFeedback == true,
                                                    settingsPresented: settingsPresented, metrics: metrics) else {
            model.state = .collapsed
            model.itemCount = machine.itemCount
            hideSurface(panel)
            renderedAnchor = .notch
            return
        }
        drawnSize = target.size
        let wasVisible = panel.isVisible
        let anchorChanged = machine.anchor != renderedAnchor
        let displayID = Self.displayID(for: screen)
        let displayChanged = renderedDisplayID != displayID
        renderedDisplayID = displayID
        renderedAnchor = machine.anchor
        panel.hasShadow = machine.anchor == .pointer      // at the notch a shadow would reveal the rect

        let fixed: CGRect
        switch machine.anchor {
        case .notch:
            fixed = NotchSurfaceLayout.panelFrame(notch: notch, screen: screen.frame, settingsPresented: settingsPresented, metrics: metrics)
        case .pointer:
            // A tray at the pointer may have been dragged aside by its title strip: while it stays visible at
            // the pointer, every update (a file added, a page change) keeps it where the user put it.
            let size = NotchSurfaceLayout.panelSize(notch: notch, settingsPresented: settingsPresented, metrics: metrics)
            if wasVisible && !anchorChanged {
                if panel.frame.size != size || displayChanged || !screen.visibleFrame.intersects(panel.frame) {
                    let resized = CGRect(x: panel.frame.midX - size.width / 2, y: panel.frame.maxY - size.height,
                                         width: size.width, height: size.height)
                    fixed = SurfaceGeometry.clamp(resized, into: screen.visibleFrame)
                } else {
                    fixed = panel.frame
                }
            } else {
                fixed = SurfaceGeometry.clamp(CGRect(x: target.midX - size.width / 2, y: target.maxY - size.height,
                                                     width: size.width, height: size.height), into: screen.visibleFrame)
            }
        }
        if panel.frame != fixed { panel.setFrame(fixed, display: true) }   // first show, anchor change or screen change only

        if !wasVisible || anchorChanged {
            // D0c: at the notch the surface GROWS OUT OF THE NOTCH — the shape starts at the notch's own size and
            // springs to the state's size on the next run-loop turn. At the pointer (a shake) it appears at once.
            let grow = NotchMotionPolicy.shouldGrowFromNotch(
                wasVisible: wasVisible,
                anchor: machine.anchor,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                model.appearFromNotch = grow
                applyModel(notch: notch)
            }
            if !wasVisible { panel.orderFrontRegardless() }   // never key: the user's app keeps focus
            synchronizeMirrorVisibility()
            if grow {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.model.appearFromNotch = false }
                }
            }
            return
        }
        applyModel(notch: notch)
        synchronizeMirrorVisibility()
    }

    private func shouldHideForFullscreen(on screen: NSScreen) -> Bool {
        let policy = NotchFullscreenVisibility.parse(fullscreenVisibilityRaw)
        guard policy != .show else { return false }
        let expanded: Bool = { if case .expanded = machine.state { return true }; return false }()
        let mustRemainVisible = NotchFullscreenRules.mustRemainVisible(
            expanded: expanded, taskRunning: machine.taskRunning, agentsNeedingYou: model.agentsNeedingYou,
            replyPending: model.agentReplyTarget != nil, composerOpen: model.newWindowlessOpen,
            activityHasButtons: !(model.activity?.buttons.isEmpty ?? true))
        guard !mustRemainVisible else { return false }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        let displayID = displayNumber.uint32Value
        let inspection: FullscreenInspection
        if let cached = fullscreenInspections[displayID], cached.frontmostPID == frontmostPID {
            inspection = cached
        } else {
            inspection = inspectFullscreenWindow(on: displayID, topInset: screen.safeAreaInsets.top,
                                                 frontmostPID: frontmostPID)
            fullscreenInspections[displayID] = inspection
        }
        let snapshot = NowPlayingMonitor.shared.liveSnapshot
        return NotchFullscreenRules.shouldHide(policy, context: .init(
            fullscreenOwnerPID: inspection.fullscreenOwnerPID,
            frontmostPID: inspection.frontmostPID,
            mediaPID: snapshot?.pid,
            mediaPlaying: snapshot?.playing == true,
            mustRemainVisible: mustRemainVisible
        ))
    }

    /// `AXFullScreen` of the frontmost app's focused window; nil when Accessibility is not granted or the app
    /// does not answer within 0.25 s (a hung app must not stall the notch). Read at most once per inspection.
    private func frontmostAXFullScreen(pid: Int32) -> Bool? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, "AXFullScreen" as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func inspectFullscreenWindow(on displayID: UInt32, topInset: CGFloat, frontmostPID: Int32?) -> FullscreenInspection {
        guard let frontmostPID,
              let displayWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return FullscreenInspection(frontmostPID: frontmostPID, fullscreenOwnerPID: nil) }

        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            return FullscreenInspection(frontmostPID: frontmostPID, fullscreenOwnerPID: nil)
        }
        var axFullScreen: Bool??   // read lazily: only a below-housing candidate needs it
        for window in displayWindows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid == frontmostPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
            if NotchFullscreenRules.matchesDisplayFrame(frame, displayBounds) {
                return FullscreenInspection(frontmostPID: frontmostPID, fullscreenOwnerPID: pid)
            }
            guard NotchFullscreenRules.isFullscreenFrame(frame, display: displayBounds, topInset: topInset,
                                                         axFullScreen: true) else { continue }
            if axFullScreen == nil { axFullScreen = .some(frontmostAXFullScreen(pid: pid)) }
            if NotchFullscreenRules.isFullscreenFrame(frame, display: displayBounds, topInset: topInset,
                                                      axFullScreen: axFullScreen ?? nil) {
                return FullscreenInspection(frontmostPID: frontmostPID, fullscreenOwnerPID: pid)
            }
        }
        return FullscreenInspection(frontmostPID: frontmostPID, fullscreenOwnerPID: nil)
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
        let previousMessage = activityQueue.localMessageID
        let changed = activityQueue.push(item)
        if let previousMessage, activityQueue.localMessageID != previousMessage {
            NotchMessageModel.shared.notifyDismissed(id: previousMessage)
        }
        if changed { showCurrentActivity() }
    }

    private func showLocalMessage(_ payload: NotchMessageRules.NoticePayload) {
        guard canPresentActivities else {
            NotchMessageModel.shared.notifyDismissed(id: payload.id)
            return
        }
        present(LiveActivity.Item(
            kind: .localMessage,
            symbol: "bubble.left",
            titleKey: "Tin nhắn cục bộ",
            detail: payload.text,
            tint: .neutral,
            duration: payload.duration,
            localMessageID: payload.id
        ))
        // The notice waits behind the expanded editor until the Island is collapsed.
        dismiss()
    }

    private func dismissLocalMessage(id: UUID) {
        if activityQueue.current?.localMessageID == id {
            activityWork?.cancel()
            activityTimeUp()
        } else {
            activityQueue.removePendingLocalMessage(id: id)
        }
    }

    private func showCurrentActivity() {
        activityWork?.cancel(); activityWork = nil
        guard let item = activityQueue.current else { return }
        // A notice that cannot be drawn now (hub open, peek) waits in line instead of timing out unseen; `dispatch`
        // resumes it when the notch is idle again.
        guard machine.state.isIdle || item.kind.isKeyFeedback else {
            activityQueue.hold(); model.activity = nil
            return
        }
        model.activity = item
        if machine.state == .activity { render() }
        else if item.kind.isKeyFeedback { dispatch(.feedbackShown) }
        else { dispatch(.activityShown) }
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
        case .hydrateAck:
            acknowledgeHydration()
        case .hydrateSnooze(let minutes):
            snoozeHydration(minutes: minutes)
        }
    }

    private func activityTimeUp() {
        activityWork = nil
        if let id = activityQueue.current?.localMessageID {
            NotchMessageModel.shared.notifyDismissed(id: id)
        }
        if activityQueue.advance() != nil {
            showCurrentActivity()
        } else {
            model.activity = nil
            dispatch(.activityEnded)
            // The peek came back: the leave clock restarts now (a pointer that left during the level gets the full grace
            // from this moment), and one tick decides instead of waiting for the next mouse move.
            if machine.state == .peek {
                leftAt = nil; graceWork?.cancel(); graceWork = nil
                tick()
            }
        }
    }

    // MARK: - Countdown, Stopwatch, Pomodoro & Hydration (B4b + XF-ISLAND 1B)

    private var clockSuite = NotchClockSuite()
    private var countdownTicker: Timer?
    private var hydrationWork: DispatchWorkItem?
    private var terminateObserver: NSObjectProtocol?
    private var didRestoreClockState = false

    private var countdown: LiveActivity.Countdown? {
        get { clockSuite.countdown }
        set { clockSuite.countdown = newValue }
    }

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

    func selectClockMode(_ mode: NotchClockMode) {
        guard clockSuite.selectedMode != mode else { return }
        clockSuite.selectedMode = mode
        persistClockState()
        let hadBadge = model.timerText != nil
        syncClockModel(at: Date())
        if hadBadge != (model.timerText != nil) || model.timerText != nil { render() }
    }

    /// A 1 s ticker exists ONLY while a clock RUNS (countdown, stopwatch, or pomodoro); none while paused or idle.
    func startTimer(minutes: Int) {
        guard enabled, panel != nil else { return }
        let now = Date()
        clockSuite.selectedMode = .countdown
        clockSuite.countdown = LiveActivity.Countdown(minutes: minutes, now: now)
        commitClockChange(at: now, forceRender: true)
    }

    /// P2: freeze / restart the clock. A paused countdown keeps its wing (the time left, with a pause glyph) and no ticker.
    func pauseTimer() {
        guard let c = countdown, !c.isPaused else { return }
        let now = Date()
        clockSuite.countdown = c.paused(at: now)
        commitClockChange(at: now, forceRender: true)
    }

    func resumeTimer() {
        guard let c = countdown, c.isPaused else { return }
        let now = Date()
        clockSuite.countdown = c.resumed(at: now)
        commitClockChange(at: now, forceRender: true)
    }

    /// P2: "−5 / +5" on a running or paused countdown (what is left stays within 1 minute … the maximum).
    func extendTimer(byMinutes minutes: Int) {
        guard let c = countdown else { return }
        let now = Date()
        clockSuite.countdown = c.extended(byMinutes: minutes, now: now)
        commitClockChange(at: now, forceRender: false)
    }

    func cancelTimer() {
        let now = Date()
        clockSuite.countdown = nil
        commitClockChange(at: now, forceRender: true)
    }

    // MARK: - Stopwatch

    func startStopwatch() {
        guard enabled, panel != nil else { return }
        let now = Date()
        clockSuite.selectedMode = .stopwatch
        clockSuite.stopwatch = clockSuite.stopwatch.started(at: now)
        commitClockChange(at: now, forceRender: true)
    }

    func pauseStopwatch() {
        guard clockSuite.stopwatch.isRunning else { return }
        let now = Date()
        clockSuite.stopwatch = clockSuite.stopwatch.paused(at: now)
        commitClockChange(at: now, forceRender: true)
    }

    func resumeStopwatch() {
        guard enabled, panel != nil, clockSuite.stopwatch.isPaused else { return }
        let now = Date()
        clockSuite.stopwatch = clockSuite.stopwatch.resumed(at: now)
        commitClockChange(at: now, forceRender: true)
    }

    func lapStopwatch() {
        guard clockSuite.stopwatch.isActive else { return }
        let now = Date()
        clockSuite.stopwatch = clockSuite.stopwatch.recordedLap(at: now)
        commitClockChange(at: now, forceRender: false)
    }

    func resetStopwatch() {
        let now = Date()
        clockSuite.stopwatch = clockSuite.stopwatch.reset()
        commitClockChange(at: now, forceRender: true)
    }

    // MARK: - Pomodoro

    func startPomodoro() {
        guard enabled, panel != nil else { return }
        let now = Date()
        clockSuite.selectedMode = .pomodoro
        clockSuite.pomodoro = clockSuite.pomodoro.started(at: now)
        commitClockChange(at: now, forceRender: true)
    }

    func pausePomodoro() {
        guard clockSuite.pomodoro.isRunning else { return }
        let now = Date()
        clockSuite.pomodoro = clockSuite.pomodoro.paused(at: now)
        commitClockChange(at: now, forceRender: true)
    }

    func resumePomodoro() {
        guard enabled, panel != nil, clockSuite.pomodoro.isPaused else { return }
        let now = Date()
        clockSuite.pomodoro = clockSuite.pomodoro.resumed(at: now)
        commitClockChange(at: now, forceRender: true)
    }

    func skipPomodoroPhase() {
        let now = Date()
        clockSuite.pomodoro = clockSuite.pomodoro.skipped()
        commitClockChange(at: now, forceRender: true)
    }

    func resetPomodoro() {
        let now = Date()
        clockSuite.pomodoro = clockSuite.pomodoro.reset()
        commitClockChange(at: now, forceRender: true)
    }

    // MARK: - Hydration reminder (optional, independent switch)

    func setHydrationEnabled(_ isOn: Bool) {
        let now = Date()
        clockSuite.hydration.setEnabled(isOn, now: now)
        commitClockChange(at: now, forceRender: false)
    }

    func setHydrationInterval(minutes: Int) {
        let now = Date()
        clockSuite.hydration.setInterval(minutes: minutes, now: now)
        commitClockChange(at: now, forceRender: false)
    }

    func setHydrationDailyLimit(_ limit: Int) {
        let now = Date()
        clockSuite.hydration.setDailyLimit(limit, now: now)
        commitClockChange(at: now, forceRender: false)
    }

    func acknowledgeHydration() {
        let now = Date()
        clockSuite.hydration.acknowledge(now: now)
        commitClockChange(at: now, forceRender: false)
    }

    func snoozeHydration(minutes: Int = NotchHydrationReminder.snoozeMinutes) {
        let now = Date()
        clockSuite.hydration.snooze(minutes: minutes, now: now)
        commitClockChange(at: now, forceRender: false)
    }

    // MARK: - Clock persistence, sleep/wake & single ticker

    private func persistClockState() {
        let defaults = UserDefaults.standard
        if let data = clockSuite.encoded() {
            defaults.set(data, forKey: NotchClockSuite.stateStorageKey)
        }
        defaults.set(clockSuite.hydration.enabled, forKey: NotchHydrationReminder.enabledKey)
        defaults.set(clockSuite.hydration.intervalMinutes, forKey: NotchHydrationReminder.intervalKey)
    }

    private func restoreClockStateIfNeeded() {
        guard !didRestoreClockState else { return }
        didRestoreClockState = true
        let defaults = UserDefaults.standard
        let now = Date()
        let savedData = defaults.data(forKey: NotchClockSuite.stateStorageKey)
        let hydrationEnabled = defaults.object(forKey: NotchHydrationReminder.enabledKey) as? Bool
        let hydrationInterval = defaults.object(forKey: NotchHydrationReminder.intervalKey) as? Int
        clockSuite = NotchClockSuite.decoded(
            from: savedData,
            hydrationEnabledOverride: hydrationEnabled,
            hydrationIntervalOverride: hydrationInterval,
            now: now
        )
        reconcileClockSuite(at: now, forceRender: true)
    }

    private func handleSystemWake() {
        guard enabled else { return }
        reconcileClockSuite(at: Date(), forceRender: true)
    }

    private func commitClockChange(at now: Date, forceRender: Bool) {
        persistClockState()
        updateClockSchedulers(at: now)
        let hadBadge = model.timerText != nil
        let hadPaused = model.timerBadgePaused
        syncClockModel(at: now)
        if forceRender || hadBadge != (model.timerText != nil) || hadPaused != model.timerBadgePaused {
            render()
        }
    }

    private func updateClockSchedulers(at now: Date) {
        if clockSuite.needsSecondTicker {
            if countdownTicker == nil {
                let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tickCountdown() }
                }
                RunLoop.main.add(t, forMode: .common)
                countdownTicker = t
            }
        } else {
            countdownTicker?.invalidate()
            countdownTicker = nil
        }

        hydrationWork?.cancel()
        hydrationWork = nil
        if enabled, let seconds = clockSuite.hydration.secondsUntilDue(at: now) {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.reconcileClockSuite(at: Date(), forceRender: false) }
            }
            hydrationWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, seconds), execute: work)
        }
    }

    private func syncClockModel(at now: Date) {
        model.clockMode = clockSuite.selectedMode
        model.timer = clockSuite.countdown
        model.stopwatch = clockSuite.stopwatch
        model.pomodoro = clockSuite.pomodoro
        model.hydration = clockSuite.hydration
        model.timerNow = now
        if let badge = clockSuite.collapsedBadge(at: now) {
            model.timerText = badge.text
            model.timerBadgeMode = badge.mode
            model.timerBadgeSymbol = badge.symbol
            model.timerBadgePaused = badge.isPaused
        } else {
            model.timerText = nil
            model.timerBadgeMode = .countdown
            model.timerBadgeSymbol = "timer"
            model.timerBadgePaused = false
        }
    }

    private func reconcileClockSuite(at now: Date, forceRender: Bool) {
        let events = clockSuite.reconcile(at: now)
        if !events.isEmpty {
            persistClockState()
        }
        updateClockSchedulers(at: now)
        let hadBadge = model.timerText != nil
        let hadPaused = model.timerBadgePaused
        syncClockModel(at: now)
        if forceRender || !events.isEmpty || hadBadge != (model.timerText != nil) || hadPaused != model.timerBadgePaused {
            render()
        }
        for event in events {
            switch event {
            case .countdownFinished(let c):
                NSSound(named: "Glass")?.play()
                present(LiveActivity.timerFinishedItem(c))
            case .pomodoroPhaseFinished(let completed, let next, _):
                NSSound(named: "Glass")?.play()
                present(NotchClockSuite.pomodoroFinishedItem(completed: completed, next: next))
            case .hydrationDue(let intervalMinutes):
                NSSound(named: "Pop")?.play()
                present(NotchClockSuite.hydrationDueItem(intervalMinutes: intervalMinutes))
            }
        }
    }

    private func tickCountdown() {
        reconcileClockSuite(at: Date(), forceRender: false)
    }

    // MARK: - Hub actions (B2d)

    private var job: Task<Void, Never>?

    /// Runs one action on the held (or selected) files. One job at a time; progress is counted in files done.
    func run(_ action: NotchActions.Action) {
        guard model.task?.isRunning != true, model.task?.isAwaitingReview != true else { return }
        DropTrayStore.shared.refreshStatuses()
        let resolved = DropTrayActionResolution.resolve(
            items: DropTrayStore.shared.items,
            selection: model.traySelection,
            id: \.id,
            isActionable: \.status.isActionable
        )
        let items = resolved.targets.map { URL(fileURLWithPath: $0.path) }
        guard !items.isEmpty else {
            model.notice = "Không có tệp hợp lệ để thao tác."
            return
        }
        model.notice = nil
        if action == .airDrop { airDropFileURLs(items); return }
        let inputs = NotchActions.inputs(for: action, from: items)
        guard !inputs.isEmpty else { return }
        if case .convert = action { prepareImageReview(action, inputs: inputs); return }
        if case .resize = action { prepareImageReview(action, inputs: inputs); return }
        model.task = NotchTask(action: action, total: NotchActions.stepCount(for: action, inputs: inputs.count))
        model.ocrSummary = nil
        dispatch(.taskStarted)
        job = Task { [weak self] in
            await self?.execute(action, inputs: inputs)
            self?.finishJob()
        }
    }

    private func prepareImageReview(_ action: NotchActions.Action, inputs: [URL]) {
        model.task = NotchTask(action: action, total: inputs.count, awaitingImageReview: true)
        model.ocrSummary = nil
        dispatch(.taskStarted)
        job = Task { [weak self] in
            let rows = await Task.detached(priority: .utility) { () -> [NotchTask.ImageReviewRow] in
                inputs.map { url in
                    let options: ImageRunner.TransformOptions
                    switch action {
                    case .convert(let target): options = .init(format: target, outputOperation: .convert(target))
                    case .resize(let pixels):
                        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let uti = CGImageSourceGetType(source) as String?,
                              let format = ImageEngine.Target.allCases.first(where: { $0.uti == uti }) else {
                            return .init(url: url, preview: nil, options: nil, failure: .noEncoder(url.pathExtension.uppercased()))
                        }
                        options = .init(target: .longestEdge(pixels), format: format, outputOperation: .resize(maxPixels: pixels))
                    default:
                        return .init(url: url, preview: nil, options: nil, failure: .invalidTransform(url.lastPathComponent))
                    }
                    switch ImageRunner.preview(url, options: options) {
                    case .success(let preview): return .init(url: url, preview: preview, options: options, failure: nil)
                    case .failure(let failure): return .init(url: url, preview: nil, options: options, failure: failure)
                    }
                }
            }.value
            guard let self, !Task.isCancelled, self.model.task?.isAwaitingReview == true else { return }
            self.model.task?.setReviewRows(rows)
            self.job = nil
        }
    }

    func confirmImageReview() {
        guard let rows = model.task?.imageReviewRows, model.task?.isAwaitingReview == true else { return }
        model.task?.beginReviewedWork()
        job = Task { [weak self] in
            guard let self else { return }
            for row in rows {
                if Task.isCancelled || self.model.task?.isRunning != true { break }
                guard let preview = row.preview, let options = row.options, !preview.willSkip else {
                    let failure = row.failure ?? .invalidTransform("Ảnh nhỏ hơn kích thước đích; sẽ bỏ qua nếu không bật phóng lớn.")
                    self.model.task?.stepFailed(key: failure.messageKey, detail: failure.detail)
                    continue
                }
                let result = await Task.detached(priority: .userInitiated) {
                    ImageRunner.transform(row.url, options: options, expectedIdentity: preview.identity)
                }.value
                switch result {
                case .success(let output): self.model.task?.stepSucceeded(output: output)
                case .failure(let failure): self.model.task?.stepFailed(key: failure.messageKey, detail: failure.detail)
                }
            }
            self.finishJob()
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
