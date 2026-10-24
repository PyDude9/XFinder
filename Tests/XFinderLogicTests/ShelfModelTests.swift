import XCTest
@testable import XFinderLogicTests

final class ShelfModelTests: XCTestCase {

    // MARK: init

    func test_init_isEmpty() {
        let shelf = ShelfModel()
        XCTAssertEqual(shelf.items, [])
        XCTAssertEqual(shelf.count, 0)
        XCTAssertEqual(shelf.totalBytes, 0)
    }

    // MARK: add — order, counting

    func test_add_appendsInOrder() {
        var shelf = ShelfModel()
        let added = shelf.add(["/a/one", "/a/two", "/a/three"], sizes: [:])
        XCTAssertEqual(added, 3)
        XCTAssertEqual(shelf.items.map(\.path), ["/a/one", "/a/two", "/a/three"])
        XCTAssertEqual(shelf.count, 3)
    }

    func test_add_returnsCountActuallyAdded() {
        var shelf = ShelfModel()
        XCTAssertEqual(shelf.add(["/a/one"], sizes: [:]), 1)
        XCTAssertEqual(shelf.add(["/a/one", "/a/two"], sizes: [:]), 1)
    }

    func test_add_setsSizeFromSizesDictionaryKeyedByInputPath() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: ["/a/one": 1024])
        XCTAssertEqual(shelf.items[0].size, 1024)
        XCTAssertNil(shelf.items[1].size)
    }

    func test_add_newItemsStartNotMissing() {
        var shelf = ShelfModel()
        shelf.add(["/a/one"], sizes: [:])
        XCTAssertFalse(shelf.items[0].missing)
    }

    // MARK: add — de-duplication by normalized path

    func test_add_dropsExactDuplicate() {
        var shelf = ShelfModel()
        shelf.add(["/a/one"], sizes: [:])
        let added = shelf.add(["/a/one"], sizes: [:])
        XCTAssertEqual(added, 0)
        XCTAssertEqual(shelf.count, 1)
    }

    func test_add_dropsDuplicateWithTrailingSlash() {
        var shelf = ShelfModel()
        shelf.add(["/a/one"], sizes: [:])
        let added = shelf.add(["/a/one/"], sizes: [:])
        XCTAssertEqual(added, 0)
        XCTAssertEqual(shelf.count, 1)
    }

    func test_add_dropsDuplicateWithDotComponents() {
        var shelf = ShelfModel()
        shelf.add(["/a/one"], sizes: [:])
        let added = shelf.add(["/a/./one"], sizes: [:])
        XCTAssertEqual(added, 0)
        XCTAssertEqual(shelf.count, 1)
    }

    func test_add_withinSameCallAlsoDeduplicates() {
        var shelf = ShelfModel()
        let added = shelf.add(["/a/one", "/a/one/", "/a/two"], sizes: [:])
        XCTAssertEqual(added, 2)
        XCTAssertEqual(shelf.items.map(\.path), ["/a/one", "/a/two"])
    }

    func test_add_existingItemKeepsOriginalPositionAndSpelling() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        shelf.add(["/a/one/"], sizes: [:])
        // Position and the originally-recorded path string are both unchanged — a second drag doesn't reorder or rewrite it.
        XCTAssertEqual(shelf.items.map(\.path), ["/a/one", "/a/two"])
    }

    func test_add_emptyArrayAddsNothing() {
        var shelf = ShelfModel()
        XCTAssertEqual(shelf.add([], sizes: [:]), 0)
        XCTAssertEqual(shelf.count, 0)
    }

    // MARK: remove

    func test_remove_deletesMatchingPaths() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two", "/a/three"], sizes: [:])
        shelf.remove(["/a/two"])
        XCTAssertEqual(shelf.items.map(\.path), ["/a/one", "/a/three"])
    }

    func test_remove_matchesByNormalizedPath() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        shelf.remove(["/a/one/"])
        XCTAssertEqual(shelf.items.map(\.path), ["/a/two"])
    }

    func test_remove_unknownPathIsNoOp() {
        var shelf = ShelfModel()
        shelf.add(["/a/one"], sizes: [:])
        shelf.remove(["/a/nonexistent"])
        XCTAssertEqual(shelf.count, 1)
    }

    func test_remove_emptySetIsNoOp() {
        var shelf = ShelfModel()
        shelf.add(["/a/one"], sizes: [:])
        shelf.remove([])
        XCTAssertEqual(shelf.count, 1)
    }

    // MARK: clear

    func test_clear_removesEverything() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        shelf.clear()
        XCTAssertEqual(shelf.count, 0)
        XCTAssertEqual(shelf.items, [])
    }

    // MARK: refreshMissing

    func test_refreshMissing_marksAbsentPaths() {
        var shelf = ShelfModel()
        shelf.add(["/a/exists", "/a/gone"], sizes: [:])
        shelf.refreshMissing { $0 == "/a/exists" }
        XCTAssertFalse(shelf.items[0].missing)
        XCTAssertTrue(shelf.items[1].missing)
    }

    func test_refreshMissing_canClearPreviouslyMissingFlag() {
        var shelf = ShelfModel()
        shelf.add(["/a/one"], sizes: [:])
        shelf.refreshMissing { _ in false }
        XCTAssertTrue(shelf.items[0].missing)
        shelf.refreshMissing { _ in true }
        XCTAssertFalse(shelf.items[0].missing)
    }

    func test_refreshMissing_onEmptyShelfDoesNothing() {
        var shelf = ShelfModel()
        shelf.refreshMissing { _ in true }
        XCTAssertEqual(shelf.count, 0)
    }

    // MARK: totalBytes

    func test_totalBytes_sumsKnownSizes() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: ["/a/one": 100, "/a/two": 200])
        XCTAssertEqual(shelf.totalBytes, 300)
    }

    func test_totalBytes_treatsUnknownSizeAsZeroNotMissing() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: ["/a/one": 100])
        // /a/two has size == nil: contributes nothing, but does not need to be "missing" to be excluded.
        XCTAssertEqual(shelf.totalBytes, 100)
    }

    func test_totalBytes_excludesMissingItemsEvenWithKnownSize() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: ["/a/one": 100, "/a/two": 200])
        shelf.refreshMissing { $0 == "/a/one" }
        XCTAssertEqual(shelf.totalBytes, 100)
    }

    func test_totalBytes_emptyShelfIsZero() {
        let shelf = ShelfModel()
        XCTAssertEqual(shelf.totalBytes, 0)
    }

    // MARK: targets

    func test_targets_emptySelectionReturnsAllPresentItemsInShelfOrder() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two", "/a/three"], sizes: [:])
        XCTAssertEqual(shelf.targets(selection: []), ["/a/one", "/a/two", "/a/three"])
    }

    func test_targets_nonEmptySelectionReturnsOnlySelectedInShelfOrder() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two", "/a/three"], sizes: [:])
        // Selection given out of Shelf order; result must still follow Shelf order.
        XCTAssertEqual(shelf.targets(selection: ["/a/three", "/a/one"]), ["/a/one", "/a/three"])
    }

    func test_targets_selectionMatchesByNormalizedPath() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        XCTAssertEqual(shelf.targets(selection: ["/a/one/"]), ["/a/one"])
    }

    func test_targets_excludesMissingFromAllBranch() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        // exists("/a/one") == true, so /a/one stays present; /a/two is not reported as existing, so it becomes missing.
        shelf.refreshMissing { $0 == "/a/one" }
        XCTAssertEqual(shelf.targets(selection: []), ["/a/one"])
    }

    func test_targets_excludesMissingFromSelectedBranch() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        shelf.refreshMissing { $0 == "/a/one" }
        XCTAssertEqual(shelf.targets(selection: ["/a/one", "/a/two"]), ["/a/one"])
    }

    /// If `selection` contains only paths that are not on the Shelf at all (e.g. a pane selection unrelated to the
    /// Shelf), nothing on the Shelf is "selected" — the spec treats "selected" as "Shelf items also in selection",
    /// so with no overlap the fallback is still "all".
    func test_targets_selectionWithNoShelfOverlapFallsBackToAll() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        XCTAssertEqual(shelf.targets(selection: ["/not/on/shelf"]), ["/a/one", "/a/two"])
    }

    /// Selecting exactly one Shelf row that happens to be missing is still a selection — the user picked something,
    /// even if it can no longer be acted on. The result must be empty, not a silent fallback to copying every
    /// *other*, unselected item on the Shelf: a Chép/Di chuyển action must never touch files the user didn't select.
    func test_targets_selectingOnlyAMissingItemDoesNotFallBackToAll() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        shelf.refreshMissing { $0 == "/a/one" }
        XCTAssertEqual(shelf.targets(selection: ["/a/two"]), [])
    }

    /// Same as above but selection matches the missing item via its normalized form, to confirm the branch decision
    /// (not just the final present-filter) uses normalization consistently.
    func test_targets_selectingOnlyAMissingItemByNormalizedPathDoesNotFallBackToAll() {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: [:])
        shelf.refreshMissing { $0 == "/a/one" }
        XCTAssertEqual(shelf.targets(selection: ["/a/two/"]), [])
    }

    func test_targets_emptyShelfReturnsEmpty() {
        let shelf = ShelfModel()
        XCTAssertEqual(shelf.targets(selection: []), [])
        XCTAssertEqual(shelf.targets(selection: ["/a/one"]), [])
    }

    // MARK: Codable / Equatable

    func test_codable_roundTrip() throws {
        var shelf = ShelfModel()
        shelf.add(["/a/one", "/a/two"], sizes: ["/a/one": 42])
        shelf.refreshMissing { $0 == "/a/one" }
        let data = try JSONEncoder().encode(shelf)
        let decoded = try JSONDecoder().decode(ShelfModel.self, from: data)
        XCTAssertEqual(decoded, shelf)
    }

    func test_equatable_sameContentsAreEqual() {
        var a = ShelfModel()
        a.add(["/a/one"], sizes: [:])
        var b = ShelfModel()
        b.add(["/a/one"], sizes: [:])
        XCTAssertEqual(a, b)
    }
}
