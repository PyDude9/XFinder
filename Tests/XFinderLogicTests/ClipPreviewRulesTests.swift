import XCTest
import Foundation

/// The two preview rules that cost hundreds of MB when wrong (Clipboard Library, measured 2026-10-13).
final class ClipPreviewRulesTests: XCTestCase {
    typealias R = ClipPreviewRules

    func testOnlyImageExtensionsMayBeDecoded() {
        for yes in ["/a/b.png", "/a/b.PNG", "shot.jpg", "x.jpeg", "x.heic", "x.HEIC", "x.gif", "x.tiff", "x.webp", "x.bmp",
                    "/Users/me/Desktop/Screenshot 2026-10-13 at 07.00.00.png"] {
            XCTAssertTrue(R.isImageFile(yes), yes)
        }
        // The measured case first: a copied 42 MB .mp4 must never reach NSImage/ImageIO.
        for no in ["/Users/me/Movies/2026-10-12_06-47-39.mp4", "clip.mov", "notes.md", "a.txt", "doc.pdf", "a.zip",
                   "Screenshot 2026-10-13 at 07.00.00", "/Users/me/Desktop", "", "archive.tar.gz", "noext."] {
            XCTAssertFalse(R.isImageFile(no), no)
        }
    }

    /// side × side premultiplied RGBA filled with `fill`, with an optional block of `block` in the top-left corner.
    private func bitmap(side: Int = 8, row: Int? = nil, fill: [UInt8], block: [UInt8]? = nil, blockSide: Int = 3,
                        padding: [UInt8] = [0, 255, 0, 255]) -> (bytes: [UInt8], row: Int) {
        let rowBytes = row ?? side * 4
        var b = [UInt8](repeating: 0, count: rowBytes * side)
        for y in 0..<side {
            for x in 0..<(rowBytes / 4) {
                let i = y * rowBytes + x * 4
                let px = x >= side ? padding : ((block != nil && x < blockSide && y < blockSide) ? block! : fill)
                b[i] = px[0]; b[i + 1] = px[1]; b[i + 2] = px[2]; b[i + 3] = px[3]
            }
        }
        return (b, rowBytes)
    }

    func testTheMostVividRegionWinsOverGrey() {
        let m = bitmap(fill: [128, 128, 128, 255], block: [220, 30, 40, 255])
        let c = R.dominantColor(rgba: m.bytes, width: 8, height: 8)
        XCTAssertNotNil(c)
        XCTAssertGreaterThan(c!.r, 0.8); XCTAssertLessThan(c!.g, 0.2); XCTAssertLessThan(c!.b, 0.2)
    }

    func testGreyTransparentAndExtremeIconsGiveNoAccent() {
        XCTAssertNil(R.dominantColor(rgba: bitmap(fill: [128, 128, 128, 255]).bytes, width: 8, height: 8), "grey has no saturation")
        XCTAssertNil(R.dominantColor(rgba: bitmap(fill: [0, 0, 0, 0], block: [250, 0, 0, 100]).bytes, width: 8, height: 8),
                     "pixels under 50 % alpha are skipped")
        XCTAssertNil(R.dominantColor(rgba: bitmap(fill: [10, 0, 0, 255]).bytes, width: 8, height: 8), "too dark")
        XCTAssertNil(R.dominantColor(rgba: [], width: 8, height: 8), "a short buffer is refused, never read past")
        XCTAssertNil(R.dominantColor(rgba: bitmap(fill: [200, 0, 0, 255]).bytes, width: 0, height: 8))
    }

    /// CGContext gives PREMULTIPLIED alpha: a pure blue at 60 % alpha is stored as (0, 0, 153). Un-premultiplied it
    /// is full blue; read as-is it would be a dark navy and score lower than a duller opaque colour.
    func testPremultipliedPixelsAreUnpremultipliedBeforeScoring() {
        let m = bitmap(fill: [0, 0, 0, 0], block: [0, 0, 153, 153])
        let c = R.dominantColor(rgba: m.bytes, width: 8, height: 8)
        XCTAssertNotNil(c)
        XCTAssertGreaterThan(c!.b, 0.95, "153/255 ÷ 0.6 alpha = 1.0")
    }

    /// CoreGraphics pads rows; the padding (vivid green here) must never be read as a pixel.
    func testRowPaddingIsNeverRead() {
        let m = bitmap(side: 8, row: 48, fill: [128, 128, 128, 255], padding: [0, 230, 0, 255])
        XCTAssertNil(R.dominantColor(rgba: m.bytes, width: 8, height: 8, bytesPerRow: m.row),
                     "grey image + green padding ⇒ no accent; a green answer means the padding was sampled")
        let withRed = bitmap(side: 8, row: 48, fill: [128, 128, 128, 255], block: [220, 30, 40, 255], padding: [0, 230, 0, 255])
        let c = R.dominantColor(rgba: withRed.bytes, width: 8, height: 8, bytesPerRow: withRed.row)
        XCTAssertGreaterThan(c?.r ?? 0, 0.8)
    }

    func testTheIconSampleIsSmall() {
        XCTAssertLessThanOrEqual(R.iconSampleSide * R.iconSampleSide * 4, 16 * 1024,
                                 "the accent colour must come from a few KB, not a TIFF of every icon size")
    }
}

/// PDF previews: `NSImage(contentsOfFile:)` used to show page 1 of a copied PDF; the image-only rule above would
/// have silently dropped that, so PDFs get their own kind and a one-page renderer.
final class ClipPreviewPDFTests: XCTestCase {
    typealias R = ClipPreviewRules

    func testPreviewKindByExtensionOnly() {
        XCTAssertEqual(R.previewKind("/x/statement.pdf"), .pdf)
        XCTAssertEqual(R.previewKind("/x/STATEMENT.PDF"), .pdf)
        XCTAssertEqual(R.previewKind("/x/a.png"), .image)
        for none in ["/x/a.mp4", "/x/a.md", "/x/a.csv", "/x/folder", "/x/a.rtfd", ""] { XCTAssertEqual(R.previewKind(none), .none, none) }
        XCTAssertFalse(R.isImageFile("/x/statement.pdf"), "a PDF is not an image for ImageIO")
    }

    /// A 600×800 pt page, red in its lower half (PDF space is bottom-up), rendered at ≤ 480 px.
    private func makePDF(width: CGFloat = 600, height: CGFloat = 800) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xf-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("page.pdf")
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        ctx.endPDFPage(); ctx.closePDF()
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return url
    }

    private func rgba(_ img: CGImage, x: Int, y: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Draw so that image pixel (x, y) — y counted from the TOP — lands on the single destination pixel.
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
        return px
    }

    func testPageOneIsRenderedSmallUprightAndOnWhite() throws {
        let url = try makePDF()
        let img = try XCTUnwrap(R.pdfFirstPage(atPath: url.path, maxPixel: 480))
        XCTAssertEqual(img.height, 480, "long side scaled to maxPixel")
        XCTAssertEqual(img.width, 360, "aspect kept: 600 × 480 / 800")
        let bottom = rgba(img, x: 180, y: 400), top = rgba(img, x: 180, y: 60)
        XCTAssertGreaterThan(bottom[0], 200); XCTAssertLessThan(bottom[1], 60, "the red half is at the bottom, not flipped")
        XCTAssertGreaterThan(top[0], 240); XCTAssertGreaterThan(top[1], 240); XCTAssertGreaterThan(top[2], 240)
        XCTAssertEqual(top[3], 255, "white behind the page, never transparent")
    }

    func testLandscapeSmallMissingAndZero() throws {
        let wide = try XCTUnwrap(R.pdfFirstPage(atPath: try makePDF(width: 800, height: 400).path, maxPixel: 480))
        XCTAssertEqual(wide.width, 480); XCTAssertEqual(wide.height, 240)
        let small = try XCTUnwrap(R.pdfFirstPage(atPath: try makePDF(width: 200, height: 100).path, maxPixel: 480))
        XCTAssertEqual(small.width, 200, "never scaled UP past the page size")
        XCTAssertNil(R.pdfFirstPage(atPath: "/nonexistent/x.pdf"))
        XCTAssertNil(R.pdfFirstPage(atPath: try makePDF().path, maxPixel: 0))
    }
}
