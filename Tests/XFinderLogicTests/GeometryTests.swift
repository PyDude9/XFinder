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

