import Foundation
import PDFKit

/// Runs the PDF tools with PDFKit. No AppKit, so the test package exercises it on generated PDFs.
/// Results are written next to the source (or a chosen folder) under a name from `PdfEngine.outputURL`,
/// so a run never replaces an earlier result or a source.
enum PdfRunner {

    enum Failure: Error, Equatable {
        case unreadable(String)          // file name
        case invalidRange(pageCount: Int)
        case writeFailed(String)         // file name

        var messageKey: String {
            switch self {
            case .unreadable: return "Không đọc được tập tin PDF: "
            case .invalidRange: return "Khoảng trang không hợp lệ. Số trang của tài liệu: "
            case .writeFailed: return "Không ghi được tập tin đích: "
            }
        }
        var detail: String {
            switch self {
            case .unreadable(let n), .writeFailed(let n): return n
            case .invalidRange(let c): return "\(c)"
            }
        }
        static let examples: [Failure] = [.unreadable("a"), .invalidRange(pageCount: 3), .writeFailed("a")]
    }

    struct Output: Equatable {
        let url: URL
        let pages: Int
    }

    static func merge(_ sources: [URL], into folder: URL) -> Result<Output, Failure> {
        var docs: [PDFDocument] = []
        for url in sources {
            guard let d = PDFDocument(url: url) else { return .failure(.unreadable(url.lastPathComponent)) }
            docs.append(d)
        }
        let out = PDFDocument()
        for d in docs {
            for i in 0..<d.pageCount {
                if let page = d.page(at: i) { out.insert(page, at: out.pageCount) }
            }
        }
        return write(out, tool: .merge, sources: sources, folder: folder)
    }

    static func extract(_ source: URL, range: String, into folder: URL) -> Result<Output, Failure> {
        guard let doc = PDFDocument(url: source) else { return .failure(.unreadable(source.lastPathComponent)) }
        guard let pages = PdfEngine.pageIndices(range, pageCount: doc.pageCount, emptyMeansAll: false) else {
            return .failure(.invalidRange(pageCount: doc.pageCount))
        }
        let out = PDFDocument()
        for p in pages { if let page = doc.page(at: p) { out.insert(page, at: out.pageCount) } }
        return write(out, tool: .extract, sources: [source], folder: folder)
    }

    static func rotate(_ source: URL, range: String, degrees: Int, into folder: URL) -> Result<Output, Failure> {
        guard let doc = PDFDocument(url: source) else { return .failure(.unreadable(source.lastPathComponent)) }
        guard let pages = PdfEngine.pageIndices(range, pageCount: doc.pageCount, emptyMeansAll: true) else {
            return .failure(.invalidRange(pageCount: doc.pageCount))
        }
        for p in pages { if let page = doc.page(at: p) { page.rotation = ((page.rotation + degrees) % 360 + 360) % 360 } }
        guard case .success(let o) = write(doc, tool: .rotate, sources: [source], folder: folder) else {
            return .failure(.writeFailed(source.lastPathComponent))
        }
        return .success(Output(url: o.url, pages: pages.count))
    }

    private static func write(_ doc: PDFDocument, tool: PdfEngine.Tool, sources: [URL], folder: URL) -> Result<Output, Failure> {
        let dest = PdfEngine.outputURL(tool: tool, sources: sources, folder: folder,
                                       exists: { FileManager.default.fileExists(atPath: $0.path) })
        guard doc.write(to: dest) else { return .failure(.writeFailed(dest.lastPathComponent)) }
        return .success(Output(url: dest, pages: doc.pageCount))
    }
}
