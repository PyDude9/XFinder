import XCTest
import Foundation

final class NotchClockEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 4_000_000)

    // MARK: - Stopwatch (start, pause/resume, lap, reset, sleep/wake, clock jump)

    func testStopwatchStartPauseResumeLapResetAndSleepWake() {
        var sw = NotchStopwatch()
        XCTAssertFalse(sw.isActive)
        XCTAssertFalse(sw.isRunning)
        XCTAssertFalse(sw.isPaused)
        XCTAssertEqual(sw.label(at: t0), "0:00")

        // Start and advance 65 seconds
        sw = sw.started(at: t0)
        XCTAssertTrue(sw.isRunning)
        XCTAssertTrue(sw.isActive)
        XCTAssertFalse(sw.isPaused)
        XCTAssertEqual(sw.label(at: t0.addingTimeInterval(65)), "1:05")
        XCTAssertEqual(sw.started(at: t0.addingTimeInterval(10)), sw, "starting twice is idempotent")

        // Record lap while running
        sw = sw.recordedLap(at: t0.addingTimeInterval(65))
        XCTAssertEqual(sw.laps.count, 1)
        XCTAssertEqual(sw.laps[0], 65, accuracy: 0.001)

        // Pause freezes elapsed across arbitrary sleep duration
        sw = sw.paused(at: t0.addingTimeInterval(90))
        XCTAssertTrue(sw.isPaused)
        XCTAssertFalse(sw.isRunning)
        XCTAssertEqual(sw.elapsed(at: t0.addingTimeInterval(99_999)), 90, accuracy: 0.001)
        XCTAssertEqual(sw.paused(at: t0.addingTimeInterval(120)), sw, "pausing twice is idempotent")

        // Resume and simulate 1 hour sleep/wake
        sw = sw.resumed(at: t0.addingTimeInterval(200))
        XCTAssertTrue(sw.isRunning)
        let afterSleep = t0.addingTimeInterval(200 + 3600)
        XCTAssertEqual(sw.elapsed(at: afterSleep), 3690, accuracy: 0.001)
        XCTAssertEqual(sw.label(at: afterSleep), "1:01:30")

        // Backward wall-clock jump never shrinks below accumulated
        XCTAssertEqual(sw.elapsed(at: t0), 90, accuracy: 0.001)

        // Reset clears everything
        let cleared = sw.reset()
        XCTAssertFalse(cleared.isActive)
        XCTAssertTrue(cleared.laps.isEmpty)
        XCTAssertEqual(cleared.elapsed(at: afterSleep), 0, accuracy: 0.001)
    }

    func testStopwatchCapsLapsAtMaximum() {
        var sw = NotchStopwatch().started(at: t0)
        for i in 1...(NotchStopwatch.maxLaps + 10) {
            sw = sw.recordedLap(at: t0.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(sw.laps.count, NotchStopwatch.maxLaps)
        XCTAssertEqual(sw.laps.last ?? 0, Double(NotchStopwatch.maxLaps + 10), accuracy: 0.001)
    }

    // MARK: - Pomodoro (phases, cycle, pause/resume, skip, sleep/wake)

    func testPomodoroCyclePauseResumeAndLongBreak() {
        let cfg = NotchPomodoro.Config(focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, cyclesBeforeLongBreak: 4)
        var pomo = NotchPomodoro(config: cfg)
        XCTAssertEqual(pomo.phase, .focus)
        XCTAssertFalse(pomo.isActive)
        XCTAssertEqual(pomo.label(at: t0), "25:00")
        XCTAssertEqual(pomo.cycleSlot, 1)

        // Start, pause after 5 min, resume after 1 hour sleep
        pomo = pomo.started(at: t0)
        XCTAssertTrue(pomo.isRunning)
        pomo = pomo.paused(at: t0.addingTimeInterval(300))
        XCTAssertTrue(pomo.isPaused)
        XCTAssertEqual(pomo.remaining(at: t0.addingTimeInterval(4000)), 1200, accuracy: 0.001)
        XCTAssertFalse(pomo.isPhaseFinished(at: t0.addingTimeInterval(4000)))

        pomo = pomo.resumed(at: t0.addingTimeInterval(4000))
        XCTAssertTrue(pomo.isRunning)
        XCTAssertFalse(pomo.isPhaseFinished(at: t0.addingTimeInterval(5199)))
        XCTAssertTrue(pomo.isPhaseFinished(at: t0.addingTimeInterval(5200)))

        // Complete 4 focus cycles -> 4th focus leads to long break
        var current = NotchPomodoro(config: cfg)
        for cycle in 1...4 {
            current = current.started(at: t0)
            let done = current.advancedAfterCompletion()
            XCTAssertEqual(done.completed, .focus)
            current = done.state
            XCTAssertFalse(current.isActive, "next phase waits in ready state")
            XCTAssertEqual(current.completedFocusSessions, cycle)
            if cycle < 4 {
                XCTAssertEqual(current.phase, .shortBreak)
                let breakDone = current.started(at: t0).advancedAfterCompletion()
                XCTAssertEqual(breakDone.completed, .shortBreak)
                current = breakDone.state
                XCTAssertEqual(current.phase, .focus)
            } else {
                XCTAssertEqual(current.phase, .longBreak)
                XCTAssertEqual(current.completedDotsInCycle, 4)
            }
        }
    }

    func testPomodoroSkipDoesNotCreditUnfinishedFocus() {
        var pomo = NotchPomodoro().started(at: t0)
        pomo = pomo.skipped()
        XCTAssertEqual(pomo.phase, .shortBreak)
        XCTAssertEqual(pomo.completedFocusSessions, 0)
        XCTAssertFalse(pomo.isActive)
        pomo = pomo.skipped()
        XCTAssertEqual(pomo.phase, .focus)
        XCTAssertEqual(pomo.completedFocusSessions, 0)
    }

    func testPomodoroOverdueAfterLongSleepFiresOnceWithoutChainedSpam() {
        var suite = NotchClockSuite()
        suite.selectedMode = .pomodoro
        suite.pomodoro = suite.pomodoro.started(at: t0)

        // Sleep 3 hours (past 25m focus + 5m break + more)
        let wake = t0.addingTimeInterval(3 * 3600)
        let events = suite.reconcile(at: wake)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first, .pomodoroPhaseFinished(completed: .focus, next: .shortBreak, completedFocusSessions: 1))
        XCTAssertEqual(suite.pomodoro.phase, .shortBreak)
        XCTAssertFalse(suite.pomodoro.isRunning)
        XCTAssertFalse(suite.needsSecondTicker)

        // Second reconcile immediately after produces nothing
        XCTAssertTrue(suite.reconcile(at: wake.addingTimeInterval(1)).isEmpty)
    }

    // MARK: - Hydration reminder (optional, OFF by default, sleep coalescing, snooze)

    func testHydrationOffByDefaultAndNeverFiresWhenDisabled() {
        var suite = NotchClockSuite()
        XCTAssertFalse(suite.hydration.enabled)
        XCTAssertNil(suite.hydration.nextDueAt)
        XCTAssertNil(suite.hydration.secondsUntilDue(at: t0))
        XCTAssertTrue(suite.reconcile(at: t0.addingTimeInterval(86_400)).isEmpty)
        XCTAssertFalse(suite.needsSecondTicker)
    }

    func testHydrationCoalescesSleepAndSupportsSnoozeAndAck() {
        let t0 = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: self.t0)!
        var hydration = NotchHydrationReminder()
        hydration.setInterval(minutes: 45, now: t0)
        hydration.setEnabled(true, now: t0)
        XCTAssertEqual(hydration.secondsUntilDue(at: t0) ?? -1, 7200, accuracy: 0.001)

        // Not due before two hours
        XCTAssertFalse(hydration.reconcile(at: t0.addingTimeInterval(7199)))

        // Sleep 4 hours -> fires ONCE and reschedules +2 hours from wake
        let wake = t0.addingTimeInterval(4 * 3600)
        XCTAssertTrue(hydration.reconcile(at: wake))
        XCTAssertFalse(hydration.reconcile(at: wake.addingTimeInterval(1)))
        XCTAssertEqual(hydration.secondsUntilDue(at: wake) ?? -1, 7200, accuracy: 0.001)

        // Snooze 10 minutes
        hydration.snooze(minutes: 10, now: wake)
        XCTAssertEqual(hydration.secondsUntilDue(at: wake) ?? -1, 600, accuracy: 0.001)
        XCTAssertTrue(hydration.reconcile(at: wake.addingTimeInterval(600)))

        // Turning OFF clears schedule
        hydration.setEnabled(false, now: wake)
        XCTAssertNil(hydration.nextDueAt)
        XCTAssertFalse(hydration.reconcile(at: wake.addingTimeInterval(99_999)))
    }

    func testHydrationDailyCapSurvivesRelaunchAndQuietHours() throws {
        let calendar = Calendar.current
        let noon = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()))
        let morning = try XCTUnwrap(calendar.date(bySettingHour: 8, minute: 0, second: 0, of: noon))
        var reminder = NotchHydrationReminder(enabled: true, nextDueAt: noon)
        reminder.setDailyLimit(2, now: morning.addingTimeInterval(-7200))
        XCTAssertTrue(reminder.reconcile(at: noon))
        let evening = noon.addingTimeInterval(6 * 3600)
        XCTAssertTrue(reminder.reconcile(at: evening))
        let data = try JSONEncoder().encode(reminder)
        reminder = try JSONDecoder().decode(NotchHydrationReminder.self, from: data)
        reminder.setEnabled(false, now: evening)
        reminder.setEnabled(true, now: evening)
        XCTAssertFalse(reminder.reconcile(at: evening.addingTimeInterval(3600)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: morning))
        XCTAssertEqual(reminder.nextDueAt, tomorrow)
        XCTAssertTrue(reminder.reconcile(at: tomorrow))
    }

    func testHydrationIntervalValidationAndPresets() {
        XCTAssertEqual(NotchHydrationReminder.validIntervalMinutes(nil), 45)
        XCTAssertEqual(NotchHydrationReminder.validIntervalMinutes(5), 15)
        XCTAssertEqual(NotchHydrationReminder.validIntervalMinutes(999), 180)
        XCTAssertEqual(NotchHydrationReminder.nextPreset(after: 30), 45)
        XCTAssertEqual(NotchHydrationReminder.nextPreset(after: 45), 60)
        XCTAssertEqual(NotchHydrationReminder.nextPreset(after: 60), 90)
        XCTAssertEqual(NotchHydrationReminder.nextPreset(after: 90), 30)
    }

    // MARK: - Collapsed signal arbitration

    func testCollapsedBadgeArbitrationBetweenModesAndHydration() {
        var suite = NotchClockSuite()
        // Hydration ON alone never claims the collapsed clock wing
        suite.hydration.setEnabled(true, now: t0)
        XCTAssertNil(suite.collapsedBadge(at: t0))
        XCTAssertFalse(suite.needsSecondTicker)

        // Running stopwatch claims badge even when selectedMode is countdown
        suite.selectedMode = .countdown
        suite.stopwatch = suite.stopwatch.started(at: t0)
        let swBadge = suite.collapsedBadge(at: t0.addingTimeInterval(12))
        XCTAssertEqual(swBadge?.mode, .stopwatch)
        XCTAssertEqual(swBadge?.text, "0:12")
        XCTAssertEqual(swBadge?.isPaused, false)

        // Running clock beats paused clock
        suite.countdown = LiveActivity.Countdown(minutes: 10, now: t0).paused(at: t0.addingTimeInterval(60))
        XCTAssertEqual(suite.collapsedBadge(at: t0.addingTimeInterval(60))?.mode, .stopwatch)

        // When both are running, selectedMode wins tie
        suite.countdown = LiveActivity.Countdown(minutes: 10, now: t0)
        suite.selectedMode = .countdown
        XCTAssertEqual(suite.collapsedBadge(at: t0)?.mode, .countdown)
        suite.selectedMode = .stopwatch
        XCTAssertEqual(suite.collapsedBadge(at: t0)?.mode, .stopwatch)

        // When only paused clocks remain, selectedMode wins tie
        suite.countdown = suite.countdown?.paused(at: t0.addingTimeInterval(30))
        suite.stopwatch = suite.stopwatch.paused(at: t0.addingTimeInterval(30))
        suite.selectedMode = .stopwatch
        let pausedBadge = suite.collapsedBadge(at: t0.addingTimeInterval(100))
        XCTAssertEqual(pausedBadge?.mode, .stopwatch)
        XCTAssertEqual(pausedBadge?.isPaused, true)
        XCTAssertEqual(pausedBadge?.symbol, "pause.fill")
    }

    func testCollapsedSignalIntegrationWithNotchCollapsedSignalAndHiddenTimerTab() {
        var suite = NotchClockSuite()
        suite.pomodoro = suite.pomodoro.started(at: t0)
        let badge = suite.collapsedBadge(at: t0)
        XCTAssertNotNil(badge)

        // Running pomodoro beats held files when .timer tab is visible
        let visible = Set(NotchDestinationID.allCases)
        let signal = NotchCollapsedSignal.resolve(
            itemCount: 2,
            timerActive: badge != nil,
            timerPaused: badge?.isPaused == true,
            nowPlayingActive: true,
            nowPlayingPlaying: true,
            agentActive: false,
            agentBusy: false,
            agentsNeedingYou: 0,
            visibleDestinations: visible
        )
        XCTAssertEqual(signal, .timerRunning)
        XCTAssertEqual(signal.targetPage, .timer)

        // Hiding .timer tab suppresses collapsed timer signal while pomodoro stays running
        var withoutTimer = visible
        withoutTimer.remove(.timer)
        let hiddenSignal = NotchCollapsedSignal.resolve(
            itemCount: 2,
            timerActive: badge != nil,
            timerPaused: badge?.isPaused == true,
            nowPlayingActive: true,
            nowPlayingPlaying: true,
            agentActive: false,
            agentBusy: false,
            agentsNeedingYou: 0,
            visibleDestinations: withoutTimer
        )
        XCTAssertEqual(hiddenSignal, .files(2))
        XCTAssertTrue(suite.pomodoro.isRunning)
    }

    // MARK: - Relaunch persistence & corrupt fallback

    func testRelaunchRoundTripAndReconciliation() {
        var suite = NotchClockSuite()
        suite.selectedMode = .pomodoro
        suite.countdown = LiveActivity.Countdown(minutes: 5, now: t0)
        suite.stopwatch = suite.stopwatch.started(at: t0).recordedLap(at: t0.addingTimeInterval(15))
        suite.pomodoro = suite.pomodoro.started(at: t0).paused(at: t0.addingTimeInterval(60))
        suite.hydration.setInterval(minutes: 30, now: t0)
        suite.hydration.setEnabled(true, now: t0)

        let data = suite.encoded()
        XCTAssertNotNil(data)

        // Relaunch 10 minutes later: countdown expired, stopwatch kept running, pomodoro stayed paused
        let relaunchTime = t0.addingTimeInterval(600)
        var restored = NotchClockSuite.decoded(from: data, now: relaunchTime)
        XCTAssertEqual(restored.selectedMode, .pomodoro)
        XCTAssertEqual(restored.stopwatch.laps.count, 1)
        XCTAssertTrue(restored.pomodoro.isPaused)
        XCTAssertTrue(restored.hydration.enabled)

        let events = restored.reconcile(at: relaunchTime)
        XCTAssertEqual(events.count, 1)
        if case .countdownFinished = events[0] {} else {
            XCTFail("Expected countdownFinished event on relaunch")
        }
        XCTAssertNil(restored.countdown)
        XCTAssertEqual(restored.stopwatch.elapsed(at: relaunchTime), 600, accuracy: 0.001)
        XCTAssertEqual(restored.pomodoro.remaining(at: relaunchTime), 1440, accuracy: 0.001)
    }

    func testCorruptPersistenceDataFallsBackCleanly() {
        let corrupt = Data("not-valid-json{{{".utf8)
        let restored = NotchClockSuite.decoded(
            from: corrupt,
            hydrationEnabledOverride: true,
            hydrationIntervalOverride: 60,
            now: t0
        )
        XCTAssertEqual(restored.selectedMode, .countdown)
        XCTAssertNil(restored.countdown)
        XCTAssertFalse(restored.stopwatch.isActive)
        XCTAssertFalse(restored.pomodoro.isActive)
        XCTAssertTrue(restored.hydration.enabled)
        XCTAssertEqual(restored.hydration.intervalMinutes, 60)
    }

    func testExistingCountdownPreferencesAndCodablePreserved() throws {
        XCTAssertEqual(LiveActivity.timerDefaultMinutes, 25)
        XCTAssertEqual(LiveActivity.timerMinMinutes, 5)
        XCTAssertEqual(LiveActivity.timerMaxMinutes, 120)
        XCTAssertEqual(LiveActivity.validTimerMinutes(nil), 25)

        let paused = LiveActivity.Countdown(minutes: 15, now: t0).paused(at: t0.addingTimeInterval(120))
        let data = try JSONEncoder().encode(paused)
        let decoded = try JSONDecoder().decode(LiveActivity.Countdown.self, from: data)
        XCTAssertEqual(decoded, paused)
        XCTAssertEqual(decoded.remaining(at: t0.addingTimeInterval(9999)), 780, accuracy: 0.001)
    }
}
