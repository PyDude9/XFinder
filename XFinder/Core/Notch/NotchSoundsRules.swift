import Foundation

/// Pure logic for Dynamic Island ambient sounds: noise synthesis, mix-gain limiting,
/// sleep-timer fade-out math, and lifecycle transition rules. Foundation-only so every
/// rule and DSP generator runs directly in `XFinderLogicTests` without audio hardware.
enum NotchSoundsRules {

    // MARK: - Channels

    enum NoiseKind: String, CaseIterable, Identifiable, Codable, Sendable {
        case white
        case pink
        case brown

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .white: return "waveform"
            case .pink: return "waveform.path"
            case .brown: return "water.waves"
            }
        }

        static let defaultVolume: Double = 0.5
    }

    struct ChannelState: Equatable, Sendable {
        var isActive: Bool
        var volume: Double

        init(isActive: Bool = false, volume: Double = NoiseKind.defaultVolume) {
            self.isActive = isActive
            self.volume = NotchSoundsRules.clampVolume(volume)
        }
    }

    struct MixGains: Equatable, Sendable {
        var white: Float
        var pink: Float
        var brown: Float

        static let zero = MixGains(white: 0, pink: 0, brown: 0)

        var sum: Float { white + pink + brown }
        var isSilent: Bool { white <= 0 && pink <= 0 && brown <= 0 }

        subscript(_ kind: NoiseKind) -> Float {
            switch kind {
            case .white: return white
            case .pink: return pink
            case .brown: return brown
            }
        }
    }

    // MARK: - Constants

    static let defaultFadeDuration: TimeInterval = 15
    /// Combined linear gain across all active channels never exceeds this ceiling before soft-limiting.
    static let maxMixGainSum: Float = 1.0
    /// Hard ceiling after soft-limiting so summed noise peaks never digitally clip.
    static let sampleCeiling: Float = 0.98
    /// Perceptual loudness taper exponent (smooth low-end control).
    static let volumeExponent: Double = 1.5
    /// Fade tick cadence (~20 Hz) only while actively fading out.
    static let fadeTickInterval: TimeInterval = 0.05
    /// Countdown tick cadence (1 Hz) while counting down before fade begins.
    static let countdownTickInterval: TimeInterval = 1.0

    static func defaultChannels() -> [NoiseKind: ChannelState] {
        var dict: [NoiseKind: ChannelState] = [:]
        for kind in NoiseKind.allCases {
            dict[kind] = ChannelState(isActive: false, volume: NoiseKind.defaultVolume)
        }
        return dict
    }

    static func clampVolume(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    static func clampGain(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// Computes per-channel linear gains with automatic mix-sum limiting and master fade scaling.
    /// When multiple channels are active at high volume, gains are proportionally scaled so their
    /// sum never exceeds `maxMixGainSum`, preventing runaway loudness and clipping.
    static func effectiveGains(
        channels: [NoiseKind: ChannelState],
        masterGain: Float = 1.0
    ) -> MixGains {
        let master = clampGain(masterGain)
        guard master > 0 else { return .zero }

        func rawGain(_ kind: NoiseKind) -> Float {
            guard let ch = channels[kind], ch.isActive else { return 0 }
            let v = clampVolume(ch.volume)
            guard v > 0 else { return 0 }
            return Float(pow(v, volumeExponent))
        }

        let w = rawGain(.white)
        let p = rawGain(.pink)
        let b = rawGain(.brown)
        let total = w + p + b
        guard total > 0 else { return .zero }

        let limitScale: Float = total > maxMixGainSum ? (maxMixGainSum / total) : 1.0
        let scale = limitScale * master
        return MixGains(white: w * scale, pink: p * scale, brown: b * scale)
    }

    /// Smooth saturating limiter guaranteeing `|output| <= sampleCeiling` and zero NaN/Inf.
    static func softLimit(_ sample: Float) -> Float {
        guard sample.isFinite else { return 0 }
        return tanhf(sample) * sampleCeiling
    }

    // MARK: - Sleep / Fade-Out Timer

    enum SleepPreset: Int, CaseIterable, Identifiable, Sendable {
        case off = 0
        case min15 = 15
        case min30 = 30
        case min60 = 60

        var id: Int { rawValue }
        var durationSeconds: TimeInterval { TimeInterval(rawValue * 60) }
    }

    enum FadePhase: Equatable, Sendable {
        case inactive
        case countingDown
        case fadingOut
        case finished
    }

    struct SleepTimer: Equatable, Sendable {
        let startedAt: Date
        let duration: TimeInterval
        let fadeDuration: TimeInterval

        init(startedAt: Date, duration: TimeInterval, fadeDuration: TimeInterval = NotchSoundsRules.defaultFadeDuration) {
            self.startedAt = startedAt
            self.duration = max(0, duration.isFinite ? duration : 0)
            let safeFade = max(0, fadeDuration.isFinite ? fadeDuration : 0)
            self.fadeDuration = min(safeFade, self.duration)
        }

        var endDate: Date { startedAt.addingTimeInterval(duration) }
        var fadeStartDate: Date { endDate.addingTimeInterval(-fadeDuration) }

        func remaining(at now: Date) -> TimeInterval {
            max(0, endDate.timeIntervalSince(now))
        }

        func phase(at now: Date) -> FadePhase {
            guard duration > 0 else { return .finished }
            let rem = endDate.timeIntervalSince(now)
            if rem <= 0 { return .finished }
            if fadeDuration > 0 && rem <= fadeDuration { return .fadingOut }
            return .countingDown
        }

        /// Equal-power / raised-cosine fade-out curve: smooth derivative at both ends (zero clicks).
        func fadeGain(at now: Date) -> Float {
            switch phase(at: now) {
            case .inactive, .countingDown:
                return 1.0
            case .finished:
                return 0.0
            case .fadingOut:
                guard fadeDuration > 0 else { return 0.0 }
                let u = min(max(remaining(at: now) / fadeDuration, 0), 1)
                let smooth = 0.5 * (1.0 - cos(Double.pi * u))
                return Float(smooth)
            }
        }

        /// Monospaced countdown string (`MM:SS`, ceiling seconds so `00:01` does not read `00:00` early).
        func label(at now: Date) -> String {
            let totalSeconds = Int(ceil(remaining(at: now)))
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }

        /// Next wake-up interval for one-shot scheduling; `nil` once finished (zero idle timer).
        func nextTickInterval(at now: Date) -> TimeInterval? {
            switch phase(at: now) {
            case .inactive, .finished:
                return nil
            case .fadingOut:
                return min(NotchSoundsRules.fadeTickInterval, max(0.01, remaining(at: now)))
            case .countingDown:
                let untilFade = fadeStartDate.timeIntervalSince(now)
                if untilFade > 0 && untilFade < NotchSoundsRules.countdownTickInterval {
                    return max(0.01, untilFade)
                }
                return NotchSoundsRules.countdownTickInterval
            }
        }
    }

    // MARK: - Lifecycle & Error Rules

    enum StopReason: Equatable, Sendable {
        case user
        case sleepTimerFinished
        case tabDisabled
        case systemSleep
        case outputDeviceLost
        case engineError
        case appWillTerminate
    }

    enum EngineError: Error, Equatable, Sendable {
        case noOutputDevice
        case engineStartFailed
    }

    enum OutputChangeDecision: Equatable, Sendable {
        case ignore
        case restart
        case stopDeviceLost
    }

    static func onOutputChange(isPlaying: Bool, hasOutputDevice: Bool) -> OutputChangeDecision {
        guard isPlaying else { return .ignore }
        return hasOutputDevice ? .restart : .stopDeviceLost
    }

    // MARK: - Pure Procedural DSP Generators (real-time safe, zero heap allocation)

    /// Fast deterministic PRNG (xorshift64*) for audio-thread noise synthesis.
    struct Xorshift64: Sendable {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func nextUInt64() -> UInt64 {
            var x = state
            x ^= x >> 12
            x ^= x << 25
            x ^= x >> 27
            state = x
            return x &* 2_685_821_657_736_338_717
        }

        /// Uniform sample in `[-1.0, 1.0]`.
        mutating func nextUnitFloat() -> Float {
            let bits = nextUInt64() >> 40 // 24 bits of precision
            let normalized = Float(bits) / Float(1 << 24) // [0, 1)
            return normalized * 2.0 - 1.0
        }
    }

    /// Flat-spectrum white noise with comfortable nominal headroom.
    struct WhiteNoiseGenerator: Sendable {
        private var prng: Xorshift64
        private static let nominalScale: Float = 0.35

        init(seed: UInt64 = 0x1111_2222_3333_4444) {
            self.prng = Xorshift64(seed: seed)
        }

        mutating func nextSample() -> Float {
            prng.nextUnitFloat() * Self.nominalScale
        }
    }

    /// Paul Kellet's refined 7-stage IIR pink noise filter (-3 dB/octave).
    struct PinkNoiseGenerator: Sendable {
        private var prng: Xorshift64
        private var b0: Float = 0
        private var b1: Float = 0
        private var b2: Float = 0
        private var b3: Float = 0
        private var b4: Float = 0
        private var b5: Float = 0
        private var b6: Float = 0
        private static let nominalScale: Float = 0.11

        init(seed: UInt64 = 0x5555_6666_7777_8888) {
            self.prng = Xorshift64(seed: seed)
        }

        mutating func nextSample() -> Float {
            let white = prng.nextUnitFloat()
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            return pink * Self.nominalScale
        }
    }

    /// Leaky-integrator brown (Brownian / red) noise (-6 dB/octave), bounded against DC drift.
    struct BrownNoiseGenerator: Sendable {
        private var prng: Xorshift64
        private var last: Float = 0
        private static let nominalScale: Float = 3.5

        init(seed: UInt64 = 0x9999_AAAA_BBBB_CCCC) {
            self.prng = Xorshift64(seed: seed)
        }

        mutating func nextSample() -> Float {
            let white = prng.nextUnitFloat()
            last = (last + 0.02 * white) / 1.02
            return last * Self.nominalScale
        }
    }

    /// Combined 3-channel procedural mixer with soft limiting.
    struct NoiseMixerDSP: Sendable {
        var white: WhiteNoiseGenerator
        var pink: PinkNoiseGenerator
        var brown: BrownNoiseGenerator

        init(
            whiteSeed: UInt64 = 0x1111_2222_3333_4444,
            pinkSeed: UInt64 = 0x5555_6666_7777_8888,
            brownSeed: UInt64 = 0x9999_AAAA_BBBB_CCCC
        ) {
            self.white = WhiteNoiseGenerator(seed: whiteSeed)
            self.pink = PinkNoiseGenerator(seed: pinkSeed)
            self.brown = BrownNoiseGenerator(seed: brownSeed)
        }

        mutating func renderSample(gains: MixGains) -> Float {
            guard !gains.isSilent else { return 0 }
            var acc: Float = 0
            if gains.white > 0 { acc += white.nextSample() * gains.white }
            if gains.pink > 0 { acc += pink.nextSample() * gains.pink }
            if gains.brown > 0 { acc += brown.nextSample() * gains.brown }
            return NotchSoundsRules.softLimit(acc)
        }
    }
}
