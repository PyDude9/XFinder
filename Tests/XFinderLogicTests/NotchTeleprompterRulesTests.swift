import XCTest
import CoreGraphics

final class NotchTeleprompterRulesTests: XCTestCase {

    // MARK: - 1. Empty Text

    func testEmptyAndWhitespaceScriptCannotPlayOrAdvance() {
        for raw in ["", "   ", "\n\t\r\n"] {
            var state = NotchTeleprompterState(
                script: raw,
                isTabEnabled: true,
                isIslandVisible: true,
                isReaderWindowVisible: true
            )
            state = NotchTeleprompterEngine.setMode(state, mode: .reader)
            state = NotchTeleprompterEngine.play(state)

            XCTAssertFalse(state.hasReadableScript)
            XCTAssertFalse(state.isPlaying)
            XCTAssertFalse(state.canAdvance)
            XCTAssertEqual(state.progress, 0)

            let tick = NotchTeleprompterEngine.tick(state, deltaTime: 0.1, scrollableDistance: 400)
            XCTAssertFalse(tick.didAdvance)
            XCTAssertFalse(tick.state.isPlaying)
            XCTAssertEqual(tick.state.progress, 0)
        }
    }

    // MARK: - 2. Large Scripts

    func testLargeScriptIsTruncatedDeterministicallyAndWordCountStaysLinear() {
        let oversized = String(repeating: "word ", count: 25_000) // 125,000 chars
        let normalized = NotchTeleprompterScriptNormalization.sanitize(oversized)
        XCTAssertTrue(normalized.wasTruncated)
        XCTAssertEqual(normalized.text.count, NotchTeleprompterLimits.maxScriptCharacters)
        XCTAssertEqual(NotchTeleprompterScriptNormalization.wordCount(normalized.text), 20_000)

        let exact = String(repeating: "a", count: NotchTeleprompterLimits.maxScriptCharacters)
        let exactResult = NotchTeleprompterScriptNormalization.sanitize(exact)
        XCTAssertFalse(exactResult.wasTruncated)
        XCTAssertEqual(exactResult.text.count, NotchTeleprompterLimits.maxScriptCharacters)
    }

    // MARK: - 3. Invalid Saved Settings

    func testInvalidSavedSettingsSanitizeToSafeBounds() {
        let nanSettings = NotchTeleprompterSettings.sanitized(
            speed: .nan,
            fontSize: .infinity,
            progress: -.infinity,
            modeRaw: "corrupted-mode"
        )
        XCTAssertEqual(nanSettings.speedPointsPerSecond, NotchTeleprompterLimits.defaultSpeed)
        XCTAssertEqual(nanSettings.fontSize, NotchTeleprompterLimits.defaultFontSize)
        XCTAssertEqual(nanSettings.progress, 0)
        XCTAssertEqual(nanSettings.mode, .editor)

        let outOfRange = NotchTeleprompterSettings.sanitized(
            speed: -500,
            fontSize: 999,
            progress: 4.5,
            modeRaw: "reader"
        )
        XCTAssertEqual(outOfRange.speedPointsPerSecond, NotchTeleprompterLimits.minSpeed)
        XCTAssertEqual(outOfRange.fontSize, NotchTeleprompterLimits.maxFontSize)
        XCTAssertEqual(outOfRange.progress, 1.0)
        XCTAssertEqual(outOfRange.mode, .reader)
    }

    // MARK: - 4. Edits During Playback

    func testEditDuringPlaybackPausesAndPreservesProgress() {
        var state = NotchTeleprompterState(
            script: "First line\nSecond line\nThird line",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 50, fontSize: 22, progress: 0.4, mode: .reader),
            isIslandVisible: true
        )
        state = NotchTeleprompterEngine.play(state)
        XCTAssertTrue(state.isPlaying)

        state = NotchTeleprompterEngine.updateScript(state, rawText: "First line edited\nSecond line\nThird line")
        XCTAssertFalse(state.isPlaying, "Editing during playback must pause so text does not move under the cursor")
        XCTAssertEqual(state.progress, 0.4, accuracy: 0.0001)

        // Clearing script resets position to 0 and keeps paused
        state = NotchTeleprompterEngine.updateScript(state, rawText: "   ")
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.progress, 0)
        XCTAssertFalse(state.reachedEnd)
    }

    // MARK: - 5. Reaching the End & Restart

    func testReachingEndStopsPlaybackAndPlayRestartsFromZero() {
        var state = NotchTeleprompterState(
            script: "Line one\nLine two",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 100, fontSize: 22, progress: 0.95, mode: .reader),
            isIslandVisible: true
        )
        state = NotchTeleprompterEngine.play(state)

        let tick1 = NotchTeleprompterEngine.tick(state, deltaTime: 0.1, scrollableDistance: 100)
        XCTAssertTrue(tick1.didAdvance)
        XCTAssertEqual(tick1.state.progress, 1.0)
        XCTAssertTrue(tick1.state.reachedEnd)
        XCTAssertFalse(tick1.state.isPlaying)
        XCTAssertFalse(tick1.state.needsTicker)

        // Subsequent tick after end is a no-op
        let tick2 = NotchTeleprompterEngine.tick(tick1.state, deltaTime: 0.1, scrollableDistance: 100)
        XCTAssertFalse(tick2.didAdvance)
        XCTAssertEqual(tick2.state.progress, 1.0)

        // Pressing Play at the end restarts from 0
        let replayed = NotchTeleprompterEngine.play(tick1.state)
        XCTAssertTrue(replayed.isPlaying)
        XCTAssertEqual(replayed.progress, 0)
        XCTAssertFalse(replayed.reachedEnd)

        // Explicit restart resets to 0
        var mid = NotchTeleprompterEngine.setProgress(replayed, progress: 0.6)
        mid = NotchTeleprompterEngine.restart(mid)
        XCTAssertEqual(mid.progress, 0)
        XCTAssertFalse(mid.reachedEnd)
    }

    func testShortScriptWithZeroScrollableDistanceCompletesCleanly() {
        var state = NotchTeleprompterState(
            script: "Short line",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 44, fontSize: 22, progress: 0, mode: .reader),
            isIslandVisible: true
        )
        state = NotchTeleprompterEngine.play(state)
        let tick = NotchTeleprompterEngine.tick(state, deltaTime: 0.1, scrollableDistance: 0)
        XCTAssertEqual(tick.state.progress, 1.0)
        XCTAssertTrue(tick.state.reachedEnd)
        XCTAssertFalse(tick.state.isPlaying)
    }

    // MARK: - 6. Preserving Reading Position Across Surface Switches

    func testReadingPositionPreservedAcrossIslandEditorReaderAndSeparateWindow() {
        var state = NotchTeleprompterState(
            script: "Opening\nMiddle\nClosing",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 44, fontSize: 22, progress: 0, mode: .reader),
            isIslandVisible: true
        )
        state = NotchTeleprompterEngine.play(state)
        state = NotchTeleprompterEngine.tick(state, deltaTime: 0.25, scrollableDistance: 110).state
        let savedProgress = state.progress
        XCTAssertEqual(savedProgress, 0.1, accuracy: 0.0001)

        // Open separate reader window, switch Island to editor, close Island -> progress preserved & still playing
        state = NotchTeleprompterEngine.setReaderWindowVisible(state, visible: true)
        state = NotchTeleprompterEngine.setMode(state, mode: .editor)
        state = NotchTeleprompterEngine.setIslandVisible(state, visible: false)
        XCTAssertEqual(state.progress, savedProgress, accuracy: 0.0001)
        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.canAdvance)

        // Advance inside reader window
        state = NotchTeleprompterEngine.tick(state, deltaTime: 0.25, scrollableDistance: 110).state
        let windowProgress = state.progress
        XCTAssertEqual(windowProgress, 0.2, accuracy: 0.0001)

        // Close reader window, reopen Island in reader mode -> exact progress preserved
        state = NotchTeleprompterEngine.setReaderWindowVisible(state, visible: false)
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.progress, windowProgress, accuracy: 0.0001)

        state = NotchTeleprompterEngine.setIslandVisible(state, visible: true)
        state = NotchTeleprompterEngine.setMode(state, mode: .reader)
        XCTAssertEqual(state.progress, windowProgress, accuracy: 0.0001)
    }

    // MARK: - 7. Closing Island, Disabling Tab, Closing Reader Window

    func testClosingIslandPausesWhenReaderWindowIsClosed() {
        var state = NotchTeleprompterState(
            script: "Hello world",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 44, fontSize: 22, progress: 0.25, mode: .reader),
            isIslandVisible: true,
            isReaderWindowVisible: false
        )
        state = NotchTeleprompterEngine.play(state)
        XCTAssertTrue(state.canAdvance)

        state = NotchTeleprompterEngine.setIslandVisible(state, visible: false)
        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.canAdvance)
        XCTAssertEqual(state.progress, 0.25, accuracy: 0.0001)

        let tick = NotchTeleprompterEngine.tick(state, deltaTime: 0.2, scrollableDistance: 200)
        XCTAssertFalse(tick.didAdvance)
        XCTAssertEqual(tick.state.progress, 0.25, accuracy: 0.0001)
    }

    func testDisablingTabStopsPlaybackClosesReaderWindowAndPreservesState() {
        var state = NotchTeleprompterState(
            script: "Keep my script",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 60, fontSize: 24, progress: 0.33, mode: .reader),
            isTabEnabled: true,
            isIslandVisible: true,
            isReaderWindowVisible: true
        )
        state = NotchTeleprompterEngine.play(state)
        XCTAssertTrue(state.isPlaying)

        state = NotchTeleprompterEngine.setTabEnabled(state, enabled: false)
        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.isReaderWindowVisible)
        XCTAssertFalse(state.canAdvance)
        XCTAssertEqual(state.script, "Keep my script")
        XCTAssertEqual(state.progress, 0.33, accuracy: 0.0001)

        // Cannot start playing or open reader window while disabled
        let attemptedPlay = NotchTeleprompterEngine.play(state)
        XCTAssertFalse(attemptedPlay.isPlaying)
        let attemptedWindow = NotchTeleprompterEngine.setReaderWindowVisible(state, visible: true)
        XCTAssertFalse(attemptedWindow.isReaderWindowVisible)
    }

    // MARK: - 8. Sleep, Wake & Delta Clamping

    func testSleepPausesImmediatelyAndWakeDoesNotAutoResume() {
        var state = NotchTeleprompterState(
            script: "Presentation script",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 44, fontSize: 22, progress: 0.1, mode: .reader),
            isIslandVisible: true
        )
        state = NotchTeleprompterEngine.play(state)
        XCTAssertTrue(state.isPlaying)

        state = NotchTeleprompterEngine.handleSystemSleep(state)
        XCTAssertTrue(state.isSleeping)
        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.canAdvance)

        // Cannot play while sleeping
        XCTAssertFalse(NotchTeleprompterEngine.play(state).isPlaying)

        state = NotchTeleprompterEngine.handleSystemWake(state)
        XCTAssertFalse(state.isSleeping)
        XCTAssertFalse(state.isPlaying, "Wake must not auto-resume playback unexpectedly")
    }

    func testHugeDeltaTimeIsClampedToMaxTickDelta() {
        var state = NotchTeleprompterState(
            script: "Long script",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 100, fontSize: 22, progress: 0, mode: .reader),
            isIslandVisible: true
        )
        state = NotchTeleprompterEngine.play(state)
        let tick = NotchTeleprompterEngine.tick(state, deltaTime: 30.0, scrollableDistance: 1000)
        // Clamped to 0.25s * 100pt/s / 1000pt = 0.025
        XCTAssertEqual(tick.state.progress, 0.025, accuracy: 0.0001)
    }

    // MARK: - 9. Reduce Motion

    func testReduceMotionAdvancesInDiscreteStepsInsteadOfSubStepContinuousMotion() {
        var state = NotchTeleprompterState(
            script: "Stepped script",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 100, fontSize: 22, progress: 0, mode: .reader),
            isIslandVisible: true,
            reduceMotion: true
        )
        state = NotchTeleprompterEngine.play(state)

        // Below step interval (0.85s): accumulates without jumping
        let t1 = NotchTeleprompterEngine.tick(state, deltaTime: 0.25, scrollableDistance: 1000)
        XCTAssertFalse(t1.didAdvance)
        XCTAssertEqual(t1.state.progress, 0)

        let t2 = NotchTeleprompterEngine.tick(t1.state, deltaTime: 0.25, scrollableDistance: 1000)
        XCTAssertFalse(t2.didAdvance)
        XCTAssertEqual(t2.state.progress, 0)

        let t3 = NotchTeleprompterEngine.tick(t2.state, deltaTime: 0.25, scrollableDistance: 1000)
        XCTAssertFalse(t3.didAdvance)
        XCTAssertEqual(t3.state.progress, 0)

        // Crossing 0.85s (0.75 + 0.25 = 1.00s): advances one discrete 0.85s step -> 85 / 1000 = 0.085
        let t4 = NotchTeleprompterEngine.tick(t3.state, deltaTime: 0.25, scrollableDistance: 1000)
        XCTAssertTrue(t4.didAdvance)
        XCTAssertEqual(t4.state.progress, 0.085, accuracy: 0.0001)
    }

    // MARK: - 10. Separate Reader Window Placement & Display Changes

    func testReaderWindowOpensBelowTopEdgeOfNotchedAndNotchlessDisplays() {
        // Notched display: 1512x982, menu bar/notch top inset 38pt, visibleFrame maxY 944
        let notchedFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notchedVisible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let frame1 = NotchTeleprompterWindowLayout.readerWindowFrame(
            size: CGSize(width: 560, height: 184),
            screenFrame: notchedFrame,
            visibleFrame: notchedVisible,
            topInset: 38,
            gapBelowTopEdge: 10
        )
        XCTAssertEqual(frame1.midX, notchedFrame.midX, accuracy: 1.0)
        XCTAssertEqual(frame1.maxY, 944 - 10, accuracy: 1.0)
        XCTAssertLessThanOrEqual(frame1.maxY, notchedFrame.maxY - 38)

        // Secondary display on the right, smaller height
        let smallDisplay = CGRect(x: 1512, y: 100, width: 400, height: 220)
        let smallVisible = CGRect(x: 1512, y: 100, width: 400, height: 195)
        let frame2 = NotchTeleprompterWindowLayout.readerWindowFrame(
            size: CGSize(width: 560, height: 184),
            screenFrame: smallDisplay,
            visibleFrame: smallVisible,
            topInset: 0,
            gapBelowTopEdge: 10
        )
        XCTAssertGreaterThanOrEqual(frame2.minX, smallVisible.minX + NotchTeleprompterLimits.screenHorizontalMargin)
        XCTAssertLessThanOrEqual(frame2.maxX, smallVisible.maxX - NotchTeleprompterLimits.screenHorizontalMargin)
        XCTAssertGreaterThanOrEqual(frame2.minY, smallVisible.minY + NotchTeleprompterLimits.screenBottomMargin)
        XCTAssertLessThanOrEqual(frame2.maxY, smallVisible.maxY)
    }

    // MARK: - 11. Invariant: Advance Only While Visible & Playing

    func testAdvanceInvariantBlocksEveryHiddenOrPausedCombination() {
        let base = NotchTeleprompterState(
            script: "Invariant check",
            settings: NotchTeleprompterSettings(speedPointsPerSecond: 44, fontSize: 22, progress: 0.2, mode: .editor),
            isTabEnabled: true,
            isIslandVisible: true,
            isReaderWindowVisible: false
        )
        // Editor mode only (no reader visible)
        XCTAssertFalse(base.isAnyReaderVisible)
        XCTAssertFalse(base.canAdvance)

        // Play from Island editor switches into inline reader and allows advance
        let played = NotchTeleprompterEngine.play(base)
        XCTAssertEqual(played.mode, .reader)
        XCTAssertTrue(played.canAdvance)

        // Switching back to editor without reader window pauses playback
        let backToEditor = NotchTeleprompterEngine.setMode(played, mode: .editor)
        XCTAssertFalse(backToEditor.isPlaying)
        XCTAssertFalse(backToEditor.canAdvance)
    }
}
