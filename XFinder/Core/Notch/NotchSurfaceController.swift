import AppKit
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
    private var shrinkWork: DispatchWorkItem?

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
    private var clipboardOnHover: Bool {
        UserDefaults.standard.object(forKey: "notch.clipboardOnHover") as? Bool ?? false
    }
    /// B7: keep the surface out of screenshots, recordings and screen sharing (`NSWindow.sharingType = .none`;
    /// measured as `kCGWindowSharingState = 0`). On by default — an overlay in a recording is noise.
    private var hideFromCapture: Bool {
        UserDefaults.standard.object(forKey: "notch.hideFromCapture") as? Bool ?? true
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
        NotchSurfaceMachine.Settings(enabled: enabled, hoverToPeek: hoverEnabled, hoverOpensClipboard: clipboardOnHover,
                                     nowPlayingActive: NowPlayingMonitor.shared.hasTrack,
                                     dragIntoNotchOpens: notchDropEnabled, shakeOpens: shakeEnabled,
                                     hoverDwell: NotchSurfaceMachine.Settings.hoverDwell(forSpeed: hoverSpeed))
    }

    /// Something is on the collapsed surface (badge or pill): files, a countdown, a track.
    private var badgeShown: Bool { machine.itemCount > 0 || countdown != nil || NowPlayingMonitor.shared.hasTrack }

    func applySettings() {
        if enabled {
            start()
            panel?.sharingType = hideFromCapture ? .none : .readOnly   // B7, live
            model.pillOnPlainScreens = pillOnPlainScreens
            render()
            NowPlayingMonitor.shared.applySettings()      // B6: its own switch, under the master
        } else {
            stop()
        }
    }

    private func start() {
        if panel == nil { prepare() }
        NowPlayingMonitor.shared.onChange = { [weak self] in self?.nowPlayingChanged() }
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
        activityWork?.cancel(); activityWork = nil
        activityQueue.clear()
        countdownTicker?.invalidate(); countdownTicker = nil; countdown = nil; model.timerText = nil
        NowPlayingMonitor.shared.stop()
        nowPlayingTicker?.invalidate(); nowPlayingTicker = nil
        model.nowPlaying = nil; model.nowPlayingArtwork = nil; model.nowPlayingPosition = nil
        model.nowPlayingAvailability = .off
        samples.removeAll()
        machine.handle(.disabled, settings: settings, now: Date())
        state = machine.state
        panel?.hide()
        panel = nil
        detailPanel?.orderOut(nil)
    }

    // MARK: Public intents

    /// Deliberate open: badge / peek click, or the Finder-extension URL. `page` lands on that page.
    func reveal(page: NotchSurfaceMachine.Page = .files) {
        if !state.isOpen { surfaceScreen = WindowManager.screenUnderPointer() }
        dispatch(.activate)
        if page != .files { dispatch(.switchPage(page)) }
    }

    /// A tab in the open hub (B5).
    func switchPage(_ page: NotchSurfaceMachine.Page) { dispatch(.switchPage(page)) }

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
            && (panel?.frame.insetBy(dx: -12, dy: -12).contains(point) ?? false)

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
                                                visible: screen.visibleFrame,
                                                pillShown: pillOnPlainScreens && badgeShown && machine.state == .collapsed)
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
        for w in [dwellWork, graceWork, shrinkWork] { w?.cancel() }
        dwellWork = nil; graceWork = nil; shrinkWork = nil
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
        render()
        syncClipboardKeyboard()
        syncNowPlayingTicker()
    }

    // MARK: - Now Playing (B6)

    private var nowPlayingTicker: Timer?

    /// The helper reported something (or went away): mirror it into the model, let the machine
    /// re-decide (a peek that showed only the track collapses when it ends), and redraw — the
    /// collapsed badge appears or disappears with the track.
    private func nowPlayingChanged() {
        let m = NowPlayingMonitor.shared
        model.nowPlaying = m.snapshot
        model.nowPlayingArtwork = m.artwork
        model.nowPlayingAvailability = m.availability
        let app = m.playerApp
        model.nowPlayingAppName = app?.localizedName
        model.nowPlayingAppIcon = app?.icon
        model.nowPlayingPosition = m.snapshot.flatMap { NowPlaying.position(of: $0, at: Date()) }
        dispatch(.itemsChanged(count: machine.itemCount))
        render()
        syncNowPlayingTicker()
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

    func openPlayer() { NowPlayingMonitor.shared.openPlayer() }

    // MARK: - Clipboard page (B5)

    private var clipboardKeyMonitor: Any?

    /// The clipboard page needs typing (its search field) and arrow keys. The panel becomes key
    /// WITHOUT `NSApp.activate` (which would raise every XFinder window); `orderOut` on collapse
    /// gives the keyboard back. A LOCAL monitor is enough: the keys matter only while our panel is key.
    private func syncClipboardKeyboard() {
        if case .expanded(.clipboard) = machine.state {
            guard clipboardKeyMonitor == nil else { return }
            panel?.makeKeyAndOrderFront(nil)
            clipboardKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.panel?.isKeyWindow == true else { return e }
                let items = self.model.clipboard.items(from: ClipboardManager.shared)
                switch e.keyCode {
                case 53: self.dismiss(); return nil                                   // Esc
                case 123: self.model.clipboard.moveSelection(-1, in: items); return nil
                case 124: self.model.clipboard.moveSelection(1, in: items); return nil
                case 36:                                                              // Return
                    if let id = self.model.clipboard.selectedID, let r = items.first(where: { $0.id == id }) {
                        self.pasteFromClipboardPage(r); return nil
                    }
                    return e
                default: return e
                }
            }
        } else if let m = clipboardKeyMonitor {
            NSEvent.removeMonitor(m)
            clipboardKeyMonitor = nil
        }
    }

    /// Whether the shelf's event tap is alive — the Paste Stack can then intercept ⌘V system-wide.
    var pasteStackInterceptsCommandV: Bool { ClipboardShelfController.shared.tapIsLive }

    /// Paste into the app the user came from and get out of the way. Without Accessibility (or
    /// with auto-paste off) the item is copied and the page says to press ⌘V — never a silent nothing.
    func pasteFromClipboardPage(_ record: ClipboardRecord) {
        let pid = ClipboardManager.shared.lastExternalPID
        ClipboardManager.shared.incrementUsage(record.id)
        if ClipboardShelfController.shared.autoPasteAfterSelection, WindowManager.isTrusted {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ClipboardPasteEngine.paste(record: record, to: pid) }
        } else {
            ClipboardPasteEngine.writeToPasteboard(record: record)
            ClipboardSounds.playCopy()
            model.clipboard.notice = "Đã sao chép — dán bằng ⌘V."
        }
    }

    func pasteNextFromStack() { ClipboardManager.shared.pasteNextManually() }

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
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Build the panel ONCE — a hosting controller created on the way to the screen cost 0.15–0.65 s
    /// in QuitProtection. `sizingOptions = []` so SwiftUI never resizes the window to its content:
    /// the frame is owned by `NotchSurfaceLayout`, and the drawn shape animates inside it.
    private func prepare() {
        let p = SurfacePanel(kind: .notch, size: CGSize(width: 440, height: 222))
        p.sharingType = hideFromCapture ? .none : .readOnly          // B7: invisible to capture by default
        // A hosting VIEW subclass, not a controller: it must answer acceptsFirstMouse = true or every
        // control needs two clicks while another app is frontmost (the panel is never made key).
        let host = FirstMouseHostingView(rootView: NotchSurfaceView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: p.frame.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        panel = p
    }

    /// Grow: set the window frame first, then let the shape animate up into it. Shrink: animate the
    /// shape first, set the smaller frame once the spring has settled, or the content clips
    /// mid-animation. An anchor change (pointer ⇄ notch) jumps with no animation.
    private func render() {
        guard let panel else { return }
        guard enabled else { panel.hide(); return }
        var screen = surfaceScreen ?? WindowManager.screenUnderPointer()
        if machine.state == .collapsed, let notched = Self.notchedScreen { screen = notched }
        let notch = Self.notch(on: screen)
        shrinkWork?.cancel(); shrinkWork = nil

        guard let target = NotchSurfaceLayout.frame(for: machine.state, anchor: machine.anchor,
                                                    itemCount: machine.itemCount, notch: notch,
                                                    screen: screen.frame, visible: screen.visibleFrame,
                                                    pointer: shakePoint, timerActive: countdown != nil,
                                                    nowPlayingActive: NowPlayingMonitor.shared.hasTrack,
                                                    pillOnPlainScreens: pillOnPlainScreens) else {
            model.state = .collapsed
            model.itemCount = machine.itemCount
            panel.hide()
            renderedAnchor = .notch
            return
        }
        let wasVisible = panel.isVisible
        let anchorChanged = machine.anchor != renderedAnchor
        renderedAnchor = machine.anchor
        panel.hasShadow = machine.anchor == .pointer      // at the notch a shadow would reveal the rect

        if !wasVisible || anchorChanged {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { applyModel(notch: notch) }
            panel.setFrame(target, display: true)
            if !wasVisible { panel.orderFrontRegardless() }   // never key: the user's app keeps focus
            return
        }
        // A tray at the pointer may have been dragged aside by its title strip; it has one fixed size,
        // so an update (a file added, a count change) keeps it where the user put it.
        if machine.anchor == .pointer, panel.frame.size == target.size {
            applyModel(notch: notch)
            return
        }
        if target.width >= panel.frame.width && target.height >= panel.frame.height {
            panel.setFrame(target, display: true)
            applyModel(notch: notch)
        } else {
            applyModel(notch: notch)
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.panel?.setFrame(target, display: true) }
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
        }
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

    func present(_ item: LiveActivity.Item) {
        guard canPresentActivities else { return }
        if activityQueue.push(item) { showCurrentActivity() }
    }

    private func showCurrentActivity() {
        activityWork?.cancel(); activityWork = nil
        guard let item = activityQueue.current else { return }
        model.activity = item
        if machine.state.isIdle {
            if machine.state == .activity { render() } else { dispatch(.activityShown) }
        }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.activityTimeUp() } }
        activityWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + item.duration, execute: work)
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

    private var countdown: LiveActivity.Countdown?
    private var countdownTicker: Timer?

    var timerRunning: Bool { countdown != nil }

    /// A 1 s ticker exists ONLY while a countdown runs (it drives the badge's seconds); none otherwise.
    func startTimer(minutes: Int) {
        guard enabled, panel != nil else { return }
        countdown = LiveActivity.Countdown(minutes: minutes, now: Date())
        countdownTicker?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tickCountdown() } }
        RunLoop.main.add(t, forMode: .common)
        countdownTicker = t
        tickCountdown()
    }

    func cancelTimer() {
        countdownTicker?.invalidate(); countdownTicker = nil
        countdown = nil
        model.timerText = nil
        render()
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
            case .failure(let f): model.task?.stepFailed(key: f.messageKey, detail: f.detail ?? "")
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
        case .convert, .removeBackground: return "image"
        case .airDrop: return "other"
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
