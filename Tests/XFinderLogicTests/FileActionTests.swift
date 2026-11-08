import XCTest
import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// N6 — the three new notch file actions: Sang PDF, OCR, Thu nhỏ (resize presets), against generated files.
final class FileActionTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("xf-n6-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// A PNG of `w`×`h` with a solid colour and, optionally, big black text drawn with Core Text.
    func png(_ name: String, w: Int = 800, h: Int = 400, text: String? = nil) throws -> URL {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if let text {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
            ctx.textPosition = CGPoint(x: 40, y: h / 2 - 24)
            CTLineDraw(line, ctx)
        }
        let img = ctx.makeImage()!
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    // MARK: Sang PDF

    func testImagesAndPDFsBecomeOnePDFBesideTheFirstInputInOrder() throws {
        let a = try png("a.png", w: 300, h: 200), b = try png("b.png", w: 200, h: 300)
        // a two-page PDF held in the middle
        let doc = PDFDocument()
        doc.insert(PDFPage(image: NSImage(cgImage: PDFAssembler.orientedImage(at: a)!, size: .init(width: 300, height: 200)))!, at: 0)
        doc.insert(PDFPage(image: NSImage(cgImage: PDFAssembler.orientedImage(at: b)!, size: .init(width: 200, height: 300)))!, at: 1)
        let p = dir.appendingPathComponent("mid.pdf"); XCTAssertTrue(doc.write(to: p))
        let out = try PDFAssembler.assemble([a, p, b, dir.appendingPathComponent("notes.txt")]).get()
        XCTAssertEqual(out.deletingLastPathComponent().standardizedFileURL.path, dir.standardizedFileURL.path, "beside the first input")
        XCTAssertEqual(out.lastPathComponent, "a.pdf", "named after the first input")
        let result = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(result.pageCount, 4, "1 image + 2 pages + 1 image, the .txt ignored")
        XCTAssertEqual(Int(result.page(at: 0)!.bounds(for: .mediaBox).width), 300)
        XCTAssertEqual(Int(result.page(at: 3)!.bounds(for: .mediaBox).width), 200)
    }

    func testAnimatedImageIsRejectedForImageToPDFWithoutCreatingAStillPage() throws {
        let a = try png("frame-a.png", w: 30, h: 20)
        let b = try png("frame-b.png", w: 20, h: 30)
        let first = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(a as CFURL, nil)!, 0, nil)!
        let second = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(b as CFURL, nil)!, 0, nil)!
        let animation = dir.appendingPathComponent("animated.gif")
        let destination = CGImageDestinationCreateWithURL(animation as CFURL, "com.compuserve.gif" as CFString, 2, nil)!
        CGImageDestinationAddImage(destination, first, nil)
        CGImageDestinationAddImage(destination, second, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertEqual(PDFAssembler.assemble([animation]), .failure(.animatedUnsupported("animated.gif")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".pdf") }.count, 0)
    }

    func testToPDFNeverOverwritesAndRefusesNothing() throws {
        let a = try png("a.png")
        let first = try PDFAssembler.assemble([a]).get()
        let second = try PDFAssembler.assemble([a]).get()
        XCTAssertNotEqual(first, second, "keep-both: the second run gets a new name")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path) && FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(PDFAssembler.assemble([dir.appendingPathComponent("x.txt")]), .failure(.noInputs))
        // the output of a PDF input is never the input itself
        let out = PDFAssembler.outputURL(for: [dir.appendingPathComponent("r.pdf")], exists: { _ in false })
        XCTAssertNotEqual(out?.lastPathComponent, "r.pdf")
    }

    func testEveryPDFFailureKeyIsInTheStore() throws {
        let store = try L10nFixture.load()
        for f in PDFAssembler.Failure.examples { XCTAssertNotNil(store.entries[f.messageKey], f.messageKey) }
        for f in ImageTextOCR.Failure.examples { XCTAssertNotNil(store.entries[f.messageKey], f.messageKey) }
    }

    // MARK: OCR

    func testOCRReadsBigTextFromAnImageFile() throws {
        let url = try png("text.png", w: 1200, h: 300, text: "XFINDER 2026")
        let text = try ImageTextOCR.recognize(url).get()
        XCTAssertTrue(text.uppercased().contains("XFINDER"), text)
        XCTAssertTrue(text.contains("2026"), text)
    }

    func testOCRRefusesABlankImageAndAnUnreadableFile() throws {
        let blank = try png("blank.png")
        XCTAssertEqual(ImageTextOCR.recognize(blank), .failure(.noText("blank.png")))
        XCTAssertEqual(ImageTextOCR.recognize(dir.appendingPathComponent("nope.png")), .failure(.unreadable("nope.png")))
    }

    func testLinesAreJoinedTopToBottomThenLeftToRight() {
        func line(_ t: String, x: CGFloat, y: CGFloat) -> OCRText.Line { .init(text: t, box: CGRect(x: x, y: y, width: 0.2, height: 0.05), confidence: 1) }
        let lines = [line("bottom", x: 0.1, y: 0.1), line("top-right", x: 0.6, y: 0.8), line("top-left", x: 0.1, y: 0.8), line("middle", x: 0.1, y: 0.5)]
        XCTAssertEqual(ImageTextOCR.text(from: lines), "top-left\ntop-right\nmiddle\nbottom")
    }

    func testOCROutputNameIsKeepBoth() {
        let src = dir.appendingPathComponent("scan.png")
        XCTAssertEqual(ImageTextOCR.outputURL(for: src, exists: { _ in false }).lastPathComponent, "scan.txt")
        let taken = ImageTextOCR.outputURL(for: src, exists: { $0.lastPathComponent == "scan.txt" }).lastPathComponent
        XCTAssertNotEqual(taken, "scan.txt"); XCTAssertTrue(taken.hasSuffix(".txt"))
    }

    // MARK: Actions on the notch

    func testTheNewActionsAreOfferedForImagesAndCountStepsHonestly() {
        let img = dir.appendingPathComponent("a.png"), pdf = dir.appendingPathComponent("b.pdf"), txt = dir.appendingPathComponent("c.txt")
        let offered = NotchActions.available(for: [img, pdf], encodable: ["public.jpeg", "public.png"])
        XCTAssertTrue(offered.contains(.toPDF)); XCTAssertTrue(offered.contains(.ocr))
        XCTAssertTrue(offered.contains(.resize(maxPixels: ImageEngine.resizePresets[2])))
        XCTAssertFalse(NotchActions.available(for: [txt, pdf], encodable: []).contains(.ocr), "no image ⇒ no OCR")
        XCTAssertFalse(NotchActions.available(for: [txt], encodable: []).contains(.toPDF))
        XCTAssertTrue(NotchActions.available(for: [pdf], encodable: []).contains(.toPDF), "a single PDF still gets a (copied) PDF — mergePDFs needs two")
        XCTAssertEqual(NotchActions.inputs(for: .toPDF, from: [img, pdf, txt]), [img, pdf])
        XCTAssertEqual(NotchActions.inputs(for: .ocr, from: [img, pdf, txt]), [img])
        XCTAssertEqual(NotchActions.stepCount(for: .toPDF, inputs: 2), 1, "one output ⇒ one step")
        XCTAssertEqual(NotchActions.stepCount(for: .ocr, inputs: 3), 3)
        XCTAssertEqual(NotchActions.stepCount(for: .resize(maxPixels: 1600), inputs: 2), 2)
    }
}
