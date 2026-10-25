import XCTest
@testable import XFinderLogicTests

/// XF-T30 W2 — `FolderViewStore`: LRU-500 per-folder view preferences, tolerant decode (a damaged file falls back to
/// empty rather than crashing or throwing), and `encoded()`/`decode(_:)` round-tripping through `Data`.
final class FolderViewOptionsTests: XCTestCase {

    private func prefs(viewMode: BrowserViewMode = .list) -> FolderViewPrefs {
        FolderViewPrefs.defaults(viewMode: viewMode)
    }

    // MARK: - FolderViewPrefs.defaults

    func testDefaultsUsesFinderDefaultSort() {
        XCTAssertEqual(FolderViewPrefs.defaults(viewMode: .list).sort, .finderDefault)
    }

    func testDefaultsIconSizeIs64() {
        XCTAssertEqual(FolderViewPrefs.defaults(viewMode: .icons).iconSize, 64)
    }

    func testDefaultsTextSizeIs13() {
        XCTAssertEqual(FolderViewPrefs.defaults(viewMode: .list).textSize, 13)
    }

    func testDefaultsColumnsAreNameDateModifiedSizeKind() {
        XCTAssertEqual(FolderViewPrefs.defaults(viewMode: .list).columns, [.name, .dateModified, .size, .kind])
    }

    func testDefaultsGroupByIsNoneAndUseGroupsIsOff() {
        let p = FolderViewPrefs.defaults(viewMode: .list)
        XCTAssertEqual(p.groupBy, .none)
        XCTAssertFalse(p.useGroups)
    }

    func testIconSizesRangeStepsBy16From32To128() {
        XCTAssertEqual(FolderViewPrefs.iconSizes, [32, 48, 64, 80, 96, 112, 128])
    }

    func testTextSizesRange10To16() {
        XCTAssertEqual(FolderViewPrefs.textSizes, [10, 11, 12, 13, 14, 15, 16])
    }

    // MARK: - FolderViewStore: basic get/set

    func testEmptyStoreHasNoPrefsForAnyPath() {
        let store = FolderViewStore()
        XCTAssertNil(store.prefs(for: "/Users/x/Documents"))
    }

    func testSetThenGetReturnsTheSameValue() {
        var store = FolderViewStore()
        let p = prefs(viewMode: .gallery)
        store.set(p, for: "/Users/x/Documents")
        XCTAssertEqual(store.prefs(for: "/Users/x/Documents"), p)
    }

    func testSetOverwritesPreviousValueForSamePath() {
        var store = FolderViewStore()
        store.set(prefs(viewMode: .icons), for: "/p")
        store.set(prefs(viewMode: .columns), for: "/p")
        XCTAssertEqual(store.prefs(for: "/p")?.viewMode, .columns)
    }

    func testDifferentPathsAreIndependent() {
        var store = FolderViewStore()
        store.set(prefs(viewMode: .icons), for: "/a")
        store.set(prefs(viewMode: .list), for: "/b")
        XCTAssertEqual(store.prefs(for: "/a")?.viewMode, .icons)
        XCTAssertEqual(store.prefs(for: "/b")?.viewMode, .list)
    }

    // MARK: - LRU eviction at 500

    func testLimitConstantIs500() {
        XCTAssertEqual(FolderViewStore.limit, 500)
    }

    func testStoreStaysAtOrUnderLimitAfterManyInserts() {
        var store = FolderViewStore()
        for i in 0..<600 {
            store.set(prefs(), for: "/folder/\(i)")
        }
        XCTAssertEqual(store.order.count, FolderViewStore.limit)
        XCTAssertEqual(store.prefsByPath.count, FolderViewStore.limit)
    }

    func testLRUEvictsTheOldestPathFirst() {
        var store = FolderViewStore()
        for i in 0..<500 {
            store.set(prefs(), for: "/folder/\(i)")
        }
        // One more insert must evict "/folder/0" (the very first, never touched again) and keep everything else.
        store.set(prefs(), for: "/folder/500")
        XCTAssertNil(store.prefs(for: "/folder/0"))
        XCTAssertNotNil(store.prefs(for: "/folder/1"))
        XCTAssertNotNil(store.prefs(for: "/folder/500"))
        XCTAssertEqual(store.order.count, 500)
    }

    func testReSettingAnExistingPathRefreshesItsRecency() {
        var store = FolderViewStore()
        for i in 0..<500 {
            store.set(prefs(), for: "/folder/\(i)")
        }
        // Touch "/folder/0" again (re-set, not just read) so it is no longer the least-recently-used entry.
        store.set(prefs(viewMode: .gallery), for: "/folder/0")
        // Now "/folder/1" is the oldest untouched entry; one more insert should evict IT, not "/folder/0".
        store.set(prefs(), for: "/folder/500")
        XCTAssertNotNil(store.prefs(for: "/folder/0"), "re-set entries must not be evicted ahead of untouched ones")
        XCTAssertNil(store.prefs(for: "/folder/1"))
    }

    func testEvictingOverCapacityByMoreThanOneAtOnceIsImpossibleButRepeatedSingleInsertsStayAtLimit() {
        var store = FolderViewStore()
        for i in 0..<550 {
            store.set(prefs(), for: "/f/\(i)")
        }
        XCTAssertEqual(store.order.count, FolderViewStore.limit)
        // The 50 oldest (0...49) should be gone, the 500 newest (50...549) should remain.
        for i in 0..<50 { XCTAssertNil(store.prefs(for: "/f/\(i)"), "index \(i) should have been evicted") }
        for i in 50..<550 { XCTAssertNotNil(store.prefs(for: "/f/\(i)"), "index \(i) should still be present") }
    }

    // MARK: - encoded() / decode(_:)

    func testEncodedThenDecodedRoundTrips() {
        var store = FolderViewStore()
        store.set(prefs(viewMode: .columns), for: "/a")
        store.set(prefs(viewMode: .gallery), for: "/b")
        let decoded = FolderViewStore.decode(store.encoded())
        XCTAssertEqual(decoded, store)
    }

    func testDecodeNilDataReturnsEmptyStore() {
        XCTAssertEqual(FolderViewStore.decode(nil), FolderViewStore())
    }

    func testDecodeEmptyDataReturnsEmptyStore() {
        XCTAssertEqual(FolderViewStore.decode(Data()), FolderViewStore())
    }

    func testDecodeGarbageBytesReturnsEmptyStoreNotCrash() {
        let garbage = Data([0x00, 0xFF, 0x12, 0x34, 0x56])
        XCTAssertEqual(FolderViewStore.decode(garbage), FolderViewStore())
    }

    func testDecodeTruncatedValidJSONReturnsEmptyStore() {
        var store = FolderViewStore()
        store.set(prefs(), for: "/a")
        let full = store.encoded()
        let truncated = full.prefix(full.count / 2)
        XCTAssertEqual(FolderViewStore.decode(Data(truncated)), FolderViewStore())
    }

    func testDecodeDropsOnlyDamagedEntriesWhenOrderAndPrefsDisagree() {
        // Hand-construct JSON where `order` references a path that `prefsByPath` doesn't have (and vice versa) —
        // "drops damaged entries only": the well-formed path ("/good") must survive even though the payload overall
        // is inconsistent, rather than the whole decode being thrown away.
        let json = """
        {"order":["/good","/missing-prefs"],"prefsByPath":{"/good":\(prefsJSON()),"/stray":\(prefsJSON())}}
        """
        let decoded = FolderViewStore.decode(json.data(using: .utf8))
        XCTAssertNotNil(decoded.prefs(for: "/good"))
        XCTAssertNil(decoded.prefs(for: "/missing-prefs"), "order entry with no matching prefs must be dropped")
        XCTAssertNil(decoded.prefs(for: "/stray"), "prefs entry with no matching order must be dropped")
        XCTAssertEqual(decoded.order, ["/good"])
    }

    private func prefsJSON() -> String {
        let data = (try? JSONEncoder().encode(FolderViewPrefs.defaults(viewMode: .list))) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func testEncodedIsValidJSON() {
        var store = FolderViewStore()
        store.set(prefs(), for: "/a")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: store.encoded()))
    }
}
