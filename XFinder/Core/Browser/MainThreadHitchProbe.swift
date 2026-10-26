import Foundation

/// XF-T32 W0 — stub (builder `hitch`): Debug-only main-thread hitch probe. Contract §C.
@MainActor final class MainThreadHitchProbe {
    static let shared = MainThreadHitchProbe()
    private(set) var recent: [HitchRules.Hitch] = []
    var onHitch: ((HitchRules.Hitch) -> Void)?

    func start() {}
    func stop() {}
}
