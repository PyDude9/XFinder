import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import Vision
import Darwin

/// Runs the image tools with ImageIO, Core Image and Vision — no AppKit, so the test package
/// exercises it on generated images. Every output goes through `ImageEngine.outputURL`.
enum ImageRunner {

    enum Failure: Error, Equatable, Sendable {
        case unreadable(String)
        case noEncoder(String)        // target label
        case writeFailed(String)
        case noSubject(String)        // Vision found no foreground instance
        case visionFailed(String)
        case animatedUnsupported(String)
        case staleSource(String)
        case invalidTransform(String)

        var messageKey: String {
            switch self {
            case .unreadable: return "Không đọc được ảnh: "
            case .noEncoder: return "Máy này không ghi được định dạng: "
            case .writeFailed: return "Không ghi được ảnh: "
            case .noSubject: return "Không tìm thấy chủ thể để tách nền trong: "
            case .visionFailed: return "Tách nền thất bại: "
            case .animatedUnsupported: return "Ảnh động nhiều khung hình chưa được hỗ trợ; tệp gốc được giữ nguyên: "
            case .staleSource: return "Ảnh đã thay đổi sau khi xem trước; chưa tạo bản mới: "
            case .invalidTransform: return "Không thể áp dụng thông số ảnh: "
            }
        }
        var detail: String {
            switch self {
            case .unreadable(let s), .noEncoder(let s), .writeFailed(let s), .noSubject(let s), .visionFailed(let s),
                 .animatedUnsupported(let s), .staleSource(let s), .invalidTransform(let s): return s
            }
        }
        static let examples: [Failure] = [.unreadable("a"), .noEncoder("a"), .writeFailed("a"), .noSubject("a"), .visionFailed("a"), .animatedUnsupported("a"), .staleSource("a"), .invalidTransform("a")]
    }

    struct TransformOptions: Sendable {
        var crop: ImageTransformRules.NormalizedCrop = .full
        var target: ImageTransformRules.Target?
        var allowUpscale = false
        var format: ImageEngine.Target
        var quality = 0.85
        var outputOperation: ImageEngine.Operation?
    }

    struct TransformPreview: Equatable, Sendable {
        let identity: String
        let plan: ImageTransformRules.Plan
        let outputType: String
        let willSkip: Bool
    }

    static var encodableTypes: [String] { (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [] }

    private static func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    /// Preview and save share this metadata/geometry calculation. Callers must retain the returned
    /// identity and pass it back to `transform`; path equality alone is not a stable source check.
    static func preview(_ source: URL, options: TransformOptions) -> Result<TransformPreview, Failure> {
        guard let identity = fileIdentity(source), let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(src) > 0 else { return .failure(.unreadable(source.lastPathComponent)) }
        guard CGImageSourceGetCount(src) == 1 else { return .failure(.animatedUnsupported(source.lastPathComponent)) }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return .failure(.unreadable(source.lastPathComponent)) }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        do {
            let plan = try ImageTransformRules.calculate(sourceWidth: width, sourceHeight: height,
                orientation: orientation, crop: options.crop, target: options.target,
                allowUpscale: options.allowUpscale)
            return .success(.init(identity: identity, plan: plan, outputType: options.format.uti,
                                  willSkip: plan.skipReason != nil))
        } catch {
            return .failure(.invalidTransform(source.lastPathComponent))
        }
    }

    /// Single geometry pipeline: orientation is applied to pixels, then crop, then resize. The
    /// source identity is checked before decoding and again before atomic keep-both publication.
    static func transform(_ source: URL, options: TransformOptions, expectedIdentity: String? = nil) -> Result<URL, Failure> {
        guard let beforeIdentity = fileIdentity(source), expectedIdentity == nil || expectedIdentity == beforeIdentity else {
            return .failure(.staleSource(source.lastPathComponent))
        }
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            return .failure(.unreadable(source.lastPathComponent))
        }
        guard CGImageSourceGetCount(src) == 1 else { return .failure(.animatedUnsupported(source.lastPathComponent)) }
        let previewResult = preview(source, options: options)
        guard case .success(let preview) = previewResult else {
            if case .failure(let failure) = previewResult { return .failure(failure) }
            return .failure(.unreadable(source.lastPathComponent))
        }
        guard preview.identity == beforeIdentity else { return .failure(.staleSource(source.lastPathComponent)) }
        if preview.willSkip { return .failure(.invalidTransform("Kích thước đích sẽ phóng lớn ảnh nhỏ; hãy bật Phóng lớn ảnh nhỏ.")) }

        let p = preview.plan
        guard let upright = CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(p.uprightWidth, p.uprightHeight),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary), upright.width == p.uprightWidth, upright.height == p.uprightHeight else {
            return .failure(.unreadable(source.lastPathComponent))
        }
        let crop = p.cropPixels
        let cgRect = CGRect(x: crop.x, y: upright.height - crop.y - crop.height,
                            width: crop.width, height: crop.height)
        guard let cropped = upright.cropping(to: cgRect),
              let rendered = render(cropped, width: p.outputWidth, height: p.outputHeight) else {
            return .failure(.invalidTransform(source.lastPathComponent))
        }
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(options.format.uti) else {
            return .failure(.noEncoder(options.format.label))
        }
        let staging = source.deletingLastPathComponent().appendingPathComponent(".xf-image-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: staging) }
        var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImagePropertyOrientation] = 1
        props[kCGImagePropertyPixelWidth] = p.outputWidth
        props[kCGImagePropertyPixelHeight] = p.outputHeight
        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = p.outputWidth
            exif[kCGImagePropertyExifPixelYDimension] = p.outputHeight
            props[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            // TIFF tag names are not exported as ImageIO constants on the macOS 14 SDK.
            // Rewrite only the standard TIFF dimension tags; actual pixel dimensions are also
            // verified from the encoded image's top-level ImageIO properties below.
            tiff["ImageWidth" as CFString] = p.outputWidth
            tiff["ImageLength" as CFString] = p.outputHeight
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        guard let dest = CGImageDestinationCreateWithURL(staging as CFURL, options.format.uti as CFString, 1, nil) else {
            return .failure(.noEncoder(options.format.label))
        }
        if options.format.isLossy { props[kCGImageDestinationLossyCompressionQuality] = min(1, max(0, options.quality)) }
        CGImageDestinationAddImage(dest, rendered, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return .failure(.writeFailed(staging.lastPathComponent)) }
        guard let check = CGImageSourceCreateWithURL(staging as CFURL, nil), CGImageSourceGetCount(check) == 1,
                  CGImageSourceGetType(check) as String? == options.format.uti,
                  let checkProps = CGImageSourceCopyPropertiesAtIndex(check, 0, nil) as? [CFString: Any],
                  (checkProps[kCGImagePropertyPixelWidth] as? Int) == p.outputWidth,
                  (checkProps[kCGImagePropertyPixelHeight] as? Int) == p.outputHeight,
                  (checkProps[kCGImagePropertyOrientation] as? Int ?? 1) == 1 else {
                return .failure(.writeFailed("Không xác minh được ảnh đầu ra."))
            }
        guard fileIdentity(source) == beforeIdentity else { return .failure(.staleSource(source.lastPathComponent)) }
        let name: String
        switch options.outputOperation ?? .convert(options.format) {
            case .convert(let target): name = "\(source.deletingPathExtension().lastPathComponent).\(target.fileExtension)"
            case .resize(let pixels): name = "\(source.deletingPathExtension().lastPathComponent)-\(pixels)px.\(options.format.fileExtension)"
            case .removeBackground: name = "\(source.deletingPathExtension().lastPathComponent)-cutout.\(options.format.fileExtension)"
        }
        let base = source.deletingLastPathComponent().appendingPathComponent(name)
        let stem = base.deletingPathExtension().lastPathComponent
        for attempt in 0..<1000 {
            let candidate = base.deletingLastPathComponent().appendingPathComponent(
                attempt == 0 ? base.lastPathComponent : "\(stem) (\(attempt + 1)).\(options.format.fileExtension)")
            if candidate.standardizedFileURL.path == source.standardizedFileURL.path { continue }
            if renamex_np(staging.path, candidate.path, UInt32(RENAME_EXCL)) == 0 { return .success(candidate) }
            if errno != EEXIST { return .failure(.writeFailed(candidate.lastPathComponent)) }
        }
        return .failure(.writeFailed("Có quá nhiều tệp trùng tên trong thư mục."))
    }

    private static func render(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func fileIdentity(_ url: URL) -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
    }

    /// Re-encodes through `AddImageFromSource`, which carries orientation, colour profile and EXIF
    /// (measured: HEIC orientation 6 + sRGB survive into JPEG and PNG).
    static func convert(_ source: URL, to target: ImageEngine.Target, quality: Double = 0.85) -> Result<URL, Failure> {
        transform(source, options: .init(format: target, quality: quality, outputOperation: .convert(target)))
    }

    /// Shrinks so the longest edge is `maxPixels`, applying the orientation into the pixels (so the
    /// result is upright everywhere) and keeping the colour profile. Same format as the source.
    static func resize(_ source: URL, maxPixels: Int) -> Result<URL, Failure> {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), let type = CGImageSourceGetType(src) as String? else {
            return .failure(.unreadable(source.lastPathComponent))
        }
        guard let format = ImageEngine.Target.allCases.first(where: { $0.uti == type }) else {
            return .failure(.noEncoder(source.pathExtension.uppercased()))
        }
        return transform(source, options: .init(target: .longestEdge(maxPixels), format: format,
                                               outputOperation: .resize(maxPixels: maxPixels)))
    }

    /// Vision foreground segmentation (macOS 14+, on-device, no permission) → PNG with alpha.
    /// Measured: ~2.2 s on the first call (model load), corner alpha 0, subject alpha 255.
    static func removeBackground(_ source: URL) -> Result<URL, Failure> {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(imageSource) > 0 else {
            return .failure(.unreadable(source.lastPathComponent))
        }
        guard CGImageSourceGetCount(imageSource) == 1 else {
            return .failure(.animatedUnsupported(source.lastPathComponent))
        }
        // The file's bytes go to the Vision child as they are: decoding a 48-MP photo here first cost the app hundreds
        // of megabytes it kept (see VisionChild.decode).
        if VisionChild.isAvailable, let data = VisionChild.fileBytes(source), let reply = VisionChild.run(.cutout, imageData: data) {
            switch reply.status {
            case VisionChild.Status.ok where !reply.output.isEmpty: return write(reply.output, for: source)
            case VisionChild.Status.noSubject: return .failure(.noSubject(source.lastPathComponent))
            case VisionChild.Status.notAnImage: return .failure(.unreadable(source.lastPathComponent))
            default: break      // the child failed: do it here
            }
        }
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 8192,
              ] as CFDictionary) else { return .failure(.unreadable(source.lastPathComponent)) }
        let png: Data
        switch cutoutHere(image, name: source.lastPathComponent) {
        case .success(let data): png = data
        case .failure(let f): return .failure(f)
        }
        return write(png, for: source)
    }

    private static func write(_ png: Data, for source: URL) -> Result<URL, Failure> {
        let out = ImageEngine.outputURL(for: source, operation: .removeBackground, exists: exists)
        do { try png.write(to: out, options: .atomic) } catch { return .failure(.writeFailed(out.lastPathComponent)) }
        return .success(out)
    }

    /// In THIS process: the child's work, and what the tests run.
    static func cutoutHere(_ image: CGImage, name: String) -> Result<Data, Failure> {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch { return .failure(.visionFailed(error.localizedDescription)) }
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else {
            return .failure(.noSubject(name))
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
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            return .failure(.noEncoder("PNG"))
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return .failure(.visionFailed("encode")) }
        return .success(data as Data)
    }
}
