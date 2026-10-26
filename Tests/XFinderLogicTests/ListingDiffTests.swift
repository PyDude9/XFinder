import XCTest

/// 2026-10-26 — a refreshed listing patches the outline in place (FileOctopus mechanism, measured in its binary).
final class ListingDiffTests: XCTestCase {
    func testIdenticalListsAreAnEmptyPatch() {
        XCTAssertEqual(ListingDiff.plan(old: ["a", "b"], new: ["a", "b"]), .patch(removed: [], inserted: []))
        XCTAssertEqual(ListingDiff.plan(old: [], new: []), .patch(removed: [], inserted: []))
    }

    func testAddedAndRemovedRowsKeepTheOthersInOrder() {
        // ~ with "probe.txt" created and "Dockerfile" trashed, sorted by name.
        let old = ["Agent", "Dockerfile", "Documents", "Downloads", "zz"]
        let new = ["Agent", "Documents", "Downloads", "probe.txt", "zz"]
        XCTAssertEqual(ListingDiff.plan(old: old, new: new), .patch(removed: [1], inserted: [3]))
        XCTAssertEqual(ListingDiff.plan(old: [], new: ["a", "b"]), .patch(removed: [], inserted: [0, 1]))
        XCTAssertEqual(ListingDiff.plan(old: ["a", "b"], new: []), .patch(removed: [0, 1], inserted: []))
    }

    func testReorderedKeptRowsNeedAReload() {
        XCTAssertEqual(ListingDiff.plan(old: ["a", "b", "c"], new: ["c", "a", "b"]), .reload, "resort")
        XCTAssertEqual(ListingDiff.plan(old: ["a", "b", "c"], new: ["b", "x", "a"]), .reload, "moved + inserted")
    }

    func testDuplicateIdentitiesNeedAReload() {
        XCTAssertEqual(ListingDiff.plan(old: ["a", "a"], new: ["a"]), .reload)
        XCTAssertEqual(ListingDiff.plan(old: ["a"], new: ["a", "a"]), .reload)
        // The duplicates survive on both sides in the same order — only the duplicate guard turns this into a reload.
        XCTAssertEqual(ListingDiff.plan(old: ["a", "a", "b"], new: ["a", "a"]), .reload)
        XCTAssertEqual(ListingDiff.plan(old: ["b", "a", "a"], new: ["a", "a", "c"]), .reload)
    }

    func testPatchSizeCap() {
        let old = (0..<1000).map(String.init)
        XCTAssertTrue(ListingDiff.shouldPatch(ListingDiff.plan(old: old, new: Array(old.dropLast(500)))))
        XCTAssertFalse(ListingDiff.shouldPatch(ListingDiff.plan(old: old, new: Array(old.dropLast(501)))))
        XCTAssertFalse(ListingDiff.shouldPatch(.reload))
    }

    func testLargeListingIsFast() {
        let old = (0..<100_000).map { "f\($0)" }
        var new = old; new.remove(at: 50_000); new.append("zzz")
        let t0 = Date()
        let plan = ListingDiff.plan(old: old, new: new)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.5)
        XCTAssertEqual(plan, .patch(removed: [50_000], inserted: [99_999]))
    }
}
