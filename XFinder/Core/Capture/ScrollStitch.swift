import Foundation
import CoreGraphics
import ImageIO

/// XF-T26 — the pure half of scrolling capture (symlinked into the test package): what changed between two captures of
/// the same screen area, by how many rows the content moved, which rows are pinned (a sticky header or footer), and which
/// rows of each capture make up the final long image. The session (`ScrollCaptureController`) only captures, scrolls and
/// draws what this decides.
///
/// Job: *"capture a whole web page, chat or long list as ONE image instead of ten screenshots stitched by hand."*
enum ScrollStitch {

    // MARK: Row signatures

    /// Samples taken across each row. The outer 4 % on the left and 8 % on the right are skipped: an overlay scroll bar
    /// appears and moves at the right edge exactly while scrolling, and would make every row look different.
    static let samples = 64
    /// A row is "informative" when its samples span at least this many levels (of 64): a blank or flat row matches
    /// anything and must never count as evidence of a shift.
    static let informativeSpan: UInt8 = 6
    /// Two rows are the same when their samples differ by at most this much on average (of 64 levels) — anti-aliasing and
    /// colour noise, not content.
    static let rowTolerancePerSample = 2

    struct Frame: Equatable {
        var width: Int
        var height: Int
        /// `height × samples` quantised luminance values, row-major.
        var values: [UInt8]
        var informative: [Bool]

        func row(_ r: Int) -> ArraySlice<UInt8> { values[(r * samples)..<((r + 1) * samples)] }
    }

    /// Signature of one captured area. `pixels` is 8-bit RGBA (any alpha placement — alpha is ignored), `bytesPerRow`
    /// as the bitmap was laid out.
    static func frame(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> Frame {
        precondition(width > 0 && height > 0 && pixels.count >= bytesPerRow * height)
        let left = width * 4 / 100, right = width - width * 8 / 100
        let span = max(right - left, 1)
        var values = [UInt8](repeating: 0, count: height * samples)
        var informative = [Bool](repeating: false, count: height)
        for y in 0..<height {
            var lo: UInt8 = 255, hi: UInt8 = 0
            let base = y * bytesPerRow
            for i in 0..<samples {
                let x = left + (i * span) / samples
                let p = base + x * 4
                let r = Int(pixels[p]), g = Int(pixels[p + 1]), b = Int(pixels[p + 2])
                let lum = UInt8(((r * 77 + g * 150 + b * 29) >> 8) >> 2)     // 0…63
                values[y * samples + i] = lum
                lo = min(lo, lum); hi = max(hi, lum)
            }
            informative[y] = hi - lo >= informativeSpan
        }
        return Frame(width: width, height: height, values: values, informative: informative)
    }

    static func rowsMatch(_ a: Frame, _ ra: Int, _ b: Frame, _ rb: Int) -> Bool {
        var total = 0
        let limit = rowTolerancePerSample * samples
        let ba = ra * samples, bb = rb * samples
        for i in 0..<samples {
            total += abs(Int(a.values[ba + i]) - Int(b.values[bb + i]))
            if total > limit { return false }
        }
        return true
    }

    // MARK: Pixels from ScreenCaptureKit

    /// ScreenCaptureKit's BGRA rows (`bytesPerRow` may be padded: 6528 for a 1628 px row, measured) as packed RGBA.
    ///
    /// Why not draw the capture into an RGBA context: measured 2026-10-23, every `CGContext.draw` of a ScreenCaptureKit
    /// image left a full-size converted copy in CoreGraphics' caches — 30 captures, 30 live 10 MB blocks; one scrolling
    /// capture left 12 (118 MB) in the installed app. Asking ScreenCaptureKit for sRGB and copying the bytes gives the
    /// same pixels (0 bytes differ from the drawn copy) and leaves nothing behind (probe `scratchpad/scmem/probe.swift`).
    static func rgba(fromBGRA src: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int) -> [UInt8]? {
        guard width > 0, height > 0, bytesPerRow >= width * 4, src.count >= bytesPerRow * (height - 1) + width * 4 else { return nil }
        let out = width * 4
        var pixels = [UInt8](repeating: 0, count: out * height)
        pixels.withUnsafeMutableBufferPointer { dst in
            for y in 0..<height {
                let s = y * bytesPerRow, d = y * out
                for x in 0..<width {
                    let i = s + x * 4, o = d + x * 4
                    dst[o] = src[i + 2]; dst[o + 1] = src[i + 1]; dst[o + 2] = src[i]; dst[o + 3] = src[i + 3]
                }
            }
        }
        return pixels
    }

    // MARK: Comparing two captures

    struct Match: Equatable {
        /// Rows the content moved up between the two captures (> 0).
        var shift: Int
        /// Pinned rows at the top and bottom (sticky header / footer), identical at the same place in both.
        var top: Int
        var bottom: Int
    }

    enum Outcome: Equatable {
        /// Nothing new (the page did not move, or only a caret blinked).
        case same
        case moved(Match)
        /// No shift explains the new capture: scrolled too far at once, scrolled up, or the area changed.
        case lost
    }

    /// Below this share of informative rows agreeing, a candidate shift is rejected.
    static let minimumAgreement = 0.95
    /// A shift needs at least this many informative rows in the overlap to be believed.
    static let minimumEvidence = 8

    static func compare(_ a: Frame, _ b: Frame) -> Outcome {
        guard a.width == b.width, a.height == b.height else { return .lost }
        let h = a.height
        // Unchanged (or nearly: a blinking caret, a spinner) — nothing to add.
        if agreement(a, b, shift: 0, top: 0, bottom: 0) ?? 1 >= 0.98 { return .same }
        // Pinned bands: identical rows at the same place, from each edge, at most a third of the height each.
        var top = 0
        while top < h / 3, rowsMatch(a, top, b, top) { top += 1 }
        var bottom = 0
        while bottom < h / 3, rowsMatch(a, h - 1 - bottom, b, h - 1 - bottom) { bottom += 1 }
        let body = h - top - bottom
        guard body > minimumEvidence else { return .lost }
        var best: (shift: Int, score: Double)?
        for d in 1..<(body - minimumEvidence + 1) {
            guard let score = agreement(a, b, shift: d, top: top, bottom: bottom), score >= minimumAgreement else { continue }
            if best == nil || score > best!.score { best = (d, score) }
            if score == 1 { break }     // an exact fit: smaller shifts were already tried, larger ones cannot do better
        }
        guard let best else { return .lost }
        return .moved(Match(shift: best.shift, top: top, bottom: bottom))
    }

    /// Share of the informative rows of `b`'s body that equal the rows of `a` `shift` rows lower; nil when the overlap has
    /// fewer than `minimumEvidence` informative rows. Early exit once the share can no longer reach `minimumAgreement`.
    static func agreement(_ a: Frame, _ b: Frame, shift: Int, top: Int, bottom: Int) -> Double? {
        let end = a.height - bottom - shift
        guard end > top else { return nil }
        var considered = 0, failed = 0
        let informativeTotal = (top..<end).reduce(0) { $0 + (b.informative[$1] ? 1 : 0) }
        guard informativeTotal >= minimumEvidence else { return nil }
        let allowed = Int(Double(informativeTotal) * (1 - minimumAgreement))
        for r in top..<end where b.informative[r] {
            considered += 1
            if !rowsMatch(a, r + shift, b, r) {
                failed += 1
                if failed > allowed, shift != 0 { return 0 }
            }
        }
        return considered == 0 ? nil : Double(considered - failed) / Double(considered)
    }

    // MARK: Assembling the long image

    /// What to do with the rows of a new capture. Rows are indices into that capture.
    struct Step: Equatable {
        /// Drop this many rows from the end of the image so far (the previous pinned footer).
        var dropFooter: Int
        /// Append these rows of the new capture (new content).
        var append: Range<Int>
        /// Then append these rows as the new pinned footer.
        var footer: Range<Int>
    }

    /// The running assembly: the first capture is taken whole; each match then replaces the footer with the new content
    /// rows and the new footer.
    struct Assembly: Equatable {
        var height: Int = 0
        var footer: Int = 0
        var steps: [Step] = []

        init(first: Frame) {
            height = first.height
            steps = [Step(dropFooter: 0, append: 0..<first.height, footer: first.height..<first.height)]
        }

        /// The rows `next` adds after `match`. Content row `h - footer` of the previous capture is row
        /// `h - footer - shift` of the next one; everything from there down to the next capture's own footer is new.
        mutating func add(_ match: Match, frameHeight h: Int) -> Step {
            // The first capture went in whole, footer rows included — as many as this first match finds pinned. After
            // that the image ends with exactly the footer the previous step appended.
            let prevFooter = steps.count == 1 ? match.bottom : footer
            let start = max(h - prevFooter - match.shift, match.top)
            let end = h - match.bottom
            let step = Step(dropFooter: prevFooter, append: start..<max(start, end), footer: (h - match.bottom)..<h)
            height += -prevFooter + step.append.count + step.footer.count
            footer = match.bottom
            steps.append(step)
            return step
        }
    }

    // MARK: The session's decisions

    /// Height cap of the long image, in pixels (spec §2.5; re-measured by T-T26-5).
    static let heightLimit = 20_000
    /// Smallest area worth scrolling, in points (the reference app's limit).
    static let minimumSide = 48.0

    static func isLargeEnough(width: Double, height: Double) -> Bool { width >= minimumSide && height >= minimumSide }

    /// One auto-scroll step, in points: 60 % of the area between the pinned bands, never less than 40 pt — enough overlap
    /// for the next comparison to find its place.
    static func autoScrollStep(areaHeightPoints: Double, pinnedPoints: Double) -> Double {
        max(40, (areaHeightPoints - pinnedPoints) * 0.6)
    }

    /// Auto-scroll stops after this many scrolls in a row that change nothing ("reached the end of the page").
    static let unchangedScrollsToStop = 3
    /// `eventSourceUserData` of the auto-scroll events ("XFSCAP"), so no tap of ours treats them as the person's.
    static let autoScrollTag: Int64 = 0x584653434150

    // MARK: Files

    /// One strip on disk. PNG with the screen's DPI, which the editor and the pin window read the point size from.
    @discardableResult
    static func writePNG(_ image: CGImage?, to url: URL, scale: Double) -> Bool {
        guard let image, let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
        let dpi = 72 * max(scale, 1)
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    /// What the Vision child needs to build the long image: the strips top to bottom and where to write it.
    struct Manifest: Codable, Equatable {
        var strips: [String]
        var output: String
        var scale: Double
    }

    /// Stack the strips into one PNG. Strips narrower than the first are left-aligned; nothing is scaled.
    static func compose(_ manifest: Manifest) -> Bool {
        let images = manifest.strips.compactMap { path -> CGImage? in
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        guard images.count == manifest.strips.count, let width = images.first?.width else { return false }
        let height = images.reduce(0) { $0 + $1.height }
        guard height > 0, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        var y = height
        for image in images {
            y -= image.height                                  // CoreGraphics: origin at the bottom
            ctx.draw(image, in: CGRect(x: 0, y: y, width: image.width, height: image.height))
        }
        return writePNG(ctx.makeImage(), to: URL(fileURLWithPath: manifest.output), scale: manifest.scale)
    }

    /// In the Vision child when it can run — the long bitmap's memory then leaves with it — else here.
    static func composeInChild(strips: [URL], output: URL, scale: Double) -> Bool {
        let manifest = Manifest(strips: strips.map(\.path), output: output.path, scale: scale)
        if VisionChild.isAvailable, let data = try? JSONEncoder().encode(manifest),
           // A tall image takes longer to decode and draw than one OCR: two minutes before the in-process fallback.
           let reply = VisionChild.run(.stitch, imageData: data, timeout: 120), reply.status == VisionChild.Status.ok,
           FileManager.default.fileExists(atPath: output.path) {
            return true
        }
        return compose(manifest)
    }
}
