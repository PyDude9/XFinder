import XCTest
import Foundation

final class ColorFormatTests: XCTestCase {

    // MARK: D1 #7 — parsing hex, rgb(), hsl()

    func testParsesEveryHexLengthAndRejectsOthers() {
        XCTAssertEqual(ColorFormat.parse("#1F4E79"), .init(red: 0x1F / 255.0, green: 0x4E / 255.0, blue: 0x79 / 255.0, alpha: 1))
        XCTAssertEqual(ColorFormat.parse("#f80"), .init(red: 1, green: 0x88 / 255.0, blue: 0, alpha: 1), "#RGB doubles each digit")
        XCTAssertEqual(ColorFormat.parse("#f808")?.alpha ?? -1, 0x88 / 255.0, accuracy: 1e-9, "#RGBA")
        XCTAssertEqual(ColorFormat.parse("#1F4E7980")?.alpha ?? -1, 0x80 / 255.0, accuracy: 1e-9, "#RRGGBBAA")
        XCTAssertEqual(ColorFormat.parse("  #1f4e79\n"), ColorFormat.parse("#1F4E79"), "trimmed, case-insensitive")
        XCTAssertNil(ColorFormat.parse("#12345"), "five digits is not a colour")
        XCTAssertNil(ColorFormat.parse("#GGGGGG"))
        XCTAssertNil(ColorFormat.parse("1F4E79"), "no # ⇒ a hex-looking word, not a colour")
    }

    func testParsesRGBInCommaSpacePercentAndAlphaForms() {
        let orange = ColorFormat.RGBA(red: 1, green: 136 / 255.0, blue: 0, alpha: 1)
        XCTAssertEqual(ColorFormat.parse("rgb(255, 136, 0)"), orange)
        XCTAssertEqual(ColorFormat.parse("RGB(255 136 0)"), orange, "CSS4 space syntax, any case")
        XCTAssertEqual(ColorFormat.parse("rgb(100%, 50%, 0%)"), .init(red: 1, green: 0.5, blue: 0, alpha: 1))
        XCTAssertEqual(ColorFormat.parse("rgba(255,136,0,0.5)")?.alpha, 0.5)
        XCTAssertEqual(ColorFormat.parse("rgb(255 136 0 / 50%)")?.alpha, 0.5, "slash alpha as a percentage")
        XCTAssertEqual(ColorFormat.parse("rgb(300, -5, 0)"), .init(red: 1, green: 0, blue: 0, alpha: 1), "out of range clamps")
        XCTAssertNil(ColorFormat.parse("rgb(1, 2)"), "two channels")
        XCTAssertNil(ColorFormat.parse("rgb(a, b, c)"))
        XCTAssertNil(ColorFormat.parse("the colour is rgb(0,0,0) here"), "a sentence is text")
    }

    func testParsesHSLWithDegreesWrapAndAlpha() {
        let red = ColorFormat.parse("hsl(0, 100%, 50%)")!
        XCTAssertEqual(red.red, 1, accuracy: 1e-9); XCTAssertEqual(red.green, 0, accuracy: 1e-9); XCTAssertEqual(red.blue, 0, accuracy: 1e-9)
        let blue = ColorFormat.parse("hsl(240deg 100% 50%)")!
        XCTAssertEqual(blue.blue, 1, accuracy: 1e-9); XCTAssertEqual(blue.red, 0, accuracy: 1e-9)
        XCTAssertEqual(ColorFormat.parse("hsl(390, 100%, 50%)"), ColorFormat.parse("hsl(30, 100%, 50%)"), "hue wraps past 360")
        XCTAssertEqual(ColorFormat.parse("hsl(-30, 100%, 50%)"), ColorFormat.parse("hsl(330, 100%, 50%)"), "negative hue wraps")
        XCTAssertEqual(ColorFormat.parse("hsla(210, 65%, 57%, .5)")?.alpha, 0.5)
        let grey = ColorFormat.parse("hsl(120, 0%, 50%)")!
        XCTAssertEqual(grey.red, 0.5, accuracy: 1e-9); XCTAssertEqual(grey.green, 0.5, accuracy: 1e-9); XCTAssertEqual(grey.blue, 0.5, accuracy: 1e-9)
        XCTAssertNil(ColorFormat.parse("hsl(120, 50, 50)"), "saturation and lightness must be percentages")
        // OneNotch's page pairs #4A90D9 with hsl(210, 65%, 57%); those are ROUNDED forms of each other (#4A90D9 is
        // 210.6°, 65.3 %, 57.1 %). Converting the rounded hsl back lands one green step up — the maths is right,
        // the pair on the reference page is not exact. Pinned here so nobody "fixes" the converter to match it.
        XCTAssertEqual(ColorFormat.hex(ColorFormat.parse("hsl(210, 65%, 57%)")!), "#4A91D9")
        XCTAssertEqual(ColorFormat.hex(ColorFormat.parse("hsl(210.6, 65.3%, 57.06%)")!), "#4A90D9", "the exact hsl of #4A90D9 round-trips")
    }

    func testFormatsKnownColoursAsUpperCaseSixDigitHex() {
        XCTAssertEqual(ColorFormat.hex(red: 0, green: 0, blue: 0), "#000000")
        XCTAssertEqual(ColorFormat.hex(red: 1, green: 1, blue: 1), "#FFFFFF")
        XCTAssertEqual(ColorFormat.hex(red: 1, green: 136.0 / 255, blue: 0), "#FF8800")
        XCTAssertEqual(ColorFormat.hex(red: 31.0 / 255, green: 111.0 / 255, blue: 235.0 / 255), "#1F6FEB",
                       "the blue used throughout the classifier tests")
    }

    /// Rounded, not truncated: truncation turns every mid-tone one step too dark (0.5 → 0x7F).
    func testChannelsRoundToNearestNotTruncate() {
        XCTAssertEqual(ColorFormat.byte(0.5), 128, "127.5 rounds to 128, truncating would give 127")
        XCTAssertEqual(ColorFormat.hex(red: 0.5, green: 0.5, blue: 0.5), "#808080")
        XCTAssertEqual(ColorFormat.byte(0.999), 255)
        XCTAssertEqual(ColorFormat.byte(0.001), 0)
    }

    /// A wide-gamut display converted to sRGB can land just outside 0…1; that must clamp, not wrap
    /// into a different colour or produce a 3-digit channel.
    func testOutOfGamutValuesClampInsteadOfWrapping() {
        XCTAssertEqual(ColorFormat.hex(red: 1.08, green: -0.04, blue: 0.5), "#FF0080")
        XCTAssertEqual(ColorFormat.hex(red: 7, green: -9, blue: 1.0001), "#FF00FF")
        for v in stride(from: -1.0, through: 2.0, by: 0.173) {
            let h = ColorFormat.hex(red: v, green: v, blue: v)
            XCTAssertEqual(h.count, 7, "'\(h)' is not #RRGGBB for component \(v)")
        }
    }

    func testNonFiniteComponentsBecomeZeroInsteadOfCrashing() {
        // Int(NaN) would trap; a sampler should never produce these, but a trap in a colour picker
        // would take the app down, so every non-finite component is defined as 0.
        XCTAssertEqual(ColorFormat.byte(.nan), 0)
        XCTAssertEqual(ColorFormat.byte(.infinity), 0)
        XCTAssertEqual(ColorFormat.byte(-.infinity), 0)
        XCTAssertEqual(ColorFormat.hex(red: .nan, green: .infinity, blue: -.infinity), "#000000")
    }

    /// The contract with the clipboard: whatever this emits must be classified as a colour, or
    /// the history would file a picked colour under "text". The classifier lives in
    /// `ClipboardPasteEngine.swift` (AppKit), so its regex is mirrored in `ClipboardClassifierTests`;
    /// here the same pattern is checked against every channel extreme.
    func testOutputAlwaysMatchesTheClassifiersColourPattern() throws {
        let re = try NSRegularExpression(pattern: #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#)
        var checked = 0
        for r in [0.0, 0.5, 1.0] {
            for g in [0.0, 0.25, 1.0] {
                for b in [0.0, 0.75, 1.0] {
                    let h = ColorFormat.hex(red: r, green: g, blue: b)
                    XCTAssertNotNil(re.firstMatch(in: h, range: NSRange(h.startIndex..., in: h)),
                                    "'\(h)' would not be recognised as a colour by the clipboard classifier")
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 27, "the sweep collapsed")
    }
}
