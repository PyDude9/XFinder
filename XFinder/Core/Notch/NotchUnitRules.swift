import Foundation

/// Pure offline unit-conversion rules for the Dynamic Island Units page.
/// Uses Foundation `Measurement` for length, mass, and temperature only (no currency).
/// No AppKit or SwiftUI dependencies, so every edge case is unit-tested in `Tests/`.
enum NotchUnitRules {

    /// Maximum accepted input magnitude (1e15 keeps full Double integer precision).
    static let maxInputMagnitude: Double = 1e15
    /// Maximum accepted converted output magnitude.
    static let maxOutputMagnitude: Double = 1e18
    /// Values smaller than this in magnitude snap to 0 to eliminate IEEE-754 offset drift (e.g. 273.15 K -> 0 °C).
    static let zeroSnapEpsilon: Double = 1e-12
    /// Default maximum fractional digits when formatting results.
    static let defaultMaxFractionDigits: Int = 6

    // MARK: - Categories & Units

    enum Category: String, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
        case length
        case mass
        case temperature

        var id: String { rawValue }

        var units: [UnitOption] {
            UnitOption.allCases.filter { $0.category == self }
        }

        var defaultPair: (from: UnitOption, to: UnitOption) {
            switch self {
            case .length: return (.kilometer, .mile)
            case .mass: return (.kilogram, .pound)
            case .temperature: return (.celsius, .fahrenheit)
            }
        }
    }

    enum UnitOption: String, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
        // Length
        case millimeter
        case centimeter
        case meter
        case kilometer
        case inch
        case foot
        case yard
        case mile

        // Mass
        case milligram
        case gram
        case kilogram
        case metricTon
        case ounce
        case pound

        // Temperature
        case celsius
        case fahrenheit
        case kelvin

        var id: String { rawValue }

        var category: Category {
            switch self {
            case .millimeter, .centimeter, .meter, .kilometer, .inch, .foot, .yard, .mile:
                return .length
            case .milligram, .gram, .kilogram, .metricTon, .ounce, .pound:
                return .mass
            case .celsius, .fahrenheit, .kelvin:
                return .temperature
            }
        }

        var symbol: String {
            switch self {
            case .millimeter: return "mm"
            case .centimeter: return "cm"
            case .meter: return "m"
            case .kilometer: return "km"
            case .inch: return "in"
            case .foot: return "ft"
            case .yard: return "yd"
            case .mile: return "mi"
            case .milligram: return "mg"
            case .gram: return "g"
            case .kilogram: return "kg"
            case .metricTon: return "t"
            case .ounce: return "oz"
            case .pound: return "lb"
            case .celsius: return "°C"
            case .fahrenheit: return "°F"
            case .kelvin: return "K"
            }
        }

        fileprivate var unitLength: UnitLength? {
            switch self {
            case .millimeter: return .millimeters
            case .centimeter: return .centimeters
            case .meter: return .meters
            case .kilometer: return .kilometers
            case .inch: return .inches
            case .foot: return .feet
            case .yard: return .yards
            case .mile: return .miles
            default: return nil
            }
        }

        fileprivate var unitMass: UnitMass? {
            switch self {
            case .milligram: return .milligrams
            case .gram: return .grams
            case .kilogram: return .kilograms
            case .metricTon: return .metricTons
            case .ounce: return .ounces
            case .pound: return .pounds
            default: return nil
            }
        }

        fileprivate var unitTemperature: UnitTemperature? {
            switch self {
            case .celsius: return .celsius
            case .fahrenheit: return .fahrenheit
            case .kelvin: return .kelvin
            default: return nil
            }
        }
    }

    // MARK: - Evaluation & Errors

    enum ParseResult: Equatable, Sendable {
        case empty
        case incomplete
        case invalid
        case outOfRange
        case value(Double)
    }

    enum ConversionError: Equatable, Sendable {
        case invalidNumber
        case outOfRange
        case incompatibleUnits
    }

    struct ConversionResult: Equatable, Sendable {
        let inputValue: Double
        let outputValue: Double
        let formattedInput: String
        let formattedOutput: String
        let fromUnit: UnitOption
        let toUnit: UnitOption

        /// Text written to the clipboard when the user copies a valid conversion result.
        var copyText: String {
            "\(formattedOutput) \(toUnit.symbol)"
        }
    }

    enum Evaluation: Equatable, Sendable {
        case empty
        case incomplete
        case value(ConversionResult)
        case error(ConversionError)

        var result: ConversionResult? {
            if case .value(let res) = self { return res }
            return nil
        }

        var error: ConversionError? {
            if case .error(let err) = self { return err }
            return nil
        }
    }

    // MARK: - Pure UI State

    struct State: Equatable, Sendable {
        var category: Category
        var fromUnit: UnitOption
        var toUnit: UnitOption
        var inputText: String

        init(
            category: Category = .length,
            fromUnit: UnitOption? = nil,
            toUnit: UnitOption? = nil,
            inputText: String = ""
        ) {
            self.category = category
            let pair = NotchUnitRules.sanitizedPair(for: category, from: fromUnit, to: toUnit)
            self.fromUnit = pair.from
            self.toUnit = pair.to
            self.inputText = inputText
        }

        /// Switch category: resets incompatible/stale units to the new category's default pair while preserving `inputText`.
        mutating func selectCategory(_ newCategory: Category) {
            guard newCategory != category else { return }
            category = newCategory
            let pair = newCategory.defaultPair
            fromUnit = pair.from
            toUnit = pair.to
        }

        /// Update the source unit if it belongs to the active category, preserving `inputText`.
        mutating func selectFromUnit(_ unit: UnitOption) {
            guard unit.category == category else { return }
            fromUnit = unit
        }

        /// Update the destination unit if it belongs to the active category, preserving `inputText`.
        mutating func selectToUnit(_ unit: UnitOption) {
            guard unit.category == category else { return }
            toUnit = unit
        }

        /// Swap source and destination units while preserving `inputText`.
        mutating func swapUnits() {
            let pair = NotchUnitRules.sanitizedPair(for: category, from: fromUnit, to: toUnit)
            fromUnit = pair.to
            toUnit = pair.from
        }

        func evaluate(locale: Locale, maximumFractionDigits: Int = NotchUnitRules.defaultMaxFractionDigits) -> Evaluation {
            NotchUnitRules.convert(
                rawInput: inputText,
                category: category,
                from: fromUnit,
                to: toUnit,
                locale: locale,
                maximumFractionDigits: maximumFractionDigits
            )
        }
    }

    // MARK: - Unit Validation

    /// Returns a valid `(from, to)` pair for `category`, falling back to `category.defaultPair`
    /// whenever either unit is nil or belongs to a different category.
    static func sanitizedPair(
        for category: Category,
        from: UnitOption?,
        to: UnitOption?
    ) -> (from: UnitOption, to: UnitOption) {
        let fallback = category.defaultPair
        guard let from, let to, from.category == category, to.category == category else {
            return fallback
        }
        return (from, to)
    }

    // MARK: - Locale-Aware Strict Number Parsing

    /// Strictly parses a user-entered number according to `locale`'s decimal and grouping separators.
    /// - Distinguishes `.empty`, `.incomplete` (partial typing such as `"-"`, `","`, `"12,"`),
    ///   `.invalid` (extra characters, wrong separator, malformed grouping), and `.outOfRange`.
    static func parseNumber(_ raw: String, locale: Locale) -> ParseResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let decimalSep = locale.decimalSeparator.flatMap { $0.isEmpty ? nil : $0 } ?? "."
        let rawGroupSep = locale.groupingSeparator.flatMap { $0.isEmpty ? nil : $0 }
        let groupSep: String? = (rawGroupSep == decimalSep) ? nil : rawGroupSep

        var body = trimmed
        var isNegative = false

        if body.hasPrefix("-") || body.hasPrefix("\u{2212}") {
            isNegative = true
            body.removeFirst()
        } else if body.hasPrefix("+") {
            body.removeFirst()
        }

        // Sign only (e.g. "-", "+", "−")
        if body.isEmpty {
            return .incomplete
        }

        // Reject any additional sign or internal whitespace (unless whitespace is the locale's grouping separator).
        let groupIsSpace = groupSep.map { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        if body.contains("-") || body.contains("+") || body.contains("\u{2212}") {
            return .invalid
        }

        // Split on the locale's decimal separator.
        let decimalParts = body.components(separatedBy: decimalSep)
        if decimalParts.count > 2 {
            return .invalid
        }

        let intPartRaw = decimalParts[0]
        let hasDecimalSep = decimalParts.count == 2
        let fracPartRaw = hasDecimalSep ? decimalParts[1] : ""

        // Fractional part must contain only ASCII digits (no grouping separators, spaces, or letters).
        if hasDecimalSep && !fracPartRaw.allSatisfy(\.isASCIIDigit) {
            return .invalid
        }

        // Parse & validate integer part (may be empty if user typed ",5" or ".").
        let intDigits: String
        if intPartRaw.isEmpty {
            intDigits = ""
        } else if let groupSep, containsGrouping(intPartRaw, groupSep: groupSep, groupIsSpace: groupIsSpace) {
            guard let stripped = stripValidGrouping(intPartRaw, groupSep: groupSep, groupIsSpace: groupIsSpace) else {
                return .invalid
            }
            intDigits = stripped
        } else {
            guard intPartRaw.allSatisfy(\.isASCIIDigit) else {
                return .invalid
            }
            intDigits = intPartRaw
        }

        // Incomplete typing: ".", "-.", "12.", "1.000,"
        if hasDecimalSep && fracPartRaw.isEmpty {
            return .incomplete
        }
        if intDigits.isEmpty && fracPartRaw.isEmpty {
            return .incomplete
        }

        let normalizedInt = intDigits.isEmpty ? "0" : intDigits
        let normalized = (isNegative ? "-" : "") + normalizedInt + (hasDecimalSep ? ".\(fracPartRaw)" : "")

        guard let parsed = Double(normalized) else {
            return .invalid
        }
        guard parsed.isFinite, abs(parsed) <= maxInputMagnitude else {
            return .outOfRange
        }

        let cleaned = parsed == 0 ? 0.0 : parsed
        return .value(cleaned)
    }

    private static func containsGrouping(_ text: String, groupSep: String, groupIsSpace: Bool) -> Bool {
        if groupIsSpace {
            return text.contains(" ") || text.contains("\u{00A0}") || text.contains("\u{202F}")
        }
        return text.contains(groupSep)
    }

    private static func stripValidGrouping(_ text: String, groupSep: String, groupIsSpace: Bool) -> String? {
        let normalized: String
        if groupIsSpace {
            normalized = text
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{202F}", with: " ")
        } else {
            normalized = text
        }
        let separator = groupIsSpace ? " " : groupSep
        let segments = normalized.components(separatedBy: separator)
        guard segments.count >= 2 else { return nil }

        guard let first = segments.first,
              (1...3).contains(first.count),
              first.allSatisfy(\.isASCIIDigit) else {
            return nil
        }

        for segment in segments.dropFirst() {
            guard segment.count == 3, segment.allSatisfy(\.isASCIIDigit) else {
                return nil
            }
        }
        return segments.joined()
    }

    // MARK: - Conversion via Foundation Measurement

    /// Evaluates a raw string input into a conversion result, incomplete/empty state, or explicit error.
    static func convert(
        rawInput: String,
        category: Category,
        from: UnitOption,
        to: UnitOption,
        locale: Locale,
        maximumFractionDigits: Int = defaultMaxFractionDigits
    ) -> Evaluation {
        guard from.category == category, to.category == category else {
            return .error(.incompatibleUnits)
        }

        switch parseNumber(rawInput, locale: locale) {
        case .empty:
            return .empty
        case .incomplete:
            return .incomplete
        case .invalid:
            return .error(.invalidNumber)
        case .outOfRange:
            return .error(.outOfRange)
        case .value(let inputValue):
            guard let rawOutput = convertValue(inputValue, from: from, to: to) else {
                return .error(.incompatibleUnits)
            }
            guard rawOutput.isFinite, abs(rawOutput) <= maxOutputMagnitude else {
                return .error(.outOfRange)
            }
            let cleanedOutput = normalizeZero(rawOutput)
            let formattedInput = format(inputValue, locale: locale, maximumFractionDigits: maximumFractionDigits)
            let formattedOutput = format(cleanedOutput, locale: locale, maximumFractionDigits: maximumFractionDigits)
            return .value(
                ConversionResult(
                    inputValue: inputValue,
                    outputValue: cleanedOutput,
                    formattedInput: formattedInput,
                    formattedOutput: formattedOutput,
                    fromUnit: from,
                    toUnit: to
                )
            )
        }
    }

    /// Converts a numeric value using Foundation `Measurement`.
    /// Short-circuits identical units to prevent round-trip affine offset drift (e.g. °C -> K -> °C).
    static func convertValue(_ value: Double, from: UnitOption, to: UnitOption) -> Double? {
        guard from.category == to.category else { return nil }
        if from == to { return normalizeZero(value) }

        switch from.category {
        case .length:
            guard let uFrom = from.unitLength, let uTo = to.unitLength else { return nil }
            return Measurement(value: value, unit: uFrom).converted(to: uTo).value
        case .mass:
            guard let uFrom = from.unitMass, let uTo = to.unitMass else { return nil }
            return Measurement(value: value, unit: uFrom).converted(to: uTo).value
        case .temperature:
            guard let uFrom = from.unitTemperature, let uTo = to.unitTemperature else { return nil }
            return Measurement(value: value, unit: uFrom).converted(to: uTo).value
        }
    }

    // MARK: - Rounding, Formatting & Copy

    static func normalizeZero(_ value: Double) -> Double {
        if abs(value) < zeroSnapEpsilon || value == 0 {
            return 0.0
        }
        return value
    }

    /// Formats a finite value for display and copy using `locale`'s decimal separator,
    /// rounding half-up to `maximumFractionDigits`, trimming trailing zeros, and never emitting `"-0"`.
    static func format(
        _ value: Double,
        locale: Locale,
        maximumFractionDigits: Int = defaultMaxFractionDigits
    ) -> String {
        let digits = max(0, maximumFractionDigits)
        let halfStep = pow(10.0, -Double(digits)) * 0.5
        let safeValue: Double = (abs(value) < halfStep || abs(value) < zeroSnapEpsilon || value == 0) ? 0.0 : value

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.roundingMode = .halfUp

        return formatter.string(from: NSNumber(value: safeValue)) ?? String(safeValue)
    }

    /// Returns the clipboard payload when an evaluation has a valid result, or `nil` when copy must be disabled.
    static func copyPayload(for evaluation: Evaluation) -> String? {
        evaluation.result?.copyText
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return scalar.value >= 48 && scalar.value <= 57
    }
}
