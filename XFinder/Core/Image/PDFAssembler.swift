import Foundation
import AppKit
import ImageIO
import PDFKit

/// N6 (2026-10-13) — "Sang PDF" on the notch (OneNotch's "To PDF" file action, re-derived): every held image
/// becomes one page, every held PDF contributes its pages, in the order held, into ONE new PDF beside the first
/// input under a keep-both name. Nothing is touched in place. Images are decoded through ImageIO with the EXIF
/// transform applied (B2c measured `NSImage(contentsOf:)` alone keeps a rotated phone photo sideways).
enum PDFAssembler {
    enum Failure: Error, Equatable {
        case noInputs
        case unreadable(String)
        case writeFailed(String)

        var messageKey: String {
            switch self {
            case .noInputs: return "Không có ảnh hay PDF nào để ghép."
            case .unreadable: return "Không đọc được: "
            case .writeFailed: return "Không ghi được PDF: "
            }
        }
        var detail: String {
            switch self {
            case .noInputs: return ""
            case .unreadable(let s), .writeFailed(let s): return s
            }
        }
        static let examples: [Failure] = [.noInputs, .unreadable("a"), .writeFailed("a")]
    }

    static func isPDF(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }

    /// What the action works on: images and PDFs, in the order held.
    static func inputs(from items: [URL]) -> [URL] { items.filter { ImageEngine.isImage($0) || isPDF($0) } }

    /// "<first stem>.pdf" beside the first input, never onto an existing file (keep-both numbering) and never
    /// onto the input itself when that input is a PDF.
    static func outputURL(for inputs: [URL], exists: (URL) -> Bool) -> URL? {
        guard let first = inputs.first else { return nil }
        let dir = first.deletingLastPathComponent()
        let base = dir.appendingPathComponent(first.deletingPathExtension().lastPathComponent + ".pdf")
        let taken: (URL) -> Bool = { u in exists(u) || inputs.contains { $0.standardizedFileURL.path == u.standardizedFileURL.path } }
        guard case .write(let url) = ArchiveEngine.destination(base: base, policy: .keepBoth, exists: taken) else { return base }
        return url
    }

    /// Build and write the PDF. Runs on the calling thread (call it off the main actor).
    static func assemble(_ items: [URL]) -> Result<URL, Failure> {
        let inputs = inputs(from: items)
        guard !inputs.isEmpty else { return .failure(.noInputs) }
        let doc = PDFDocument()
        for url in inputs {
            if isPDF(url) {
                guard let src = PDFDocument(url: url) else { return .failure(.unreadable(url.lastPathComponent)) }
                for i in 0..<src.pageCount {
                    if let page = src.page(at: i) { doc.insert(page, at: doc.pageCount) }
                }
            } else {
                guard let cg = orientedImage(at: url) else { return .failure(.unreadable(url.lastPathComponent)) }
                let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                guard let page = PDFPage(image: image) else { return .failure(.unreadable(url.lastPathComponent)) }
                doc.insert(page, at: doc.pageCount)
            }
        }
        guard let out = outputURL(for: inputs, exists: { FileManager.default.fileExists(atPath: $0.path) }) else { return .failure(.noInputs) }
        guard doc.write(to: out) else { return .failure(.writeFailed(out.lastPathComponent)) }
        return .success(out)
    }

    /// Full-resolution decode with the EXIF orientation applied (the thumbnail API at the image's own size).
    static func orientedImage(at url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1)]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
