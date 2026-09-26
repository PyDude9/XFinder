import XCTest
import AppKit
@testable import XFinderLogicTests

final class MenuBarEngineTests: XCTestCase {

    // MARK: - MenuBarLayoutResolver Tests

    func testMenuBarLayoutResolverLeftIsHiddenRightIsVisible() {
        // Arrow is at x = 500, width = 20 -> midX = 510
        let arrowFrame = CGRect(x: 500, y: 0, width: 20, height: 24)

        // Item 1: Slack at x = 300, midX = 310 (< 510) -> hidden
        let slack = MenuBarInventoryItem(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            frame: CGRect(x: 300, y: 0, width: 20, height: 24)
        )

        // Item 2: Telegram at x = 600, midX = 610 (> 510) -> visible
        let telegram = MenuBarInventoryItem(
            bundleIdentifier: "ru.keepcoder.Telegram",
            frame: CGRect(x: 600, y: 0, width: 20, height: 24)
        )

        let inventory = [slack, telegram]
        let layout = MenuBarLayoutResolver.resolve(
            inventory: inventory,
            separatorFrame: arrowFrame,
            isLTR: true,
            excludingBundle: "com.xfinder.app"
        )

        XCTAssertEqual(layout.sections["com.tinyspeck.slackmacgap"], .hidden)
        XCTAssertEqual(layout.sections["ru.keepcoder.Telegram"], .visible)
        XCTAssertEqual(layout.bundles(in: [.visible]), ["ru.keepcoder.Telegram"])
        XCTAssertEqual(layout.bundles(in: [.hidden]), ["com.tinyspeck.slackmacgap"])
    }

    func testMenuBarLayoutResolverMultipleItemsSameAppWinsVisible() {
        let arrowFrame = CGRect(x: 500, y: 0, width: 20, height: 24)

        // App A has one icon to the left (hidden) and another icon to the right (visible)
        let itemHidden = MenuBarInventoryItem(
            bundleIdentifier: "com.example.multi",
            frame: CGRect(x: 200, y: 0, width: 20, height: 24)
        )
        let itemVisible = MenuBarInventoryItem(
            bundleIdentifier: "com.example.multi",
            frame: CGRect(x: 800, y: 0, width: 20, height: 24)
        )

        let layout = MenuBarLayoutResolver.resolve(
            inventory: [itemHidden, itemVisible],
            separatorFrame: arrowFrame,
            isLTR: true,
            excludingBundle: "com.xfinder.app"
        )

        // Most visible item wins (.visible < .hidden)
        XCTAssertEqual(layout.sections["com.example.multi"], .visible)
    }

    func testMenuBarLayoutResolverExcludesOwnBundleAndSystemItems() {
        let arrowFrame = CGRect(x: 500, y: 0, width: 20, height: 24)

        let ownItem = MenuBarInventoryItem(
            bundleIdentifier: "com.xfinder.app",
            frame: CGRect(x: 600, y: 0, width: 20, height: 24)
        )
        let controlCenter = MenuBarInventoryItem(
            bundleIdentifier: "com.apple.controlcenter",
            frame: CGRect(x: 900, y: 0, width: 20, height: 24)
        )
        let normalApp = MenuBarInventoryItem(
            bundleIdentifier: "com.spotify.client",
            frame: CGRect(x: 200, y: 0, width: 20, height: 24)
        )

        let layout = MenuBarLayoutResolver.resolve(
            inventory: [ownItem, controlCenter, normalApp],
            separatorFrame: arrowFrame,
            isLTR: true,
            excludingBundle: "com.xfinder.app"
        )

        XCTAssertNil(layout.sections["com.xfinder.app"], "Own bundle should be excluded from layout")
        XCTAssertNil(layout.sections["com.apple.controlcenter"], "System bundles should be excluded from layout")
        XCTAssertEqual(layout.sections["com.spotify.client"], .hidden)
    }

    // MARK: - Legacy Engine Geometry Math

    func testLegacyCollapseLengthBounds() {
        let screenWidths: [CGFloat] = [1280, 1440, 1728, 2560, 5120, 10000]

        for width in screenWidths {
            let collapsedLength = max(500, min(width * 2, 10_000))
            XCTAssertGreaterThanOrEqual(collapsedLength, 500)
            XCTAssertLessThanOrEqual(collapsedLength, 10_000)
        }
    }

    // MARK: - States and Results

    func testEngineStates() {
        XCTAssertEqual(MenuBarEngineState.expanded, MenuBarEngineState.expanded)
        XCTAssertEqual(MenuBarEngineState.collapsed, MenuBarEngineState.collapsed)
        XCTAssertEqual(MenuBarEngineState.calibrating, MenuBarEngineState.calibrating)
        XCTAssertEqual(MenuBarEngineState.unavailable, MenuBarEngineState.unavailable)
        XCTAssertNotEqual(MenuBarEngineState.expanded, MenuBarEngineState.collapsed)

        XCTAssertEqual(CollapseResult.collapsed, CollapseResult.collapsed)
        XCTAssertEqual(CollapseResult.unavailable, CollapseResult.unavailable)
        XCTAssertNotEqual(CollapseResult.collapsed, CollapseResult.unavailable)
    }
}
