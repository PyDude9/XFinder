import Foundation

/// The pure half of "pick a colour from the screen": turning sRGB components into the text that
/// goes on the clipboard. Foundation-only so the rounding and clamping rules are pinned by tests.
///
/// The output is exactly what `ClipboardClassifier` recognises as a colour (`#RRGGBB`, upper-case),
/// so a picked colour lands in the clipboard history as "Màu sắc" with no extra code.
enum ColorFormat {

    /// `#RRGGBB` from sRGB components in 0…1. Out-of-range values are clamped (a wide-gamut
    /// display can produce values just outside sRGB once converted), NaN counts as 0, and each
    /// channel is rounded to the nearest 8-bit value — not truncated, which would turn 0.5 into
    /// 0x7F and make mid-greys one step too dark.
    static func hex(red: Double, green: Double, blue: Double) -> String {
        String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    static func byte(_ component: Double) -> Int {
        guard component.isFinite else { return 0 }
        let clamped = min(1, max(0, component))
        return Int((clamped * 255).rounded())
    }

    // MARK: - Parsing (D1 #7): hex, rgb(), hsl() — CSS syntax, the whole string

    struct RGBA: Equatable {
        var red: Double, green: Double, blue: Double, alpha: Double
    }

    /// Recognises a colour written as `#RGB` · `#RGBA` · `#RRGGBB` · `#RRGGBBAA` · `rgb(…)` / `rgba(…)` ·
    /// `hsl(…)` / `hsla(…)` with comma or space syntax, percentages, `deg`, and a `/ alpha` tail. The whole
    /// trimmed string must be the colour: a sentence that mentions `rgb(0,0,0)` is text. Components are
    /// clamped into range rather than rejected (`rgb(300, 0, 0)` is a sloppy red, not a non-colour).
    static func parse(_ text: String) -> RGBA? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 48 else { return nil }
        if t.hasPrefix("#") { return parseHex(String(t.dropFirst())) }
        let lower = t.lowercased()
        guard let open = lower.firstIndex(of: "("), lower.hasSuffix(")") else { return nil }
        let fn = String(lower[..<open])
        let inner = String(lower[lower.index(after: open)..<lower.index(before: lower.endIndex)])
        // "a, b, c" · "a b c" · "a b c / d" · "a, b, c, d"
        let mainAndAlpha = inner.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        var parts = mainAndAlpha[0].split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        if mainAndAlpha.count == 2 { parts.append(mainAndAlpha[1].trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let alpha = parts.count == 4 ? alphaValue(parts[3]) : 1
        guard let alpha else { return nil }
        switch fn {
        case "rgb", "rgba":
            guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
            return RGBA(red: r, green: g, blue: b, alpha: alpha)
        case "hsl", "hsla":
            guard let h = hue(parts[0]), let s = percent(parts[1]), let l = percent(parts[2]) else { return nil }
            let (r, g, b) = hslToRGB(h: h, s: s, l: l)
            return RGBA(red: r, green: g, blue: b, alpha: alpha)
        default:
            return nil
        }
    }

    /// `#RRGGBB` for a parsed colour (alpha dropped — the clipboard's canonical colour form).
    static func hex(_ c: RGBA) -> String { hex(red: c.red, green: c.green, blue: c.blue) }

    private static func parseHex(_ h: String) -> RGBA? {
        guard [3, 4, 6, 8].contains(h.count), h.allSatisfy(\.isHexDigit) else { return nil }
        let full = h.count <= 4 ? h.map { "\($0)\($0)" }.joined() : h
        var v: UInt64 = 0
        guard Scanner(string: full).scanHexInt64(&v) else { return nil }
        if full.count == 6 {
            return RGBA(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, alpha: 1)
        }
        return RGBA(red: Double((v >> 24) & 0xFF) / 255, green: Double((v >> 16) & 0xFF) / 255,
                    blue: Double((v >> 8) & 0xFF) / 255, alpha: Double(v & 0xFF) / 255)
    }

    /// `255` → 1.0, `50%` → 0.5; clamped to 0…1.
    private static func channel(_ s: String) -> Double? {
        if s.hasSuffix("%") { return percent(s) }
        guard let v = Double(s) else { return nil }
        return min(1, max(0, v / 255))
    }

    private static func percent(_ s: String) -> Double? {
        guard s.hasSuffix("%"), let v = Double(s.dropLast()) else { return nil }
        return min(1, max(0, v / 100))
    }

    /// `0.5` · `50%` → 0.5.
    private static func alphaValue(_ s: String) -> Double? {
        if s.hasSuffix("%") { return percent(s) }
        guard let v = Double(s) else { return nil }
        return min(1, max(0, v))
    }

    /// Degrees (with or without `deg`), wrapped into 0…<360 so `hsl(-30 …)` and `hsl(390 …)` are both 330 / 30.
    private static func hue(_ s: String) -> Double? {
        let digits = s.hasSuffix("deg") ? String(s.dropLast(3)) : s
        guard let v = Double(digits), v.isFinite else { return nil }
        let wrapped = v.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Standard CSS HSL → RGB (0…1 each).
    static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case ..<60:   (r1, g1, b1) = (c, x, 0)
        case ..<120:  (r1, g1, b1) = (x, c, 0)
        case ..<180:  (r1, g1, b1) = (0, c, x)
        case ..<240:  (r1, g1, b1) = (0, x, c)
        case ..<300:  (r1, g1, b1) = (x, 0, c)
        default:      (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }
}
