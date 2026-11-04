import XCTest
import Foundation
import CoreGraphics

/// Tests the REAL snap geometry (B3 moved it out of WindowManager; the old tests checked a copy).
final class SnapLayoutTests: XCTestCase {
    typealias L = SnapLayout
    let ax = CGRect(x: 0, y: 0, width: 1728, height: 1023)          // top-left space work area
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)      // AppKit
    let notch = CGRect(x: 771.5, y: 1085, width: 185, height: 32)   // measured on this MacBook Pro

    func testSnapKeyTargetsAndUnknownKeys() {
        XCTAssertEqual(L.hotkeyTarget(keyCode: 123), .leftHalf)
        XCTAssertEqual(L.hotkeyTarget(keyCode: 124), .rightHalf)
        XCTAssertEqual(L.hotkeyTarget(keyCode: 126), .maximize)
        XCTAssertEqual(L.hotkeyTarget(keyCode: 3), .centerThird)
        XCTAssertNil(L.hotkeyTarget(keyCode: 40))
    }

    func testSnapModifierFamilyDoesNotStealBrowserOrShiftShortcuts() {
        for mask in 0..<16 {
            XCTAssertEqual(L.acceptsHotkey(control: mask & 1 != 0, option: mask & 2 != 0,
                                          command: mask & 4 != 0, shift: mask & 8 != 0), mask == 3,
                           "Only exact Control+Option belongs to Snap; mask \(mask)")
        }
    }

    func testNativeMinimumSizeStaysOnDisplayForSmallRightBottomZone() {
        let visible = CGRect(x: -1512, y: 30, width: 1512, height: 900)
        let target = CGRect(x: -504, y: 30, width: 504, height: 450)
        let frame = L.constrainedFrame(target, minimum: CGSize(width: 720, height: 500), visibleFrame: visible)
        XCTAssertEqual(frame, CGRect(x: -720, y: 30, width: 720, height: 500))
        XCTAssertTrue(visible.contains(frame))
        XCTAssertEqual(L.constrainedFrame(visible, minimum: CGSize(width: 720, height: 500), visibleFrame: visible), visible)
    }

    func testNativeMinimumLargerThanDisplayRemainsAnchoredAndUsable() {
        let visible = CGRect(x: 50, y: 20, width: 600, height: 400)
        let frame = L.constrainedFrame(visible, minimum: CGSize(width: 720, height: 500), visibleFrame: visible)
        XCTAssertEqual(frame, CGRect(x: 50, y: 20, width: 720, height: 500))
    }

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
                       .row(tile: nil, target: nil))
        XCTAssertEqual(L.decide(point: atNotch, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: false, rowVisible: false),
                       .edge(.maximize), "row switched off ⇒ the old behaviour")
        let farTop = CGPoint(x: 100, y: screen.maxY - 2)
        XCTAssertEqual(L.decide(point: farTop, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: false),
                       .edge(.maximize), "away from the notch the top edge still maximises")
    }

    func testMovingDownOntoATileSelectsItAndLeavingDropsTheRow() {
        let row = L.rowFrame(count: L.rowItems.count, notch: notch, screen: screen)
        let tiles = L.tileFrames(row: row, count: L.rowItems.count)
        let third = CGPoint(x: tiles[4].midX, y: tiles[4].midY)          // centerThird
        XCTAssertEqual(L.decide(point: third, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: true),
                       .row(tile: 4, target: .centerThird))
        XCTAssertEqual(L.rowItems[4], .single(.centerThird))
        XCTAssertEqual(L.decide(point: third, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: false),
                       .edge(nil), "the row region below the zone only counts once the row is showing")
        let below = CGPoint(x: notch.midX, y: row.minY - 60)
        XCTAssertEqual(L.decide(point: below, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: true),
                       .edge(nil))
    }

    /// The four-corner tile: the pointer's quadrant inside the tile picks the corner, upper half = top (AppKit y grows up).
    func testTheFourCornerTilePicksTheQuadrantUnderThePointer() throws {
        let row = L.rowFrame(count: L.rowItems.count, notch: notch, screen: screen)
        let tiles = L.tileFrames(row: row, count: L.rowItems.count)
        let i = try XCTUnwrap(L.rowItems.firstIndex(of: .quarters), "the row has a four-corner tile")
        let t = tiles[i]
        let cases: [(CGPoint, SnapLayout.Target)] = [
            (CGPoint(x: t.minX + 4, y: t.maxY - 4), .topLeft),
            (CGPoint(x: t.maxX - 4, y: t.maxY - 4), .topRight),
            (CGPoint(x: t.minX + 4, y: t.minY + 4), .bottomLeft),
            (CGPoint(x: t.maxX - 4, y: t.minY + 4), .bottomRight),
        ]
        for (p, want) in cases {
            XCTAssertEqual(L.decide(point: p, screen: screen, notch: notch, edgeMargin: 8, rowEnabled: true, rowVisible: true),
                           .row(tile: i, target: want), "\(want)")
        }
        XCTAssertEqual(SnapLayout.RowItem.quarters.targets, [.topLeft, .topRight, .bottomLeft, .bottomRight])
        // every single tile still gives exactly its own layout wherever the pointer is on it
        for (j, item) in L.rowItems.enumerated() {
            guard case .single(let target) = item else { continue }
            XCTAssertEqual(L.rowTarget(item: item, tile: tiles[j], point: CGPoint(x: tiles[j].minX + 2, y: tiles[j].minY + 2)), target)
        }
        // the row is still on screen with the extra tile
        XCTAssertGreaterThanOrEqual(row.minX, screen.minX)
        XCTAssertLessThanOrEqual(row.maxX, screen.maxX)
        // every tile's name reaches the screen through L10n.t(variable) — no literal sweep can see it
        let store = try L10nFixture.load()
        for item in L.rowItems {
            XCTAssertFalse(store.entries[item.titleKey]?.en.isEmpty ?? true, "\(item.titleKey) is not translated")
        }
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

    // MARK: Window-drag qualification (2026-10-14)

    func testOnlyAWindowThatMovesQualifiesAsAWindowDrag() {
        typealias Q = SnapLayout.DragQualifier
        let press = CGPoint(x: 500, y: 800)
        // The window under the pointer moved: a title-bar drag, however deep its Accessibility tree is.
        var q = Q(pressPoint: press, windowOrigin: CGPoint(x: 100, y: 50))
        XCTAssertEqual(q.observe(pointer: CGPoint(x: 501, y: 800), windowOriginNow: CGPoint(x: 100, y: 50)), .pending)
        XCTAssertEqual(q.observe(pointer: CGPoint(x: 505, y: 798), windowOriginNow: CGPoint(x: 104, y: 52)), .windowMove)
        XCTAssertEqual(q.observe(pointer: CGPoint(x: 900, y: 798), windowOriginNow: CGPoint(x: 104, y: 52)), .windowMove,
                       "decided once for the whole press")
        // The pointer travelled and the window stayed put: a text selection / a file drag — never a snap.
        var sel = Q(pressPoint: press, windowOrigin: CGPoint(x: 100, y: 50))
        XCTAssertEqual(sel.observe(pointer: CGPoint(x: 530, y: 800), windowOriginNow: CGPoint(x: 100, y: 50)), .pending)
        XCTAssertEqual(sel.observe(pointer: CGPoint(x: 545, y: 800), windowOriginNow: CGPoint(x: 100, y: 50)), .notWindowMove)
        XCTAssertEqual(sel.observe(pointer: CGPoint(x: 560, y: 800), windowOriginNow: CGPoint(x: 300, y: 50)), .notWindowMove,
                       "a later move does not turn a rejected press into a window drag")
        // No normal window under the pointer (menu bar, Dock, XFinder panel): rejected at once.
        XCTAssertEqual(Q(pressPoint: press, windowOrigin: nil).verdict, .notWindowMove)
        // A window that cannot be read this time keeps the press pending until the travel limit.
        var blind = Q(pressPoint: press, windowOrigin: CGPoint(x: 0, y: 0))
        XCTAssertEqual(blind.observe(pointer: CGPoint(x: 520, y: 800), windowOriginNow: nil), .pending)
        XCTAssertEqual(blind.observe(pointer: CGPoint(x: 540, y: 800), windowOriginNow: nil), .notWindowMove)
    }
}
