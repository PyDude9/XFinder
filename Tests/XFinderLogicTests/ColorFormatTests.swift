import XCTest
import Foundation

final class ColorFormatTests: XCTestCase {

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
