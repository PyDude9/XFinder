import XCTest
import Foundation
import CoreGraphics

final class BSPTilingRulesTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testSingleInsertFillsUsableAreaMinusPadding() {
        var tree = BSPTree()
        tree.insert(101, in: screen, gap: 8, padding: 10)
        let slots = tree.layout(in: screen, gap: 8, padding: 10)
        XCTAssertEqual(slots[101], CGRect(x: 10, y: 10, width: 1580, height: 980))
        XCTAssertEqual(tree.windowIDs, [101])
    }

    func testDwindleSplitsFollowAspectRatioAndGap() {
        var tree = BSPTree()
        // 1600x1000 -> wider than tall -> horizontal split
        tree.insert(1, in: screen, gap: 10, padding: 0)
        tree.insert(2, in: screen, gap: 10, padding: 0)
        var slots = tree.layout(in: screen, gap: 10, padding: 0)
        XCTAssertEqual(slots[1], CGRect(x: 0, y: 0, width: 795, height: 1000))
        XCTAssertEqual(slots[2], CGRect(x: 805, y: 0, width: 795, height: 1000))

        // Target #2 is 795x1000 -> taller than wide -> vertical split
        tree.insert(3, in: screen, gap: 10, padding: 0, preferredTarget: 2)
        slots = tree.layout(in: screen, gap: 10, padding: 0)
        XCTAssertEqual(slots[2], CGRect(x: 805, y: 0, width: 795, height: 495))
        XCTAssertEqual(slots[3], CGRect(x: 805, y: 505, width: 795, height: 495))
    }

    func testDuplicateInsertIsIgnoredAndRemovePromotesSibling() {
        var tree = BSPTree()
        tree.insert(1, in: screen, gap: 0, padding: 0)
        tree.insert(2, in: screen, gap: 0, padding: 0)
        tree.insert(2, in: screen, gap: 0, padding: 0)
        XCTAssertEqual(tree.windowIDs, [1, 2])

        tree.remove(1)
        let slots = tree.layout(in: screen, gap: 0, padding: 12)
        XCTAssertEqual(tree.windowIDs, [2])
        XCTAssertEqual(slots[2], CGRect(x: 12, y: 12, width: 1576, height: 976))

        tree.remove(2)
        XCTAssertEqual(tree.root, .empty)
        XCTAssertTrue(tree.windowIDs.isEmpty)
    }

    func testSwapToggleSplitResizeAndBalance() {
        var tree = BSPTree()
        tree.insert(10, in: screen, gap: 0, padding: 0)
        tree.insert(20, in: screen, gap: 0, padding: 0)

        XCTAssertTrue(tree.swap(10, 20))
        XCTAssertEqual(tree.windowIDs, [20, 10])
        XCTAssertFalse(tree.swap(10, 999))

        XCTAssertTrue(tree.toggleSplit(for: 20))
        let verticalSlots = tree.layout(in: screen, gap: 0, padding: 0)
        XCTAssertEqual(verticalSlots[20], CGRect(x: 0, y: 0, width: 1600, height: 500))
        XCTAssertEqual(verticalSlots[10], CGRect(x: 0, y: 500, width: 1600, height: 500))

        // Growing second child reduces split ratio
        XCTAssertTrue(tree.resize(windowID: 10, delta: 0.10))
        var resized = tree.layout(in: screen, gap: 0, padding: 0)
        XCTAssertEqual(resized[20]?.height ?? 0, 400, accuracy: 1)
        XCTAssertEqual(resized[10]?.height ?? 0, 600, accuracy: 1)

        // Clamped at minRatio (0.15)
        for _ in 0..<15 { tree.resize(windowID: 10, delta: 0.10) }
        resized = tree.layout(in: screen, gap: 0, padding: 0)
        XCTAssertEqual(resized[20]?.height ?? 0, 150, accuracy: 1)
        XCTAssertEqual(resized[10]?.height ?? 0, 850, accuracy: 1)

        tree.resetRatios()
        let balanced = tree.layout(in: screen, gap: 0, padding: 0)
        XCTAssertEqual(balanced[20]?.height ?? 0, 500, accuracy: 1)
        XCTAssertEqual(balanced[10]?.height ?? 0, 500, accuracy: 1)
    }

    func testInsertBesideSupportsAllEdgesAndCenterSwap() {
        var tree = BSPTree()
        tree.insert(1, in: screen, gap: 0, padding: 0)
        tree.insert(2, in: screen, gap: 0, padding: 0)
        XCTAssertTrue(tree.insertBeside(2, target: 1, edge: .top))
        var slots = tree.layout(in: screen, gap: 0, padding: 0)
        XCTAssertEqual(slots[2], CGRect(x: 0, y: 0, width: 1600, height: 500))
        XCTAssertEqual(slots[1], CGRect(x: 0, y: 500, width: 1600, height: 500))

        XCTAssertTrue(tree.insertBeside(3, target: 1, edge: .left))
        slots = tree.layout(in: screen, gap: 0, padding: 0)
        XCTAssertEqual(slots[3], CGRect(x: 0, y: 500, width: 800, height: 500))
        XCTAssertEqual(slots[1], CGRect(x: 800, y: 500, width: 800, height: 500))

        XCTAssertTrue(tree.insertBeside(3, target: 2, edge: .center))
        XCTAssertEqual(tree.windowIDs, [3, 2, 1])
    }

    func testDirectionalFocusFindsGeometricallyNearestNeighbors() {
        var tree = BSPTree()
        tree.insert(1, in: screen, gap: 8, padding: 8)
        tree.insert(2, in: screen, gap: 8, padding: 8)
        tree.insert(3, in: screen, gap: 8, padding: 8, preferredTarget: 2)

        XCTAssertEqual(tree.neighbor(of: 1, direction: .right, in: screen, gap: 8, padding: 8), 2)
        XCTAssertEqual(tree.neighbor(of: 2, direction: .left, in: screen, gap: 8, padding: 8), 1)
        XCTAssertEqual(tree.neighbor(of: 2, direction: .down, in: screen, gap: 8, padding: 8), 3)
        XCTAssertEqual(tree.neighbor(of: 3, direction: .up, in: screen, gap: 8, padding: 8), 2)
        XCTAssertNil(tree.neighbor(of: 1, direction: .left, in: screen, gap: 8, padding: 8))
    }

    func testTiledDropResolverCenterAndEdges() {
        let slots: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 800, height: 1000),
            2: CGRect(x: 810, y: 0, width: 800, height: 1000),
        ]
        // Center 50% swaps two tiled windows
        let center = TiledDropResolver.resolve(pointerAX: CGPoint(x: 1210, y: 500), draggedID: 1, slots: slots, gap: 10)
        XCTAssertEqual(center?.targetID, 2)
        XCTAssertEqual(center?.edge, .center)
        XCTAssertEqual(center?.previewRect, slots[2])

        // Top edge of target 2
        let top = TiledDropResolver.resolve(pointerAX: CGPoint(x: 1210, y: 40), draggedID: 1, slots: slots, gap: 10)
        XCTAssertEqual(top?.edge, .top)
        XCTAssertEqual(top?.previewRect, CGRect(x: 810, y: 0, width: 800, height: 495))

        // Hovering own slot yields nil
        XCTAssertNil(TiledDropResolver.resolve(pointerAX: CGPoint(x: 400, y: 500), draggedID: 1, slots: slots, gap: 10))
        // Untiled dragged ID does not offer center swap, drops to nearest edge
        let untiledCenter = TiledDropResolver.resolve(pointerAX: CGPoint(x: 1210, y: 500), draggedID: 99, slots: slots, gap: 10)
        XCTAssertNotNil(untiledCenter)
        XCTAssertNotEqual(untiledCenter?.edge, .center)
    }

    func testHotkeysAreDisjointFromSnapLayoutAndCoverAllActions() {
        for mask in 0..<16 {
            let c = mask & 1 != 0, o = mask & 2 != 0, m = mask & 4 != 0, s = mask & 8 != 0
            let hypr = HyprTilingRules.acceptsHotkey(control: c, option: o, command: m, shift: s)
            let snap = SnapLayout.acceptsHotkey(control: c, option: o, command: m, shift: s)
            XCTAssertFalse(hypr && snap, "HyprMac and Snap hotkeys must never overlap")
        }
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 35), .retileAll)
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 4), .focus(.left))
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 123), .swap(.left))
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 1), .toggleSplit)
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 17), .toggleFloat)
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 46), .toggleMaximize)
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 24), .resizeGrow)
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 27), .resizeShrink)
        XCTAssertEqual(HyprTilingRules.action(forKeyCode: 29), .balanceSplits)
        XCTAssertNil(HyprTilingRules.action(forKeyCode: 999))

        let bindings = HyprTilingRules.hotkeyBindings
        XCTAssertEqual(bindings.count, 15)
        XCTAssertEqual(Set(bindings.map(\.id)).count, 15, "Carbon hotkey IDs must be unique")
        XCTAssertEqual(Set(bindings.map(\.keyCode)).count, 15, "Key codes must be unique")
        for binding in bindings {
            XCTAssertEqual(HyprTilingRules.action(forKeyCode: Int64(binding.keyCode)), binding.action,
                           "Binding \(binding.label) must map 1-to-1 with action(forKeyCode:)")
            XCTAssertFalse(binding.label.isEmpty)
        }
        // Even if key codes overlap with SnapLayout (e.g. arrow keys 123...126), modifier masks are strictly disjoint.
        XCTAssertTrue(HyprTilingRules.acceptsHotkey(control: true, option: true, command: false, shift: true))
        XCTAssertFalse(SnapLayout.acceptsHotkey(control: true, option: true, command: false, shift: true))
    }

    func testWindowEligibilityFiltersSystemFloatingSmallAndExcluded() {
        let excluded = Set(HyprTilingRules.defaultExcludedBundleIDs)
        let okRect = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertTrue(HyprTilingRules.isEligibleWindow(
            layer: 0, alpha: 1.0, bounds: okRect, subrole: "AXStandardWindow",
            isResizable: true, bundleID: "com.apple.Safari", excludedBundleIDs: excluded, isOwnNonBrowser: false
        ))
        XCTAssertFalse(HyprTilingRules.isEligibleWindow(
            layer: 1, alpha: 1.0, bounds: okRect, subrole: "AXStandardWindow",
            isResizable: true, bundleID: "com.apple.Safari", excludedBundleIDs: excluded, isOwnNonBrowser: false
        ))
        XCTAssertFalse(HyprTilingRules.isEligibleWindow(
            layer: 0, alpha: 1.0, bounds: okRect, subrole: "AXDialog",
            isResizable: true, bundleID: "com.apple.Safari", excludedBundleIDs: excluded, isOwnNonBrowser: false
        ))
        XCTAssertFalse(HyprTilingRules.isEligibleWindow(
            layer: 0, alpha: 1.0, bounds: CGRect(x: 0, y: 0, width: 150, height: 150), subrole: "AXStandardWindow",
            isResizable: true, bundleID: "com.apple.Safari", excludedBundleIDs: excluded, isOwnNonBrowser: false
        ))
        XCTAssertFalse(HyprTilingRules.isEligibleWindow(
            layer: 0, alpha: 1.0, bounds: okRect, subrole: "AXStandardWindow",
            isResizable: true, bundleID: "com.apple.calculator", excludedBundleIDs: excluded, isOwnNonBrowser: false
        ))
        XCTAssertFalse(HyprTilingRules.isEligibleWindow(
            layer: 0, alpha: 1.0, bounds: okRect, subrole: "AXStandardWindow",
            isResizable: false, bundleID: "com.apple.Safari", excludedBundleIDs: excluded, isOwnNonBrowser: false
        ))
    }

    func testWindowIDFromNSWindowNumberRejectsNegativeZeroAndOverflow() {
        XCTAssertNil(HyprTilingRules.windowID(fromNSWindowNumber: -1))
        XCTAssertNil(HyprTilingRules.windowID(fromNSWindowNumber: 0))
        XCTAssertNil(HyprTilingRules.windowID(fromNSWindowNumber: Int.min))
        XCTAssertNil(HyprTilingRules.windowID(fromNSWindowNumber: Int(UInt32.max) + 1))
        XCTAssertEqual(HyprTilingRules.windowID(fromNSWindowNumber: 42), 42)
        XCTAssertEqual(HyprTilingRules.windowID(fromNSWindowNumber: Int(UInt32.max)), UInt32.max)
    }
}
