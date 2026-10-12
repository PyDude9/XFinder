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
            XCTAssertGreaterThan(f.height, notch.height, "\(state) must reach below the notch or it is invisible")
        }
    }

    /// D0: the hub's size follows the page — the clipboard deck (OneNotch reference: a wide band either
    /// side of the notch, four cards in a row) is far wider than the tray; the other pages keep 440 × 222,
    /// at the notch and at the pointer alike.
    func testTheClipboardPageIsWiderThanTheOtherPagesAndOnlyThatPage() {
        let files = L.size(for: .expanded(.files), anchor: .notch, itemCount: 1, notch: notch)!
        let clip = L.size(for: .expanded(.clipboard), anchor: .notch, itemCount: 1, notch: notch)!
        let player = L.size(for: .expanded(.nowPlaying), anchor: .notch, itemCount: 1, notch: notch)!
        let fl = 2 * L.Metrics.standard.topFillet
        XCTAssertEqual(files, CGSize(width: 440 + fl, height: notch.height + 222), "440 of content plus the two flares")
        XCTAssertEqual(player, files, "only the clipboard page changes")
        XCTAssertGreaterThan(clip.width, files.width + 250, "four 174-pt cards need the band beside the notch")
        XCTAssertEqual(clip, CGSize(width: 752 + fl, height: notch.height + 200))
        XCTAssertLessThan(clip.width, screen.width, "still fits a 1728-pt screen with room to spare")
        let pointerClip = L.size(for: .expanded(.clipboard), anchor: .pointer, itemCount: 1, notch: notch)!
        XCTAssertEqual(pointerClip.width, clip.width - fl, "a pointer tray has no top edge to flare into")
        XCTAssertEqual(pointerClip.height, clip.height - notch.height, "at the pointer there is no notch band to add")
        // The frame stays centred on the notch and inside the screen.
        let f = L.frame(for: .expanded(.clipboard), anchor: .notch, itemCount: 1, notch: notch, screen: screen, visible: visible, pointer: .zero)!
        XCTAssertEqual(f.midX, notch.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(f.minX, 0); XCTAssertLessThanOrEqual(f.maxX, screen.width)
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
        XCTAssertEqual(pill, CGSize(width: L.Metrics.standard.pillWidth, height: L.Metrics.standard.pillHeight), "B7: a pill stands in for the badge")
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
        XCTAssertEqual(pill, L.frame(for: .collapsed, anchor: .notch, itemCount: 2, notch: v, screen: ext, visible: extVisible, pointer: .zero))
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

    /// The strip under the notch is the centre of every window's title bar; without files it must
    /// not be part of the hover zone, or grabbing a title bar would count as hovering the tray.
    func testHoverZoneGainsTheBadgeLipOnlyWhileFilesAreHeld() {
        let empty = L.hoverZone(notch: notch, screen: screen, itemCount: 0)
        XCTAssertEqual(empty, notch)
        let held = L.hoverZone(notch: notch, screen: screen, itemCount: 2)
        XCTAssertEqual(held.maxY, screen.maxY)
        XCTAssertEqual(held.minY, notch.minY - L.Metrics.standard.badgeLip)
        let v = L.notch(screen: external, auxLeft: nil, auxRight: nil)
        let zv = L.hoverZone(notch: v, screen: external, itemCount: 2)
        XCTAssertEqual(zv.height, 8); XCTAssertEqual(zv.maxY, external.maxY, "no pill shown ⇒ the bare strip in the menu bar")
        // While the pill (the virtual notch, D0c) is shown it is the hover target — flush with the top edge.
        let extVisible = CGRect(x: external.minX, y: 0, width: external.width, height: external.height - 24)
        let zp = L.hoverZone(notch: v, screen: external, itemCount: 2, visible: extVisible, pillShown: true)
        XCTAssertEqual(zp, L.pillRect(notch: v, visible: extVisible))
        XCTAssertEqual(zp.maxY, external.maxY, "the pill zone sits at the top edge like a notch")
        XCTAssertEqual(zp.height, L.Metrics.standard.pillHeight)
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
        let states: [S] = [.collapsed, .peek, .activity, .expanded(.files), .expanded(.clipboard), .expanded(.nowPlaying)]
        for (scr, vis, n) in [(screen, visible, notch), (external, externalVisible, plain)] {
            let panel = L.panelFrame(notch: n, screen: scr)
            XCTAssertEqual(panel.maxY, scr.maxY, accuracy: 0.001)
            XCTAssertEqual(panel.midX, n.midX, accuracy: 0.001)
            XCTAssertLessThanOrEqual(panel.width, scr.width)
            var drawn = 0
            for state in states { for items in [0, 3] { for np in [false, true] { for timer in [false, true] {
                guard let f = L.frame(for: state, anchor: .notch, itemCount: items, notch: n, screen: scr, visible: vis,
                                      pointer: .zero, timerActive: timer, nowPlayingActive: np) else { continue }
                drawn += 1
                XCTAssertTrue(panel.insetBy(dx: -0.001, dy: -0.001).contains(f),
                              "\(state) items \(items) track \(np) timer \(timer): \(f) is not inside the fixed panel \(panel)")
            } } } }
            XCTAssertGreaterThan(drawn, 20, "the walk must actually draw states, or the test proves nothing")
        }
    }

    /// The fixed panel is as wide as the widest state (the clipboard hub plus its two top fillets) and as tall as
    /// the deepest drop below the notch — nothing more, so the transparent remainder stays small.
    func testTheFixedPanelIsExactlyTheUnionOfTheStates() {
        let m = L.Metrics.standard
        let size = L.panelSize(notch: notch)
        XCTAssertEqual(size.width, m.clipboardExpandedWidth + 2 * m.topFillet)
        XCTAssertEqual(size.height, notch.height + m.expandedDrop)
    }
}
