import XCTest
import Foundation
import CoreGraphics

final class SurfaceGeometryTests: XCTestCase {
    // This MacBook Pro: 1728×1117 full, menu bar 32 pt, Dock not auto-hidden (visible frame shorter).
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let visible = CGRect(x: 0, y: 80, width: 1728, height: 1005)
    let auxL = CGRect(x: 0, y: 1085, width: 771.5, height: 32), auxR = CGRect(x: 956.5, y: 1085, width: 771.5, height: 32)

    func testNotchRectFromTheTwoAuxiliaryAreas() {
        let n = SurfaceGeometry.notchRect(auxLeft: auxL, auxRight: auxR)!
        XCTAssertEqual(n, CGRect(x: 771.5, y: 1085, width: 185, height: 32))
        XCTAssertNil(SurfaceGeometry.notchRect(auxLeft: nil, auxRight: nil), "external display: no notch")
        XCTAssertNil(SurfaceGeometry.notchRect(auxLeft: auxR, auxRight: auxL), "swapped/overlapping areas are not a notch")
    }

    func testCollapsedFrameIsTheNotchOrAPillAtTheTopEdge() {
        let n = SurfaceGeometry.notchRect(auxLeft: auxL, auxRight: auxR)
        XCTAssertEqual(SurfaceGeometry.collapsedNotchFrame(screen: screen, notch: n, pill: CGSize(width: 200, height: 28)), n!)
        let pill = SurfaceGeometry.collapsedNotchFrame(screen: screen, notch: nil, pill: CGSize(width: 200, height: 28))
        XCTAssertEqual(pill, CGRect(x: 764, y: 1089, width: 200, height: 28))
        XCTAssertEqual(pill.maxY, screen.maxY, "glued to the top edge")
    }

    func testExpandedFrameGrowsAroundTheNotchCentreAndNeverLeavesTheScreen() {
        let collapsed = CGRect(x: 771.5, y: 1085, width: 185, height: 32)
        let e = SurfaceGeometry.expandedNotchFrame(collapsed: collapsed, size: CGSize(width: 600, height: 220), screen: screen)
        XCTAssertEqual(e.midX, collapsed.midX, accuracy: 0.001)
        XCTAssertEqual(e.maxY, screen.maxY)
        XCTAssertEqual(e.size, CGSize(width: 600, height: 220))
        let huge = SurfaceGeometry.expandedNotchFrame(collapsed: collapsed, size: CGSize(width: 5000, height: 220), screen: screen)
        XCTAssertEqual(huge.width, screen.width, "wider than the screen is clamped to the screen")
        XCTAssertEqual(huge.minX, 0)
    }

    func testAnchorsLandWhereTheOldControllersPutThem() {
        let size = CGSize(width: 340, height: 68)
        let tr = SurfaceGeometry.frame(size: size, anchor: .topRight(inset: 16), screen: screen, visible: visible)
        XCTAssertEqual(tr.maxX, visible.maxX - 16); XCTAssertEqual(tr.maxY, visible.maxY - 16)
        let tc = SurfaceGeometry.frame(size: size, anchor: .topCenter(inset: 72), screen: screen, visible: visible)
        XCTAssertEqual(tc.midX, visible.midX, accuracy: 0.001); XCTAssertEqual(tc.maxY, visible.maxY - 72)
        let notch = SurfaceGeometry.frame(size: CGSize(width: 185, height: 32), anchor: .notch, screen: screen, visible: visible)
        XCTAssertEqual(notch.maxY, screen.maxY, "the notch surface sits over the menu bar, not under it")
        let sp = SurfaceGeometry.frame(size: CGSize(width: 680, height: 400), anchor: .spotlight, screen: screen, visible: visible)
        XCTAssertEqual(sp.maxY, visible.maxY - visible.height * 0.28, accuracy: 0.001)
        let c = SurfaceGeometry.frame(size: size, anchor: .center, screen: screen, visible: visible)
        XCTAssertEqual(c.midX, visible.midX, accuracy: 0.001); XCTAssertEqual(c.midY, visible.midY, accuracy: 0.001)
    }

    func testPointerAnchorIsClampedInsideTheVisibleFrame() {
        let size = CGSize(width: 300, height: 200)
        let nearCorner = SurfaceGeometry.frame(size: size, anchor: .pointer(CGPoint(x: 1720, y: 90)), screen: screen, visible: visible)
        XCTAssertEqual(nearCorner.maxX, visible.maxX); XCTAssertEqual(nearCorner.minY, visible.minY)
        let mid = SurfaceGeometry.frame(size: size, anchor: .pointer(CGPoint(x: 800, y: 500)), screen: screen, visible: visible)
        XCTAssertEqual(mid.midX, 800); XCTAssertEqual(mid.midY, 500)
    }

    func testClampHandlesARectLargerThanTheBounds() {
        let r = SurfaceGeometry.clamp(CGRect(x: -50, y: -50, width: 3000, height: 3000), into: visible)
        XCTAssertEqual(r.origin, visible.origin, "cannot fit ⇒ align to the bounds' origin, never NaN or negative overflow")
    }
}
