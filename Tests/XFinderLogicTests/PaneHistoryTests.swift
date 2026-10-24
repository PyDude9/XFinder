import XCTest

final class PaneHistoryTests: XCTestCase {

    // MARK: - init

    func testInitSetsCurrentAndEmptyStacks() {
        let h = PaneHistory(current: "/a")
        XCTAssertEqual(h.current, "/a")
        XCTAssertFalse(h.canGoBack)
        XCTAssertFalse(h.canGoForward)
    }

    // MARK: - visit

    func testVisitPushesCurrentToBackAndMovesCurrent() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        XCTAssertEqual(h.current, "/b")
        XCTAssertTrue(h.canGoBack)
    }

    func testVisitClearsForward() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        _ = h.goBack()
        XCTAssertTrue(h.canGoForward)
        h.visit("/c")
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.current, "/c")
    }

    func testVisitSamePathIsNoOp() {
        var h = PaneHistory(current: "/a")
        h.visit("/a")
        XCTAssertEqual(h.current, "/a")
        XCTAssertFalse(h.canGoBack)
    }

    func testVisitSamePathDoesNotClearForward() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        _ = h.goBack() // current = /a, forward = [/b]
        h.visit("/a")  // re-visit same path: no-op, must not nuke forward
        XCTAssertTrue(h.canGoForward)
    }

    func testVisitTrimsBackToLimitDroppingOldest() {
        var h = PaneHistory(current: "/p0")
        for i in 1...(PaneHistory.limit + 10) {
            h.visit("/p\(i)")
        }
        // back should hold exactly `limit` entries, the oldest ones dropped.
        var backEntries: [String] = []
        while h.canGoBack {
            guard let dest = h.goBack() else { break }
            backEntries.append(dest)
        }
        XCTAssertEqual(backEntries.count, PaneHistory.limit)
        // The oldest surviving entry should be /p10 (p0..p9 dropped: 10 entries evicted since
        // we visited limit+10 new paths total, pushing limit+10 entries, keep last `limit`).
        XCTAssertEqual(backEntries.last, "/p10")
    }

    func testVisitAtExactlyLimitEvictsNothing() {
        var h = PaneHistory(current: "/p0")
        for i in 1...PaneHistory.limit {
            h.visit("/p\(i)")
        }
        var backEntries: [String] = []
        while h.canGoBack {
            guard let dest = h.goBack() else { break }
            backEntries.append(dest)
        }
        // Exactly `limit` visits after the initial current: nothing evicted yet, oldest is /p0.
        XCTAssertEqual(backEntries.count, PaneHistory.limit)
        XCTAssertEqual(backEntries.last, "/p0")
    }

    /// `back.count + forward.count` can never exceed `limit`: goBack/goForward only ever move an
    /// entry between the two stacks (conservation), and `visit` is the only place that can grow the
    /// total, already trimmed there. A regression that re-grows `forward` unboundedly (e.g. appending
    /// without ever trimming it) would still slip past tests that only check `back` in isolation.
    func testBackPlusForwardNeverExceedsLimitThroughMixedNavigation() {
        var h = PaneHistory(current: "/p0")
        for i in 1...(PaneHistory.limit * 3) {
            h.visit("/p\(i)")
            if i % 2 == 0 { _ = h.goBack() }
            if i % 3 == 0 { _ = h.goForward() }
            XCTAssertLessThanOrEqual(h.back.count, PaneHistory.limit)
            XCTAssertLessThanOrEqual(h.forward.count, PaneHistory.limit)
        }
    }

    // MARK: - goBack / goForward

    func testGoBackReturnsNilWhenEmpty() {
        var h = PaneHistory(current: "/a")
        XCTAssertNil(h.goBack())
        XCTAssertEqual(h.current, "/a")
    }

    func testGoForwardReturnsNilWhenEmpty() {
        var h = PaneHistory(current: "/a")
        XCTAssertNil(h.goForward())
        XCTAssertEqual(h.current, "/a")
    }

    func testGoBackMovesCurrentIntoForward() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        let dest = h.goBack()
        XCTAssertEqual(dest, "/a")
        XCTAssertEqual(h.current, "/a")
        XCTAssertTrue(h.canGoForward)
        XCTAssertFalse(h.canGoBack)
    }

    func testGoForwardMovesCurrentIntoBack() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        _ = h.goBack()
        let dest = h.goForward()
        XCTAssertEqual(dest, "/b")
        XCTAssertEqual(h.current, "/b")
        XCTAssertTrue(h.canGoBack)
        XCTAssertFalse(h.canGoForward)
    }

    func testGoBackThenGoForwardRoundTrips() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        h.visit("/c")
        XCTAssertEqual(h.goBack(), "/b")
        XCTAssertEqual(h.goBack(), "/a")
        XCTAssertNil(h.goBack())
        XCTAssertEqual(h.goForward(), "/b")
        XCTAssertEqual(h.goForward(), "/c")
        XCTAssertNil(h.goForward())
        XCTAssertEqual(h.current, "/c")
    }

    func testMultipleBackEntriesPopInLIFOOrder() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        h.visit("/c")
        h.visit("/d")
        XCTAssertEqual(h.goBack(), "/c")
        XCTAssertEqual(h.goBack(), "/b")
        XCTAssertEqual(h.goBack(), "/a")
        XCTAssertNil(h.goBack())
    }

    // MARK: - noteLeaving / childToSelect

    func testNoteLeavingThenChildToSelect() {
        var h = PaneHistory(current: "/a")
        h.noteLeaving(child: "Sub", of: "/a")
        XCTAssertEqual(h.childToSelect(in: "/a"), "Sub")
    }

    func testChildToSelectNilWhenNeverLeft() {
        let h = PaneHistory(current: "/a")
        XCTAssertNil(h.childToSelect(in: "/a"))
    }

    func testNoteLeavingOverwritesPreviousChildForSameParent() {
        var h = PaneHistory(current: "/a")
        h.noteLeaving(child: "First", of: "/a")
        h.noteLeaving(child: "Second", of: "/a")
        XCTAssertEqual(h.childToSelect(in: "/a"), "Second")
    }

    func testNoteLeavingDistinctParentsAreIndependent() {
        var h = PaneHistory(current: "/a")
        h.noteLeaving(child: "SubA", of: "/a")
        h.noteLeaving(child: "SubB", of: "/b")
        XCTAssertEqual(h.childToSelect(in: "/a"), "SubA")
        XCTAssertEqual(h.childToSelect(in: "/b"), "SubB")
    }

    func testNoteLeavingEvictsOldestWhenOverRememberLimit() {
        var h = PaneHistory(current: "/a")
        for i in 0..<(PaneHistory.rememberLimit + 5) {
            h.noteLeaving(child: "Child\(i)", of: "/parent\(i)")
        }
        // The first 5 parents should have been evicted (oldest insertion dropped first).
        for i in 0..<5 {
            XCTAssertNil(h.childToSelect(in: "/parent\(i)"), "parent\(i) should have been evicted")
        }
        // The remaining `rememberLimit` entries should still be there.
        for i in 5..<(PaneHistory.rememberLimit + 5) {
            XCTAssertEqual(h.childToSelect(in: "/parent\(i)"), "Child\(i)")
        }
    }

    func testNoteLeavingAtExactlyRememberLimitEvictsNothing() {
        var h = PaneHistory(current: "/a")
        for i in 0..<PaneHistory.rememberLimit {
            h.noteLeaving(child: "Child\(i)", of: "/parent\(i)")
        }
        // Exactly at the limit: every entry inserted so far must still be reachable.
        for i in 0..<PaneHistory.rememberLimit {
            XCTAssertEqual(h.childToSelect(in: "/parent\(i)"), "Child\(i)")
        }
    }

    func testNoteLeavingOverwriteDoesNotCountTwiceTowardLimit() {
        var h = PaneHistory(current: "/a")
        // Fill to exactly the limit.
        for i in 0..<PaneHistory.rememberLimit {
            h.noteLeaving(child: "Child\(i)", of: "/parent\(i)")
        }
        // Re-note an existing parent: must not evict anything since count doesn't grow.
        h.noteLeaving(child: "ChildUpdated", of: "/parent0")
        XCTAssertEqual(h.childToSelect(in: "/parent0"), "ChildUpdated")
        for i in 1..<PaneHistory.rememberLimit {
            XCTAssertEqual(h.childToSelect(in: "/parent\(i)"), "Child\(i)")
        }
    }

    // MARK: - removeMissing

    func testRemoveMissingFiltersBackAndForward() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        h.visit("/c")
        _ = h.goBack() // current = /b, back = [/a], forward = [/c]
        let existing: Set<String> = ["/b"]
        h.removeMissing(exists: { existing.contains($0) }, fallback: "/home")
        XCTAssertFalse(h.canGoBack)
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.current, "/b")
    }

    func testRemoveMissingKeepsExistingEntries() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        h.visit("/c")
        _ = h.goBack() // current = /b, back = [/a], forward = [/c]
        let existing: Set<String> = ["/a", "/b", "/c"]
        h.removeMissing(exists: { existing.contains($0) }, fallback: "/home")
        XCTAssertTrue(h.canGoBack)
        XCTAssertTrue(h.canGoForward)
        XCTAssertEqual(h.current, "/b")
    }

    func testRemoveMissingFallsBackWhenCurrentGone() {
        var h = PaneHistory(current: "/a")
        h.removeMissing(exists: { _ in false }, fallback: "/home")
        XCTAssertEqual(h.current, "/home")
    }

    func testRemoveMissingDoesNotTouchCurrentWhenItExists() {
        var h = PaneHistory(current: "/a")
        h.removeMissing(exists: { $0 == "/a" }, fallback: "/home")
        XCTAssertEqual(h.current, "/a")
    }

    func testRemoveMissingPreservesOrderOfSurvivors() {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        h.visit("/c")
        h.visit("/d") // back = [/a, /b, /c], current = /d
        let existing: Set<String> = ["/a", "/c", "/d"]
        h.removeMissing(exists: { existing.contains($0) }, fallback: "/home")
        // /b removed, order of remaining back entries preserved: [/a, /c]
        XCTAssertEqual(h.goBack(), "/c")
        XCTAssertEqual(h.goBack(), "/a")
        XCTAssertNil(h.goBack())
    }

    /// Contract for `removeMissing` only scopes "back/forward/current" — it does not mention the
    /// `noteLeaving` remember-map. A parent folder dropping out of back/forward (e.g. renamed away)
    /// must not silently lose its remembered child, since re-entering that same parent path later
    /// (it may come back, or a sibling pane still has it as `current`) should still reselect.
    func testRemoveMissingDoesNotTouchRememberedChildren() {
        var h = PaneHistory(current: "/a")
        h.visit("/a/Sub")
        h.noteLeaving(child: "Sub", of: "/a")
        _ = h.goBack() // current back to /a, /a/Sub now only lives in forward
        h.removeMissing(exists: { $0 == "/a" }, fallback: "/home") // /a/Sub reported gone
        XCTAssertFalse(h.canGoForward)
        XCTAssertEqual(h.childToSelect(in: "/a"), "Sub")
    }

    // MARK: - Codable / Equatable

    func testCodableRoundTrip() throws {
        var h = PaneHistory(current: "/a")
        h.visit("/b")
        h.visit("/c")
        _ = h.goBack()
        h.noteLeaving(child: "Sub", of: "/a")
        let data = try JSONEncoder().encode(h)
        let decoded = try JSONDecoder().decode(PaneHistory.self, from: data)
        XCTAssertEqual(decoded, h)
        XCTAssertEqual(decoded.current, h.current)
        XCTAssertEqual(decoded.canGoBack, h.canGoBack)
        XCTAssertEqual(decoded.canGoForward, h.canGoForward)
        // The remember-map is private; round-trip it through observable behaviour rather than `==`
        // alone, so a future Codable key change that silently drops it still fails a test.
        XCTAssertEqual(decoded.childToSelect(in: "/a"), "Sub")
    }

    func testEqualityIgnoresNothingStructural() {
        var a = PaneHistory(current: "/a")
        var b = PaneHistory(current: "/a")
        a.visit("/b")
        b.visit("/b")
        XCTAssertEqual(a, b)
        a.visit("/c")
        XCTAssertNotEqual(a, b)
    }
}
