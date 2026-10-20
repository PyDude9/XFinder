import XCTest
import Foundation
import CoreGraphics

/// Phase C: the ⌘-Tab switcher's new rules, through the real store with a fake window lister.
final class SwitcherPhaseCTests: XCTestCase {
    typealias S = WindowPreviewStore
    func ref(_ id: CGWindowID, _ pid: pid_t, _ owner: String, _ title: String, x: CGFloat = 0, w: CGFloat = 800) -> S.WindowRef {
        S.WindowRef(id: id, ownerPID: pid, ownerName: owner, title: title, bounds: CGRect(x: x, y: 100, width: w, height: 600))
    }

    func testExclusionNeverMatchesAnEmptyBundleID() {
        XCTAssertTrue(S.isExcluded(bundleID: "com.apple.Safari", excluded: ["com.apple.Safari"]))
        XCTAssertFalse(S.isExcluded(bundleID: "com.apple.Music", excluded: ["com.apple.Safari"]))
        XCTAssertFalse(S.isExcluded(bundleID: "", excluded: ["", "com.apple.Safari"]), "a window with no bundle id is never excluded")
    }

    func testAppKitScreenFrameConvertsToCGSpaceAndIntersectionDecidesMembership() {
        // Primary 1728×1117; an external 2560×1440 to the right, its bottom 200 pt below the primary's.
        let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let external = CGRect(x: 1728, y: -200, width: 2560, height: 1440)
        XCTAssertEqual(S.cgRect(forAppKitFrame: primary, primaryHeight: 1117), CGRect(x: 0, y: 0, width: 1728, height: 1117))
        let extCG = S.cgRect(forAppKitFrame: external, primaryHeight: 1117)
        XCTAssertEqual(extCG, CGRect(x: 1728, y: 1117 - 1240, width: 2560, height: 1440), "CG y grows downward from the primary's top")
        XCTAssertTrue(S.isOnScreen(ref(1, 1, "A", "a", x: 100), screenCG: S.cgRect(forAppKitFrame: primary, primaryHeight: 1117)))
        XCTAssertFalse(S.isOnScreen(ref(2, 1, "A", "b", x: 2000), screenCG: S.cgRect(forAppKitFrame: primary, primaryHeight: 1117)))
        XCTAssertTrue(S.isOnScreen(ref(3, 1, "A", "straddles", x: 1500, w: 800), screenCG: extCG), "partly on a screen counts")
    }

    @MainActor
    func testScreenFilterDropsWindowsOnOtherDisplays() {
        let store = S(captureProvider: MockScreenCaptureProvider(isAllowed: true))
        store.windowLister = { [self.ref(1, 10, "Safari", "Here", x: 100), self.ref(2, 20, "Terminal", "There", x: 3000)] }
        store.loadSwitchableWindows(screenCG: CGRect(x: 0, y: 0, width: 1728, height: 1117))
        XCTAssertEqual(store.previewItems.map(\.title), ["Here"])
        store.loadSwitchableWindows()
        XCTAssertEqual(store.previewItems.count, 2, "no filter ⇒ both")
    }

    /// Owner, 2026-10-20: the switcher's cards were blank because a hidden helper window was the app's "best" window.
    @MainActor
    func testTheSwitcherCardShowsTheAppsRealWindowNotAHiddenHelper() {
        let store = S(captureProvider: MockScreenCaptureProvider(isAllowed: true))
        store.windowLister = { [self.ref(172, 10, "TradingView", "", x: 100), self.ref(176, 10, "TradingView", "BTCUSDT", x: 100),
                                self.ref(3, 20, "Terminal", "zsh")] }
        store.axWindowIDs = { $0 == 10 ? [176] : nil }
        store.loadSwitchableWindows()
        let tv = store.previewItems.first { $0.windowIDs.contains(176) }
        XCTAssertEqual(tv?.windowID, 176, "the card captures the real window")
        XCTAssertEqual(tv?.windowCount, 1, "the helper is not counted")
    }

    @MainActor
    func testBackquoteFlipsBetweenOneCardPerAppAndTheAppsWindowsAndBack() {
        let store = S(captureProvider: MockScreenCaptureProvider(isAllowed: true))
        store.windowLister = { [self.ref(1, 10, "Safari", "GitHub"), self.ref(2, 10, "Safari", "Apple"), self.ref(3, 20, "Terminal", "zsh")] }
        store.loadSwitchableWindows()
        XCTAssertEqual(store.previewItems.count, 2); XCTAssertEqual(store.mode, .apps)
        store.select(index: 0)                                   // Safari's card
        store.toggleMode()
        XCTAssertEqual(store.mode, .windows(bundleID: "Safari"))
        XCTAssertEqual(store.previewItems.map(\.title), ["GitHub", "Apple"], "one card per window, z-order kept")
        XCTAssertEqual(store.selectedIndex, 0)
        XCTAssertTrue(store.previewItems.allSatisfy { !$0.isGroup && $0.windowCount == 1 })
        store.toggleMode()
        XCTAssertEqual(store.mode, .apps)
        XCTAssertEqual(store.previewItems.count, 2)
        // The SECOND app, so "back where we came from" is distinguishable from "back to the first card".
        store.select(index: 1)                                   // Terminal's card
        store.toggleMode()
        XCTAssertEqual(store.mode, .windows(bundleID: "Terminal"))
        XCTAssertEqual(store.previewItems.map(\.title), ["zsh"])
        store.toggleMode()
        XCTAssertEqual(store.mode, .apps)
        XCTAssertEqual(store.selectedIndex, 1, "back on the app we came from, not on the first card")
    }

    func testWindowItemsTitleUntitledWindowsByTheApp() {
        let items = S.windowItems(for: "x", wins: [ref(1, 1, "Preview", ""), ref(2, 1, "Preview", "Doc.pdf")], appName: "Preview")
        XCTAssertEqual(items.map(\.title), ["Preview", "Doc.pdf"])
    }

    func testRemovingAWindowShrinksAGroupAndDropsASingletonAndPicksANewRepresentative() {
        let group = PreviewItem(windowID: 1, bundleID: "a", title: "A", appName: "A", isGroup: true, windowCount: 3, windowIDs: [1, 2, 3])
        let single = PreviewItem(windowID: 9, bundleID: "b", title: "B", appName: "B")
        let after = S.removing(windowID: 1, from: [group, single])
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after[0].windowID, 2, "the closed representative is replaced by the next window")
        XCTAssertEqual(after[0].windowIDs, [2, 3]); XCTAssertEqual(after[0].windowCount, 2); XCTAssertTrue(after[0].isGroup)
        let pair = S.removing(windowID: 2, from: after)
        XCTAssertFalse(pair[0].isGroup, "two windows minus one is no longer a group")
        XCTAssertEqual(S.removing(windowID: 9, from: pair).map(\.bundleID), ["a"], "a one-window app disappears")
        XCTAssertEqual(S.removing(windowID: 42, from: pair).count, 2, "unknown id ⇒ unchanged")
    }

    func testSelectionIsClampedToTheDeck() {
        XCTAssertEqual(S.clampedSelection(5, count: 3), 2)
        XCTAssertEqual(S.clampedSelection(-1, count: 3), 0)
        XCTAssertEqual(S.clampedSelection(0, count: 0), 0)
        XCTAssertEqual(S.clampedSelection(1, count: 3), 1)
    }

    @MainActor
    func testClosingTheLastWindowOfTheAppInWindowModeFallsBackToTheAppDeck() {
        let store = S(captureProvider: MockScreenCaptureProvider(isAllowed: true))
        store.windowLister = { [self.ref(1, 10, "Safari", "GitHub"), self.ref(3, 20, "Terminal", "zsh")] }
        store.loadSwitchableWindows()
        store.select(index: 0); store.toggleMode()
        XCTAssertEqual(store.mode, .windows(bundleID: "Safari"))
        store.removeWindow(id: 1)
        XCTAssertEqual(store.mode, .apps, "nothing left to show for Safari ⇒ back to apps")
        XCTAssertEqual(store.previewItems.map(\.bundleID), ["Terminal"])
        XCTAssertEqual(store.selectedIndex, 0)
    }

    @MainActor
    func testHidingAnAppDropsEveryCardAndZoomStateResetsOnClear() {
        let store = S(captureProvider: MockScreenCaptureProvider(isAllowed: true))
        store.windowLister = { [self.ref(1, 10, "Safari", "GitHub"), self.ref(2, 10, "Safari", "Apple"), self.ref(3, 20, "Terminal", "zsh")] }
        store.loadSwitchableWindows()
        store.select(index: 1)                                   // Terminal
        store.removeApp(bundleID: "Terminal")
        XCTAssertEqual(store.previewItems.map(\.bundleID), ["Safari"])
        XCTAssertEqual(store.selectedIndex, 0, "clamped after the last card went away")
        store.toggleZoom(); XCTAssertTrue(store.isZoomed)
        store.clear()
        XCTAssertFalse(store.isZoomed); XCTAssertNil(store.zoomImage); XCTAssertEqual(store.mode, .apps)
    }
}
