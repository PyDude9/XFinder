import AppKit

/// Disk offload (payloads under Application Support; images go through `ClipboardImageStore`) and
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

    /// File-name stamp of one copied item (milliseconds since 1970).
    static func stamp() -> String { String(Int(Date().timeIntervalSince1970 * 1000)) }

    /// SVG, which ImageIO does not read: drawn by AppKit straight at thumbnail size (a vector image has no large
    /// bitmap to decode). Size is the document's own, in points.
    @MainActor
    static func storeSVGThumbnail(ofFile url: URL) -> ClipboardImageStore.Stored? {
        guard url.pathExtension.lowercased() == "svg", let image = NSImage(contentsOf: url),
              image.size.width > 0, image.size.height > 0 else { return nil }
        let side = CGFloat(ClipboardImageStore.thumbnailPixels)
        let scale = min(side / image.size.width, side / image.size.height, 1)
        let w = max(1, Int((image.size.width * scale).rounded())), h = max(1, Int((image.size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        let thumb = baseDir().appendingPathComponent("thumb-\(stamp()).png")
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: thumb)) != nil else { return nil }
        return ClipboardImageStore.Stored(payload: nil, thumb: thumb.path,
                                          width: Int(image.size.width.rounded()), height: Int(image.size.height.rounded()))
    }

    /// Write raw text payload (>4KB snippets) so history stays light in RAM.
    static func storeText(_ text: String) -> String? {
        guard ClipboardText.needsPayload(text) else { return nil }
        let url = baseDir().appendingPathComponent("txt-\(stamp()).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch { return nil }
    }
}

/// Vision OCR for a stored image payload path. Returns recognized text or nil. `.fast` — it feeds the search index —
/// and in a short-lived child process (`ScreenTextRecognizer`), so a copied screenshot no longer leaves Vision's tens of
/// megabytes in the app.
enum ClipboardOCR {
    static func recognizeText(atPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let data = VisionChild.fileBytes(url) else { return nil }
        return recognizeText(data: data)
    }

    static func recognizeText(data: Data) -> String? {
        guard let lines = ScreenTextRecognizer.recognize(imageData: data, level: .fast) else { return nil }
        let joined = lines.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
