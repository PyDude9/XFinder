import XCTest
import Foundation

final class LiveActivityTests: XCTestCase {
    typealias A = LiveActivity
    func p(_ ac: Bool, _ pct: Int?, charging: Bool = false, charged: Bool = false) -> A.PowerState {
        A.PowerState(onAC: ac, percent: pct, charging: charging, charged: charged)
    }

    func testTheFirstReadingIsABaselineNotNews() {
        XCTAssertEqual(A.powerItems(old: nil, new: p(false, 5)), [])
        XCTAssertNil(A.networkItem(wasOnline: nil, isOnline: false))
        XCTAssertNil(A.capsLockItem(wasOn: nil, isOn: true))
    }

    /// Measured: on AC at 80 % with optimised charging, IsCharging and IsCharged are both false.
    func testPluggingInSaysChargingOrHoldingTruthfully() {
        XCTAssertEqual(A.powerItems(old: p(false, 80), new: p(true, 80, charging: true)).first?.titleKey, "Đang sạc")
        XCTAssertEqual(A.powerItems(old: p(false, 80), new: p(true, 80)).first?.titleKey, "Đã cắm sạc, đang giữ mức pin")
        XCTAssertEqual(A.powerItems(old: p(true, 80), new: p(false, 80)).first?.titleKey, "Đang dùng pin")
    }

    func testFullOnlyWhenTheOSSaysCharged() {
        XCTAssertEqual(A.powerItems(old: p(true, 99, charging: true), new: p(true, 100, charging: true)), [],
                       "100 % alone is not 'charged'")
        XCTAssertEqual(A.powerItems(old: p(true, 99, charging: true), new: p(true, 100, charged: true)).map(\.titleKey), ["Pin đã đầy"])
    }

    func testLowAndCriticalFireOnceWhenCrossingDownOnBattery() {
        XCTAssertEqual(A.powerItems(old: p(false, 21), new: p(false, 20)).map(\.titleKey), ["Pin yếu"])
        XCTAssertEqual(A.powerItems(old: p(false, 20), new: p(false, 19)), [], "already low — no repeat every percent")
        XCTAssertEqual(A.powerItems(old: p(false, 11), new: p(false, 10)).map(\.titleKey), ["Pin rất yếu"])
        XCTAssertEqual(A.powerItems(old: p(true, 21), new: p(true, 15)), [], "on AC a low level is not a warning")
        XCTAssertEqual(A.powerItems(old: p(false, 25), new: p(false, 8)).map(\.titleKey), ["Pin rất yếu"], "a big drop says the worse one")
    }

    func testNetworkAndCapsLockOnlyOnChange() {
        XCTAssertEqual(A.networkItem(wasOnline: true, isOnline: false)?.titleKey, "Mất kết nối mạng")
        XCTAssertNil(A.networkItem(wasOnline: true, isOnline: true))
        XCTAssertEqual(A.capsLockItem(wasOn: false, isOn: true)?.titleKey, "Caps Lock đang bật")
    }

    // MARK: Queue

    func item(_ k: A.Kind, _ key: String) -> A.Item { A.Item(kind: k, symbol: "x", titleKey: key, detail: nil, tint: .neutral) }

    func testCancelQueuedLocalMessagePreservesUnrelatedActivity() {
        var queue = A.Queue()
        let meeting = item(.meeting, "meeting")
        let network = item(.network, "network")
        let messageID = UUID()
        var message = item(.localMessage, "message")
        message.localMessageID = messageID
        queue.push(meeting)
        queue.push(message)
        queue.push(network)

        queue.removePendingLocalMessage(id: UUID())
        XCTAssertEqual(queue.localMessageID, messageID)
        queue.removePendingLocalMessage(id: messageID)

        XCTAssertNil(queue.localMessageID)
        XCTAssertEqual(queue.current, meeting)
        XCTAssertEqual(queue.advance(), network)
    }

    func testSameKindReplacesSoFlappingNeverStacks() {
        var q = A.Queue()
        q.push(item(.network, "lost"))
        q.push(item(.network, "back"))
        XCTAssertEqual(q.current?.titleKey, "back")
        XCTAssertTrue(q.pending.isEmpty)
        q.push(item(.power, "plug")); q.push(item(.power, "unplug"))
        XCTAssertEqual(q.pending.map(\.titleKey), ["unplug"], "a waiting notice is replaced by a newer one of its kind")
    }

    func testDifferentKindsWaitTheirTurnAndTheBacklogIsBounded() {
        var q = A.Queue()
        q.push(item(.alert, "a"))
        for k in [A.Kind.power, .network, .capsLock, .bluetooth] { q.push(item(k, k.rawValue)) }
        XCTAssertEqual(q.current?.titleKey, "a")
        XCTAssertEqual(q.pending.count, 4)
        XCTAssertEqual(q.advance()?.titleKey, "power")
        q.clear(); XCTAssertNil(q.current)
        XCTAssertNil(q.advance())
    }

    /// A notice whose turn comes while the hub is open is held, not consumed: it shows once the notch is idle again.
    func testANoticeThatCannotBeDrawnIsHeldNotLost() {
        var q = A.Queue()
        q.push(item(.agent, "A")); q.push(item(.network, "B"))
        XCTAssertEqual(q.advance()?.titleKey, "B", "A's time is up while the hub is open")
        q.hold()
        XCTAssertNil(q.current)
        XCTAssertEqual(q.pending.map(\.titleKey), ["B"], "B waits at the head of the line")
        XCTAssertEqual(q.resume()?.titleKey, "B", "resume with nothing current brings B back")
        XCTAssertEqual(q.current?.titleKey, "B")
        XCTAssertTrue(q.pending.isEmpty)
        XCTAssertNil(q.resume(), "nothing to resume while something is current")
        q.hold(); q.push(item(.power, "C"))
        XCTAssertEqual(q.current?.titleKey, "C", "a new notice may show; the held one stays queued")
        XCTAssertEqual(q.advance()?.titleKey, "B", "and B comes back after it")
    }

    /// A volume press must answer at once even while another notice is up; the notice comes back right after.
    func testKeyFeedbackJumpsTheQueueAndTheNoticeItInterruptedReturnsFirst() {
        var q = A.Queue()
        q.push(item(.agent, "Claude is waiting"))
        q.push(item(.network, "net"))
        XCTAssertTrue(q.push(item(.volume, "vol 31")), "feedback becomes current — the caller re-renders")
        XCTAssertEqual(q.current?.titleKey, "vol 31")
        XCTAssertEqual(q.pending.map(\.titleKey), ["Claude is waiting", "net"], "the interrupted notice is next, then the rest")
        XCTAssertTrue(q.push(item(.brightness, "bri 50")))
        XCTAssertEqual(q.current?.titleKey, "bri 50")
        XCTAssertFalse(q.pending.contains { $0.kind.isKeyFeedback }, "an interrupted volume level is dropped, not replayed")
        XCTAssertEqual(q.advance()?.titleKey, "Claude is waiting")
        // A notice arriving during feedback still waits its turn.
        var f = A.Queue(); f.push(item(.volume, "v")); XCTAssertFalse(f.push(item(.alert, "a")))
        XCTAssertEqual(f.current?.titleKey, "v")
        XCTAssertTrue(A.Kind.volume.isKeyFeedback && A.Kind.brightness.isKeyFeedback)
        XCTAssertFalse(A.Kind.allCases.filter { $0 != .volume && $0 != .brightness }.contains { $0.isKeyFeedback })
    }

    /// Exhaustive: any 6 pushes/advances keep at most one item per kind in the whole queue and never
    /// exceed the bound.
    func testNoSequenceHoldsTwoOfAKind() {
        let kinds: [A.Kind] = [.power, .network, .volume, .brightness]
        func walk(_ q: A.Queue, _ depth: Int) {
            let all = (q.current.map { [$0] } ?? []) + q.pending
            XCTAssertEqual(Set(all.map(\.kind)).count, all.count, "duplicate kind: \(all.map(\.kind))")
            XCTAssertLessThanOrEqual(q.pending.count, A.Queue.maxPending)
            guard depth < 6 else { return }
            for k in kinds { var n = q; n.push(item(k, "\(depth)")); walk(n, depth + 1) }
            var a = q; a.advance(); walk(a, depth + 1)
        }
        walk(A.Queue(), 0)
    }

    func testEveryHeadlineIsInTheStore() throws {
        let store = try L10nFixture.load()
        var keys = Set<String>()
        for (o, n) in [(p(false, 80), p(true, 80, charging: true)), (p(false, 80), p(true, 80)), (p(true, 80), p(false, 80)),
                       (p(true, 99), p(true, 100, charged: true)), (p(false, 21), p(false, 20)), (p(false, 11), p(false, 10))] {
            A.powerItems(old: o, new: n).forEach { keys.insert($0.titleKey) }
        }
        for b in [true, false] {
            A.networkItem(wasOnline: !b, isOnline: b).map { keys.insert($0.titleKey) }
            A.capsLockItem(wasOn: !b, isOn: b).map { keys.insert($0.titleKey) }
            keys.insert(A.bluetoothItem(name: "x", connected: b).titleKey)
        }
        keys.insert(A.volumeItem(old: .init(level: 0.5, muted: false), new: .init(level: 0.6, muted: false))!.titleKey)
        keys.insert(A.volumeItem(old: .init(level: 0.5, muted: false), new: .init(level: 0.5, muted: true))!.titleKey)
        keys.insert(A.timerFinishedItem(A.Countdown(minutes: 5, now: Date())).titleKey)
        keys.insert(A.brightnessItem(level: 0.5).titleKey)
        XCTAssertEqual(keys.count, 16, "the vocabulary walk collapsed")
        for k in keys { XCTAssertNotNil(store.entries[k], k) }
    }

    // MARK: B4b

    func testVolumeHUDOnlyOnARealChange() {
        let v = { (l: Double, m: Bool) in A.VolumeState(level: l, muted: m) }
        XCTAssertNil(A.volumeItem(old: nil, new: v(0.5, false)), "baseline")
        XCTAssertNil(A.volumeItem(old: v(0.5, false), new: v(0.5, false)), "CoreAudio reports one change twice")
        let up = A.volumeItem(old: v(0.5, false), new: v(0.5625, false))
        XCTAssertEqual(up?.detail, "56%"); XCTAssertEqual(up?.level ?? -1, 0.5625, accuracy: 1e-9)
        XCTAssertEqual(A.volumeItem(old: v(0.5, false), new: v(0.5, true))?.titleKey, "Đã tắt tiếng")
        XCTAssertEqual(A.volumeItem(old: v(0.5, false), new: v(0.5, true))?.level, 0)
        XCTAssertEqual(A.volumeItem(old: v(0.1, false), new: v(0.9, false))?.symbol, "speaker.wave.3.fill")
    }

    func testCountdownLabelNeverReadsZeroEarlyAndFinishesOnTime() {
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let c = A.Countdown(minutes: 25, now: t0)
        XCTAssertEqual(c.label(at: t0), "25:00")
        XCTAssertEqual(c.label(at: t0.addingTimeInterval(0.4)), "25:00", "rounded up: 24:59.6 still reads 25:00")
        XCTAssertEqual(c.label(at: t0.addingTimeInterval(1499.5)), "0:01", "half a second left is not 0:00")
        XCTAssertFalse(c.isFinished(at: t0.addingTimeInterval(1499.5)))
        XCTAssertTrue(c.isFinished(at: t0.addingTimeInterval(1500)))
        XCTAssertEqual(c.label(at: t0.addingTimeInterval(2000)), "0:00")
        XCTAssertEqual(A.Countdown(minutes: 90, now: t0).label(at: t0), "1:30:00")
        XCTAssertEqual(A.Countdown(minutes: 0, now: t0).duration, 60, "a zero-minute timer is one minute, not instant")
    }

    /// P2: a paused timer freezes — the wall clock can run past its old end and it is neither finished nor shorter.
    func testAPausedCountdownFreezesAndResumesWhereItStopped() {
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let c = A.Countdown(minutes: 10, now: t0)
        let p = c.paused(at: t0.addingTimeInterval(120))
        XCTAssertTrue(p.isPaused)
        XCTAssertEqual(p.remaining(at: t0.addingTimeInterval(5000)), 480, accuracy: 0.001, "frozen at 8:00")
        XCTAssertFalse(p.isFinished(at: t0.addingTimeInterval(5000)), "a paused timer never finishes by itself")
        XCTAssertEqual(p.paused(at: t0.addingTimeInterval(9000)), p, "pausing twice changes nothing")
        let r = p.resumed(at: t0.addingTimeInterval(5000))
        XCTAssertFalse(r.isPaused)
        XCTAssertEqual(r.remaining(at: t0.addingTimeInterval(5000)), 480, accuracy: 0.001)
        XCTAssertTrue(r.isFinished(at: t0.addingTimeInterval(5480)))
        XCTAssertEqual(r.resumed(at: t0.addingTimeInterval(5100)), r, "resuming a running timer changes nothing")
        XCTAssertEqual(r.progress(at: t0.addingTimeInterval(5240)), 0.6, accuracy: 0.001, "6 of 10 minutes elapsed")
    }

    /// P2: "+5 / −5" while running or paused; what is left stays within 1 minute … the maximum.
    func testExtendingKeepsAtLeastAMinuteAndAtMostTheMaximum() {
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let c = A.Countdown(minutes: 10, now: t0)
        XCTAssertEqual(c.extended(byMinutes: 5, now: t0).remaining(at: t0), 900, accuracy: 0.001)
        XCTAssertEqual(c.extended(byMinutes: 5, now: t0).duration, 900, accuracy: 0.001)
        let two = t0.addingTimeInterval(480)                      // 2 minutes left
        XCTAssertEqual(c.extended(byMinutes: -5, now: two).remaining(at: two), 60, accuracy: 0.001, "−5 with 2 left ⇒ 1, never 0")
        XCTAssertFalse(c.extended(byMinutes: -5, now: two).isFinished(at: two))
        let paused = c.paused(at: two).extended(byMinutes: 5, now: two)
        XCTAssertTrue(paused.isPaused, "extending a paused timer keeps it paused")
        XCTAssertEqual(paused.remaining(at: two.addingTimeInterval(999)), 420, accuracy: 0.001)
        let huge = A.Countdown(minutes: 118, now: t0).extended(byMinutes: 30, now: t0)
        XCTAssertEqual(huge.remaining(at: t0), TimeInterval(A.timerMaxMinutes * 60), accuracy: 0.001, "capped at the maximum")
        XCTAssertEqual(c.extended(byMinutes: 0, now: t0), c)
        // duration = elapsed + left after any extension, so the progress bar keeps the elapsed share it had.
        let long = A.Countdown(minutes: 120, now: t0)
        let nearEnd = t0.addingTimeInterval(7140)                  // 1 minute left
        let ext = long.extended(byMinutes: 5, now: nearEnd)
        XCTAssertEqual(ext.remaining(at: nearEnd), 360, accuracy: 0.001)
        XCTAssertEqual(ext.duration, 7140 + 360, accuracy: 0.001, "elapsed 119 min + 6 left")
        XCTAssertEqual(ext.progress(at: nearEnd), 7140 / 7500, accuracy: 0.0001)
    }

    func testTheIdleStepperSnapsToFiveMinutesWithinRange() {
        XCTAssertEqual(A.steppedMinutes(25, by: 1), 30)
        XCTAssertEqual(A.steppedMinutes(25, by: -1), 20)
        XCTAssertEqual(A.steppedMinutes(23, by: 1), 25, "an off-grid value snaps up to the grid")
        XCTAssertEqual(A.steppedMinutes(23, by: -1), 20, "… and down to the grid")
        XCTAssertEqual(A.steppedMinutes(5, by: -1), 5, "never below the minimum")
        XCTAssertEqual(A.steppedMinutes(120, by: 1), 120, "never above the maximum")
        XCTAssertEqual(A.validTimerMinutes(nil), A.timerDefaultMinutes)
        XCTAssertEqual(A.validTimerMinutes(0), A.timerMinMinutes)
        XCTAssertEqual(A.validTimerMinutes(900), A.timerMaxMinutes)
    }

    // MARK: Brightness HUD + HUD suppression (owner's request, 2026-10-15)

    /// The brightness bar answers every key XFinder takes — including at 0 and 1, where the level cannot move
    /// (nothing observes brightness, so an unchanged press would otherwise look dead).
    func testBrightnessHUDAnswersEveryPressEvenAtTheEnds() {
        let mid = A.brightnessItem(level: 0.5625)
        XCTAssertEqual(mid.kind, .brightness)
        XCTAssertEqual(mid.titleKey, "Độ sáng")
        XCTAssertEqual(mid.detail, "56%")
        XCTAssertEqual(mid.level ?? -1, 0.5625, accuracy: 1e-9)
        XCTAssertEqual(A.brightnessItem(level: 1.0).detail, "100%", "at the top it still answers")
        XCTAssertEqual(A.brightnessItem(level: 0.0).detail, "0%", "at the bottom it still answers")
        XCTAssertEqual(A.brightnessItem(level: 1.0).symbol, "sun.max.fill")
        XCTAssertEqual(A.brightnessItem(level: 0.2).symbol, "sun.min.fill")
        XCTAssertEqual(A.brightnessItem(level: 2.0).level, 1.0, "clamped to the top")
    }

    /// A volume key XFinder took at the top/bottom moves nothing, so CoreAudio reports nothing; the forced
    /// item is what answers the press. The change-driven path keeps its "only a real change" rule.
    func testVolumeItemForAStateAlwaysAnswers() {
        XCTAssertEqual(A.volumeItem(A.VolumeState(level: 1.0, muted: false)).detail, "100%")
        XCTAssertEqual(A.volumeItem(A.VolumeState(level: 0.0, muted: false)).titleKey, "Đã tắt tiếng")
        XCTAssertNil(A.volumeItem(old: .init(level: 1.0, muted: false), new: .init(level: 1.0, muted: false)))
    }

    func testPhaseReadsBitsEightToFifteen() {
        XCTAssertEqual(A.HUDSuppression.phase(data1: 0x0A00), .down)
        XCTAssertEqual(A.HUDSuppression.phase(data1: 0x0B00), .up)
        XCTAssertEqual(A.HUDSuppression.phase(data1: 0x0000), .other, "a stray state-0 event is not a key press")
        XCTAssertEqual(A.HUDSuppression.phase(data1: 0x20A00), .down, "brightness-up down")
    }

    private func ctx(hide: Bool = true, present: Bool = true, master: Bool = true,
                     volume: Bool = true, brightness: Bool = true, writable: Bool = true,
                     volumeWritable: Bool = true, modifiers: Bool = false)
        -> A.HUDSuppression.Context {
        .init(hideSystemHUD: hide, canPresent: present, masterOn: master,
              volumeOn: volume, brightnessOn: brightness, brightnessWritable: writable,
              volumeWritable: volumeWritable, modifiersHeld: modifiers)
    }

    func testSwallowingNeedsTheSwitchAndASurfaceToDrawOn() {
        let c = ctx()
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .down, context: c), .consume(.volumeUp))
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 1, phase: .down, context: c), .consume(.volumeDown))
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 7, phase: .down, context: c), .consume(.mute))
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 2, phase: .down, context: c), .consume(.brightnessUp))
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 3, phase: .down, context: c), .consume(.brightnessDown))
    }

    func testSwallowingIsRefusedWheneverXFinderCannotShowTheValue() {
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .down, context: ctx(hide: false)), .passThrough,
                       "the switch is off: macOS keeps its own square")
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .down, context: ctx(present: false)), .passThrough,
                       "no notch surface: swallowing would leave no feedback at all")
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .down, context: ctx(master: false)), .passThrough)
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .down, context: ctx(volume: false)), .passThrough)
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 2, phase: .down, context: ctx(brightness: false)), .passThrough)
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 2, phase: .down, context: ctx(writable: false)), .passThrough,
                       "brightness not writable (no DisplayServices): let macOS draw its own")
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .down, context: ctx(volumeWritable: false)), .passThrough,
                       "an output whose volume cannot be set: macOS shows its own 'not available' square")
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 7, phase: .down, context: ctx(volumeWritable: false)), .passThrough)
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .down, context: ctx(modifiers: true)), .passThrough,
                       "⌥⇧ quarter steps and ⌥-opens-Settings stay macOS's")
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 2, phase: .down, context: ctx(modifiers: true)), .passThrough)
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 2, phase: .down, context: ctx(volumeWritable: false)), .consume(.brightnessUp),
                       "the volume device never blocks the brightness key")
        // A kind that is off never blocks the other kind.
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 2, phase: .down, context: ctx(volume: false)), .consume(.brightnessUp))
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .down, context: ctx(brightness: false)), .consume(.volumeUp))
    }

    func testUnrecognisedKeysAndPhasesAreNeverTouched() {
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 32, phase: .down, context: ctx()), .passThrough,
                       "keytype 32 is not a real NX constant — never swallow it")
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 0, phase: .other, context: ctx()), .passThrough)
        XCTAssertEqual(A.HUDSuppression.decide(keyType: 2, phase: .other, context: ctx()), .passThrough)
    }

    /// The UP follows its DOWN, whatever the context has become by then.
    func testAnUpFollowsItsDownWhateverTheContextBecame() {
        var pairing = A.HUDSuppression.Pairing()
        // Swallowed DOWN, then the switch flips off before the UP: the UP is still swallowed.
        XCTAssertEqual(pairing.resolve(keyType: 0, phase: .down) { .consume(.volumeUp) }, .consume(.volumeUp))
        XCTAssertEqual(pairing.resolve(keyType: 0, phase: .up) { .passThrough }, .consume(.volumeUp))
        // DOWN passed (⌥ held), ⌥ released before the UP: the UP passes too.
        XCTAssertEqual(pairing.resolve(keyType: 2, phase: .down) { .passThrough }, .passThrough)
        XCTAssertEqual(pairing.resolve(keyType: 2, phase: .up) { .consume(.brightnessUp) }, .passThrough)
        // A lone UP (its DOWN arrived before the tap existed) is never swallowed.
        XCTAssertEqual(pairing.resolve(keyType: 1, phase: .up) { .consume(.volumeDown) }, .passThrough)
        // Auto-repeat DOWNs while held keep the pair; one UP closes it.
        _ = pairing.resolve(keyType: 3, phase: .down) { .consume(.brightnessDown) }
        _ = pairing.resolve(keyType: 3, phase: .down) { .consume(.brightnessDown) }
        XCTAssertEqual(pairing.resolve(keyType: 3, phase: .up) { .passThrough }, .consume(.brightnessDown))
        XCTAssertEqual(pairing.resolve(keyType: 3, phase: .up) { .passThrough }, .passThrough, "closed once")
        XCTAssertTrue(pairing.swallowed.isEmpty)
    }
}
