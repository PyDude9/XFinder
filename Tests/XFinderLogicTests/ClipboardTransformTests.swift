import XCTest
import Foundation

final class ClipboardTransformTests: XCTestCase {
    typealias X = ClipboardTransform
    func ok(_ t: X, _ s: String) -> String? { if case .success(let v) = t.apply(to: s) { return v } else { return nil } }
    func fail(_ t: X, _ s: String) -> X.Failure? { if case .failure(let f) = t.apply(to: s) { return f } else { return nil } }

    func testWhitespaceAndLines() {
        XCTAssertEqual(ok(.trim, "  xin chào \n"), "xin chào")
        XCTAssertEqual(ok(.normalizeWhitespace, "a \t b\r\n\n c"), "a b c")
        XCTAssertEqual(ok(.removeLineBreaks, "a\r\nb\n\nc"), "a b c", "CRLF and blank lines")
        XCTAssertEqual(ok(.sortLines, "b\na\r\nc"), "a\nb\nc")
        XCTAssertEqual(ok(.dedupeLines, "a\nb\na\n"), "a\nb")
        XCTAssertEqual(ok(.reverseLines, "1\n2\n3"), "3\n2\n1")
        XCTAssertEqual(X.lines("a\r\nb\n").count, 2, "a trailing newline is not an extra line")
    }

    func testCaseMappingKeepsVietnamese() {
        XCTAssertEqual(ok(.uppercase, "đường phố"), "ĐƯỜNG PHỐ")
        XCTAssertEqual(ok(.lowercase, "HÀ NỘI"), "hà nội")
        XCTAssertEqual(ok(.titleCase, "nguyễn văn a"), "Nguyễn Văn A")
    }

    func testNoChangeIsReportedNotDisguised() {
        XCTAssertEqual(fail(.trim, "clean"), .noChange)
        XCTAssertEqual(fail(.uppercase, "ABC"), .noChange)
        XCTAssertEqual(fail(.dedupeLines, "a\nb"), .noChange)
    }

    func testJSONPrettySortsKeysAndMinifyRoundTrips() {
        let pretty = ok(.jsonPretty, #"{"b":1,"a":[1,2],"url":"https://x/y"}"#)!
        XCTAssertTrue(pretty.range(of: #""a""#)!.lowerBound < pretty.range(of: #""b""#)!.lowerBound, "keys are sorted (order is not preserved by JSONSerialization)")
        XCTAssertTrue(pretty.contains("https://x/y"), "slashes are not escaped")
        XCTAssertEqual(ok(.jsonMinify, pretty), #"{"a":[1,2],"b":1,"url":"https://x/y"}"#)
        XCTAssertEqual(fail(.jsonPretty, "not json"), .notJSON)
        XCTAssertEqual(ok(.jsonPretty, "42"), nil, "a bare scalar pretty-prints to itself ⇒ no change")
        XCTAssertEqual(fail(.jsonPretty, "42"), .noChange)
    }

    func testBase64BothWaysIncludingUnpaddedAndURLSafe() {
        XCTAssertEqual(ok(.base64Encode, "xin chào"), "eGluIGNow6Bv")
        XCTAssertEqual(ok(.base64Decode, "eGluIGNow6Bv"), "xin chào")
        XCTAssertEqual(ok(.base64Decode, "eyJhbGciOiJIUzI1NiJ9"), #"{"alg":"HS256"}"#, "a JWT header has no padding")
        // Mutation C4 stayed GREEN once: every "unpadded" input above is a multiple of 4 characters, so the
        // padding branch was never exercised. These three genuinely need 1, 2 and 1 "=" — Foundation on
        // macOS 27 returns nil for them without the padding (measured).
        XCTAssertEqual(ok(.base64Decode, "aGVsbG8"), "hello", "needs one =")
        XCTAssertEqual(ok(.base64Decode, "YQ"), "a", "needs two =")
        XCTAssertEqual(ok(.base64Decode, "eyJzdWIiOiIxMjM0NTY3ODkwIn0"), #"{"sub":"1234567890"}"#, "a JWT payload, 27 chars")
        XCTAssertEqual(ok(.base64Decode, "Pz8_"), "???", "URL-safe alphabet")
        XCTAssertEqual(fail(.base64Decode, "hello world"), .notBase64)
        XCTAssertEqual(fail(.base64Decode, "/w=="), .notBase64, "valid Base64 but not UTF-8 text")
    }

    func testURLEncodingUsesTheStrictUnreservedSet() {
        XCTAssertEqual(ok(.urlEncode, "a b&c=d?e/f~g"), "a%20b%26c%3Dd%3Fe%2Ff~g")
        XCTAssertEqual(ok(.urlEncode, "Hà Nội"), "H%C3%A0%20N%E1%BB%99i")
        XCTAssertEqual(ok(.urlDecode, "H%C3%A0%20N%E1%BB%99i"), "Hà Nội")
        XCTAssertEqual(fail(.urlDecode, "plain"), .notURLEncoded)
        XCTAssertEqual(fail(.urlDecode, "100%"), .notURLEncoded, "a lone % is not an escape")
    }

    func testCleanURLDelegatesToURLCleaner() {
        XCTAssertEqual(ok(.cleanURL, "https://example.com/p?utm_source=x&id=7"), "https://example.com/p?id=7")
        XCTAssertEqual(fail(.cleanURL, "https://example.com/p?id=7"), .noChange)
        XCTAssertEqual(fail(.cleanURL, "just words"), .notALink)
    }

    func testMD5IsAChecksumString() {
        XCTAssertEqual(ok(.md5, "abc"), "900150983cd24fb0d6963f7d28e17f72")
    }

    func testStats() {
        let s = X.stats("một hai\nba")
        XCTAssertEqual(s.words, 3); XCTAssertEqual(s.characters, 10); XCTAssertEqual(s.lines, 2)
        XCTAssertEqual(X.stats("").lines, 0)
    }

    func testEveryLabelAndFailureIsInTheStoreAndEveryTransformIsInAGroup() throws {
        let store = try L10nFixture.load()
        for t in X.allCases { XCTAssertNotNil(store.entries[t.labelKey], t.labelKey) }
        for f in X.Failure.all { XCTAssertNotNil(store.entries[f.messageKey], f.messageKey) }
        XCTAssertEqual(Set(X.groups.flatMap { $0 }), Set(X.allCases), "a transform exists that no menu shows")
    }
}
