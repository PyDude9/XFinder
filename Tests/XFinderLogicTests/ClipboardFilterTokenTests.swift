import XCTest
import Foundation

final class ClipboardFilterTokenTests: XCTestCase {
    typealias T = ClipboardFilterToken

    func testPlainTextIsJustText() {
        XCTAssertEqual(T.parse("  hello   world "), T.Parsed(type: nil, app: nil, text: "hello world"))
        XCTAssertEqual(T.parse(""), T.Parsed(type: nil, app: nil, text: ""))
    }

    func testTypeTokensAndAliases() {
        XCTAssertEqual(T.parse("@image").type, .image)
        XCTAssertEqual(T.parse("@IMG").type, .image, "case-insensitive")
        XCTAssertEqual(T.parse("@ảnh").type, .image)
        XCTAssertEqual(T.parse("@link invoice").type, .link)
        XCTAssertEqual(T.parse("@link invoice").text, "invoice")
        XCTAssertNil(T.parse("@link invoice").app)
    }

    func testUnknownTokenIsAnAppFilter() {
        let p = T.parse("@chrome meeting @image")
        XCTAssertEqual(p.app, "chrome"); XCTAssertEqual(p.type, .image); XCTAssertEqual(p.text, "meeting")
        XCTAssertTrue(T.appMatches(token: "chrome", appName: "Google Chrome", bundleID: nil))
        XCTAssertTrue(T.appMatches(token: "chrome", appName: nil, bundleID: "com.google.Chrome"))
        XCTAssertFalse(T.appMatches(token: "chrome", appName: "Safari", bundleID: "com.apple.Safari"))
        XCTAssertTrue(T.appMatches(token: nil, appName: nil, bundleID: nil), "no token ⇒ no filter")
    }

    func testALoneAtSignIsText() {
        XCTAssertEqual(T.parse("@ you"), T.Parsed(type: nil, app: nil, text: "@ you"))
        XCTAssertEqual(T.parse("mail@example.com").text, "mail@example.com", "an @ inside a word is not a token")
    }

    func testTheLastTokenOfAKindWins() {
        XCTAssertEqual(T.parse("@image @link").type, .link)
        XCTAssertEqual(T.parse("@safari @chrome").app, "chrome")
    }
}
