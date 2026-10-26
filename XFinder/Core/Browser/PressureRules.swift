import Foundation

/// XF-T32 W0 — memory-pressure relief rules (pure, Foundation-only). Contract §D.
///
/// `warning`  ⇒ keep 50 % of image/thumbnail caches, drop listing sessions nobody subscribes to.
/// `critical` ⇒ keep 0 %, drop idle sessions, and clear the per-path icon cache.
enum PressureRules {
    enum Level: Equatable, Sendable { case warning, critical }

    struct Plan: Equatable {
        let keepFraction: Double
        let dropIdleSessions: Bool
        let dropPathIcons: Bool
    }

    /// Raw bits of `DispatchSource.MemoryPressureEvent` (kept literal so this file stays Dispatch-free).
    enum DispatchBit {
        static let normal: UInt = 0x1
        static let warning: UInt = 0x2
        static let critical: UInt = 0x4
    }

    static let warningPlan: Plan = Plan(keepFraction: 0.5, dropIdleSessions: true, dropPathIcons: false)
    static let criticalPlan: Plan = Plan(keepFraction: 0, dropIdleSessions: true, dropPathIcons: true)

    static func plan(for level: Level) -> Plan {
        switch level {
        case .warning: return warningPlan
        case .critical: return criticalPlan
        }
    }

    /// Maps a memory-pressure event mask to a level; the most severe bit wins.
    /// `.normal` alone, zero, or unknown bits ⇒ nil (nothing to relieve).
    static func level(fromDispatchMask raw: UInt) -> Level? {
        if raw & DispatchBit.critical != 0 { return .critical }
        if raw & DispatchBit.warning != 0 { return .warning }
        return nil
    }

    /// Number of entries to keep when a cache of `count` entries applies `plan`.
    /// Rounds down (a 1-entry cache under `warning` keeps 0); clamps NaN/negative/over-1 fractions.
    static func keepCount(of count: Int, plan: Plan) -> Int {
        guard count > 0 else { return 0 }
        let fraction: Double = plan.keepFraction.isFinite ? min(max(plan.keepFraction, 0), 1) : 0
        if fraction >= 1 { return count }  // Double(Int.max) rounds up past Int.max — never convert it back.
        let kept: Int = Int((Double(count) * fraction).rounded(.down))
        return min(max(kept, 0), count)
    }
}
