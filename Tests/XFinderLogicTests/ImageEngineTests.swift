import XCTest
import Foundation
import ImageIO
import CoreGraphics

final class ImageEngineTests: XCTestCase {
    typealias E = ImageEngine

    func testOnlyEncodableTargetsAreOffered() {
        XCTAssertEqual(E.availableTargets(encodable: ["public.jpeg", "public.png"]), [.jpeg, .png])
        XCTAssertFalse(E.Target.allCases.map(\.uti).contains("org.webmproject.webp"),
                       "measured: no WebP encoder on macOS 27 — it must not even be a target")
    }

    func testTheRealEncoderListOnThisMac() {
        let live = E.availableTargets(encodable: ImageRunner.encodableTypes)
        XCTAssertTrue(live.contains(.jpeg) && live.contains(.png), "\(live)")
    }

    func testOutputNamesNeverReplaceAFileOrTheSource() {
        let src = URL(fileURLWithPath: "/p/IMG_1.jpg")
        XCTAssertEqual(E.outputURL(for: src, operation: .convert(.jpeg), exists: { _ in false }).lastPathComponent,
                       "IMG_1 2.jpg", "converting into the source's own name must not overwrite it")
        let taken: Set<String> = ["/p/IMG_1-cutout.png"]
        XCTAssertEqual(E.outputURL(for: src, operation: .removeBackground, exists: { taken.contains($0.path) }).lastPathComponent,
                       "IMG_1-cutout 2.png")
        XCTAssertEqual(E.outputURL(for: src, operation: .resize(maxPixels: 1600), exists: { _ in false }).lastPathComponent,
                       "IMG_1-1600px.jpg")
    }

    func testInputsAndSameFormat() {
        XCTAssertTrue(E.isImage(URL(fileURLWithPath: "/a/b.HEIC")))
        XCTAssertFalse(E.isImage(URL(fileURLWithPath: "/a/b.pdf")))
        XCTAssertTrue(E.isSameFormat(URL(fileURLWithPath: "/a/b.jpeg"), .jpeg))
        XCTAssertFalse(E.isSameFormat(URL(fileURLWithPath: "/a/b.heic"), .png))
        XCTAssertTrue(E.resizeShrinks(width: 4000, height: 3000, maxPixels: 1600))
        XCTAssertFalse(E.resizeShrinks(width: 800, height: 600, maxPixels: 1600))
    }

    func testEveryFailureKeyIsInTheStore() throws {
        let store = try L10nFixture.load()
        for f in ImageRunner.Failure.examples { XCTAssertNotNil(store.entries[f.messageKey], f.messageKey) }
    }

    // MARK: Integration — real ImageIO / Vision on generated images

    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("xf-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// 800×600: a gradient background with a red disc as the subject.
    func makeImage(_ name: String, type: String, orientation: Int = 1) -> URL {
        let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<600 { ctx.setFillColor(CGColor(red: 0.2, green: 0.5 + Double(y) / 1500, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: y, width: 800, height: 1)) }
        ctx.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 250, y: 150, width: 300, height: 300))
        let url = dir.appendingPathComponent(name)
        let d = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(d))
        return url
    }
    func props(_ u: URL) -> [CFString: Any] {
        CGImageSourceCreateWithURL(u as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
    }

    func testHeicToJpegKeepsOrientationAndProfile() {
        let src = makeImage("photo.heic", type: "public.heic", orientation: 6)
        guard case .success(let out) = ImageRunner.convert(src, to: .jpeg) else { return XCTFail() }
        XCTAssertEqual(out.lastPathComponent, "photo.jpg")
        XCTAssertEqual(props(out)[kCGImagePropertyOrientation] as? Int, 6)
        XCTAssertNotNil(props(out)[kCGImagePropertyProfileName])
    }

    func testResizeBakesTheOrientationAndShrinksTheLongEdge() {
        let src = makeImage("photo.jpg", type: "public.jpeg", orientation: 6)
        guard case .success(let out) = ImageRunner.resize(src, maxPixels: 400) else { return XCTFail() }
        let p = props(out)
        XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, 300, "rotated 90°: 800×600 → 300×400")
        XCTAssertEqual(p[kCGImagePropertyPixelHeight] as? Int, 400)
        XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int ?? 1, 1, "orientation must be reset after baking it in")
    }

    func testBackgroundRemovalLeavesATransparentBackgroundAndAnOpaqueSubject() throws {
        let src = makeImage("subject.png", type: "public.png")
        guard case .success(let out) = ImageRunner.removeBackground(src) else { return XCTFail("Vision found no subject") }
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(out as CFURL, nil)!, 0, nil)!
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * image.width + x) * 4 + 3] }
        XCTAssertEqual(alpha(10, 10), 0, "the corner is background")
        XCTAssertEqual(alpha(400, 300), 255, "the centre is the subject")
    }

    /// The cutout in this process: a plain image has no subject (the child answers with its own exit status for that),
    /// and the bytes it returns are a PNG.
    func testCutoutHereSaysNoSubjectForAPlainImageAndReturnsPNGForOne() throws {
        let plain = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        plain.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); plain.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(ImageRunner.cutoutHere(plain.makeImage()!, name: "plain.png"), .failure(.noSubject("plain.png")))
        let src = makeImage("subject.png", type: "public.png")
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(src as CFURL, nil)!, 0, nil)!
        guard case .success(let png) = ImageRunner.cutoutHere(image, name: "subject.png") else { return XCTFail("Vision found no subject") }
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG signature")
        XCTAssertEqual(CGImageSourceGetType(CGImageSourceCreateWithData(png as CFData, nil)!) as String?, "public.png")
    }

    func testANonImageFailsAndWritesNothing() {
        let junk = dir.appendingPathComponent("fake.jpg")
        try? "not an image".write(to: junk, atomically: true, encoding: .utf8)
        XCTAssertEqual(ImageRunner.convert(junk, to: .png), .failure(.unreadable("fake.jpg")))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [], ["fake.jpg"])
    }
}
