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

    /// A capture taken mid-way into the Stage Manager strip is tilted although its frame is not tile-sized; the pixels
    /// decide (owner, 2026-10-21: TradingView's switcher card).
    func testTiltIsDetectedFromThePixelsAndAnUprightWindowIsLeftAlone() {
        func image(_ quad: [CGPoint]) -> CGImage {
            let ctx = CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
            ctx.move(to: quad[0]); for p in quad.dropFirst() { ctx.addLine(to: p) }; ctx.closePath(); ctx.fillPath()
            return ctx.makeImage()!
        }
        // CG y up: the right edge shorter, like the measured Claude tile (left 5…291, right 33…293 in y-down pixels).
        let tilted = image([CGPoint(x: 6, y: 295), CGPoint(x: 280, y: 267), CGPoint(x: 282, y: 7), CGPoint(x: 6, y: 9)])
        XCTAssertTrue(ScreenCaptureProvider.straightened(tilted).wasTilted)
        let upright = image([CGPoint(x: 6, y: 290), CGPoint(x: 290, y: 290), CGPoint(x: 290, y: 10), CGPoint(x: 6, y: 10)])
        let s = ScreenCaptureProvider.straightened(upright)
        XCTAssertFalse(s.wasTilted, "a flat window is not warped")
        XCTAssertTrue(s.image === upright)
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

    /// Measured 2026-10-20: Finder with one 3-tab window and one other window listed 5 CG windows; AX lists 2.
    func testAccessibilityDecidesWhatAWindowIs() {
        let finder = [ref(1930, "Downloads", w: 84, h: 160, stage: true), ref(53, "docs", w: 840, h: 1021, current: false),
                      ref(51, "opencode", w: 83, h: 150, current: false, stage: true), ref(50, "Downloads", w: 83, h: 160, stage: true)]
        XCTAssertEqual(Set(WindowPreviewStore.dockWindowCards(finder, axWindows: [50, 1930]).map(\.id)), [50, 1930], "tabs are not windows")
        XCTAssertEqual(WindowPreviewStore.dockWindowCards(finder, axWindows: nil).count, 4, "without AX the CG heuristics stay")
        XCTAssertEqual(WindowPreviewStore.dockWindowCards(finder, axWindows: [999]).count, 4, "an AX list that matches nothing is ignored")
        let claude = [ref(3056, "", w: 800, h: 600, current: false), ref(3053, "", w: 500, h: 500, current: false), ref(3051, "Claude", w: 1510, h: 1022)]
        XCTAssertEqual(WindowPreviewStore.dockWindowCards(claude, axWindows: [3051]).map(\.id), [3051])
        XCTAssertEqual(windowPanelDimensions(count: 1).withExtraHeight(60).panelHeight, windowPanelDimensions(count: 1).panelHeight + 60)
    }

    /// Owner, 2026-10-20: every app's preview the same size — one fixed card per window, the browser's own card.
    func testEveryCardIsTheSameFixedSizeAndMatchesTheBrowserCard() {
        let browser = browserPanelDimensions(tabCount: 1)
        for n in 1...6 {
            let d = windowPanelDimensions(count: n)
            XCTAssertEqual(d.cardWidth, browser.cardWidth, "n=\(n): the same card as a browser tab")
            XCTAssertEqual(d.cardHeight, browser.cardHeight)
            XCTAssertEqual(d.panelHeight, browser.panelHeight, "n=\(n): the panel never changes height")
            let k = CGFloat(min(n, 4))
            XCTAssertEqual(d.panelWidth, k * d.cardWidth + (k - 1) * DockCard.gap + 2 * DockCard.padding, accuracy: 0.001, "n=\(n): only the card count changes the width")
        }
        XCTAssertEqual(windowPanelDimensions(count: 1).panelWidth, browser.panelWidth, "one window = exactly Chrome's panel")
        XCTAssertEqual(DockCard.width, 200, "the switcher's card width")
        XCTAssertEqual(DockCard.thumbWidth, 184); XCTAssertEqual(DockCard.thumbHeight, 86, "the switcher's picture")
        XCTAssertEqual(windowPanelDimensions(count: 1).panelHeight, 8 + 22 + 8 + 86 + 8 + 24)
    }

    func testTheSwitcherUsesRealWindowsPerApp() {
        let wins = [ref(172, "TradingView", w: 800, h: 600, current: false), ref(176, "USOIL", w: 143, h: 148, stage: true)]
            .map { Ref(id: $0.id, ownerPID: 7, ownerName: "TV", title: $0.title, bounds: $0.bounds, isOnCurrentSpace: $0.isOnCurrentSpace,
                       isStageMiniature: $0.isStageMiniature) }
            + [Ref(id: 9, ownerPID: 8, ownerName: "Other", title: "x", bounds: CGRect(x: 0, y: 0, width: 800, height: 600))]
        let real = WindowPreviewStore.realWindows(wins, axWindowIDs: { $0 == 7 ? [176] : nil })
        XCTAssertEqual(real.map(\.id), [176, 9], "the hidden 800×600 helper is not TradingView's window; apps without AX keep theirs")
        XCTAssertEqual(WindowPreviewStore.realWindows(wins, axWindowIDs: { _ in [12345] }).count, 3, "an AX list matching nothing is ignored")
    }
}
