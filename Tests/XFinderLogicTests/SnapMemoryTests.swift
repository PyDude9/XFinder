import XCTest
import CoreGraphics
@testable import XFinderLogicTests

/// SNAPMEM (2026-10-18) — the pure rules of window-layout memory. Each test names the failure case it pins.
final class SnapMemoryTests: XCTestCase {
    typealias M = SnapMemory

    let builtin = M.DisplayKey(uuid: "37D8832A", name: "Built-in Retina Display", pixelWidth: 3456, pixelHeight: 2234, isBuiltin: true)
    let external = M.DisplayKey(uuid: "62512806", name: "HC-L200A", pixelWidth: 1920, pixelHeight: 1080, isBuiltin: false)
    let visible = CGRect(x: 0, y: 33, width: 1728, height: 1052)      // AX top-left space, menu bar excluded
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func rule(_ bundle: String = "com.google.Chrome", layout: M.Layout = .snap(.maximize),
              arrangement: M.Arrangement? = nil, date: Date? = nil) -> M.Rule {
        let a = arrangement ?? M.Arrangement(displays: [builtin, external])
        return M.Rule(bundleID: bundle, appName: "Chrome", arrangement: a, display: a.displays.first!, layout: layout,
                      updatedAt: date ?? t0, lastOutcome: nil, lastAppliedAt: nil)
    }

    // MARK: Displays

    func testArrangementIgnoresEnumerationOrderAndKeepsBuiltinFirst() {
        let a = M.Arrangement(displays: [external, builtin])
        let b = M.Arrangement(displays: [builtin, external])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.displays.first, builtin, "the built-in display sorts first whatever the cable order")
        XCTAssertNotEqual(M.Arrangement(displays: [builtin]).id, a.id, "one display and two displays are two sets")
        XCTAssertTrue(a.contains(external)); XCTAssertFalse(M.Arrangement(displays: [builtin]).contains(external))
    }

    // MARK: Frames

    func testNormalizedFrameRoundTripsAndSurvivesAResolutionChange() {
        let frame = CGRect(x: 100, y: 133, width: 800, height: 600)
        let n = M.NormalizedRect.normalized(frame, in: visible)!
        let back = n.denormalized(in: visible)
        XCTAssertEqual(back.minX, frame.minX, accuracy: 0.001); XCTAssertEqual(back.height, frame.height, accuracy: 0.001)
        // Same display at half the points: the fractions hold, the frame scales.
        let smaller = CGRect(x: 0, y: 33, width: 864, height: 526)
        let scaled = n.denormalized(in: smaller)
        XCTAssertEqual(scaled.width, 400, accuracy: 0.001); XCTAssertEqual(scaled.minX, 50, accuracy: 0.001)
        XCTAssertNil(M.NormalizedRect.normalized(frame, in: .zero), "nothing to be a fraction of")
        // Off-screen values clamp instead of producing fractions outside 0…1.
        let off = M.NormalizedRect.normalized(CGRect(x: -500, y: 33, width: 5000, height: 10), in: visible)!
        XCTAssertEqual(off.x, 0); XCTAssertEqual(off.width, 1)
    }

    func testClassifyRecognisesEveryTargetWithinToleranceAndKeepsOtherFramesAsFrames() {
        for t in SnapLayout.Target.allCases {
            // Nudged 3 pt (position) and 3 pt narrower (size): both inside the 4 pt per-edge tolerance. An `insetBy(3)`
            // would change the width by 6 — that is a frame, and the first run of this test said so.
            var r = t.rect(in: visible).offsetBy(dx: 3, dy: 3)
            r.size.width -= 3
            XCTAssertEqual(M.classify(frame: r, visible: visible), .snap(t), "\(t) should classify as itself")
        }
        let hand = CGRect(x: 123, y: 210, width: 777, height: 555)
        guard case .frame(let n) = M.classify(frame: hand, visible: visible) else { return XCTFail("a hand frame stays a frame") }
        XCTAssertEqual(n.denormalized(in: visible).width, 777, accuracy: 0.001)
        // 5 pt off is outside the tolerance — a frame, not the half.
        let almost = SnapLayout.Target.leftHalf.rect(in: visible).offsetBy(dx: 5, dy: 0)
        if case .snap = M.classify(frame: almost, visible: visible) { XCTFail("5 pt off must not round to a target") }
        XCTAssertNil(M.rect(for: .fullscreen, visible: visible), "full screen is not a rect")
        XCTAssertEqual(M.rect(for: .snap(.leftHalf), visible: visible), SnapLayout.Target.leftHalf.rect(in: visible))
    }

    // MARK: Store

    func testStoreReplacesByIdCapsAtTwoHundredAndForgets() {
        var s = M.Store()
        s.remember(rule(layout: .snap(.leftHalf)))
        s.remember(rule(layout: .fullscreen))
        XCTAssertEqual(s.rules.count, 1, "one rule per app per display set")
        XCTAssertEqual(s.rules.first?.layout, .fullscreen)
        // A different display set is a different rule for the same app.
        s.remember(rule(arrangement: M.Arrangement(displays: [builtin])))
        XCTAssertEqual(s.rules.count, 2)
        XCTAssertEqual(s.rules(for: M.Arrangement(displays: [builtin])).count, 1)
        // Cap: the oldest go first.
        for i in 0..<M.Store.maxRules { s.remember(rule("app.\(i)", date: t0.addingTimeInterval(Double(i) + 10))) }
        XCTAssertEqual(s.rules.count, M.Store.maxRules)
        XCTAssertNil(s.rule(bundleID: "com.google.Chrome", arrangement: M.Arrangement(displays: [builtin, external])),
                     "the oldest rule (t0) was dropped")
        XCTAssertNotNil(s.rule(bundleID: "app.\(M.Store.maxRules - 1)", arrangement: M.Arrangement(displays: [builtin, external])))
        let id = s.rules.last!.id
        s.forget(id: id); XCTAssertNil(s.rules.first { $0.id == id })
        s.forgetAll(); XCTAssertTrue(s.rules.isEmpty)
    }

    func testStoreRoundTripsThroughJSONAndToleratesGarbage() {
        var s = M.Store()
        s.remember(rule(layout: .frame(M.NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6))))
        s.remember(rule("com.apple.Safari", layout: .fullscreen))
        s.noteOutcome(.notSettable, ruleID: s.rules.last!.id, at: t0.addingTimeInterval(5))
        let back = M.Store.decode(s.encode())
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.rules.last?.lastOutcome, .notSettable)
        XCTAssertEqual(M.Store.decode(nil), M.Store())
        XCTAssertEqual(M.Store.decode(Data("{not json".utf8)), M.Store(), "a damaged payload is an empty store, never a crash")
        XCTAssertEqual(M.Store.decode(Data("{\"version\":1,\"rules\":[{\"bogus\":1}]}".utf8)), M.Store())
    }

    // MARK: Recording

    func testOwnWritesPointerDownAndTheFramesSwitchGateRecording() {
        // Our own AX write echoes back within the grace: ignored.
        XCTAssertFalse(M.shouldRecord(kind: .movedOrResized, eventAt: 10.9, lastOwnWriteAt: 10.0, pointerDown: false, framesEnabled: true))
        XCTAssertTrue(M.shouldRecord(kind: .movedOrResized, eventAt: 11.6, lastOwnWriteAt: 10.0, pointerDown: false, framesEnabled: true))
        // Mid-drag: wait for the release.
        XCTAssertFalse(M.shouldRecord(kind: .movedOrResized, eventAt: 20, lastOwnWriteAt: nil, pointerDown: true, framesEnabled: true))
        // Frames switch off: hand drags are not remembered, full screen still is.
        XCTAssertFalse(M.shouldRecord(kind: .movedOrResized, eventAt: 20, lastOwnWriteAt: nil, pointerDown: false, framesEnabled: false))
        XCTAssertTrue(M.shouldRecord(kind: .fullscreenToggled(true), eventAt: 20, lastOwnWriteAt: nil, pointerDown: false, framesEnabled: false))
        // A full-screen echo of our own write is still an echo.
        XCTAssertFalse(M.shouldRecord(kind: .fullscreenToggled(true), eventAt: 10.5, lastOwnWriteAt: 10.0, pointerDown: false, framesEnabled: false))
        // An XFinder snap is recorded whatever the grace says (it IS the own write).
        XCTAssertTrue(M.shouldRecord(kind: .snapByXFinder, eventAt: 10.1, lastOwnWriteAt: 10.0, pointerDown: true, framesEnabled: false))
    }

    // MARK: Replay

    func testReplayNeedsTheSameDisplaySetARunningAppAndOnePassPerLaunch() {
        let both = M.Arrangement(displays: [builtin, external]), one = M.Arrangement(displays: [builtin])
        let r = rule()
        XCTAssertNil(M.replay(rule: r, trigger: .windowAppeared, arrangementNow: one, appRunning: true, alreadyAppliedThisLaunch: false),
                     "a rule for two displays does not fire with one")
        XCTAssertNil(M.replay(rule: r, trigger: .displayChanged, arrangementNow: both, appRunning: false, alreadyAppliedThisLaunch: false))
        XCTAssertNil(M.replay(rule: r, trigger: .windowAppeared, arrangementNow: both, appRunning: true, alreadyAppliedThisLaunch: true),
                     "a second window of the same launch is not a new launch")
        let p = M.replay(rule: r, trigger: .windowAppeared, arrangementNow: both, appRunning: true, alreadyAppliedThisLaunch: false)
        XCTAssertEqual(p?.delays, [0.5, 2.0])
        // Display change and switch-on ignore the per-launch flag.
        XCTAssertEqual(M.replay(rule: r, trigger: .displayChanged, arrangementNow: both, appRunning: true, alreadyAppliedThisLaunch: true)?.delays, [1.0, 3.0])
        XCTAssertEqual(M.replay(rule: r, trigger: .switchedOn, arrangementNow: both, appRunning: true, alreadyAppliedThisLaunch: true)?.delays.first, 0)
        for t in [M.Trigger.windowAppeared, .displayChanged, .switchedOn] {
            let d = M.delays(for: t)
            XCTAssertEqual(d.count, 2, "settle + exactly one re-check, never a loop: \(t)")
            XCTAssertLessThan(d[0], d[1])
        }
    }

    func testReapplyOnlyWhenTheWindowDrifted() {
        let target = SnapLayout.Target.leftHalf.rect(in: visible)
        XCTAssertFalse(M.needsReapply(current: target.insetBy(dx: 2, dy: 2), target: target))
        XCTAssertTrue(M.needsReapply(current: target.offsetBy(dx: 40, dy: 0), target: target))
    }

    func testWindowBelongsToTheDisplayHoldingItsCentreElseTheLargestOverlap() {
        let a = CGRect(x: 0, y: 0, width: 1728, height: 1117), b = CGRect(x: 1728, y: 37, width: 1920, height: 1080)
        XCTAssertEqual(M.displayIndex(for: CGRect(x: 1600, y: 100, width: 800, height: 600), visibleFrames: [a, b]), 1, "centre at x 2000 is on b")
        XCTAssertEqual(M.displayIndex(for: CGRect(x: 1500, y: 100, width: 400, height: 600), visibleFrames: [a, b]), 0)
        // Centre in a gap between displays: the larger overlap wins.
        XCTAssertEqual(M.displayIndex(for: CGRect(x: 1700, y: 2000, width: 100, height: 100), visibleFrames: [a, b]), nil, "touches neither")
    }

    // MARK: Store keys

    func testEveryLayoutAndOutcomeKeyIsTranslated() throws {
        let store = try L10nFixture.load()
        let layouts: [M.Layout] = [.fullscreen, .frame(M.NormalizedRect(x: 0, y: 0, width: 1, height: 1))] + SnapLayout.Target.allCases.map { .snap($0) }
        for l in layouts { XCTAssertFalse(store.entries[l.titleKey]?.en.isEmpty ?? true, "\(l.titleKey) is not translated") }
        for o in [M.Outcome.applied, .notTrusted, .noWindow, .notSettable, .failed, .appNotRunning] {
            XCTAssertFalse(store.entries[o.titleKey]?.en.isEmpty ?? true, "\(o.titleKey) is not translated")
        }
    }
}
