import Foundation

/// Smart Selection E2 — "the user selected `5 km`; show `≈ 3.11 mi`". Pure.
///
/// Exact definitions, NOT Foundation's `Measurement`: measured on macOS 27, `UnitSpeed.kilometersPerHour` is 0.277778 m/s
/// (exact 1/3.6), `UnitMass.pounds` 0.453592 kg (exact 0.45359237), `UnitVolume.gallons` 3.78541 l (exact 3.785411784) —
/// six significant figures. Invisible at "5 km", visible at large values: 1 000 000 gal would read 3,785,410 l instead of
/// 3,785,412 l, and the panel prints whole numbers above 1 000.
///
/// Rules (each pinned by a test):
/// * The WHOLE selection must be one quantity (optional sign, a number, optional space, a unit) — a sentence that
///   merely contains "5 km" is not converted. ≤ `maxLength` characters.
/// * Each unit converts to ONE counterpart in the other system (metric ↔ US customary), so the result is a single
///   answer, not a table. US gallons/fluid ounces (the ones a selected recipe or spec sheet means); the label says "US".
/// * Temperature needs a degree sign or a word (`72°F`, `30 độ C`, `20 celsius`): a bare `72 F` is not converted.
/// * Number separators: commas followed by groups of exactly three digits group thousands (`1,500` · `12,500,000`),
///   any other single comma is the decimal mark (`1,5`). Dots group thousands only when repeated (`1.500.000`); a
///   single dot is always the decimal mark (`1.500` = 1.5 — the reading Swift and most sources use). When both
///   appear, the LAST one is the decimal mark (`1,234.5` · `1.234,5`). The panel shows the parsed number, so the
///   reading is visible.
enum UnitConversion {

    static let maxLength = 40

    enum Kind: String { case length, mass, temperature, volume, speed }

    enum Unit: String, CaseIterable {
        case millimetre, centimetre, metre, kilometre, inch, foot, yard, mile
        case gram, kilogram, ounce, pound
        case celsius, fahrenheit
        case millilitre, litre, fluidOunceUS, gallonUS
        case kilometrePerHour, milePerHour, metrePerSecond

        var kind: Kind {
            switch self {
            case .millimetre, .centimetre, .metre, .kilometre, .inch, .foot, .yard, .mile: return .length
            case .gram, .kilogram, .ounce, .pound: return .mass
            case .celsius, .fahrenheit: return .temperature
            case .millilitre, .litre, .fluidOunceUS, .gallonUS: return .volume
            case .kilometrePerHour, .milePerHour, .metrePerSecond: return .speed
            }
        }

        /// Shown after the number. Language-neutral symbols, so they stay outside `L10n.t`.
        var symbol: String {
            switch self {
            case .millimetre: return "mm"
            case .centimetre: return "cm"
            case .metre: return "m"
            case .kilometre: return "km"
            case .inch: return "in"
            case .foot: return "ft"
            case .yard: return "yd"
            case .mile: return "mi"
            case .gram: return "g"
            case .kilogram: return "kg"
            case .ounce: return "oz"
            case .pound: return "lb"
            case .celsius: return "°C"
            case .fahrenheit: return "°F"
            case .millilitre: return "ml"
            case .litre: return "l"
            case .fluidOunceUS: return "fl oz (US)"
            case .gallonUS: return "gal (US)"
            case .kilometrePerHour: return "km/h"
            case .milePerHour: return "mph"
            case .metrePerSecond: return "m/s"
            }
        }

        /// The one unit this converts to.
        var counterpart: Unit {
            switch self {
            case .millimetre, .centimetre: return .inch
            case .metre: return .foot
            case .kilometre: return .mile
            case .inch: return .centimetre
            case .foot, .yard: return .metre
            case .mile: return .kilometre
            case .gram: return .ounce
            case .kilogram: return .pound
            case .ounce: return .gram
            case .pound: return .kilogram
            case .celsius: return .fahrenheit
            case .fahrenheit: return .celsius
            case .millilitre: return .fluidOunceUS
            case .litre: return .gallonUS
            case .fluidOunceUS: return .millilitre
            case .gallonUS: return .litre
            case .kilometrePerHour, .metrePerSecond: return .milePerHour
            case .milePerHour: return .kilometrePerHour
            }
        }

        /// Exact factor to the kind's base unit (metre, kilogram, litre, metre per second); nil for temperature,
        /// which is an affine conversion, not a ratio.
        var factorToBase: Double? {
            switch self {
            case .millimetre: return 0.001
            case .centimetre: return 0.01
            case .metre: return 1
            case .kilometre: return 1000
            case .inch: return 0.0254
            case .foot: return 0.3048
            case .yard: return 0.9144
            case .mile: return 1609.344
            case .gram: return 0.001
            case .kilogram: return 1
            case .ounce: return 0.028349523125
            case .pound: return 0.45359237
            case .celsius, .fahrenheit: return nil
            case .millilitre: return 0.001
            case .litre: return 1
            case .fluidOunceUS: return 0.0295735295625
            case .gallonUS: return 3.785411784
            case .kilometrePerHour: return 1 / 3.6
            case .milePerHour: return 0.44704
            case .metrePerSecond: return 1
            }
        }
    }

    struct Quantity: Equatable {
        let value: Double
        let unit: Unit
    }

    struct Result: Equatable {
        let source: Quantity
        let target: Quantity
    }

    /// Spellings accepted after the number, lowercased. Temperature spellings all carry a degree sign or a word.
    static let spellings: [String: Unit] = [
        "mm": .millimetre, "millimetre": .millimetre, "millimeter": .millimetre, "millimetres": .millimetre, "millimeters": .millimetre,
        "cm": .centimetre, "centimetre": .centimetre, "centimeter": .centimetre, "centimetres": .centimetre, "centimeters": .centimetre,
        "m": .metre, "metre": .metre, "meter": .metre, "metres": .metre, "meters": .metre, "mét": .metre,
        "km": .kilometre, "kilometre": .kilometre, "kilometer": .kilometre, "kilometres": .kilometre, "kilometers": .kilometre,
        "cây số": .kilometre,
        "in": .inch, "inch": .inch, "inches": .inch, "\"": .inch, "″": .inch,
        "ft": .foot, "foot": .foot, "feet": .foot, "'": .foot, "′": .foot,
        "yd": .yard, "yard": .yard, "yards": .yard,
        "mi": .mile, "mile": .mile, "miles": .mile, "dặm": .mile,
        "g": .gram, "gram": .gram, "grams": .gram, "gr": .gram,
        "kg": .kilogram, "kilogram": .kilogram, "kilograms": .kilogram, "kgs": .kilogram, "cân": .kilogram,
        "oz": .ounce, "ounce": .ounce, "ounces": .ounce,
        "lb": .pound, "lbs": .pound, "pound": .pound, "pounds": .pound,
        "°c": .celsius, "ºc": .celsius, "℃": .celsius, "celsius": .celsius, "độ c": .celsius, "degrees celsius": .celsius,
        "°f": .fahrenheit, "ºf": .fahrenheit, "℉": .fahrenheit, "fahrenheit": .fahrenheit, "độ f": .fahrenheit,
        "degrees fahrenheit": .fahrenheit,
        "ml": .millilitre, "millilitre": .millilitre, "milliliter": .millilitre, "millilitres": .millilitre, "milliliters": .millilitre,
        "l": .litre, "litre": .litre, "liter": .litre, "litres": .litre, "liters": .litre, "lít": .litre,
        "fl oz": .fluidOunceUS, "fl. oz": .fluidOunceUS, "fl. oz.": .fluidOunceUS, "fluid ounce": .fluidOunceUS, "fluid ounces": .fluidOunceUS,
        "gal": .gallonUS, "gallon": .gallonUS, "gallons": .gallonUS,
        "km/h": .kilometrePerHour, "kmh": .kilometrePerHour, "kph": .kilometrePerHour, "km/giờ": .kilometrePerHour,
        "mph": .milePerHour, "mi/h": .milePerHour,
        "m/s": .metrePerSecond,
    ]

    /// Parse the whole selection as one quantity, or nil.
    static func parse(_ text: String) -> Quantity? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= maxLength else { return nil }
        // Split: leading sign+number, then the rest is the unit (spaces between are optional).
        var numberEnd = t.startIndex
        var i = t.startIndex
        if i < t.endIndex, t[i] == "-" || t[i] == "−" || t[i] == "+" { i = t.index(after: i) }
        var sawDigit = false
        while i < t.endIndex, (t[i].isASCII && t[i].isNumber) || t[i] == "," || t[i] == "." {
            if t[i].isNumber { sawDigit = true }
            i = t.index(after: i)
            numberEnd = i
        }
        guard sawDigit else { return nil }
        let numberText = String(t[t.startIndex..<numberEnd]).replacingOccurrences(of: "−", with: "-")
        let unitText = t[numberEnd...].trimmingCharacters(in: .whitespaces).lowercased()
        guard !unitText.isEmpty, let unit = spellings[unitText], let value = parseNumber(numberText) else { return nil }
        return Quantity(value: value, unit: unit)
    }

    static func convert(_ q: Quantity) -> Quantity {
        let to = q.unit.counterpart
        let v: Double
        switch (q.unit, to) {
        case (.celsius, .fahrenheit): v = q.value * 9 / 5 + 32
        case (.fahrenheit, .celsius): v = (q.value - 32) * 5 / 9
        default: v = q.value * (q.unit.factorToBase ?? 1) / (to.factorToBase ?? 1)
        }
        return Quantity(value: v, unit: to)
    }

    static func convert(_ text: String) -> Result? {
        guard let q = parse(text) else { return nil }
        return Result(source: q, target: convert(q))
    }

    /// The thousands/decimal rule documented on the type. Nil when the digits do not form a number.
    static func parseNumber(_ raw: String) -> Double? {
        var s = raw
        var sign = 1.0
        if let f = s.first, f == "-" || f == "+" { sign = f == "-" ? -1 : 1; s.removeFirst() }
        guard !s.isEmpty, s.first != ",", s.last != ",", s.last != "." else { return nil }
        let commas = s.filter { $0 == "," }.count, dots = s.filter { $0 == "." }.count
        func groupsOfThree(_ sep: Character) -> Bool {
            let parts = s.split(separator: sep, omittingEmptySubsequences: false)
            guard parts.count > 1, let head = parts.first, (1...3).contains(head.count) else { return false }
            return parts.dropFirst().allSatisfy { $0.count == 3 }
        }
        var normalized: String
        switch (commas, dots) {
        case (0, 0):
            normalized = s
        case (_, 0):
            normalized = groupsOfThree(",") ? s.replacingOccurrences(of: ",", with: "")
                : (commas == 1 ? s.replacingOccurrences(of: ",", with: ".") : "")
        case (0, _):
            normalized = (dots > 1 && groupsOfThree(".")) ? s.replacingOccurrences(of: ".", with: "") : (dots == 1 ? s : "")
        default:
            // Both present: the last separator is the decimal mark, the other one groups thousands.
            let lastComma = s.lastIndex(of: ",")!, lastDot = s.lastIndex(of: ".")!
            let decimal: Character = lastComma > lastDot ? "," : "."
            let group: Character = decimal == "," ? "." : ","
            guard s.filter({ $0 == decimal }).count == 1 else { return nil }
            let intPart = s[s.startIndex..<s.lastIndex(of: decimal)!]
            let intParts = intPart.split(separator: group, omittingEmptySubsequences: false)
            guard let head = intParts.first, (1...3).contains(head.count), intParts.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
            normalized = s.replacingOccurrences(of: String(group), with: "").replacingOccurrences(of: String(decimal), with: ".")
        }
        guard !normalized.isEmpty, normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let v = Double(normalized), v.isFinite else { return nil }
        return sign * v
    }

    /// A short number for the panel: 4 significant figures below 1 000, whole numbers above, trailing zeros trimmed,
    /// thousands grouped, decimal mark chosen by the UI language. Never "-0".
    static func format(_ value: Double, decimalComma: Bool) -> String {
        guard value.isFinite else { return "–" }
        let a = abs(value)
        let decimals: Int
        switch a {
        case 0: decimals = 0
        case ..<0.01: decimals = 4
        case ..<1: decimals = 3
        case ..<10: decimals = 2
        case ..<100: decimals = 2
        case ..<1000: decimals = 1
        default: decimals = 0
        }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = decimalComma ? "." : ","
        f.decimalSeparator = decimalComma ? "," : "."
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = decimals
        let rounded = (value * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        return f.string(from: NSNumber(value: rounded == 0 ? 0 : rounded)) ?? "–"
    }
}
