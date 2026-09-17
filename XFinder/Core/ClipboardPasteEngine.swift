import AppKit
import Foundation
import SwiftUI

/// Paste-via-keystroke engine (PasteApp behavior): writes a record's content to
/// the general pasteboard, fronts the previously-active app, and synthesizes
/// ⌘V (or plain-text paste) via CGEvent. Requires Accessibility trust —
/// callers gate on `WindowManager.isTrusted` and show the grant flow otherwise.
enum ClipboardPasteEngine {

    /// Activate `pid` then synthesize ⌘V after a short settle delay.
    @discardableResult
    static func paste(record: ClipboardRecord, to pid: pid_t?, plainText: Bool = false) -> Bool {
        guard WindowManager.isTrusted else { return false }
        guard writeToPasteboard(record: record, plainText: plainText) else { return false }
        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
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
        let pb = NSPasteboard.general
        pb.clearContents()
        switch record.type {
        case .text, .code, .markdown, .color:
            guard let s = record.textSnippet ?? record.ocrText else { return false }
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

    private static func synthesizeCommandV() {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// Paste Stack: sequential queue — repeat ⌘V pastes queue items FIFO.
/// Modelled as plain state on ClipboardManager; the view renders the mini-HUD.
struct PasteStack {
    private(set) var items: [ClipboardRecord] = []
    private(set) var active = false

    var remaining: Int { items.count }

    mutating func start(with items: [ClipboardRecord]) {
        self.items = items
        self.active = !items.isEmpty
    }

    mutating func stop() {
        items = []
        active = false
    }

    /// Write the next item to the pasteboard; deactivate when drained.
    mutating func popNext() -> ClipboardRecord? {
        guard active, !items.isEmpty else {
            active = false
            return nil
        }
        let next = items.removeFirst()
        if items.isEmpty { active = false }
        return next
    }
}

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

    static func playCopy() {
        guard soundsOn else { return }
        NSSound(named: "Pop")?.play()
        if #available(macOS 12.0, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}

/// App-icon accent helper: icon of the source app for card headers.
enum ClipboardAppIcon {
    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let id = bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Content-type classifier: code / color / file / link / image / text.
/// Pure + nonisolated so capture paths can call it off the main actor.
enum ClipboardClassifier {
    private static let hexRE = try? NSRegularExpression(pattern: #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#)

    static func classify(text: String) -> ContentType {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .text }
        if t.count <= 9, let re = hexRE,
           re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
            return .color
        }
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
    static func color(from hex: String) -> NSColor? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard h.hasPrefix("#") else { return nil }
        h.removeFirst()
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&value) else { return nil }
        if h.count == 6 {
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        } else if h.count == 8 {
            return NSColor(srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
                           green: CGFloat((value >> 16) & 0xFF) / 255,
                           blue: CGFloat((value >> 8) & 0xFF) / 255,
                           alpha: CGFloat(value & 0xFF) / 255)
        }
        return nil
    }
}
