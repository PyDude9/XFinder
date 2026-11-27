import XCTest

final class NotchSoundsRulesTests: XCTestCase {

    // MARK: - Volume Clamping & Mix Gain Limiting

    func testClampVolumeHandlesBoundsAndNonFinite() {
        XCTAssertEqual(NotchSoundsRules.clampVolume(-0.5), 0)
        XCTAssertEqual(NotchSoundsRules.clampVolume(0.0), 0)
        XCTAssertEqual(NotchSoundsRules.clampVolume(0.42), 0.42, accuracy: 1e-9)
        XCTAssertEqual(NotchSoundsRules.clampVolume(1.5), 1)
        XCTAssertEqual(NotchSoundsRules.clampVolume(.nan), 0)
        XCTAssertEqual(NotchSoundsRules.clampVolume(.infinity), 0)
        XCTAssertEqual(NotchSoundsRules.clampVolume(-.infinity), 0)
    }

    func testEffectiveGainsLimitsCombinedSumAcrossMultipleChannels() {
        var channels = NotchSoundsRules.defaultChannels()
        channels[.white] = .init(isActive: true, volume: 1.0)
        channels[.pink] = .init(isActive: true, volume: 1.0)
        channels[.brown] = .init(isActive: true, volume: 1.0)

        let gains = NotchSoundsRules.effectiveGains(channels: channels, masterGain: 1.0)
        XCTAssertEqual(gains.sum, NotchSoundsRules.maxMixGainSum, accuracy: 1e-5)
        XCTAssertEqual(gains.white, gains.pink, accuracy: 1e-5)
        XCTAssertEqual(gains.pink, gains.brown, accuracy: 1e-5)
    }

    func testEffectiveGainsPreservesProportionalMixWhenLimited() {
        var channels = NotchSoundsRules.defaultChannels()
        channels[.white] = .init(isActive: true, volume: 1.0)
        channels[.pink] = .init(isActive: true, volume: 0.5)
        channels[.brown] = .init(isActive: false, volume: 1.0)

        let gains = NotchSoundsRules.effectiveGains(channels: channels, masterGain: 1.0)
        XCTAssertLessThanOrEqual(gains.sum, NotchSoundsRules.maxMixGainSum + 1e-5)
        XCTAssertEqual(gains.brown, 0)
        XCTAssertGreaterThan(gains.white, gains.pink)
        let expectedRatio = Float(pow(1.0, NotchSoundsRules.volumeExponent) / pow(0.5, NotchSoundsRules.volumeExponent))
        XCTAssertEqual(gains.white / gains.pink, expectedRatio, accuracy: 1e-4)
    }

    func testEffectiveGainsAppliesMasterGainAndSilencesZeroMaster() {
        var channels = NotchSoundsRules.defaultChannels()
        channels[.white] = .init(isActive: true, volume: 0.8)

        let full = NotchSoundsRules.effectiveGains(channels: channels, masterGain: 1.0)
        let half = NotchSoundsRules.effectiveGains(channels: channels, masterGain: 0.5)
        let zero = NotchSoundsRules.effectiveGains(channels: channels, masterGain: 0.0)

        XCTAssertEqual(half.white, full.white * 0.5, accuracy: 1e-5)
        XCTAssertTrue(zero.isSilent)
    }

    // MARK: - Soft Limiter & Procedural Noise DSP

    func testSoftLimiterBoundsExtremeAndInvalidSamples() {
        XCTAssertEqual(NotchSoundsRules.softLimit(0), 0)
        XCTAssertEqual(NotchSoundsRules.softLimit(.nan), 0)
        XCTAssertEqual(NotchSoundsRules.softLimit(.infinity), 0)
        XCTAssertEqual(NotchSoundsRules.softLimit(-.infinity), 0)
        XCTAssertLessThanOrEqual(abs(NotchSoundsRules.softLimit(100)), NotchSoundsRules.sampleCeiling)
        XCTAssertLessThanOrEqual(abs(NotchSoundsRules.softLimit(-100)), NotchSoundsRules.sampleCeiling)
    }

    func testProceduralNoiseGeneratorsProduceDistinctBoundedSignals() {
        var whiteGen = NotchSoundsRules.WhiteNoiseGenerator()
        var pinkGen = NotchSoundsRules.PinkNoiseGenerator()
        var brownGen = NotchSoundsRules.BrownNoiseGenerator()

        let count = 4096
        var whiteSamples = [Float]()
        var pinkSamples = [Float]()
        var brownSamples = [Float]()
        whiteSamples.reserveCapacity(count)
        pinkSamples.reserveCapacity(count)
        brownSamples.reserveCapacity(count)

        for _ in 0..<count {
            whiteSamples.append(whiteGen.nextSample())
            pinkSamples.append(pinkGen.nextSample())
            brownSamples.append(brownGen.nextSample())
        }

        // Non-silent and finite.
        for samples in [whiteSamples, pinkSamples, brownSamples] {
            XCTAssertTrue(samples.allSatisfy(\.isFinite))
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(count))
            XCTAssertGreaterThan(rms, 0.02)
        }

        // Spectral tilt check via lag-1 autocorrelation: brown > pink > white.
        func lag1Correlation(_ xs: [Float]) -> Float {
            var num: Float = 0
            var den: Float = 0
            for i in 1..<xs.count {
                num += xs[i] * xs[i - 1]
                den += xs[i] * xs[i]
            }
            return den > 0 ? num / den : 0
        }

        let rWhite = lag1Correlation(whiteSamples)
        let rPink = lag1Correlation(pinkSamples)
        let rBrown = lag1Correlation(brownSamples)
        XCTAssertLessThan(abs(rWhite), 0.1)
        XCTAssertGreaterThan(rPink, rWhite + 0.3)
        XCTAssertGreaterThan(rBrown, rPink)
    }

    func testNoiseMixerDSPStaysBoundedWithAllChannelsMaxed() {
        var channels = NotchSoundsRules.defaultChannels()
        for kind in NotchSoundsRules.NoiseKind.allCases {
            channels[kind] = .init(isActive: true, volume: 1.0)
        }
        let gains = NotchSoundsRules.effectiveGains(channels: channels, masterGain: 1.0)
        var dsp = NotchSoundsRules.NoiseMixerDSP()

        var peak: Float = 0
        for _ in 0..<8192 {
            let s = dsp.renderSample(gains: gains)
            XCTAssertTrue(s.isFinite)
            peak = max(peak, abs(s))
        }
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertLessThanOrEqual(peak, NotchSoundsRules.sampleCeiling)
        XCTAssertEqual(dsp.renderSample(gains: .zero), 0)
    }

    // MARK: - Sleep Timer & Fade Curve

    func testSleepTimerPhasesAndSmoothFadeCurve() {
        let start = Date(timeIntervalSince1970: 1_000)
        let timer = NotchSoundsRules.SleepTimer(startedAt: start, duration: 60, fadeDuration: 15)

        XCTAssertEqual(timer.phase(at: start), .countingDown)
        XCTAssertEqual(timer.fadeGain(at: start), 1.0, accuracy: 1e-6)
        XCTAssertEqual(timer.label(at: start), "01:00")

        let fadeStart = start.addingTimeInterval(45)
        XCTAssertEqual(timer.phase(at: fadeStart), .fadingOut)
        XCTAssertEqual(timer.fadeGain(at: fadeStart), 1.0, accuracy: 1e-5)

        let midFade = start.addingTimeInterval(52.5)
        XCTAssertEqual(timer.phase(at: midFade), .fadingOut)
        XCTAssertEqual(timer.fadeGain(at: midFade), 0.5, accuracy: 1e-4)

        let nearEnd = start.addingTimeInterval(59)
        XCTAssertEqual(timer.phase(at: nearEnd), .fadingOut)
        XCTAssertLessThan(timer.fadeGain(at: nearEnd), 0.1)
        XCTAssertGreaterThan(timer.fadeGain(at: nearEnd), 0.0)
        XCTAssertEqual(timer.label(at: nearEnd), "00:01")

        let end = start.addingTimeInterval(60)
        XCTAssertEqual(timer.phase(at: end), .finished)
        XCTAssertEqual(timer.fadeGain(at: end), 0.0, accuracy: 1e-6)
        XCTAssertNil(timer.nextTickInterval(at: end))
        XCTAssertEqual(timer.label(at: end), "00:00")
    }

    func testShortDurationClampsFadeDuration() {
        let start = Date(timeIntervalSince1970: 2_000)
        let timer = NotchSoundsRules.SleepTimer(startedAt: start, duration: 5, fadeDuration: 15)
        XCTAssertEqual(timer.fadeDuration, 5)
        XCTAssertEqual(timer.phase(at: start), .fadingOut)
        XCTAssertEqual(timer.fadeGain(at: start.addingTimeInterval(2.5)), 0.5, accuracy: 1e-4)
    }

    // MARK: - Output Change Decision

    func testOutputChangeDecisionTable() {
        XCTAssertEqual(NotchSoundsRules.onOutputChange(isPlaying: false, hasOutputDevice: true), .ignore)
        XCTAssertEqual(NotchSoundsRules.onOutputChange(isPlaying: false, hasOutputDevice: false), .ignore)
        XCTAssertEqual(NotchSoundsRules.onOutputChange(isPlaying: true, hasOutputDevice: true), .restart)
        XCTAssertEqual(NotchSoundsRules.onOutputChange(isPlaying: true, hasOutputDevice: false), .stopDeviceLost)
    }
}
