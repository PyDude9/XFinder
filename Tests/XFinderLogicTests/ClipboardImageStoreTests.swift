import XCTest
import ImageIO

/// A copied image goes to disk without being decoded in the app (2026-10-23: +42 MB left behind per copy before).
final class ClipboardImageStoreTests: XCTestCase {
    typealias S = ClipboardImageStore

    func encoded(_ type: String, width: Int, height: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out as CFMutableData, type as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    func type(of data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipimg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testAPNGIsKeptByteForByte() {
        let png = encoded("public.png", width: 40, height: 30)
        XCTAssertEqual(S.png(from: png), png)
    }

    func testTIFFAndJPEGBecomePNGOfTheSameSize() throws {
        for t in ["public.tiff", "public.jpeg"] {
            let data = encoded(t, width: 64, height: 48)
            let png = try XCTUnwrap(S.png(from: data), t)
            XCTAssertEqual(type(of: png), "public.png", t)
            XCTAssertEqual(S.size(of: png)?.width, 64, t)
            XCTAssertEqual(S.size(of: png)?.height, 48, t)
        }
    }

    func testNotAnImageIsNothing() throws {
        let junk = Data("hello, not an image".utf8)
        XCTAssertNil(S.size(of: junk))
        XCTAssertNil(S.png(from: junk))
        XCTAssertNil(S.store(junk, in: try tempDir(), stamp: "1"))
    }

    func testStoreWritesPayloadAndASmallThumbnail() throws {
        let dir = try tempDir()
        let data = encoded("public.tiff", width: 900, height: 600)
        let stored = try XCTUnwrap(S.store(data, in: dir, stamp: "42"))
        XCTAssertEqual(stored.width, 900); XCTAssertEqual(stored.height, 600)
        XCTAssertEqual(stored.payload, dir.appendingPathComponent("img-42.png").path)
        let payload = try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(stored.payload)))
        XCTAssertEqual(type(of: payload), "public.png")
        let thumb = try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(stored.thumb)))
        XCTAssertEqual(S.size(of: thumb)?.width, S.thumbnailPixels)       // long side capped, aspect kept
        XCTAssertEqual(S.size(of: thumb)?.height, 200)
    }

    func testACopiedFileGetsOnlyAThumbnail() throws {
        let dir = try tempDir()
        let file = dir.appendingPathComponent("photo.jpg")
        try encoded("public.jpeg", width: 120, height: 80).write(to: file)
        let stored = try XCTUnwrap(S.storeThumbnail(ofFile: file, in: dir, stamp: "7"))
        XCTAssertNil(stored.payload)
        XCTAssertEqual(stored.width, 120); XCTAssertEqual(stored.height, 80)
        XCTAssertNotNil(stored.thumb)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["photo.jpg", "thumb-7.png"])
        XCTAssertNil(S.storeThumbnail(ofFile: dir.appendingPathComponent("missing.png"), in: dir, stamp: "8"))
    }

    func testTheSameBytesGiveTheSameDuplicateKey() {
        let a = encoded("public.png", width: 20, height: 20), b = encoded("public.png", width: 21, height: 20)
        XCTAssertEqual(S.duplicateKey(a), S.duplicateKey(a))
        XCTAssertNotEqual(S.duplicateKey(a), S.duplicateKey(b))
        XCTAssertTrue(S.duplicateKey(a).hasPrefix("image:"))
        XCTAssertEqual(S.duplicateKey(a).count, "image:".count + 64)
    }
}
