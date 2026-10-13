import XCTest
import Foundation

/// The arithmetic behind ⌘K / Tìm nhanh and Smart Selection. Replaced `NSExpression(format:)`, which aborted the
/// process on malformed input (measured: `1+`, `(1+2`, `1..2+3`) and answered `1/0` with 0.
final class SafeArithmeticTests: XCTestCase {
    typealias A = SafeArithmetic

    func testOrdinaryArithmetic() {
        XCTAssertEqual(A.evaluate("2+3"), 5)
        XCTAssertEqual(A.evaluate("2 + 3 * 4"), 14, "precedence")
        XCTAssertEqual(A.evaluate("(2 + 3) * 4"), 20)
        XCTAssertEqual(A.evaluate("10 - 4 - 3"), 3, "left-associative minus")
        XCTAssertEqual(A.evaluate("100 / 10 / 2"), 5, "left-associative divide")
        XCTAssertEqual(A.evaluate("7 / 2"), 3.5)
        XCTAssertEqual(A.evaluate("-3 + 5"), 2)
        XCTAssertEqual(A.evaluate("2 * -3"), -6)
        XCTAssertEqual(A.evaluate(".5 + .25"), 0.75)
        XCTAssertEqual(A.evaluate("3 × 4 ÷ 2"), 6, "× and ÷ as selected from prose")
    }

    func testPowerIsRightAssociativeAndBindsTighterThanUnaryMinus() {
        XCTAssertEqual(A.evaluate("2^10"), 1024)
        XCTAssertEqual(A.evaluate("2**3"), 8, "the ** form NSExpression accepted keeps working")
        XCTAssertEqual(A.evaluate("2^3^2"), 512, "2^(3^2), not (2^3)^2 = 64")
        XCTAssertEqual(A.evaluate("-2^2"), -4, "-(2^2)")
        XCTAssertEqual(A.evaluate("2^-1"), 0.5)
    }

    /// Every input that aborted the app through NSExpression, plus the obvious neighbours: a failure, never a throw.
    func testMalformedInputFailsInsteadOfAborting() {
        for bad in ["1+", "(1+2", "1..2+3", "+", "()", "1 2", "2*/3", ")", "1+(", "3)", "..", "1.2.3", "abc", "2 + x"] {
            XCTAssertNil(A.evaluate(bad), bad)
        }
        XCTAssertEqual(A.parse(""), .failure(.empty))
        XCTAssertEqual(A.parse("1+"), .failure(.unexpectedEnd))
        XCTAssertEqual(A.parse("1..2"), .failure(.unexpected(".")))
    }

    func testNoInventedNumbers() {
        XCTAssertEqual(A.parse("1/0"), .failure(.divisionByZero), "NSExpression answered 0")
        XCTAssertEqual(A.parse("1/(2-2)"), .failure(.divisionByZero))
        XCTAssertEqual(A.parse("(-8)^0.5"), .failure(.notFinite), "NaN is not a result")
        XCTAssertEqual(A.parse("10^400"), .failure(.notFinite))
        XCTAssertEqual(A.evaluate("0 * -1"), 0)
        XCTAssertEqual(A.evaluate("0 * -1").map { $0.sign }, .plus, "never shows -0")
    }

    func testBoundsStopHostileInput() {
        XCTAssertEqual(A.parse(String(repeating: "1+", count: 200) + "1"), .failure(.tooLong))
        XCTAssertEqual(A.parse(String(repeating: "(", count: 80) + "1" + String(repeating: ")", count: 80)), .failure(.tooDeep))
        XCTAssertEqual(A.parse(String(repeating: "-", count: 100) + "1"), .failure(.tooDeep))
        XCTAssertEqual(A.evaluate(String(repeating: "(", count: 20) + "1" + String(repeating: ")", count: 20)), 1)
    }

    /// Gate: the exception-raising initializer must not come back anywhere in the app.
    func testNoNSExpressionFormatAnywhereInTheApp() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = root.appendingPathComponent("XFinder")
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 100, "the walk must see the app's sources — or this gate is blind")
        for f in files {
            let code = try String(contentsOf: f, encoding: .utf8).split(separator: "\n")
                .map { line -> Substring in line.range(of: "//").map { line[..<$0.lowerBound] } ?? line[...] }
                .joined(separator: "\n")
            XCTAssertFalse(code.contains("NSExpression(format:"), "\(f.lastPathComponent) uses NSExpression(format:), which aborts on malformed input")
        }
    }
}
