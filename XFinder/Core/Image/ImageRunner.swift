import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import Vision

/// Runs the image tools with ImageIO, Core Image and Vision — no AppKit, so the test package
/// exercises it on generated images. Every output goes through `ImageEngine.outputURL`.
enum ImageRunner {

    enum Failure: Error, Equatable {
        case unreadable(String)
        case noEncoder(String)        // target label
        case writeFailed(String)
        case noSubject(String)        // Vision found no foreground instance
        case visionFailed(String)

        var messageKey: String {
            switch self {
            case .unreadable: return "Không đọc được ảnh: "
            case .noEncoder: return "Máy này không ghi được định dạng: "
            case .writeFailed: return "Không ghi được ảnh: "
            case .noSubject: return "Không tìm thấy chủ thể để tách nền trong: "
            case .visionFailed: return "Tách nền thất bại: "
            }
        }
        var detail: String {
            switch self {
            case .unreadable(let s), .noEncoder(let s), .writeFailed(let s), .noSubject(let s), .visionFailed(let s): return s
            }
        }
        static let examples: [Failure] = [.unreadable("a"), .noEncoder("a"), .writeFailed("a"), .noSubject("a"), .visionFailed("a")]
    }

    static var encodableTypes: [String] { (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [] }

    private static func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    /// Re-encodes through `AddImageFromSource`, which carries orientation, colour profile and EXIF
    /// (measured: HEIC orientation 6 + sRGB survive into JPEG and PNG).
    static func convert(_ source: URL, to target: ImageEngine.Target, quality: Double = 0.85) -> Result<URL, Failure> {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            return .failure(.unreadable(source.lastPathComponent))
        }
        let out = ImageEngine.outputURL(for: source, operation: .convert(target), exists: exists)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, target.uti as CFString, 1, nil) else {
            return .failure(.noEncoder(target.label))
        }
        var props: [CFString: Any] = [:]
        if target.isLossy { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out); return .failure(.writeFailed(out.lastPathComponent))
        }
        return .success(out)
    }

    /// Shrinks so the longest edge is `maxPixels`, applying the orientation into the pixels (so the
    /// result is upright everywhere) and keeping the colour profile. Same format as the source.
    static func resize(_ source: URL, maxPixels: Int) -> Result<URL, Failure> {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), let type = CGImageSourceGetType(src),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return .failure(.unreadable(source.lastPathComponent)) }
        let out = ImageEngine.outputURL(for: source, operation: .resize(maxPixels: maxPixels), exists: exists)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else {
            return .failure(.noEncoder(source.pathExtension.uppercased()))
        }
        var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImagePropertyOrientation] = 1                 // the transform is already in the pixels
        props.removeValue(forKey: kCGImagePropertyPixelWidth)
        props.removeValue(forKey: kCGImagePropertyPixelHeight)
        props[kCGImageDestinationLossyCompressionQuality] = 0.85
        CGImageDestinationAddImage(dest, thumb, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out); return .failure(.writeFailed(out.lastPathComponent))
        }
        return .success(out)
    }

    /// Vision foreground segmentation (macOS 14+, on-device, no permission) → PNG with alpha.
    /// Measured: ~2.2 s on the first call (model load), corner alpha 0, subject alpha 255.
    static func removeBackground(_ source: URL) -> Result<URL, Failure> {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 8192,
              ] as CFDictionary) else { return .failure(.unreadable(source.lastPathComponent)) }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch { return .failure(.visionFailed(error.localizedDescription)) }
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else {
            return .failure(.noSubject(source.lastPathComponent))
        }
        let buffer: CVPixelBuffer
        do {
            buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        } catch { return .failure(.visionFailed(error.localizedDescription)) }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent,
                                                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            return .failure(.visionFailed("render"))
        }
        let out = ImageEngine.outputURL(for: source, operation: .removeBackground, exists: exists)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else {
            return .failure(.noEncoder("PNG"))
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out); return .failure(.writeFailed(out.lastPathComponent))
        }
        return .success(out)
    }
}
