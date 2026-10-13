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
