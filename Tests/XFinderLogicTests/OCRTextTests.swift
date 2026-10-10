import XCTest
import Foundation
import AppKit

final class OCRTextTests: XCTestCase {
    private func line(_ t: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.2, h: CGFloat = 0.04, c: Float = 0.9) -> OCRText.Line {
        .init(text: t, box: CGRect(x: x, y: y, width: w, height: h), confidence: c)
    }

    func testReadsTopToBottomEvenWhenVisionReturnsThemShuffled() {
        let text = OCRText.assemble([line("third", x: 0.1, y: 0.2), line("first", x: 0.1, y: 0.8), line("second", x: 0.1, y: 0.5)])
        XCTAssertEqual(text, "first\nsecond\nthird", "Vision's y axis points UP: larger y is earlier")
    }

    func testLinesOnOneVisualRowJoinLeftToRightWithATab() {
        let text = OCRText.assemble([line("Price", x: 0.6, y: 0.5), line("Name", x: 0.1, y: 0.505), line("Row two", x: 0.1, y: 0.3)])
        XCTAssertEqual(text, "Name\tPrice\nRow two")
    }

    func testNarrowlyOffsetRowsStaySeparate() {
        // Heights 0.04, offset 0.03: overlap 0.01 < half of 0.04 ⇒ two rows.
        XCTAssertEqual(OCRText.assemble([line("a", x: 0.1, y: 0.50), line("b", x: 0.5, y: 0.47)]), "a\nb")
    }

    func testNoiseAndEmptyLinesAreDropped() {
        XCTAssertEqual(OCRText.assemble([line("real", x: 0.1, y: 0.5), line("▒▒", x: 0.1, y: 0.4, c: 0.1), line("   ", x: 0.1, y: 0.3)]), "real")
    }

    func testNothingUsableIsNilNotAnEmptyString() {
        XCTAssertNil(OCRText.assemble([]))
        XCTAssertNil(OCRText.assemble([line("x", x: 0, y: 0, c: 0.05), line(" \n ", x: 0, y: 0.5)]))
    }

    func testThresholdBoundary() {
        XCTAssertNotNil(OCRText.assemble([line("ok", x: 0, y: 0, c: OCRText.minimumConfidence)]))
        XCTAssertNil(OCRText.assemble([line("no", x: 0, y: 0, c: OCRText.minimumConfidence - 0.01)]))
    }

    // MARK: Real Vision on a rendered image

    /// Renders text into a bitmap, runs the REAL recogniser on it and checks the words come back.
    /// No fixture can stand in for this: the failures it catches are language/accuracy settings.
    private func render(_ lines: [String], size: CGFloat = 34) -> CGImage {
        let w = 900, h = 90 * lines.count + 40
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        for (i, s) in lines.enumerated() {
            (s as NSString).draw(at: NSPoint(x: 30, y: CGFloat(h) - 80 - CGFloat(i) * 90),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    func testRealRecognitionOfEnglishLinesInOrder() throws {
        let image = render(["Open ports and settings", "Back up your clipboard"])
        let text = try XCTUnwrap(OCRText.assemble(ScreenTextRecognizer.recognize(image)))
        XCTAssertTrue(text.lowercased().contains("open ports"), text)
        XCTAssertTrue(text.lowercased().contains("clipboard"), text)
        XCTAssertLessThan(text.lowercased().range(of: "open ports")!.lowerBound, text.lowercased().range(of: "clipboard")!.lowerBound)
    }

    func testRealRecognitionKeepsVietnameseDiacritics() throws {
        let image = render(["Chào mừng đến với XFinder", "Sao lưu cài đặt của bạn"])
        let text = try XCTUnwrap(OCRText.assemble(ScreenTextRecognizer.recognize(image)))
        // The point of vi-VT + .accurate: the DIACRITICS survive, not just the base letters.
        XCTAssertTrue(text.contains("mừng"), "diacritics lost: \(text)")
        XCTAssertTrue(text.contains("đến") || text.contains("Chào"), "diacritics lost: \(text)")
        XCTAssertTrue(text.contains("XFinder"), text)
    }

    func testABlankImageYieldsNoTextNotGarbage() {
        XCTAssertNil(OCRText.assemble(ScreenTextRecognizer.recognize(render([" "]))))
    }
}
