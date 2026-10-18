import AppKit
import ApplicationServices
import os

/// SNAPMEM — "I arranged Chrome once on this set of displays; it goes back there." The ONE reader of
/// `snapzones.remember` / `snapzones.rememberFrames`. Drives the pure `SnapMemory` rules (do not duplicate
/// its logic here — this file only supplies displays, AX events, the clock, and performs the AX writes).
///
/// Pattern copied from `QuitOnCloseController` (AXObserver-per-app, workspace launch/terminate, run-loop
/// source on main) and `SelectionWatcher` (the -25204 registration retry at 0.5/1.5/3 s). Zero cost at rest:
/// no rule anywhere ⇒ no observer, no workspace tokens, no timers.
@MainActor @Observable
final class SnapMemoryController {
    static let shared = SnapMemoryController()
    private init() {
        store = SnapMemory.Store.decode(UserDefaults.standard.data(forKey: SnapMemory.Key.store))
    }

    // MARK: Settings (one reader each — spec §3)

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "snapzones.remember") as? Bool ?? false }
    var framesEnabled: Bool { UserDefaults.standard.object(forKey: "snapzones.rememberFrames") as? Bool ?? false }

    // MARK: State

    /// Observed by the settings page (`store.rules`); every mutation goes through `persist()`.
    private(set) var store: SnapMemory.Store
    private(set) var isRunning = false

    private struct Watch {
        let observer: AXObserver
        let app: AXUIElement
        /// True once this launch has had its replay — or from the start for an app that was ALREADY running when we
        /// attached: a new window of a running app (a Save sheet, ⌘N) must never yank the main window back (spec: no
        /// fighting the user). Only a fresh launch replays on its first window.
        var appliedThisLaunch = false
        var pendingSettle: [DispatchWorkItem] = []
        var recordDebounce: DispatchWorkItem?
    }

    @ObservationIgnored private var watches: [pid_t: Watch] = [:]
    @ObservationIgnored private var attachRetries: [pid_t: DispatchWorkItem] = [:]
    /// pids whose `didLaunchApplication` we saw and whose first window is still owed a replay.
    @ObservationIgnored private var launching: Set<pid_t> = []
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var screenParamsToken: NSObjectProtocol?
    @ObservationIgnored private var displayChangeWork: DispatchWorkItem?
    /// Uptime of the last AX write WE made, per pid — used to ignore the echo (spec rule 6 / `ownWriteGrace`).
    @ObservationIgnored private var lastOwnWriteAt: [pid_t: TimeInterval] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.xfinder.app", category: "SnapMemory")
    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? "com.xfinder.app" }

    // MARK: Lifecycle

    /// Called at launch, on `didBecomeActive` (Accessibility granted later), from the page's `.onChange`,
    /// and from FeatureHub.
    func applySettings() {
        guard isEnabled, WindowManager.isTrusted else { stop(); return }
        guard !isRunning else { attachAllRemembered(); return }
        isRunning = true
        let nc = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app { SnapMemoryController.shared.appLaunched(app) } }
        })
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { SnapMemoryController.shared.detach(pid) } }
        })
        screenParamsToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SnapMemoryController.shared.scheduleDisplayChange() }
        }
        attachAllRemembered()
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        for pid in Array(watches.keys) { detach(pid) }
        for (_, work) in attachRetries { work.cancel() }
        attachRetries.removeAll()
        displayChangeWork?.cancel(); displayChangeWork = nil
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        if let t = screenParamsToken { NotificationCenter.default.removeObserver(t) }
        screenParamsToken = nil
        lastOwnWriteAt.removeAll()
    }

    // MARK: Displays

    /// Every attached screen, identified the way it survives a reconnect.
    private func currentArrangementAndKeys() -> (SnapMemory.Arrangement, [NSScreen: SnapMemory.DisplayKey]) {
        var map: [NSScreen: SnapMemory.DisplayKey] = [:]
        for screen in NSScreen.screens {
            guard let key = displayKey(for: screen) else { continue }
            map[screen] = key
        }
        return (SnapMemory.Arrangement(displays: Array(map.values)), map)
    }

    var currentArrangement: SnapMemory.Arrangement { currentArrangementAndKeys().0 }

    /// nil only when the screen carries no `NSScreenNumber` (never observed in practice).
    private func displayKey(for screen: NSScreen) -> SnapMemory.DisplayKey? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = CGDirectDisplayID(number.uint32Value)
        var uuid = "unknown-\(id)"
        if let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let str = CFUUIDCreateString(nil, ref) {
            uuid = str as String
        }
        var pw = Int(screen.frame.width), ph = Int(screen.frame.height)
        if let mode = CGDisplayCopyDisplayMode(id) {
            pw = mode.pixelWidth
            ph = mode.pixelHeight
        }
        return SnapMemory.DisplayKey(uuid: uuid, name: screen.localizedName, pixelWidth: pw, pixelHeight: ph,
                                      isBuiltin: CGDisplayIsBuiltin(id) != 0)
    }

    private func screen(for key: SnapMemory.DisplayKey, in map: [NSScreen: SnapMemory.DisplayKey]) -> NSScreen? {
        map.first { $0.value.uuid == key.uuid }?.key
    }

    /// For the page's rows: the display's own name, or a note when two displays share a UUID (spec case table).
    func displayName(for key: SnapMemory.DisplayKey) -> String {
        key.name
    }

    // MARK: Recording — rule 1: an app enters memory only when XFinder itself snaps it

    /// Called by `WindowManager.snapFrontmost` on success.
    func didSnap(app: NSRunningApplication, target: SnapLayout.Target, screen: NSScreen) {
        guard isEnabled, let bundleID = app.bundleIdentifier, let display = displayKey(for: screen) else { return }
        let (arrangement, _) = currentArrangementAndKeys()
        guard arrangement.contains(display) else { return }
        let rule = SnapMemory.Rule(bundleID: bundleID, appName: app.localizedName ?? bundleID, arrangement: arrangement,
                                    display: display, layout: .snap(target), updatedAt: Date(), lastOutcome: nil, lastAppliedAt: nil)
        store.remember(rule)
        persist()
        lastOwnWriteAt[app.processIdentifier] = ProcessInfo.processInfo.systemUptime
        attachIfNeeded(app)
    }

    func forget(id: String) {
        store.forget(id: id)
        persist()
        pruneWatchesWithoutRules()
    }

    func forgetAll() {
        store.forgetAll()
        persist()
        pruneWatchesWithoutRules()
    }

    /// The page's button: replay every rule of the arrangement attached right now.
    func reapplyNow() {
        guard isEnabled, WindowManager.isTrusted else { return }
        let arrangement = currentArrangement
        for rule in store.rules(for: arrangement) {
            guard let app = runningApp(bundleID: rule.bundleID) else { continue }
            attachIfNeeded(app)
            schedule(rule: rule, trigger: .switchedOn)
        }
    }

    private func persist() {
        UserDefaults.standard.set(store.encode(), forKey: SnapMemory.Key.store)
    }

    private func pruneWatchesWithoutRules() {
        for pid in Array(watches.keys) {
            guard let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier,
                  !store.rules.contains(where: { $0.bundleID == bundleID }) else { continue }
            detach(pid)
        }
    }

    // MARK: Attaching observers (rule 2)

    private func attachAllRemembered() {
        let remembered = Set(store.rules.map(\.bundleID))
        guard !remembered.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, remembered.contains(bundleID),
                  bundleID != ownBundleID, watches[app.processIdentifier] == nil else { continue }
            attachIfNeeded(app)
        }
    }

    private func appLaunched(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != ownBundleID,
              store.rules.contains(where: { $0.bundleID == bundleID }) else { return }
        launching.insert(app.processIdentifier)
        attachIfNeeded(app)
    }

    private func attachIfNeeded(_ app: NSRunningApplication) {
        guard watches[app.processIdentifier] == nil, attachRetries[app.processIdentifier] == nil,
              let bundleID = app.bundleIdentifier, bundleID != ownBundleID else { return }
        attach(app, attempt: 0)
    }

    private func attach(_ app: NSRunningApplication, attempt: Int) {
        let pid = app.processIdentifier
        var obs: AXObserver?
        // Only Sendable values (pid, notification name) cross from the callback — an AXUIElement is not Sendable
        // (the Bluetooth-callback lesson). The source lives on the main run loop, so `runOnMainActor` resolves
        // synchronously here in practice; it still hops safely if that is ever wrong.
        let callback: AXObserverCallback = { _, element, notification, _ in
            let name = notification as String
            var p: pid_t = 0
            AXUIElementGetPid(element, &p)
            let pid = p
            runOnMainActor { SnapMemoryController.shared.handle(name, pid: pid) }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let o = obs else { return }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.5)
        let created = AXObserverAddNotification(o, appEl, kAXWindowCreatedNotification as CFString, nil)
        guard created == .success else {
            if let delay = SmartSelectionRules.registrationRetryDelay(attempt: attempt, error: created.rawValue) {
                let work = DispatchWorkItem { MainActor.assumeIsolated {
                    guard SnapMemoryController.shared.isRunning,
                          NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier == pid }) else { return }
                    SnapMemoryController.shared.attachRetries[pid] = nil
                    SnapMemoryController.shared.attach(app, attempt: attempt + 1)
                } }
                attachRetries[pid] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
            return
        }
        for w in windows(of: appEl) {
            AXObserverAddNotification(o, w, kAXWindowMovedNotification as CFString, nil)
            AXObserverAddNotification(o, w, kAXWindowResizedNotification as CFString, nil)
            AXObserverAddNotification(o, w, kAXUIElementDestroyedNotification as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        let isLaunch = launching.remove(pid) != nil
        // An app that was already running when we attached has had its "launch": nothing replays until it relaunches
        // (or the displays change / the page's button). A launching app owes its first window a replay — and a fast
        // app may have opened it before our observer existed, so treat an existing window as that first window.
        watches[pid] = Watch(observer: o, app: appEl, appliedThisLaunch: !isLaunch)
        attachRetries[pid] = nil
        log.notice("watching pid=\(pid) app=\(app.bundleIdentifier ?? "?", privacy: .public) attempt=\(attempt) launch=\(isLaunch)")
        if isLaunch, !windows(of: appEl).isEmpty {
            scheduleForAllRules(bundleID: app.bundleIdentifier, pid: pid, trigger: .windowAppeared)
        }
    }

    private func detach(_ pid: pid_t) {
        attachRetries[pid]?.cancel(); attachRetries[pid] = nil
        launching.remove(pid)
        guard let w = watches.removeValue(forKey: pid) else { return }
        w.pendingSettle.forEach { $0.cancel() }
        w.recordDebounce?.cancel()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(w.observer), .defaultMode)
        lastOwnWriteAt[pid] = nil
    }

    private func windows(of app: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
              let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    private func mainWindow(of app: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &v) == .success, let w = v {
            return (w as! AXUIElement)
        }
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &v) == .success, let w = v {
            return (w as! AXUIElement)
        }
        return windows(of: app).first
    }

    // MARK: AX callback

    private func handle(_ notification: String, pid: pid_t) {
        guard isEnabled, var w = watches[pid] else { return }
        switch notification {
        case kAXWindowCreatedNotification as String:
            for win in windows(of: w.app) {
                AXObserverAddNotification(w.observer, win, kAXWindowMovedNotification as CFString, nil)
                AXObserverAddNotification(w.observer, win, kAXWindowResizedNotification as CFString, nil)
                AXObserverAddNotification(w.observer, win, kAXUIElementDestroyedNotification as CFString, nil)
            }
            watches[pid] = w
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            scheduleForAllRules(bundleID: app.bundleIdentifier, pid: pid, trigger: .windowAppeared)

        case kAXUIElementDestroyedNotification as String:
            // A window of this app closed. Re-count on the next run loop turn is not needed here (that is F3's
            // job for the app's own lifecycle, not ours) — nothing to do beyond letting app-terminate detach us.
            break

        case kAXWindowMovedNotification as String, kAXWindowResizedNotification as String:
            recordDebounced(pid: pid)

        default:
            break
        }
    }

    // MARK: Replay (rules 4, 5, 8)

    /// Schedule every rule of `bundleID` that matches the display it names, for the arrangement attached now.
    private func scheduleForAllRules(bundleID: String?, pid: pid_t, trigger: SnapMemory.Trigger) {
        guard let bundleID else { return }
        let (arrangement, _) = currentArrangementAndKeys()
        for rule in store.rules.filter({ $0.bundleID == bundleID && $0.arrangement == arrangement }) {
            scheduleReplay(rule: rule, trigger: trigger, pid: pid)
        }
    }

    private func schedule(rule: SnapMemory.Rule, trigger: SnapMemory.Trigger) {
        guard let app = runningApp(bundleID: rule.bundleID) else { return }
        scheduleReplay(rule: rule, trigger: trigger, pid: app.processIdentifier)
    }

    private func scheduleReplay(rule: SnapMemory.Rule, trigger: SnapMemory.Trigger, pid: pid_t) {
        let (arrangement, _) = currentArrangementAndKeys()
        let alreadyApplied = watches[pid]?.appliedThisLaunch ?? false
        guard let plan = SnapMemory.replay(rule: rule, trigger: trigger, arrangementNow: arrangement,
                                           appRunning: true, alreadyAppliedThisLaunch: alreadyApplied) else { return }
        // Cancel any plan already in flight for this rule (a new trigger supersedes an older one).
        watches[pid]?.pendingSettle.forEach { $0.cancel() }
        watches[pid]?.pendingSettle = []
        var items: [DispatchWorkItem] = []
        for (i, delay) in plan.delays.enumerated() {
            let isLast = i == plan.delays.count - 1
            let item = DispatchWorkItem { MainActor.assumeIsolated {
                SnapMemoryController.shared.attempt(rule: plan.rule, pid: pid, isRecheck: isLast)
            } }
            items.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
        if var w = watches[pid] {
            w.pendingSettle = items
            if trigger == .windowAppeared { w.appliedThisLaunch = true }
            watches[pid] = w
        }
    }

    private func scheduleDisplayChange() {
        displayChangeWork?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { SnapMemoryController.shared.applyDisplayChange() } }
        displayChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func applyDisplayChange() {
        guard isEnabled, WindowManager.isTrusted else { return }
        let arrangement = currentArrangement
        for rule in store.rules(for: arrangement) {
            guard let app = runningApp(bundleID: rule.bundleID) else { continue }
            attachIfNeeded(app)
            scheduleReplay(rule: rule, trigger: .displayChanged, pid: app.processIdentifier)
        }
    }

    /// One attempt of a replay plan. `isRecheck` is the plan's last delay: only re-set when the window drifted.
    private func attempt(rule: SnapMemory.Rule, pid: pid_t, isRecheck: Bool) {
        // The switch may have been turned off (or the rule deleted) while this attempt was pending: nothing to apply.
        guard isEnabled, store.rules.contains(where: { $0.id == rule.id }) else { return }
        guard kill(pid, 0) == 0 else {
            store.noteOutcome(.appNotRunning, ruleID: rule.id, at: Date()); persist(); return
        }
        guard WindowManager.isTrusted else {
            store.noteOutcome(.notTrusted, ruleID: rule.id, at: Date()); persist(); return
        }
        if NSEvent.pressedMouseButtons != 0 {
            // User is dragging something — postpone this one attempt by 1 s, do not drop it (spec case table).
            let retry = DispatchWorkItem { MainActor.assumeIsolated {
                SnapMemoryController.shared.attempt(rule: rule, pid: pid, isRecheck: isRecheck)
            } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: retry)
            return
        }
        guard let w = watches[pid], let win = mainWindow(of: w.app) else {
            store.noteOutcome(.noWindow, ruleID: rule.id, at: Date()); persist(); return
        }
        let (_, map) = currentArrangementAndKeys()
        guard let screen = screen(for: rule.display, in: map) else {
            store.noteOutcome(.noWindow, ruleID: rule.id, at: Date()); persist(); return
        }
        let visible = WindowManager.axVisibleFrame(for: screen)

        if case .fullscreen = rule.layout {
            applyFullscreen(rule: rule, win: win, visible: visible, pid: pid)
            return
        }

        guard let target = SnapMemory.rect(for: rule.layout, visible: visible) else {
            store.noteOutcome(.failed, ruleID: rule.id, at: Date()); persist(); return
        }
        if isRecheck {
            guard let current = currentFrame(of: win) else {
                store.noteOutcome(.noWindow, ruleID: rule.id, at: Date()); persist(); return
            }
            guard SnapMemory.needsReapply(current: current, target: target) else {
                store.noteOutcome(.applied, ruleID: rule.id, at: Date()); persist(); return
            }
        }
        let ok = WindowManager.setWindow(win, rect: target)
        lastOwnWriteAt[pid] = ProcessInfo.processInfo.systemUptime
        store.noteOutcome(ok ? .applied : .failed, ruleID: rule.id, at: Date())
        persist()
    }

    /// Full screen (rule 8): move onto the recorded display first, then set `AXFullScreen`. Not settable ⇒
    /// record the outcome once, never retried.
    private func applyFullscreen(rule: SnapMemory.Rule, win: AXUIElement, visible: CGRect, pid: pid_t) {
        // Already full screen (the re-check, or the app restored it itself): done — moving a full-screen window's
        // origin would be a pointless write that echoes back as a resize.
        if isFullscreen(win) {
            store.noteOutcome(.applied, ruleID: rule.id, at: Date()); persist(); return
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(win, "AXFullScreen" as CFString, &settable) == .success, settable.boolValue else {
            store.noteOutcome(.notSettable, ruleID: rule.id, at: Date()); persist(); return
        }
        // Move the window's origin onto the target display before entering full screen, so macOS creates the
        // full-screen Space on the right screen rather than wherever the window happened to be.
        _ = WindowManager.setWindow(win, rect: CGRect(origin: visible.origin, size: currentFrame(of: win)?.size ?? visible.size))
        let ok = AXUIElementSetAttributeValue(win, "AXFullScreen" as CFString, kCFBooleanTrue) == .success
        lastOwnWriteAt[pid] = ProcessInfo.processInfo.systemUptime
        store.noteOutcome(ok ? .applied : .failed, ruleID: rule.id, at: Date())
        persist()
    }

    private func isFullscreen(_ win: AXUIElement) -> Bool {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &v) == .success && (v as? Bool == true)
    }

    private func currentFrame(of win: AXUIElement) -> CGRect? {
        var posVal: CFTypeRef?, sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posVal) == .success, let pv = posVal,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeVal) == .success, let sv = sizeVal,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &point)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    // MARK: Recording hand drags / fullscreen toggles (rule 2, 6; spec case table)

    private func recordDebounced(pid: pid_t) {
        guard var w = watches[pid] else { return }
        w.recordDebounce?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { SnapMemoryController.shared.recordNow(pid: pid) } }
        w.recordDebounce = work
        watches[pid] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + SnapMemory.recordDebounce, execute: work)
    }

    private func recordNow(pid: pid_t) {
        guard let w = watches[pid], let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier,
              let win = mainWindow(of: w.app), let frame = currentFrame(of: win) else { return }
        let (arrangement, map) = currentArrangementAndKeys()
        guard let existing = store.rule(bundleID: bundleID, arrangement: arrangement) else { return }

        let isFullscreenNow = isFullscreen(win)
        let wasFullscreen: Bool = { if case .fullscreen = existing.layout { return true }; return false }()

        let kind: SnapMemory.ChangeKind
        if isFullscreenNow != wasFullscreen {
            kind = .fullscreenToggled(isFullscreenNow)
        } else if isFullscreenNow {
            // Still full screen and still recorded as such: a resize while full screen (our own echo, the app
            // relaying out) says nothing new — classifying that frame would turn the rule into a bogus frame.
            return
        } else {
            kind = .movedOrResized
        }

        let pointerDown = NSEvent.pressedMouseButtons != 0
        guard SnapMemory.shouldRecord(kind: kind, eventAt: ProcessInfo.processInfo.systemUptime,
                                      lastOwnWriteAt: lastOwnWriteAt[pid], pointerDown: pointerDown,
                                      framesEnabled: framesEnabled) else { return }

        var updated = existing
        if case .fullscreenToggled(let on) = kind, on {
            updated.layout = .fullscreen
        } else {
            // Attribute the window to whichever display it now overlaps most (it may have been dragged across).
            // ONE ordered list, so the index returned by the rules refers to the same screen it was computed from.
            let screens = Array(map.keys)
            let visibleFrames = screens.map { WindowManager.axVisibleFrame(for: $0) }
            if let idx = SnapMemory.displayIndex(for: frame, visibleFrames: visibleFrames), let key = map[screens[idx]] {
                updated.display = key
            }
            let visible = WindowManager.axVisibleFrame(for: screen(for: updated.display, in: map) ?? NSScreen.main!)
            updated.layout = SnapMemory.classify(frame: frame, visible: visible)
        }
        updated.updatedAt = Date()
        store.remember(updated)
        persist()
    }
}
