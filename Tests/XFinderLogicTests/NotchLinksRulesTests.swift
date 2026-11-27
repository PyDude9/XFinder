import XCTest
import Foundation

final class NotchLinksRulesTests: XCTestCase {

    private let sampleLinks: [NotchLinkEntry] = [
        NotchLinkEntry(keyword: "gg", title: "Google", url: "https://google.com"),
        NotchLinkEntry(keyword: "gh", title: "GitHub Repositories", url: "https://github.com/wolong/xfinder"),
        NotchLinkEntry(keyword: "docs", title: "Tài liệu đồng bộ", url: "https://docs.example.com/dong-bo"),
        NotchLinkEntry(keyword: "local", title: "Local Dev Server", url: "http://localhost:3000/dashboard"),
    ]

    // MARK: - Empty Catalog (danh sách rỗng)

    func testEmptyCatalogReturnsEmptyStateWithOrWithoutQuery() {
        XCTAssertEqual(NotchLinksRules.displayState(links: [], query: ""), .emptyCatalog)
        XCTAssertEqual(NotchLinksRules.displayState(links: [], query: "github"), .emptyCatalog)
        XCTAssertTrue(NotchLinksRules.filter([], query: "anything").isEmpty)
    }

    // MARK: - No Matches (không có kết quả)

    func testNoMatchQueryReturnsNoMatchesState() {
        XCTAssertEqual(NotchLinksRules.displayState(links: sampleLinks, query: "khongtontai999"), .noMatches)
        XCTAssertEqual(NotchLinksRules.displayState(links: sampleLinks, query: "google github"), .noMatches)
        XCTAssertTrue(NotchLinksRules.filter(sampleLinks, query: "missing-link").isEmpty)
    }

    // MARK: - Filtering by Title, Keyword, and URL (including VI accents & đ/Đ)

    func testFilterMatchesKeywordTitleAndURLWithDiacriticAndDStrokeFolding() {
        // Exact keyword ranks first
        let byKeyword = NotchLinksRules.filter(sampleLinks, query: "gh")
        XCTAssertEqual(byKeyword.first?.keyword, "gh")

        // Title with Vietnamese diacritics and đ/Đ
        let accented = NotchLinksRules.filter(sampleLinks, query: "đồng bộ")
        let unaccented = NotchLinksRules.filter(sampleLinks, query: "dong bo")
        XCTAssertEqual(accented.map(\.keyword), ["docs"])
        XCTAssertEqual(unaccented.map(\.keyword), ["docs"])

        // URL path / port match
        let byURL = NotchLinksRules.filter(sampleLinks, query: "localhost:3000")
        XCTAssertEqual(byURL.map(\.keyword), ["local"])

        // Empty/whitespace query preserves original order
        XCTAssertEqual(NotchLinksRules.filter(sampleLinks, query: "   "), sampleLinks)
    }

    // MARK: - Bad URLs (URL xấu) vs Valid HTTP/HTTPS

    func testValidatedWebURLRejectsNonHTTPAndMalformedURLs() {
        let badURLs = [
            "",
            "   ",
            "google.com",
            "javascript:alert(1)",
            "file:///etc/passwd",
            "data:text/html,<script>alert(1)</script>",
            "mailto:test@example.com",
            "xfinder://settings?page=finderSearch",
            "ftp://example.com/file",
            "https://",
            "http:///only-path",
            "https://..",
            "https://example.com/has space",
            "https://example.com\ninjected",
        ]

        for bad in badURLs {
            XCTAssertNil(NotchLinksRules.validatedWebURL(bad), "must reject bad URL: \(bad)")
            let entry = NotchLinkEntry(keyword: "bad", title: "Bad", url: bad)
            var openerCalled = false
            let result = NotchLinksRules.open(entry) { _ in
                openerCalled = true
                return true
            }
            XCTAssertEqual(result, .invalidURL, "open must return .invalidURL for \(bad)")
            XCTAssertFalse(openerCalled, "opener must never be called for invalid URL: \(bad)")
        }
    }

    func testValidatedWebURLAcceptsHTTPAndHTTPS() {
        let validURLs = [
            "https://google.com",
            "http://localhost:8080/api?v=1#top",
            "HTTPS://EXAMPLE.COM/path",
            "  https://github.com/wolong  ",
        ]

        for raw in validURLs {
            let url = NotchLinksRules.validatedWebURL(raw)
            XCTAssertNotNil(url, "must accept valid HTTP/HTTPS URL: \(raw)")
        }
    }

    // MARK: - Long Titles & Long URLs (tiêu đề dài)

    func testLongTitleAndURLStaySearchableAndSafeToFormat() {
        let longTitle = String(repeating: "Tài liệu thiết kế hệ thống Dynamic Island siêu dài ", count: 8)
        let longURL = "https://docs.example.com/" + String(repeating: "segment/", count: 25) + "overview?tab=details"
        let entry = NotchLinkEntry(keyword: "longdoc", title: longTitle, url: longURL)

        let matched = NotchLinksRules.filter([entry], query: "dynamic island")
        XCTAssertEqual(matched, [entry])

        let formattedTitle = NotchLinksRules.displayTitle(entry.title, fallbackURL: entry.url)
        XCTAssertEqual(formattedTitle, longTitle.trimmingCharacters(in: .whitespacesAndNewlines))

        let formattedURL = NotchLinksRules.displayURL(entry.url)
        XCTAssertTrue(formattedURL.hasPrefix("docs.example.com/"))
        XCTAssertFalse(formattedURL.hasPrefix("https://"))

        // Blank title falls back to compact URL
        XCTAssertEqual(
            NotchLinksRules.displayTitle("   ", fallbackURL: "https://example.com/"),
            "example.com"
        )
    }

    // MARK: - App Open Failure (lỗi ứng dụng mở)

    func testOpenReportsLaunchFailureWhenDefaultAppRefusesURL() {
        let entry = NotchLinkEntry(keyword: "gg", title: "Google", url: "https://google.com")
        let expectedURL = URL(string: "https://google.com")!

        var received: URL?
        let failed = NotchLinksRules.open(entry) { url in
            received = url
            return false
        }
        XCTAssertEqual(received, expectedURL)
        XCTAssertEqual(failed, .launchFailed(expectedURL))

        let succeeded = NotchLinksRules.open(entry) { _ in true }
        XCTAssertEqual(succeeded, .opened(expectedURL))
    }

    // MARK: - Copy Address

    func testCopyAddressCopiesTrimmedURLAndRejectsEmpty() {
        var copied: [String] = []
        let entry = NotchLinkEntry(keyword: "gh", title: "GitHub", url: "  https://github.com  ")
        XCTAssertTrue(NotchLinksRules.copyAddress(entry) { addr in
            copied.append(addr)
            return true
        })
        XCTAssertEqual(copied, ["https://github.com"])

        let empty = NotchLinkEntry(keyword: "x", title: "Empty", url: "   ")
        XCTAssertFalse(NotchLinksRules.copyAddress(empty) { _ in
            XCTFail("copier must not be called for empty URL")
            return true
        })
    }
}
