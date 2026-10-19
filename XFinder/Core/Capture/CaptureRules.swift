import Foundation
import CoreGraphics

/// F4 — Chụp & chú thích: pure rules shared by the settings page, the capture controller and the Quick Access
/// card. No AppKit/SwiftUI here so the whole module can be unit tested without a running app (CLAUDE.md Part 4).
///
/// The job sentence: *"I capture a region / the focused window / the screen; it is on my clipboard at once, a
/// small card offers to mark it up, save it, pin it or drag it out; marking up is quick and Return copies the
/// result."* Everything in this file either decides WHAT to capture (shortcuts, screencapture argv) or WHERE a
/// result goes (file names, dedupe, pruning, card geometry) — never HOW to draw it (that is Annotation.swift).

// MARK: - Modes

enum CaptureMode: String, CaseIterable, Codable {
    case area, window, fullscreen, areaAnnotate, text, color

    var titleKey: String {
        switch self {
        case .area: return "Chụp vùng"
        case .window: return "Chụp cửa sổ đang mở"
        case .fullscreen: return "Chụp toàn màn hình"
        case .areaAnnotate: return "Chụp vùng rồi chú thích"
        case .text: return "Chép chữ từ màn hình"
        case .color: return "Lấy màu từ màn hình"
        }
    }

    var descriptionKey: String {
        switch self {
        case .area: return "Kéo khoanh phần màn hình bạn muốn lấy"
        case .window: return "Chụp đúng cửa sổ đang được chọn, không cần khoanh vùng"
        case .fullscreen: return "Chụp toàn bộ màn hình đang dùng"
        case .areaAnnotate: return "Khoanh vùng rồi mở ngay cửa sổ chú thích"
        case .text: return "Nhận diện và sao chép chữ trong vùng bạn chọn"
        case .color: return "Lấy mã màu tại điểm bạn trỏ tới"
        }
    }

    var symbol: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullscreen: return "display"
        case .areaAnnotate: return "pencil.and.outline"
        case .text: return "text.viewfinder"
        case .color: return "eyedropper"
        }
    }

    var shortcutKey: String { "capture.shortcut.\(rawValue)" }
}

// MARK: - Shortcuts

/// A key combination stored as a virtual key code + a subset of `NSEvent.ModifierFlags`' raw bits. Kept
/// Foundation-only by hard-coding the raw bit values (command 1<<20, shift 1<<17, option 1<<19, control 1<<18 —
/// the same values `NSEvent.ModifierFlags` publishes) rather than importing AppKit.
struct CaptureShortcut: Codable, Equatable, Hashable {
    static let commandBit = 1 << 20
    static let shiftBit = 1 << 17
    static let optionBit = 1 << 19
    static let controlBit = 1 << 18

    var keyCode: Int
    var modifiers: Int

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var hasControl: Bool { modifiers & Self.controlBit != 0 }
    var hasOption: Bool { modifiers & Self.optionBit != 0 }
    var hasShift: Bool { modifiers & Self.shiftBit != 0 }
    var hasCommand: Bool { modifiers & Self.commandBit != 0 }

    /// At least one of ⌘ ⌥ ⌃ — a bare ⇧ (or no modifier) is not a valid global shortcut.
    var hasRequiredModifier: Bool { hasCommand || hasOption || hasControl }

    /// Display order ⌃⌥⇧⌘ then the key's own name.
    var label: String {
        var s = ""
        if hasControl { s += "⌃" }
        if hasOption { s += "⌥" }
        if hasShift { s += "⇧" }
        if hasCommand { s += "⌘" }
        s += Self.keyName(for: keyCode)
        return s
    }

    /// Carbon modifier mask (cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096 — Carbon's own constants,
    /// reproduced as literals so this file need not import Carbon).
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if hasCommand { m |= 256 }
        if hasShift { m |= 512 }
        if hasOption { m |= 2048 }
        if hasControl { m |= 4096 }
        return m
    }

    var encoded: String {
        let obj: [String: Int] = ["keyCode": keyCode, "modifiers": modifiers]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ s: String?) -> CaptureShortcut? {
        guard let s, let data = s.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else { return nil }
        guard let keyCode = obj["keyCode"], let modifiers = obj["modifiers"] else { return nil }
        return CaptureShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    /// Virtual key code → display name: digits, letters, F-keys, arrows, and the handful of named keys a
    /// screenshot/OCR/color shortcut is realistically bound to. Virtual key codes are macOS's own stable ANSI
    /// layout constants (the same values Carbon's `kVK_*` enum publishes); reproduced here as literals because
    /// this file is Foundation-only.
    static func keyName(for keyCode: Int) -> String {
        if let digit = digitNames[keyCode] { return digit }
        if let letter = letterNames[keyCode] { return letter }
        if let fKey = fKeyNames[keyCode] { return fKey }
        if let named = namedKeys[keyCode] { return named }
        return "Key \(keyCode)"
    }

    // kVK_ANSI_0...9
    private static let digitNames: [Int: String] = [
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
        23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]

    // kVK_ANSI_A...Z
    private static let letterNames: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
    ]

    // kVK_F1...F20 (the commonly bound subset)
    private static let fKeyNames: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]

    private static let namedKeys: [Int: String] = [
        123: "←", 124: "→", 126: "↑", 125: "↓",
        49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "⌫",
        117: "⌦", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]
}

// MARK: - After-capture / card edge / format

enum CaptureAfter: String, CaseIterable {
    case copyAndCard, copyOnly, annotate

    var titleKey: String {
        switch self {
        case .copyAndCard: return "Sao chép và hiện thẻ xem trước — mặc định"
        case .copyOnly: return "Chỉ sao chép"
        case .annotate: return "Mở chú thích ngay"
        }
    }
}

enum CaptureCardEdge: String, CaseIterable {
    case left, right

    var titleKey: String {
        switch self {
        case .left: return "Trái"
        case .right: return "Phải"
        }
    }
}

enum CaptureFormat: String, CaseIterable {
    case png, jpg, heic

    var utType: String {
        switch self {
        case .png: return "public.png"
        case .jpg: return "public.jpeg"
        case .heic: return "public.heic"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpg: return "jpg"
        case .heic: return "heic"
        }
    }
}

// MARK: - Capture item

struct CaptureItem: Equatable, Identifiable {
    var url: URL
    var date: Date
    var pixelWidth: Int
    var pixelHeight: Int

    var id: String { url.path }
}

// MARK: - Rules

enum CaptureRules {
    // UserDefaults keys (read in Core with the project's standard reader forms — see CaptureController).
    static let enabledKey = "capture.enabled"
    static let afterKey = "capture.after"
    static let cardSecondsKey = "capture.cardSeconds"
    static let cardEdgeKey = "capture.cardEdge"
    static let pauseOnHoverKey = "capture.pauseOnHover"
    static let swipeDismissKey = "capture.swipeDismiss"
    static let soundKey = "capture.sound"
    static let countdownKey = "capture.countdown"
    static let windowShadowKey = "capture.windowShadow"
    static let saveFolderKey = "capture.saveFolder"
    static let formatKey = "capture.format"
    static let keepHistoryKey = "capture.keepHistory"
    static let annotateColorKey = "capture.annotate.color"
    static let annotateWidthKey = "capture.annotate.width"

    static let historyLimit = 50
    static let cardSecondsChoices = [5, 10, 30, 0]

    /// OneNotch's own default bindings (measured from its shipped defaults): area ⇧⌘4, fullscreen ⇧⌘3,
    /// window ⇧⌘9, text ⇧⌘2, color ⇧⌘1. `areaAnnotate` has none in the reference, so it is absent here too.
    static let oneNotchPreset: [CaptureMode: CaptureShortcut] = [
        .area: CaptureShortcut(keyCode: 21, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
        .fullscreen: CaptureShortcut(keyCode: 20, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
        .window: CaptureShortcut(keyCode: 25, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
        .text: CaptureShortcut(keyCode: 19, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
        .color: CaptureShortcut(keyCode: 18, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
    ]

    /// macOS's own screenshot shortcuts (System Settings ▸ Keyboard ▸ Shortcuts ▸ Screenshots default bindings).
    static let systemReserved: [(shortcut: CaptureShortcut, nameKey: String)] = [
        (CaptureShortcut(keyCode: 20, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
         "macOS Chụp toàn màn hình"),
        (CaptureShortcut(keyCode: 21, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
         "macOS Chụp vùng"),
        (CaptureShortcut(keyCode: 23, modifiers: CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
         "macOS Tùy chọn chụp và ghi màn hình"),
        (CaptureShortcut(keyCode: 20, modifiers: CaptureShortcut.controlBit | CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
         "macOS Sao chép toàn màn hình"),
        (CaptureShortcut(keyCode: 21, modifiers: CaptureShortcut.controlBit | CaptureShortcut.shiftBit | CaptureShortcut.commandBit),
         "macOS Sao chép vùng"),
    ]

    enum Conflict: Equatable {
        case system(nameKey: String)
        case mode(CaptureMode)
    }

    /// Another assigned mode with the same shortcut wins over a system clash in the answer — the user can fix
    /// their own double-assignment immediately, while the system clash is informational (macOS may or may not
    /// still own the combination; the page just warns).
    static func conflict(for shortcut: CaptureShortcut, mode: CaptureMode, assigned: [CaptureMode: CaptureShortcut]) -> Conflict? {
        for (otherMode, otherShortcut) in assigned where otherMode != mode && otherShortcut == shortcut {
            return .mode(otherMode)
        }
        for entry in systemReserved where entry.shortcut == shortcut {
            return .system(nameKey: entry.nameKey)
        }
        return nil
    }

    /// Exact argv for `/usr/sbin/screencapture`.
    /// `countdown` (seconds, `-T`) applies only to the modes with no selection step — fullscreen and a window taken by
    /// id; once `-i` waits for the person to pick, the person already decides when. `windowShadow == false` adds `-o`
    /// for window shots only (the flag means nothing elsewhere).
    static func screencaptureArguments(mode: CaptureMode, output: String, sound: Bool, windowID: Int?, display: Int,
                                       countdown: Int = 0, windowShadow: Bool = true) -> [String] {
        var args: [String] = []
        switch mode {
        case .area, .areaAnnotate, .text:
            args += ["-i"]
        case .window:
            if let windowID {
                args += ["-l", "\(windowID)"]
            } else {
                args += ["-i", "-W"]
            }
        case .fullscreen:
            args += ["-D", "\(display)"]
        case .color:
            args += ["-i"]
        }
        if countdown > 0, !args.contains("-i") {
            args += ["-T", "\(countdown)"]
        }
        if mode == .window, !windowShadow {
            args += ["-o"]
        }
        args += ["-t", "png"]
        if !sound {
            args += ["-x"]
        }
        args.append(output)
        return args
    }

    /// "<prefix> 2026-10-13 lúc 14.32.10.<ext>" — 24-hour clock, zero-padded, local time zone unless given.
    static func fileName(prefix: String, at: String, date: Date, ext: String, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = c.year ?? 1970
        let month = pad2(c.month ?? 1)
        let day = pad2(c.day ?? 1)
        let hour = pad2(c.hour ?? 0)
        let minute = pad2(c.minute ?? 0)
        let second = pad2(c.second ?? 0)
        return "\(prefix) \(year)-\(month)-\(day)\(at)\(hour).\(minute).\(second).\(ext)"
    }

    private static func pad2(_ n: Int) -> String {
        n < 10 ? "0\(n)" : "\(n)"
    }

    /// Keep-both: "x.png" → "x 2.png", "x 3.png"… matched case-insensitively against existing names.
    static func uniqueName(_ name: String, existing: Set<String>) -> String {
        let lowerExisting = Set(existing.map { $0.lowercased() })
        guard lowerExisting.contains(name.lowercased()) else { return name }

        let ext = (name as NSString).pathExtension
        let base: String
        if ext.isEmpty {
            base = name
        } else {
            base = (name as NSString).deletingPathExtension
        }

        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !lowerExisting.contains(candidate.lowercased()) {
                return candidate
            }
            counter += 1
        }
    }

    /// Items beyond `limit`, oldest first out (sorted by date ascending; ties broken by path so the result is
    /// deterministic).
    static func toPrune(_ items: [CaptureItem], limit: Int) -> [CaptureItem] {
        guard items.count > limit else { return [] }
        let sortedOldestFirst = items.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.url.path < b.url.path
        }
        let overflow = sortedOldestFirst.count - limit
        return Array(sortedOldestFirst.prefix(overflow))
    }

    /// Card frame in AppKit coordinates (origin bottom-left): anchored to the bottom corner of `visible` on
    /// `edge`, 16 pt inset from both edges, stacked UPWARD by index with a 10 pt gap between cards.
    static func cardFrame(visible: CGRect, edge: CaptureCardEdge, size: CGSize, index: Int) -> CGRect {
        let inset: CGFloat = 16
        let gap: CGFloat = 10
        let x: CGFloat
        switch edge {
        case .left:
            x = visible.minX + inset
        case .right:
            x = visible.maxX - inset - size.width
        }
        let y = visible.minY + inset + CGFloat(index) * (size.height + gap)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Card size for an image: fixed width 220 pt, height scaled to the image's aspect ratio and clamped to
    /// [90, 260].
    static func cardSize(pixelWidth: Int, pixelHeight: Int) -> CGSize {
        let width: CGFloat = 220
        guard pixelWidth > 0 else { return CGSize(width: width, height: 90) }
        let aspectHeight = width * CGFloat(pixelHeight) / CGFloat(pixelWidth)
        let height = min(max(aspectHeight, 90), 260)
        return CGSize(width: width, height: height)
    }

    /// Display title parts "13/10" and "14.32" for "Ảnh chụp 13/10 lúc 14.32" — callers assemble the sentence
    /// through `L10n.t` fragments; this just formats the two numeric parts.
    static func titleParts(date: Date, timeZone: TimeZone = .current) -> (day: String, time: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.day, .month, .hour, .minute], from: date)
        let day = "\(c.day ?? 1)/\(c.month ?? 1)"
        let time = "\(pad2(c.hour ?? 0)).\(pad2(c.minute ?? 0))"
        return (day, time)
    }
}

// MARK: - Card countdown

/// A pure countdown for a Quick Access card. No timer lives inside it — the view/controller owns the ticking
/// timer and calls `remaining(at:)` / `isExpired(at:)` against the current `Date()`.
struct CardCountdown: Equatable {
    private(set) var total: TimeInterval
    private var start: Date
    private var pausedAt: Date?
    /// Total time already spent paused, subtracted from elapsed time.
    private var accumulatedPause: TimeInterval = 0

    init(total: TimeInterval, start: Date) {
        self.total = total
        self.start = start
    }

    var isPaused: Bool { pausedAt != nil }

    mutating func pause(at date: Date) {
        guard pausedAt == nil else { return }
        pausedAt = date
    }

    mutating func resume(at date: Date) {
        guard let pausedSince = pausedAt else { return }
        accumulatedPause += max(0, date.timeIntervalSince(pausedSince))
        pausedAt = nil
    }

    /// Remaining time, never negative. While paused, time does not advance past the pause point.
    func remaining(at date: Date) -> TimeInterval {
        guard total > 0 else { return .infinity }
        let effectiveNow = pausedAt ?? date
        let elapsed = effectiveNow.timeIntervalSince(start) - accumulatedPause
        return max(0, total - elapsed)
    }

    /// total == 0 means "never expires".
    func isExpired(at date: Date) -> Bool {
        guard total > 0 else { return false }
        return remaining(at: date) <= 0
    }
}
