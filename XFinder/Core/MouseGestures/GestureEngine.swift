import AppKit
import CoreGraphics
import os

// All commands/results are value types. AppKit never enters the event callback.
enum GestureCommand: Sendable {
    case configure(GestureConfiguration)
    case frontmost(String)
    case recordTrigger
    case recordShortcut(String, GestureDirection)
    case cancelRecording
    case suspend
    case resume
}
enum GestureResult: Sendable {
    case status(String)
    case tap(active: Bool)
    /// Why the last tap attempt failed. Empty when no failure has occurred.
    case tapFailure(String)
    case trigger(TriggerSource)
    case shortcut(String, GestureDirection, GestureShortcut)
    case recordingEnded
}

/// A single high-priority serial queue owns one CFRunLoop. A dispatch queue alone
/// does not deliver Mach-port event taps: the run-loop source is essential.
/// The command source wakes it only for settings/app changes, not on a timer.
final class GestureEngine: Sendable {
    private struct Inbox {
        var started = false
        var commands: [GestureCommand] = []
        var loop: CFRunLoop?
        var source: CFRunLoopSource?
    }
    // CF references stay behind this lock. Only the documented thread-safe
    // CFRunLoopSourceSignal/CFRunLoopWakeUp operations run on a caller thread.
    // No non-Sendable reference escapes the lock; worker state never crosses it.
    private let inbox = OSAllocatedUnfairLock(uncheckedState: Inbox())
    private let queue = DispatchQueue(label: "com.xfinder.gesture.engine", qos: .userInteractive)
    let report: @Sendable (GestureResult) -> Void
    init(report: @escaping @Sendable (GestureResult) -> Void) { self.report = report }

    func send(_ command: GestureCommand) {
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

    fileprivate func drain() -> [GestureCommand] {
        inbox.withLockUnchecked { state in
            let commands = state.commands
            state.commands.removeAll(keepingCapacity: true)
            return commands
        }
    }

    private func run() {
        // Worker is created, accessed and destroyed exclusively on this queue.
        let worker = GestureWorker(engine: self)
        var context = CFRunLoopSourceContext(version: 0,
            info: Unmanaged.passUnretained(worker).toOpaque(), retain: nil, release: nil,
            copyDescription: nil, equal: nil, hash: nil, schedule: nil, cancel: nil,
            perform: { info in
                guard let info else { return }
                Unmanaged<GestureWorker>.fromOpaque(info).takeUnretainedValue().commands()
            })
        guard let source = CFRunLoopSourceCreate(nil, 0, &context) else {
            inbox.withLockUnchecked { $0.started = false }
            report(.status("Không tạo được vòng lặp cử chỉ")); return
        }
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        inbox.withLockUnchecked { $0.loop = loop; $0.source = source }
        worker.commands()
        withExtendedLifetime(worker) { CFRunLoopRun() }
    }
}

// Internal so the standalone runtime harness can exercise the production callback.
// Never pass a worker between threads.
final class GestureWorker {
    static let syntheticTag: Int64 = 0x584647455354
    let engine: GestureEngine
    var configuration = GestureConfiguration()
    var suspended = false
    var bundle = ""
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var stroke: GestureStroke?
    var originalDown: CGEvent?
    var swallowedButton: Int?
    var strokeBundle = ""
    var cancelled = false
    var modifierHeld = false
    var lastModifierFlags: UInt64 = 0
    var record: Record?
    var recordingTimer: CFRunLoopTimer?
    var holdTimer: CFRunLoopTimer?
    var lastTilt: CFTimeInterval = 0
    var lastDebug: CFTimeInterval = 0
    let logQueue = DispatchQueue(label: "com.xfinder.gesture.debug", qos: .utility)
    let logPending = OSAllocatedUnfairLock(initialState: false)
    enum Record { case trigger; case shortcut(String, GestureDirection) }
    private let eventSink: (CGEvent) -> Void
    init(engine: GestureEngine, eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }) {
        self.engine = engine; self.eventSink = eventSink
    }

    func commands() {
        for command in engine.drain() {
            switch command {
            case .configure(let config):
                cancelStroke(); configuration = config
                if !config.enabled { endRecording() }
            case .frontmost(let id):
                if bundle != id { cancelStroke(); endRecording(); bundle = id }
            case .recordTrigger: cancelStroke(); beginRecording(.trigger)
            case .recordShortcut(let id, let direction): cancelStroke(); beginRecording(.shortcut(id,direction))
            case .cancelRecording: endRecording()
            case .suspend: suspended = true; cancelStroke(); endRecording()
            case .resume: suspended = false; cancelStroke()
            }
        }
        reconcileTap()
    }

    /// Reason the last `tapCreate` returned nil. `tapCreate` reports no error of
    /// its own, so the only trustworthy signal is the process's AX trust state at
    /// the moment of the attempt. Recorded so the UI and a probe can tell
    /// "permission missing" apart from "tap exists but is not rendering".
    nonisolated(unsafe) static var lastTapFailure = ""

    func reconcileTap() {
        let needed = (!suspended && (configuration.enabled || record != nil)) || swallowedButton != nil || suppressedKey != nil
        if !needed {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
            if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), tapSource, .commonModes) }
            tap = nil; tapSource = nil
            engine.report(.tap(active: false))
            engine.report(.status("Đã tắt")); return
        }
        guard tap == nil else { return }
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged,
            .rightMouseDragged, .otherMouseDragged, .flagsChanged, .keyDown, .keyUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        Self.lastTapFailure = AXIsProcessTrusted()
            ? "tapCreate trả nil dù đã có quyền Trợ năng"
            : "chưa có quyền Trợ năng"
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<GestureWorker>.fromOpaque(info).takeUnretainedValue().handle(type,event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            endRecording(reconcile: false)
            engine.report(.tap(active: false))
            engine.report(.tapFailure(Self.lastTapFailure))
            engine.report(.status("Không mở được Event Tap — kiểm tra quyền Trợ năng")); return
        }
        tap = port; tapSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        engine.report(.tap(active: true))
        engine.report(.status("Đang hoạt động"))
    }

    func beginRecording(_ value: Record) {
        endRecording(); record = value
        lastModifierFlags = CGEventSource.flagsState(.combinedSessionState).rawValue & GestureShortcut.modifierMask
        engine.report(.status("Đang ghi — Esc để hủy, tự dừng sau 10 giây"))
        recordingTimer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent()+10, 0, 0, 0) { [weak self] _ in
            self?.endRecording(); self?.reconcileTap()
        }
        if let recordingTimer { CFRunLoopAddTimer(CFRunLoopGetCurrent(), recordingTimer, .commonModes) }
    }
    func scheduleReconcile() {
        CFRunLoopPerformBlock(CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.reconcileTap()
        }
    }
    func endRecording(reconcile: Bool = true) {
        guard record != nil else { return }
        record = nil
        if let recordingTimer { CFRunLoopTimerInvalidate(recordingTimer) }
        recordingTimer = nil
        engine.report(.recordingEnded)
        engine.report(.status(configuration.enabled ? "Đang hoạt động" : "Đã tắt"))
        if reconcile { scheduleReconcile() }
    }
    func cancelStroke() {
        stroke = nil; originalDown = nil; cancelled = true
        // Keep swallowing the matching up even after settings change: the native
        // target never saw the down. Do not replay a click into a newly focused app.
    }
    func startStroke(_ event: CGEvent, button: Int?) {
        stroke = GestureStroke(); strokeBundle = bundle; cancelled = false
        originalDown = button == nil ? nil : event.copy()
        swallowedButton = button
        if let holdTimer { CFRunLoopTimerInvalidate(holdTimer) }
        armDrainTimer()
    }
    func armDrainTimer() {
        if let holdTimer { CFRunLoopTimerInvalidate(holdTimer) }
        holdTimer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent()+15, 0, 0, 0) { [weak self] _ in
            // Missing release (disconnect / sleep): release the drain after a
            // bounded interval so disabling never leaves a permanent event tap.
            self?.cancelStroke()
            self?.swallowedButton = nil
            self?.suppressedKey = nil
            self?.reconcileTap()
        }
        if let holdTimer { CFRunLoopAddTimer(CFRunLoopGetCurrent(), holdTimer, .commonModes) }
    }
    func finishStroke(_ event: CGEvent) {
        defer {
            stroke = nil; originalDown = nil; swallowedButton = nil
            if let holdTimer { CFRunLoopTimerInvalidate(holdTimer) }; holdTimer = nil
        }
        guard !cancelled, strokeBundle == bundle, let stroke else { return }
        if stroke.isClick(deadzone: configuration.deadzone), let down = originalDown,
           let up = event.copy() {
            // Use the original click location, flags, button and click count.
            // Preallocate BOTH events before posting either half of the pair.
            up.location = down.location
            up.flags = down.flags
            up.setIntegerValueField(.mouseEventClickState, value: down.getIntegerValueField(.mouseEventClickState))
            post(down); post(up)
        } else if let direction = stroke.direction(deadzone: configuration.deadzone) {
            perform(configuration.action(bundle: strokeBundle, direction: direction))
        }
        debug(stroke)
    }
    func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        eventSink(event)
    }
    func perform(_ action: GestureAction) {
        guard case .shortcut(let shortcut) = action,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.key, keyDown: false) else { return }
        down.flags = CGEventFlags(rawValue: shortcut.flags)
        up.flags = down.flags
        post(down); post(up)
    }
    func debug(_ stroke: GestureStroke) {
        guard configuration.debug else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now-lastDebug >= 0.25 else { return }
        lastDebug = now
        let pending = logPending
        let enqueue = pending.withLock { busy in
            if busy { return false }; busy = true; return true
        }
        guard enqueue else { return } // A blocked stdout can never grow an unbounded queue.
        let id = bundle, x = stroke.x, y = stroke.y, distance = stroke.distance
        let profile = GestureProfiles.all.first { $0.id == bundle }?.name ?? "Global"
        logQueue.async {
            print("[MouseGestures] app=\(id) profile=\(profile) delta=(\(x),\(y)) path=\(distance)")
            pending.withLock { $0 = false }
        }
    }
    var suppressedKey: Int64?
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        assert(!Thread.isMainThread, "Gesture callback must never run on the main thread")
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelStroke(); endRecording()
            // Timeout disables a valid port; invalidating it then enabling it would
            // be a use-after-invalidate. Re-enable only while the CFMachPort is valid.
            if let tap, CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                engine.report(.tap(active: true))
                engine.report(.status("Event Tap đã khôi phục; cử chỉ cũ đã hủy"))
            } else {
                engine.report(.tap(active: false))
            }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag { return pass }
        let flagsNow = event.flags.rawValue & GestureShortcut.modifierMask
        let addedModifiers = flagsNow & ~lastModifierFlags
        if type == .flagsChanged { lastModifierFlags = flagsNow }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, suppressedKey == key {
            suppressedKey = nil
            if stroke == nil && swallowedButton == nil {
                if let holdTimer { CFRunLoopTimerInvalidate(holdTimer) }; holdTimer = nil
            }
            scheduleReconcile(); return nil
        }
        if type == .keyDown, suppressedKey == key { return nil }
        let isDown = type == .rightMouseDown || type == .otherMouseDown
        let isUp = type == .rightMouseUp || type == .otherMouseUp
        if isUp, swallowedButton == button {
            finishStroke(event)
            // reconcile outside callback removal is unnecessary while enabled.
            if !configuration.enabled && record == nil { scheduleReconcile() }
            return nil
        }
        if let record {
            if type == .keyDown, key == 53 {
                suppressedKey = key; armDrainTimer(); endRecording(); return nil
            }
            guard swallowedButton == nil else { return pass }
            switch record {
            case .trigger:
                if isDown, TriggerSource.mouseButton(button).isValid {
                    startStroke(event, button: button); cancelStroke()
                    configuration.trigger = .mouseButton(button)
                    engine.report(.trigger(configuration.trigger)); endRecording(); return nil
                }
                if type == .flagsChanged {
                    let flags = event.flags.rawValue & GestureShortcut.modifierMask
                    if TriggerSource.modifierKey(flags).isValid && addedModifiers == flags {
                        configuration.trigger = .modifierKey(flags)
                        engine.report(.trigger(configuration.trigger)); endRecording()
                    }
                }
            case .shortcut(let id, let direction):
                if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    suppressedKey = key; armDrainTimer()
                    engine.report(.shortcut(id,direction,GestureShortcut(key: UInt16(clamping:key),
                        flags:event.flags.rawValue & GestureShortcut.modifierMask)))
                    endRecording(); return nil
                }
            }
            return pass
        }
        guard configuration.enabled && !suspended else { return pass }
        switch configuration.trigger {
        case .mouseButton(let n):
            if isDown, button == n { startStroke(event, button: button); return nil }
        case .modifierKey(let flag):
            if type == .flagsChanged {
                if event.flags.rawValue & flag == flag {
                    if !modifierHeld {
                        modifierHeld = true
                        // Do not steal an in-progress native selection/window drag.
                        if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
                            startStroke(event, button: nil)
                        }
                    }
                } else {
                    if stroke != nil { finishStroke(event) }
                    modifierHeld = false
                    cancelled = false
                }
                return pass // Preserve normal keyboard shortcuts; modifier clicks are not fabricated.
            }
        }
        if type == .leftMouseDown || type == .keyDown || (isDown && swallowedButton != button) {
            cancelStroke()
        }
        if stroke == nil, swallowedButton != nil, type == .rightMouseDragged || type == .otherMouseDragged { return nil }
        let isMovement: Bool
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: isMovement = true
        default: isMovement = false
        }
        if stroke != nil && isMovement {
            stroke?.move(dx:Double(event.getIntegerValueField(.mouseEventDeltaX)),
                         dy:Double(event.getIntegerValueField(.mouseEventDeltaY)))
            if let stroke { debug(stroke) }
            return nil // Do not leak a native drag without a native down.
        }
        if type == .scrollWheel, configuration.tiltEnabled {
            // Discrete horizontal wheel only: do not steal Magic Mouse / trackpad
            // continuous scrolling or inertia and pretend it is a hardware tilt.
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
                  event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0 else { return pass }
            let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            guard delta != 0 else { return pass }
            let action = configuration.action(bundle:bundle,direction:delta > 0 ? .tiltLeft : .tiltRight)
            if action == .unassigned || action == .horizontalScroll { return pass }
            let now = CFAbsoluteTimeGetCurrent()
            if now-lastTilt >= 0.35 { lastTilt = now; perform(action) }
            return nil
        }
        return pass
    }
}
