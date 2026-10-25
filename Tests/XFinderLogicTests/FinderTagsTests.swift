import XCTest
@testable import XFinderLogicTests

/// XF-T30 W2 — `FinderTags`: the `com.apple.metadata:_kMDItemUserTags` stored-string format ("Name\n<colour>") and its
/// binary-plist xattr payload (an array of those strings).
final class FinderTagsTests: XCTestCase {

    // MARK: - parse

    func testParseNameOnlyHasNoColor() {
        let tag = FinderTags.parse("Work")
        XCTAssertEqual(tag, FinderTag(name: "Work", color: .none))
    }

    func testParseNameWithColorSuffix() {
        let tag = FinderTags.parse("Work\n6")
        XCTAssertEqual(tag, FinderTag(name: "Work", color: .red))
    }

    func testParseAllSevenColors() {
        for color in TagColor.allCases {
            let raw = color == .none ? "Tag" : "Tag\n\(color.rawValue)"
            XCTAssertEqual(FinderTags.parse(raw).color, color, "color \(color)")
        }
    }

    func testParseColorZeroIsExplicitNoColorSuffix() {
        // "Tag\n0" is a well-formed (if redundant) explicit "no colour" suffix, distinct from a bare "Tag" with no
        // newline at all — both must parse to the SAME `.none` tag.
        XCTAssertEqual(FinderTags.parse("Tag\n0"), FinderTag(name: "Tag", color: .none))
    }

    func testParseOutOfRangeColorNumberKeepsWholeStringAsName() {
        // 8 is one past `.orange` (7) — not a valid TagColor, so this is NOT a colour suffix; the "\n8" is part of
        // the name verbatim (Finder would never write this, but a corrupted/foreign xattr might).
        let tag = FinderTags.parse("Work\n8")
        XCTAssertEqual(tag, FinderTag(name: "Work\n8", color: .none))
    }

    func testParseNonNumericSuffixKeepsWholeStringAsName() {
        let tag = FinderTags.parse("Work\nred")
        XCTAssertEqual(tag, FinderTag(name: "Work\nred", color: .none))
    }

    func testParseTrailingNewlineWithNoDigitsKeepsWholeStringAsName() {
        let tag = FinderTags.parse("Work\n")
        XCTAssertEqual(tag, FinderTag(name: "Work\n", color: .none))
    }

    func testParseNameContainingLiteralNewlineButNoColorSuffixAtEnd() {
        // A tag name itself may contain "\n" with real Finder content after it that is not a plausible colour digit —
        // must not be mistaken for a (very wrong) colour suffix and must not drop any text.
        let tag = FinderTags.parse("Line one\nLine two")
        XCTAssertEqual(tag, FinderTag(name: "Line one\nLine two", color: .none))
    }

    func testParseEmptyStringHasEmptyNameAndNoColor() {
        XCTAssertEqual(FinderTags.parse(""), FinderTag(name: "", color: .none))
    }

    func testParseMultipleDigitSuffixOutOfRange() {
        let tag = FinderTags.parse("Work\n42")
        XCTAssertEqual(tag, FinderTag(name: "Work\n42", color: .none))
    }

    func testParseNegativeLookingSuffixIsNotANumberKeepsWholeStringAsName() {
        // "-1" contains a non-digit ('-'), so `allSatisfy(\.isNumber)` rejects it as a colour suffix outright.
        let tag = FinderTags.parse("Work\n-1")
        XCTAssertEqual(tag, FinderTag(name: "Work\n-1", color: .none))
    }

    // MARK: - encode

    func testEncodeNoColorHasNoSuffix() {
        XCTAssertEqual(FinderTags.encode(FinderTag(name: "Work", color: .none)), "Work")
    }

    func testEncodeWithColorAppendsSuffix() {
        XCTAssertEqual(FinderTags.encode(FinderTag(name: "Work", color: .red)), "Work\n6")
    }

    func testEncodeAllColorsRoundTripThroughParse() {
        for color in TagColor.allCases {
            let tag = FinderTag(name: "Project", color: color)
            XCTAssertEqual(FinderTags.parse(FinderTags.encode(tag)), tag, "color \(color)")
        }
    }

    func testEncodeEmptyNameWithColor() {
        XCTAssertEqual(FinderTags.encode(FinderTag(name: "", color: .blue)), "\n4")
    }

    // MARK: - decodeXattr / encodeXattr

    func testEncodeDecodeXattrRoundTrip() {
        let tags = [FinderTag(name: "Work", color: .red), FinderTag(name: "Personal", color: .none)]
        let data = FinderTags.encodeXattr(tags)
        XCTAssertEqual(FinderTags.decodeXattr(data), tags)
    }

    func testEncodeDecodeXattrRoundTripEmptyArray() {
        let data = FinderTags.encodeXattr([])
        XCTAssertEqual(FinderTags.decodeXattr(data), [])
    }

    func testEncodeDecodeXattrRoundTripAllSevenColorsAndUncolored() {
        let tags = TagColor.allCases.map { FinderTag(name: "Tag \($0.rawValue)", color: $0) }
        let data = FinderTags.encodeXattr(tags)
        XCTAssertEqual(FinderTags.decodeXattr(data), tags)
    }

    func testDecodeXattrEmptyDataIsEmpty() {
        XCTAssertEqual(FinderTags.decodeXattr(Data()), [])
    }

    func testDecodeXattrGarbageBytesIsEmpty() {
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02])
        XCTAssertEqual(FinderTags.decodeXattr(garbage), [])
    }

    func testDecodeXattrTruncatedValidPlistIsEmpty() {
        let full = FinderTags.encodeXattr([FinderTag(name: "Work", color: .red)])
        let truncated = full.prefix(full.count / 2)
        XCTAssertEqual(FinderTags.decodeXattr(Data(truncated)), [])
    }

    func testDecodeXattrWellFormedPlistButNotAnArrayIsEmpty() {
        // A binary plist whose top-level value is a DICTIONARY, not an array of strings — same xattr key, wrong
        // shape (a foreign writer, or a different metadata attribute entirely).
        let dict = ["not": "an array"]
        let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        XCTAssertEqual(FinderTags.decodeXattr(data), [])
    }

    func testDecodeXattrArrayOfNonStringsIsEmpty() {
        let numbers = [1, 2, 3]
        let data = try! PropertyListSerialization.data(fromPropertyList: numbers, format: .binary, options: 0)
        XCTAssertEqual(FinderTags.decodeXattr(data), [])
    }

    func testDecodeXattrXMLFormatPlistAlsoDecodes() {
        // Finder writes binary plists, but `decodeXattr` should not be needlessly strict about which plist
        // serialization format produced the bytes — `PropertyListSerialization` autodetects either.
        let strings = ["Work\n6", "Personal"]
        let data = try! PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
        XCTAssertEqual(FinderTags.decodeXattr(data), [FinderTag(name: "Work", color: .red), FinderTag(name: "Personal", color: .none)])
    }

    func testEncodeXattrPreservesTagOrder() {
        let tags = [FinderTag(name: "Z", color: .none), FinderTag(name: "A", color: .none), FinderTag(name: "M", color: .none)]
        let data = FinderTags.encodeXattr(tags)
        XCTAssertEqual(FinderTags.decodeXattr(data).map(\.name), ["Z", "A", "M"])
    }

    // MARK: - TagColor.titleKey

    func testTagColorTitleKeysAreAllDistinct() {
        let keys = TagColor.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
