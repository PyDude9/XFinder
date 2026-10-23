import Foundation
import ImageIO
import CryptoKit

/// A copied image on disk, without the app ever holding its decoded pixels (symlinked into the test package).
///
/// Measured 2026-10-23 with a 1628×6710 scrolling capture: the old path — `NSImage(pasteboard:)` →
/// `tiffRepresentation` → `NSBitmapImageRep` → PNG — left **+42 MB in the process per copy** even inside an
/// autorelease pool (4 copies: 176 MB, peak 260 MB; the installed app sat at 257–374 MB, peak 821 MB). Writing the
/// pasteboard's PNG bytes as they are and reading size + thumbnail through ImageIO: flat at 8 MB (probe
/// `scratchpad/scmem/clip.swift`). A TIFF or JPEG is turned into PNG once by ImageIO (+8 MB the first time, then flat).
enum ClipboardImageStore {

    struct Stored: Equatable {
        /// The full image, nil when only a thumbnail was asked for (the record points at the person's own file).
        var payload: String?
        var thumb: String?
        var width: Int
        var height: Int
    }

    static let thumbnailPixels = 300

    /// Size of the image in `data`, or nil when it is not an image ImageIO reads.
    static func size(of data: Data) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return (w, h)
    }

    /// `data` as PNG: the same bytes when it already is one, else re-encoded once by ImageIO. nil for anything else.
    static func png(from data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 else { return nil }
        if (CGImageSourceGetType(src) as String?) == "public.png" { return data }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(dest, src, 0, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// `data` re-encoded as TIFF (what an app that only reads TIFF gets, asked for lazily — never built up front).
    static func tiff(from data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.tiff" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(dest, src, 0, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// An image held in memory (an annotated capture) as PNG with the screen's DPI, so its point size survives the paste.
    static func png(from image: CGImage, scale: Double) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        let dpi = 72 * max(scale, 1)
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// A PNG at most `maxPixels` on the long side.
    static func thumbnail(from data: Data, maxPixels: Int = thumbnailPixels) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: false,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// Image bytes from the pasteboard (PNG, TIFF or JPEG): payload + thumbnail under `dir`, named by `stamp`.
    static func store(_ data: Data, in dir: URL, stamp: String) -> Stored? {
        guard let size = size(of: data), let png = png(from: data) else { return nil }
        let payload = dir.appendingPathComponent("img-\(stamp).png")
        guard (try? png.write(to: payload)) != nil else { return nil }
        return Stored(payload: payload.path, thumb: writeThumbnail(png, in: dir, stamp: stamp), width: size.width, height: size.height)
    }

    /// An image FILE the person copied: only a thumbnail is written — the record keeps pointing at their file, so a
    /// second full copy in the clipboard folder would be dead weight (before 2026-10-23 one was written and never read).
    static func storeThumbnail(ofFile url: URL, in dir: URL, stamp: String) -> Stored? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let size = size(of: data) else { return nil }
        return Stored(payload: nil, thumb: writeThumbnail(data, in: dir, stamp: stamp), width: size.width, height: size.height)
    }

    private static func writeThumbnail(_ data: Data, in dir: URL, stamp: String) -> String? {
        let url = dir.appendingPathComponent("thumb-\(stamp).png")
        guard let thumb = thumbnail(from: data), (try? thumb.write(to: url)) != nil else { return nil }
        return url.path
    }

    /// Key for the clipboard's 10-second duplicate window: the same image written again (one app re-wrote the same
    /// capture three times within 5 s, measured) is not a new copy.
    static func duplicateKey(_ data: Data) -> String {
        "image:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
