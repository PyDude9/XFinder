import Foundation
import IOKit.pwr_mgt

/// Prevents idle sleep/screensaver for a bounded duration. Public API only:
/// `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep)`.
@MainActor
@Observable
final class CaffeineController {
    static let shared = CaffeineController()

    var isActive = false
    var remainingSeconds: Int? = nil

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    private init() {}

    enum Duration {
        case indefinite
        case minutes(Int)
        var seconds: Int? {
            switch self {
            case .indefinite: return nil
            case .minutes(let m): return m * 60
            }
        }
    }

    func activate(duration: Duration) {
        if isActive { deactivate() }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "XFinder: Chống ngủ" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isActive = true
        if let s = duration.seconds {
            remainingSeconds = s
            scheduleCountdown(total: s)
        } else {
            remainingSeconds = nil
        }
    }

    func deactivate() {
        if assertionID != 0 { IOPMAssertionRelease(assertionID); assertionID = 0 }
        timer?.invalidate(); timer = nil
        isActive = false
        remainingSeconds = nil
    }

    private func scheduleCountdown(total: Int) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let r = self.remainingSeconds {
                    if r <= 1 { self.deactivate() }
                    else { self.remainingSeconds = r - 1 }
                }
            }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    // No `deinit` release: this is a `shared` singleton that lives for the
    // whole process, so the deinit never runs — and touching main-actor state
    // from a nonisolated deinit is an error under strict concurrency anyway.
    // macOS drops the power assertion automatically when the process exits.
}
