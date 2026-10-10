import XCTest
import Foundation
import PDFKit
import CoreGraphics

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

    func testBadRangeAndUnreadableFileFailWithoutWriting() {
        let src = makePDF("doc.pdf", pages: 2)
        XCTAssertEqual(PdfRunner.extract(src, range: "5", into: dir), .failure(.invalidRange(pageCount: 2)))
        let junk = dir.appendingPathComponent("junk.pdf"); try? "not a pdf".write(to: junk, atomically: true, encoding: .utf8)
        XCTAssertEqual(PdfRunner.merge([src, junk], into: dir), .failure(.unreadable("junk.pdf")))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertEqual(Set(files), ["doc.pdf", "junk.pdf"], "a failed run left output behind: \(files)")
    }
}
