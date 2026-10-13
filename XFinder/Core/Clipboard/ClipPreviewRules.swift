import Foundation
import CoreGraphics
import UniformTypeIdentifiers

/// What a clipboard card may decode for a preview, and how a source app's accent colour is picked from its icon.
/// Pure so the two rules that cost hundreds of MB when wrong are tested.
///
/// Measured 2026-10-13 with `MallocStackLogging=full` + `malloc_history -highWaterMark` on the Clipboard Library page
/// (second visit: footprint 646 MB, peak 886 MB, 2.1 GB allocated in total):
///   * `ClipboardAppColor.extractDominantColor` called `NSImage.tiffRepresentation` on the app icon — every
///     representation up to 1024 px @2x rendered into one uncompressed TIFF, ≈ 74 MB per source app (3 live at peak).
///   * `ClipboardClassifier.resolveCandidateImage` called `NSImage(contentsOfFile:)` on a copied 42 008 051-byte .mp4
///     — twice per render (payload path, then `metadata["path"]`), plus 67 MB for AppKit's SVG sniff — only to learn
///     it was not an image.
enum ClipPreviewRules {

    /// Only a path whose extension names an image type may be handed to an image decoder.
    static func isImageFile(_ path: String) -> Bool { previewKind(path) == .image }

    enum PreviewKind: Equatable { case image, pdf, none }

    /// How a copied file may be previewed, decided by its extension alone — never by reading it. PDF is its own
    /// kind: `NSImage(contentsOfFile:)` used to open a PDF as `NSPDFImageRep` and show page 1, and ImageIO cannot,
    /// so a PDF gets `pdfFirstPage` instead of silently losing its preview.
    static func previewKind(_ path: String) -> PreviewKind {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .none }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        return .none
    }

    /// Page 1 of a PDF drawn at most `maxPixel` on the long side, white behind it (pages are transparent). Nil for
    /// a missing, unreadable or still-locked (encrypted) document. Draws only the one page, so a 1 MB statement
    /// costs a ≤ 480 px bitmap, not the document.
    static func pdfFirstPage(atPath path: String, maxPixel: Int = 480) -> CGImage? {
        guard maxPixel > 0, let doc = CGPDFDocument(URL(fileURLWithPath: path) as CFURL),
              !doc.isEncrypted || doc.isUnlocked, let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let turned = page.rotationAngle % 180 != 0
        let (pw, ph) = turned ? (box.height, box.width) : (box.width, box.height)
        let scale = min(1, Double(maxPixel) / Double(max(pw, ph)))
        let w = max(1, Int((Double(pw) * scale).rounded())), h = max(1, Int((Double(ph) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let target = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(target)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    /// The icon is drawn at this size for the accent colour: 32 × 32 × 4 bytes = 4 KB.
    static let iconSampleSide = 32

    /// Most vivid colour of an RGBA8 bitmap with PREMULTIPLIED alpha last (what a `CGContext` with
    /// `premultipliedLast` produces). Same scoring as the old TIFF path: skip pixels under 50 % alpha, keep mid
    /// lightness (0.18…0.85) and saturation above 0.20, score = saturation × 1.6 + closeness to mid lightness.
    /// `bytesPerRow` may exceed `width * 4` (CoreGraphics pads rows); padding bytes are never read.
    static func dominantColor(rgba: [UInt8], width: Int, height: Int, bytesPerRow: Int? = nil) -> (r: Double, g: Double, b: Double)? {
        let row = bytesPerRow ?? width * 4
        guard width > 0, height > 0, row >= width * 4, rgba.count >= row * (height - 1) + width * 4 else { return nil }
        var best: (r: Double, g: Double, b: Double)?
        var maxScore = -1.0
        for y in 0..<height {
            for x in 0..<width {
                let i = y * row + x * 4
                let a = Double(rgba[i + 3]) / 255
                if a < 0.5 { continue }
                // Un-premultiply: a premultiplied channel is colour × alpha.
                let r = min(1, Double(rgba[i]) / 255 / a)
                let g = min(1, Double(rgba[i + 1]) / 255 / a)
                let b = min(1, Double(rgba[i + 2]) / 255 / a)
                let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
                let sat = maxC > 0.001 ? (maxC - minC) / maxC : 0
                let light = (maxC + minC) / 2
                guard light > 0.18, light < 0.85, sat > 0.20 else { continue }
                let score = sat * 1.6 + (0.5 - abs(light - 0.5))
                if score > maxScore { maxScore = score; best = (r, g, b) }
            }
        }
        return best
    }
}
