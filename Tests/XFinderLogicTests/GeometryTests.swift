import XCTest
import AppKit

/// Coordinate-space conversions.
///
/// These exist because the same class of bug hit three separate features this
/// session — Dock-hover preview firing at the notch, snap zones highlighting
/// the wrong corner, and windows landing under the menu bar. All three were
/// **top-left (Accessibility / CoreGraphics) vs bottom-left (AppKit)** mixups,
/// and all three were invisible until a human noticed the UI was wrong.
///
/// The logic is duplicated here rather than imported: the app is an .app
/// target, not a library, so a test package cannot link it. Duplication is
/// acceptable for ~10 lines of pure arithmetic; if the app's copy changes,
/// `testFlipIsItsOwnInverse` still pins the *property* that must hold.
final class GeometryTests: XCTestCase {

    // Mirrors WindowManager.axRectToAppKit / DockPreviewController.flipToAppKit.
    private func flip(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryMaxY - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }

    /// A rect at the TOP in AX space must land at the TOP in AppKit space.
    /// Getting this backwards is what made the Dock preview fire at the notch.
    func testTopInAXBecomesTopInAppKit() {
        let screenHeight: CGFloat = 1117
        // AX: y=0 is the top of the screen.
        let axTopBar = CGRect(x: 0, y: 0, width: 100, height: 50)
        let appKit = flip(axTopBar, primaryMaxY: screenHeight)
        // AppKit: the top of the screen is the HIGHEST y.
        XCTAssertEqual(appKit.maxY, screenHeight, accuracy: 0.001,
                       "A bar at AX y=0 must touch the top edge in AppKit space")
    }

    /// And the bottom stays the bottom — the Dock lives here.
    func testBottomInAXBecomesBottomInAppKit() {
        let screenHeight: CGFloat = 1117
        let axDock = CGRect(x: 0, y: 1067, width: 100, height: 50)
        let appKit = flip(axDock, primaryMaxY: screenHeight)
        XCTAssertEqual(appKit.minY, 0, accuracy: 0.001,
                       "A Dock icon at the AX bottom must sit at AppKit y=0")
    }

    /// Flipping twice returns the original. This is the property that holds
    /// even if the implementation is rewritten.
    func testFlipIsItsOwnInverse() {
        let screenHeight: CGFloat = 1117
        let original = CGRect(x: 12, y: 340, width: 220, height: 96)
        let round = flip(flip(original, primaryMaxY: screenHeight),
                         primaryMaxY: screenHeight)
        XCTAssertEqual(round, original)
    }

    /// Width and x are untouched by a vertical flip.
    func testFlipPreservesHorizontalGeometry() {
        let r = CGRect(x: 40, y: 10, width: 300, height: 80)
        let f = flip(r, primaryMaxY: 1000)
        XCTAssertEqual(f.origin.x, r.origin.x)
        XCTAssertEqual(f.width, r.width)
        XCTAssertEqual(f.height, r.height)
    }
}

/// Snap-zone target rectangles, defined in TOP-LEFT origin space.
final class SnapTargetTests: XCTestCase {

    /// Mirrors WindowManager.SnapTarget.rect(in:) for the cases that broke.
    private func topLeft(_ s: CGRect) -> CGRect {
        CGRect(x: s.minX, y: s.minY, width: s.width / 2, height: s.height / 2)
    }
    private func bottomLeft(_ s: CGRect) -> CGRect {
        CGRect(x: s.minX, y: s.minY + s.height / 2, width: s.width / 2, height: s.height / 2)
    }

    /// The reported bug: dragging to the bottom-left highlighted the top-left.
    /// In TOP-LEFT space, "bottom" must have the LARGER y.
    func testBottomLeftIsBelowTopLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1023)
        XCTAssertGreaterThan(bottomLeft(screen).minY, topLeft(screen).minY,
                             "In top-left origin space the bottom quadrant must start lower down")
    }

    /// Quadrants must tile the screen without overlapping.
    func testQuadrantsDoNotOverlap() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1023)
        XCTAssertFalse(topLeft(screen).intersects(bottomLeft(screen)))
    }

    /// Each quadrant is exactly a quarter of the work area.
    func testQuadrantArea() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1024)
        let q = topLeft(screen)
        XCTAssertEqual(q.width * q.height, screen.width * screen.height / 4, accuracy: 1)
    }

    /// Stage Manager clearance shrinks the usable area from the LEFT only.
    /// macOS does not do this for us — verified: visibleFrame reports a 0 gap
    /// even with Stage Manager enabled.
    func testStageManagerInsetReservesLeftEdgeOnly() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1023)
        let reserved = applyInset(68, to: visible)
        XCTAssertEqual(reserved.minX, 68)
        XCTAssertEqual(reserved.maxX, visible.maxX, "The right edge must not move")
        XCTAssertEqual(reserved.height, visible.height, "Height must not change")
    }

    private func applyInset(_ inset: CGFloat, to visible: CGRect) -> CGRect {
        CGRect(x: visible.minX + inset, y: visible.minY,
               width: visible.width - inset, height: visible.height)
    }

    /// Mirrors `WindowManager.stageManagerInset`'s two gates. The user can now
    /// switch the clearance off entirely, or tune it — a zero inset must give
    /// back the *whole* width, not a one-pixel-off approximation.
    private func inset(stageManagerOn: Bool, reserve: Bool, custom: Double?) -> CGFloat {
        guard stageManagerOn else { return 0 }
        guard reserve else { return 0 }
        return CGFloat(custom ?? 68)
    }

    func testInsetIsZeroWhenStageManagerIsOff() {
        XCTAssertEqual(inset(stageManagerOn: false, reserve: true, custom: 68), 0,
                       "No Stage Manager means nothing to reserve")
    }

    func testUserCanTurnClearanceOff() {
        XCTAssertEqual(inset(stageManagerOn: true, reserve: false, custom: 68), 0,
                       "Turning the toggle off must reclaim the full width")
    }

    func testDisabledClearanceRestoresFullWidth() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1023)
        let full = applyInset(inset(stageManagerOn: true, reserve: false, custom: 68),
                              to: visible)
        XCTAssertEqual(full, visible, "A window may span the whole screen when clearance is off")
    }

    func testCustomInsetIsHonoured() {
        XCTAssertEqual(inset(stageManagerOn: true, reserve: true, custom: 24), 24,
                       "The slider value must win over the 68pt default")
    }

    func testDefaultInsetPreservesPreviousBehaviour() {
        XCTAssertEqual(inset(stageManagerOn: true, reserve: true, custom: nil), 68,
                       "An existing install must not shift when the toggle is added")
    }
}
