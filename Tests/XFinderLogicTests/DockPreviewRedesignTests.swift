import XCTest
import AppKit

/// 2026-10-19 — the Dock preview: thumbnails that go stale or keep a Stage Manager tilt, and the per-window cards.
final class DockPreviewRedesignTests: XCTestCase {
    typealias Ref = WindowPreviewStore.WindowRef
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testAnUprightPictureIsNeverReplacedByAStripTile() {
        let cache = LRUThumbnailCache(capacity: 4)
        let upright = NSImage(size: NSSize(width: 800, height: 500)), tile = NSImage(size: NSSize(width: 143, height: 149))
        cache.set(7, image: upright, fromProxy: false, at: t0)
        cache.set(7, image: tile, fromProxy: true, at: t0.addingTimeInterval(5))
        XCTAssertTrue(cache.get(7) === upright, "the tilted strip tile must not overwrite the flat picture")
        XCTAssertEqual(cache.entry(7)?.capturedAt, t0)
        let newer = NSImage(size: NSSize(width: 800, height: 500))
        cache.set(7, image: newer, fromProxy: false, at: t0.addingTimeInterval(9))
        XCTAssertTrue(cache.get(7) === newer, "a newer upright picture does replace it")
        cache.set(8, image: tile, fromProxy: true, at: t0)
        XCTAssertTrue(cache.get(8) === tile, "with nothing better, the tile picture is kept")
        cache.set(8, image: upright, fromProxy: false, at: t0)
        XCTAssertFalse(cache.entry(8)!.fromProxy, "and an upright one replaces it")
    }

    func testFreshnessRecapturesStaleAndTilePictures() {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        XCTAssertTrue(ThumbnailFreshness.needsCapture(nil, now: t0))
        let fresh = LRUThumbnailCache.Entry(image: img, capturedAt: t0, fromProxy: false)
        XCTAssertFalse(ThumbnailFreshness.needsCapture(fresh, now: t0.addingTimeInterval(1.9)))
        XCTAssertTrue(ThumbnailFreshness.needsCapture(fresh, now: t0.addingTimeInterval(2.0)), "the old cache never expired — stale previews")
        let tile = LRUThumbnailCache.Entry(image: img, capturedAt: t0, fromProxy: true)
        XCTAssertTrue(ThumbnailFreshness.needsCapture(tile, now: t0), "a tile picture is retried: the window may be back on stage")
    }

    func testCaptureSizeIsCappedForThumbnails() {
        let full = ThumbnailFreshness.captureSize(frame: CGSize(width: 1728, height: 1117), scale: 2, maxPixels: 800)
        XCTAssertEqual(full.width, 800, "a full-screen window was captured at 3456 px for a 300-pt thumbnail")
        XCTAssertEqual(full.height, 517)
        let small = ThumbnailFreshness.captureSize(frame: CGSize(width: 300, height: 200), scale: 2, maxPixels: 800)
        XCTAssertEqual(small.width, 600, "small windows keep full Retina detail")
        XCTAssertEqual(small.height, 400)
    }

    func testOneStripTileRuleForStoreAndCapture() {
        XCTAssertTrue(ScreenCaptureProvider.isStageManagerProxy(frame: CGRect(x: 15, y: 412, width: 143, height: 149)), "measured Claude tile")
        XCTAssertTrue(ScreenCaptureProvider.isStageManagerProxy(frame: CGRect(x: 15, y: 412, width: 157, height: 148)), "measured Chrome tile")
        XCTAssertFalse(ScreenCaptureProvider.isStageManagerProxy(frame: CGRect(x: 414, y: 139, width: 900, height: 632)))
    }

    func ref(_ id: CGWindowID, _ title: String, w: CGFloat = 800, h: CGFloat = 600, current: Bool = true, stage: Bool = false) -> Ref {
        Ref(id: id, ownerPID: 1, ownerName: "App", title: title, bounds: CGRect(x: 100, y: 100, width: w, height: h),
            isOnCurrentSpace: current, isStageMiniature: stage)
    }

    func testDockCardsKeepParkedWindowsDropPalettesAndOrderSensibly() {
        let cards = WindowPreviewStore.dockWindowCards([
            ref(1, "", current: true),                   // untitled
            ref(2, "Palette", w: 200, h: 120),           // utility window
            ref(3, "Other Space", current: false),
            ref(4, "Parked", w: 143, h: 149, current: false, stage: true),
            ref(5, "Main"),
        ])
        XCTAssertEqual(cards.map(\.id), [4, 5, 3, 1], "titled on stage/strip first (z-order kept), then other Space, then untitled; no palette")
        XCTAssertEqual(WindowPreviewStore.dockWindowCards([ref(9, "Tiny", w: 200, h: 100)]).map(\.id), [9], "a palette that is all there is still shows")
        XCTAssertEqual(WindowPreviewStore.dockMaxCards, 4)
    }

    func testPanelDimensionsFitTheCards() {
        for n in 1...6 {
            let d = windowPanelDimensions(count: n)
            let k = CGFloat(min(n, 4))
            XCTAssertEqual(d.panelWidth, k * d.cardWidth + (k - 1) * 10 + 24, accuracy: 0.001, "n=\(n)")
            XCTAssertEqual(d.thumbHeight / d.thumbWidth, 10.0 / 16.0, accuracy: 0.01, "16:10 thumbnails, n=\(n)")
            XCTAssertEqual(d.panelHeight, 12 + 28 + 6 + d.thumbHeight + 22 + 12, accuracy: 0.001)
        }
        XCTAssertGreaterThan(windowPanelDimensions(count: 1).cardWidth, windowPanelDimensions(count: 4).cardWidth, "fewer windows ⇒ bigger cards")
        XCTAssertLessThan(windowPanelDimensions(count: 4).panelWidth, 1000, "four cards fit a 13-inch screen")
    }
}
