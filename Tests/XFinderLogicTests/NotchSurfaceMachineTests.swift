import XCTest
import Foundation

final class NotchSurfaceMachineTests: XCTestCase {
    typealias M = NotchSurfaceMachine
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    let s = M.Settings()

    func holding(_ n: Int) -> M.Machine { var m = M.Machine(); m.itemCount = n; return m }

    func testInlineSettingsSurvivesPointerLeaveAndAllowsFileDropsToOpenTray() {
        var machine = holding(0)
        machine.handle(.openExtra(.settings), settings: s, now: t0)
        machine.handle(.pointerAway(since: t0), settings: s, now: at(2))
        XCTAssertEqual(machine.activeExtra, .settings)
        XCTAssertTrue(machine.state.isOpen)
        machine.handle(.fileDragInZone, settings: s, now: at(3))
        XCTAssertNil(machine.activeExtra)
        XCTAssertEqual(machine.state, .expanded(.files))
    }

    // MARK: Opening straight onto a page (D0c)

    func testActivateOnOpensStraightOnThePageAndOnlySwitchesWhenAlreadyOpen() {
        var m = holding(0)
        m.handle(.activateOn(.clipboard), settings: s, now: t0)
        XCTAssertEqual(m.state, .expanded(.clipboard), "one transition, no tray page in between")
        XCTAssertEqual(m.anchor, .notch)
        m.handle(.activateOn(.nowPlaying), settings: s, now: t0)
        XCTAssertEqual(m.state, .expanded(.nowPlaying), "already open ⇒ just the page")
        var pointer = holding(2); pointer.handle(.shake, settings: s, now: t0)
        XCTAssertEqual(pointer.anchor, .pointer)
        pointer.handle(.activateOn(.clipboard), settings: s, now: t0)
        XCTAssertEqual(pointer.anchor, .pointer, "a tray already at the pointer is not yanked to the notch")
        var off = M.Settings(); off.enabled = false
        var closed = holding(0); closed.handle(.activateOn(.clipboard), settings: off, now: t0)
        XCTAssertEqual(closed.state, .collapsed, "disabled surface never opens")
    }

    // MARK: Hover

    func testDirectAIUsageSelectionOpensEvenAfterPointerLeaveCollapsedTheIsland() {
        var machine = holding(0)
        machine.handle(.activateOn(.files), settings: s, now: t0)
        machine.handle(.pointerAway(since: t0), settings: s, now: at(1))
        XCTAssertEqual(machine.state, .collapsed)

        machine.handle(.activateOn(.aiUsage), settings: s, now: at(1.1))
        XCTAssertEqual(machine.state, .expanded(.aiUsage))
        XCTAssertNil(machine.activeExtra)
    }

    func testHoverNeedsDwellAndHeldFiles() {
        var m = holding(2)
        m.handle(.hoverInZone(since: at(0)), settings: s, now: at(0.1))
        XCTAssertEqual(m.state, .collapsed, "a 100 ms pass over the notch is not a hover")
        m.handle(.hoverInZone(since: at(0)), settings: s, now: at(0.3))
        XCTAssertEqual(m.state, .peek)
        XCTAssertEqual(m.anchor, .notch)
    }

    /// P10 — OneNotch's "AI edge": resting on the agent tile opens the Agents page whatever `hoverOpens` says, after the
    /// same dwell, only when the switch is on, the Agents page is shown, and hover itself is allowed.
    func testPointingAtTheAgentEdgeOpensTheAgents() {
        var edge = M.Settings(); edge.agentEdgeHover = true; edge.pointerOnAgentEdge = true
        var m = holding(2)
        m.handle(.hoverInZone(since: at(0)), settings: edge, now: at(0.1))
        XCTAssertEqual(m.state, .collapsed, "the dwell still applies")
        m.handle(.hoverInZone(since: at(0)), settings: edge, now: at(0.3))
        XCTAssertEqual(m.state, .expanded(.agents), "not the peek of the held files")
        var off = edge; off.agentEdgeHover = false
        var n = holding(2); n.handle(.hoverInZone(since: at(0)), settings: off, now: at(0.3))
        XCTAssertEqual(n.state, .peek, "switch off ⇒ the ordinary hover")
        var hidden = edge; hidden.shownPages = [.files, .clipboard]
        var h = holding(2); h.handle(.hoverInZone(since: at(0)), settings: hidden, now: at(0.3))
        XCTAssertEqual(h.state, .peek, "a hidden Agents page is never opened by a hover")
        var noHover = edge; noHover.hoverToPeek = false
        var q = holding(2); q.handle(.hoverInZone(since: at(0)), settings: noHover, now: at(0.3))
        XCTAssertEqual(q.state, .collapsed, "the master hover switch still wins")
    }

    /// CLAUDE.md Part 3c: hover-to-open only reveals files already held, never an empty tray.
    func testHoverNeverRevealsAnEmptyTray() {
        var m = holding(0)
        m.handle(.hoverInZone(since: at(0)), settings: s, now: at(10))
        XCTAssertEqual(m.state, .collapsed)
    }

    func testHoverSwitchOffNeverPeeks() {
        var off = s; off.hoverToPeek = false
        var m = holding(3); m.handle(.hoverInZone(since: at(0)), settings: off, now: at(5))
        XCTAssertEqual(m.state, .collapsed, "the switch must gate the behaviour (dropTray.hoverEnabled was a dead key)")
    }

    func testHoverNeverShrinksAnOpenSurface() {
        var m = holding(1); m.handle(.activate, settings: s, now: t0)
        m.handle(.hoverInZone(since: at(0)), settings: s, now: at(5))
        XCTAssertEqual(m.state, .expanded(.files))
    }

    // MARK: Drag into the notch

    func testFileDragIntoNotchExpandsAtTheNotchAndRespectsItsSwitch() {
        var m = M.Machine(); m.handle(.fileDragInZone, settings: s, now: t0)
        XCTAssertEqual(m.state, .expanded(.files)); XCTAssertEqual(m.anchor, .notch)
        var off = s; off.dragIntoNotchOpens = false
        var m2 = M.Machine(); m2.handle(.fileDragInZone, settings: off, now: t0)
        XCTAssertEqual(m2.state, .collapsed, "dropTray.notchDropEnabled was a dead key — it must gate now")
    }

    func testADragReachingTheNotchDoesNotYankAPointerTrayAway() {
        var m = M.Machine(); m.handle(.shake, settings: s, now: t0)
        XCTAssertEqual(m.anchor, .pointer)
        m.handle(.fileDragInZone, settings: s, now: at(1))
        XCTAssertEqual(m.anchor, .pointer, "moving the tray under a live drag pulls the target from the hand")
    }

    // MARK: Shake

    func testShakeOpensAtThePointerOnlyWhenEnabled() {
        var m = M.Machine(); m.handle(.shake, settings: s, now: t0)
        XCTAssertEqual(m.state, .expanded(.files)); XCTAssertEqual(m.anchor, .pointer)
        var off = s; off.shakeOpens = false
        var m2 = M.Machine(); m2.handle(.shake, settings: off, now: t0); XCTAssertEqual(m2.state, .collapsed)
    }

    func testShakeDoesNotTeleportAnAlreadyOpenNotchSurface() {
        var m = M.Machine(); m.handle(.fileDragInZone, settings: s, now: t0)
        m.handle(.shake, settings: s, now: at(1))
        XCTAssertEqual(m.anchor, .notch)
    }

    // MARK: Leaving

    func testLeavingCollapsesAfterGraceNotBefore() {
        var m = M.Machine(); m.handle(.fileDragInZone, settings: s, now: t0)
        m.handle(.pointerAway(since: at(1)), settings: s, now: at(1.25)); XCTAssertEqual(m.state, .expanded(.files), "250 ms is within grace")
        m.handle(.pointerAway(since: at(1)), settings: s, now: at(1.5)); XCTAssertEqual(m.state, .collapsed)
    }

    /// The reported "khay đóng nhanh quá" bug, for the shaken-open tray: holding files, it stays.
    func testAShakenTrayHoldingFilesNeverAutoCloses() {
        var m = M.Machine(); m.handle(.shake, settings: s, now: t0)
        m.handle(.dropped(count: 3), settings: s, now: at(1))
        m.handle(.pointerAway(since: at(2)), settings: s, now: at(600))
        XCTAssertEqual(m.state, .expanded(.files)); XCTAssertEqual(m.anchor, .pointer)
        m.handle(.dismiss, settings: s, now: at(601))
        XCTAssertEqual(m.state, .collapsed, "only the explicit close button puts it away")
        XCTAssertEqual(m.itemCount, 3, "closing never touches the staged files")
    }

    func testAnEmptyShakenTrayStillGetsOutOfTheWay() {
        var m = M.Machine(); m.handle(.shake, settings: s, now: t0)
        m.handle(.pointerAway(since: at(1)), settings: s, now: at(2))
        XCTAssertEqual(m.state, .collapsed)
    }

    /// At the notch, collapsing keeps the files: the count stays and the badge shows it.
    func testNotchSurfaceCollapsesToTheBadgeAndComesBackWithTheSameFiles() {
        var m = M.Machine(); m.handle(.fileDragInZone, settings: s, now: t0)
        m.handle(.dropped(count: 3), settings: s, now: at(1))
        XCTAssertEqual(m.state, .expanded(.files), "a drop keeps the surface open — it is the start of the task")
        m.handle(.pointerAway(since: at(2)), settings: s, now: at(10))
        XCTAssertEqual(m.state, .collapsed)
        XCTAssertEqual(m.itemCount, 3)
        m.handle(.hoverInZone(since: at(11)), settings: s, now: at(11.3))
        XCTAssertEqual(m.state, .peek, "hovering the badge peeks the held files")
        m.handle(.activate, settings: s, now: at(12))
        XCTAssertEqual(m, M.Machine(state: .expanded(.files), anchor: .notch, itemCount: 3, taskRunning: false))
    }

    func testPeekCollapsesWhenTheLastFileIsRemovedElsewhere() {
        var m = holding(1); m.handle(.hoverInZone(since: t0), settings: s, now: at(1))
        XCTAssertEqual(m.state, .peek)
        m.handle(.itemsChanged(count: 0), settings: s, now: at(2))
        XCTAssertEqual(m.state, .collapsed)
    }

    func testPointerOnSurfaceKeepsItOpenIndefinitely() {
        var m = M.Machine(); m.handle(.fileDragInZone, settings: s, now: t0)
        for i in 1...50 { m.handle(.pointerOnSurface, settings: s, now: at(Double(i))) }
        XCTAssertEqual(m.state, .expanded(.files))
    }

    // MARK: Master switch

    func testDisabledCollapsesAndNothingOpens() {
        var d = M.Machine(); d.handle(.shake, settings: s, now: t0); d.handle(.dropped(count: 2), settings: s, now: t0)
        d.handle(.disabled, settings: s, now: at(1)); XCTAssertEqual(d.state, .collapsed); XCTAssertEqual(d.anchor, .notch)
        var off = s; off.enabled = false
        var m = holding(4)
        for e in [M.Event.fileDragInZone, .shake, .activate, .dropped(count: 5), .hoverInZone(since: t0)] {
            m.handle(e, settings: off, now: at(9))
            XCTAssertEqual(m.state, .collapsed, "master off ⇒ \(e) opens nothing")
        }
    }

    // MARK: Exhaustive invariants

    /// Every sequence of ≤ 4 events (8 kinds ⇒ 4 681 paths). After the pointer has been away past
    /// grace, the surface is open ONLY in the one sanctioned case — a shaken tray holding files —
    /// and an explicit dismiss always closes it. This is the "never closes" bug as a property.
    func testNoShortSequenceLeavesTheSurfaceStuckOpen() {
        let events: [M.Event] = [.hoverInZone(since: t0), .fileDragInZone, .shake, .activate,
                                 .dropped(count: 2), .itemsChanged(count: 0), .pointerOnSurface, .dismiss,
                                 .taskStarted, .taskEnded, .activityShown, .activityEnded, .feedbackShown,
                                 .switchPage(.clipboard), .switchPage(.files)]
        var visited = 0, stuck = 0, undismissable = 0
        func walk(_ m: M.Machine, _ depth: Int) {
            visited += 1
            var away = m; away.handle(.pointerAway(since: at(100)), settings: s, now: at(200))
            // A shaken-open tray holding files never auto-closes, whichever page it shows.
            var pointerTrayWithFiles = false
            if case .expanded = away.state, away.anchor == .pointer, away.itemCount > 0 { pointerTrayWithFiles = true }
            let sanctioned = pointerTrayWithFiles || away.taskRunning
                || away.state == .activity                          // a notice ends on its timer, not on the pointer
            var ended = m; ended.handle(.activityEnded, settings: s, now: at(250))
            if ended.state == .activity { undismissable += 1 }
            if away.state.isOpen && !sanctioned { stuck += 1 }
            var closed = m; closed.handle(.dismiss, settings: s, now: at(300))
            if closed.state != .collapsed || closed.anchor != .notch { undismissable += 1 }
            guard depth < 4 else { return }
            for e in events { var n = m; n.handle(e, settings: s, now: at(Double(depth) + 1)); walk(n, depth + 1) }
        }
        walk(M.Machine(), 0)
        XCTAssertEqual(visited, 54241, "the walk must cover the whole tree (15 events, depth 4)")
        XCTAssertEqual(stuck, 0)
        XCTAssertEqual(undismissable, 0)
    }

    /// No sequence can show the peek strip while the tray is empty — peek exists to show held files.
    func testPeekIsNeverEmpty() {
        let events: [M.Event] = [.hoverInZone(since: t0), .dropped(count: 1), .itemsChanged(count: 0),
                                 .itemsChanged(count: 2), .dismiss, .pointerAway(since: t0), .feedbackShown, .activityEnded]
        var bad = 0
        func walk(_ m: M.Machine, _ depth: Int) {
            if m.state == .peek && m.itemCount == 0 { bad += 1 }
            guard depth < 5 else { return }
            for e in events { var n = m; n.handle(e, settings: s, now: at(50)); walk(n, depth + 1) }
        }
        walk(M.Machine(), 0)
        XCTAssertEqual(bad, 0)
    }

    func testARunningTaskKeepsTheHubOpenButCloseStillCloses() {
        var m = holding(2); m.handle(.activate, settings: s, now: t0)
        m.handle(.taskStarted, settings: s, now: t0)
        m.handle(.pointerAway(since: at(1)), settings: s, now: at(60))
        XCTAssertEqual(m.state, .expanded(.files), "progress must not vanish mid-job")
        m.handle(.taskEnded, settings: s, now: at(61))
        m.handle(.pointerAway(since: at(61)), settings: s, now: at(63))
        XCTAssertEqual(m.state, .collapsed)
        var d = holding(1); d.handle(.activate, settings: s, now: t0); d.handle(.taskStarted, settings: s, now: t0)
        d.handle(.dismiss, settings: s, now: at(1))
        XCTAssertEqual(d.state, .collapsed, "the close button always closes")
    }

    /// P6: while the person types a reply on the Agents page, leaving the notch must not throw the text away.
    func testComposingAReplyKeepsTheHubOpenButCloseStillCloses() {
        var c = s; c.composing = true
        var m = M.Machine(); m.handle(.activateOn(.agents), settings: c, now: t0)
        m.handle(.pointerAway(since: at(1)), settings: c, now: at(60))
        XCTAssertEqual(m.state, .expanded(.agents), "a half-typed reply must not vanish when the pointer wanders")
        m.handle(.pointerAway(since: at(61)), settings: s, now: at(63))
        XCTAssertEqual(m.state, .collapsed, "done composing ⇒ the ordinary leave rule again")
        var d = M.Machine(); d.handle(.activateOn(.agents), settings: c, now: t0)
        d.handle(.dismiss, settings: c, now: at(1))
        XCTAssertEqual(d.state, .collapsed, "the close button always closes")
    }

    func testAnActivityShowsOnlyWhileIdleAndYieldsToTheUser() {
        var m = M.Machine(); m.handle(.activityShown, settings: s, now: t0)
        XCTAssertEqual(m.state, .activity)
        m.handle(.pointerAway(since: t0), settings: s, now: at(10))
        XCTAssertEqual(m.state, .activity, "the pointer is usually elsewhere; the timer ends a notice")
        m.handle(.activityEnded, settings: s, now: at(11))
        XCTAssertEqual(m.state, .collapsed)
        var hub = M.Machine(); hub.handle(.activate, settings: s, now: t0)
        hub.handle(.activityShown, settings: s, now: at(1))
        XCTAssertEqual(hub.state, .expanded(.files), "a notice never interrupts the open hub")
        var drag = M.Machine(); drag.handle(.activityShown, settings: s, now: t0)
        drag.handle(.fileDragInZone, settings: s, now: at(1))
        XCTAssertEqual(drag.state, .expanded(.files), "a file drag takes over from a notice")
        drag.handle(.activityEnded, settings: s, now: at(2))
        XCTAssertEqual(drag.state, .expanded(.files), "the notice's timer must not close the hub that replaced it")
        var held = holding(2); held.handle(.activityShown, settings: s, now: t0)
        held.handle(.hoverInZone(since: at(1)), settings: s, now: at(2))
        XCTAssertEqual(held.state, .peek, "hovering during a notice still peeks the held files")
    }

    /// Volume / brightness feedback replaces a passive peek (the key was swallowed — nothing else answers) but never the hub.
    func testKeyFeedbackReplacesAPeekButNotTheHub() {
        var peek = holding(2); peek.handle(.hoverInZone(since: t0), settings: s, now: at(5))
        XCTAssertEqual(peek.state, .peek)
        peek.handle(.feedbackShown, settings: s, now: at(6))
        XCTAssertEqual(peek.state, .activity, "the level shows over the peek")
        peek.handle(.activityEnded, settings: s, now: at(8))
        XCTAssertEqual(peek.state, .peek, "the peek comes back when the level is gone — it still holds 2 files")
        peek.handle(.pointerAway(since: at(8)), settings: s, now: at(10))
        XCTAssertEqual(peek.state, .collapsed, "and leaves with the pointer like any peek")
        var notice = holding(2); notice.handle(.hoverInZone(since: t0), settings: s, now: at(5))
        notice.handle(.activityShown, settings: s, now: at(6))
        XCTAssertEqual(notice.state, .peek, "an ordinary notice still never interrupts a peek")
        var idle = M.Machine(); idle.handle(.feedbackShown, settings: s, now: t0)
        XCTAssertEqual(idle.state, .activity)
        var hub = M.Machine(); hub.handle(.activateOn(.nowPlaying), settings: s, now: t0)
        hub.handle(.feedbackShown, settings: s, now: at(1))
        XCTAssertEqual(hub.state, .expanded(.nowPlaying), "the open hub is never taken over — macOS answers the key there")
    }

    /// A peek over a playing track comes back after the level; one with nothing left to show does not, and a notice that
    /// interrupted nothing still ends in `collapsed`.
    func testThePeekReturnsAfterKeyFeedbackOnlyWhileItHasSomethingToShow() {
        var track = s; track.nowPlayingActive = true
        var m = M.Machine(); m.handle(.hoverInZone(since: t0), settings: track, now: at(5))
        XCTAssertEqual(m.state, .peek)
        m.handle(.feedbackShown, settings: track, now: at(6))
        m.handle(.activityEnded, settings: track, now: at(8))
        XCTAssertEqual(m.state, .peek, "a playing track is never empty")
        var stopped = M.Machine(); stopped.handle(.hoverInZone(since: t0), settings: track, now: at(5))
        stopped.handle(.feedbackShown, settings: track, now: at(6))
        stopped.handle(.activityEnded, settings: s, now: at(8))          // the track ended meanwhile, nothing held
        XCTAssertEqual(stopped.state, .collapsed)
        var emptied = holding(2); emptied.handle(.hoverInZone(since: t0), settings: s, now: at(5))
        emptied.handle(.feedbackShown, settings: s, now: at(6))
        emptied.handle(.itemsChanged(count: 0), settings: s, now: at(7))
        emptied.handle(.activityEnded, settings: s, now: at(8))
        XCTAssertEqual(emptied.state, .collapsed, "the tray was emptied during the level")
        var idle = holding(2); idle.handle(.feedbackShown, settings: s, now: t0)
        idle.handle(.activityEnded, settings: s, now: at(2))
        XCTAssertEqual(idle.state, .collapsed, "feedback over nothing returns to nothing")
        var reopened = holding(2); reopened.handle(.hoverInZone(since: t0), settings: s, now: at(5))
        reopened.handle(.feedbackShown, settings: s, now: at(6))
        reopened.handle(.activate, settings: s, now: at(7))
        reopened.handle(.dismiss, settings: s, now: at(8))
        reopened.handle(.feedbackShown, settings: s, now: at(9))
        reopened.handle(.activityEnded, settings: s, now: at(10))
        XCTAssertEqual(reopened.state, .collapsed, "the old peek is forgotten once anything else was shown")
    }

    /// §3b #33 — a meeting alert has buttons; the pointer that comes to press one must not turn it into a peek.
    func testANoticeWithButtonsHoldsTheHover() {
        var hold = s; hold.activityHoldsHover = true
        var m = holding(2); m.handle(.activityShown, settings: hold, now: t0)
        m.handle(.hoverInZone(since: at(1)), settings: hold, now: at(5))
        XCTAssertEqual(m.state, .activity, "the buttons stay under the pointer")
        m.handle(.fileDragInZone, settings: hold, now: at(6))
        XCTAssertEqual(m.state, .expanded(.files), "a file drag still takes over — only the hover is held")
        var plain = holding(2); plain.handle(.activityShown, settings: s, now: t0)
        plain.handle(.hoverInZone(since: at(1)), settings: s, now: at(5))
        XCTAssertEqual(plain.state, .peek, "a notice without buttons still yields to the hover")
    }

    // MARK: B5 — the clipboard page

    func testSwitchPageOnlyChangesAnOpenHub() {
        var m = M.Machine(); m.handle(.switchPage(.clipboard), settings: s, now: t0)
        XCTAssertEqual(m.state, .collapsed, "a page switch never opens the surface")
        m.handle(.activate, settings: s, now: t0)
        m.handle(.switchPage(.clipboard), settings: s, now: at(1))
        XCTAssertEqual(m.state, .expanded(.clipboard))
        XCTAssertEqual(m.anchor, .notch); XCTAssertEqual(m.itemCount, 0)
        m.handle(.switchPage(.files), settings: s, now: at(2))
        XCTAssertEqual(m.state, .expanded(.files))
        var p = holding(2); p.handle(.hoverInZone(since: t0), settings: s, now: at(1))
        XCTAssertEqual(p.state, .peek)
        p.handle(.switchPage(.clipboard), settings: s, now: at(2))
        XCTAssertEqual(p.state, .peek, "a peek is not a hub; it has no tabs")
    }

    /// N2: the default (peek) never opens an empty tray; a fixed choice opens that page even over held files;
    /// By activity opens the tray page for held files; the master hover switch gates all of it.
    func testHoverOpensTheChosenPageAndPeekStaysTheDefault() {
        var m = M.Machine(); m.handle(.hoverInZone(since: t0), settings: s, now: at(1))
        XCTAssertEqual(m.state, .collapsed, "default: an empty tray never opens on hover")
        var on = s; on.hoverOpens = .clipboard
        var e = M.Machine(); e.handle(.hoverInZone(since: t0), settings: on, now: at(1))
        XCTAssertEqual(e.state, .expanded(.clipboard))
        var h = holding(3); h.handle(.hoverInZone(since: t0), settings: on, now: at(1))
        XCTAssertEqual(h.state, .expanded(.clipboard), "a fixed choice is that page, files or not")
        var act = s; act.hoverOpens = .activity
        var a = holding(3); a.handle(.hoverInZone(since: t0), settings: act, now: at(1))
        XCTAssertEqual(a.state, .expanded(.files), "By activity: held files open the tray page")
        var off = on; off.hoverToPeek = false
        var d = M.Machine(); d.handle(.hoverInZone(since: t0), settings: off, now: at(1))
        XCTAssertEqual(d.state, .collapsed, "the master hover switch gates all of it")
    }

    func testEveryOpenPathStillLandsOnTheFilesPage() {
        for e in [M.Event.fileDragInZone, .shake, .activate, .dropped(count: 1)] {
            var m = M.Machine(); m.handle(e, settings: s, now: t0)
            XCTAssertEqual(m.state, .expanded(.files), "\(e)")
        }
    }

    /// Phase 1: leaving the pointer away during a drag-in, drop-hover, async import, or drag-out session
    /// must NEVER close the tray; once the drag ends, normal leave grace applies and explicit dismiss still closes.
    func testPointerAwayDuringActiveDragNeverClosesTheTray() {
        var dragging = s; dragging.dragging = true
        var m = holding(3)
        m.handle(.activate, settings: dragging, now: t0)
        XCTAssertEqual(m.state, .expanded(.files))

        m.handle(.pointerAway(since: at(1)), settings: dragging, now: at(60))
        XCTAssertEqual(m.state, .expanded(.files), "leaving the tray mid-drag must not collapse it")

        // Once the drag ends, leaving past grace collapses normally.
        m.handle(.pointerAway(since: at(61)), settings: s, now: at(63))
        XCTAssertEqual(m.state, .collapsed, "after drag ends, normal leave grace closes the tray")

        // Explicit dismiss still closes even if dragging is flagged.
        var d = holding(2)
        d.handle(.activate, settings: dragging, now: t0)
        d.handle(.dismiss, settings: dragging, now: at(1))
        XCTAssertEqual(d.state, .collapsed, "explicit dismiss always closes")
    }

    /// Ref-29 Pin toggle: leaving the pointer away while pinned keeps any expanded hub page open
    /// (even with 0 held files), while unpinning restores normal leaveGrace and explicit dismiss/disabled still close.
    func testPinnedHubStaysOpenWhenPointerLeavesButDismissStillCloses() {
        var pinned = s; pinned.pinned = true
        var m = M.Machine()
        m.handle(.activateOn(.nowPlaying), settings: pinned, now: t0)
        XCTAssertEqual(m.state, .expanded(.nowPlaying))

        m.handle(.pointerAway(since: at(1)), settings: pinned, now: at(120))
        XCTAssertEqual(m.state, .expanded(.nowPlaying), "pinned hub stays open on pointerAway")

        m.handle(.pointerAway(since: at(121)), settings: s, now: at(123))
        XCTAssertEqual(m.state, .collapsed, "unpinning restores normal leave grace")

        var d = M.Machine()
        d.handle(.activateOn(.files), settings: pinned, now: t0)
        d.handle(.dismiss, settings: pinned, now: at(1))
        XCTAssertEqual(d.state, .collapsed, "explicit dismiss always closes even when pinned")
    }
}

