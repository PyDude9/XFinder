import Foundation
import Vision
import CoreGraphics

/// Vision text recognition for one screen region: `.accurate` with language correction. Unlike
/// the clipboard's index (`.fast`, English-class languages only), `.fast` is measured to lose accuracy
/// here (a test goes red). `vi-VT` is requested for Vietnamese, but measured 2026-10-10 on macOS 27 it
/// read the sample texts IDENTICALLY to `en-US` alone — so it is a harmless request, not a demonstrated
/// gain. Known misses at small sizes: a hook-above mark can drop (`Thuỷ` → `Thuy`, `Phủ` → `Phù`). Runs
/// on the calling thread: call it off the main actor.
///
/// 2026-10-21 — the recognition itself runs in `VisionChild` (`XFinder --vision ocr-*`), a process that exits when it is
/// done, because Vision keeps tens of megabytes in whichever process ran it first. `recognizeHere` is the in-process
/// path: the child's work, the fallback when the child cannot run, and what the tests exercise.
enum ScreenTextRecognizer {

    enum Level: String {
        case fast, accurate
        var job: VisionChild.Job { self == .fast ? .ocrFast : .ocrAccurate }
    }

    static let languages = ["vi-VT", "en-US"]

    /// `.accurate` for screen text and image files; the clipboard's search index asks for `.fast`.
    static func recognize(_ image: CGImage, level: Level = .accurate) -> [OCRText.Line] {
        if VisionChild.isAvailable, let data = VisionChild.encode(image),
           let reply = VisionChild.run(level.job, imageData: data), reply.status == VisionChild.Status.ok,
           let lines = OCRWire.decode(reply.output) {
            return lines
        }
        return recognizeHere(image, level: level)
    }

    /// The bytes of an image file, in any format ImageIO reads. nil when they are not an image.
    static func recognize(imageData: Data, level: Level) -> [OCRText.Line]? {
        if VisionChild.isAvailable, let reply = VisionChild.run(level.job, imageData: imageData) {
            if reply.status == VisionChild.Status.ok, let lines = OCRWire.decode(reply.output) { return lines }
            if reply.status == VisionChild.Status.notAnImage { return nil }
        }
        guard let image = VisionChild.decode(imageData) else { return nil }
        return recognizeHere(image, level: level)
    }

    /// In THIS process.
    static func recognizeHere(_ image: CGImage, level: Level) -> [OCRText.Line] {
        let request = VNRecognizeTextRequest()
        switch level {
        case .accurate:
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Only languages this OS build actually supports; an unsupported entry would throw.
            let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
            let chosen = languages.filter { supported.contains($0) }
            if !chosen.isEmpty { request.recognitionLanguages = chosen }
        case .fast:
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            return OCRText.Line(text: top.string, box: obs.boundingBox, confidence: top.confidence)
        }
    }
}

/// The lines on the wire between the Vision child and the app: JSON, every field of a line.
enum OCRWire {
    struct Line: Codable, Equatable {
        var text: String
        var x: Double, y: Double, w: Double, h: Double
        var confidence: Float
    }

    static func encode(_ lines: [OCRText.Line]) -> Data {
        let wire = lines.map {
            Line(text: $0.text, x: Double($0.box.minX), y: Double($0.box.minY), w: Double($0.box.width),
                 h: Double($0.box.height), confidence: $0.confidence)
        }
        return (try? JSONEncoder().encode(wire)) ?? Data("[]".utf8)
    }

    /// nil for anything that is not the child's JSON — a crash, a truncated pipe, the wrong program.
    static func decode(_ data: Data) -> [OCRText.Line]? {
        guard let wire = try? JSONDecoder().decode([Line].self, from: data) else { return nil }
        return wire.map { OCRText.Line(text: $0.text, box: CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h), confidence: $0.confidence) }
    }
}
