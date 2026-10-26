import Foundation

/// XF-T32 W0 — stub (builder `pressure`): memory-pressure relief rules. Contract §D.
enum PressureRules {
    enum Level: Equatable, Sendable { case warning, critical }

    struct Plan: Equatable {
        let keepFraction: Double
        let dropIdleSessions: Bool
        let dropPathIcons: Bool
    }

    static func plan(for level: Level) -> Plan { Plan(keepFraction: 1, dropIdleSessions: false, dropPathIcons: false) }
    static func level(fromDispatchMask raw: UInt) -> Level? { nil }
}
