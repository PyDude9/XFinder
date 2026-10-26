import Foundation

/// XF-T32 W0 (builder `hitch`): main-thread hitch rules. Contract §C. Pure — symlinked into the test package.
enum HitchRules {
    /// How often the background thread pings the main queue.
    static let pingInterval: TimeInterval = 0.1
    /// A ping answered later than this is a hitch.
    static let threshold: TimeInterval = 0.25
    /// At most this many `sample(1)` captures in any rolling hour.
    static let maxSamplesPerHour: Int = 3
    /// A single latency above this is a sleep/wake (or debugger pause), not a hitch.
    static let sleepWakeCutoff: TimeInterval = 30
    /// The rolling window `maxSamplesPerHour` counts over.
    static let sampleWindow: TimeInterval = 3600

    struct Hitch: Equatable, Sendable {
        let at: Date
        let latency: TimeInterval
    }

    /// `threshold ≤ latency ≤ sleepWakeCutoff`; NaN, infinite and negative latencies are never hitches.
    static func isHitch(latency: TimeInterval) -> Bool {
        guard latency.isFinite else { return false }
        return latency >= threshold && latency <= sleepWakeCutoff
    }

    /// Whether a new `sample` may run now, given the dates of earlier samples.
    /// A sample counts when it lies within one window of `now` on either side: a sample "in the future"
    /// (clock moved back a little) still counts, but one more than a window away in either direction
    /// (clock moved by days) is ignored so a clock change can never block sampling forever.
    static func shouldSample(now: Date, previousSamples: [Date]) -> Bool {
        guard maxSamplesPerHour > 0 else { return false }
        let recentCount: Int = previousSamples.reduce(0) { (count: Int, date: Date) -> Int in
            isInsideWindow(date, of: now) ? count + 1 : count
        }
        return recentCount < maxSamplesPerHour
    }

    /// The `keep` most recent hitches, oldest first. `keep ≤ 0` ⇒ empty.
    static func pruned(_ hitches: [Hitch], keep: Int = 50) -> [Hitch] {
        guard keep > 0 else { return [] }
        let chronological: [Hitch] = hitches.enumerated()
            .sorted { (lhs: (offset: Int, element: Hitch), rhs: (offset: Int, element: Hitch)) -> Bool in
                lhs.element.at == rhs.element.at ? lhs.offset < rhs.offset : lhs.element.at < rhs.element.at
            }
            .map { (pair: (offset: Int, element: Hitch)) -> Hitch in pair.element }
        return Array(chronological.suffix(keep))
    }

    private static func isInsideWindow(_ date: Date, of now: Date) -> Bool {
        let distance: TimeInterval = abs(now.timeIntervalSince(date))
        return distance.isFinite && distance < sampleWindow
    }
}
