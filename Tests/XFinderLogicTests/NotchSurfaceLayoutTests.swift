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

    func testSizesGrowBadgeToPeekToExpanded() {
        let b = L.size(for: .collapsed, anchor: .notch, itemCount: 1, notch: notch)!
        let p = L.size(for: .peek, anchor: .notch, itemCount: 1, notch: notch)!
        let e = L.size(for: .expanded(.files), anchor: .notch, itemCount: 1, notch: notch)!
        XCTAssertLessThan(b.width, p.width); XCTAssertLessThan(p.width, e.width)
        XCTAssertLessThan(b.height, p.height); XCTAssertLessThan(p.height, e.height)
    }

    func testCollapsedDrawsNothingWithoutFilesOrWithoutARealNotch() {
        XCTAssertNil(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: notch), "no files ⇒ no badge")
        let v = L.notch(screen: external, auxLeft: nil, auxRight: nil)
        XCTAssertNil(L.size(for: .collapsed, anchor: .notch, itemCount: 5, notch: v), "a badge needs a notch to hang from (pill = B7)")
        XCTAssertNotNil(L.size(for: .peek, anchor: .notch, itemCount: 5, notch: v))
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
        XCTAssertEqual(zv.height, 8); XCTAssertEqual(zv.maxY, external.maxY)
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
        XCTAssertNil(L.size(for: .collapsed, anchor: .notch, itemCount: 0, notch: v, timerActive: true),
                     "nothing to hang a badge from on a notch-less screen")
    }
}

