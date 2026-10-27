import XCTest
import ImageIO
import CoreGraphics
import Darwin

final class InspectorImageChildTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("inspector-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Ảnh.png")
        // Four opaque pixels, left red and right blue. Two rows exercise both flip axes.
        let bytes: [UInt8] = [255,0,0,255, 0,0,255,255, 0,255,0,255, 255,255,0,255]
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return (dir, url)
    }
    private func request(_ url: URL, _ op: InspectorImageRules.Operation, pixels: Int? = nil) -> InspectorImageRules.Request {
        var info = stat(); XCTAssertEqual(lstat(url.path, &info), 0)
        return .init(source: url.path, expectedIdentity: InspectorImageRules.identity(path: url.path, info: info), operation: op, maxPixels: pixels)
    }
    private func dimensions(_ path: String) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }
    func testCopiesNeverOverwriteAndResizeIsBounded() throws {
        let (dir, input) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try Data(contentsOf: input)
        let first = try XCTUnwrap(InspectorImageChild.process(request(input, .png)).output)
        let second = try XCTUnwrap(InspectorImageChild.process(request(input, .png)).output)
        XCTAssertNotEqual(first, input.path); XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: input), original)
        let small = try XCTUnwrap(InspectorImageChild.process(request(input, .resize, pixels: 1)).output)
        let props = try dimensions(small)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 1)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 1)
        XCTAssertNil(InspectorImageChild.process(request(input, .resize, pixels: 2)).output)
    }
    func testRejectsStaleSourceAndCorruptImage() throws {
        let (dir, input) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let stale = request(input, .jpeg)
        try Data("not an image".utf8).write(to: input)
        XCTAssertEqual(InspectorImageChild.process(stale).errorKey, "Tệp nguồn đã thay đổi. Hãy chọn lại tệp rồi thử lại.")
        XCTAssertNil(InspectorImageChild.process(request(input, .jpeg)).output)
    }
    private func rgba(_ url: URL) throws -> [[UInt8]] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes.withUnsafeMutableBytes { memory in
            let context = CGContext(data: memory.baseAddress, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return stride(from: 0, to: 16, by: 4).map { Array(bytes[$0..<$0 + 4]) }
    }
    func testBothFlipsProduceCorrectPixelsAndKeepSource() throws {
        let (dir, input) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = try Data(contentsOf: input)
        let pixels = try rgba(input)
        for op in [InspectorImageRules.Operation.flipHorizontal, .flipVertical] {
            let path = try XCTUnwrap(InspectorImageChild.process(request(input, op)).output)
            XCTAssertEqual(try dimensions(path)[kCGImagePropertyPixelWidth] as? Int, 2)
            let expected = op == .flipHorizontal ? [pixels[1], pixels[0], pixels[3], pixels[2]] : [pixels[2], pixels[3], pixels[0], pixels[1]]
            XCTAssertEqual(try rgba(URL(fileURLWithPath: path)), expected)
        }
        XCTAssertEqual(try Data(contentsOf: input), original)
    }
}
