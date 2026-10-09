import AppKit
import Foundation
import ImageIO
import Vision
import Vision

/// Disk offload (payloads + 300px thumbnails under Application Support) and
/// Vision OCR for copied images. All work is nonisolated/background-safe; the
/// manager hops back to @MainActor only to apply results.
enum ClipboardPayloadStore {

    static func baseDir() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = appSupport.appendingPathComponent("XFinder/Clipboard", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write full image data, return (payloadPath, thumbnailPath).
    static func storeImage(_ image: NSImage) -> (payload: String, thumb: String)? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let dir = baseDir()
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let payloadURL = dir.appendingPathComponent("img-\(stamp).png")
        do { try png.write(to: payloadURL) } catch { return nil }
        let thumbURL = dir.appendingPathComponent("thumb-\(stamp).png")
        if let thumb = thumbnailPNG(from: png, maxPixel: 300) {
            try? thumb.write(to: thumbURL)
        }
        return (payloadURL.path, thumbURL.path)
    }

    /// Write raw text payload (>4KB snippets) so history stays light in RAM.
    static func storeText(_ text: String) -> String? {
        guard text.count > 4096 else { return nil }
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let url = baseDir().appendingPathComponent("txt-\(stamp).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch { return nil }
    }

    private static func thumbnailPNG(from data: Data, maxPixel: CGFloat) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: CFDictionary = [
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }
}

/// Vision OCR for a stored image payload path. Returns recognized text or nil.
enum ClipboardOCR {
    static func recognizeText(atPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return recognizeText(data: data)
    }

    static func recognizeText(data: Data) -> String? {
        guard let cg = cgImage(from: data) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch { return nil }
        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
