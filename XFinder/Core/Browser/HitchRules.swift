import Foundation

/// XF-T32 W0 — stub (builder `hitch`): main-thread hitch rules. Contract §C.
enum HitchRules {
    static let pingInterval: TimeInterval = 0.1
    static let threshold: TimeInterval = 0.25
    static let maxSamplesPerHour: Int = 3

    struct Hitch: Equatable, Sendable {
        let at: Date
        let latency: TimeInterval
    }

    static func isHitch(latency: TimeInterval) -> Bool { false }
    static func shouldSample(now: Date, previousSamples: [Date]) -> Bool { false }
    static func pruned(_ hitches: [Hitch], keep: Int = 50) -> [Hitch] { hitches }
}
