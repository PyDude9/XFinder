import XCTest

final class NotchCaptureRulesTests: XCTestCase {

    // MARK: - 1. Supported Modes & Gating

    func testSupportedModesMatchAllCaptureModesAndPermissionRequirements() {
        XCTAssertEqual(NotchCaptureRules.supportedModes, CaptureMode.allCases)
        XCTAssertFalse(NotchCaptureRules.requiresScreenRecording(.color))
        for mode in CaptureMode.allCases where mode != .color {
            XCTAssertTrue(NotchCaptureRules.requiresScreenRecording(mode), "\(mode) must require Screen Recording")
        }
        XCTAssertTrue(NotchCaptureRules.requiresPro(.scrolling))
        XCTAssertFalse(NotchCaptureRules.requiresPro(.area))
    }

    // MARK: - 2. Permission Denied

    func testPermissionDeniedBlocksScreenRecordingModesWithoutEnteringPrepare() {
        let denied = NotchCaptureAvailability(
            isFeatureEnabled: true,
            isScreenRecordingGranted: false,
            allowsScrollingCapture: true
        )
        let state = NotchCaptureSessionMachine.State()

        for mode in CaptureMode.allCases where mode != .color {
            let (next, decision) = NotchCaptureSessionMachine.requestCapture(state, mode: mode, availability: denied)
            XCTAssertEqual(decision, .blocked(.permissionDenied))
            XCTAssertEqual(next.phase, .idle, "Island must not enter prepare/hide when permission is denied")
        }

        // Color picker does not need Screen Recording
        let (colorNext, colorDecision) = NotchCaptureSessionMachine.requestCapture(state, mode: .color, availability: denied)
        XCTAssertEqual(colorDecision, .beginPrepare(mode: .color, token: 1))
        XCTAssertEqual(colorNext.phase, .preparing(mode: .color, token: 1))
    }

    // MARK: - 3. Feature Disabled

    func testFeatureDisabledBlocksEveryModeIncludingColor() {
        let disabled = NotchCaptureAvailability(
            isFeatureEnabled: false,
            isScreenRecordingGranted: true,
            allowsScrollingCapture: true
        )
        let state = NotchCaptureSessionMachine.State()

        for mode in CaptureMode.allCases {
            let (next, decision) = NotchCaptureSessionMachine.requestCapture(state, mode: mode, availability: disabled)
            XCTAssertEqual(decision, .blocked(.featureDisabled))
            XCTAssertEqual(next.phase, .idle)
        }
    }

    // MARK: - 4. Pro Gating

    func testScrollingModeBlockedWhenProNotUnlocked() {
        let freeTier = NotchCaptureAvailability(
            isFeatureEnabled: true,
            isScreenRecordingGranted: true,
            allowsScrollingCapture: false
        )
        let (next, decision) = NotchCaptureSessionMachine.requestCapture(
            NotchCaptureSessionMachine.State(),
            mode: .scrolling,
            availability: freeTier
        )
        XCTAssertEqual(decision, .blocked(.proRequired))
        XCTAssertEqual(next.phase, .idle)
    }

    // MARK: - 5. Empty & Capped History

    func testEmptyAndCappedRecentHistory() {
        XCTAssertTrue(NotchCaptureRules.recentItems(from: []).isEmpty)

        let items = (0..<10).map { i in
            CaptureItem(
                url: URL(fileURLWithPath: "/tmp/cap-\(i).png"),
                date: Date(timeIntervalSince1970: Double(1000 - i)),
                pixelWidth: 800,
                pixelHeight: 600
            )
        }
        let recent = NotchCaptureRules.recentItems(from: items, limit: 6)
        XCTAssertEqual(recent.count, 6)
        XCTAssertEqual(recent.first?.id, "/tmp/cap-0.png")
        XCTAssertEqual(recent.last?.id, "/tmp/cap-5.png")
        XCTAssertTrue(NotchCaptureRules.recentItems(from: items, limit: 0).isEmpty)
    }

    // MARK: - 6. Consecutive Clicks & Hide-Before-Capture Handoff

    func testConsecutiveClicksDuringPrepareAndCaptureAreBlocked() {
        var state = NotchCaptureSessionMachine.State()

        let (s1, d1) = NotchCaptureSessionMachine.requestCapture(state, mode: .area, availability: .allReady)
        XCTAssertEqual(d1, .beginPrepare(mode: .area, token: 1))
        state = s1

        // Second click while waiting for Island to hide is ignored
        let (s2, d2) = NotchCaptureSessionMachine.requestCapture(state, mode: .fullscreen, availability: .allReady)
        XCTAssertEqual(d2, .blocked(.busy))
        XCTAssertEqual(s2.phase, .preparing(mode: .area, token: 1))

        // Island disappears because we asked it to hide — must NOT cancel `.preparing`
        state = NotchCaptureSessionMachine.islandDisappeared(state)
        XCTAssertEqual(state.phase, .preparing(mode: .area, token: 1))

        // Coordinator invokes hide completion -> launches capture
        let (s3, d3) = NotchCaptureSessionMachine.prepareCompleted(state, token: 1, availability: .allReady)
        XCTAssertEqual(d3, .launchCapture(mode: .area, token: 1))
        XCTAssertEqual(s3.phase, .capturing(mode: .area, token: 1))
        state = s3

        // Duplicate completion callback with same token is a no-op
        let (sDup, dDup) = NotchCaptureSessionMachine.prepareCompleted(state, token: 1, availability: .allReady)
        XCTAssertEqual(dDup, .noop)
        XCTAssertEqual(sDup.phase, .capturing(mode: .area, token: 1))

        // Click while capturing is blocked
        let (_, dBusy) = NotchCaptureSessionMachine.requestCapture(state, mode: .window, availability: .allReady)
        XCTAssertEqual(dBusy, .blocked(.busy))
    }

    // MARK: - 7. Cancelled Capture & Timeout Recovery

    func testCancelledCaptureAndTimeoutRecoverCleanlyToIdle() {
        var state = NotchCaptureSessionMachine.State()

        // Timeout during prepare recovers to idle and rejects late callback
        let (sPrep, _) = NotchCaptureSessionMachine.requestCapture(state, mode: .area, availability: .allReady)
        state = NotchCaptureSessionMachine.prepareTimedOut(sPrep, token: 1)
        XCTAssertEqual(state.phase, .idle)

        let (sLate, dLate) = NotchCaptureSessionMachine.prepareCompleted(state, token: 1, availability: .allReady)
        XCTAssertEqual(dLate, .noop)
        XCTAssertEqual(sLate.phase, .idle)

        // Start capture -> user presses Esc -> Island reopens -> immediately usable
        let (s2, _) = NotchCaptureSessionMachine.requestCapture(state, mode: .area, availability: .allReady)
        let (s3, d3) = NotchCaptureSessionMachine.prepareCompleted(s2, token: 2, availability: .allReady)
        XCTAssertEqual(d3, .launchCapture(mode: .area, token: 2))

        let recovered = NotchCaptureSessionMachine.islandReappeared(s3)
        XCTAssertEqual(recovered.phase, .idle)

        let (_, dAgain) = NotchCaptureSessionMachine.requestCapture(recovered, mode: .window, availability: .allReady)
        XCTAssertEqual(dAgain, .beginPrepare(mode: .window, token: 3))
    }

    // MARK: - 8. Mid-Prepare Disable / Permission Revocation

    func testFeatureDisabledMidPrepareAbortsWithoutLaunchingCapture() {
        let (sPrep, _) = NotchCaptureSessionMachine.requestCapture(
            NotchCaptureSessionMachine.State(),
            mode: .fullscreen,
            availability: .allReady
        )
        let disabled = NotchCaptureAvailability(
            isFeatureEnabled: false,
            isScreenRecordingGranted: true,
            allowsScrollingCapture: true
        )
        let (sDone, decision) = NotchCaptureSessionMachine.prepareCompleted(sPrep, token: 1, availability: disabled)
        XCTAssertEqual(decision, .blocked(.featureDisabled))
        XCTAssertEqual(sDone.phase, .idle)
    }

    func testCopyBadgeTracksAndClearsPerItemID() {
        var state = NotchCaptureSessionMachine.State()
        state = NotchCaptureSessionMachine.recordCopied(state, itemID: "/tmp/a.png")
        XCTAssertEqual(state.lastCopiedItemID, "/tmp/a.png")
        // Clearing a different item ID does not clear the newer badge
        state = NotchCaptureSessionMachine.clearCopied(state, itemID: "/tmp/old.png")
        XCTAssertEqual(state.lastCopiedItemID, "/tmp/a.png")
        state = NotchCaptureSessionMachine.clearCopied(state, itemID: "/tmp/a.png")
        XCTAssertNil(state.lastCopiedItemID)
    }

    // MARK: - 9. Coordinator-Owned Handoff (Unmount, Duplicate Taps, Cancellation, Retry, Permissions)

    @MainActor
    func testHandoffSurvivesViewUnmountAndLaunchesExactlyOnce() {
        let coordinator = NotchCaptureHandoffCoordinator(
            prepareTimeoutNanoseconds: 5_000_000_000,
            postLaunchRecoveryNanoseconds: 5_000_000_000
        )

        var pendingHideCompletion: (@MainActor () -> Void)?
        var launchedModes: [CaptureMode] = []

        // First tap enters `.preparing` and triggers hide-before-capture.
        let d1 = coordinator.requestCapture(
            mode: .area,
            availability: { .allReady },
            prepareToHide: { completion in
                pendingHideCompletion = completion
            },
            launchCapture: { mode in
                launchedModes.append(mode)
            }
        )
        XCTAssertEqual(d1, .beginPrepare(mode: .area, token: 1))
        XCTAssertTrue(coordinator.session.isPreparing)

        // Repeated tap while hiding is rejected and does NOT overwrite the hide callback.
        let d2 = coordinator.requestCapture(
            mode: .fullscreen,
            availability: { .allReady },
            prepareToHide: { _ in
                XCTFail("Duplicate tap must not re-invoke prepareToHide")
            },
            launchCapture: { mode in
                launchedModes.append(mode)
            }
        )
        XCTAssertEqual(d2, .blocked(.busy))

        // Simulate `NotchCapturePage` unmounting when `dismiss()` collapses the Island.
        coordinator.handleIslandDisappeared()
        XCTAssertTrue(coordinator.session.isPreparing, "Unmounting view must preserve in-flight token")

        // Hide completion fires after view unmount -> launches capture exactly once.
        pendingHideCompletion?()
        XCTAssertEqual(launchedModes, [.area])
        XCTAssertEqual(coordinator.session.phase, .capturing(mode: .area, token: 1))

        // Duplicate invocation of the same hide completion is ignored.
        pendingHideCompletion?()
        XCTAssertEqual(launchedModes, [.area])
    }

    @MainActor
    func testCancelledHandoffRejectsLateHideCallbackAndAllowsRetry() {
        let coordinator = NotchCaptureHandoffCoordinator(
            prepareTimeoutNanoseconds: 5_000_000_000,
            postLaunchRecoveryNanoseconds: 5_000_000_000
        )

        var staleHideCompletion: (@MainActor () -> Void)?
        var launchedModes: [CaptureMode] = []

        _ = coordinator.requestCapture(
            mode: .window,
            availability: { .allReady },
            prepareToHide: { completion in staleHideCompletion = completion },
            launchCapture: { launchedModes.append($0) }
        )

        // Cancel in-flight request before hide completes.
        coordinator.cancelInFlight()
        XCTAssertEqual(coordinator.session.phase, .idle)

        // Late callback carrying the cancelled token must be rejected.
        staleHideCompletion?()
        XCTAssertTrue(launchedModes.isEmpty)
        XCTAssertEqual(coordinator.session.phase, .idle)

        // Retry works cleanly with a new token.
        var retryCompletion: (@MainActor () -> Void)?
        let retryDecision = coordinator.requestCapture(
            mode: .fullscreen,
            availability: { .allReady },
            prepareToHide: { completion in retryCompletion = completion },
            launchCapture: { launchedModes.append($0) }
        )
        XCTAssertEqual(retryDecision, .beginPrepare(mode: .fullscreen, token: 2))

        // Even if the older stale callback fires again now, it must NOT launch token 2.
        staleHideCompletion?()
        XCTAssertTrue(launchedModes.isEmpty)

        retryCompletion?()
        XCTAssertEqual(launchedModes, [.fullscreen])
    }

    @MainActor
    func testHandoffPreservesPermissionAndProBlockingWithoutHidingIsland() {
        let coordinator = NotchCaptureHandoffCoordinator()
        var hideCount = 0
        var blockedReasons: [(CaptureMode, NotchCaptureBlockReason)] = []

        let denied = NotchCaptureAvailability(
            isFeatureEnabled: true,
            isScreenRecordingGranted: false,
            allowsScrollingCapture: false
        )

        let dPerm = coordinator.requestCapture(
            mode: .area,
            availability: { denied },
            prepareToHide: { _ in hideCount += 1 },
            launchCapture: { _ in XCTFail("Must not launch when permission denied") },
            handleBlocked: { mode, reason in blockedReasons.append((mode, reason)) }
        )
        XCTAssertEqual(dPerm, .blocked(.permissionDenied))

        let dPro = coordinator.requestCapture(
            mode: .scrolling,
            availability: { denied },
            prepareToHide: { _ in hideCount += 1 },
            launchCapture: { _ in XCTFail("Must not launch when Pro required") },
            handleBlocked: { mode, reason in blockedReasons.append((mode, reason)) }
        )
        XCTAssertEqual(dPro, .blocked(.proRequired))

        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(blockedReasons.count, 2)
        XCTAssertEqual(blockedReasons[0].0, .area)
        XCTAssertEqual(blockedReasons[0].1, .permissionDenied)
        XCTAssertEqual(blockedReasons[1].0, .scrolling)
        XCTAssertEqual(blockedReasons[1].1, .proRequired)
        XCTAssertEqual(coordinator.session.phase, .idle)
    }
}
