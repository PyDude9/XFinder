import Foundation
import AppKit
import ScreenCaptureKit

/// Thread-safe LRU cache for window thumbnails.
public final class LRUThumbnailCache: @unchecked Sendable {
    private let lock = NSLock()
    public let capacity: Int
    private var entries: [CGWindowID: (image: NSImage, lastAccess: Date)] = [:]

    public init(capacity: Int = 40) {
        self.capacity = capacity
    }

    public func get(_ key: CGWindowID) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        entries[key] = (entry.image, Date())
        return entry.image
    }

    public func set(_ key: CGWindowID, image: NSImage) {
        lock.lock()
        defer { lock.unlock() }
        if entries.count >= capacity, entries[key] == nil {
            if let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
                entries.removeValue(forKey: oldest)
            }
        }
        entries[key] = (image, Date())
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

    public init(cache: LRUThumbnailCache = LRUThumbnailCache(capacity: 40)) {
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
    public static func straightenImageIfNeeded(_ cgImage: CGImage) -> CGImage {
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

    public func captureWindow(windowID: CGWindowID, maxSize: CGFloat = 800) async -> NSImage? {
        if let cached = cache.get(windowID) {
            return cached
        }
        guard isScreenRecordingAllowed() else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            if let win = content.windows.first(where: { $0.windowID == windowID }),
               win.frame.width > 1, win.frame.height > 1 {
                let filter = SCContentFilter(desktopIndependentWindow: win)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let config = SCStreamConfiguration()
                config.width = max(200, Int(win.frame.width * scale))
                config.height = max(200, Int(win.frame.height * scale))
                config.scalesToFit = false
                config.showsCursor = false
                config.capturesAudio = false
                config.captureResolution = .best

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let finalCG: CGImage = (win.frame.width <= 260 && win.frame.height <= 260)
                    ? Self.straightenImageIfNeeded(cgImage)
                    : cgImage
                let ptW = CGFloat(finalCG.width) / scale
                let ptH = CGFloat(finalCG.height) / scale
                let img = NSImage(cgImage: finalCG, size: NSSize(width: ptW, height: ptH))
                cache.set(windowID, image: img)
                return img
            }
        } catch {
            // SCK failed, try legacy fallback
        }

        // Fallback for On another Space, Stage Manager or SCK miss:
        if let fallbackCG = legacyWindowCapture(windowID: windowID) {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let ptW = CGFloat(fallbackCG.width) / scale
            let ptH = CGFloat(fallbackCG.height) / scale
            let img = NSImage(cgImage: fallbackCG, size: NSSize(width: ptW, height: ptH))
            cache.set(windowID, image: img)
            return img
        }

        return nil
    }

    public func captureWindows(windowIDs: [CGWindowID], maxSize: CGFloat = 800) async -> [CGWindowID: NSImage] {
        guard !windowIDs.isEmpty else { return [:] }
        var result: [CGWindowID: NSImage] = [:]
        var neededIDs: [CGWindowID] = []

        for wid in windowIDs {
            if let cached = cache.get(wid) {
                result[wid] = cached
            } else {
                neededIDs.append(wid)
            }
        }

        guard !neededIDs.isEmpty, isScreenRecordingAllowed() else { return result }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let wanted = Set(neededIDs)
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            for win in content.windows where wanted.contains(win.windowID) {
                guard win.frame.width > 1, win.frame.height > 1 else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: win)
                let config = SCStreamConfiguration()
                config.width = max(200, Int(win.frame.width * scale))
                config.height = max(200, Int(win.frame.height * scale))
                config.scalesToFit = false
                config.showsCursor = false
                config.capturesAudio = false
                config.captureResolution = .best

                guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                    continue
                }
                let finalCG: CGImage = (win.frame.width <= 260 && win.frame.height <= 260)
                    ? Self.straightenImageIfNeeded(cgImage)
                    : cgImage
                let ptW = CGFloat(finalCG.width) / scale
                let ptH = CGFloat(finalCG.height) / scale
                let img = NSImage(cgImage: finalCG, size: NSSize(width: ptW, height: ptH))
                cache.set(win.windowID, image: img)
                result[win.windowID] = img
            }
        } catch {
            // SCK failed, proceed to fallback for remaining
        }

        // Fallback for any needed windows not captured by SCK:
        for wid in neededIDs where result[wid] == nil {
            if let fallbackCG = legacyWindowCapture(windowID: wid) {
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let ptW = CGFloat(fallbackCG.width) / scale
                let ptH = CGFloat(fallbackCG.height) / scale
                let img = NSImage(cgImage: fallbackCG, size: NSSize(width: ptW, height: ptH))
                cache.set(wid, image: img)
                result[wid] = img
            }
        }

        return result
    }

    private func legacyWindowCapture(windowID: CGWindowID) -> CGImage? {
        // 1. Try CGSHWCaptureWindowList (private API from SkyLight / CoreGraphics)
        typealias CGSFunc = @convention(c) (UInt32, UnsafeMutablePointer<CGWindowID>, UInt32, UInt32) -> Unmanaged<CFArray>?
        typealias MainCIDFunc = @convention(c) () -> UInt32

        if let handle = dlopen(nil, RTLD_LAZY),
           let symCID = dlsym(handle, "CGSMainConnectionID"),
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
        guard let handle = dlopen(nil, RTLD_LAZY),
              let sym = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: Func.self)
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let raw = fn(.null, .optionIncludingWindow, windowID, options)?.takeRetainedValue() else { return nil }
        return Self.straightenImageIfNeeded(raw)
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
