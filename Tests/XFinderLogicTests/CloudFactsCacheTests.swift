import XCTest
import Foundation

/// 2026-10-26 — the per-row cloud read is gated by its folder: one folder probe per folder, no item read outside a
/// cloud folder, cached until the listing changes.
@MainActor
final class CloudFactsCacheTests: XCTestCase {
    private var probed: [String] = []
    private var read: [String] = []

    private func cache(cloudFolders: Set<String>) -> CloudFactsCache {
        CloudFactsCache(
            probeFolder: { [unowned self] folder in probed.append(folder); return cloudFolders.contains(folder) },
            readItem: { [unowned self] path in read.append(path); return CloudFacts(isUbiquitous: true, isUploaded: false) })
    }

    func testPlainFolderNeverReadsItemsAndProbesTheFolderOnce() {
        let c = cache(cloudFolders: [])
        for name in ["a.txt", "b.txt", "c.txt"] {
            XCTAssertEqual(c.facts(for: "/Users/me/" + name), CloudFacts())
        }
        XCTAssertEqual(probed, ["/Users/me"])
        XCTAssertEqual(read, [])
    }

    func testCloudFolderReadsEachItemOnceThenCaches() {
        let c = cache(cloudFolders: ["/Users/me/iCloud"])
        let path = "/Users/me/iCloud/doc.pages"
        XCTAssertEqual(c.facts(for: path).isUbiquitous, true)
        XCTAssertEqual(c.facts(for: path).isUbiquitous, true)
        XCTAssertEqual(read, [path], "second ask is served from the cache")
        XCTAssertEqual(probed, ["/Users/me/iCloud"])
    }

    func testFoldersAreJudgedSeparately() {
        let c = cache(cloudFolders: ["/Users/me/Documents"])
        _ = c.facts(for: "/Users/me/Documents/x.pdf")
        _ = c.facts(for: "/Users/me/Downloads/y.pdf")
        XCTAssertEqual(read, ["/Users/me/Documents/x.pdf"])
        XCTAssertEqual(Set(probed), ["/Users/me/Documents", "/Users/me/Downloads"])
    }

    func testRemoveAllForgetsItemsAndFolders() {
        let c = cache(cloudFolders: ["/c"])
        _ = c.facts(for: "/c/f")
        c.removeAll()
        _ = c.facts(for: "/c/f")
        XCTAssertEqual(read, ["/c/f", "/c/f"])
        XCTAssertEqual(probed, ["/c", "/c"])
    }

    func testRootAndRelativeEdgeCasesDoNotProbeNonsense() {
        let c = cache(cloudFolders: [""])
        XCTAssertEqual(c.facts(for: "relative"), CloudFacts(), "no parent ⇒ not a cloud item")
        XCTAssertEqual(c.facts(for: "/"), CloudFacts(), "the root is its own parent")
        XCTAssertEqual(read, [])
    }
}
