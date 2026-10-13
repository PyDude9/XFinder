import Foundation

/// Arithmetic over text the user typed or selected, evaluated by a small recursive-descent parser that can only
/// return a number or a failure — it never raises.
///
/// Why it exists (measured 2026-10-13): `Calculator` handed every query that matched `^[\d\s+\-*/.()]+$` to
/// `NSExpression(format:)`. That initializer raises an Objective-C exception on malformed input, and Swift cannot
/// catch it — the process aborts (`libc++abi: terminating due to uncaught exception of type NSException`). The probe
/// aborted on `1+`, `(1+2` and `1..2+3`; all three pass the regex, so typing `1+` into ⌘K and pausing for the 0.2 s
/// debounce killed XFinder. It also answered `1/0` with **0**, a number it made up.
///
/// Grammar (left-associative except `^`):
///   expr    := term (('+' | '-') term)*
///   term    := unary (('*' | '/' | '×' | '÷') unary)*
///   unary   := ('+' | '-') unary | power
///   power   := primary (('^' | '**') unary)?
///   primary := number | '(' expr ')'
///   number  := digits ['.' digits] | '.' digits
enum SafeArithmetic {

    enum Failure: Error, Equatable {
        case empty
        case tooLong
        case tooDeep
        case unexpected(Character)
        case unexpectedEnd
        case divisionByZero
        case notFinite
    }

    /// Longer input is refused outright: nobody selects a 300-character formula, and it bounds the work.
    static let maxLength = 256
    /// Nesting bound so `((((…` cannot exhaust the stack.
    static let maxDepth = 64

    static func evaluate(_ text: String) -> Double? {
        if case .success(let v) = parse(text) { return v }
        return nil
    }

    static func parse(_ text: String) -> Result<Double, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maxLength else { return .failure(.tooLong) }
        var p = Parser(chars: Array(trimmed))
        do {
            let v = try p.expression(depth: 0)
            p.skipSpaces()
            if let c = p.peek { throw Failure.unexpected(c) }
            guard v.isFinite else { throw Failure.notFinite }
            return .success(v == 0 ? 0 : v)          // never "-0"
        } catch let f as Failure {
            return .failure(f)
        } catch {
            return .failure(.unexpectedEnd)
        }
    }

    private struct Parser {
        let chars: [Character]
        var i = 0

        var peek: Character? { i < chars.count ? chars[i] : nil }

        mutating func skipSpaces() { while let c = peek, c == " " || c == "\t" { i += 1 } }

        mutating func expression(depth: Int) throws -> Double {
            var v = try term(depth: depth)
            while true {
                skipSpaces()
                guard let c = peek, c == "+" || c == "-" else { return v }
                i += 1
                let r = try term(depth: depth)
                v = c == "+" ? v + r : v - r
            }
        }

        mutating func term(depth: Int) throws -> Double {
            var v = try unary(depth: depth)
            while true {
                skipSpaces()
                guard let c = peek, c == "*" || c == "/" || c == "×" || c == "÷" else { return v }
                // `**` is power, handled one level down; leave it alone here.
                if c == "*", i + 1 < chars.count, chars[i + 1] == "*" { return v }
                i += 1
                let r = try unary(depth: depth)
                if c == "/" || c == "÷" {
                    guard r != 0 else { throw Failure.divisionByZero }
                    v /= r
                } else {
                    v *= r
                }
            }
        }

        mutating func unary(depth: Int) throws -> Double {
            guard depth < SafeArithmetic.maxDepth else { throw Failure.tooDeep }
            skipSpaces()
            if let c = peek, c == "+" || c == "-" {
                i += 1
                let v = try unary(depth: depth + 1)
                return c == "-" ? -v : v
            }
            return try power(depth: depth)
        }

        mutating func power(depth: Int) throws -> Double {
            let base = try primary(depth: depth)
            skipSpaces()
            if peek == "^" {
                i += 1
            } else if peek == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
            } else {
                return base
            }
            let exponent = try unary(depth: depth + 1)
            let v = Foundation.pow(base, exponent)
            guard v.isFinite else { throw Failure.notFinite }
            return v
        }

        mutating func primary(depth: Int) throws -> Double {
            skipSpaces()
            guard let c = peek else { throw Failure.unexpectedEnd }
            if c == "(" {
                i += 1
                let v = try expression(depth: depth + 1)
                skipSpaces()
                guard peek == ")" else {
                    if let d = peek { throw Failure.unexpected(d) }
                    throw Failure.unexpectedEnd
                }
                i += 1
                return v
            }
            return try number()
        }

        mutating func number() throws -> Double {
            let start = i
            var sawDigit = false, sawDot = false
            while let c = peek {
                if c.isASCII, c.isNumber { sawDigit = true; i += 1 }
                else if c == ".", !sawDot { sawDot = true; i += 1 }
                else { break }
            }
            guard sawDigit, let v = Double(String(chars[start..<i])) else {
                if let c = peek { throw Failure.unexpected(c) }
                throw Failure.unexpectedEnd
            }
            return v
        }
    }
}
