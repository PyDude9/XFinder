import XCTest
import Foundation
import CoreGraphics

/// XF-T30 W1 — tests for `PaneTabList` (per-pane tab bookkeeping) and `PaneTabRules.dropTarget` (drag-and-drop
/// geometry). Contract: `docs/specs/XF-T30-w1-contract.md` §2.
final class PaneTabsTests: XCTestCase {

    // MARK: - init

    func testInitHasOneSelectedTab() {
        let id = TabID()
        let list = PaneTabList(first: id)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.selectedTab, id)
        XCTAssertEqual(list.tabs, [id])
    }

    func testTabIDsAreUnique() {
        XCTAssertNotEqual(TabID(), TabID())
    }

    // MARK: - add

    func testAddGoesRightAfterSelectedAndBecomesSelected() {
        var list = PaneTabList(first: TabID())
        let first = list.selectedTab
        let second = TabID()
        list.add(second)
        XCTAssertEqual(list.tabs, [first, second])
        XCTAssertEqual(list.selectedTab, second)
    }

    func testAddAfterSelectingAnEarlierTabInsertsRightAfterThatOne() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.add(b)         // [a, b], selected b
        _ = list.select(a)  // selected a
        let c = TabID()
        list.add(c)         // must land right after a, not at the end
        XCTAssertEqual(list.tabs, [a, c, b])
        XCTAssertEqual(list.selectedTab, c)
    }

    func testAddExistingIDMovesInsteadOfDuplicating() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        let c = TabID()
        list.add(b) // [a, b] selected b
        list.add(c) // [a, b, c] selected c
        _ = list.select(a) // selected a
        list.add(c) // c already exists; moves to right after a instead of duplicating
        XCTAssertEqual(list.tabs, [a, c, b])
        XCTAssertEqual(list.count, 3, "must not duplicate an existing id")
        XCTAssertEqual(list.selectedTab, c)
    }

    // MARK: - select

    func testSelectExistingTabReturnsTrueAndSelects() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.add(b)
        XCTAssertTrue(list.select(a))
        XCTAssertEqual(list.selectedTab, a)
    }

    func testSelectUnknownTabReturnsFalseAndDoesNotChangeSelection() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        XCTAssertFalse(list.select(TabID()))
        XCTAssertEqual(list.selectedTab, a)
    }

    // MARK: - selectNext / selectPrevious (cyclic)

    func testSelectNextCyclesAndWraps() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        let c = TabID()
        list.add(b)
        list.add(c) // [a, b, c], selected c
        list.selectNext()
        XCTAssertEqual(list.selectedTab, a, "must wrap from last to first")
        list.selectNext()
        XCTAssertEqual(list.selectedTab, b)
    }

    func testSelectPreviousCyclesAndWraps() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.add(b) // [a, b], selected b
        list.selectPrevious()
        XCTAssertEqual(list.selectedTab, a)
        list.selectPrevious()
        XCTAssertEqual(list.selectedTab, b, "must wrap from first to last")
    }

    func testSelectNextOnSingleTabIsNoOp() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        list.selectNext()
        XCTAssertEqual(list.selectedTab, a)
        list.selectPrevious()
        XCTAssertEqual(list.selectedTab, a)
    }

    // MARK: - remove

    func testRemoveLastTabIsRefused() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        XCTAssertFalse(list.remove(a))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.selectedTab, a)
    }

    func testRemoveUnknownTabIsRefused() {
        var list = PaneTabList(first: TabID())
        let b = TabID()
        list.add(b)
        XCTAssertFalse(list.remove(TabID()))
        XCTAssertEqual(list.count, 2)
    }

    func testRemoveSelectedTabSelectsRightNeighbourFirst() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        let c = TabID()
        list.add(b)
        list.add(c) // [a, b, c], selected c
        _ = list.select(b) // selected b, right neighbour is c
        XCTAssertTrue(list.remove(b))
        XCTAssertEqual(list.tabs, [a, c])
        XCTAssertEqual(list.selectedTab, c, "right neighbour wins when one exists")
    }

    func testRemoveSelectedLastTabSelectsLeftNeighbour() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.add(b) // [a, b], selected b (no right neighbour)
        XCTAssertTrue(list.remove(b))
        XCTAssertEqual(list.tabs, [a])
        XCTAssertEqual(list.selectedTab, a, "falls back to the left neighbour when there is no right one")
    }

    func testRemoveUnselectedTabKeepsSelectionOnSameTab() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        let c = TabID()
        list.add(b)
        list.add(c) // [a, b, c], selected c
        _ = list.select(a) // selected a
        XCTAssertTrue(list.remove(b))
        XCTAssertEqual(list.tabs, [a, c])
        XCTAssertEqual(list.selectedTab, a, "removing a non-selected tab must not move the selection")
    }

    func testRemoveMiddleSelectedTabPrefersRightNeighbourOverLeft() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        let c = TabID()
        let d = TabID()
        list.add(b); list.add(c); list.add(d) // [a, b, c, d], selected d
        _ = list.select(b) // selected b, neighbours: a (left), c (right)
        XCTAssertTrue(list.remove(b))
        XCTAssertEqual(list.tabs, [a, c, d])
        XCTAssertEqual(list.selectedTab, c, "right neighbour (c) must win over left neighbour (a)")
    }

    // MARK: - insert

    func testInsertAtIndexClampsBelowZero() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.insert(b, at: -5, select: false)
        XCTAssertEqual(list.tabs, [b, a])
    }

    func testInsertAtIndexClampsAboveCount() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.insert(b, at: 99, select: false)
        XCTAssertEqual(list.tabs, [a, b])
    }

    func testInsertExistingIDMovesInsteadOfDuplicating() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        let c = TabID()
        list.add(b); list.add(c) // [a, b, c]
        list.insert(a, at: 2, select: false)
        XCTAssertEqual(list.tabs, [b, c, a], "existing id moves, list never grows")
        XCTAssertEqual(list.count, 3)
    }

    func testInsertWithSelectTrueSelectsTheInsertedTab() {
        var list = PaneTabList(first: TabID())
        let b = TabID()
        list.insert(b, at: 0, select: true)
        XCTAssertEqual(list.selectedTab, b)
    }

    func testInsertWithSelectFalseKeepsPreviousSelection() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.insert(b, at: 0, select: false)
        XCTAssertEqual(list.selectedTab, a, "selection must survive even though inserting shifted indices")
    }

    func testInsertIntoEmptyEdgeOfSingleTabList() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.insert(b, at: 0, select: false)
        XCTAssertEqual(list.tabs, [b, a])
        XCTAssertEqual(list.selectedTab, a)
    }

    // MARK: - move

    func testMoveKeepsSelectionOnSameTab() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        let c = TabID()
        list.add(b); list.add(c) // [a, b, c], selected c
        _ = list.select(a)
        list.move(c, to: 0) // move c (not selected) to front
        XCTAssertEqual(list.tabs, [c, a, b])
        XCTAssertEqual(list.selectedTab, a, "moving a different tab must not disturb selection")
    }

    func testMoveTheSelectedTabKeepsItSelected() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        let c = TabID()
        list.add(b); list.add(c) // [a, b, c], selected c
        list.move(c, to: 0)
        XCTAssertEqual(list.tabs, [c, a, b])
        XCTAssertEqual(list.selectedTab, c, "moving the selected tab must keep it selected")
    }

    func testMoveUnknownTabIsNoOp() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let before = list.tabs
        list.move(TabID(), to: 0)
        XCTAssertEqual(list.tabs, before)
        XCTAssertEqual(list.selectedTab, a)
    }

    func testMoveClampsOutOfRangeIndex() {
        var list = PaneTabList(first: TabID())
        let a = list.selectedTab
        let b = TabID()
        list.add(b) // [a, b]
        list.move(a, to: 99)
        XCTAssertEqual(list.tabs, [b, a])
    }

    // MARK: - Codable / Equatable

    func testCodableRoundTrip() throws {
        var list = PaneTabList(first: TabID())
        list.add(TabID())
        list.add(TabID())
        let data = try JSONEncoder().encode(list)
        let decoded = try JSONDecoder().decode(PaneTabList.self, from: data)
        XCTAssertEqual(decoded, list)
    }

    // MARK: - PaneTabRules.dropTarget

    private let paneRect = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let stripHeight: CGFloat = 32
    private func tabFrames(count: Int, width: CGFloat = 100) -> [CGRect] {
        (0..<count).map { CGRect(x: CGFloat($0) * width, y: 0, width: width, height: stripHeight) }
    }

    func testDropOnStripBeforeFirstTabMidpointReturnsIndexZero() {
        let frames = tabFrames(count: 3) // tabs at [0,100), [100,200), [200,300)
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 10, y: 10), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .strip(index: 0))
    }

    func testDropOnStripBetweenTabsReturnsThatIndex() {
        let frames = tabFrames(count: 3)
        // Between tab 0's midpoint (50) and tab 1's midpoint (150): point at x=120 is past tab0's midpoint (50)
        // but before tab1's midpoint (150) -> index 1.
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 120, y: 10), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .strip(index: 1))
    }

    func testDropOnStripAfterLastTabMidpointReturnsCount() {
        let frames = tabFrames(count: 3)
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 290, y: 10), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .strip(index: 3))
    }

    func testDropOnEmptyStripReturnsIndexZero() {
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 50, y: 10), paneRect: paneRect, stripHeight: stripHeight, tabFrames: [])
        XCTAssertEqual(target, .strip(index: 0))
    }

    func testDropNearLeftEdgeBelowStripIsEdgeLeft() {
        let frames = tabFrames(count: 3)
        // Below the strip (y > stripHeight), within the edge band on the left.
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 5, y: 150), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .edge(.left))
    }

    func testDropNearRightEdgeIsEdgeRight() {
        let frames = tabFrames(count: 3)
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 398, y: 150), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .edge(.right))
    }

    func testDropNearBottomEdgeIsEdgeDown() {
        let frames = tabFrames(count: 3)
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 200, y: 298), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .edge(.down))
    }

    func testDropJustBelowStripButWithinTopEdgeBandIsEdgeUp() {
        // Edge zone = min(56, 0.18 * min(400,300)) = min(56, 54) = 54. Just below the strip (stripHeight=32),
        // within 54pt of the strip's bottom edge (32+53=85) and far from other edges, is the "up" edge zone —
        // the space between the tab strip and the rest of the content that still counts as "near the top".
        let frames = tabFrames(count: 3)
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 200, y: 40), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .edge(.up))
    }

    func testDropInCenterIsCenterNotNearAnyEdge() {
        let frames = tabFrames(count: 3)
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 200, y: 150), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .center)
    }

    func testDropInCornerGoesToNearerEdge() {
        let frames = tabFrames(count: 3)
        // Bottom-right corner, closer to the right edge than the bottom.
        // paneRect width 400 height 300: point (396, 296) -> distRight = 4, distBottom = 4 -> tie goes to either,
        // make it asymmetric: point (396, 280) -> distRight = 4, distBottom = 20 -> right wins.
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 396, y: 280), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .edge(.right), "closer edge (right, dist 4) must win over farther one (bottom, dist 20)")
    }

    func testDropInCornerOtherDirectionGoesToNearerEdge() {
        let frames = tabFrames(count: 3)
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 350, y: 298), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .edge(.down), "bottom (dist 2) must win over right (dist 50)")
    }

    func testDropOutsidePaneRectIsCenter() {
        let frames = tabFrames(count: 3)
        let target = PaneTabRules.dropTarget(point: CGPoint(x: -10, y: -10), paneRect: paneRect, stripHeight: stripHeight, tabFrames: frames)
        XCTAssertEqual(target, .center, "a point entirely outside the pane rect has nothing sensible to report but must not crash; caller clamps before calling in practice")
    }

    func testEdgeZoneIsCappedAtMaxEvenForALargePane() {
        let bigRect = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        // 0.18 * 2000 = 360, capped to edgeZoneMax (56). A point 100pt from the left edge is outside the capped
        // zone, so it must NOT be treated as an edge drop even though it would be within an uncapped 18% zone.
        let target = PaneTabRules.dropTarget(point: CGPoint(x: 100, y: 1000), paneRect: bigRect, stripHeight: stripHeight, tabFrames: [])
        XCTAssertEqual(target, .center)
    }

    func testEdgeZoneUsesFractionForASmallPane() {
        // A small pane: 0.18 * 100 = 18, well under the 56pt cap, so the fraction (not the cap) governs.
        let smallRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let justInside = PaneTabRules.dropTarget(point: CGPoint(x: 5, y: 80), paneRect: smallRect, stripHeight: stripHeight, tabFrames: [])
        XCTAssertEqual(justInside, .edge(.left))
        let justOutside = PaneTabRules.dropTarget(point: CGPoint(x: 30, y: 80), paneRect: smallRect, stripHeight: stripHeight, tabFrames: [])
        XCTAssertEqual(justOutside, .center)
    }
}
