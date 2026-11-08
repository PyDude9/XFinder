import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import Darwin

/// Early app entry point, never creates a scene. No in-process decoding fallback in the caller.
enum InspectorImageChild {
    static let flag = "--image"
    static func main() -> Never {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), args.count == i + 3 else { exit(64) }
        let requestURL = URL(fileURLWithPath: args[i + 1])
        let replyURL = URL(fileURLWithPath: args[i + 2])
        let reply: InspectorImageRules.Reply
        do {
            let request = try JSONDecoder().decode(InspectorImageRules.Request.self, from: Data(contentsOf: requestURL))
            reply = process(request)
        } catch { reply = .init(output: nil, errorKey: "Không thực hiện được thao tác ảnh.") }
        do { try JSONEncoder().encode(reply).write(to: replyURL, options: .atomic) }
        catch { exit(74) }
        exit(reply.output == nil ? 1 : 0)
    }

    static func process(_ request: InspectorImageRules.Request) -> InspectorImageRules.Reply {
        func failure(_ key: String) -> InspectorImageRules.Reply { .init(output: nil, errorKey: key) }
        guard request.isValid else { return failure("Yêu cầu thao tác ảnh không hợp lệ.") }
        var before = stat()
        guard lstat(request.source, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              InspectorImageRules.identity(path: request.source, info: before) == request.expectedIdentity else {
            return failure("Tệp nguồn đã thay đổi. Hãy chọn lại tệp rồi thử lại.")
        }
        guard before.st_flags & UInt32(SF_DATALESS) == 0 else { return failure("Tệp chỉ có trên đám mây — thao tác ảnh không tải tệp về.") }
        guard before.st_size > 0, before.st_size <= InspectorImageRules.byteLimit else { return failure("Ảnh vượt giới hạn xử lý an toàn (100 MiB hoặc 100 triệu điểm ảnh).") }
        let sourceURL = URL(fileURLWithPath: request.source)
        if let values = try? sourceURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]), values.ubiquitousItemDownloadingStatus == .notDownloaded {
            return failure("Tệp chỉ có trên đám mây — thao tác ảnh không tải tệp về.")
        }
        let fd = open(request.source, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return failure("Không đọc được nội dung tệp.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var opened = stat()
        guard fstat(fd, &opened) == 0, InspectorImageRules.identity(path: request.source, info: opened) == request.expectedIdentity else {
            return failure("Tệp nguồn đã thay đổi. Hãy chọn lại tệp rồi thử lại.")
        }
        guard let bytes = try? handle.read(upToCount: InspectorImageRules.byteLimit + 1), bytes.count <= InspectorImageRules.byteLimit,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
              width <= InspectorImageRules.pixelLimit / height else {
            return failure("Ảnh không đọc được hoặc vượt giới hạn xử lý an toàn.")
        }
        var after = stat()
        guard fstat(fd, &after) == 0, InspectorImageRules.identity(path: request.source, info: after) == request.expectedIdentity else {
            return failure("Tệp nguồn đã thay đổi. Hãy chọn lại tệp rồi thử lại.")
        }
        guard CGImageSourceGetCount(source) == 1 else {
            return failure("Ảnh động nhiều khung hình chưa được hỗ trợ; tệp gốc được giữ nguyên.")
        }
        let type = request.format?.uti ?? (request.operation == .jpeg ? "public.jpeg" : (request.operation == .webp ? "org.webmproject.webp" : "public.png"))
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type) else { return failure("ImageIO trên máy này không có bộ ghi cho định dạng đã chọn.") }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let target: ImageTransformRules.Target? = request.target ?? (request.operation == .resize
            ? .longestEdge(request.maxPixels ?? 0) : nil)
        let plan: ImageTransformRules.Plan
        do {
            plan = try ImageTransformRules.calculate(sourceWidth: width, sourceHeight: height,
                orientation: orientation, crop: request.crop, target: target, allowUpscale: request.allowUpscale)
        } catch { return failure("Yêu cầu thao tác ảnh không hợp lệ.") }
        guard plan.skipReason == nil else { return failure("Kích thước đích sẽ phóng lớn ảnh nhỏ; hãy bật Phóng lớn ảnh nhỏ.") }
        guard let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(plan.uprightWidth, plan.uprightHeight),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { return failure("Không thực hiện được thao tác ảnh.") }
        let crop = plan.cropPixels
        let cropRect = CGRect(x: crop.x, y: upright.height - crop.y - crop.height,
                              width: crop.width, height: crop.height)
        guard let cropped = upright.cropping(to: cropRect),
              let rendered = render(cropped, width: plan.outputWidth, height: plan.outputHeight) else {
            return failure("Không thực hiện được thao tác ảnh.")
        }
        let result: CGImage
        if request.operation == .flipHorizontal || request.operation == .flipVertical {
            let ci = CIImage(cgImage: rendered)
            let transform = request.operation == .flipHorizontal
                ? CGAffineTransform(translationX: ci.extent.width, y: 0).scaledBy(x: -1, y: 1)
                : CGAffineTransform(translationX: 0, y: ci.extent.height).scaledBy(x: 1, y: -1)
            guard let flipped = CIContext().createCGImage(ci.transformed(by: transform), from: ci.extent) else {
                return failure("Không thực hiện được thao tác ảnh.")
            }
            result = flipped
        } else { result = rendered }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, type as CFString, 1, nil) else { return failure("Không thực hiện được thao tác ảnh.") }
        var outputProps = props
        outputProps[kCGImagePropertyOrientation] = 1
        outputProps[kCGImagePropertyPixelWidth] = plan.outputWidth
        outputProps[kCGImagePropertyPixelHeight] = plan.outputHeight
        if request.format?.isLossy ?? (request.operation == .jpeg || request.operation == .webp) {
            outputProps[kCGImageDestinationLossyCompressionQuality] = min(1, max(0, request.quality))
        }
        CGImageDestinationAddImage(destination, result, outputProps as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return failure("Không thực hiện được thao tác ảnh.") }
        var finalSource = stat()
        guard lstat(request.source, &finalSource) == 0, InspectorImageRules.identity(path: request.source, info: finalSource) == request.expectedIdentity else {
            return failure("Tệp nguồn đã thay đổi. Hãy chọn lại tệp rồi thử lại.")
        }
        // Stage on the source volume, then publish with an atomic exclusive rename.
        // The parent also removes this owned staging path after a kill or crash.
        let staging = request.stagingURL
        do { try (encoded as Data).write(to: staging, options: .withoutOverwriting) }
        catch { return failure("Không ghi được bản ảnh mới. Kiểm tra quyền ghi của thư mục.") }
        defer { try? FileManager.default.removeItem(at: staging) }
        for attempt in 0..<1000 {
            let output = sourceURL.deletingLastPathComponent().appendingPathComponent(InspectorImageRules.outputName(source: sourceURL, operation: request.operation, maxPixels: request.maxPixels, format: request.format, attempt: attempt))
            if output.path == sourceURL.path { continue }
            if renamex_np(staging.path, output.path, UInt32(RENAME_EXCL)) == 0 {
                return .init(output: output.path, errorKey: nil)
            }
            if errno == EEXIST { continue }
            return failure("Không ghi được bản ảnh mới. Kiểm tra quyền ghi của thư mục.")
        }
        return failure("Có quá nhiều tệp trùng tên trong thư mục.")
    }

    private static func render(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
