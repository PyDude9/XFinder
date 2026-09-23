import AppKit
import CoreGraphics
import os

/// Compile with the production GestureModel.swift and GestureEngine.swift.
/// No synthetic event leaves this harness: an injected sink collects every output.
/// --live-tap separately attempts a real tap with unused button 31 for two seconds.
@main struct MouseGesturesProbe {
    static func main() {
        print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Accessibility trusted: \(AXIsProcessTrusted())")
        if CommandLine.arguments.contains("--live-tap") {
            let active = OSAllocatedUnfairLock(initialState: false)
            let engine = GestureEngine {
                precondition(!Thread.isMainThread)
                if case .status("Đang hoạt động") = $0 { active.withLock { $0 = true } }
                print("LIVE result: \($0)")
            }
            var config = GestureConfiguration(); config.enabled = true; config.trigger = .mouseButton(31)
            engine.send(.configure(config))
            Thread.sleep(forTimeInterval:2)
            engine.send(.configure(GestureConfiguration()))
            Thread.sleep(forTimeInterval:0.5)
            guard active.withLock({ $0 }) else { print("LIVE TAP NOT VERIFIED: permission/service failure"); exit(2) }
            let recovered = DispatchSemaphore(value:0)
            DispatchQueue(label:"gesture.recovery.probe",qos:.userInteractive).async {
                let worker = GestureWorker(engine:engine, eventSink: { _ in })
                worker.configuration.enabled = true; worker.configuration.trigger = .mouseButton(31)
                worker.reconcileTap()
                guard let tap = worker.tap else { print("Recovery probe could not open tap"); exit(2) }
                CGEvent.tapEnable(tap:tap,enable:false)
                precondition(!CGEvent.tapIsEnabled(tap:tap))
                let dummy = CGEvent(source:nil)!
                _ = worker.handle(.tapDisabledByTimeout,dummy)
                precondition(CGEvent.tapIsEnabled(tap:tap),"Recovery must re-enable the real port")
                worker.configuration.enabled = false; worker.reconcileTap()
                precondition(worker.tap == nil && worker.tapSource == nil)
                print("PASS live background tap install/remove and simulated-timeout recovery of real port")
                recovered.signal()
            }
            precondition(recovered.wait(timeout:.now()+5) == .success)
            return
        }
        let done = DispatchSemaphore(value:0)
        DispatchQueue(label:"gesture.probe",qos:.userInteractive).async {
            precondition(!Thread.isMainThread)
            let engine = GestureEngine { _ in }
            var output: [CGEvent] = []
            let worker = GestureWorker(engine: engine, eventSink: { output.append($0.copy()!) })
            worker.configuration.enabled = true
            // The harness pins its **own** trigger rather than relying on the production
            // default. That default moved from the wheel click (2) to the upper side button
            // (3) when the wheel-hold was found to be ergonomically impossible, and this
            // file silently started failing its first assertion as a result — a reminder
            // that a harness reading a default is testing two things at once.
            worker.configuration.trigger = .mouseButton(2)
            worker.bundle = "com.apple.Safari"
            // The machine's own symbolic hotkeys, as measured on this host: Mission Control
            // ⌃↑, App Exposé ⌃↓, previous/next Space ⌃←/⌃→, each with `0x840000` =
            // control | maskSecondaryFn. The Global preset resolves its four arms from
            // these, so a harness with no bindings models a Mac with nothing bound — a real
            // state, but not one that produces a keypress.
            let machineBindings = GestureSystemBindings(entries: SpaceBinding.parse([
                "32": ["enabled": 1, "value": ["parameters": [65535, 126, 8650752]]],
                "33": ["enabled": 1, "value": ["parameters": [65535, 125, 8650752]]],
                "79": ["enabled": 1, "value": ["parameters": [65535, 123, 8650752]]],
                "81": ["enabled": 1, "value": ["parameters": [65535, 124, 8650752]]],
            ]))
            worker.systemBindings = machineBindings

            /// What the engine actually posted must equal what the **resolver** says the row
            /// sends. Written as an equivalence rather than a magic keycode because the raw
            /// numbers here had already drifted from the presets (this file expected `⌘T`
            /// for the browser tilt row, which had become `⌃Tab`) — and a harness asserting a
            /// stale literal fails for the wrong reason. The unit tests pin the table; this
            /// pins that the engine dispatches what the table says.
            func posts(_ action: GestureAction) -> Bool {
                guard let expected = GestureMap.shortcut(of: action) else { return false }
                return output.count == 2
                    && output[0].getIntegerValueField(.keyboardEventKeycode) == Int64(expected.key)
                    && output[1].getIntegerValueField(.keyboardEventKeycode) == Int64(expected.key)
                    && (output[0].flags.rawValue & expected.flags) == expected.flags
            }
            func resolved(_ bundle: String, _ direction: GestureDirection) -> GestureAction {
                GestureProfiles.resolve(overrides: [:], bundle: bundle, direction: direction)
            }
            func event(_ type: CGEventType, button: Int64 = 2, dx: Int64 = 0, dy: Int64 = 0) -> CGEvent {
                let value = CGEvent(source:nil)!
                value.type = type
                value.setIntegerValueField(.mouseEventButtonNumber,value:button)
                value.setIntegerValueField(.mouseEventDeltaX,value:dx)
                value.setIntegerValueField(.mouseEventDeltaY,value:dy)
                value.location = CGPoint(x:100,y:100)
                return value
            }
            func send(_ type: CGEventType, button: Int64 = 2, dx: Int64 = 0, dy: Int64 = 0) -> Bool {
                worker.handle(type,event(type,button:button,dx:dx,dy:dy)) == nil
            }
            precondition(send(.otherMouseDown))
            precondition(send(.otherMouseUp))
            precondition(output.map(\.type) == [.otherMouseDown,.otherMouseUp])
            precondition(output.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == GestureWorker.syntheticTag })
            precondition(worker.handle(output[0].type,output[0]) != nil, "Replay recursion guard")
            output.removeAll()
            precondition(send(.otherMouseDown)); precondition(send(.otherMouseDragged,dy:-20)); precondition(send(.otherMouseUp))
            precondition(output.map(\.type) == [.keyDown,.keyUp])
            precondition(posts(resolved("com.apple.Safari", .up)), "engine did not post the row's own key")
            precondition(output[0].flags.contains(.maskCommand))
            output.removeAll()
            precondition(send(.otherMouseDown)); precondition(send(.otherMouseDragged,dx:20))
            precondition(send(.otherMouseDragged,dx:-20)); precondition(send(.otherMouseUp))
            precondition(output.isEmpty,"Out-and-back must not replay a click")
            precondition(send(.otherMouseDown)); worker.cancelStroke(); worker.bundle = "other.app"
            precondition(send(.otherMouseUp)); precondition(output.isEmpty,"Never click into a different app")
            precondition(send(.otherMouseDown)); worker.configuration.enabled = false; worker.cancelStroke()
            precondition(send(.otherMouseUp)); precondition(output.isEmpty)
            worker.configuration.enabled = true
            worker.configuration.trigger = .modifierKey(GestureShortcut.option)
            let flags = event(.flagsChanged); flags.flags = .maskAlternate
            precondition(worker.handle(.flagsChanged,flags) != nil)
            precondition(send(.mouseMoved,dx:20))
            flags.flags = []; precondition(worker.handle(.flagsChanged,flags) != nil)
            precondition(output.count == 2)
            output.removeAll()
            // A normal shortcut while holding the modifier cancels the gesture.
            flags.flags = .maskAlternate; _ = worker.handle(.flagsChanged,flags)
            _ = send(.keyDown); precondition(!send(.mouseMoved,dx:50))
            flags.flags = []; _ = worker.handle(.flagsChanged,flags)
            precondition(output.isEmpty)
            worker.configuration.trigger = .mouseButton(2)
            precondition(!send(.leftMouseDown,button:0))
            precondition(!send(.otherMouseDown,button:4))
            // Record mode ignores motion/left click and drains the recorded release.
            worker.beginRecording(.trigger)
            precondition(!send(.mouseMoved,dx:30))
            precondition(!send(.leftMouseDown,button:0))
            precondition(send(.otherMouseDown,button:4))
            precondition(worker.configuration.trigger == .mouseButton(4))
            precondition(send(.otherMouseUp,button:4)); precondition(output.isEmpty)
            worker.beginRecording(.trigger); worker.lastModifierFlags = 0
            let modifierRecord = event(.flagsChanged)
            modifierRecord.flags = [.maskControl,.maskShift]
            _ = worker.handle(.flagsChanged,modifierRecord)
            modifierRecord.flags = .maskControl // releasing Shift must not bind Control
            _ = worker.handle(.flagsChanged,modifierRecord)
            precondition(worker.record != nil)
            modifierRecord.flags = []; _ = worker.handle(.flagsChanged,modifierRecord)
            modifierRecord.flags = .maskAlternate; _ = worker.handle(.flagsChanged,modifierRecord)
            precondition(worker.record == nil && worker.configuration.trigger == .modifierKey(GestureShortcut.option))
            modifierRecord.flags = []; _ = worker.handle(.flagsChanged,modifierRecord)
            worker.beginRecording(.shortcut("example.app",.up))
            let recorded = event(.keyDown); recorded.setIntegerValueField(.keyboardEventKeycode,value:3)
            recorded.flags = [.maskCommand,.maskShift]
            precondition(worker.handle(.keyDown,recorded) == nil)
            precondition(worker.handle(.keyDown,recorded) == nil) // swallow repeat
            recorded.type = .keyUp
            precondition(worker.handle(.keyUp,recorded) == nil)
            precondition(worker.suppressedKey == nil)
            worker.beginRecording(.trigger)
            let escape = event(.keyDown); escape.setIntegerValueField(.keyboardEventKeycode,value:53)
            precondition(worker.handle(.keyDown,escape) == nil)
            escape.type = .keyUp; precondition(worker.handle(.keyUp,escape) == nil)
            precondition(worker.record == nil && output.isEmpty)
            // Tilt is opt-in, discrete only, and throttled. Native/unknown scroll passes.
            worker.configuration.tiltEnabled = true; worker.bundle = "com.apple.Safari"
            let wheel = event(.scrollWheel)
            wheel.setIntegerValueField(.scrollWheelEventDeltaAxis2,value:1)
            wheel.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
            precondition(worker.handle(.scrollWheel,wheel) != nil)
            wheel.setIntegerValueField(.scrollWheelEventIsContinuous,value:0)
            precondition(worker.handle(.scrollWheel,wheel) == nil)
            precondition(output.count == 2)
            precondition(worker.handle(.scrollWheel,wheel) == nil && output.count == 2)
            precondition(posts(resolved("com.apple.Safari", .tiltLeft)),
                         "the tilt row's dispatched key differs from what the resolver reports")
            output.removeAll()
            worker.configuration.trigger = .mouseButton(2)
            // Directly measure the actual callback (no posting), not a model copy.
            precondition(send(.otherMouseDown))
            let move = event(.otherMouseDragged,dx:1,dy:1)
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<80_000 { precondition(worker.handle(.otherMouseDragged,move) == nil) }
            let elapsed = CFAbsoluteTimeGetCurrent()-start
            worker.cancelStroke(); precondition(send(.otherMouseUp))
            precondition(output.isEmpty)

            // ── System actions post *this machine's* chord, or nothing at all ───────────
            //
            // The bug asserted against: the Global preset named Mission Control and posted
            // an invented `NSEvent.systemDefined` keytype 32. That keytype does not exist
            // (`ev_keymap.h` stops at `NX_KEYTYPE_MENU = 25`), so the gesture was recognised
            // and did nothing — the user's "nhận dạng cho có, không làm việc". The fix
            // resolves the chord from the user's own symbolic hotkeys; this measures that
            // the engine posts **that** chord, with its mask intact, and that an action the
            // machine does not bind posts nothing at all.
            var systemConfig = GestureConfiguration()
            systemConfig.enabled = true
            systemConfig.trigger = .mouseButton(2)
            worker.configuration = systemConfig
            worker.bundle = "com.example.unknown"   // no preset of its own → the Global table
            // The live shape read from this machine on 2026-09-23: 32 = ⌃↑ Mission Control,
            // 81 = ⌃→ next Space, both with `0x840000` = control | maskSecondaryFn.
            worker.systemBindings = machineBindings
            guard let expectedMissionControl = machineBindings.shortcut(for: .missionControl),
                  let expectedNextSpace = machineBindings.shortcut(for: .nextSpace) else {
                preconditionFailure("the fixture must carry these two bindings")
            }
            output.removeAll()
            precondition(send(.otherMouseDown))
            precondition(send(.otherMouseDragged,dy:-20))   // pull UP → Mission Control
            precondition(send(.otherMouseUp))
            precondition(output.map(\.type) == [.keyDown,.keyUp],
                         "a system action must post a real key pair, not a systemDefined event")
            precondition(output[0].getIntegerValueField(.keyboardEventKeycode)
                         == Int64(expectedMissionControl.key),
                         "Mission Control must post the key this machine binds, not an invented one")
            precondition(output[0].flags.contains(.maskControl), "control must survive")
            precondition(output[0].flags.contains(.maskSecondaryFn),
                         "the secondary-fn bit is part of Apple's encoding and must survive")
            output.removeAll()
            precondition(send(.otherMouseDown))
            precondition(send(.otherMouseDragged,dx:20))    // pull RIGHT → next Space
            precondition(send(.otherMouseUp))
            precondition(output.map(\.type) == [.keyDown,.keyUp])
            precondition(output[0].getIntegerValueField(.keyboardEventKeycode)
                         == Int64(expectedNextSpace.key),
                         "next Space must post the key this machine binds")
            // Unbound: the same gesture must post **nothing**. A fabricated fallback here is
            // exactly the shipped bug, so this is the assertion that keeps it out.
            worker.systemBindings = .empty
            output.removeAll()
            precondition(send(.otherMouseDown))
            precondition(send(.otherMouseDragged,dy:-20))
            precondition(send(.otherMouseUp))
            precondition(output.isEmpty,
                         "an unbound system action must post nothing, not a guessed key")
            // A deliberately unassigned row (the dev preset leaves up/down empty) likewise
            // posts nothing, and must not be reported as a sent shortcut.
            worker.bundle = "dev.zed.Zed"
            output.removeAll()
            precondition(send(.otherMouseDown))
            precondition(send(.otherMouseDragged,dy:-20))
            precondition(send(.otherMouseUp))
            precondition(output.isEmpty, "an unassigned direction must not post a key")

            print("PASS production callback: click replay, recursion, browser shortcut, deadzone, cancellation, modifier, passthrough")
            print("PASS system actions: machine's own chord posted, fn+control mask intact, unbound posts nothing")
            print("80,000 callback invocations: \(elapsed) s; NOT a physical 8 kHz mouse measurement")
            done.signal()
        }
        precondition(done.wait(timeout:.now()+15) == .success)
    }
}
