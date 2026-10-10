import Foundation
import Vision
import CoreGraphics

/// Vision text recognition for one screen region: `.accurate` with language correction. Unlike
/// `ClipboardOCR` (tuned for fast search indexing: `.fast`, English-class languages only),
/// `.fast` is measured to lose accuracy here (a test goes red). `vi-VT` is requested for
/// Vietnamese, but measured 2026-10-10 on macOS 27 it read the sample texts IDENTICALLY to
/// `en-US` alone — so it is a harmless request, not a demonstrated gain. Known misses at small
/// sizes: a hook-above mark can drop (`Thuỷ` → `Thuy`, `Phủ` → `Phù`). Runs on the calling
/// thread: call it off the main actor.
enum ScreenTextRecognizer {

    static let languages = ["vi-VT", "en-US"]

    static func recognize(_ image: CGImage) -> [OCRText.Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Only languages this OS build actually supports; an unsupported entry would throw.
        let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
        let chosen = languages.filter { supported.contains($0) }
        if !chosen.isEmpty { request.recognitionLanguages = chosen }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            return OCRText.Line(text: top.string, box: obs.boundingBox, confidence: top.confidence)
        }
    }
}
