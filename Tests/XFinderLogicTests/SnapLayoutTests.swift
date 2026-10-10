import XCTest
import Foundation
import CoreGraphics

/// Tests the REAL snap geometry (B3 moved it out of WindowManager; the old tests checked a copy).
final class SnapLayoutTests: XCTestCase {
    typealias L = SnapLayout
    let ax = CGRect(x: 0, y: 0, width: 1728, height: 1023)          // top-left space work area
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)      // AppKit
    let notch = CGRect(x: 771.5, y: 1085, width: 185, height: 32)   // measured on this MacBook Pro

    // MARK: Target rects

    /// The reported bug: dragging to the bottom-left highlighted the top-left. In TOP-LEFT space
    /// "bottom" must have the LARGER y.
    func testBottomLeftIsBelowTopLeft() {
        XCTAssertGreaterThan(L.Target.bottomLeft.rect(in: ax).minY, L.Target.topLeft.rect(in: ax).minY)
        XCTAssertFalse(L.Target.topLeft.rect(in: ax).intersects(L.Target.bottomLeft.rect(in: ax)))
    }

    func testThirdsTileTheWidthExactly() {
        for width in [1728.0, 1440, 1001, 2560] {
            let s = CGRect(x: 30, y: 0, width: width, height: 900)
            let l = L.Target.leftThird.rect(in: s), c = L.Target.centerThird.rect(in: s), r = L.Target.rightThird.rect(in: s)
            XCTAssertEqual(l.minX, s.minX); XCTAssertEqual(l.maxX, c.minX); XCTAssertEqual(c.maxX, r.minX)
            XCTAssertEqual(r.maxX, s.maxX, "width \(width): the thirds must cover the screen to the pixel")
            XCTAssertEqual(L.Target.leftTwoThirds.rect(in: s).maxX, c.maxX)
            XCTAssertEqual(L.Target.rightTwoThirds.rect(in: s).minX, c.minX)
        }
    }

    func testFocusIsCentredAndFullHeight() {
        let f = L.Target.focus.rect(in: ax)
        XCTAssertEqual(f.midX, ax.midX, accuracy: 1)
        XCTAssertEqual(f.width, ax.width * 0.6, accuracy: 1)
        XCTAssertEqual(f.height, ax.height)
    }

    func testEveryTargetStaysInsideTheWorkArea() {
        let s = CGRect(x: 68, y: 33, width: 1660, height: 1023)
        for t in L.Target.allCases { XCTAssertTrue(s.contains(t.rect(in: s)), "\(t)") }
    }

    // MARK: Stage Manager (real function now)

    func testStageInsetGatesAndClamp() {
        XCTAssertEqual(L.stageInset(stageManagerOn: false, reserve: true, custom: 68), 0)
        XCTAssertEqual(L.stageInset(stageManagerOn: true, reserve: false, custom: 68), 0)
        XCTAssertEqual(L.stageInset(stageManagerOn: true, reserve: true, custom: nil), 68)
        XCTAssertEqual(L.stageInset(stageManagerOn: true, reserve: true, custom: 10), 48, "below the slider floor")
        XCTAssertEqual(L.stageInset(stageManagerOn: true, reserve: true, custom: 500), 140)
    }

    // MARK: Edge zones

    func testEdgeZonesAndCornerPrecedence() {
        XCTAssertEqual(L.edgeTarget(at: CGPoint(x: 2, y: 1100), screen: screen, margin: 8), .topLeft)
        XCTAssertEqual(L.edgeTarget(at: CGPoint(x: 2, y: 500), screen: screen, margin: 8), .leftHalf)
        XCTAssertEqual(L.edgeTarget(at: CGPoint(x: 1000, y: 1115), screen: screen, margin: 8), .maximize)
        XCTAssertNil(L.edgeTarget(at: CGPoint(x: 800, y: 500), screen: screen, margin: 8))
    }

    // MARK: Notch row

    func testDraggingToTheNotchShowsTheRowInsteadOfMaximize() {
        let atNotch = CGPoint(x: notch.midX, y: screen.maxY - 2)
        XCTAssertEqual(L.decide(point: atNotch, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: false),
                       .row(tile: nil))
        XCTAssertEqual(L.decide(point: atNotch, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: false, rowVisible: false),
                       .edge(.maximize), "row switched off ⇒ the old behaviour")
        let farTop = CGPoint(x: 100, y: screen.maxY - 2)
        XCTAssertEqual(L.decide(point: farTop, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: false),
                       .edge(.maximize), "away from the notch the top edge still maximises")
    }

    func testMovingDownOntoATileSelectsItAndLeavingDropsTheRow() {
        let row = L.rowFrame(count: L.rowTargets.count, notch: notch, screen: screen)
        let tiles = L.tileFrames(row: row, count: L.rowTargets.count)
        let third = CGPoint(x: tiles[3].midX, y: tiles[3].midY)          // centerThird
        XCTAssertEqual(L.decide(point: third, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: true),
                       .row(tile: 3))
        XCTAssertEqual(L.rowTargets[3], .centerThird)
        XCTAssertEqual(L.decide(point: third, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: false),
                       .edge(nil), "the row region below the zone only counts once the row is showing")
        let below = CGPoint(x: notch.midX, y: row.minY - 60)
        XCTAssertEqual(L.decide(point: below, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: true),
                       .edge(nil))
    }

    func testTileHitTestCoversGapsAndEveryTile() {
        let row = L.rowFrame(count: 7, notch: notch, screen: screen)
        let tiles = L.tileFrames(row: row, count: 7)
        for (i, t) in tiles.enumerated() { XCTAssertEqual(L.tileIndex(at: CGPoint(x: t.midX, y: t.midY), row: row, count: 7), i) }
        let gap = CGPoint(x: (tiles[1].maxX + tiles[2].minX) / 2, y: tiles[1].midY)
        XCTAssertNotNil(L.tileIndex(at: gap, row: row, count: 7), "a gap must not flicker to nothing")
        XCTAssertEqual(tiles.last!.maxX + SnapLayout.RowMetrics.standard.padding, row.maxX, accuracy: 0.01)
    }

    func testRowHangsBelowTheNotchAndStaysOnScreen() {
        let row = L.rowFrame(count: 7, notch: notch, screen: screen)
        XCTAssertLessThan(row.maxY, notch.minY, "the row must not cover the notch")
        XCTAssertEqual(row.midX, notch.midX, accuracy: 0.5)
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 800)
        let r2 = L.rowFrame(count: 7, notch: CGRect(x: 0, y: 800, width: 100, height: 0), screen: tiny)
        XCTAssertGreaterThanOrEqual(r2.minX, tiny.minX)
    }

    func testEveryTargetNameIsInTheStore() throws {
        let store = try L10nFixture.load()
        for t in L.Target.allCases { XCTAssertNotNil(store.entries[t.titleKey], t.titleKey) }
    }
}
