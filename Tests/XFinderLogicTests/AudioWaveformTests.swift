import XCTest

/// §3b #21 — numbers from the probe: music RMS 0.004–0.17, peaks to 0.52; silence is exact zeros.
final class AudioWaveformTests: XCTestCase {
    typealias W = AudioWaveform

    func testRMSOfKnownSignals() {
        XCTAssertEqual(W.rms([Float]()), 0)
        XCTAssertEqual(W.rms([Float](repeating: 0, count: 512)), 0)
        XCTAssertEqual(W.rms([0.5, -0.5, 0.5, -0.5]), 0.5, accuracy: 1e-6)
        let sine = (0..<4800).map { Float(sin(Double($0) * 2 * .pi / 48)) }
        XCTAssertEqual(W.rms(sine), 1 / Float(2).squareRoot(), accuracy: 1e-3, "a full-scale sine is 1/√2")
    }

    func testLevelIsADecibelScale() {
        XCTAssertEqual(W.level(rms: 0), 0)
        XCTAssertEqual(W.level(rms: 1), 1, accuracy: 1e-6)
        XCTAssertEqual(W.level(rms: 0.1), 0.6, accuracy: 1e-4, "−20 dB is 60 % of a −50…0 dB scale")
        XCTAssertGreaterThan(W.level(rms: 0.0038), 0.0, "the quietest measured music still moves the bar")
        XCTAssertEqual(W.level(rms: 0.000_01), 0, "below −50 dB is the floor")
        XCTAssertEqual(W.level(rms: .nan), 0)
        XCTAssertEqual(W.level(rms: 4), 1, "clipping never draws past the top")
    }

    func testMeterRisesFastFallsSlowAndKeepsItsLength() {
        var m = W.Meter()
        m.push(level: 1)
        let up = m.smoothed
        XCTAssertEqual(up, W.Meter.attack, accuracy: 1e-6)
        m.push(level: 0)
        XCTAssertGreaterThan(m.smoothed, up * 0.8, "a bar falls slowly")
        XCTAssertEqual(m.levels.count, W.bars)
        XCTAssertEqual(m.levels.last, m.smoothed, "newest last")
        for _ in 0..<200 { m.push(level: .infinity) }
        XCTAssertLessThanOrEqual(m.levels.max() ?? 0, 1)
        m.reset()
        XCTAssertEqual(m.levels, Array(repeating: 0, count: W.bars))
    }

    func testDigitalSilenceForTwoSecondsLooksDenied() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var w = W.SilenceWatch()
        XCTAssertFalse(w.looksDenied(now: t0.addingTimeInterval(10)), "no buffer at all means nothing is playing, not a denial")
        w.observe(rms: 0, at: t0)
        w.observe(rms: 0, at: t0.addingTimeInterval(1.9))
        XCTAssertFalse(w.looksDenied(now: t0.addingTimeInterval(1.9)))
        XCTAssertTrue(w.looksDenied(now: t0.addingTimeInterval(2.1)))
        w.observe(rms: 0.00001, at: t0.addingTimeInterval(2.2))
        XCTAssertFalse(w.looksDenied(now: t0.addingTimeInterval(9)), "any signal at all clears it")
    }

    /// The measured process table from 2026-10-13 (Chrome playing; Safari, OneNotch, AirDrop also have WebKit.GPU).
    private let measured: [W.AudioProcess] = [
        .init(object: 119, pid: 66580, responsiblePID: 66530, parentPID: 66530),   // Chrome audio helper (out = 1)
        .init(object: 120, pid: 66581, responsiblePID: 66530, parentPID: 66530),   // another Chrome helper
        .init(object: 121, pid: 66530, responsiblePID: 66530, parentPID: 1),       // Chrome itself (out = 0)
        .init(object: 125, pid: 52320, responsiblePID: 52320, parentPID: 1),       // Safari
        .init(object: 128, pid: 41172, responsiblePID: 52320, parentPID: 1),       // Safari's WebKit.GPU
        .init(object: 130, pid: 29956, responsiblePID: 29948, parentPID: 1),       // OneNotch's WebKit.GPU
        .init(object: 122, pid: 66787, responsiblePID: 66780, parentPID: 1),       // AirDrop's WebKit.GPU
    ]

    func testAPlayerIsTappedWithEveryProcessItIsResponsibleFor() {
        XCTAssertEqual(Set(W.playerProcesses(measured, player: 66530)), [119, 120, 121],
                       "Chrome's sound comes from its helper — tapping the browser alone delivers no buffers")
        XCTAssertEqual(Set(W.playerProcesses(measured, player: 52320)), [125, 128],
                       "Safari's WebKit.GPU is found by responsibility (its parent is launchd)")
        XCTAssertFalse(W.playerProcesses(measured, player: 52320).contains(130), "another app's WebKit.GPU is never mixed in")
        XCTAssertEqual(W.playerProcesses(measured, player: 4242), [], "a player with no audio object taps nothing")
    }

    func testParentPIDIsOnlyAFallbackWhenResponsibilityIsUnknown() {
        let noLookup = measured.map { W.AudioProcess(object: $0.object, pid: $0.pid, responsiblePID: nil, parentPID: $0.parentPID) }
        XCTAssertEqual(Set(W.playerProcesses(noLookup, player: 66530)), [119, 120, 121], "children still found by parent")
        let lying = [W.AudioProcess(object: 1, pid: 10, responsiblePID: 99, parentPID: 66530)]
        XCTAssertEqual(W.playerProcesses(lying, player: 66530), [], "a known responsible pid outranks the parent")
    }
}
