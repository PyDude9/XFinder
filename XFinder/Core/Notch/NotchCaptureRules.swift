import Foundation
import Observation

/// Pure rules and session state machine for Dynamic Island Capture (`XF-ISLAND-CAPTURE`).
/// Keeps permission/enabled/Pro gating, hide-before-capture handoff tokens, rapid-click deduplication,
/// and Esc-cancellation recovery testable without AppKit or a live Island panel.
struct NotchCaptureAvailability: Equatable, Sendable {
    var isFeatureEnabled: Bool
    var isScreenRecordingGranted: Bool
    var allowsScrollingCapture: Bool

    static let allReady = NotchCaptureAvailability(
        isFeatureEnabled: true,
        isScreenRecordingGranted: true,
        allowsScrollingCapture: true
    )
}

enum NotchCaptureBlockReason: Equatable, Sendable {
    case featureDisabled
    case permissionDenied
    case proRequired
    case busy
}

enum NotchCaptureRules {
    /// All capture modes exposed by `CaptureController` / `CaptureMode`, in canonical order.
    static var supportedModes: [CaptureMode] { CaptureMode.allCases }

    /// Maximum recent captures displayed in the compact Dynamic Island strip.
    static let defaultRecentHistoryLimit = 6

    /// Safety timeout (seconds) for the Island-hide handoff callback so a missed callback never wedges controls.
    static let prepareTimeoutSeconds: TimeInterval = 1.5

    /// Short recovery window (seconds) after launching `/usr/sbin/screencapture` so silent Esc cancellation
    /// cannot leave buttons locked even if the user keeps the Island open or reopens it quickly.
    static let postLaunchRecoverySeconds: TimeInterval = 0.9

    /// `.color` uses `NSColorSampler` and does not require Screen Recording; every pixel-capture mode does.
    static func requiresScreenRecording(_ mode: CaptureMode) -> Bool {
        mode != .color
    }

    static func requiresPro(_ mode: CaptureMode) -> Bool {
        mode == .scrolling
    }

    static func blockReason(
        for mode: CaptureMode,
        availability: NotchCaptureAvailability,
        isBusy: Bool
    ) -> NotchCaptureBlockReason? {
        guard availability.isFeatureEnabled else { return .featureDisabled }
        guard !isBusy else { return .busy }
        if requiresPro(mode) && !availability.allowsScrollingCapture {
            return .proRequired
        }
        if requiresScreenRecording(mode) && !availability.isScreenRecordingGranted {
            return .permissionDenied
        }
        return nil
    }

    static func recentItems(
        from visibleHistory: [CaptureItem],
        limit: Int = defaultRecentHistoryLimit
    ) -> [CaptureItem] {
        guard limit > 0, !visibleHistory.isEmpty else { return [] }
        return Array(visibleHistory.prefix(limit))
    }
}

/// Deterministic state machine guarding the Island-hide -> capture launch sequence against
/// double-clicks, stale hide callbacks, mid-flight disables, and silent Esc cancellations.
enum NotchCaptureSessionMachine {
    enum Phase: Equatable, Sendable {
        case idle
        case preparing(mode: CaptureMode, token: UInt64)
        case capturing(mode: CaptureMode, token: UInt64)

        var activeMode: CaptureMode? {
            switch self {
            case .idle: return nil
            case .preparing(let mode, _), .capturing(let mode, _): return mode
            }
        }

        var token: UInt64? {
            switch self {
            case .idle: return nil
            case .preparing(_, let token), .capturing(_, let token): return token
            }
        }
    }

    struct State: Equatable, Sendable {
        var phase: Phase = .idle
        var nextToken: UInt64 = 1
        var lastCopiedItemID: String? = nil

        var isBusy: Bool { phase != .idle }

        var isPreparing: Bool {
            if case .preparing = phase { return true }
            return false
        }
    }

    enum Decision: Equatable, Sendable {
        case beginPrepare(mode: CaptureMode, token: UInt64)
        case launchCapture(mode: CaptureMode, token: UInt64)
        case blocked(NotchCaptureBlockReason)
        case noop
    }

    static func requestCapture(
        _ state: State,
        mode: CaptureMode,
        availability: NotchCaptureAvailability
    ) -> (State, Decision) {
        if let reason = NotchCaptureRules.blockReason(
            for: mode,
            availability: availability,
            isBusy: state.isBusy
        ) {
            return (state, .blocked(reason))
        }
        var next = state
        let token = next.nextToken
        next.nextToken &+= 1
        next.phase = .preparing(mode: mode, token: token)
        return (next, .beginPrepare(mode: mode, token: token))
    }

    /// Invoked when the coordinator confirms the Island panel is hidden and safe to capture behind.
    static func prepareCompleted(
        _ state: State,
        token: UInt64,
        availability: NotchCaptureAvailability
    ) -> (State, Decision) {
        guard case .preparing(let mode, let expectedToken) = state.phase,
              expectedToken == token else {
            return (state, .noop)
        }
        if let reason = NotchCaptureRules.blockReason(
            for: mode,
            availability: availability,
            isBusy: false
        ) {
            var aborted = state
            aborted.phase = .idle
            return (aborted, .blocked(reason))
        }
        var next = state
        next.phase = .capturing(mode: mode, token: token)
        return (next, .launchCapture(mode: mode, token: token))
    }

    /// Fires if the coordinator never invokes the hide completion within `prepareTimeoutSeconds`.
    static func prepareTimedOut(_ state: State, token: UInt64) -> State {
        guard case .preparing(_, let expectedToken) = state.phase,
              expectedToken == token else {
            return state
        }
        var next = state
        next.phase = .idle
        return next
    }

    /// Resets after capture completes, errors, or is cancelled silently (Esc).
    static func captureFinishedOrCancelled(_ state: State, token: UInt64? = nil) -> State {
        if let token, state.phase.token != token {
            return state
        }
        var next = state
        next.phase = .idle
        return next
    }

    /// Island disappearing is EXPECTED during `.preparing` (because we asked the Island to hide),
    /// so it must not abort the pending prepare token.
    static func islandDisappeared(_ state: State) -> State {
        state
    }

    /// Reopening the Island clears any lingering `.capturing` state (e.g. after Esc cancellation)
    /// so controls are immediately interactive again.
    static func islandReappeared(_ state: State) -> State {
        var next = state
        next.phase = .idle
        return next
    }

    static func tabDisabled(_ state: State) -> State {
        var next = state
        next.phase = .idle
        next.lastCopiedItemID = nil
        return next
    }

    static func recordCopied(_ state: State, itemID: String) -> State {
        var next = state
        next.lastCopiedItemID = itemID
        return next
    }

    static func clearCopied(_ state: State, itemID: String) -> State {
        guard state.lastCopiedItemID == itemID else { return state }
        var next = state
        next.lastCopiedItemID = nil
        return next
    }
}

/// Owns the in-flight capture handoff token and timers OUTSIDE the transient `NotchCapturePage` view.
///
/// Why this lives outside SwiftUI `@State`: `NotchSurfaceController.hideForCapture` synchronously
/// dismisses/collapses the Island before waiting ~50 ms and invoking its completion callback.
/// Unmounting `NotchCapturePage` during that window must NEVER drop the in-flight token or prevent
/// the requested capture from launching exactly once.
@MainActor
@Observable
final class NotchCaptureHandoffCoordinator {
    static let shared = NotchCaptureHandoffCoordinator()

    private(set) var session = NotchCaptureSessionMachine.State()

    private let prepareTimeoutNanoseconds: UInt64
    private let postLaunchRecoveryNanoseconds: UInt64
    private let copiedResetNanoseconds: UInt64

    private var prepareTimeoutTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var copiedResetTask: Task<Void, Never>?

    init(
        prepareTimeoutNanoseconds: UInt64 = UInt64(NotchCaptureRules.prepareTimeoutSeconds * 1_000_000_000),
        postLaunchRecoveryNanoseconds: UInt64 = UInt64(NotchCaptureRules.postLaunchRecoverySeconds * 1_000_000_000),
        copiedResetNanoseconds: UInt64 = 1_500_000_000
    ) {
        self.prepareTimeoutNanoseconds = prepareTimeoutNanoseconds
        self.postLaunchRecoveryNanoseconds = postLaunchRecoveryNanoseconds
        self.copiedResetNanoseconds = copiedResetNanoseconds
    }

    /// Requests a capture mode. Rejects duplicate taps while busy, preserves permission/Pro blocking
    /// without hiding the Island, and guarantees at-most-once launch after the Island hides even
    /// if the requesting view unmounts before `prepareToHide` completes.
    @discardableResult
    func requestCapture(
        mode: CaptureMode,
        availability: @escaping @MainActor () -> NotchCaptureAvailability,
        prepareToHide: (@escaping @MainActor () -> Void) -> Void,
        launchCapture: @escaping @MainActor (CaptureMode) -> Void,
        handleBlocked: @escaping @MainActor (CaptureMode, NotchCaptureBlockReason) -> Void = { _, _ in }
    ) -> NotchCaptureSessionMachine.Decision {
        let (next, decision) = NotchCaptureSessionMachine.requestCapture(
            session,
            mode: mode,
            availability: availability()
        )
        session = next

        switch decision {
        case .beginPrepare(_, let token):
            armPrepareTimeout(token: token)
            prepareToHide { [weak self] in
                guard let self else { return }
                self.completePrepare(
                    token: token,
                    availability: availability(),
                    launchCapture: launchCapture
                )
            }
        case .blocked(let reason) where reason == .permissionDenied || reason == .proRequired:
            handleBlocked(mode, reason)
        case .blocked, .launchCapture, .noop:
            break
        }
        return decision
    }

    /// Completes a pending prepare token and launches capture at most once.
    /// Rejects stale tokens (after cancellation, timeout, or duplicate callbacks) and re-checks availability.
    @discardableResult
    func completePrepare(
        token: UInt64,
        availability: NotchCaptureAvailability,
        launchCapture: @MainActor (CaptureMode) -> Void
    ) -> NotchCaptureSessionMachine.Decision {
        prepareTimeoutTask?.cancel()
        prepareTimeoutTask = nil

        let (next, decision) = NotchCaptureSessionMachine.prepareCompleted(
            session,
            token: token,
            availability: availability
        )
        session = next

        if case .launchCapture(let mode, let activeToken) = decision {
            launchCapture(mode)
            armPostLaunchRecovery(token: activeToken)
        }
        return decision
    }

    /// Explicitly cancels any in-flight prepare or capture session. Late hide callbacks carrying the
    /// cancelled token are guaranteed to be rejected as `.noop`.
    func cancelInFlight() {
        prepareTimeoutTask?.cancel()
        prepareTimeoutTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        session = NotchCaptureSessionMachine.captureFinishedOrCancelled(session)
    }

    /// View `onAppear`: clears lingering post-launch state so controls are immediately interactive.
    func handleIslandReappeared() {
        cancelTimers()
        session = NotchCaptureSessionMachine.islandReappeared(session)
    }

    /// View `onDisappear`: preserves an in-flight `.preparing` token and its timeout so an expected
    /// hide-before-capture unmount still delivers the capture exactly once.
    func handleIslandDisappeared() {
        session = NotchCaptureSessionMachine.islandDisappeared(session)
        if !session.isPreparing {
            cancelTimers()
        }
    }

    /// Called when `CaptureController` records a new capture item or error.
    func handleCaptureOutcomeObserved() {
        recoveryTask?.cancel()
        recoveryTask = nil
        session = NotchCaptureSessionMachine.captureFinishedOrCancelled(session)
    }

    /// Called when the Capture tab is disabled.
    func handleTabDisabled() {
        cancelTimers()
        session = NotchCaptureSessionMachine.tabDisabled(session)
    }

    /// Records a brief copy confirmation badge for a recent capture item.
    func recordCopied(itemID: String) {
        session = NotchCaptureSessionMachine.recordCopied(session, itemID: itemID)
        copiedResetTask?.cancel()
        let delay = copiedResetNanoseconds
        copiedResetTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.session = NotchCaptureSessionMachine.clearCopied(self.session, itemID: itemID)
        }
    }

    // MARK: - Timers

    private func armPrepareTimeout(token: UInt64) {
        prepareTimeoutTask?.cancel()
        let delay = prepareTimeoutNanoseconds
        prepareTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.session = NotchCaptureSessionMachine.prepareTimedOut(self.session, token: token)
        }
    }

    private func armPostLaunchRecovery(token: UInt64) {
        recoveryTask?.cancel()
        let delay = postLaunchRecoveryNanoseconds
        recoveryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.session = NotchCaptureSessionMachine.captureFinishedOrCancelled(self.session, token: token)
        }
    }

    private func cancelTimers() {
        prepareTimeoutTask?.cancel()
        prepareTimeoutTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        copiedResetTask?.cancel()
        copiedResetTask = nil
    }
}
