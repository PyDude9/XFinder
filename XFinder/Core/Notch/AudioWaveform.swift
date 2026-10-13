import Foundation

/// §3b #21 — the live waveform beside the playing track. Pure: from raw samples to the bar heights the view draws,
/// and the one honest signal available about the permission.
///
/// Measured 2026-10-13 with a probe app (CoreAudio process tap, macOS 27): a tap delivers NO buffers while nothing
/// plays (so a running tap costs nothing in silence), ~45 buffers/s while audio plays, and ~0.45 % CPU computing RMS;
/// the first IO start blocked ~40 s on the system's permission prompt; without the grant a GLOBAL tap delivers buffers
/// full of exact zeros rather than an error — there is no public preflight for this permission, so "playing, buffers
/// arriving, every sample zero for 2 s" is the only way to tell the user the waveform is probably not allowed.
enum AudioWaveform {

    static let bars = 24
    /// Levels below this are drawn as the floor; 0 dBFS is the top.
    static let floorDB: Float = -50

    /// Root mean square of interleaved float samples. Empty ⇒ 0.
    static func rms<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// RMS → 0…1 on a dB scale: −50 dB (and silence) → 0, 0 dBFS → 1. A linear scale would leave ordinary music
    /// (RMS 0.01–0.2, measured) as a flat line at the bottom.
    static func level(rms: Float) -> Float {
        guard rms.isFinite, rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db - floorDB) / -floorDB))
    }

    /// The bars: a ring of `bars` levels, newest last, smoothed so a bar rises fast and falls slowly (how meters read).
    struct Meter: Equatable {
        private(set) var levels: [Float] = Array(repeating: 0, count: AudioWaveform.bars)
        private(set) var smoothed: Float = 0
        static let attack: Float = 0.6
        static let release: Float = 0.15

        mutating func push(level: Float) {
            let l = min(1, max(0, level.isFinite ? level : 0))
            let k = l > smoothed ? Self.attack : Self.release
            smoothed += (l - smoothed) * k
            levels.removeFirst()
            levels.append(smoothed)
        }

        mutating func reset() { self = Meter() }
    }

    /// "Probably not allowed": the track has been playing for `grace` seconds, buffers arrived, and every one of them
    /// was exact digital silence. A real song is never exactly zero for two seconds; a quiet passage still has noise.
    struct SilenceWatch: Equatable {
        static let grace: TimeInterval = 2
        private(set) var firstBuffer: Date?
        private(set) var sawSignal = false

        mutating func observe(rms: Float, at t: Date) {
            if firstBuffer == nil { firstBuffer = t }
            if rms > 0 { sawSignal = true }
        }

        func looksDenied(now: Date) -> Bool {
            guard let first = firstBuffer, !sawSignal else { return false }
            return now.timeIntervalSince(first) >= Self.grace
        }

        mutating func reset() { self = SilenceWatch() }
    }
}
