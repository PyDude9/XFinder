import Foundation
import AppKit
import ScreenCaptureKit

/// Thread-safe LRU cache for window thumbnails.
///
/// 2026-10-19 (owner: "the preview is taken skewed"): entries used to live until evicted — the FIRST capture of a
/// window was shown forever, stale, and when it happened while the window sat in the Stage Manager strip (macOS draws
/// it there as a small 3-D tilted tile, and ScreenCaptureKit captures exactly that) the tilt stayed for good. Entries
/// now carry when they were taken and whether they came from such a tile; an upright image is never replaced by a
/// tile image, and callers recapture by `ThumbnailFreshness`.
public final class LRUThumbnailCache: @unchecked Sendable {
    public struct Entry {
        public let image: NSImage
        public let capturedAt: Date
        /// Taken from the Stage Manager strip tile (straightened, low resolution) or by the legacy path.
        public let fromProxy: Bool
        /// The longest-side pixel cap it was captured at; a request for more (the switcher's zoom) recaptures.
        public var maxPixels: CGFloat = ThumbnailFreshness.cardPixels
    }

    private let lock = NSLock()
    public let capacity: Int
    private var entries: [CGWindowID: (entry: Entry, lastAccess: Date)] = [:]

    public init(capacity: Int = 40) {
        self.capacity = capacity
    }

    public func get(_ key: CGWindowID) -> NSImage? { entry(key)?.image }

    public func entry(_ key: CGWindowID) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let e = entries[key] else { return nil }
        entries[key] = (e.entry, Date())
        return e.entry
    }

    /// An upright image is never replaced by a tile image: the sharp, flat picture of the window from when it was on
    /// stage is worth more than a blurred un-warp of the strip tile.
    public func set(_ key: CGWindowID, image: NSImage, fromProxy: Bool = false, at date: Date = Date(),
                    maxPixels: CGFloat = ThumbnailFreshness.cardPixels) {
        lock.lock()
        defer { lock.unlock() }
        if fromProxy, let old = entries[key]?.entry, !old.fromProxy { return }
        if entries.count >= capacity, entries[key] == nil {
            if let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
                entries.removeValue(forKey: oldest)
            }
        }
        entries[key] = (Entry(image: image, capturedAt: date, fromProxy: fromProxy, maxPixels: maxPixels), Date())
    }

    public func remove(_ key: CGWindowID) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}

/// When a cached thumbnail is good enough to show without capturing again (pure, tested).
public enum ThumbnailFreshness {
    /// A preview opened twice within this long reuses the picture; after it, the window may have changed.
    public static let maxAge: TimeInterval = 2
    /// Longest side of a card picture, in pixels: the Dock and switcher cards draw 184 × 86 pt, 368 px wide on a Retina
    /// screen. Measured 2026-10-21: at the old 800-px cap the cached pictures were ~25 MB of the app's 52 MB footprint
    /// (eight 1.6 MB blocks in `heap`), with room for 40.
    public static let cardPixels: CGFloat = 480
    /// The switcher's Space zoom shows one window large.
    public static let zoomPixels: CGFloat = 1600

    /// Capture again when nothing is cached, when the cached picture is a strip-tile un-warp (the window may be back
    /// on stage), or when the upright picture is older than `maxAge`.
    public static func needsCapture(_ entry: LRUThumbnailCache.Entry?, now: Date, maxAge: TimeInterval = maxAge,
                                    wantPixels: CGFloat = cardPixels) -> Bool {
        guard let entry else { return true }
        if entry.fromProxy { return true }
        if entry.maxPixels < wantPixels { return true }   // a card picture is too small for the zoom
        return now.timeIntervalSince(entry.capturedAt) >= maxAge
    }

    /// Pixel size to capture a window of `frame` points at: the screen's scale, but never a longest side above
    /// `maxPixels` — a full-screen window at 2× was 3456 × 2234 px (~30 MB) for a 300-pt thumbnail, ×40 in the cache.
    public static func captureSize(frame: CGSize, scale: CGFloat, maxPixels: CGFloat) -> (width: Int, height: Int) {
        let longest = max(frame.width, frame.height, 1)
        let factor = min(scale, maxPixels / longest)
        return (max(1, Int((frame.width * factor).rounded())), max(1, Int((frame.height * factor).rounded())))
    }

    /// Stage Manager warm captures: at most one per app per this long.
    public static let warmInterval: TimeInterval = 30

    /// True when `pid` may be warmed now, and records it. Every app switch used to start a ScreenCaptureKit enumeration of
    /// all on-screen windows — ⌘-Tab between three apps all day, with no Dock hover at all. Entries older than the interval
    /// are dropped first, so the log holds only the apps switched to in the last 30 s.
    public static func claimWarm(pid: pid_t, now: Date, log: inout [pid_t: Date]) -> Bool {
        log = log.filter { now.timeIntervalSince($0.value) < warmInterval }
        guard log[pid] == nil else { return false }
        log[pid] = now
        return true
    }
}

/// Protocol for screen capture operations.
public protocol ScreenCaptureProviding: Sendable {
    func isScreenRecordingAllowed() -> Bool
    func captureWindow(windowID: CGWindowID, maxSize: CGFloat) async -> NSImage?
    func captureWindows(windowIDs: [CGWindowID], maxSize: CGFloat) async -> [CGWindowID: NSImage]
}

/// ScreenCaptureKit implementation of ScreenCaptureProviding.
public final class ScreenCaptureProvider: ScreenCaptureProviding, @unchecked Sendable {
    public static let shared = ScreenCaptureProvider()

    public let cache: LRUThumbnailCache

    public init(cache: LRUThumbnailCache = LRUThumbnailCache(capacity: 24)) {
        self.cache = cache
    }

    public func isScreenRecordingAllowed() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    public static func isStageManagerProxy(frame: CGRect) -> Bool {
        (frame.width <= 260 && frame.height <= 260) || (frame.origin.x <= 80 && frame.width <= 280)
    }

    /// Automatically detects if an image has Stage Manager 3D perspective distortion,
    /// and un-warps it into an upright, flat, sharp rectangle using CoreImage CIPerspectiveCorrection.
    public static func straightenImageIfNeeded(_ cgImage: CGImage) -> CGImage { straightened(cgImage).image }

    /// The image, un-warped when it shows Stage Manager's 3-D tilt, and whether it did.
    public static func straightened(_ cgImage: CGImage) -> (image: CGImage, wasTilted: Bool) {
        let warped = straightenCore(cgImage)
        return (warped, warped !== cgImage)
    }

    private static func straightenCore(_ cgImage: CGImage) -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 30, height > 30 else { return cgImage }

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else { return cgImage }

        let bpp = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        guard bpp >= 4 else { return cgImage }

        var minX = width
        var maxX = 0
        for x in stride(from: 0, to: width, by: 2) {
            for y in stride(from: 0, to: height, by: 4) {
                let offset = y * bytesPerRow + x * bpp
                let a = max(ptr[offset], ptr[offset + 3])
                if a > 30 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                }
            }
        }

        guard maxX - minX > 30 else { return cgImage }

        let leftCol = min(minX + 3, width - 1)
        let rightCol = max(maxX - 3, 0)

        var leftTop = height, leftBottom = 0
        var rightTop = height, rightBottom = 0

        for y in 0..<height {
            let aLeft = max(ptr[y * bytesPerRow + leftCol * bpp], ptr[y * bytesPerRow + leftCol * bpp + 3])
            if aLeft > 30 {
                if y < leftTop { leftTop = y }
                if y > leftBottom { leftBottom = y }
            }
            let aRight = max(ptr[y * bytesPerRow + rightCol * bpp], ptr[y * bytesPerRow + rightCol * bpp + 3])
            if aRight > 30 {
                if y < rightTop { rightTop = y }
                if y > rightBottom { rightBottom = y }
            }
        }

        let leftH = CGFloat(leftBottom - leftTop)
        let rightH = CGFloat(rightBottom - rightTop)

        let ratio = leftH > 0 ? rightH / leftH : 1.0
        let isTilted = abs(ratio - 1.0) > 0.04 || abs(CGFloat(leftBottom - rightBottom)) > 8

        if !isTilted {
            return cgImage
        }

        let ciH = CGFloat(height)
        let topLeft = CIVector(x: CGFloat(leftCol), y: ciH - CGFloat(leftTop))
        let bottomLeft = CIVector(x: CGFloat(leftCol), y: ciH - CGFloat(leftBottom))
        let topRight = CIVector(x: CGFloat(rightCol), y: ciH - CGFloat(rightTop))
        let bottomRight = CIVector(x: CGFloat(rightCol), y: ciH - CGFloat(rightBottom))

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return cgImage }
        let ciImage = CIImage(cgImage: cgImage)
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(topLeft, forKey: "inputTopLeft")
        filter.setValue(topRight, forKey: "inputTopRight")
        filter.setValue(bottomRight, forKey: "inputBottomRight")
        filter.setValue(bottomLeft, forKey: "inputBottomLeft")

        guard let outputCI = filter.outputImage else { return cgImage }
        let context = CIContext(options: nil)
        return context.createCGImage(outputCI, from: outputCI.extent) ?? cgImage
    }

    public func captureWindow(windowID: CGWindowID, maxSize: CGFloat = ThumbnailFreshness.cardPixels) async -> NSImage? {
        await captureWindows(windowIDs: [windowID], maxSize: maxSize)[windowID]
    }

    /// Fresh cached pictures are returned as they are; the rest are captured in one ScreenCaptureKit query. A window
    /// that is a Stage Manager strip tile keeps its upright picture when one exists (`LRUThumbnailCache.set`).
    public func captureWindows(windowIDs: [CGWindowID], maxSize: CGFloat = ThumbnailFreshness.cardPixels) async -> [CGWindowID: NSImage] {
        guard !windowIDs.isEmpty else { return [:] }
        var result: [CGWindowID: NSImage] = [:]
        var neededIDs: [CGWindowID] = []
        let now = Date()
        for wid in windowIDs {
            let entry = cache.entry(wid)
            if let entry, !ThumbnailFreshness.needsCapture(entry, now: now, wantPixels: maxSize) { result[wid] = entry.image } else { neededIDs.append(wid) }
        }
        guard !neededIDs.isEmpty, isScreenRecordingAllowed() else {
            for wid in neededIDs { if let stale = cache.get(wid) { result[wid] = stale } }
            return result
        }

        if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
            let wanted = Set(neededIDs)
            for win in content.windows where wanted.contains(win.windowID) {
                if let img = await capture(win, maxSize: maxSize) { result[win.windowID] = img }
            }
        }

        // Fallback for windows ScreenCaptureKit did not give (another Space, a miss). Marked as less trusted so it never
        // replaces an upright capture.
        for wid in neededIDs where result[wid] == nil {
            if let rawCG = legacyWindowCapture(windowID: wid) {
                // The legacy path returns full backing size (3456 × 2168 for a full-screen window on another Space,
                // measured) — scale to the same cap as a ScreenCaptureKit capture before it goes into the cache.
                let fallbackCG = Self.downscaled(rawCG, maxPixels: maxSize) ?? rawCG
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let img = NSImage(cgImage: fallbackCG, size: NSSize(width: CGFloat(fallbackCG.width) / scale,
                                                                    height: CGFloat(fallbackCG.height) / scale))
                cache.set(wid, image: img, fromProxy: true, maxPixels: maxSize)
                result[wid] = cache.get(wid)
            } else if let stale = cache.get(wid) {
                result[wid] = stale
            }
        }
        return result
    }

    /// One window. A strip tile with an upright picture already cached is not captured at all.
    private func capture(_ win: SCWindow, maxSize: CGFloat) async -> NSImage? {
        guard win.frame.width > 1, win.frame.height > 1 else { return nil }
        let isProxy = Self.isStageManagerProxy(frame: win.frame)
        if isProxy, let upright = cache.entry(win.windowID), !upright.fromProxy { return upright.image }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let px = ThumbnailFreshness.captureSize(frame: win.frame.size, scale: scale, maxPixels: maxSize)
        let config = SCStreamConfiguration()
        config.width = px.width
        config.height = px.height
        config.scalesToFit = false
        config.showsCursor = false
        config.capturesAudio = false
        config.captureResolution = .best
        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: win),
                                                                         configuration: config) else { return nil }
        // The tilt is checked on the PIXELS for every window short of a big one, not only for a strip-sized frame: a
        // capture taken while the window flies into the Stage Manager strip has a mid-size frame and is already tilted
        // (owner, 2026-10-21: TradingView's switcher card showed the tilt now and then). Such a picture was cached as
        // upright, and "an upright picture is never replaced by a tile picture" then kept it.
        let checkTilt = isProxy || win.frame.width < 700
        let s = checkTilt ? Self.straightened(cgImage) : (image: cgImage, wasTilted: false)
        let finalCG = s.image
        let img = NSImage(cgImage: finalCG, size: NSSize(width: CGFloat(finalCG.width) / scale, height: CGFloat(finalCG.height) / scale))
        cache.set(win.windowID, image: img, fromProxy: isProxy || s.wasTilted, maxPixels: maxSize)
        return cache.get(win.windowID)
    }

    static func downscaled(_ image: CGImage, maxPixels: CGFloat) -> CGImage? {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxPixels, maxPixels > 0 else { return image }
        let f = maxPixels / longest
        let w = max(1, Int((CGFloat(image.width) * f).rounded())), h = max(1, Int((CGFloat(image.height) * f).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Stage Manager only: called a moment after an app comes on stage, so its windows have an upright picture before
    /// they are parked in the strip again (where only a tilted tile can be captured). At most three windows.
    public func warmUprightPictures(pid: pid_t, maxSize: CGFloat = ThumbnailFreshness.cardPixels) async {
        guard isScreenRecordingAllowed(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
        let wins = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.isOnScreen
                && !Self.isStageManagerProxy(frame: $0.frame) && $0.frame.width >= 260 && $0.frame.height >= 180
        }
        for win in wins.prefix(3) { _ = await capture(win, maxSize: maxSize) }
    }

    private func legacyWindowCapture(windowID: CGWindowID) -> CGImage? {
        // 1. Try CGSHWCaptureWindowList (private API from SkyLight / CoreGraphics)
        typealias CGSFunc = @convention(c) (UInt32, UnsafeMutablePointer<CGWindowID>, UInt32, UInt32) -> Unmanaged<CFArray>?
        typealias MainCIDFunc = @convention(c) () -> UInt32

        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }

        if let symCID = dlsym(handle, "CGSMainConnectionID"),
           let symCap = dlsym(handle, "CGSHWCaptureWindowList") {
            let getCID = unsafeBitCast(symCID, to: MainCIDFunc.self)
            let capture = unsafeBitCast(symCap, to: CGSFunc.self)
            let cid = getCID()
            var wid = windowID
            // CGSWindowCaptureOptions.bestResolution = 1 << 8 = 256
            if let unmanaged = capture(cid, &wid, 1, 256),
               let array = unmanaged.takeRetainedValue() as? [CGImage],
               let first = array.first {
                return Self.straightenImageIfNeeded(first)
            }
        }

        // 2. Fall back to CGWindowListCreateImage
        typealias Func = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
        if let sym = dlsym(handle, "CGWindowListCreateImage") {
            let fn = unsafeBitCast(sym, to: Func.self)
            let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
            if let raw = fn(.null, .optionIncludingWindow, windowID, options)?.takeRetainedValue() {
                return Self.straightenImageIfNeeded(raw)
            }
        }
        return nil
    }
}

/// Mock implementation of ScreenCaptureProviding for deterministic tests.
public final class MockScreenCaptureProvider: ScreenCaptureProviding, @unchecked Sendable {
    public var isAllowed: Bool
    public let cache: LRUThumbnailCache
    private var mockImages: [CGWindowID: NSImage] = [:]
    private let lock = NSLock()

    public init(isAllowed: Bool = true, cache: LRUThumbnailCache = LRUThumbnailCache(capacity: 10)) {
        self.isAllowed = isAllowed
        self.cache = cache
    }

    public func setMockImage(for windowID: CGWindowID, image: NSImage) {
        lock.lock()
        defer { lock.unlock() }
        mockImages[windowID] = image
    }

    public func isScreenRecordingAllowed() -> Bool {
        return isAllowed
    }

    private func getMockImage(for windowID: CGWindowID, defaultSize: CGFloat) -> NSImage {
        lock.lock()
        defer { lock.unlock() }
        return mockImages[windowID] ?? NSImage(size: NSSize(width: defaultSize, height: defaultSize))
    }

    public func captureWindow(windowID: CGWindowID, maxSize: CGFloat = 320) async -> NSImage? {
        if let cached = cache.get(windowID) {
            return cached
        }
        guard isAllowed else { return nil }

        let img = getMockImage(for: windowID, defaultSize: maxSize)
        cache.set(windowID, image: img)
        return img
    }

    public func captureWindows(windowIDs: [CGWindowID], maxSize: CGFloat = 320) async -> [CGWindowID: NSImage] {
        var res: [CGWindowID: NSImage] = [:]
        for wid in windowIDs {
            if let img = await captureWindow(windowID: wid, maxSize: maxSize) {
                res[wid] = img
            }
        }
        return res
    }
}
