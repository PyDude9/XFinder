import XCTest
import Foundation

/// D4b — which links may be fetched for a preview, and when.
final class LinkPreviewRulesTests: XCTestCase {
    typealias R = LinkPreviewRules
    func u(_ s: String) -> URL { URL(string: s)! }

    func testOnlyPublicHTTPHostsAreEligible() {
        XCTAssertTrue(R.isEligible(u("https://www.apple.com/")))
        XCTAssertTrue(R.isEligible(u("http://example.com/a?b=1")))
        XCTAssertTrue(R.isEligible(u("https://8.8.8.8/")), "a public IP is a public host")
        for bad in ["ftp://example.com/", "file:///etc/hosts", "https://localhost/", "https://foo.localhost/", "https://printer.local/",
                    "https://api.internal/", "https://x.invalid/", "https://10.0.0.5/", "https://127.0.0.1:8080/", "https://192.168.1.1/",
                    "https://172.16.0.9/", "https://172.31.255.1/", "https://169.254.1.1/", "https://0.0.0.0/",
                    "https://user:pw@example.com/", "https://[::1]/", "mailto:a@b.c"] {
            XCTAssertFalse(R.isEligible(u(bad)), bad)
        }
        XCTAssertTrue(R.isEligible(u("https://172.32.0.1/")), "172.32 is outside the private block")
    }

    func testCacheStemIsAStableHashNeverTheHost() {
        let a = R.cacheStem(for: u("https://example.com/x"))
        XCTAssertEqual(a.count, 64); XCTAssertEqual(a, R.cacheStem(for: u("https://example.com/x")))
        XCTAssertNotEqual(a, R.cacheStem(for: u("https://example.com/y")))
        XCTAssertFalse(a.contains("example"))
    }

    func testNeedsFetchHonoursStaleAndRetryWindows() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        XCTAssertTrue(R.needsFetch(fetched: nil, hasTitle: false, now: now))
        XCTAssertFalse(R.needsFetch(fetched: now.addingTimeInterval(-3600), hasTitle: true, now: now))
        XCTAssertTrue(R.needsFetch(fetched: now.addingTimeInterval(-31 * 86_400), hasTitle: true, now: now), "a month-old title refreshes")
        XCTAssertFalse(R.needsFetch(fetched: now.addingTimeInterval(-3600), hasTitle: false, now: now), "a failed fetch waits a day — never a retry per render")
        XCTAssertTrue(R.needsFetch(fetched: now.addingTimeInterval(-2 * 86_400), hasTitle: false, now: now))
    }

    func testMetadataPatchAlwaysRecordsTheFetchAndCapsTheTitle() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let ok = R.metadataPatch(title: String(repeating: "t", count: 300), imagePath: "/p.png", fetched: now)
        XCTAssertEqual(ok[R.titleKey]?.count, 200); XCTAssertEqual(ok[R.imageKey], "/p.png")
        XCTAssertEqual(R.fetchedDate(from: ok), now)
        let failed = R.metadataPatch(title: nil, imagePath: nil, fetched: now)
        XCTAssertNil(failed[R.titleKey]); XCTAssertNil(failed[R.imageKey]); XCTAssertNotNil(failed[R.fetchedKey])
        let empty = R.metadataPatch(title: "", imagePath: nil, fetched: now)
        XCTAssertNil(empty[R.titleKey], "an empty title is no title")
    }

    func testTheClipsURLComesFromMetadataThenPreview() {
        XCTAssertEqual(R.url(of: ["url": "https://a.b/"], preview: "https://c.d/")?.host, "a.b")
        XCTAssertEqual(R.url(of: [:], preview: " https://c.d/ ")?.host, "c.d")
        XCTAssertNil(R.url(of: [:], preview: "not a url at all"))
    }
}
