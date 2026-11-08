import XCTest
import Foundation
import PDFKit
import CoreGraphics
import CoreText
import Dispatch

final class PdfEngineTests: XCTestCase {

    func testPageRangesAreOneBasedSortedAndDeduplicated() {
        XCTAssertEqual(PdfEngine.pageIndices("1-3", pageCount: 5, emptyMeansAll: false), [0, 1, 2])
        XCTAssertEqual(PdfEngine.pageIndices(" 5 , 2,2, 1-2 ", pageCount: 5, emptyMeansAll: false), [0, 1, 4])
    }

    func testInvalidRangesAreRejectedNotClamped() {
        for bad in ["0-1", "3-1", "1-6", "7", "a", "1,,2", "1-", "-2", "1-2-3"] {
            XCTAssertNil(PdfEngine.pageIndices(bad, pageCount: 5, emptyMeansAll: false), bad)
        }
    }

    func testEmptyMeansAllOnlyWhenAsked() {
        XCTAssertEqual(PdfEngine.pageIndices("", pageCount: 3, emptyMeansAll: true), [0, 1, 2])
        XCTAssertNil(PdfEngine.pageIndices("  ", pageCount: 3, emptyMeansAll: false))
        XCTAssertNil(PdfEngine.pageIndices("", pageCount: 0, emptyMeansAll: true))
    }

    func testPageOrderingRequiresACompleteUniqueSequenceAndPreservesOrder() {
        XCTAssertEqual(PdfEngine.orderedPageIndices("3,1,2", pageCount: 3), [2, 0, 1])
        XCTAssertEqual(PdfEngine.orderedPageIndices("3-4,1-2", pageCount: 4), [2, 3, 0, 1])
        for invalid in ["", "1,1,2", "1,2", "1,2,4", "0,1,2", "3-1,2", "1,,2,3"] {
            XCTAssertNil(PdfEngine.orderedPageIndices(invalid, pageCount: 3), invalid)
        }
    }

    /// The measured bug: write(to:) silently overwrites, and the names were deterministic.
    func testOutputNeverReplacesAnExistingFileOrASource() {
        let folder = URL(fileURLWithPath: "/tmp/p")
        let taken: Set<String> = ["/tmp/p/Report-pages.pdf"]
        let u = PdfEngine.outputURL(tool: .extract, sources: [URL(fileURLWithPath: "/tmp/p/Report.pdf")], folder: folder,
                                    exists: { taken.contains($0.path) })
        XCTAssertEqual(u.lastPathComponent, "Report-pages 2.pdf")
        // A source literally named like the output must not be the target either.
        let src = URL(fileURLWithPath: "/tmp/p/Merged.pdf")
        let m = PdfEngine.outputURL(tool: .merge, sources: [src, URL(fileURLWithPath: "/tmp/p/b.pdf")], folder: folder, exists: { _ in false })
        XCTAssertNotEqual(m.path, src.path)
    }

    func testExclusivePublishRejectsLateCollisionWithoutReplacingEitherFile() throws {
        let staged = dir.appendingPathComponent("staged.pdf")
        let target = dir.appendingPathComponent("late-collision.pdf")
        try Data("staged output".utf8).write(to: staged)
        try Data("other process output".utf8).write(to: target)
        XCTAssertFalse(PdfRunner.publishExclusive(staged: staged, target: target))
        XCTAssertEqual(try Data(contentsOf: staged), Data("staged output".utf8))
        XCTAssertEqual(try Data(contentsOf: target), Data("other process output".utf8))
    }

    func testCancelledPDFOperationWritesNoOutputAndKeepsSource() async throws {
        let source = makePDF("cancelled.pdf", pages: 2)
        let folder = dir!
        let original = try Data(contentsOf: source)
        let gate = DispatchSemaphore(value: 0)
        let task = Task.detached {
            gate.wait()
            return PdfRunner.extract(source, range: "1-2", into: folder)
        }
        task.cancel()
        gate.signal()
        let result = await task.value
        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["cancelled.pdf"])
    }

    func testEveryFailureKeyIsInTheStore() throws {
        let store = try L10nFixture.load()
        for f in PdfRunner.Failure.examples {
            XCTAssertNotNil(store.entries[f.messageKey], f.messageKey)
        }
    }

    // MARK: Integration — real PDFKit on generated files

    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("xf-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func makePDF(_ name: String, pages: Int) -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        for _ in 0..<pages { ctx.beginPDFPage(nil); ctx.endPDFPage() }
        ctx.closePDF()
        return url
    }

    func makeVectorTextPDF(_ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 20, y: 20))
        context.addLine(to: CGPoint(x: 200, y: 80))
        context.strokePath()
        let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
        let text = NSAttributedString(string: "Selectable fixture",
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage()
        context.closePDF()
        return url
    }

    func makeRawPDF(_ name: String, catalogExtras: String = "", corruptStartXref: Bool = false) throws -> URL {
        let url = dir.appendingPathComponent(name)
        var data = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = [0]
        let objects = [
            "1 0 obj\n<< /Type /Catalog /Pages 2 0 R \(catalogExtras) >>\nendobj\n",
            "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
            "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << >> /Contents 4 0 R >>\nendobj\n",
            "4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n"
        ]
        for object in objects {
            offsets.append(data.count)
            data.append(Data(object.utf8))
        }
        let xrefOffset = data.count
        var xref = "xref\n0 5\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { xref += String(format: "%010d 00000 n \n", offset) }
        xref += "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(corruptStartXref ? data.count + 1_000_000 : xrefOffset)\n%%EOF\n"
        data.append(Data(xref.utf8))
        try data.write(to: url)
        return url
    }

    func testMergeTwiceKeepsBothResults() {
        let a = makePDF("a.pdf", pages: 3), b = makePDF("b.pdf", pages: 2)
        guard case .success(let first) = PdfRunner.merge([a, b], into: dir),
              case .success(let second) = PdfRunner.merge([a, b], into: dir) else { return XCTFail() }
        XCTAssertEqual(first.pages, 5)
        XCTAssertNotEqual(first.url, second.url, "the second merge replaced the first")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
    }

    func testExtractAndRotateWriteNewFilesAndLeaveTheSourceAlone() throws {
        let src = makePDF("doc.pdf", pages: 4)
        let before = try Data(contentsOf: src)
        guard case .success(let ex) = PdfRunner.extract(src, range: "2-3", into: dir) else { return XCTFail() }
        XCTAssertEqual(PDFDocument(url: ex.url)?.pageCount, 2)
        guard case .success(let rot) = PdfRunner.rotate(src, range: "1", degrees: 90, into: dir) else { return XCTFail() }
        XCTAssertEqual(PDFDocument(url: rot.url)?.page(at: 0)?.rotation, 90)
        XCTAssertEqual(PDFDocument(url: rot.url)?.page(at: 1)?.rotation, 0)
        XCTAssertEqual(try Data(contentsOf: src), before, "the source PDF was modified")
    }

    func testReorderWritesPagesInRequestedOrderAndNeverChangesSource() throws {
        let src = makePDF("ordered.pdf", pages: 3)
        let sourceDocument = try XCTUnwrap(PDFDocument(url: src))
        sourceDocument.page(at: 0)?.rotation = 0
        sourceDocument.page(at: 1)?.rotation = 90
        sourceDocument.page(at: 2)?.rotation = 180
        XCTAssertTrue(sourceDocument.write(to: src))
        let before = try Data(contentsOf: src)
        guard case .success(let out) = PdfRunner.reorder(src, order: "3,1,2", into: dir) else { return XCTFail("reorder failed") }
        let result = try XCTUnwrap(PDFDocument(url: out.url))
        XCTAssertEqual((0..<result.pageCount).compactMap { result.page(at: $0)?.rotation }, [180, 0, 90])
        XCTAssertEqual(try Data(contentsOf: src), before)
    }

    func testMissingTerminalEOFIsReportedAsARewrittenRecoveryCopy() throws {
        let source = makePDF("recoverable.pdf", pages: 2)
        let original = try Data(contentsOf: source)
        let eof = Data("%%EOF".utf8)
        guard let range = original.range(of: eof, options: .backwards) else { return XCTFail("fixture has no EOF") }
        var damaged = original
        damaged.removeSubrange(range)
        try damaged.write(to: source)
        guard PDFDocument(url: source) != nil else { return XCTFail("PDFKit did not expose the recoverable page tree") }
        guard case .success(let output) = PdfRunner.extract(source, range: "1-2", into: dir) else { return XCTFail("recovery copy was refused") }
        XCTAssertTrue(output.rewrittenAfterRecoveryWarning)
        XCTAssertEqual(try Data(contentsOf: source), damaged)
        XCTAssertFalse(try Data(contentsOf: output.url).isEmpty)
    }

    func testOutOfFileStartXrefIsRefusedWhenRewriteCannotVerifyContentStreams() throws {
        let source = makeVectorTextPDF("xref-offset.pdf")
        var bytes = try Data(contentsOf: source)
        let marker = Data("startxref".utf8)
        var cursor = try XCTUnwrap(bytes.range(of: marker, options: .backwards)).upperBound
        while cursor < bytes.endIndex, [10, 13, 32, 9].contains(bytes[cursor]) { cursor += 1 }
        let number = cursor
        var digitsEnd = number
        while digitsEnd < bytes.endIndex, (48...57).contains(bytes[digitsEnd]) { digitsEnd += 1 }
        XCTAssertGreaterThan(digitsEnd, number)
        bytes.replaceSubrange(number..<digitsEnd, with: Data("999999999".utf8))
        try bytes.write(to: source)
        XCTAssertEqual(PDFDocument(url: source)?.pageCount, 1, "the repair fixture needs a PDFKit-readable page tree")
        XCTAssertEqual(CGPDFDocument(source as CFURL)?.numberOfPages, 1, "the repair fixture needs a CoreGraphics-readable page tree")
        let damagedBytes = try Data(contentsOf: source)
        guard case .failure(.validationFailed) = PdfRunner.extract(source, range: "1", into: dir) else {
            return XCTFail("recovery must fail closed when content-stream evidence differs")
        }
        XCTAssertEqual(try Data(contentsOf: source), damagedBytes)
        let outputs = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix("-pages.pdf") }
        XCTAssertTrue(outputs.isEmpty, "unverified recovery must not publish a new PDF")
    }

    func testSignatureCatalogMarkerAndUnknownCatalogFeatureFailClosed() throws {
        let signed = try makeRawPDF("signed.pdf", catalogExtras: "/Perms << /DocMDP << /Type /Sig >> >>")
        XCTAssertEqual(PdfRunner.rotate(signed, range: "", degrees: 90, into: dir), .failure(.signed("signed.pdf")))
        let unknown = try makeRawPDF("unknown.pdf", catalogExtras: "/VendorFeature /Unknown")
        XCTAssertEqual(PdfRunner.rotate(unknown, range: "", degrees: 90, into: dir), .failure(.unsupportedStructure("unknown.pdf")))
        let outputs = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix("-rotated.pdf") }
        XCTAssertTrue(outputs.isEmpty, "refused inputs must leave no output behind")
    }

    func testSelectableTextVectorStreamAndURLLinkAreComparedAfterRewrite() throws {
        let src = makeVectorTextPDF("content.pdf")
        let source = try XCTUnwrap(PDFDocument(url: src))
        let link = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 40, height: 20), forType: .link, withProperties: nil)
        link.action = PDFActionURL(url: URL(string: "https://example.invalid/document")!)
        source.page(at: 0)?.addAnnotation(link)
        XCTAssertTrue(source.write(to: src))
        let originalBytes = try Data(contentsOf: src)
        let before = try PdfStructureInspector.inspect(src)
        XCTAssertTrue(before.pages[0].text?.contains("Selectable fixture") == true)
        guard case .success(let output) = PdfRunner.rotate(src, range: "1", degrees: 90, into: dir) else {
            return XCTFail("a PDF with inspectable text, vector content and URL link should be rewritten")
        }
        let after = try PdfStructureInspector.inspect(output.url)
        XCTAssertEqual(before.pages[0].contentStreams, after.pages[0].contentStreams)
        XCTAssertEqual(before.pages[0].xObjects, after.pages[0].xObjects)
        XCTAssertEqual(before.pages[0].annotations, after.pages[0].annotations)
        XCTAssertEqual(try Data(contentsOf: src), originalBytes)
    }

    func testBadRangeAndUnreadableFileFailWithoutWriting() {
        let src = makePDF("doc.pdf", pages: 2)
        XCTAssertEqual(PdfRunner.extract(src, range: "5", into: dir), .failure(.invalidRange(pageCount: 2)))
        let junk = dir.appendingPathComponent("junk.pdf"); try? "not a pdf".write(to: junk, atomically: true, encoding: .utf8)
        XCTAssertEqual(PdfRunner.merge([src, junk], into: dir), .failure(.unreadable("junk.pdf")))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertEqual(Set(files), ["doc.pdf", "junk.pdf"], "a failed run left output behind: \(files)")
    }
}
