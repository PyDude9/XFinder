import Foundation
import ImageIO
import CoreGraphics
import PDFKit
import AppKit
import Vision

/// `XFinder --vision <job>`: the app binary as its own short-lived Vision worker. The image's bytes arrive on stdin, the
/// answer goes to stdout, the exit status says what happened (`Status`). Decided in `XFinderApp.init` before any scene or
/// AppKit object exists, like `--mcp`; `main` never returns.
///
/// Why a child (2026-10-21): the first Vision request in a process takes its footprint from ~10 MB to 106–150 MB and keeps
/// +21 MB (`.fast` text), +29 MB (foreground mask) or +54 MB (`.accurate` text) for good — `malloc_zone_pressure_relief`
/// frees nothing, 60 s of idling changes nothing (probes `scratchpad/ocrmem`). The clipboard reads the text of every copied
/// image, so a few screenshots took the installed app from 43 MB to 125 MB (peak 170 MB). A whole child run costs 0.1 s
/// (`.fast`) / 0.2 s (`.accurate`, cutout) and its memory is the system's again when it exits.
enum VisionChild {
    static let flag = "--vision"

    enum Job: String, CaseIterable {
        case ocrFast = "ocr-fast", ocrAccurate = "ocr-accurate", cutout
        /// XF-T26: stdin is a `ScrollStitch.Manifest` (JSON), the child writes the long image itself.
        case stitch
        /// XF-T30 W5a — content index extraction jobs. stdin is the raw file BYTES (never a path: rule 9, NFD
        /// argv). stdout is UTF-8 text capped at `SearchIndexRules.storedCharacterCap`; PDFKit and Vision OCR both
        /// run only here (Vision-memory rule, CLAUDE.md §7 2026-10-21).
        case textPDF = "text-pdf", textRich = "text-rich", ocrIndex = "ocr-index"
    }

    /// The child's exit statuses. Anything else (a kill, a crash) is "no answer": the parent does the work itself.
    enum Status {
        static let ok: Int32 = 0
        static let notAnImage: Int32 = 2
        static let noSubject: Int32 = 3
        static let visionFailed: Int32 = 4
        /// `text-pdf`/`ocr-index`: the text was there but got cut at a cap (page count, character count). Still
        /// `stdout` has usable text — this is a status, not a failure.
        static let truncated: Int32 = 5
        static let usage: Int32 = 64
    }

    /// Only the app can be its own child: under `swift test` the executable is the test runner, which must never be
    /// started with `--vision`.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier == "com.xfinder.app" && Bundle.main.executableURL != nil }

    /// One child at a time: three screenshots copied in a row would otherwise be three ~100 MB processes at once.
    private static let oneAtATime = NSLock()

    /// The word after `--vision`; nil for anything else, so a typo is a usage error, not a silent default.
    static func job(fromArguments args: [String]) -> Job? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return Job(rawValue: args[i + 1])
    }

    /// An uncompressed TIFF: encoding a full-screen PNG costs more than the recognition saves.
    static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.tiff" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Upright (EXIF orientation applied) and at most `maxPixels` on the long side — the cap the cutout always had.
    /// Decoding happens HERE, in the child: the app sends a file's bytes as they are. Measured 2026-10-21: when the app
    /// decoded a large photo and re-encoded it as TIFF before handing it over, its own footprint peaked at 813 MB and
    /// settled at 162 MB (freed malloc pages that stay dirty), although Vision itself never ran in it.
    static let maxPixels = 8192

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let longest = max(props?[kCGImagePropertyPixelWidth] as? Int ?? 0, props?[kCGImagePropertyPixelHeight] as? Int ?? 0, 1)
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longest, maxPixels),
        ] as CFDictionary)
    }

    /// A file's bytes without copying them into the heap first (mapped when the file system allows it).
    static func fileBytes(_ url: URL) -> Data? { try? Data(contentsOf: url, options: .mappedIfSafe) }

    /// The child. Never returns.
    static func main() -> Never {
        guard let job = job(fromArguments: CommandLine.arguments) else { exit(Status.usage) }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        switch job {
        case .stitch:
            guard let manifest = try? JSONDecoder().decode(ScrollStitch.Manifest.self, from: input) else { exit(Status.usage) }
            exit(ScrollStitch.compose(manifest) ? Status.ok : Status.visionFailed)

        case .textPDF:
            exit(extractPDFText(input))

        case .textRich:
            exit(extractRichText(input))

        case .ocrIndex:
            exit(extractOCRIndexText(input))

        case .ocrFast, .ocrAccurate, .cutout:
            guard let image = decode(input) else { exit(Status.notAnImage) }
            switch job {
            case .ocrFast, .ocrAccurate:
                let lines = ScreenTextRecognizer.recognizeHere(image, level: job == .ocrFast ? .fast : .accurate)
                FileHandle.standardOutput.write(OCRWire.encode(lines))
                exit(Status.ok)
            case .cutout:
                switch ImageRunner.cutoutHere(image, name: "stdin") {
                case .success(let png):
                    FileHandle.standardOutput.write(png)
                    exit(Status.ok)
                case .failure(.noSubject):
                    exit(Status.noSubject)
                case .failure:
                    exit(Status.visionFailed)
                }
            default:
                exit(Status.usage)  // unreachable: outer switch already narrowed to these three
            }
        }
    }

    /// `text-pdf`: PDFKit's text layer, at most `SearchIndexRules.pdfPageCap` pages (the caller already enforced
    /// the 64 MiB file-size cap before spawning this job — `PDFDocument(data:)` would otherwise hold the whole
    /// thing regardless). Output capped at `storedCharacterCap` UTF-8 characters.
    private static func extractPDFText(_ data: Data) -> Int32 {
        guard looksLikePDF(data), let doc = PDFDocument(data: data) else { return Status.notAnImage }
        let pageCount = doc.pageCount
        guard pageCount > 0 else { return Status.noSubject }
        let pagesToRead = min(pageCount, SearchIndexRules.pdfPageCap)
        var text = ""
        for i in 0..<pagesToRead {
            if let pageText = doc.page(at: i)?.string, !pageText.isEmpty {
                if !text.isEmpty { text += "\n" }
                text += pageText
            }
            if text.count > SearchIndexRules.storedCharacterCap { break }
        }
        var truncated = pagesToRead < pageCount
        if text.count > SearchIndexRules.storedCharacterCap {
            text = String(text.prefix(SearchIndexRules.storedCharacterCap))
            truncated = true
        }
        guard !text.isEmpty else { return Status.noSubject }
        FileHandle.standardOutput.write(Data(text.utf8))
        return truncated ? Status.truncated : Status.ok
    }

    /// `text-rich`: rtf/rtfd/doc/docx/odt/html via `NSAttributedString`'s document importers — no network, no
    /// external process. The extension decides which importer to try: `.html`'s importer accepts almost any byte
    /// stream as "plain text content" (measured: a garbage file with no markup at all imports "successfully"), so
    /// it is never used as a blind-guess fallback — only when the caller's own extension says the file IS html.
    private static func extractRichText(_ data: Data) -> Int32 {
        guard let ext = richTextExtensionHint, let docType = richTextDocumentType(forExtension: ext) else {
            return attemptEveryRichTextFormat(data)
        }
        guard let attr = try? NSAttributedString(data: data, options: [.documentType: docType], documentAttributes: nil) else {
            return attemptEveryRichTextFormat(data)
        }
        return writeRichText(attr.string)
    }

    /// Set by the parent via an extra argument (`--vision text-rich .docx`) — the bytes alone do not say which
    /// rich-text format they are.
    private static var richTextExtensionHint: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: Job.textRich.rawValue), i + 1 < args.count else { return nil }
        return args[i + 1].hasPrefix(".") ? String(args[i + 1].dropFirst()).lowercased() : nil
    }

    private static func richTextDocumentType(forExtension ext: String) -> NSAttributedString.DocumentType? {
        switch ext {
        case "rtf", "rtfd": return .rtf
        case "doc": return .docFormat
        case "docx": return .officeOpenXML
        case "odt": return .openDocument
        case "html", "htm": return .html
        default: return nil
        }
    }

    /// No usable extension hint, or the hinted importer failed: try the formats that only succeed on bytes that
    /// are actually structured that way (`.html` excluded — see `extractRichText`'s doc comment).
    private static func attemptEveryRichTextFormat(_ data: Data) -> Int32 {
        for docType: NSAttributedString.DocumentType in [.rtf, .officeOpenXML, .docFormat, .openDocument] {
            if let attr = try? NSAttributedString(data: data, options: [.documentType: docType], documentAttributes: nil) {
                return writeRichText(attr.string)
            }
        }
        return Status.notAnImage
    }

    private static func writeRichText(_ string: String) -> Int32 {
        var text = string
        var truncated = false
        if text.count > SearchIndexRules.storedCharacterCap {
            text = String(text.prefix(SearchIndexRules.storedCharacterCap))
            truncated = true
        }
        guard !text.isEmpty else { return Status.noSubject }
        FileHandle.standardOutput.write(Data(text.utf8))
        return truncated ? Status.truncated : Status.ok
    }

    /// `%PDF` magic bytes: checked before handing data to `PDFDocument(data:)` so a plain image never makes
    /// CoreGraphics log a parse error to stderr for bytes that were never going to be a PDF.
    private static func looksLikePDF(_ data: Data) -> Bool {
        data.starts(with: Array("%PDF".utf8))
    }

    /// `ocr-index`: `.accurate` OCR for an image, or for a SCANNED pdf (no text layer) rendered page-by-page, at
    /// most `SearchIndexRules.scannedPDFPageCap` pages — a smaller cap than `text-pdf`'s because rendering +
    /// recognizing a page costs much more than reading its text layer.
    private static func extractOCRIndexText(_ data: Data) -> Int32 {
        if looksLikePDF(data), let doc = PDFDocument(data: data), doc.pageCount > 0 {
            return ocrScannedPDF(doc)
        }
        guard let image = decode(data) else { return Status.notAnImage }
        let lines = ScreenTextRecognizer.recognizeHere(image, level: .accurate)
        return writeRichText(lines.map(\.text).joined(separator: "\n"))
    }

    private static func ocrScannedPDF(_ doc: PDFDocument) -> Int32 {
        let pageCount = doc.pageCount
        let pagesToRead = min(pageCount, SearchIndexRules.scannedPDFPageCap)
        var text = ""
        for i in 0..<pagesToRead {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let scale: CGFloat = 2  // ~144 dpi: enough for OCR, far cheaper than a 4x render
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let cgImage = renderPDFPage(page, size: size, scale: scale) else { continue }
            let lines = ScreenTextRecognizer.recognizeHere(cgImage, level: .accurate)
            let pageText = lines.map(\.text).joined(separator: "\n")
            if !pageText.isEmpty {
                if !text.isEmpty { text += "\n" }
                text += pageText
            }
            if text.count > SearchIndexRules.storedCharacterCap { break }
        }
        var truncated = pagesToRead < pageCount
        if text.count > SearchIndexRules.storedCharacterCap {
            text = String(text.prefix(SearchIndexRules.storedCharacterCap))
            truncated = true
        }
        guard !text.isEmpty else { return Status.noSubject }
        FileHandle.standardOutput.write(Data(text.utf8))
        return truncated ? Status.truncated : Status.ok
    }

    private static func renderPDFPage(_ page: PDFPage, size: CGSize, scale: CGFloat) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                   bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// The parent: the child's exit status and stdout, or nil when it could not start, was killed, or crashed.
    /// `extensionHint` (e.g. `"docx"`) is only consulted by `.textRich` — the bytes alone do not say which rich-text
    /// format they are; every other job ignores it. Passed as an argv word (never the file's path — rule 9, NFD),
    /// so plain ASCII only (an extension always is).
    static func run(_ job: Job, imageData: Data, timeout: TimeInterval = 30, extensionHint: String? = nil) -> (status: Int32, output: Data)? {
        guard let exe = Bundle.main.executableURL else { return nil }
        oneAtATime.lock()
        defer { oneAtATime.unlock() }
        let p = Process()
        p.executableURL = exe
        p.arguments = [flag, job.rawValue]
        if job == .textRich, let ext = extensionHint { p.arguments?.append("." + ext) }
        let inPipe = Pipe(), out = Pipe()
        p.standardInput = inPipe
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        // A stuck child must not hold the next one forever: measured ≤ 0.2 s warm; the very first run after a build waited
        // on the Neural Engine daemon once for > 15 s.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        // F_SETNOSIGPIPE: a child that dies before reading its stdin must not take XFinder down with SIGPIPE. The child reads
        // all of stdin before it writes a byte, so writing first and reading after cannot deadlock.
        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? inPipe.fileHandleForWriting.write(contentsOf: imageData)
        try? inPipe.fileHandleForWriting.close()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationReason == .exit else { return nil }
        return (p.terminationStatus, outData)
    }
}
