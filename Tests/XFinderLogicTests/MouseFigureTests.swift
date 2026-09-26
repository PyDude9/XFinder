import XCTest

/// The mouse figure on the "Chuột & cử chỉ" page (PATCH v10.1 R2).
///
/// ── Why these are tests and not a screenshot ──────────────────────────────────────────
/// The user's report was *"mặc định giao diện này là Magic Mouse nên chỉ có 4 nút 4 hướng,
/// chứ ko phải smart mouse có nhiều button"* — i.e. the **figure** was making a claim about
/// the hardware that the page's own data did not support. The fix is a silhouette with a
/// thumb rest, and the two properties that make it a multi-button mouse rather than a pill
/// are geometry, not taste:
///
///  1. it is **not** a circle — the widest point on the left and the widest point on the
///     right sit at different heights, and the left one is the lower of the two;
///  2. the thumb rest is in the **lower-left**, which is where a thumb actually is.
///
/// Both are asserted against `MouseFigureOutline`, which is plain numbers in a
/// Foundation-only file. That placement is the point: a SwiftUI `Path` could not be reached
/// from this package, and the three mutations that stayed green in earlier rounds all lived
/// in code no test could compile.
final class MouseFigureTests: XCTestCase {

    // MARK: - The outline is a mouse, not a circle

    /// The property that a pill cannot have. A stadium/circle is symmetric, so its extreme
    /// points are level with each other; this outline's are not, and the left one is lower.
    func testOutlineIsNotACircleAndTheThumbRestIsTheLowerSide() {
        let left = MouseFigureOutline.leftMost
        let right = MouseFigureOutline.rightMost
        XCTAssertGreaterThan(left.y, right.y + 0.2,
                             "the left extreme (thumb rest) must sit clearly lower than the "
                             + "right one, or the figure is symmetric — i.e. a pill")
    }

    /// Neither extreme may sit on the vertical midline, which is where a stadium's straight
    /// sides put it. This is what stops the figure collapsing back into a Magic Mouse.
    func testNeitherExtremeSitsAtTheVerticalMiddle() {
        XCTAssertGreaterThan(abs(MouseFigureOutline.leftMost.y - 0.5), 0.1)
        XCTAssertGreaterThan(abs(MouseFigureOutline.rightMost.y - 0.5), 0.1)
    }

    /// The outline must actually reach both edges of the rect it is drawn in, or the figure
    /// floats inside its frame and every chip offset tuned against the body edge is wrong.
    func testOutlineReachesBothEdgesOfItsRect() {
        XCTAssertLessThanOrEqual(MouseFigureOutline.leftMost.x, 0.02)
        XCTAssertGreaterThanOrEqual(MouseFigureOutline.rightMost.x, 0.98)
    }

    /// Every vertex stays inside the drawing rect (with a hair of tolerance), and there are
    /// enough of them for the curve to read as a silhouette rather than a polygon.
    func testOutlineIsWellFormedAndInsideItsRect() {
        let points = MouseFigureOutline.points
        XCTAssertGreaterThanOrEqual(points.count, 12,
                                    "too few vertices for a smooth silhouette")
        for point in points {
            XCTAssertGreaterThanOrEqual(point.x, -0.02)
            XCTAssertLessThanOrEqual(point.x, 1.02)
            XCTAssertGreaterThanOrEqual(point.y, -0.02)
            XCTAssertLessThanOrEqual(point.y, 1.02)
        }
    }

    /// The front of the body must be wide enough that the two main-button chips still land
    /// on it. Those chips are 46 pt wide on a 116 pt body, i.e. they reach `x = 0.5 ± 0.198`
    /// at `y ≈ 0.12`; a narrow "nose" would leave them floating in mid-air, which is a worse
    /// drawing than a blunt front. This pins the blunt front.
    func testOutlineIsWideEnoughWhereTheMainButtonChipsSit() {
        let nearFront = MouseFigureOutline.points.filter { $0.y > 0.02 && $0.y < 0.17 }
        XCTAssertTrue(nearFront.contains { $0.x <= 0.06 },
                      "no wide vertex on the front left — the Button 1 chip would float")
        XCTAssertTrue(nearFront.contains { $0.x >= 0.94 },
                      "no wide vertex on the front right — the Button 2 chip would float")
    }

    // MARK: - The thumb rest

    /// Lower-left, not centred: a centred panel would be a decoration, and the three
    /// controls that sit on this one (the two side buttons and the Sniper) are all on the
    /// left half of the mouse.
    func testThumbRestIsInTheLowerLeft() {
        let centre = MouseFigureOutline.thumbRest.centre
        XCTAssertLessThan(centre.x, 0.5, "the thumb rest is on the left half")
        XCTAssertGreaterThan(centre.y, 0.5, "the thumb rest is in the lower half")
    }

    /// It must stay inside the body, or it reads as a floating box rather than a region of
    /// the mouse.
    func testThumbRestStaysInsideTheBody() {
        let region = MouseFigureOutline.thumbRest
        XCTAssertGreaterThanOrEqual(region.x, 0.0)
        XCTAssertGreaterThanOrEqual(region.y, 0.0)
        XCTAssertLessThanOrEqual(region.x + region.width, 1.0)
        XCTAssertLessThanOrEqual(region.y + region.height, 1.0)
        XCTAssertGreaterThan(region.width, 0.0)
        XCTAssertGreaterThan(region.height, 0.0)
    }

    /// The seam separates the two main buttons, so it belongs in the front half of the body
    /// and must run downwards — an inverted or mid-body seam would draw a line through the
    /// palm instead of between the buttons.
    func testButtonSeamRunsThroughTheFrontHalf() {
        XCTAssertLessThan(MouseFigureOutline.seamTopY, MouseFigureOutline.seamBottomY)
        XCTAssertLessThan(MouseFigureOutline.seamBottomY, 0.5,
                          "the seam is between the two main buttons, so it ends well above "
                          + "the palm")
    }
}
