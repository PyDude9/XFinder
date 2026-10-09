import XCTest
import Foundation

final class URLCleanerTests: XCTestCase {

    private func clean(_ s: String) -> URLCleaner.Result? { URLCleaner.clean(s) }

    // MARK: - What it removes

    func testStripsUTMAndClickIDsKeepsEverythingElseInOrder() {
        let r = clean("https://example.com/post?id=7&utm_source=news&page=2&fbclid=AbC123&utm_medium=x#top")
        XCTAssertEqual(r?.cleaned, "https://example.com/post?id=7&page=2#top",
                       "other params keep their order, the fragment is untouched")
        XCTAssertEqual(r?.removed, ["utm_source", "fbclid", "utm_medium"], "reported in the order they appeared")
        XCTAssertEqual(r?.host, "example.com")
    }

    func testDropsTheQuestionMarkWhenNothingIsLeft() {
        XCTAssertEqual(clean("https://example.com/a?utm_source=x&gclid=1")?.cleaned, "https://example.com/a")
        XCTAssertEqual(clean("https://example.com/a?utm_source=x#frag")?.cleaned, "https://example.com/a#frag",
                       "an emptied query must not leave a dangling '?' before the fragment")
    }

    func testParameterNamesMatchCaseInsensitivelyAndPercentEncoded() {
        XCTAssertEqual(clean("https://example.com/?UTM_Source=a&q=1")?.cleaned, "https://example.com/?q=1")
        XCTAssertEqual(clean("https://example.com/?utm%5Fsource=a&q=1")?.cleaned, "https://example.com/?q=1",
                       "a percent-encoded tracking name is still tracking")
    }

    func testPreservesPercentEncodingOfKeptParameters() {
        XCTAssertEqual(clean("https://example.com/s?q=a%20b%26c&utm_term=z")?.cleaned,
                       "https://example.com/s?q=a%20b%26c",
                       "kept parameters must not be decoded or re-encoded")
    }

    // MARK: - What it must leave alone (the cost of a wrong rewrite is a broken link)

    func testReturnsNilWhenThereIsNothingToRemove() {
        XCTAssertNil(clean("https://example.com/a?q=swift&page=2&ref=nav"), "functional params untouched")
        XCTAssertNil(clean("https://example.com/a"), "no query at all")
        XCTAssertNil(clean("https://example.com/a?"), "empty query, nothing on the list")
    }

    func testOnlyActsOnASingleHTTPLink() {
        XCTAssertNil(clean("see https://example.com/?utm_source=x for details"), "prose containing a link")
        XCTAssertNil(clean("https://example.com/?utm_source=x https://other.com/?fbclid=1"), "two links")
        XCTAssertNil(clean("https://example.com/?utm_source=x\nhttps://other.com/"), "newline inside")
        XCTAssertNil(clean("mailto:a@b.com?subject=hi&utm_source=x"), "not http(s)")
        XCTAssertNil(clean("file:///tmp/a?utm_source=x"), "not http(s)")
        XCTAssertNil(clean("www.example.com/?utm_source=x"), "no scheme — conservative, not guessed")
        XCTAssertNil(clean(""))
        XCTAssertNil(clean("   \n "))
    }

    func testTrimsSurroundingWhitespaceOfASingleLink() {
        XCTAssertEqual(clean("  https://example.com/?utm_source=x&a=1 \n")?.cleaned, "https://example.com/?a=1")
    }

    func testAQuestionMarkInsideTheFragmentIsClientSideRoutingNotAQuery() {
        XCTAssertNil(clean("https://app.example.com/#/inbox?utm_source=x"),
                     "everything after # is the app's own route — never rewritten")
        XCTAssertEqual(clean("https://app.example.com/?utm_source=x#/inbox?utm_medium=keep")?.cleaned,
                       "https://app.example.com/#/inbox?utm_medium=keep")
    }

    // MARK: - Host scoping: the rule that stops a global `t` from breaking YouTube

    func testYouTubeTimestampSurvivesWhileTheShareIDIsRemoved() {
        let r = clean("https://youtu.be/dQw4w9WgXcQ?t=90&si=AbCdEf")
        XCTAssertEqual(r?.cleaned, "https://youtu.be/dQw4w9WgXcQ?t=90",
                       "t= is a timestamp on YouTube — functional, must stay")
        XCTAssertEqual(r?.removed, ["si"])
        XCTAssertEqual(clean("https://www.youtube.com/watch?v=x&t=42s&feature=share")?.cleaned,
                       "https://www.youtube.com/watch?v=x&t=42s")
    }

    func testTwitterSAndTAreTrackingOnlyOnTwitterHosts() {
        XCTAssertEqual(clean("https://x.com/user/status/1?s=20&t=Zz")?.cleaned, "https://x.com/user/status/1")
        XCTAssertEqual(clean("https://mobile.twitter.com/user/status/1?s=20")?.cleaned,
                       "https://mobile.twitter.com/user/status/1", "subdomains match")
        XCTAssertNil(clean("https://example.com/?s=search&t=1&si=2"),
                     "s/t/si on an unrelated host are real fields")
    }

    func testHostMatchingIsNotAPrefixTrick() {
        XCTAssertNil(clean("https://notyoutube.com/?si=1"), "'notyoutube.com' is not a YouTube host")
        XCTAssertNil(clean("https://youtube.com.evil.test/?si=1"), "suffix on the wrong side")
    }

    // MARK: - Host extraction

    func testHostExtractionHandlesPortUserinfoAndIPv6() {
        XCTAssertEqual(URLCleaner.host(ofAbsoluteURL: "https://User:pw@Example.COM:8443/p"), "example.com")
        XCTAssertEqual(URLCleaner.host(ofAbsoluteURL: "http://[::1]:3000/x"), "[::1]")
        XCTAssertNil(URLCleaner.host(ofAbsoluteURL: "https:///nohost"))
        XCTAssertNil(URLCleaner.host(ofAbsoluteURL: "example.com/x"))
    }

    // MARK: - The rule table itself

    func testRuleTablesAreNotEmptyAndNothingFunctionalIsGlobal() {
        XCTAssertGreaterThan(URLCleaner.globalNames.count, 10)
        XCTAssertFalse(URLCleaner.globalPrefixes.isEmpty)
        for risky in ["t", "s", "si", "ref", "source", "id", "q", "v", "page", "tag"] {
            XCTAssertFalse(URLCleaner.globalNames.contains(risky),
                           "'\(risky)' is functional on many sites and must stay host-scoped or off the list")
        }
    }

    // MARK: - Own-write marker (the ⌘V race)

    func testOwnWriteMarkRemembersRecentCountsAndForgetsOldOnes() {
        let mark = OwnWriteMark()
        XCTAssertFalse(mark.contains(10))
        mark.record(10)
        XCTAssertTrue(mark.contains(10))
        for n in 100..<120 { mark.record(n) }
        XCTAssertFalse(mark.contains(10), "bounded memory: the oldest count is forgotten")
        XCTAssertTrue(mark.contains(119))
    }
}
