import Foundation
import ImageIO
import CoreGraphics

/// N6 (2026-10-13) — OCR of an image FILE held on the notch (OneNotch's "OCR" file action, re-derived): the
/// recognised lines in reading order, top to bottom, as one text. Same Vision configuration as the screen OCR
/// (`ScreenTextRecognizer`, `.accurate`, language correction), so the two surfaces cannot disagree. The caller
/// writes the text beside the image and puts it on the clipboard; this file only reads.
enum ImageTextOCR {
    enum Failure: Error, Equatable {
        case unreadable(String)
        case noText(String)

        var messageKey: String {
            switch self {
            case .unreadable: return "Không đọc được ảnh: "
            case .noText: return "Không thấy chữ nào trong: "
            }
        }
        var detail: String {
            switch self {
            case .unreadable(let s), .noText(let s): return s
            }
        }
        static let examples: [Failure] = [.unreadable("a"), .noText("a")]
    }

    /// Lines → one text in reading order. Vision's boxes are normalised with a BOTTOM-LEFT origin, so the top
    /// line has the largest `maxY`; ties (one visual line split in two) go left to right.
    static func text(from lines: [OCRText.Line]) -> String {
        let ordered = lines.sorted { a, b in
            let dy = a.box.maxY - b.box.maxY
            if abs(dy) > 0.008 { return dy > 0 }
            return a.box.minX < b.box.minX
        }
        return ordered.map(\.text).joined(separator: "\n")
    }

    /// "<stem>.txt" beside the image, keep-both.
    static func outputURL(for source: URL, exists: (URL) -> Bool) -> URL {
        let dir = source.deletingLastPathComponent()
        let base = dir.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".txt")
        guard case .write(let url) = ArchiveEngine.destination(base: base, policy: .keepBoth, exists: exists) else { return base }
        return url
    }

    /// Runs on the calling thread (call it off the main actor). The first call per process waits for the
    /// Neural Engine daemon — measured 1–8 s on OneNotch's notes, 0.4 s warm.
    static func recognize(_ url: URL) -> Result<String, Failure> {
        guard let cg = PDFAssembler.orientedImage(at: url) else { return .failure(.unreadable(url.lastPathComponent)) }
        let lines = ScreenTextRecognizer.recognize(cg)
        let text = text(from: lines).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.noText(url.lastPathComponent)) }
        return .success(text)
    }
}
