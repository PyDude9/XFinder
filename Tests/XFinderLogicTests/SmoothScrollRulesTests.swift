import XCTest

/// XF-T25 — smooth mouse scrolling, the pure rules.
final class SmoothScrollRulesTests: XCTestCase {
    typealias R = SmoothScrollRules
    let on = R.Settings(enabled: true)

    func wheel(lines: Int64 = 0, x: Int64 = 0, continuous: Bool = false, pointY: Int64 = 0, pointX: Int64 = 0,
               phase: Int64 = 0, momentum: Int64 = 0, tag: Int64 = 0, mods: Bool = false) -> R.WheelEvent {
        R.WheelEvent(userData: tag, isContinuous: continuous, scrollPhase: phase, momentumPhase: momentum,
                     lineY: lines, lineX: x, pointY: pointY, pointX: pointX, commandOptionOrControl: mods)
    }

    // MARK: Which events

    /// The Razer and the Magic Mouse both say "continuous" (measured); only the phases tell a touch surface apart.
    func testTheDeviceIsToldApartByPhasesNotByIsContinuous() {
        XCTAssertEqual(R.kind(wheel(lines: 1)), .wheel)
        XCTAssertEqual(R.kind(wheel(continuous: true, pointY: 12)), .wheel, "a high-resolution wheel has no phases")
        XCTAssertEqual(R.kind(wheel(continuous: true, pointY: 12, phase: 2)), .gesture, "trackpad: scroll phase")
        XCTAssertEqual(R.kind(wheel(continuous: true, pointY: 12, momentum: 2)), .gesture, "trackpad inertia: momentum phase")
    }

    func testOnlyAPlainWheelIsSmoothed() {
        XCTAssertEqual(R.decide(wheel(lines: 1), settings: R.Settings()), .pass, "off")
        XCTAssertEqual(R.decide(wheel(lines: 1, phase: 1), settings: on), .pass, "trackpad untouched")
        XCTAssertEqual(R.decide(wheel(lines: 1, momentum: 3), settings: on), .pass, "trackpad inertia untouched")
        XCTAssertEqual(R.decide(wheel(lines: 1, tag: R.tag), settings: on), .pass, "our own events pass")
        XCTAssertEqual(R.decide(wheel(lines: 1, tag: R.gestureTag), settings: on), .pass, "the gesture engine's scroll is not smoothed twice")
        XCTAssertEqual(R.decide(wheel(lines: 1, mods: true), settings: on), .pass, "⌘/⌥/⌃-wheel zooms: the app needs the original")
        XCTAssertEqual(R.decide(wheel(), settings: on), .pass, "nothing to move")
        XCTAssertEqual(R.decide(wheel(lines: 1), settings: on), .smooth(dx: 0, dy: R.pixelsPerLine))
    }

    func testDistanceFollowsLinesOrPixelsSpeedAndDirection() {
        XCTAssertEqual(R.decide(wheel(lines: -2), settings: on), .smooth(dx: 0, dy: -2 * R.pixelsPerLine))
        XCTAssertEqual(R.decide(wheel(x: 1), settings: on), .smooth(dx: R.pixelsPerLine, dy: 0), "⇧-wheel arrives on the second axis")
        XCTAssertEqual(R.decide(wheel(continuous: true, pointY: 9, pointX: -3), settings: on), .smooth(dx: -3, dy: 9),
                       "a pixel wheel keeps its own pixels")
        var fast = on; fast.speed = 150
        XCTAssertEqual(R.decide(wheel(lines: 1), settings: fast), .smooth(dx: 0, dy: R.pixelsPerLine * 1.5))
        var rev = on; rev.reverse = true
        XCTAssertEqual(R.decide(wheel(lines: 1), settings: rev), .smooth(dx: 0, dy: -R.pixelsPerLine))
    }

    func testOutOfRangeSettingsArePulledBackIn() {
        let s = R.Settings(enabled: true, speed: 9_000, smoothness: 1, reverse: false).clamped
        XCTAssertEqual(s.speed, R.speedRange.upperBound)
        XCTAssertEqual(s.smoothness, R.smoothnessRange.lowerBound)
        XCTAssertEqual(R.decide(wheel(lines: 1), settings: R.Settings(enabled: true, speed: -50)),
                       .smooth(dx: 0, dy: R.pixelsPerLine * Double(R.speedRange.lowerBound) / 100), "a negative speed never flips the wheel")
    }

    // MARK: The glide

    /// Run frames until idle; returns the posted pixels.
    func run(_ glide: inout R.Glide, dt: Double = R.framePeriod, smoothness: Int = R.defaultSmoothness, limit: Int = 2_000) -> [(Int32, Int32)] {
        var out: [(Int32, Int32)] = []
        var n = 0
        while !glide.isIdle && n < limit { out.append(glide.step(dt: dt, smoothnessMs: smoothness)); n += 1 }
        return out
    }

    func testAGlidePostsExactlyItsDistanceAndStops() {
        for (distance, smoothness) in [(40.0, 220), (37.5, 80), (-120.0, 600), (3.0, 220), (1_000.0, 300)] {
            var g = R.Glide(); g.add(dx: 0, dy: distance)
            let steps = run(&g, smoothness: smoothness)
            XCTAssertTrue(g.isIdle, "\(distance) must come to rest")
            XCTAssertEqual(steps.reduce(0) { $0 + Int($1.1) }, Int(distance.rounded()), "\(distance) @\(smoothness) ms")
            XCTAssertTrue(steps.allSatisfy { distance >= 0 ? $0.1 >= 0 : $0.1 <= 0 }, "never a pixel backwards")
            XCTAssertLessThan(Double(steps.count) * R.framePeriod, Double(smoothness) / 1000 * 4, "done within ~4× the smoothness")
        }
    }

    func testMostOfTheDistanceIsCoveredWithinTheSmoothness() {
        var g = R.Glide(); g.add(dx: 0, dy: 400)
        let frames = Int((Double(R.defaultSmoothness) / 1000 / R.framePeriod).rounded())
        var moved = 0
        for _ in 0..<frames { moved += Int(g.step(dt: R.framePeriod, smoothnessMs: R.defaultSmoothness).dy) }
        XCTAssertGreaterThan(moved, 360, "≥ 90 % within the smoothness (τ = smoothness / 3)")
        XCTAssertLessThan(moved, 400, "but not all of it at once — that would be no smoothing")
    }

    func testNotchesInARowAddUpAndTurningAroundDropsTheRest() {
        var g = R.Glide()
        g.add(dx: 0, dy: 40); _ = g.step(dt: R.framePeriod, smoothnessMs: 220)
        g.add(dx: 0, dy: 40)
        XCTAssertGreaterThan(g.y.remaining, 40, "a second notch adds to what is left")
        g.add(dx: 0, dy: -40)
        XCTAssertEqual(g.y.remaining, -40, "turning around drops the old direction")
        let steps = run(&g)
        XCTAssertTrue(steps.allSatisfy { $0.1 <= 0 })
    }

    func testAxesGlideIndependently() {
        var g = R.Glide(); g.add(dx: 80, dy: -40)
        let steps = run(&g)
        XCTAssertEqual(steps.reduce(0) { $0 + Int($1.0) }, 80)
        XCTAssertEqual(steps.reduce(0) { $0 + Int($1.1) }, -40)
    }

    func testALongFrameOrNoSmoothingStillLandsExactly() {
        var g = R.Glide(); g.add(dx: 0, dy: 50)
        XCTAssertEqual(g.step(dt: 5, smoothnessMs: 220).dy, 50, "a stalled run loop posts the rest in one go")
        XCTAssertTrue(g.isIdle)
        var z = R.Axis(); z.add(10)
        XCTAssertEqual(z.step(dt: R.framePeriod, tau: 0), 10)
    }

    // MARK: Other smoothers

    func testAnotherSmootherIsNamed() {
        XCTAssertEqual(R.conflict(running: ["com.apple.finder", "com.caldis.Mos"]), "Mos")
        XCTAssertNil(R.conflict(running: ["com.apple.finder"]))
    }

    func testLinearScrollingIgnoresSpinAcceleration() {
        let lin = R.Settings(enabled: true, speed: 100, smoothness: 220, reverse: false, linear: true)
        XCTAssertEqual(R.decide(wheel(lines: 5), settings: lin), .smooth(dx: 0, dy: R.pixelsPerLine))
        XCTAssertEqual(R.decide(wheel(continuous: true, pointY: -120), settings: lin), .smooth(dx: 0, dy: -R.pixelsPerLine))

        let fastRev = R.Settings(enabled: true, speed: 150, smoothness: 220, reverse: true, linear: true)
        XCTAssertEqual(R.decide(wheel(lines: 5), settings: fastRev), .smooth(dx: 0, dy: -R.pixelsPerLine * 1.5))
    }
}
