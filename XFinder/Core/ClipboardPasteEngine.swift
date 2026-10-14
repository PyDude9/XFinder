import AppKit
import Foundation
import Observation
import SwiftUI

/// Paste-via-keystroke engine (PasteApp behavior): writes a record's content to
/// the general pasteboard, fronts the previously-active app, and synthesizes
/// ⌘V (or plain-text paste) via CGEvent. Requires Accessibility trust —
/// callers gate on `WindowManager.isTrusted` and show the grant flow otherwise.
enum ClipboardPasteEngine {

    /// Activate `pid` then synthesize ⌘V after a short settle delay.
    @discardableResult
    static func paste(record: ClipboardRecord, to pid: pid_t?, plainText: Bool = false) -> Bool {
        guard !record.isLocked else { return false }   // D4: a sealed row has nothing a user wants pasted — only ciphertext
        guard WindowManager.isTrusted else { return false }
        guard writeToPasteboard(record: record, plainText: plainText) else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        guard let targetPID = pid, targetPID != mine else {
            // No external target: content copied to clipboard; skip ⌘V synthesis
            // to avoid pasting recursively into XFinder itself.
            ClipboardSounds.playPaste()
            return true
        }
        if let app = NSRunningApplication(processIdentifier: targetPID) {
            app.activate(options: [.activateAllWindows])
        }
        // Let the target app front before the keystroke lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            synthesizeCommandV()
        }
        ClipboardSounds.playPaste()
        return true
    }

    /// Write record content to the pasteboard without pasting (copy-back).
    @discardableResult
    static func writeToPasteboard(record: ClipboardRecord, plainText: Bool = false) -> Bool {
        guard !record.isLocked else { return false }   // D4: never hand the sealed .env out as a file or text
        let pb = NSPasteboard.general
        // Tell the monitor this change is ours, after the writes below have bumped changeCount.
        // Link cleaning must never rewrite the pasteboard during a paste (see OwnWriteMark).
        defer { OwnWriteMark.shared.record(pb.changeCount) }
        pb.clearContents()
        switch record.type {
        case .text, .code, .markdown, .color, .merged:
            // The WHOLE text — the snippet is a 200-character preview (see ClipboardText).
            guard let s = ClipboardText.fullText(snippet: record.textSnippet, payloadPath: record.payloadPath) ?? record.ocrText
            else { return false }
            return pb.setString(s, forType: .string)
        case .link:
            let url = record.metadata["url"] ?? record.textSnippet ?? ""
            guard !url.isEmpty else { return false }
            pb.setString(plainText ? url : url, forType: .string)
            if !plainText, let u = URL(string: url) {
                pb.writeObjects([u as NSURL])
            }
            return true
        case .file:
            guard let path = record.payloadPath ?? record.metadata["path"],
                  FileManager.default.fileExists(atPath: path) else { return false }
            return pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
        case .image:
            if plainText, let ocr = record.ocrText, !ocr.isEmpty {
                return pb.setString(ocr, forType: .string)
            }
            if let path = record.payloadPath ?? record.thumbnailPath,
               let img = NSImage(contentsOfFile: path) {
                pb.writeObjects([img])
                return true
            }
            return false
        }
    }

    // MARK: - D4 "Bảng khoá" — pasting an in-memory unlocked clip

    /// Same shape as `writeToPasteboard(record:plainText:)`, but the content never touched disk as
    /// plaintext: it comes from `BoardLock.UnlockedClip`, which `ClipboardLibraryStore.unlock(_:)`
    /// produced by opening the Secure Enclave key (Touch ID) and decrypting in memory only.
    @discardableResult
    static func writeToPasteboard(unlocked: BoardLock.UnlockedClip, plainText: Bool = false) -> Bool {
        let pb = NSPasteboard.general
        defer { OwnWriteMark.shared.record(pb.changeCount) }
        pb.clearContents()
        let record = unlocked.record
        switch record.type {
        case .text, .code, .markdown, .merged:
            let s: String?
            if let data = unlocked.payloadData, let fromPayload = String(data: data, encoding: .utf8) {
                s = fromPayload
            } else {
                s = record.textSnippet
            }
            guard let text = s else { return false }
            return pb.setString(text, forType: .string)
        case .color:
            guard let s = record.textSnippet else { return false }
            return pb.setString(s, forType: .string)
        case .link:
            let url = record.metadata["url"] ?? record.textSnippet ?? ""
            guard !url.isEmpty else { return false }
            pb.setString(url, forType: .string)
            if !plainText, let u = URL(string: url) {
                pb.writeObjects([u as NSURL])
            }
            return true
        case .file:
            // The locked row never kept a real path on disk (that was the whole point); offer the
            // original file name back as text, which is all an unlock-in-memory can honestly restore.
            guard let name = unlocked.originalPayloadFileName ?? record.metadata["path"] else { return false }
            return pb.setString(name, forType: .string)
        case .image:
            if plainText, let ocr = record.ocrText, !ocr.isEmpty {
                return pb.setString(ocr, forType: .string)
            }
            guard let data = unlocked.payloadData ?? unlocked.thumbnailData,
                  let img = NSImage(data: data) else { return false }
            pb.writeObjects([img])
            return true
        }
    }

    /// Same shape as `paste(record:to:plainText:)`: activates `pid`, lets it settle, then synthesizes
    /// ⌘V — but writes the pasteboard from an `UnlockedClip`'s in-memory bytes, never from a sealed
    /// row's (absent) plain fields.
    @discardableResult
    static func paste(unlocked: BoardLock.UnlockedClip, to pid: pid_t?, plainText: Bool = false) -> Bool {
        guard WindowManager.isTrusted else { return false }
        guard writeToPasteboard(unlocked: unlocked, plainText: plainText) else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        guard let targetPID = pid, targetPID != mine else {
            ClipboardSounds.playPaste()
            return true
        }
        if let app = NSRunningApplication(processIdentifier: targetPID) {
            app.activate(options: [.activateAllWindows])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            synthesizeCommandV()
        }
        ClipboardSounds.playPaste()
        return true
    }

    private static func synthesizeCommandV() {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// Paste Stack: items pasted one per ⌘V, in order. The queue itself is the pure, tested
/// `PasteQueue` (Core/Clipboard); the consumer is `ClipboardManager.pasteNextFromStack()`.
typealias PasteStack = PasteQueue<ClipboardRecord>

/// Subtle paste/copy sounds via system sounds (Tink/Pop) + haptics where available.
enum ClipboardSounds {
    /// Read the preference directly, not via `@AppStorage`. A `static var`
    /// property wrapper is global mutable state (an error under Swift 6
    /// strict concurrency), and `@AppStorage` is SwiftUI view state that has
    /// no business being touched from a background thread.
    private static var soundsOn: Bool {
        UserDefaults.standard.object(forKey: "clipboard.sounds") as? Bool ?? true
    }

    static func playPaste() {
        guard soundsOn else { return }
        NSSound(named: "Tink")?.play()
    }

    /// D1 #16 — the ONE reader of `clipboard.copySound`. System sound names; "Pop" is what shipped before.
    static let copySoundChoices = ["Pop", "Tink", "Glass", "Purr", "Blow", "Frog"]
    private static var copySoundName: String {
        UserDefaults.standard.string(forKey: "clipboard.copySound") ?? "Pop"
    }

    /// The ONE reader of `clipboard.cardHaptic`: a light tap each time a different card becomes the first one of a deck
    /// while it scrolls (owner, 2026-10-14: "phản hồi rung khi lướt switch giữa các thẻ clipboard như OneNotch"). Only a
    /// Force Touch trackpad can play it, and it is felt only under a finger — a mouse wheel or the arrow keys move the
    /// deck without anything to feel.
    private static var cardHapticOn: Bool {
        UserDefaults.standard.object(forKey: "clipboard.cardHaptic") as? Bool ?? true
    }

    static func cardTick() {
        guard cardHapticOn else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A tap only when the deck moved from one of its cards to another — not when it first appears (old nil), nor when
    /// a filter replaced the list (the old card is no longer in it).
    static func tickIfCardChanged<ID: Equatable>(from old: ID?, to new: ID?, in ids: [ID]) {
        guard NotchClipboardRules.cardChanged(from: old, to: new, in: ids) else { return }
        cardTick()
    }

    static func playCopy() {
        guard soundsOn else { return }
        NSSound(named: NSSound.Name(copySoundName))?.play()
        if #available(macOS 12.0, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}

/// App-icon accent helper: icon of the source app for card headers. Main-actor: every caller is a view, and
/// the cache below is per-process state SwiftUI reads during layout.
@MainActor
enum ClipboardAppIcon {
    /// One LaunchServices lookup + one icon render per bundle id per process. Measured 2026-10-12: the notch
    /// deck asked for every visible card's icon on EVERY SwiftUI render (selection moves, hover, each key
    /// press), and `urlForApplication` + `icon(forFile:)` are not cheap — that was most of the "lag khi loading".
    private static let cache = NSCache<NSString, NSImage>()
    private static let missing = NSImage()          // sentinel: an app we could not resolve is not asked again

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let id = bundleID, !id.isEmpty else { return nil }
        if let hit = cache.object(forKey: id as NSString) { return hit === missing ? nil : hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            cache.setObject(missing, forKey: id as NSString)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: id as NSString)
        return icon
    }

    /// Icon of a file on disk, once per path (file cards in the notch deck asked on every render).
    private static let fileCache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 200; return c }()
    static func fileIcon(forPath path: String) -> NSImage {
        if let hit = fileCache.object(forKey: path as NSString) { return hit }
        let icon = NSWorkspace.shared.icon(forFile: path)
        fileCache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

/// Dynamic app-icon color extractor with curated brand colors and caching.
/// Gives every clipboard item card a vibrant, Paste 7-style brand header.
@MainActor
enum ClipboardAppColor {
    // In-memory cache by bundleID
    private static var colorCache: [String: Color] = [:]
    /// Bundle ids whose icon yields no accent (greyscale, too dark, missing app).
    private static var noAccent: Set<String> = []


    // Curated high-fidelity brand colors for popular macOS applications
    private static let curatedBrandColors: [String: Color] = [
        "com.apple.Safari": Color(red: 0.05, green: 0.52, blue: 1.0), // Safari Blue
        "com.google.Chrome": Color(red: 0.20, green: 0.53, blue: 0.98), // Chrome Blue
        "com.google.Chrome.canary": Color(red: 0.98, green: 0.65, blue: 0.10),
        "com.apple.Notes": Color(red: 0.96, green: 0.70, blue: 0.08), // Notes Amber/Gold
        "com.apple.MobileSMS": Color(red: 0.22, green: 0.80, blue: 0.38), // Messages Green
        "com.tinyspeck.slackmacgap": Color(red: 0.88, green: 0.18, blue: 0.32), // Slack Coral/Plum
        "com.apple.mail": Color(red: 0.12, green: 0.53, blue: 0.95), // Mail Blue
        "com.apple.Photos": Color(red: 0.98, green: 0.25, blue: 0.40), // Photos Coral/Rose
        "com.apple.Terminal": Color(red: 0.18, green: 0.22, blue: 0.28), // Terminal Slate
        "com.googlecode.iterm2": Color(red: 0.15, green: 0.20, blue: 0.26),
        "dev.warp.Warp-GDK": Color(red: 0.05, green: 0.65, blue: 0.85),
        "com.mitchellh.ghostty": Color(red: 0.16, green: 0.20, blue: 0.25),
        "com.apple.dt.Xcode": Color(red: 0.08, green: 0.50, blue: 0.98), // Xcode Developer Blue
        "com.microsoft.VSCode": Color(red: 0.00, green: 0.48, blue: 0.82), // VS Code Blue
        "com.apple.finder": Color(red: 0.10, green: 0.58, blue: 0.94), // Finder Sky Blue
        "com.figma.Desktop": Color(red: 0.63, green: 0.35, blue: 1.00), // Figma Purple
        "com.apple.Music": Color(red: 0.98, green: 0.18, blue: 0.30), // Apple Music Red
        "com.apple.reminders": Color(red: 1.00, green: 0.58, blue: 0.00), // Reminders Orange
        "com.apple.iCal": Color(red: 0.92, green: 0.26, blue: 0.35), // Calendar Red
        "ru.keepcoder.Telegram": Color(red: 0.16, green: 0.67, blue: 0.93), // Telegram Cyan
        "com.hnc.Discord": Color(red: 0.35, green: 0.40, blue: 0.95), // Discord Indigo
        "com.apple.Pages": Color(red: 0.95, green: 0.45, blue: 0.12), // Pages Orange
        "com.apple.Numbers": Color(red: 0.18, green: 0.75, blue: 0.35), // Numbers Green
        "com.apple.Keynote": Color(red: 0.20, green: 0.55, blue: 0.95), // Keynote Blue
        "com.microsoft.Word": Color(red: 0.11, green: 0.34, blue: 0.69), // Word Deep Blue
        "com.microsoft.Excel": Color(red: 0.13, green: 0.54, blue: 0.27), // Excel Green
        "com.microsoft.Powerpoint": Color(red: 0.86, green: 0.28, blue: 0.14), // PowerPoint Orange
        "notion.id": Color(red: 0.22, green: 0.22, blue: 0.25),
        "com.apple.Preview": Color(red: 0.10, green: 0.58, blue: 0.94),
        "com.apple.systempreferences": Color(red: 0.39, green: 0.39, blue: 0.42),
    ]

    static func color(forBundleID bundleID: String?, contentType: ContentType) -> Color {
        guard let id = bundleID, !id.isEmpty else {
            return fallbackColor(for: contentType)
        }
        if let cached = colorCache[id] {
            return cached
        }
        // The fallback depends on the CONTENT TYPE, so it is never stored under the bundle id alone (review
        // 2026-10-13: a Zed code clip cached green, then every Zed text clip inherited green). Only the fact
        // "this app's icon has no usable accent" is remembered, so the icon is not re-drawn on every render.
        if noAccent.contains(id) { return fallbackColor(for: contentType) }
        if let curated = curatedBrandColors[id] {
            colorCache[id] = curated
            return curated
        }
        // Extract dominant vibrant color from the app icon
        if let icon = ClipboardAppIcon.icon(forBundleID: id),
           let extracted = extractDominantColor(from: icon) {
            let color = Color(red: extracted.r, green: extracted.g, blue: extracted.b)
            colorCache[id] = color
            return color
        }
        noAccent.insert(id)
        return fallbackColor(for: contentType)
    }

    static func fallbackColor(for type: ContentType) -> Color {
        switch type {
        case .link: return Color(red: 0.05, green: 0.52, blue: 1.0)
        case .image: return Color(red: 0.98, green: 0.25, blue: 0.40)
        case .code: return Color(red: 0.08, green: 0.68, blue: 0.45)
        case .color: return Color(red: 0.65, green: 0.35, blue: 0.95)
        case .file: return Color(red: 0.95, green: 0.60, blue: 0.10)
        case .text: return Color(red: 0.30, green: 0.45, blue: 0.95)
        case .markdown: return Color(red: 0.10, green: 0.65, blue: 0.85)
        case .merged: return Color(red: 0.50, green: 0.30, blue: 0.90)
        }
    }

    /// The icon drawn at 32 × 32 and scored by `ClipPreviewRules.dominantColor`. Measured 2026-10-13: the old
    /// `image.tiffRepresentation` rendered every icon representation into one uncompressed TIFF — ≈ 74 MB per source
    /// app, freed at once but left dirty in the malloc zone, so the Clipboard Library page sat at 400–650 MB.
    private static func extractDominantColor(from image: NSImage) -> (r: Double, g: Double, b: Double)? {
        let side = ClipPreviewRules.iconSampleSide
        var proposed = NSRect(x: 0, y: 0, width: side, height: side)
        guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return nil }
        let row = ctx.bytesPerRow
        let bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: row * side))
        return ClipPreviewRules.dominantColor(rgba: bytes, width: side, height: side, bytesPerRow: row)
    }
}


/// Content-type classifier: code / color / file / link / image / text.
/// Pure + nonisolated so capture paths can call it off the main actor.
enum ClipboardClassifier {

    static func classify(text: String) -> ContentType {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .text }
        // D1 #7: #hex, rgb(), hsl() — whole-string only (`ColorFormat.parse`, pure, tested).
        if ColorFormat.parse(t) != nil { return .color }
        if t.count < 2000, let u = URL(string: t),
           let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return .link
        }
        if looksLikeMarkdown(t) { return .markdown }
        if looksLikeCode(t) { return .code }
        return .text
    }

    /// Markdown — tiêu đề #, list -, blockquote >, bảng |, ```, **đậm**,
    /// link [..](..). Đủ nhạy để phân biệt với text thuần nhưng không bắt
    /// nhầm code (code trả về ở looksLikeCode, chạy sau).
    private static func looksLikeMarkdown(_ t: String) -> Bool {
        var score = 0
        for rawLine in t.split(separator: "\n").prefix(20) {
            let s = String(rawLine).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { score += 2 }
            if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("> ") { score += 1 }
            if s.contains("|") { score += 1 }
            if s.contains("```") { score += 2 }
            if s.contains("**") { score += 1 }
            if s.contains("](") { score += 1 }
        }
        return score >= 2
    }

    private static func looksLikeCode(_ t: String) -> Bool {
        guard t.count > 8, t.contains("\n") || t.contains(";") else { return false }
        let markers = ["func ", "class ", "struct ", "import ", "let ", "var ",
                       "def ", "return ", "{", "}", "=>", "func(", "#include",
                       "public ", "private ", "func\t", "if let ", "guard let "]
        let hits = markers.filter { t.contains($0) }.count
        if hits >= 2 { return true }
        // Single strong marker + braces/semicolons.
        if hits == 1 && (t.contains("{") || t.contains(";")) { return true }
        return false
    }

    /// NSColor from a #RGB/RRGGBB/RRGGBBAA string; nil when unparseable.
    /// Any colour notation `ColorFormat.parse` knows (#hex, rgb(), hsl()) → an sRGB NSColor.
    static func color(from text: String) -> NSColor? {
        guard let c = ColorFormat.parse(text) else { return nil }
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// Detects credit card numbers (Luhn candidate, 13-19 digits) to prevent saving payment secrets.
    static func looksLikeCreditCard(_ t: String) -> Bool {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isNumber }
        guard (13...19).contains(digits.count),
              digits.count == trimmed.filter({ !$0.isWhitespace && $0 != "-" }).count else {
            return false
        }
        var sum = 0
        let reversed = digits.reversed().map { Int(String($0)) ?? 0 }
        for (idx, digit) in reversed.enumerated() {
            if idx % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// A preview image when the record or its text points at an IMAGE file on disk. Never hands a non-image file to
    /// a decoder and never decodes at full size: measured 2026-10-13, the old `NSImage(contentsOfFile:)` read a copied
    /// 42 MB .mp4 in full — twice per render — to learn it was not an image. Main actor: every caller is a card view,
    /// and the shared ImageIO cache (≤ 480 px, misses cached too) lives there.
    @MainActor
    static func resolveCandidateImage(for record: ClipboardRecord) -> NSImage? {
        for p in [record.thumbnailPath, record.payloadPath, record.metadata["path"]].compactMap({ $0 }) {
            if let img = previewImage(atPath: p) { return img }
        }

        let rawText = record.textSnippet ?? record.displayPreview
        let home = FileManager.default.homeDirectoryForCurrentUser
        let deskURL = home.appendingPathComponent("Desktop"), dlURL = home.appendingPathComponent("Downloads")
        for rawLine in rawText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            let hasImgExt = ClipPreviewRules.isImageFile(line)
            let isScreenshot = lower.contains("screenshot") || lower.contains("anh chup man hinh") || lower.contains("chụp màn hình")
            guard hasImgExt || isScreenshot else { continue }
            var candidates = [line, deskURL.appendingPathComponent(line).path, dlURL.appendingPathComponent(line).path]
            if !hasImgExt {
                candidates += [deskURL.appendingPathComponent(line + ".png").path, dlURL.appendingPathComponent(line + ".png").path]
            }
            for c in candidates { if let img = previewImage(atPath: c) { return img } }
        }
        return nil
    }

    @MainActor
    private static func previewImage(atPath path: String) -> NSImage? {
        let kind = ClipPreviewRules.previewKind(path)
        guard kind != .none, FileManager.default.fileExists(atPath: path) else { return nil }
        return kind == .pdf ? NotchThumbnailCache.pdfFirstPage(atPath: path) : NotchThumbnailCache.image(atPath: path)
    }
}

/// Context ranking for the shelf's "Gợi ý" tab.
///
/// This is a **rule-based heuristic**, not a model: recency, usage count, pinned/saved
/// state, and a workflow role inferred from the target app's bundle ID. It never calls
/// FoundationModels or any Apple Intelligence API, and the UI must not say it does —
/// an earlier label claimed "Apple Intelligence" for exactly this code (Part 0 §6).
@MainActor
@Observable
final class ClipboardIntelligenceEngine {
    static let shared = ClipboardIntelligenceEngine()

    private init() {}

    /// The ONE reader of `clipboard.intelligentSuggestions`. The Clipboard settings page
    /// binds the key; the shelf asks this accessor at the point of use, so the switch takes
    /// effect without a re-arm. Default `true` must equal the view's `@AppStorage` default
    /// (`FeatureKeyDefaultsTests` checks both declarations).
    nonisolated var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "clipboard.intelligentSuggestions") as? Bool ?? true
    }

    /// Workflow categories for macOS destination applications.
    enum AppWorkflowRole {
        case developer
        case communication
        case design
        case dataFinance
        case writing
        case browser
        case general
    }

    func role(forBundleID bundleID: String?, appName: String?) -> AppWorkflowRole {
        let b = (bundleID ?? "").lowercased()
        let n = (appName ?? "").lowercased()

        if b.contains("xcode") || b.contains("terminal") || b.contains("iterm") ||
           b.contains("vscode") || b.contains("warp") || b.contains("ghostty") ||
           b.contains("sublime") || b.contains("intellij") || b.contains("pycharm") ||
           b.contains("webstorm") || b.contains("zed") || n.contains("terminal") || n.contains("code") {
            return .developer
        }
        if b.contains("mail") || b.contains("mobilesms") || b.contains("slack") ||
           b.contains("telegram") || b.contains("discord") || b.contains("teams") ||
           b.contains("whatsapp") || b.contains("spark") || b.contains("outlook") ||
           n.contains("messages") || n.contains("mail") || n.contains("slack") {
            return .communication
        }
        if b.contains("figma") || b.contains("sketch") || b.contains("photoshop") ||
           b.contains("illustrator") || b.contains("pixelmator") || b.contains("canva") ||
           b.contains("keynote") || b.contains("blender") {
            return .design
        }
        if b.contains("excel") || b.contains("numbers") || b.contains("calc") ||
           b.contains("tableplus") || b.contains("dbeaver") || n.contains("excel") || n.contains("numbers") {
            return .dataFinance
        }
        if b.contains("notes") || b.contains("pages") || b.contains("word") ||
           b.contains("notion") || b.contains("obsidian") || b.contains("bear") ||
           b.contains("craft") || n.contains("notes") || n.contains("word") {
            return .writing
        }
        if b.contains("safari") || b.contains("chrome") || b.contains("arc") ||
           b.contains("edge") || b.contains("firefox") || b.contains("brave") {
            return .browser
        }
        return .general
    }

    func targetAppName(forTargetPID pid: pid_t?) -> String {
        if let pid, let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName, !name.isEmpty {
            return name
        }
        if let front = NSWorkspace.shared.frontmostApplication, let name = front.localizedName, !name.isEmpty {
            return name
        }
        return "Finder"
    }

    /// Evaluates clipboard history records and returns intelligent recommendations
    /// tailored to the destination application the user is currently working in.
    func rankSuggestions(from records: [ClipboardRecord], forTargetPID pid: pid_t?, limit: Int = 12) -> [ClipboardRecord] {
        guard !records.isEmpty else { return [] }

        var targetBundleID: String?
        var targetAppName: String?

        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            targetBundleID = app.bundleIdentifier
            targetAppName = app.localizedName
        } else if let front = NSWorkspace.shared.frontmostApplication {
            targetBundleID = front.bundleIdentifier
            targetAppName = front.localizedName
        }

        let workflow = role(forBundleID: targetBundleID, appName: targetAppName)
        let now = Date()

        var scored: [(record: ClipboardRecord, score: Double)] = []

        for r in records {
            var score: Double = 0

            // 1. Recency boost (within 10m: +35, 1h: +25, 4h: +15, 24h: +8)
            let ageMinutes = max(0, now.timeIntervalSince(r.timestamp) / 60.0)
            if ageMinutes < 10 {
                score += 35
            } else if ageMinutes < 60 {
                score += 25
            } else if ageMinutes < 240 {
                score += 15
            } else if ageMinutes < 1440 {
                score += 8
            }

            // 2. Frequency / usage habit boost
            score += min(20.0, Double(r.usageCount) * 4.0)

            // 3. Pinned / Saved snippet boost
            if r.isPinned { score += 12 }
            if r.isSavedSnippet { score += 10 }

            // 4. Workflow role affinity
            let snippet = r.textSnippet ?? ""
            switch workflow {
            case .developer:
                if r.type == .code { score += 40 }
                if snippet.contains("git ") || snippet.contains("npm ") || snippet.contains("brew ") ||
                   snippet.contains("docker ") || snippet.contains("curl ") || snippet.contains("func ") {
                    score += 30
                }
                if r.type == .link, snippet.contains("github.com") || snippet.contains("stackoverflow.com") {
                    score += 25
                }
            case .communication:
                if r.type == .link { score += 35 }
                if containsEmail(snippet) || containsPhoneNumber(snippet) { score += 30 }
                if r.type == .text && snippet.count < 300 { score += 15 }
            case .design:
                if r.type == .color { score += 45 }
                if r.type == .image { score += 40 }
            case .dataFinance:
                if containsNumbersOrCurrency(snippet) { score += 35 }
                if snippet.contains("\t") || snippet.contains(",") { score += 20 }
            case .writing:
                if r.type == .text || r.type == .markdown { score += 30 }
                if r.type == .link { score += 20 }
            case .browser:
                if r.type == .link { score += 40 }
                if r.type == .text && snippet.count < 100 { score += 20 }
            case .general:
                break
            }

            // 5. Cross-app transition: if copied from a complementary app
            if let src = r.sourceBundleID?.lowercased() {
                if (src.contains("safari") || src.contains("chrome")) && workflow == .communication {
                    score += 20
                }
                if src.contains("figma") && workflow == .developer {
                    score += 20
                }
            }

            scored.append((r, score))
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(limit).map(\.record))
    }

    private func containsEmail(_ text: String) -> Bool {
        text.contains("@") && text.contains(".") && text.count < 100
    }

    private func containsPhoneNumber(_ text: String) -> Bool {
        let digits = text.filter { $0.isNumber }
        return (9...15).contains(digits.count) && text.count < 30
    }

    private func containsNumbersOrCurrency(_ text: String) -> Bool {
        if text.contains("$") || text.contains("€") || text.contains("₫") || text.contains("VNĐ") || text.contains("%") {
            return true
        }
        let digits = text.filter { $0.isNumber }
        return digits.count > 3 && digits.count > (text.count / 3)
    }
}

