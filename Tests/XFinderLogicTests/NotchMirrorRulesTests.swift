import XCTest

final class NotchMirrorRulesTests: XCTestCase {

    // MARK: - Permission gating on appear vs explicit start

    func testActivateNeverRequestsPermissionOrStartsCamera() {
        var machine = NotchMirrorStateMachine()
        let effect = machine.activate()
        XCTAssertEqual(effect, .none)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(machine.isPageActive)
    }

    func testExplicitStartWithNotDeterminedRequestsPermission() {
        var machine = NotchMirrorStateMachine()
        _ = machine.activate()

        let effect = machine.start(hasUsageDescription: true, permission: .notDetermined)
        XCTAssertEqual(effect, .requestPermission(token: 1))
        XCTAssertEqual(machine.state, .requesting)
        XCTAssertTrue(machine.state.isBusy)
        XCTAssertFalse(machine.state.canStart)
        XCTAssertTrue(machine.state.canStop)
    }

    func testExplicitStartWithAuthorizedStartsCaptureImmediately() {
        var machine = NotchMirrorStateMachine()
        _ = machine.activate()

        let effect = machine.start(hasUsageDescription: true, permission: .authorized)
        XCTAssertEqual(effect, .startCapture(token: 1))
        XCTAssertEqual(machine.state, .starting)

        let afterStart = machine.resolveStart(
            token: 1,
            outcome: .started(deviceID: "cam-1", deviceName: "FaceTime HD Camera")
        )
        XCTAssertEqual(afterStart, .none)
        XCTAssertEqual(machine.state, .running)
        XCTAssertEqual(machine.activeDeviceID, "cam-1")
        XCTAssertEqual(machine.activeDeviceName, "FaceTime HD Camera")
        XCTAssertTrue(machine.state.isPreviewVisible)
        XCTAssertTrue(machine.state.canStop)
        XCTAssertFalse(machine.state.canStart)
    }

    func testMissingUsageDescriptionEntersMisconfiguredWithoutPrompting() {
        var machine = NotchMirrorStateMachine()
        _ = machine.activate()

        let effect = machine.start(hasUsageDescription: false, permission: .notDetermined)
        XCTAssertEqual(effect, .none)
        XCTAssertEqual(machine.state, .misconfigured)
        XCTAssertNil(machine.state.primaryActionTitleKey)
    }

    // MARK: - Denial, restriction, unavailable, failed

    func testDeniedPermissionOffersSettingsAndDoesNotStartCapture() {
        var machine = NotchMirrorStateMachine()
        let effect = machine.start(hasUsageDescription: true, permission: .denied)
        XCTAssertEqual(effect, .none)
        XCTAssertEqual(machine.state, .denied)
        XCTAssertTrue(machine.state.showsOpenSettings)
        XCTAssertEqual(machine.state.primaryActionTitleKey, "Thử lại")
    }

    func testPermissionPromptDeniedTransitionsToDenied() {
        var machine = NotchMirrorStateMachine()
        XCTAssertEqual(
            machine.start(hasUsageDescription: true, permission: .notDetermined),
            .requestPermission(token: 1)
        )

        let next = machine.resolvePermission(token: 1, granted: false, statusAfterRequest: .denied)
        XCTAssertEqual(next, .none)
        XCTAssertEqual(machine.state, .denied)
        XCTAssertTrue(machine.state.showsOpenSettings)
    }

    func testRestrictedPermissionEntersRestrictedWithoutStartCTA() {
        var machine = NotchMirrorStateMachine()
        let effect = machine.start(hasUsageDescription: true, permission: .restricted)
        XCTAssertEqual(effect, .none)
        XCTAssertEqual(machine.state, .restricted)
        XCTAssertFalse(machine.state.showsOpenSettings)
        XCTAssertFalse(machine.state.canStart)
        XCTAssertNil(machine.state.primaryActionTitleKey)
    }

    func testUnavailableDeviceTransitionsToUnavailableWithRetry() {
        var machine = NotchMirrorStateMachine()
        XCTAssertEqual(
            machine.start(hasUsageDescription: true, permission: .authorized),
            .startCapture(token: 1)
        )

        let next = machine.resolveStart(token: 1, outcome: .unavailable)
        XCTAssertEqual(next, .none)
        XCTAssertEqual(machine.state, .unavailable)
        XCTAssertTrue(machine.state.canStart)
        XCTAssertEqual(machine.state.primaryActionTitleKey, "Thử lại")
    }

    func testCaptureFailureTransitionsToFailedAndAllowsRetry() {
        var machine = NotchMirrorStateMachine()
        XCTAssertEqual(
            machine.start(hasUsageDescription: true, permission: .authorized),
            .startCapture(token: 1)
        )
        XCTAssertEqual(machine.resolveStart(token: 1, outcome: .failed), .none)
        XCTAssertEqual(machine.state, .failed)

        let retry = machine.start(hasUsageDescription: true, permission: .authorized)
        XCTAssertEqual(retry, .startCapture(token: 2))
        XCTAssertEqual(machine.state, .starting)
    }

    // MARK: - Repeated clicks

    func testRepeatedStartClicksAreIgnoredWhileRequestingStartingOrRunning() {
        var machine = NotchMirrorStateMachine()
        XCTAssertEqual(
            machine.start(hasUsageDescription: true, permission: .notDetermined),
            .requestPermission(token: 1)
        )
        XCTAssertEqual(machine.start(hasUsageDescription: true, permission: .notDetermined), .none)
        XCTAssertEqual(machine.generation, 1)

        XCTAssertEqual(
            machine.resolvePermission(token: 1, granted: true, statusAfterRequest: .authorized),
            .startCapture(token: 1)
        )
        XCTAssertEqual(machine.start(hasUsageDescription: true, permission: .authorized), .none)
        XCTAssertEqual(machine.generation, 1)

        XCTAssertEqual(
            machine.resolveStart(token: 1, outcome: .started(deviceID: "cam-1", deviceName: nil)),
            .none
        )
        XCTAssertEqual(machine.start(hasUsageDescription: true, permission: .authorized), .none)
        XCTAssertEqual(machine.state, .running)
        XCTAssertEqual(machine.generation, 1)
    }

    func testRepeatedStopClicksAreNoOpsWhenIdle() {
        var machine = NotchMirrorStateMachine()
        XCTAssertEqual(machine.stop(), .none)
        XCTAssertEqual(machine.generation, 0)
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Explicit stop vs close (leaving page / collapsing Island / disabling tab)

    func testExplicitStopReleasesSessionAndKeepsPageActive() {
        var machine = NotchMirrorStateMachine()
        _ = machine.activate()
        _ = machine.start(hasUsageDescription: true, permission: .authorized)
        _ = machine.resolveStart(token: 1, outcome: .started(deviceID: "cam-1", deviceName: "Built-in"))

        let effect = machine.stop()
        XCTAssertEqual(effect, .stopCapture)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertTrue(machine.isPageActive)
        XCTAssertNil(machine.activeDeviceID)
    }

    func testCloseReleasesSessionAndMarksPageInactive() {
        var machine = NotchMirrorStateMachine()
        _ = machine.activate()
        _ = machine.start(hasUsageDescription: true, permission: .authorized)
        _ = machine.resolveStart(token: 1, outcome: .started(deviceID: "cam-1", deviceName: "Built-in"))

        let effect = machine.close()
        XCTAssertEqual(effect, .stopCapture)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.isPageActive)
        XCTAssertNil(machine.activeDeviceID)
    }

    // MARK: - Navigation / collapse while permission is pending & late results

    func testCloseWhilePermissionPendingIgnoresLateGrantResult() {
        var machine = NotchMirrorStateMachine()
        _ = machine.activate()
        XCTAssertEqual(
            machine.start(hasUsageDescription: true, permission: .notDetermined),
            .requestPermission(token: 1)
        )

        // User collapses Island, switches page, or disables the Mirror tab before answering TCC dialog.
        XCTAssertEqual(machine.close(), .none)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.isPageActive)

        // Late TCC grant arrives for token 1 -> must be ignored and never start capture.
        let late = machine.resolvePermission(token: 1, granted: true, statusAfterRequest: .authorized)
        XCTAssertEqual(late, .none)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.isPageActive)
    }

    func testReopenBeforeLatePermissionResultStillIgnoresStaleToken() {
        var machine = NotchMirrorStateMachine()
        _ = machine.activate()
        XCTAssertEqual(
            machine.start(hasUsageDescription: true, permission: .notDetermined),
            .requestPermission(token: 1)
        )
        _ = machine.close()
        _ = machine.activate()

        // Even though the page is open again, token 1 was invalidated by close().
        let late = machine.resolvePermission(token: 1, granted: true, statusAfterRequest: .authorized)
        XCTAssertEqual(late, .none)
        XCTAssertEqual(machine.state, .idle)
    }

    func testCloseWhileStartingTriggersDefensiveStopOnLateHardwareStart() {
        var machine = NotchMirrorStateMachine()
        _ = machine.activate()
        XCTAssertEqual(
            machine.start(hasUsageDescription: true, permission: .authorized),
            .startCapture(token: 1)
        )

        XCTAssertEqual(machine.close(), .stopCapture)
        XCTAssertEqual(machine.state, .idle)

        // If a late worker callback still reports `.started`, state remains idle and requests teardown.
        let lateStart = machine.resolveStart(
            token: 1,
            outcome: .started(deviceID: "cam-1", deviceName: "Built-in")
        )
        XCTAssertEqual(lateStart, .stopCapture)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.activeDeviceID)
    }

    // MARK: - Interruption, runtime error, and device removal

    func testSessionInterruptionAndRecovery() {
        var machine = NotchMirrorStateMachine()
        _ = machine.start(hasUsageDescription: true, permission: .authorized)
        _ = machine.resolveStart(token: 1, outcome: .started(deviceID: "cam-1", deviceName: "Built-in"))

        XCTAssertEqual(machine.handleInterruptionBegan(), .none)
        XCTAssertEqual(machine.state, .interrupted)
        XCTAssertTrue(machine.state.isPreviewVisible)
        XCTAssertTrue(machine.state.canStop)
        XCTAssertTrue(machine.state.canStart)

        XCTAssertEqual(machine.handleInterruptionEnded(isSessionRunning: true), .none)
        XCTAssertEqual(machine.state, .running)
    }

    func testInterruptionEndingWithStoppedSessionReturnsToIdleAndReleasesHardware() {
        var machine = NotchMirrorStateMachine()
        _ = machine.start(hasUsageDescription: true, permission: .authorized)
        _ = machine.resolveStart(token: 1, outcome: .started(deviceID: "cam-1", deviceName: "Built-in"))

        _ = machine.handleInterruptionBegan()
        XCTAssertEqual(machine.handleInterruptionEnded(isSessionRunning: false), .stopCapture)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.activeDeviceID)
    }

    func testActiveDeviceDisconnectStopsSessionAndEntersDeviceRemoved() {
        var machine = NotchMirrorStateMachine()
        _ = machine.start(hasUsageDescription: true, permission: .authorized)
        _ = machine.resolveStart(token: 1, outcome: .started(deviceID: "usb-cam-42", deviceName: "USB Cam"))

        // Unrelated camera disconnected -> ignored.
        XCTAssertEqual(machine.handleDeviceDisconnected(deviceID: "other-cam-99"), .none)
        XCTAssertEqual(machine.state, .running)

        // Active camera disconnected -> stop capture and show deviceRemoved.
        XCTAssertEqual(machine.handleDeviceDisconnected(deviceID: "usb-cam-42"), .stopCapture)
        XCTAssertEqual(machine.state, .deviceRemoved)
        XCTAssertNil(machine.activeDeviceID)
        XCTAssertTrue(machine.state.canStart)
    }

    func testRuntimeErrorReleasesSessionAndTransitionsToFailed() {
        var machine = NotchMirrorStateMachine()
        _ = machine.start(hasUsageDescription: true, permission: .authorized)
        _ = machine.resolveStart(token: 1, outcome: .started(deviceID: "cam-1", deviceName: "Built-in"))

        XCTAssertEqual(machine.handleRuntimeError(), .stopCapture)
        XCTAssertEqual(machine.state, .failed)
        XCTAssertNil(machine.activeDeviceID)
        XCTAssertTrue(machine.state.canStart)
    }
}
