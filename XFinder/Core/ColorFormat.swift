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
}
