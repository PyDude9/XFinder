import XCTest
import Foundation
import CoreGraphics

final class PaneTreeTests: XCTestCase {

    // MARK: - init / basic shape

    func testInitIsOneLeafPaneZero() {
        let t = PaneTree()
        XCTAssertEqual(t.panes, [PaneID(raw: 0)])
        XCTAssertEqual(t.count, 1)
        XCTAssertTrue(t.canSplit)
        XCTAssertTrue(t.contains(PaneID(raw: 0)))
        XCTAssertFalse(t.contains(PaneID(raw: 1)))
        XCTAssertNil(t.zoomed)
    }

    // MARK: - split

    func testSplitRightPutsNewPaneSecond() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)
        XCTAssertEqual(p1, PaneID(raw: 1))
        XCTAssertEqual(t.panes, [p0, p1])
        guard case .split(let axis, let fraction, let first, let second) = t.root else {
            return XCTFail("expected a split node")
        }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(fraction, 0.5)
        XCTAssertEqual(first, .leaf(p0))
        XCTAssertEqual(second, .leaf(p1!))
    }

    func testSplitLeftPutsNewPaneFirst() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .left)
        guard case .split(let axis, _, let first, let second) = t.root else {
            return XCTFail("expected a split node")
        }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(first, .leaf(p1!))
        XCTAssertEqual(second, .leaf(p0))
        // Read order still goes "first then second" depth-first, so the new pane now reads before p0.
        XCTAssertEqual(t.panes, [p1!, p0])
    }

    func testSplitDownPutsNewPaneSecondVertical() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .down)
        guard case .split(let axis, _, let first, let second) = t.root else {
            return XCTFail("expected a split node")
        }
        XCTAssertEqual(axis, .vertical)
        XCTAssertEqual(first, .leaf(p0))
        XCTAssertEqual(second, .leaf(p1!))
    }

    func testSplitUpPutsNewPaneFirstVertical() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .up)
        guard case .split(let axis, _, let first, let second) = t.root else {
            return XCTFail("expected a split node")
        }
        XCTAssertEqual(axis, .vertical)
        XCTAssertEqual(first, .leaf(p1!))
        XCTAssertEqual(second, .leaf(p0))
    }

    func testSplitOnMissingPaneReturnsNil() {
        var t = PaneTree()
        XCTAssertNil(t.split(PaneID(raw: 99), .right))
        XCTAssertEqual(t.count, 1, "a failed split must not mutate the tree")
    }

    func testSplitStopsAtSixteenPanes() {
        var t = PaneTree()
        var leaf = PaneID(raw: 0)
        for _ in 0..<15 {
            leaf = t.split(leaf, .right)!
        }
        XCTAssertEqual(t.count, 16)
        XCTAssertFalse(t.canSplit)
        XCTAssertNil(t.split(leaf, .right))
        XCTAssertEqual(t.count, 16, "a split refused at the cap must not mutate the tree")
    }

    func testSplitExitsZoom() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        t.toggleZoom(p0)
        XCTAssertEqual(t.zoomed, p0)
        _ = t.split(p1, .down)
        XCTAssertNil(t.zoomed)
    }

    // MARK: - close

    func testCloseLastPaneIsRefused() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        XCTAssertNil(t.close(p0))
        XCTAssertEqual(t.count, 1)
    }

    func testCloseSiblingTakesParentSpot() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let selected = t.close(p0)
        XCTAssertEqual(selected, p1)
        XCTAssertEqual(t.root, .leaf(p1))
        XCTAssertEqual(t.panes, [p1])
    }

    func testCloseReturnsFirstLeafOfPromotedSubtree() {
        // Tree: split(p0, split(p1, p2)) — closing p0 promotes the (p1, p2) subtree; first leaf is p1.
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let p2 = t.split(p1, .down)!
        // root = split(h, p0, split(v, p1, p2))
        let selected = t.close(p0)
        XCTAssertEqual(selected, p1)
        XCTAssertEqual(t.root, .split(axis: .vertical, fraction: 0.5, first: .leaf(p1), second: .leaf(p2)))
    }

    func testCloseOnMissingPaneReturnsNil() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        XCTAssertNil(t.close(PaneID(raw: 99)))
        XCTAssertEqual(t.count, 2)
    }

    func testCloseZoomedPaneExitsZoom() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        t.toggleZoom(p1)
        XCTAssertEqual(t.zoomed, p1)
        _ = t.close(p1)
        XCTAssertNil(t.zoomed)
    }

    func testCloseNonZoomedPaneKeepsZoomOfSurvivor() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        t.toggleZoom(p1)
        _ = t.close(p0)
        XCTAssertEqual(t.zoomed, p1, "closing the OTHER pane should not disturb an existing zoom")
    }

    func testCloseDeepTreePreservesUntouchedSiblingAxisAndFraction() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let p2 = t.split(p1, .down)!
        t.setFraction(at: [], 0.3)
        // root = split(h, .3, p0, split(v, .5, p1, p2)); close p2 so the right side becomes leaf(p1),
        // and the outer split's own axis/fraction (0.3, horizontal) must survive since p2 is not a direct child of root.
        _ = t.close(p2)
        guard case .split(let axis, let fraction, let first, let second) = t.root else {
            return XCTFail("expected a split node")
        }
        XCTAssertEqual(axis, .horizontal)
        XCTAssertEqual(fraction, 0.3, accuracy: 1e-9)
        XCTAssertEqual(first, .leaf(p0))
        XCTAssertEqual(second, .leaf(p1))
    }

    // MARK: - apply(preset)

    func testApplySingleCollapsesToOnePaneReusingFirstID() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let (kept, removed) = t.apply(.single)
        XCTAssertEqual(kept, [p0])
        XCTAssertEqual(removed, [p1])
        XCTAssertEqual(t.root, .leaf(p0))
    }

    func testApplySideBySideFromSingleCreatesOneNewID() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let (kept, removed) = t.apply(.sideBySide)
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(kept[0], p0)
        XCTAssertEqual(kept[1], PaneID(raw: 1))
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(t.root, .split(axis: .horizontal, fraction: 0.5, first: .leaf(p0), second: .leaf(kept[1])))
    }

    func testApplyStackedUsesVerticalAxis() {
        var t = PaneTree()
        _ = t.apply(.stacked)
        guard case .split(let axis, _, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(axis, .vertical)
    }

    func testApplyGridBuildsTwoByTwo() {
        var t = PaneTree()
        let (kept, _) = t.apply(.grid)
        XCTAssertEqual(kept.count, 4)
        let expected = PaneNode.split(
            axis: .vertical, fraction: 0.5,
            first: .split(axis: .horizontal, fraction: 0.5, first: .leaf(kept[0]), second: .leaf(kept[1])),
            second: .split(axis: .horizontal, fraction: 0.5, first: .leaf(kept[2]), second: .leaf(kept[3]))
        )
        XCTAssertEqual(t.root, expected)
        XCTAssertEqual(t.panes, kept, "grid panes should read out top-left, top-right, bottom-left, bottom-right")
    }

    func testApplyReusesExistingIDsInReadOrderAndMintsOnlyWhatIsMissing() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)! // panes: [p0, p1], nextID = 2
        let (kept, removed) = t.apply(.grid)
        XCTAssertEqual(kept[0], p0)
        XCTAssertEqual(kept[1], p1)
        XCTAssertEqual(kept[2], PaneID(raw: 2))
        XCTAssertEqual(kept[3], PaneID(raw: 3))
        XCTAssertTrue(removed.isEmpty)
    }

    func testApplyFromGridToSingleKeepsFirstReadOrderPaneAndReportsRestRemoved() {
        var t = PaneTree()
        let (gridIDs, _) = t.apply(.grid)
        let (kept, removed) = t.apply(.single)
        XCTAssertEqual(kept, [gridIDs[0]])
        XCTAssertEqual(Set(removed), Set(gridIDs.dropFirst()))
    }

    func testApplyNextIDAfterGridContinuesPastMintedIDs() {
        var t = PaneTree()
        _ = t.apply(.grid) // mints ids 0,1,2,3
        let p4 = t.split(PaneID(raw: 0), .right)
        XCTAssertEqual(p4, PaneID(raw: 4))
    }

    func testApplyExitsZoom() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        t.toggleZoom(PaneID(raw: 0))
        _ = t.apply(.grid)
        XCTAssertNil(t.zoomed)
    }

    // MARK: - toggleZoom

    func testToggleZoomOnAndOff() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        t.toggleZoom(p0)
        XCTAssertEqual(t.zoomed, p0)
        t.toggleZoom(p0)
        XCTAssertNil(t.zoomed)
    }

    func testToggleZoomSwitchesToAnotherPane() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        t.toggleZoom(p0)
        t.toggleZoom(p1)
        XCTAssertEqual(t.zoomed, p1)
    }

    func testToggleZoomOnMissingPaneIsNoOp() {
        var t = PaneTree()
        t.toggleZoom(PaneID(raw: 99))
        XCTAssertNil(t.zoomed)
    }

    // MARK: - equalize

    func testEqualizeOnSideBySideWithUnevenFraction() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        t.setFraction(at: [], 0.9)
        t.equalize()
        guard case .split(_, let fraction, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(fraction, 0.5, accuracy: 1e-9)
    }

    func testEqualizeOnGridWithExtraPaneOnOneSideWeighsByLeafCount() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        _ = t.split(p0, .down) // p0's side now has 2 leaves, p1's side has 1 -> root first side has 2 of 3
        t.setFraction(at: [], 0.1)
        t.equalize()
        guard case .split(_, let fraction, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(fraction, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testEqualizeIsIdempotentOnFreshGrid() {
        var t = PaneTree()
        _ = t.apply(.grid)
        let before = t.root
        t.equalize()
        XCTAssertEqual(t.root, before)
    }

    // MARK: - setFraction

    func testSetFractionAtRoot() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        t.setFraction(at: [], 0.3)
        guard case .split(_, let fraction, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(fraction, 0.3, accuracy: 1e-9)
    }

    func testSetFractionClampsToMinFraction() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        t.setFraction(at: [], 0.0)
        guard case .split(_, let fraction, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(fraction, PaneTree.minFraction, accuracy: 1e-9)
    }

    func testSetFractionClampsToMaxFraction() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        t.setFraction(at: [], 1.0)
        guard case .split(_, let fraction, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(fraction, 1 - PaneTree.minFraction, accuracy: 1e-9)
    }

    func testSetFractionAtNestedPath() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        _ = t.split(p1, .down)
        // root = split(h, .5, p0, split(v, .5, p1, p2)); path [true] reaches the inner split.
        t.setFraction(at: [true], 0.25)
        guard case .split(_, let outerFraction, _, let second) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(outerFraction, 0.5, accuracy: 1e-9, "setting the inner fraction must not disturb the outer one")
        guard case .split(_, let innerFraction, _, _) = second else { return XCTFail("expected inner split") }
        XCTAssertEqual(innerFraction, 0.25, accuracy: 1e-9)
    }

    func testSetFractionWithPathIntoLeafIsIgnored() {
        var t = PaneTree()
        let before = t.root
        t.setFraction(at: [false], 0.3)
        XCTAssertEqual(t.root, before)
    }

    func testSetFractionWithPathTooShortLeavesNestedSplitAlone() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        _ = t.split(p1, .down)
        let before = t.root
        // Empty path already covered above (sets the root); here exercise an out-of-range path beyond the tree depth.
        t.setFraction(at: [true, true, true], 0.9)
        XCTAssertEqual(t.root, before, "a path longer than the tree depth must not mutate anything")
    }

    // MARK: - next / previous

    func testNextAndPreviousWrapAround() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let p2 = t.split(p1, .down)!
        XCTAssertEqual(t.panes, [p0, p1, p2])
        XCTAssertEqual(t.next(after: p0), p1)
        XCTAssertEqual(t.next(after: p1), p2)
        XCTAssertEqual(t.next(after: p2), p0, "must wrap")
        XCTAssertEqual(t.previous(before: p0), p2, "must wrap the other way")
        XCTAssertEqual(t.previous(before: p1), p0)
        XCTAssertEqual(t.previous(before: p2), p1)
    }

    func testNextOnSinglePaneReturnsItself() {
        let t = PaneTree()
        let p0 = PaneID(raw: 0)
        XCTAssertEqual(t.next(after: p0), p0)
        XCTAssertEqual(t.previous(before: p0), p0)
    }

    func testNextOnMissingPaneReturnsItUnchanged() {
        let t = PaneTree()
        let ghost = PaneID(raw: 99)
        XCTAssertEqual(t.next(after: ghost), ghost)
        XCTAssertEqual(t.previous(before: ghost), ghost)
    }

    // MARK: - other(than:)

    func testOtherWithOnePaneIsNil() {
        let t = PaneTree()
        XCTAssertNil(t.other(than: PaneID(raw: 0)))
    }

    func testOtherWithTwoPanesIsTheOtherOne() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        XCTAssertEqual(t.other(than: p0), p1)
        XCTAssertEqual(t.other(than: p1), p0)
    }

    func testOtherWithThreeOrMorePanesIsNextInReadOrder() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let p2 = t.split(p1, .down)!
        XCTAssertEqual(t.other(than: p0), p1)
        XCTAssertEqual(t.other(than: p1), p2)
        XCTAssertEqual(t.other(than: p2), p0, "cycles back to the first")
    }

    func testOtherWithMissingPaneIsNil() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        XCTAssertNil(t.other(than: PaneID(raw: 99)))
    }

    // MARK: - frames / dividers / pane(at:)

    func testFramesSinglePaneFillsRect() {
        let t = PaneTree()
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frames = t.frames(in: rect, divider: 1)
        XCTAssertEqual(frames, [PaneID(raw: 0): rect])
        XCTAssertTrue(t.dividers(in: rect, divider: 1).isEmpty)
    }

    func testFramesHorizontalSplitSideBySide() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let rect = CGRect(x: 0, y: 0, width: 801, height: 600)
        let frames = t.frames(in: rect, divider: 1)
        XCTAssertEqual(frames[p0], CGRect(x: 0, y: 0, width: 400, height: 600))
        XCTAssertEqual(frames[p1], CGRect(x: 401, y: 0, width: 400, height: 600))
        let dividers = t.dividers(in: rect, divider: 1)
        XCTAssertEqual(dividers.count, 1)
        XCTAssertEqual(dividers[0].axis, .horizontal)
        XCTAssertEqual(dividers[0].rect, CGRect(x: 400, y: 0, width: 1, height: 600))
        XCTAssertEqual(dividers[0].parent, rect)
        XCTAssertEqual(dividers[0].path, [])
    }

    func testFramesVerticalSplitStacked() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .down)!
        let rect = CGRect(x: 0, y: 0, width: 800, height: 601)
        let frames = t.frames(in: rect, divider: 1)
        // top-left origin, AppKit flipped: `first` (p0, "up" side) sits at the top (minY).
        XCTAssertEqual(frames[p0], CGRect(x: 0, y: 0, width: 800, height: 300))
        XCTAssertEqual(frames[p1], CGRect(x: 0, y: 301, width: 800, height: 300))
        let dividers = t.dividers(in: rect, divider: 1)
        XCTAssertEqual(dividers[0].axis, .vertical)
        XCTAssertEqual(dividers[0].rect, CGRect(x: 0, y: 300, width: 800, height: 1))
    }

    func testFramesNestedPathsAreRecorded() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        _ = t.split(p1, .down)!
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let dividers = t.dividers(in: rect, divider: 0)
        XCTAssertEqual(Set(dividers.map(\.path)), Set([[], [true]]))
    }

    func testFramesWhileZoomedOnlyZoomedPaneFillsRect() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        t.toggleZoom(p1)
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frames = t.frames(in: rect, divider: 1)
        XCTAssertEqual(frames, [p1: rect])
        XCTAssertTrue(t.dividers(in: rect, divider: 1).isEmpty)
    }

    func testPaneAtPointHitsCorrectPane() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertEqual(t.pane(at: CGPoint(x: 10, y: 10), in: rect, divider: 1), p0)
        XCTAssertEqual(t.pane(at: CGPoint(x: 790, y: 10), in: rect, divider: 1), p1)
    }

    func testPaneAtPointOutsideRectIsNil() {
        let t = PaneTree()
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNil(t.pane(at: CGPoint(x: -5, y: 10), in: rect, divider: 1))
        XCTAssertNil(t.pane(at: CGPoint(x: 10, y: 601), in: rect, divider: 1))
    }

    func testPaneAtPointOnDividerGapIsNil() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        _ = t.split(p0, .right)!
        let rect = CGRect(x: 0, y: 0, width: 801, height: 600)
        // divider occupies x in [400, 401)
        XCTAssertNil(t.pane(at: CGPoint(x: 400.2, y: 10), in: rect, divider: 1))
    }

    // MARK: - Codable / Equatable round-trip

    func testCodableRoundTrip() throws {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        _ = t.split(p1, .down)
        t.toggleZoom(p1)
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(PaneTree.self, from: data)
        XCTAssertEqual(decoded, t)
    }

    // MARK: - PaneID Comparable

    func testPaneIDComparable() {
        XCTAssertLessThan(PaneID(raw: 0), PaneID(raw: 1))
        XCTAssertFalse(PaneID(raw: 1) < PaneID(raw: 1))
        let sorted = [PaneID(raw: 3), PaneID(raw: 1), PaneID(raw: 2)].sorted()
        XCTAssertEqual(sorted, [PaneID(raw: 1), PaneID(raw: 2), PaneID(raw: 3)])
    }

    // MARK: - adversarial probes (verify pass)

    func testSetFractionNaNIsIgnored() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        let before = t.root
        t.setFraction(at: [], Double.nan)
        XCTAssertEqual(t.root, before, "a NaN fraction must be rejected like an out-of-bounds path, not stored verbatim")
    }

    func testSetFractionInfinityClampsToMax() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        t.setFraction(at: [], Double.infinity)
        guard case .split(_, let fraction, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(fraction, 1 - PaneTree.minFraction, accuracy: 1e-9)
    }

    func testSetFractionNegativeInfinityClampsToMin() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        t.setFraction(at: [], -Double.infinity)
        guard case .split(_, let fraction, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(fraction, PaneTree.minFraction, accuracy: 1e-9)
    }

    func testCloseGrandchildOnSecondBranchSelectsFirstLeafOfPromotedSubtree() {
        // root = split(h, p0, split(v, p1, split(h, p2, p3))); closing p2 promotes p3 into the inner-inner spot,
        // and the deep "second" recursion branch in removalOutcome must be exercised (not just "first").
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let p2 = t.split(p1, .down)!
        let p3 = t.split(p2, .right)!
        // root = split(h, p0, split(v, p1, split(h, p2, p3)))
        let selected = t.close(p2)
        XCTAssertEqual(selected, p3)
        XCTAssertEqual(t.root, .split(axis: .horizontal, fraction: 0.5, first: .leaf(p0), second: .split(axis: .vertical, fraction: 0.5, first: .leaf(p1), second: .leaf(p3))))
    }

    func testApplyPresetClearsZoomEvenWhenZoomedPaneIsKept() {
        var t = PaneTree()
        _ = t.apply(.grid)
        t.toggleZoom(t.panes[0])
        XCTAssertNotNil(t.zoomed)
        _ = t.apply(.single)
        XCTAssertNil(t.zoomed, "apply must always exit zoom, even when the zoomed pane id is reused")
    }

    func testEqualizeOnMixedAxisNestingUsesLeafCountNotAxisFilter() {
        // root = split(h, p0, split(v, p1, p2)) — inner split has a DIFFERENT axis than root.
        // Contract: "every node: fraction = leaf count of first / total" (not filtered by matching axis),
        // so root's fraction should become 1/3 (p0 alone vs {p1,p2}), regardless of the inner node's axis.
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        _ = t.split(p1, .down)
        t.setFraction(at: [], 0.9)
        t.equalize()
        guard case .split(_, let fraction, _, _) = t.root else { return XCTFail("expected split") }
        XCTAssertEqual(fraction, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testSplitThenImmediateCloseOfNewPaneRestoresOriginalSingleLeaf() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let selected = t.close(p1)
        XCTAssertEqual(selected, p0)
        XCTAssertEqual(t.root, .leaf(p0))
        XCTAssertEqual(t.count, 1)
    }

    func testFramesZeroSizedRectDoesNotCrash() {
        var t = PaneTree()
        _ = t.split(PaneID(raw: 0), .right)
        let rect = CGRect.zero
        let frames = t.frames(in: rect, divider: 1)
        XCTAssertEqual(frames.count, 2)
        for (_, frame) in frames {
            XCTAssertGreaterThanOrEqual(frame.width, 0)
            XCTAssertGreaterThanOrEqual(frame.height, 0)
        }
    }

    func testDividerCountMatchesInternalNodeCountForGrid() {
        var t = PaneTree()
        _ = t.apply(.grid)
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let dividers = t.dividers(in: rect, divider: 1)
        XCTAssertEqual(dividers.count, 3, "a 4-leaf full binary tree has exactly 3 internal (split) nodes")
    }

    func testPaneAtPointWithZeroDividerStillPartitionsExactlyAtBoundary() {
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .right)!
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        // divider = 0: split exactly at x=400.
        XCTAssertEqual(t.pane(at: CGPoint(x: 399.9, y: 10), in: rect, divider: 0), p0)
        XCTAssertEqual(t.pane(at: CGPoint(x: 400.1, y: 10), in: rect, divider: 0), p1)
    }

    func testApplySameSizePresetTwiceIsIdempotentInIDs() {
        var t = PaneTree()
        let (first, _) = t.apply(.sideBySide)
        let (second, removed) = t.apply(.sideBySide)
        XCTAssertEqual(first, second)
        XCTAssertTrue(removed.isEmpty)
    }

    func testCloseDeepInFirstBranchSelectsPromotedSiblingNotUnrelatedLeaf() {
        // Mirror of the "second branch" probe, but with the deep removal on the FIRST side of the root and the
        // untouched sibling (p3) sitting on root's second side — if `selected` ever regresses to reading
        // `leaves(of: wholeRebuiltTree)[0]` again, this would wrongly report the promoted pane instead of p3's
        // subtree, or vice versa, depending on which side the bug reads from.
        var t = PaneTree()
        let p0 = PaneID(raw: 0)
        let p1 = t.split(p0, .down)! // root = split(v, p0, p1)
        let p2 = t.split(p0, .right)! // root = split(v, split(h, p0, p2), p1)
        let p3 = t.split(p2, .down)! // root = split(v, split(h, p0, split(v, p2, p3)), p1)
        let selected = t.close(p2)
        XCTAssertEqual(selected, p3, "closing p2 promotes p3 into its spot; p1 (the untouched sibling of the outer split) must not be picked")
    }

    func testCloseThenSplitReusesNoStaleID() {
        // Build a grid (ids 0..3), close one, then split: new id must not collide with a surviving pane.
        var t = PaneTree()
        let ids = t.apply(.grid).kept
        _ = t.close(ids[3])
        let survivors = Set(t.panes)
        let newID = t.split(ids[0], .right)!
        XCTAssertFalse(survivors.contains(newID))
        XCTAssertEqual(Set(t.panes).count, t.panes.count, "no duplicate ids after close+split")
    }
}
