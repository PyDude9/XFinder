import XCTest
import Foundation
import CoreGraphics

final class NotchSurfaceLayoutTests: XCTestCase {
    typealias L = NotchSurfaceLayout
    typealias S = NotchSurfaceMachine.State
    // This MacBook Pro, measured: 1728×1117 screen, aux areas 771.5 wide × 32 tall ⇒ notch 185×32.
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let visible = CGRect(x: 0, y: 70, width: 1728, height: 1015)   // menu bar 32, Dock 70
    let auxL = CGRect(x: 0, y: 1085, width: 771.5, height: 32)
    let auxR = CGRect(x: 956.5, y: 1085, width: 771.5, height: 32)
    let external = CGRect(x: 1728, y: 0, width: 2560, height: 1440)
    var notch: CGRect { L.notch(screen: screen, auxLeft: auxL, auxRight: auxR) }

    func testRealNotchComesFromTheAuxiliaryAreas() {
        XCTAssertEqual(notch, CGRect(x: 771.5, y: 1085, width: 185, height: 32))
    }

    func testNotchlessScreenGetsAZeroHeightStandInAtTheTopCentre() {
        let n = L.notch(screen: external, auxLeft: nil, auxRight: nil)
        XCTAssertEqual(n.height, 0); XCTAssertEqual(n.midX, external.midX); XCTAssertEqual(n.minY, external.maxY)
    }

    func testNotchFramesAreGluedToTheTopAndCentredOnTheNotch() {
        for state in [S.peek, .expanded(.files), .collapsed] {
            guard let f = L.frame(for: state, anchor: .notch, itemCount: 3, notch: notch, screen: screen,
                                  visible: visible, pointer: .zero) else { return XCTFail("\(state) drew nothing") }
            XCTAssertEqual(f.maxY, screen.maxY, "\(state)")
            XCTAssertEqual(f.midX, notch.midX, accuracy: 0.001, "\(state)")
            XCTAssertGreaterThanOrEqual(f.width, notch.width, "\(state) must at least cover the notch")
            if state == .collapsed {
                XCTAssertEqual(f.height, notch.height, "P1: collapsed is notch-high, visible through its wings")
                XCTAssertGreaterThan(f.width, notch.width, "collapsed must reach past the notch or it is invisible")
            } else {
                XCTAssertGreaterThan(f.height, notch.height, "\(state) must reach below the notch or it is invisible")
            }
        }
    }

    /// P1 (measured on the owner's OneNotch screenshots): two bodies only — NARROW 382 × 168 (tray, Now Playing) and
    /// WIDE 612 × 182 (Clipboard, Agents), the calendar 188 tall — each plus a 19-pt flare per side at the notch.
    func testPagesUseTheTwoMeasuredBodiesPlusTheFlares() {
        let fl = 2 * L.Metrics.standard.topFillet
        XCTAssertEqual(fl, 38, "650 top edge − 612 body, measured")
        let files = L.size(for: .expanded(.files), anchor: .notch, itemCount: 1, notch: notch)!
        let player = L.size(for: .expanded(.nowPlaying), anchor: .notch, itemCount: 1, notch: notch)!
        let clip = L.size(for: .expanded(.clipboard), anchor: .notch, itemCount: 1, notch: notch)!
        let agents = L.size(for: .expanded(.agents), anchor: .notch, itemCount: 1, notch: notch)!
        let cal = L.size(for: .expanded(.calendar), anchor: .notch, itemCount: 1, notch: notch)!
        XCTAssertEqual(player, CGSize(width: 382 + fl, height: 168), "Now Playing: 382 × 168 measured")
        XCTAssertEqual(files, player, "the tray shares the narrow body")
        XCTAssertEqual(clip, CGSize(width: 612 + fl, height: 182), "Clipboard: 612 × 182 measured")
        XCTAssertEqual(agents, clip, "Agents shares the wide body")
        XCTAssertEqual(cal, CGSize(width: 382 + fl, height: 188), "the calendar view is taller")
        let pointerClip = L.size(for: .expanded(.clipboard), anchor: .pointer, itemCount: 1, notch: notch)!
        XCTAssertEqual(pointerClip, CGSize(width: 612, height: 182), "a pointer tray has no top edge to flare into, but keeps the band")
        let f = L.frame(for: .expanded(.clipboard), anchor: .notch, itemCount: 1, notch: notch, screen: screen, visible: visible, pointer: .zero)!
        XCTAssertEqual(f.midX, notch.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(f.minX, 0); XCTAssertLessThanOrEqual(f.maxX, screen.width)
    }

    /// P1: the collapsed surface is exactly as tall as the notch (nothing hangs over the title bars below it) and
    /// widens sideways — a wing each side, the fuller side setting both so the camera stays centred.
    /// The two pages that fill their body to the point: the sum lives in one place now, and a drift on either side (a
    /// taller card, a new inset) shows up here instead of as a clipped deck nobody measured (P1 review, mutation M49).
    func testPageBudgetsFillTheirBodiesExactly() {
        let m = L.Metrics.standard
        XCTAssertEqual(m.clipboardTopInset + m.chipRowHeight + m.chipToDeckGap + m.clipCardHeight + m.clipboardBottomInset,
                       m.expandedDrop(for: .clipboard), accuracy: 0.001, "clipboard: chip row + card row fill the wide body")
        XCTAssertEqual(m.pageTopInset + m.artworkSide + m.artworkToProgressGap + m.progressAreaHeight + m.pageBottomInset,
                       m.expandedDrop(for: .nowPlaying), accuracy: 0.001, "now playing: artwork row + progress fill the narrow body")
        // Three and a half cards show in the wide body — the half card is what says "this row scrolls".
        let visible = (m.wideWidth - 2 * 14 + m.clipCardGap) / (m.clipCardWidth + m.clipCardGap)
        XCTAssertGreaterThan(visible, 3.2); XCTAssertLessThan(visible, 3.8)
        // P2 pages: Agents (wide), and the three tools (one height).
        XCTAssertEqual(m.pageTopInset + m.agentsHeaderHeight + m.agentsHeaderGap + 2 * m.agentRowHeight + m.agentRowGap
                       + m.pageBottomInset, m.expandedDrop(for: .agents), accuracy: 0.001, "agents: header + two rows")
        XCTAssertEqual(m.pageTopInset + m.usageHeaderHeight + m.usageHeaderGap + m.usageColumnsHeight + m.pageBottomInset,
                       m.expandedDrop(for: .aiUsage), accuracy: 0.001, "AI usage: header + columns")
        XCTAssertEqual(m.pageTopInset + m.calendarHeaderHeight + m.calendarHeaderGap + m.calendarStripHeight
                       + m.calendarStripGap + m.calendarListHeight + m.pageBottomInset,
                       m.expandedDrop(for: .calendar), accuracy: 0.001, "calendar: header + strip + list")
        XCTAssertEqual(m.pageTopInset + m.timerTitleHeight + m.timerTitleGap + m.timerTimeHeight + m.timerTimeGap
                       + m.timerRulerHeight + m.timerRulerGap + m.timerControlsHeight + m.pageBottomInset,
                       m.expandedDrop(for: .timer), accuracy: 0.001, "timer: title + time + ruler + controls")
        XCTAssertEqual(m.expandedDrop(for: .timer), m.expandedDrop(for: .calendar), "every tool has the same height")
        XCTAssertEqual(m.expandedDrop(for: .aiUsage), m.expandedDrop(for: .calendar))
        XCTAssertTrue(L.Metrics.isWide(.aiUsage)); XCTAssertFalse(L.Metrics.isWide(.timer)); XCTAssertFalse(L.Metrics.isWide(.calendar))
    }

    /// P2 review: three tools + a separate ✕ needed 93 pt in a narrow page's 86.5-pt right wing. Every page, every tool and
    /// every dot page at once must fit both wings (the ✕ is the toolbar's last slot; the clipboard's left wing also holds
    /// the 24-pt search circle).
    func testTheBandsCapsulesFitTheirWings() {
        let m = L.Metrics.standard
        let tools = NotchPages.toolbar(NotchPages.defaultOrder).count
        let dots = NotchPages.dots(NotchPages.defaultOrder).count
        XCTAssertEqual(tools, 3); XCTAssertEqual(dots, 4)
        for page in NotchSurfaceMachine.Page.allCases {
            let wing = L.bandWingWidth(bodyWidth: m.expandedWidth(for: page), notchWidth: notch.width)
            XCTAssertLessThanOrEqual(L.toolbarCapsuleWidth(slots: tools + 1), wing, "\(page): tools + close fit the right wing")
            let left = L.dotsCapsuleWidth(dots: dots) + (page == .clipboard ? 8 + 24 : 0)
            XCTAssertLessThanOrEqual(left, wing, "\(page): the dots (and the search circle) fit the left wing")
        }
        XCTAssertEqual(L.dotsCapsuleWidth(dots: 3), 54, accuracy: 0.001, "OneNotch's measured three-dot capsule")
    }

    func testCollapsedIsNotchHighWithSymmetricWings() {
        let m = L.Metrics.standard
        let one = L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, nowPlayingActive: true)!
        XCTAssertEqual(one.height, notch.height, "nothing below the notch")
        XCTAssertEqual(one.width, notch.width + 2 * m.wingMin + 2 * m.collapsedFillet, "one item: the measured 262-pt body")
        XCTAssertEqual(notch.width + 2 * m.wingMin, 262, accuracy: 0.001)
        let busy = L.size(for: .collapsed, anchor: .notch, itemCount: 3, notch: notch, timerActive: true,
                          nowPlayingActive: true, agentActive: true)!
        XCTAssertGreaterThan(busy.width, one.width, "more items widen the wings")
        let w = L.wingWidth(left: [.agent, .files], right: [.music, .timer])
        XCTAssertEqual(busy.width, notch.width + 2 * w + 2 * m.collapsedFillet, "both wings take the fuller side's width")
        XCTAssertEqual(L.wingWidth(left: [], right: []), 0)
        // The wings follow the FULLER side, whichever it is: a track + a countdown with nothing on the left must still
        // widen BOTH wings, or the camera would sit off-centre in the shape (mutation M44).
        let rightHeavy = L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, timerActive: true,
                                nowPlayingActive: true)!
        let rw = L.sideWidth([.music, .timer]) + m.wingInset
        XCTAssertGreaterThan(rw, m.wingMin)
        XCTAssertEqual(rightHeavy.width, notch.width + 2 * rw + 2 * m.collapsedFillet, accuracy: 0.001)
        let sides = L.wingItems(itemCount: 2, timerActive: true, nowPlayingActive: true, agentActive: true)
        XCTAssertEqual(sides.left, [.agent, .files]); XCTAssertEqual(sides.right, [.music, .timer])
    }

    func testSizesGrowBadgeToPeekToExpanded() {
        let b = L.size(for: .collapsed, anchor: .notch, itemCount: 1, notch: notch)!
        let p = L.size(for: .peek, anchor: .notch, itemCount: 1, notch: notch)!
        let e = L.size(for: .expanded(.files), anchor: .notch, itemCount: 1, notch: notch)!
        XCTAssertLessThan(b.width, p.width); XCTAssertLessThan(p.width, e.width)
        XCTAssertLessThan(b.height, p.height); XCTAssertLessThan(p.height, e.height)
    }

    func testCollapsedDrawsNothingWithoutFilesAndAPillOnlyWhenAllowed() {
        XCTAssertNil(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch), "no files ⇒ no badge")
        let v = L.notch(screen: external, auxLeft: nil, auxRight: nil)
        XCTAssertNil(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: v), "nothing held ⇒ no pill either")
        let pill = L.size(for: .collapsed, anchor: .notch, itemCount: 5, notch: v)
        XCTAssertEqual(pill, CGSize(width: L.Metrics.standard.pillWidth, height: L.Metrics.standard.pillHeight), "one item fits the 120-pt pill")
        let wide = L.size(for: .collapsed, anchor: .notch, itemCount: 5, notch: v, timerActive: true, nowPlayingActive: true, agentActive: true)!
        XCTAssertGreaterThanOrEqual(wide.width, L.sideWidth([.agent, .files]) + L.sideWidth([.music, .timer]),
                                    "the pill widens only when its content runs out of room")
        XCTAssertEqual(wide.height, L.Metrics.standard.pillHeight)
        XCTAssertNil(L.size(for: .collapsed, anchor: .notch, itemCount: 5, notch: v, pillOnPlainScreens: false), "the pill is a switch")
        XCTAssertNotNil(L.size(for: .peek, anchor: .notch, itemCount: 5, notch: v))
    }

    /// B7: on a plain screen every state hangs from the bottom of the menu bar, never over it.
    /// D0c (user, after the OneNotch reference): a screen without a notch gets a VIRTUAL one — every state is
    /// flush with the top edge, centred, exactly as at a real notch. B7's "hang under the menu bar" is withdrawn.
    func testPlainScreenSurfacesHangFromTheTopEdgeLikeAVirtualNotch() {
        let ext = CGRect(x: 1728, y: 0, width: 2560, height: 1440)
        let extVisible = CGRect(x: 1728, y: 0, width: 2560, height: 1440 - 24)   // 24 pt menu bar, no Dock
        let v = L.notch(screen: ext, auxLeft: nil, auxRight: nil)
        for state in [S.collapsed, .peek, .expanded(.files), .expanded(.clipboard)] {
            guard let f = L.frame(for: state, anchor: .notch, itemCount: 2, notch: v, screen: ext, visible: extVisible, pointer: .zero)
            else { return XCTFail("\(state) drew nothing") }
            XCTAssertEqual(f.maxY, ext.maxY, accuracy: 0.001, "\(state) is flush with the top edge, over the menu bar's centre")
            XCTAssertEqual(f.midX, ext.midX, accuracy: 0.001)
            XCTAssertLessThanOrEqual(f.maxX, ext.maxX); XCTAssertGreaterThanOrEqual(f.minX, ext.minX)
        }
        let pill = L.pillRect(notch: v, visible: extVisible)
        XCTAssertEqual(pill, L.frame(for: .collapsed, anchor: .notch, itemCount: 2, notch: v, screen: ext, visible: extVisible, pointer: .zero),
                       "one item: the pill is exactly its default size")
        XCTAssertEqual(pill.maxY, ext.maxY, "the pill IS the virtual notch")
        // A real notch is unchanged: glued to the screen top.
        let f = L.frame(for: .collapsed, anchor: .notch, itemCount: 2, notch: notch, screen: screen, visible: visible, pointer: .zero)!
        XCTAssertEqual(f.maxY, screen.maxY)
    }

    func testPointerTraySitsUnderThePointerInsideTheVisibleFrame() {
        let p = CGPoint(x: 900, y: 600)
        let f = L.frame(for: .expanded(.files), anchor: .pointer, itemCount: 0, notch: notch, screen: screen,
                        visible: visible, pointer: p)!
        XCTAssertEqual(f.midX, p.x, accuracy: 0.001)
        XCTAssertEqual(f.maxY, p.y - L.Metrics.standard.pointerGap, accuracy: 0.001, "the tray hangs just below the hand")
        // Near the top-left corner it must be clamped into the visible frame, not under the menu bar.
        let c = L.frame(for: .expanded(.files), anchor: .pointer, itemCount: 0, notch: notch, screen: screen,
                        visible: visible, pointer: CGPoint(x: 5, y: 1110))!
        XCTAssertTrue(visible.contains(c), "\(c) escaped the visible frame \(visible)")
    }

    func testExpandedNeverExceedsTheScreenWidth() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 260)
        let n = L.notch(screen: tiny, auxLeft: nil, auxRight: nil)
        let f = L.frame(for: .expanded(.files), anchor: .notch, itemCount: 0, notch: n, screen: tiny, visible: tiny, pointer: .zero)!
        XCTAssertLessThanOrEqual(f.width, tiny.width); XCTAssertGreaterThanOrEqual(f.minX, tiny.minX)
    }

    /// The strip under the notch is the centre of every window's title bar, so the hover zone NEVER reaches below
    /// the notch (P1: the wings sit beside the camera, in the menu-bar strip). It is the collapsed shape as drawn
    /// while something sits in the wings, else the bare notch.
    func testHoverZoneIsTheDrawnWingsAndNeverReachesBelowTheNotch() {
        let empty = L.hoverZone(notch: notch, screen: screen, itemCount: 0)
        XCTAssertEqual(empty, notch)
        let held = L.hoverZone(notch: notch, screen: screen, itemCount: 2, agentActive: true)
        let drawn = L.size(for: .collapsed, anchor: .notch, itemCount: 2, notch: notch, agentActive: true)!
        XCTAssertEqual(held.maxY, screen.maxY)
        XCTAssertEqual(held.minY, notch.minY, "never the title-bar strip below the notch")
        XCTAssertEqual(held.width, drawn.width, "resting on a wing counts")
        XCTAssertEqual(held.midX, notch.midX, accuracy: 0.001)
        let v = L.notch(screen: external, auxLeft: nil, auxRight: nil)
        let zv = L.hoverZone(notch: v, screen: external, itemCount: 2)
        XCTAssertEqual(zv.height, 8); XCTAssertEqual(zv.maxY, external.maxY, "no pill shown ⇒ the bare strip in the menu bar")
        let extVisible = CGRect(x: external.minX, y: 0, width: external.width, height: external.height - 24)
        let zp = L.hoverZone(notch: v, screen: external, itemCount: 2, visible: extVisible, pillShown: true)
        XCTAssertEqual(zp, L.pillRect(notch: v, visible: extVisible))
        XCTAssertEqual(zp.maxY, external.maxY, "the pill zone sits at the top edge like a notch")
        XCTAssertEqual(zp.height, L.Metrics.standard.pillHeight)
        let zw = L.hoverZone(notch: v, screen: external, itemCount: 2, nowPlayingActive: true, timerActive: true,
                             agentActive: true, visible: extVisible, pillShown: true)
        XCTAssertGreaterThan(zw.width, zp.width, "a widened pill is hovered over its whole width")
    }

    func testDragZoneIsWiderAndDeeperThanTheNotchAndTouchesTheTop() {
        let z = L.dragZone(notch: notch, screen: screen)
        XCTAssertTrue(z.contains(CGPoint(x: notch.midX, y: screen.maxY - 1)))
        XCTAssertGreaterThan(z.width, notch.width)
        XCTAssertGreaterThanOrEqual(z.height, notch.height)
        XCTAssertEqual(z.maxY, screen.maxY)
        XCTAssertFalse(z.contains(CGPoint(x: notch.midX, y: screen.midY)), "the middle of the screen is not the notch")
        let v = L.notch(screen: external, auxLeft: nil, auxRight: nil)
        let zv = L.dragZone(notch: v, screen: external)
        XCTAssertGreaterThan(zv.height, 0, "a notch-less screen still gets a reachable target")
    }

    /// B4b: a running countdown shows the badge even with no files held — on a real notch only.
    func testTheBadgeAlsoShowsForARunningTimer() {
        XCTAssertNotNil(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, timerActive: true))
        XCTAssertNil(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, timerActive: false))
        let v = L.notch(screen: external, auxLeft: nil, auxRight: nil)
        XCTAssertNotNil(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: v, timerActive: true),
                        "B7: on a notch-less screen the timer shows in the pill")
        XCTAssertNil(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: v, timerActive: true, pillOnPlainScreens: false))
    }

    /// N1 (2026-10-13, after OneNotch's one fixed 700×745 window): every notch-anchored state — badge, peek with
    /// files or a track, activity strip, every hub page, with or without a timer — fits inside the ONE fixed
    /// panel, which is centred on the notch, glued to the top edge and never wider than the screen. That is
    /// what lets a state change skip `setFrame` entirely. Checked on the notched screen AND a plain one.
    func testEveryNotchAnchoredStateFitsInsideTheFixedPanel() {
        let plain = L.notch(screen: external, auxLeft: nil, auxRight: nil)
        let externalVisible = CGRect(x: external.minX, y: external.minY + 70, width: external.width, height: external.height - 102)
        let states: [S] = [.collapsed, .peek, .activity, .expanded(.files), .expanded(.clipboard), .expanded(.nowPlaying),
                           .expanded(.agents), .expanded(.calendar), .expanded(.timer), .expanded(.aiUsage)]
        for (scr, vis, n) in [(screen, visible, notch), (external, externalVisible, plain)] {
            let panel = L.panelFrame(notch: n, screen: scr)
            XCTAssertEqual(panel.maxY, scr.maxY, accuracy: 0.001)
            XCTAssertEqual(panel.midX, n.midX, accuracy: 0.001)
            XCTAssertLessThanOrEqual(panel.width, scr.width)
            var drawn = 0
            for state in states { for items in [0, 3] { for np in [false, true] { for timer in [false, true] { for agent in [false, true] {
                guard let f = L.frame(for: state, anchor: .notch, itemCount: items, notch: n, screen: scr, visible: vis,
                                      pointer: .zero, timerActive: timer, nowPlayingActive: np, agentActive: agent) else { continue }
                drawn += 1
                XCTAssertTrue(panel.insetBy(dx: -0.001, dy: -0.001).contains(f),
                              "\(state) items \(items) track \(np) timer \(timer) agent \(agent): \(f) is not inside the fixed panel \(panel)")
            } } } } }
            XCTAssertGreaterThan(drawn, 20, "the walk must actually draw states, or the test proves nothing")
        }
    }

    /// The fixed panel is as wide as the widest state (the wide hub plus its two flares) and as tall as the deepest
    /// page (the calendar view) — nothing more, so the transparent remainder stays small.
    func testTheFixedPanelIsExactlyTheUnionOfTheStates() {
        let m = L.Metrics.standard
        let size = L.panelSize(notch: notch)
        XCTAssertEqual(size.width, m.wideWidth + 2 * m.topFillet)
        XCTAssertEqual(size.height, notch.height + m.toolDrop)
        XCTAssertEqual(size, CGSize(width: 650, height: 188), "650 × 188 — down from 776 × 254 before P1")
    }

    /// P8: the activity grid sits first on the RIGHT wing only while an agent is busy, and widens the notch evenly.
    func testTheActivityGridJoinsTheRightWingOnlyWhileAnAgentIsBusy() {
        let idle = L.wingItems(itemCount: 0, timerActive: false, nowPlayingActive: true, agentActive: true, agentBusy: false)
        XCTAssertEqual(idle.left, [.agent]); XCTAssertEqual(idle.right, [.music])
        let busy = L.wingItems(itemCount: 0, timerActive: false, nowPlayingActive: true, agentActive: true, agentBusy: true)
        XCTAssertEqual(busy.right, [.agentActivity, .music])
        XCTAssertEqual(L.wingItems(itemCount: 0, timerActive: false, nowPlayingActive: false, agentActive: false, agentBusy: true).right, [],
                       "no agent ⇒ no grid, whatever the busy flag says")
        let notch = CGRect(x: 0, y: 0, width: 185, height: 32)
        let a = L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, nowPlayingActive: true, agentActive: true, agentBusy: false)!
        let b = L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, nowPlayingActive: true, agentActive: true, agentBusy: true)!
        XCTAssertGreaterThan(b.width, a.width, "the grid takes room on the right wing")
        XCTAssertEqual(b.height, notch.height, "the wings never hang below the notch")
    }

    /// Owner 2026-10-14: stacked agent tiles were ugly; one tile, and the session count BESIDE it only when there is one
    /// to show — the wing widens for the number, never for a single session.
    func testOneSessionKeepsTheNarrowWingAndSeveralAddOnlyTheirCount() {
        let one = L.wingItems(itemCount: 0, timerActive: false, nowPlayingActive: false, agentActive: true, agentCount: 1)
        XCTAssertEqual(one.left, [.agent])
        let six = L.wingItems(itemCount: 0, timerActive: false, nowPlayingActive: false, agentActive: true, agentCount: 6)
        XCTAssertEqual(six.left, [.agentCounted])
        let notch = CGRect(x: 0, y: 0, width: 185, height: 32)
        let a = L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, agentActive: true, agentCount: 1)!
        let b = L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, agentActive: true, agentCount: 6)!
        let c = L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch, agentActive: true, agentCount: 2)!
        XCTAssertGreaterThanOrEqual(b.width, a.width, "a count may need a little room")
        XCTAssertEqual(b.width, c.width, "the wing does not keep growing with the count — 2 and 6 sessions are the same width")
    }

    /// P10 — the "AI edge": the agent item of the left wing, on a notched screen only.
    func testTheAgentEdgeIsTheAgentItemOfTheLeftWing() throws {
        let notch = CGRect(x: 771.5, y: 1085, width: 185, height: 32)
        let w = L.wingItems(itemCount: 2, timerActive: false, nowPlayingActive: false, agentActive: true, agentCount: 3)
        let edge = try XCTUnwrap(L.agentEdgeRect(notch: notch, left: w.left, right: w.right))
        XCTAssertLessThan(edge.maxX, notch.minX, "entirely in the left wing, never under the camera")
        XCTAssertEqual(edge.height, notch.height)
        let files = L.wingItems(itemCount: 2, timerActive: false, nowPlayingActive: false, agentActive: false)
        XCTAssertNil(L.agentEdgeRect(notch: notch, left: files.left, right: files.right), "no agent ⇒ no edge")
        XCTAssertNil(L.agentEdgeRect(notch: CGRect(x: 800, y: 1117, width: 120, height: 0), left: w.left, right: w.right),
                     "a screen without a notch has no edge")
    }
}
