import Foundation

/// XF-T28 cluster B — STUB (contract: docs/specs/XF-T28-ui-contract.md).
@MainActor final class EjectGuard {
    static let shared = EjectGuard()
    func setBusyVolumes(_ mountPoints: Set<String>) {}
}
