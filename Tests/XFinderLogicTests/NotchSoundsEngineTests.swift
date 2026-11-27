import XCTest

@MainActor
private final class MockSoundsAudioBackend: SoundsAudioBackend {
    var isRunning = false
    var isAllocated = false
    var hasOutput = true
    var startError: Error?
    private(set) var startCalls = 0
    private(set) var teardownCalls = 0
    private(set) var lastGains: NotchSoundsRules.MixGains = .zero
    private(set) var onConfigChange: (@Sendable () -> Void)?

    func hasOutputDevice() -> Bool { hasOutput }

    func start(
        gains: NotchSoundsRules.MixGains,
        onConfigurationChange: @escaping @Sendable () -> Void
    ) throws {
        startCalls += 1
        if !hasOutput {
            throw NotchSoundsRules.EngineError.noOutputDevice
        }
        if let err = startError {
            throw err
        }
        isAllocated = true
        isRunning = true
        lastGains = gains
        onConfigChange = onConfigurationChange
    }

    func updateGains(_ gains: NotchSoundsRules.MixGains) {
        lastGains = gains
    }

    func teardown() {
        teardownCalls += 1
        isRunning = false
        isAllocated = false
        lastGains = .zero
        onConfigChange = nil
    }
}

@MainActor
private final class MockSoundsScheduler: SoundsTickScheduler {
    private(set) var pendingDelay: TimeInterval?
    private var pendingAction: (@MainActor () -> Void)?
    private(set) var scheduleCalls = 0
    private(set) var cancelCalls = 0

    var isScheduled: Bool { pendingAction != nil }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        scheduleCalls += 1
        pendingDelay = delay
        pendingAction = action
    }

    func cancel() {
        cancelCalls += 1
        pendingDelay = nil
        pendingAction = nil
    }

    /// Captures and invokes the current scheduled action (returns false if nothing was scheduled).
    @discardableResult
    func fireNext() -> Bool {
        guard let action = pendingAction else { return false }
        pendingDelay = nil
        pendingAction = nil
        action()
        return true
    }

    /// Captures the current scheduled action without clearing it, to test stale-callback rejection.
    func capturePendingAction() -> (@MainActor () -> Void)? {
        pendingAction
    }
}

@MainActor
final class NotchSoundsEngineTests: XCTestCase {

    private func makeHarness(startTime: TimeInterval = 10_000) -> (
        engine: NotchSoundsEngine,
        backend: MockSoundsAudioBackend,
        scheduler: MockSoundsScheduler,
        advance: (TimeInterval) -> Void
    ) {
        var now = Date(timeIntervalSince1970: startTime)
        let backend = MockSoundsAudioBackend()
        let scheduler = MockSoundsScheduler()
        let engine = NotchSoundsEngine(
            backend: backend,
            scheduler: scheduler,
            now: { now },
            registerSystemObservers: false
        )
        let advance: (TimeInterval) -> Void = { delta in
            now = now.addingTimeInterval(delta)
        }
        return (engine, backend, scheduler, advance)
    }

    // MARK: - Idle Invariant

    func testIdleHoldsZeroTimersAndNoAudioProcessing() {
        let (engine, backend, scheduler, _) = makeHarness()

        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isAudioEngineRunning)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertEqual(backend.startCalls, 0)
        XCTAssertEqual(scheduler.scheduleCalls, 0)

        // Setting a sleep preset while idle must not start a timer or audio engine.
        engine.setSleepPreset(.min15)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertNil(engine.sleepTimer)
    }

    // MARK: - Multi-Channel Mixing & Volume Limiting

    func testMultiChannelToggleVolumeLimitingAndStopAll() {
        let (engine, backend, _, _) = makeHarness()

        engine.setVolume(1.0, for: .white)
        engine.setVolume(1.0, for: .pink)
        engine.setVolume(1.0, for: .brown)

        engine.toggle(.white)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.activeCount, 1)
        XCTAssertEqual(backend.startCalls, 1)

        engine.toggle(.pink)
        engine.toggle(.brown)
        XCTAssertEqual(engine.activeCount, 3)
        // Adding channels updates gains on the running engine without restarting it.
        XCTAssertEqual(backend.startCalls, 1)
        XCTAssertEqual(backend.lastGains.sum, NotchSoundsRules.maxMixGainSum, accuracy: 1e-5)

        // Turning off one channel keeps the others running.
        engine.toggle(.white)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.activeCount, 2)
        XCTAssertEqual(backend.lastGains.white, 0)

        // Stop All tears down audio and preserves per-channel volumes.
        engine.stopAll()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertEqual(engine.lastStopReason, .user)
        XCTAssertEqual(engine.volume(for: .white), 1.0)
        XCTAssertEqual(engine.volume(for: .pink), 1.0)
    }

    // MARK: - Sleep Timer Expiry While Collapsed

    func testSleepTimerFadesAndStopsCleanlyWhileCollapsed() {
        let (engine, backend, scheduler, advance) = makeHarness()

        engine.toggle(.pink)
        engine.setSleepTimer(duration: 20, fadeDuration: 10)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertTrue(engine.hasActiveTimer)
        XCTAssertFalse(engine.isFadingOut)
        XCTAssertEqual(engine.masterGain, 1.0, accuracy: 1e-5)

        // Advance to fade midpoint (15 s elapsed, 5 s remaining -> 50% fade).
        advance(15)
        XCTAssertTrue(scheduler.fireNext())
        XCTAssertTrue(engine.isPlaying)
        XCTAssertTrue(engine.isFadingOut)
        XCTAssertEqual(engine.masterGain, 0.5, accuracy: 1e-3)
        XCTAssertLessThan(backend.lastGains.pink, NotchSoundsRules.effectiveGains(channels: engine.channels, masterGain: 1.0).pink)

        // Advance past expiry (20.1 s elapsed) while notch is collapsed / page not visible.
        advance(5.1)
        XCTAssertTrue(scheduler.fireNext())
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isAudioEngineRunning)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertNil(engine.sleepTimer)
        XCTAssertEqual(engine.lastStopReason, .sleepTimerFinished)
    }

    // MARK: - Rapid Interactions During Fade

    func testCancelTimerMidFadeRestoresFullGainAndIgnoresStaleTick() {
        let (engine, backend, scheduler, advance) = makeHarness()

        engine.toggle(.brown)
        engine.setSleepTimer(duration: 10, fadeDuration: 10)
        advance(5)
        XCTAssertTrue(scheduler.fireNext())
        XCTAssertEqual(engine.masterGain, 0.5, accuracy: 1e-3)

        let staleTick = scheduler.capturePendingAction()
        engine.cancelSleepTimer()

        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.masterGain, 1.0, accuracy: 1e-5)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertNil(engine.sleepTimer)
        XCTAssertEqual(backend.lastGains.brown, NotchSoundsRules.effectiveGains(channels: engine.channels, masterGain: 1.0).brown, accuracy: 1e-5)

        // Even if a stale callback fires late, generation guard rejects it.
        advance(10)
        staleTick?()
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.masterGain, 1.0, accuracy: 1e-5)
    }

    func testRapidPresetSwitchAndStopToggleDuringFadeNeverCorruptState() {
        let (engine, _, scheduler, advance) = makeHarness()

        engine.toggle(.white)
        engine.setSleepTimer(duration: 10, fadeDuration: 10)
        advance(8)
        XCTAssertTrue(scheduler.fireNext())
        XCTAssertLessThan(engine.masterGain, 0.2)

        // Rapidly switch to 30 min preset during fade -> restores gain to 1.0.
        let staleFromOldFade = scheduler.capturePendingAction()
        engine.setSleepPreset(.min30)
        XCTAssertEqual(engine.masterGain, 1.0, accuracy: 1e-5)
        XCTAssertFalse(engine.isFadingOut)

        // Fire stale callback from old 10 s fade -> ignored.
        advance(5)
        staleFromOldFade?()
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.masterGain, 1.0, accuracy: 1e-5)

        // Rapidly toggle channel OFF then ON again -> fresh session, no leftover fade timer.
        engine.toggle(.white)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.hasActiveTimer)
        engine.toggle(.white)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertEqual(engine.masterGain, 1.0, accuracy: 1e-5)
    }

    // MARK: - Engine Start Error

    func testEngineStartErrorLeavesHonestIdleStateAndRecoversOnRetry() {
        let (engine, backend, _, _) = makeHarness()
        backend.startError = NotchSoundsRules.EngineError.engineStartFailed

        engine.toggle(.white)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.activeCount, 0)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertEqual(engine.lastError, .engineStartFailed)
        XCTAssertEqual(engine.lastStopReason, .engineError)

        // Recover when backend works again.
        backend.startError = nil
        engine.toggle(.white)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertNil(engine.lastError)
    }

    // MARK: - Output Device Change & Device Loss

    func testOutputChangeRebuildsWhilePlayingAndIgnoresWhileIdle() {
        let (engine, backend, _, _) = makeHarness()

        // Idle: output change must not allocate or start the audio engine.
        engine.handleOutputConfigurationChanged()
        XCTAssertEqual(backend.startCalls, 0)
        XCTAssertFalse(engine.isAudioEngineAllocated)

        // Playing: output change with available device rebuilds seamlessly.
        engine.toggle(.pink)
        engine.setSleepPreset(.min15)
        XCTAssertEqual(backend.startCalls, 1)

        engine.handleOutputConfigurationChanged()
        XCTAssertEqual(backend.startCalls, 2)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertTrue(engine.hasActiveTimer)
        XCTAssertNil(engine.lastError)
    }

    func testOutputDeviceLossStopsPlaybackAndSurfacesError() {
        let (engine, backend, _, _) = makeHarness()

        engine.toggle(.white)
        engine.setSleepPreset(.min15)
        XCTAssertTrue(engine.isPlaying)

        backend.hasOutput = false
        engine.handleOutputConfigurationChanged()

        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertEqual(engine.lastError, .noOutputDevice)
        XCTAssertEqual(engine.lastStopReason, .outputDeviceLost)
    }

    // MARK: - Sleep / Wake, Tab Disable, App Termination

    func testSystemSleepReleasesResourcesAndWakeStaysIntentionallyIdle() {
        let (engine, _, _, _) = makeHarness()

        engine.setVolume(0.75, for: .brown)
        engine.toggle(.brown)
        engine.setSleepPreset(.min30)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertTrue(engine.hasActiveTimer)

        engine.handleSystemWillSleep()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertEqual(engine.lastStopReason, .systemSleep)
        XCTAssertEqual(engine.volume(for: .brown), 0.75)

        engine.handleSystemDidWake()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
    }

    func testTabDisabledStopsPlaybackAndClearsTimer() {
        let (engine, _, _, _) = makeHarness()

        engine.toggle(.white)
        engine.toggle(.pink)
        engine.setSleepPreset(.min60)
        XCTAssertTrue(engine.isPlaying)

        engine.applyTabVisibility(isEnabled: false)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertEqual(engine.lastStopReason, .tabDisabled)

        // Re-enabling tab never auto-starts sound.
        engine.applyTabVisibility(isEnabled: true)
        XCTAssertFalse(engine.isPlaying)
    }

    func testAppTerminationReleasesEverything() {
        let (engine, _, _, _) = makeHarness()

        engine.toggle(.brown)
        engine.setSleepPreset(.min15)
        engine.handleAppWillTerminate()

        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isAudioEngineAllocated)
        XCTAssertFalse(engine.hasActiveTimer)
        XCTAssertEqual(engine.lastStopReason, .appWillTerminate)
    }
}
