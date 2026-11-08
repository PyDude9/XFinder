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

    func testHeicToJpegBakesOrientationAndKeepsProfile() {
        let src = makeImage("photo.heic", type: "public.heic", orientation: 6)
        guard case .success(let out) = ImageRunner.convert(src, to: .jpeg) else { return XCTFail() }
        XCTAssertEqual(out.lastPathComponent, "photo.jpg")
        XCTAssertEqual(props(out)[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        XCTAssertNotNil(props(out)[kCGImagePropertyProfileName])
    }

    func testEXIF1_6_8AreBakedIntoOutputDimensionsExactlyOnce() {
        for orientation in [1, 6, 8] {
            let src = makeImage("orientation-\(orientation).png", type: "public.png", orientation: orientation)
            guard case .success(let out) = ImageRunner.transform(src, options: .init(format: .png)) else {
                return XCTFail("orientation \(orientation)")
            }
            let p = props(out)
            let shouldSwap = orientation == 6 || orientation == 8
            XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, shouldSwap ? 600 : 800)
            XCTAssertEqual(p[kCGImagePropertyPixelHeight] as? Int, shouldSwap ? 800 : 600)
            XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        }
    }

    /// A CMYK JPEG (print / scanner output) must still resize and convert. CGBitmapContext has no
    /// premultiplied-alpha CMYK format (measured 2026-11-08: context creation returns nil), so this
    /// only works because ImageIO's upright decode hands `render` an RGB image. Guards that path: a
    /// future change that renders from the source CGImage directly would fail CMYK files.
    func testCMYKJpegStillResizesAndConverts() {
        let cmyk = CGColorSpace(name: CGColorSpace.genericCMYK)!
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cmyk, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: cmyk, components: [0.1, 0.7, 0.9, 0.0, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let src = dir.appendingPathComponent("print.jpg")
        let d = CGImageDestinationCreateWithURL(src as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(d))
        XCTAssertEqual(props(src)[kCGImagePropertyColorModel] as? String, "CMYK", "fixture must really be CMYK")
        guard case .success(let small) = ImageRunner.resize(src, maxPixels: 50) else { return XCTFail("CMYK resize failed") }
        XCTAssertEqual(props(small)[kCGImagePropertyPixelWidth] as? Int, 50)
        guard case .success(let png) = ImageRunner.convert(src, to: .png) else { return XCTFail("CMYK convert failed") }
        XCTAssertEqual(props(png)[kCGImagePropertyPixelWidth] as? Int, 200)
    }

    func testResizeBakesTheOrientationAndShrinksTheLongEdge() {
        let src = makeImage("photo.jpg", type: "public.jpeg", orientation: 6)
        guard case .success(let out) = ImageRunner.resize(src, maxPixels: 400) else { return XCTFail() }
        let p = props(out)
        XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, 300, "rotated 90°: 800×600 → 300×400")
        XCTAssertEqual(p[kCGImagePropertyPixelHeight] as? Int, 400)
        XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int ?? 1, 1, "orientation must be reset after baking it in")
    }

    func testPreviewAndSaveUseSameUprightCropThenResizePlan() throws {
        let src = makeImage("crop.jpg", type: "public.jpeg", orientation: 6)
        let options = ImageRunner.TransformOptions(crop: .init(x: 0.25, y: 0.125, width: 0.5, height: 0.5),
                                                   target: .width(150), format: .png)
        guard case .success(let preview) = ImageRunner.preview(src, options: options) else { return XCTFail("preview") }
        XCTAssertEqual(preview.plan.cropPixels.width, 300)
        XCTAssertEqual(preview.plan.cropPixels.height, 400)
        XCTAssertEqual(preview.plan.outputWidth, 150)
        XCTAssertEqual(preview.plan.outputHeight, 200)
        let sourceBefore = try Data(contentsOf: src)
        guard case .success(let out) = ImageRunner.transform(src, options: options, expectedIdentity: preview.identity) else {
            return XCTFail("save")
        }
        XCTAssertEqual(props(out)[kCGImagePropertyPixelWidth] as? Int, 150)
        XCTAssertEqual(props(out)[kCGImagePropertyPixelHeight] as? Int, 200)
        XCTAssertEqual(props(out)[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        XCTAssertEqual(try Data(contentsOf: src), sourceBefore, "source bytes must remain unchanged")
    }

    func testPublishingKeepsExistingCopiesAndNeverChangesTheInput() throws {
        let src = makeImage("kept.jpg", type: "public.jpeg")
        let original = try Data(contentsOf: src)
        let options = ImageRunner.TransformOptions(format: .png)
        guard case .success(let first) = ImageRunner.transform(src, options: options),
              case .success(let second) = ImageRunner.transform(src, options: options) else { return XCTFail("save copies") }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: src), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testPreviewIdentityRejectsChangedSourceAndNoUpscaleCreatesNothing() throws {
        let src = makeImage("stable.png", type: "public.png")
        let sourceBefore = try Data(contentsOf: src)
        let options = ImageRunner.TransformOptions(target: .longestEdge(2048), format: .png)
        guard case .success(let preview) = ImageRunner.preview(src, options: options) else { return XCTFail("preview") }
        XCTAssertTrue(preview.willSkip)
        XCTAssertEqual(ImageRunner.transform(src, options: options, expectedIdentity: preview.identity),
                       .failure(.invalidTransform("Kích thước đích sẽ phóng lớn ảnh nhỏ; hãy bật Phóng lớn ảnh nhỏ.")))
        XCTAssertEqual(try Data(contentsOf: src), sourceBefore)

        try Data("changed".utf8).write(to: src)
        XCTAssertEqual(ImageRunner.transform(src, options: options, expectedIdentity: preview.identity),
                       .failure(.staleSource("stable.png")))
    }

    func testAnimatedGIFIsRejectedWithoutWritingAStillCopy() {
        let first = makeImage("frame1.png", type: "public.png")
        let second = makeImage("frame2.png", type: "public.png", orientation: 1)
        let animated = dir.appendingPathComponent("moving.gif")
        guard let d = CGImageDestinationCreateWithURL(animated as CFURL, "com.compuserve.gif" as CFString, 2, nil),
              let a = CGImageSourceCreateWithURL(first as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }),
              let b = CGImageSourceCreateWithURL(second as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else {
            return XCTFail("Could not build GIF fixture")
        }
        CGImageDestinationAddImage(d, a, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        CGImageDestinationAddImage(d, b, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(d))
        let original = try! Data(contentsOf: animated)
        XCTAssertEqual(ImageRunner.convert(animated, to: .png), .failure(.animatedUnsupported("moving.gif")))
        XCTAssertEqual(try! Data(contentsOf: animated), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("moving") }, ["moving.gif"])
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
