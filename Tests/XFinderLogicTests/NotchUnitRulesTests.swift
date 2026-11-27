import XCTest
import Foundation

/// Pure logic tests for `NotchUnitRules`: offline Foundation Measurement conversions,
/// locale-aware number parsing, negative/zero, incomplete inputs, trailing/extra characters,
/// out-of-range overflow, stale units across category changes, same-unit identity,
/// affine temperature offsets, rounding, and copy payload gating.
final class NotchUnitRulesTests: XCTestCase {
    private typealias R = NotchUnitRules
    private let enUS = Locale(identifier: "en_US")
    private let viVN = Locale(identifier: "vi_VN")

    // MARK: - Negative numbers and zero

    func testZeroAndNegativeZeroNormalizeCleanly() {
        let zeroLen = R.convert(rawInput: "0", category: .length, from: .meter, to: .kilometer, locale: enUS)
        XCTAssertEqual(zeroLen.result?.outputValue, 0)
        XCTAssertEqual(zeroLen.result?.formattedOutput, "0")

        let negZeroLen = R.convert(rawInput: "-0", category: .length, from: .meter, to: .centimeter, locale: enUS)
        XCTAssertEqual(negZeroLen.result?.outputValue, 0)
        XCTAssertEqual(negZeroLen.result?.formattedOutput, "0", "must never emit -0")

        let negZeroMass = R.convert(rawInput: "-0,0", category: .mass, from: .kilogram, to: .gram, locale: viVN)
        XCTAssertEqual(negZeroMass.result?.outputValue, 0)
        XCTAssertEqual(negZeroMass.result?.formattedOutput, "0")
    }

    func testNegativeValuesAcrossCategories() {
        let negLength = R.convert(rawInput: "-12.5", category: .length, from: .meter, to: .centimeter, locale: enUS)
        XCTAssertEqual(negLength.result?.outputValue ?? .nan, -1250, accuracy: 1e-9)
        XCTAssertEqual(negLength.result?.formattedOutput, "-1250")

        let negMass = R.convert(rawInput: "-2,5", category: .mass, from: .kilogram, to: .gram, locale: viVN)
        XCTAssertEqual(negMass.result?.outputValue ?? .nan, -2500, accuracy: 1e-9)
        XCTAssertEqual(negMass.result?.formattedOutput, "-2500")

        let unicodeMinus = R.convert(rawInput: "\u{2212}40", category: .temperature, from: .celsius, to: .fahrenheit, locale: enUS)
        XCTAssertEqual(unicodeMinus.result?.outputValue ?? .nan, -40, accuracy: 1e-9)
        XCTAssertEqual(unicodeMinus.result?.formattedOutput, "-40")
    }

    // MARK: - Locale decimal and grouping separators

    func testLocaleDecimalAndGroupingParsing() {
        // en_US: dot decimal, comma grouping
        let enDecimal = R.convert(rawInput: "1,234.5", category: .length, from: .kilometer, to: .meter, locale: enUS)
        XCTAssertEqual(enDecimal.result?.outputValue ?? .nan, 1_234_500, accuracy: 1e-6)
        XCTAssertEqual(enDecimal.result?.formattedOutput, "1234500")

        let enLeadingDot = R.convert(rawInput: ".5", category: .mass, from: .kilogram, to: .gram, locale: enUS)
        XCTAssertEqual(enLeadingDot.result?.outputValue ?? .nan, 500, accuracy: 1e-9)

        // vi_VN: comma decimal, dot grouping
        let viDecimal = R.convert(rawInput: "1.234,5", category: .length, from: .kilometer, to: .meter, locale: viVN)
        XCTAssertEqual(viDecimal.result?.outputValue ?? .nan, 1_234_500, accuracy: 1e-6)
        XCTAssertEqual(viDecimal.result?.formattedOutput, "1234500")

        let viFraction = R.convert(rawInput: "1", category: .length, from: .inch, to: .centimeter, locale: viVN)
        XCTAssertEqual(viFraction.result?.formattedOutput, "2,54", "vi_VN formats decimal with comma")

        // Misplaced separator in vi_VN ("12.5" is NOT 125 and NOT 12.5)
        let wrongSepVi = R.convert(rawInput: "12.5", category: .length, from: .meter, to: .centimeter, locale: viVN)
        XCTAssertEqual(wrongSepVi, .error(.invalidNumber))

        // Misplaced separator in en_US ("12,5" is NOT 125 and NOT 12.5)
        let wrongSepEn = R.convert(rawInput: "12,5", category: .length, from: .meter, to: .centimeter, locale: enUS)
        XCTAssertEqual(wrongSepEn, .error(.invalidNumber))
    }

    // MARK: - Incomplete input (chuỗi nhập dở)

    func testEmptyAndIncompleteInputsDoNotEmitErrorAndDisableCopy() {
        for raw in ["", "   ", "\t\n"] {
            let eval = R.convert(rawInput: raw, category: .length, from: .meter, to: .kilometer, locale: enUS)
            XCTAssertEqual(eval, .empty, "raw=\(raw.debugDescription)")
            XCTAssertNil(R.copyPayload(for: eval))
        }

        for raw in ["-", "+", "\u{2212}", ".", "-.", "+.", "12.", "-0.", "1,000."] {
            let eval = R.convert(rawInput: raw, category: .length, from: .meter, to: .kilometer, locale: enUS)
            XCTAssertEqual(eval, .incomplete, "enUS incomplete raw=\(raw.debugDescription)")
            XCTAssertNil(R.copyPayload(for: eval))
        }

        for raw in [",", "-,", "12,", "1.000,"] {
            let eval = R.convert(rawInput: raw, category: .length, from: .meter, to: .kilometer, locale: viVN)
            XCTAssertEqual(eval, .incomplete, "viVN incomplete raw=\(raw.debugDescription)")
            XCTAssertNil(R.copyPayload(for: eval))
        }
    }

    // MARK: - Extra / trailing characters (ký tự dư)

    func testExtraCharactersAndMalformedNumbersFailWithInvalidNumber() {
        let badEn = ["12abc", "100 m", "12.3.4", "1,,000", "1,00", "--5", "5-", "12 34", "$10", "1e5"]
        for raw in badEn {
            let eval = R.convert(rawInput: raw, category: .length, from: .meter, to: .kilometer, locale: enUS)
            XCTAssertEqual(eval, .error(.invalidNumber), "expected invalid for \(raw.debugDescription)")
            XCTAssertNil(R.copyPayload(for: eval))
        }

        let badVi = ["12,3,4", "1..000", "100 km", "12,5abc"]
        for raw in badVi {
            let eval = R.convert(rawInput: raw, category: .length, from: .meter, to: .kilometer, locale: viVN)
            XCTAssertEqual(eval, .error(.invalidNumber), "expected invalid in vi_VN for \(raw.debugDescription)")
            XCTAssertNil(R.copyPayload(for: eval))
        }
    }

    // MARK: - Out of range / overflow (số vượt giới hạn)

    func testOutOfRangeInputAndOutputOverflow() {
        // Exceeds maxInputMagnitude (1e15)
        let tooBigInput = R.convert(rawInput: "10000000000000000", category: .length, from: .meter, to: .kilometer, locale: enUS)
        XCTAssertEqual(tooBigInput, .error(.outOfRange))
        XCTAssertNil(R.copyPayload(for: tooBigInput))

        // Exceeds Double.greatestFiniteMagnitude (parses to infinity)
        let hugeDigits = String(repeating: "9", count: 320)
        let infInput = R.convert(rawInput: hugeDigits, category: .length, from: .meter, to: .kilometer, locale: enUS)
        XCTAssertEqual(infInput, .error(.outOfRange))

        // Input within limit (1e15 km) but output overflows maxOutputMagnitude (1e21 mm > 1e18)
        let outputOverflow = R.convert(rawInput: "1000000000000000", category: .length, from: .kilometer, to: .millimeter, locale: enUS)
        XCTAssertEqual(outputOverflow, .error(.outOfRange))
        XCTAssertNil(R.copyPayload(for: outputOverflow))
    }

    // MARK: - Category switch with stale units (đổi nhóm với đơn vị cũ) & preserving input

    func testSwitchingCategoryResetsStaleUnitsAndPreservesInputText() {
        var state = R.State(category: .length, fromUnit: .kilometer, toUnit: .mile, inputText: "42,5")
        state.selectCategory(.temperature)
        XCTAssertEqual(state.category, .temperature)
        XCTAssertEqual(state.fromUnit, .celsius)
        XCTAssertEqual(state.toUnit, .fahrenheit)
        XCTAssertEqual(state.inputText, "42,5", "input text must be preserved across category switch")

        // Swapping units also preserves input text
        state.swapUnits()
        XCTAssertEqual(state.fromUnit, .fahrenheit)
        XCTAssertEqual(state.toUnit, .celsius)
        XCTAssertEqual(state.inputText, "42,5", "input text must be preserved across swap")

        // Ignoring out-of-category unit selection
        state.selectFromUnit(.kilogram)
        XCTAssertEqual(state.fromUnit, .fahrenheit, "stale unit from another category must be ignored")
    }

    func testDirectConvertRejectsIncompatibleCategoryAndUnits() {
        let stale = R.convert(rawInput: "10", category: .temperature, from: .kilometer, to: .celsius, locale: enUS)
        XCTAssertEqual(stale, .error(.incompatibleUnits))
        XCTAssertNil(R.copyPayload(for: stale))

        let cross = R.convert(rawInput: "10", category: .mass, from: .kilogram, to: .meter, locale: enUS)
        XCTAssertEqual(cross, .error(.incompatibleUnits))

        let sanitized = R.sanitizedPair(for: .mass, from: .kilometer, to: .mile)
        XCTAssertEqual(sanitized.from, .kilogram)
        XCTAssertEqual(sanitized.to, .pound)
    }

    // MARK: - Same unit identity (cùng đơn vị)

    func testSameUnitReturnsExactValueWithoutOffsetDrift() {
        let sameTemp = R.convert(rawInput: "-40", category: .temperature, from: .celsius, to: .celsius, locale: enUS)
        XCTAssertEqual(sameTemp.result?.outputValue, -40)
        XCTAssertEqual(sameTemp.result?.formattedOutput, "-40")

        let sameLen = R.convert(rawInput: "123.456789", category: .length, from: .meter, to: .meter, locale: enUS)
        XCTAssertEqual(sameLen.result?.outputValue, 123.456789)
        XCTAssertEqual(sameLen.result?.formattedOutput, "123.456789")
    }

    // MARK: - Temperature with affine offset (tính nhiệt độ có độ lệch)

    func testTemperatureAffineOffsets() {
        let cToF0 = R.convert(rawInput: "0", category: .temperature, from: .celsius, to: .fahrenheit, locale: enUS)
        XCTAssertEqual(cToF0.result?.outputValue ?? .nan, 32, accuracy: 1e-9)
        XCTAssertEqual(cToF0.result?.formattedOutput, "32")

        let cToF100 = R.convert(rawInput: "100", category: .temperature, from: .celsius, to: .fahrenheit, locale: enUS)
        XCTAssertEqual(cToF100.result?.outputValue ?? .nan, 212, accuracy: 1e-9)
        XCTAssertEqual(cToF100.result?.formattedOutput, "212")

        let fToC32 = R.convert(rawInput: "32", category: .temperature, from: .fahrenheit, to: .celsius, locale: enUS)
        XCTAssertEqual(fToC32.result?.outputValue ?? .nan, 0, accuracy: 1e-9)
        XCTAssertEqual(fToC32.result?.formattedOutput, "0")

        let kToC = R.convert(rawInput: "273.15", category: .temperature, from: .kelvin, to: .celsius, locale: enUS)
        XCTAssertEqual(kToC.result?.outputValue, 0)
        XCTAssertEqual(kToC.result?.formattedOutput, "0", "273.15 K must snap to exact 0 °C without IEEE drift")

        let cToK = R.convert(rawInput: "-273.15", category: .temperature, from: .celsius, to: .kelvin, locale: enUS)
        XCTAssertEqual(cToK.result?.outputValue, 0)
        XCTAssertEqual(cToK.result?.formattedOutput, "0")
    }

    // MARK: - Rounding & copy payload (làm tròn & thao tác sao chép)

    func testRoundingAndTrimmingTrailingZeros() {
        // 100 °F -> 37.777777... °C rounds half-up to 6 digits
        let f100 = R.convert(rawInput: "100", category: .temperature, from: .fahrenheit, to: .celsius, locale: enUS)
        XCTAssertEqual(f100.result?.formattedOutput, "37.777778")

        // Custom fraction digits
        XCTAssertEqual(R.format(1.23456, locale: enUS, maximumFractionDigits: 2), "1.23")
        XCTAssertEqual(R.format(1.235, locale: enUS, maximumFractionDigits: 2), "1.24")
        XCTAssertEqual(R.format(1.2000, locale: enUS, maximumFractionDigits: 4), "1.2")
        XCTAssertEqual(R.format(-0.0000001, locale: enUS, maximumFractionDigits: 4), "0", "tiny negative rounding to zero never emits -0")
        XCTAssertEqual(R.format(1.235, locale: viVN, maximumFractionDigits: 2), "1,24")
    }

    func testCopyPayloadMatchesResultAndIsNilWithoutResult() {
        let validEn = R.convert(rawInput: "100", category: .temperature, from: .celsius, to: .fahrenheit, locale: enUS)
        XCTAssertEqual(R.copyPayload(for: validEn), "212 °F")

        let validVi = R.convert(rawInput: "1", category: .length, from: .inch, to: .centimeter, locale: viVN)
        XCTAssertEqual(R.copyPayload(for: validVi), "2,54 cm")

        XCTAssertNil(R.copyPayload(for: .empty))
        XCTAssertNil(R.copyPayload(for: .incomplete))
        XCTAssertNil(R.copyPayload(for: .error(.invalidNumber)))
        XCTAssertNil(R.copyPayload(for: .error(.outOfRange)))
        XCTAssertNil(R.copyPayload(for: .error(.incompatibleUnits)))
    }

    // MARK: - Scope check (no currency)

    func testOnlyLengthMassAndTemperatureCategoriesExist() {
        XCTAssertEqual(R.Category.allCases, [.length, .mass, .temperature])
    }
}
