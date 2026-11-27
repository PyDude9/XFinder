import AppKit
import CoreGraphics
import os

/// XF-T25 — smooth mouse scrolling. The ONE reader of the `smoothScroll.*` keys; owns the engine and tells the page what
/// it is doing (running, paused and why, which kind of device scrolled last). Rules live in `SmoothScrollRules`.
@MainActor
@Observable
final class SmoothScrollController {
    static let shared = SmoothScrollController()
    private init() {}

    enum State: Equatable {
        case off
        case running
        case needsAccessibility
        case pausedFor(String)      // another smoother is running (its name)
        case pausedForCapture       // a scrolling capture is in progress
    }

    private(set) var state: State = .off
    /// Which kind of device scrolled last while the feature was on — the page shows it so the owner can check his mouse.
    private(set) var lastKind: SmoothScrollRules.Kind?

    // ONE reader per key (FeatureKeyDefaultsTests: the views' @AppStorage defaults equal these literals).
    var enabled: Bool { UserDefaults.standard.object(forKey: "smoothScroll.enabled") as? Bool ?? false }
    var speed: Int { UserDefaults.standard.object(forKey: "smoothScroll.speed") as? Int ?? 100 }
    var smoothness: Int { UserDefaults.standard.object(forKey: "smoothScroll.smoothness") as? Int ?? 220 }
    var reverse: Bool { UserDefaults.standard.object(forKey: "smoothScroll.reverse") as? Bool ?? false }
    var linear: Bool { UserDefaults.standard.object(forKey: "smoothScroll.linear") as? Bool ?? false }

    var settings: SmoothScrollRules.Settings {
        SmoothScrollRules.Settings(enabled: enabled, speed: speed, smoothness: smoothness, reverse: reverse, linear: linear).clamped
    }

    @ObservationIgnored private var engine: SmoothScrollEngine?
    /// Bumped for every new engine: a retired engine's late report (a `tapFailed` racing a quick off/on) must not
    /// overwrite what the live engine says.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var capturePaused = false

    /// Launch, every change of a key, app activation (Accessibility may have been granted meanwhile).
    func applySettings() {
        let s = settings
        guard s.enabled else { stopAll(); state = .off; return }
        guard AXIsProcessTrusted() else { stopAll(); state = .needsAccessibility; return }
        watchOtherSmoothers()
        let conflict = SmoothScrollRules.conflict(running: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let paused = conflict != nil || capturePaused
        state = conflict.map { .pausedFor($0) } ?? (capturePaused ? .pausedForCapture : .running)
        let engine: SmoothScrollEngine
        if let live = self.engine {
            engine = live
        } else {
            generation += 1
            let gen = generation
            engine = SmoothScrollEngine { report in
                Task { @MainActor in SmoothScrollController.shared.receive(report, generation: gen) }
            }
            self.engine = engine
        }
        engine.send(.configure(s, paused: paused))
    }

    /// XF-T26: a scrolling capture posts its own scroll events and must see the page move exactly as asked.
    func setCapturePaused(_ paused: Bool) {
        guard capturePaused != paused else { return }
        capturePaused = paused
        applySettings()
    }

    private func receive(_ report: SmoothScrollEngine.Report, generation gen: Int) {
        guard gen == generation, engine != nil else { return }
        switch report {
        case .kind(let k): if lastKind != k { lastKind = k }
        case .tapFailed:
            state = AXIsProcessTrusted() ? .off : .needsAccessibility
        }
    }

    private func stopAll() {
        engine?.send(.stop)
        engine = nil
        lastKind = nil
        for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObservers = []
    }

    /// Only while the feature is on: an app launching or quitting may be another smoother.
    private func watchOtherSmoothers() {
        guard workspaceObservers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier,
                      SmoothScrollRules.conflictingBundleIDs[id] != nil else { return }
                MainActor.assumeIsolated { SmoothScrollController.shared.applySettings() }   // queue: .main
            })
        }
    }
}

/// One serial queue owning one CFRunLoop, like `GestureEngine`: the tap and the glide timer both live on it, so the worker's
/// state is never shared. Callers only append commands under the lock and signal the run-loop source.
final class SmoothScrollEngine: Sendable {
    enum Command: Sendable {
        case configure(SmoothScrollRules.Settings, paused: Bool)
        case stop
    }
    enum Report: Sendable {
        case kind(SmoothScrollRules.Kind)
        case tapFailed
    }

    private struct Inbox {
        var started = false
        var commands: [Command] = []
        var loop: CFRunLoop?
        var source: CFRunLoopSource?
    }
    private let inbox = OSAllocatedUnfairLock(uncheckedState: Inbox())
    private let queue = DispatchQueue(label: "com.xfinder.smoothscroll", qos: .userInteractive)
    let report: @Sendable (Report) -> Void
    init(report: @escaping @Sendable (Report) -> Void) { self.report = report }

    func send(_ command: Command) {
        let start = inbox.withLockUnchecked { state in
            state.commands.append(command)
            if let source = state.source, let loop = state.loop {
                CFRunLoopSourceSignal(source); CFRunLoopWakeUp(loop)
            }
            if state.started { return false }
            state.started = true
            return true
        }
        if start { queue.async { self.run() } }
    }

    fileprivate func drain() -> [Command] {
        inbox.withLockUnchecked { state in
            let c = state.commands
            state.commands.removeAll(keepingCapacity: true)
            return c
        }
    }

    fileprivate func finished() {
        inbox.withLockUnchecked { $0 = Inbox() }
    }

    private func run() {
        let worker = SmoothScrollWorker(engine: self)
        var context = CFRunLoopSourceContext(version: 0,
            info: Unmanaged.passUnretained(worker).toOpaque(), retain: nil, release: nil,
            copyDescription: nil, equal: nil, hash: nil, schedule: nil, cancel: nil,
            perform: { info in
                guard let info else { return }
                Unmanaged<SmoothScrollWorker>.fromOpaque(info).takeUnretainedValue().commands()
            })
        guard let source = CFRunLoopSourceCreate(nil, 0, &context) else { finished(); report(.tapFailed); return }
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        inbox.withLockUnchecked { $0.loop = loop; $0.source = source }
        worker.commands()
        withExtendedLifetime(worker) { CFRunLoopRun() }
        CFRunLoopRemoveSource(loop, source, .commonModes)
    }
}

/// Created, used and destroyed on the engine's queue only.
final class SmoothScrollWorker {
    let engine: SmoothScrollEngine
    var settings = SmoothScrollRules.Settings()
    var paused = false
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var timer: CFRunLoopTimer?
    var glide = SmoothScrollRules.Glide()
    var lastTick: CFAbsoluteTime = 0
    var lastFlags: CGEventFlags = []
    var lastKind: SmoothScrollRules.Kind?

    init(engine: SmoothScrollEngine) { self.engine = engine }

    func commands() {
        for command in engine.drain() {
            switch command {
            case .configure(let s, let p):
                settings = s; paused = p
                if p { stopGlide() }
            case .stop:
                teardown()
                engine.finished()
                CFRunLoopStop(CFRunLoopGetCurrent())
                return
            }
        }
        reconcileTap()
    }

    /// The tap exists only while smoothing is on and not paused — a paused feature costs nothing either.
    private func reconcileTap() {
        let needed = settings.enabled && !paused
        if !needed { teardown(); return }
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: { _, type, event, info in
                    guard let info else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<SmoothScrollWorker>.fromOpaque(info).takeUnretainedValue().handle(type, event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            engine.report(.tapFailed); return
        }
        tap = port; tapSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func teardown() {
        stopGlide()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), tapSource, .commonModes) }
        tap = nil; tapSource = nil
    }

    /// The tap callback: read the fields, decide, add to the glide. Nothing heavier ever runs here — a slow callback is
    /// how a tap gets disabled by timeout.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stopGlide()
            if let tap, CFMachPortIsValid(tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let e = SmoothScrollRules.WheelEvent(
            userData: event.getIntegerValueField(.eventSourceUserData),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            lineY: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            lineX: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            pointY: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            pointX: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
            commandOptionOrControl: !flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty)
        if e.userData != SmoothScrollRules.tag {
            let kind = SmoothScrollRules.kind(e)
            if kind != lastKind { lastKind = kind; engine.report(.kind(kind)) }
        }
        switch SmoothScrollRules.decide(e, settings: paused ? SmoothScrollRules.Settings() : settings) {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .smooth(let dx, let dy):
            lastFlags = flags
            glide.add(dx: dx, dy: dy)
            startGlide()
            return nil    // swallowed: the glide posts the distance instead
        }
    }

    private func startGlide() {
        guard timer == nil else { return }
        lastTick = CFAbsoluteTimeGetCurrent()
        let t = CFRunLoopTimerCreateWithHandler(nil, lastTick + SmoothScrollRules.framePeriod, SmoothScrollRules.framePeriod, 0, 0) { [weak self] _ in
            self?.frame()
        }
        timer = t
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), t, .commonModes)
    }

    private func stopGlide() {
        if let timer { CFRunLoopTimerInvalidate(timer) }
        timer = nil
        glide.reset()
    }

    private func frame() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = now - lastTick
        lastTick = now
        let (dx, dy) = glide.step(dt: dt, smoothnessMs: settings.smoothness)
        if dx != 0 || dy != 0, let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) {
            e.flags = lastFlags      // ⇧ turns a vertical wheel horizontal in AppKit; keep what the hand was holding
            e.setIntegerValueField(.eventSourceUserData, value: SmoothScrollRules.tag)
            e.post(tap: .cgSessionEventTap)
        }
        if glide.isIdle { stopGlide() }
    }
}
