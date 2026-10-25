import XCTest
@testable import XFinderLogicTests

final class DirectoryEntryTests: XCTestCase {

    // MARK: - Fixtures

    private func entry(
        name: String, kind: DirectoryEntry.Kind = .file, isPackage: Bool = false,
        isHidden: Bool = false, size: Int64 = 0, modified: Date = Date(timeIntervalSince1970: 0),
        created: Date = Date(timeIntervalSince1970: 0), volumeID: Int32 = 1, path: String? = nil,
        added: Date? = nil, lastOpened: Date? = nil
    ) -> DirectoryEntry {
        var e = DirectoryEntry(
            name: name, path: path ?? "/tmp/\(name)", kind: kind, isPackage: isPackage,
            isHidden: isHidden, size: size, modified: modified, created: created, volumeID: volumeID
        )
        e.added = added
        e.lastOpened = lastOpened
        return e
    }

    // MARK: - ext

    func testExtLowercasesAndStripsDot() {
        XCTAssertEqual(entry(name: "Photo.JPG").ext, "jpg")
        XCTAssertEqual(entry(name: "archive.tar.gz").ext, "gz")
    }

    func testExtNoDotIsEmpty() {
        XCTAssertEqual(entry(name: "README").ext, "")
    }

    func testExtDotfileWithNoExtensionIsEmpty() {
        // ".gitignore": the leading dot marks it hidden-by-name, not an extension.
        XCTAssertEqual(entry(name: ".gitignore").ext, "")
    }

    func testExtTrailingDotIsEmpty() {
        XCTAssertEqual(entry(name: "weird.").ext, "")
    }

    func testExtDotfileWithRealExtension() {
        XCTAssertEqual(entry(name: ".env.local").ext, "local")
    }

    // MARK: - isFolderLike

    func testIsFolderLikeTrueForPlainDirectory() {
        XCTAssertTrue(entry(name: "Documents", kind: .directory).isFolderLike)
    }

    func testIsFolderLikeFalseForPackage() {
        XCTAssertFalse(entry(name: "Keynote.app", kind: .directory, isPackage: true).isFolderLike)
    }

    func testIsFolderLikeFalseForFile() {
        XCTAssertFalse(entry(name: "a.txt", kind: .file).isFolderLike)
    }

    func testIsFolderLikeFalseForSymlink() {
        XCTAssertFalse(entry(name: "link", kind: .symlink).isFolderLike)
    }

    // MARK: - id / Identifiable

    func testIDIsPath() {
        let e = entry(name: "a.txt", path: "/Users/x/a.txt")
        XCTAssertEqual(e.id, "/Users/x/a.txt")
    }

    // MARK: - foldKey

    func testFoldKeyIsCaseInsensitive() {
        XCTAssertEqual(EntryRules.foldKey("HELLO"), EntryRules.foldKey("hello"))
    }

    func testFoldKeyIsDiacriticInsensitive() {
        XCTAssertEqual(EntryRules.foldKey("café"), EntryRules.foldKey("cafe"))
    }

    func testFoldKeyMapsVietnameseDStroke() {
        XCTAssertEqual(EntryRules.foldKey("đường"), EntryRules.foldKey("duong"))
        XCTAssertEqual(EntryRules.foldKey("Đà Nẵng"), EntryRules.foldKey("Da Nang"))
    }

    // MARK: - visible (hidden filter)

    func testVisibleHidesDotAndFlaggedWhenOff() {
        let visible = entry(name: "a.txt", isHidden: false)
        let dotfile = entry(name: ".hidden", isHidden: true)
        let result = EntryRules.visible([visible, dotfile], showHidden: false)
        XCTAssertEqual(result.map(\.name), ["a.txt"])
    }

    func testVisibleShowsHiddenWhenOn() {
        let visible = entry(name: "a.txt", isHidden: false)
        let dotfile = entry(name: ".hidden", isHidden: true)
        let result = EntryRules.visible([visible, dotfile], showHidden: true)
        XCTAssertEqual(Set(result.map(\.name)), ["a.txt", ".hidden"])
    }

    func testVisibleEmptyInput() {
        XCTAssertEqual(EntryRules.visible([], showHidden: false), [])
    }

    // MARK: - filter

    func testFilterEmptyQueryReturnsAllUnchanged() {
        let entries = [entry(name: "a"), entry(name: "b")]
        XCTAssertEqual(EntryRules.filter(entries, query: ""), entries)
    }

    func testFilterBlankQueryReturnsAllUnchanged() {
        let entries = [entry(name: "a"), entry(name: "b")]
        XCTAssertEqual(EntryRules.filter(entries, query: "   "), entries)
    }

    func testFilterSingleWordSubstring() {
        let entries = [entry(name: "Report.pdf"), entry(name: "Invoice.pdf"), entry(name: "Notes.txt")]
        let result = EntryRules.filter(entries, query: "repo")
        XCTAssertEqual(result.map(\.name), ["Report.pdf"])
    }

    func testFilterIsCaseAndDiacriticInsensitive() {
        let entries = [entry(name: "Đơn hàng.docx"), entry(name: "other.txt")]
        let result = EntryRules.filter(entries, query: "don hang")
        XCTAssertEqual(result.map(\.name), ["Đơn hàng.docx"])
    }

    func testFilterMultiWordRequiresAllWordsAnyOrder() {
        let entries = [
            entry(name: "999 report final.pdf"),
            entry(name: "report 999.pdf"),
            entry(name: "report final.pdf"),
            entry(name: "999 only.pdf"),
        ]
        let result = EntryRules.filter(entries, query: "999 report")
        XCTAssertEqual(Set(result.map(\.name)), ["999 report final.pdf", "report 999.pdf"])
    }

    func testFilterQueryExactlyEqualsEntireName() {
        // Boundary: needle length == haystack length (and a match at the very last possible start
        // position in general) — guards an off-by-one in the substring scan's loop bound.
        let entries = [entry(name: "999"), entry(name: "9990")]
        let result = EntryRules.filter(entries, query: "999")
        XCTAssertEqual(Set(result.map(\.name)), ["999", "9990"])
    }

    func testFilterQueryMatchesOnlyAtVeryEndOfName() {
        // The word appears ONLY as the tail of the name, flush with the end — the last valid start
        // offset for the needle. An off-by-one that excludes that final offset would miss this.
        let entries = [entry(name: "report_final.pdf")]
        let result = EntryRules.filter(entries, query: "final.pdf")
        XCTAssertEqual(result.map(\.name), ["report_final.pdf"])
    }

    func testFilterNoMatchReturnsEmpty() {
        let entries = [entry(name: "a"), entry(name: "b")]
        XCTAssertEqual(EntryRules.filter(entries, query: "zzz"), [])
    }

    func testFilterQueryWithExtraWhitespaceBetweenWords() {
        let entries = [entry(name: "a b report.pdf"), entry(name: "a report.pdf")]
        let result = EntryRules.filter(entries, query: "a   b")
        XCTAssertEqual(result.map(\.name), ["a b report.pdf"])
    }

    func testFilterNonASCIIEntryNameAmongASCIIEntries() {
        // Exercises the per-entry fallback: most names are ASCII (fast path), one has accents.
        let entries = [entry(name: "cafe.txt"), entry(name: "café unique.txt"), entry(name: "other.txt")]
        let result = EntryRules.filter(entries, query: "cafe")
        XCTAssertEqual(Set(result.map(\.name)), ["cafe.txt", "café unique.txt"])
    }

    func testFilterNonASCIIQueryAgainstASCIIEntries() {
        // Exercises the whole-call fallback: the query itself is non-ASCII ("đ"), entries are ASCII.
        let entries = [entry(name: "duong pho.txt"), entry(name: "other.txt")]
        let result = EntryRules.filter(entries, query: "đường")
        XCTAssertEqual(result.map(\.name), ["duong pho.txt"])
    }

    func testFilterNonASCIIQueryAndNonASCIIEntryBothFoldToMatch() {
        let entries = [entry(name: "Đơn hàng.docx"), entry(name: "other.txt")]
        let result = EntryRules.filter(entries, query: "đơn")
        XCTAssertEqual(result.map(\.name), ["Đơn hàng.docx"])
    }

    func testFilterPerformanceUnder16ms() {
        var entries: [DirectoryEntry] = []
        entries.reserveCapacity(100_000)
        for i in 0..<100_000 {
            entries.append(entry(name: "file_\(i) a b.txt", path: "/tmp/file_\(i).txt"))
        }
        // Warm up once so the measured runs aren't paying for one-time setup costs.
        _ = EntryRules.filter(entries, query: "999")
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = EntryRules.filter(entries, query: "999")
        }
        // `swift test` builds unoptimized (no -O), so this only guards against an accidentally
        // quadratic/allocation-heavy rewrite; the spec's real "< 16 ms" budget (§6) is measured with
        // `swiftc -O` in the throwaway benchmark alongside this file, not here.
        XCTAssertLessThan(elapsed, .seconds(2), "debug-build smoke budget; -O timing is measured separately")
    }

    // MARK: - sorted: name

    func testSortedByNameUsesLocalizedStandardCompare() {
        let entries = [entry(name: "File 10"), entry(name: "File 2"), entry(name: "File 1")]
        let result = EntryRules.sorted(
            entries, by: SortOrder(key: .name, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["File 1", "File 2", "File 10"])
    }

    func testSortedByNameDescendingReversesOrder() {
        let entries = [entry(name: "File 10"), entry(name: "File 2"), entry(name: "File 1")]
        let result = EntryRules.sorted(
            entries, by: SortOrder(key: .name, ascending: false), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["File 10", "File 2", "File 1"])
    }

    func testSortedByNameTiesBreakByPath() {
        let a = entry(name: "Same", path: "/a/Same")
        let b = entry(name: "Same", path: "/b/Same")
        let result = EntryRules.sorted(
            [b, a], by: SortOrder(key: .name, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.path), ["/a/Same", "/b/Same"])
    }

    // MARK: - sorted: size

    func testSortedBySizeDirectoriesFirstAscending() {
        let dir = entry(name: "Zeta", kind: .directory, size: -1)
        let file = entry(name: "Alpha", kind: .file, size: 10)
        let result = EntryRules.sorted(
            [file, dir], by: SortOrder(key: .size, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Zeta", "Alpha"])
    }

    func testSortedBySizeZeroByteFileIsNotTreatedAsDirectory() {
        // Regression guard for the `aDir = size < 0` boundary: a 0-byte FILE must sort with files
        // (by size, among files), never before every directory the way size < 0 entries do. Several
        // zero- and small-size files plus a directory force BOTH argument orders of the internal
        // comparator during the sort, so this doesn't depend on which order `Array.sorted` happens
        // to invoke it in for a given input.
        let dir = entry(name: "Zeta", kind: .directory, size: -1, path: "/tmp/Zeta")
        let empty1 = entry(name: "Alpha", kind: .file, size: 0, path: "/tmp/Alpha")
        let empty2 = entry(name: "Beta", kind: .file, size: 0, path: "/tmp/Beta")
        let small = entry(name: "Gamma", kind: .file, size: 1, path: "/tmp/Gamma")
        let result = EntryRules.sorted(
            [dir, small, empty2, empty1], by: SortOrder(key: .size, ascending: true), foldersFirst: false,
            kindName: { _ in "" }
        )
        // Directory first, then the files in ascending size/name order: both 0-byte files tie on
        // size and break by name (Alpha, Beta), then the 1-byte file.
        XCTAssertEqual(result.map(\.name), ["Zeta", "Alpha", "Beta", "Gamma"])
    }

    func testSortedBySizeAmongDirectoriesByName() {
        let dirB = entry(name: "Beta", kind: .directory, size: -1)
        let dirA = entry(name: "Alpha", kind: .directory, size: -1)
        let result = EntryRules.sorted(
            [dirB, dirA], by: SortOrder(key: .size, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Alpha", "Beta"])
    }

    func testSortedBySizeAmongFilesBySizeThenName() {
        let small = entry(name: "Zeta", size: 1)
        let big = entry(name: "Alpha", size: 100)
        let tie1 = entry(name: "B", size: 50)
        let tie2 = entry(name: "A", size: 50)
        let result = EntryRules.sorted(
            [big, small, tie1, tie2], by: SortOrder(key: .size, ascending: true), foldersFirst: false,
            kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Zeta", "A", "B", "Alpha"])
    }

    func testSortedBySizeDescendingKeepsDirectoriesAfterFilesAndNameAscendingTieBreak() {
        // Descending reverses only the primary key: files (bigger first) then directories, name tie
        // breaks (within files of equal size, and within directories) stay ascending.
        let dir = entry(name: "Zeta", kind: .directory, size: -1)
        let fileA = entry(name: "Alpha", size: 100)
        let fileB = entry(name: "Beta", size: 10)
        let result = EntryRules.sorted(
            [dir, fileA, fileB], by: SortOrder(key: .size, ascending: false), foldersFirst: false,
            kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Alpha", "Beta", "Zeta"])
    }

    // MARK: - sorted: kind

    func testSortedByKindUsesProvidedLocalizedNameNotExtension() {
        let a = entry(name: "a.pdf", path: "/a.pdf")
        let b = entry(name: "b.txt", path: "/b.txt")
        // Deliberately invert alphabetical-by-extension: "txt" would sort before "Tài liệu PDF" by
        // raw extension, but the localized kind name "Tài liệu văn bản" sorts after "Tài liệu PDF".
        let names: [String: String] = ["/a.pdf": "Tài liệu PDF", "/b.txt": "Tài liệu văn bản"]
        let result = EntryRules.sorted(
            [b, a], by: SortOrder(key: .kind, ascending: true), foldersFirst: false,
            kindName: { names[$0.path] ?? "" }
        )
        XCTAssertEqual(result.map(\.name), ["a.pdf", "b.txt"])
    }

    func testSortedByKindTiesBreakByName() {
        let a = entry(name: "Zeta.pdf", path: "/z.pdf")
        let b = entry(name: "Alpha.pdf", path: "/a.pdf")
        let result = EntryRules.sorted(
            [a, b], by: SortOrder(key: .kind, ascending: true), foldersFirst: false,
            kindName: { _ in "Tài liệu PDF" }
        )
        XCTAssertEqual(result.map(\.name), ["Alpha.pdf", "Zeta.pdf"])
    }

    func testSortedByKindCallsClosureOncePerEntryNotPerComparison() {
        var callCount = 0
        var entries: [DirectoryEntry] = []
        for i in 0..<50 {
            entries.append(entry(name: "f\(i)", path: "/f\(i)"))
        }
        _ = EntryRules.sorted(
            entries, by: SortOrder(key: .kind, ascending: true), foldersFirst: false,
            kindName: { _ in callCount += 1; return "x" }
        )
        XCTAssertEqual(callCount, entries.count)
    }

    // MARK: - sorted: modified

    func testSortedByModifiedAscending() {
        let old = entry(name: "Old", modified: Date(timeIntervalSince1970: 0))
        let new = entry(name: "New", modified: Date(timeIntervalSince1970: 1000))
        let result = EntryRules.sorted(
            [new, old], by: SortOrder(key: .modified, ascending: true), foldersFirst: false,
            kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Old", "New"])
    }

    func testSortedByModifiedTiesBreakByName() {
        let date = Date(timeIntervalSince1970: 500)
        let a = entry(name: "Beta", modified: date)
        let b = entry(name: "Alpha", modified: date)
        let result = EntryRules.sorted(
            [a, b], by: SortOrder(key: .modified, ascending: true), foldersFirst: false,
            kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Alpha", "Beta"])
    }

    // MARK: - sorted: foldersFirst

    func testSortedFoldersFirstOverridesSortKey() {
        let file = entry(name: "AAA file", kind: .file)
        let dir = entry(name: "ZZZ dir", kind: .directory)
        let result = EntryRules.sorted(
            [file, dir], by: SortOrder(key: .name, ascending: true), foldersFirst: true,
            kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["ZZZ dir", "AAA file"])
    }

    func testSortedFoldersFirstFalseFallsBackToKey() {
        let file = entry(name: "AAA file", kind: .file)
        let dir = entry(name: "ZZZ dir", kind: .directory)
        let result = EntryRules.sorted(
            [file, dir], by: SortOrder(key: .name, ascending: true), foldersFirst: false,
            kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["AAA file", "ZZZ dir"])
    }

    func testSortedFoldersFirstHoldsEvenWhenDescending() {
        let file = entry(name: "AAA file", kind: .file)
        let dir = entry(name: "ZZZ dir", kind: .directory)
        let result = EntryRules.sorted(
            [dir, file], by: SortOrder(key: .name, ascending: false), foldersFirst: true,
            kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["ZZZ dir", "AAA file"])
    }

    func testSortedFoldersFirstIgnoredWhenSortingBySize() {
        // FileOctopus R18 / Finder: "Keep folders on top" only applies "when sorting by name" — sorting by size (or
        // kind, or a date) must NOT be overridden even when foldersFirst is on.
        let file = entry(name: "AAA file", kind: .file, size: 100)
        let dir = entry(name: "ZZZ dir", kind: .directory, size: -1)
        let result = EntryRules.sorted(
            [file, dir], by: SortOrder(key: .size, ascending: true), foldersFirst: true,
            kindName: { _ in "" }
        )
        // Plain size order (directories still sort first because size -1 < any file size — that is the .size
        // comparator's own rule, not foldersFirst), identical to foldersFirst: false for this input.
        let withoutFoldersFirst = EntryRules.sorted(
            [file, dir], by: SortOrder(key: .size, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), withoutFoldersFirst.map(\.name))
    }

    func testSortedFoldersFirstIgnoredWhenSortingByKind() {
        let file = entry(name: "AAA file", kind: .file, path: "/f")
        let dir = entry(name: "ZZZ dir", kind: .directory, path: "/d")
        let names: [String: String] = ["/f": "Tài liệu", "/d": "Thư mục"]
        let result = EntryRules.sorted(
            [file, dir], by: SortOrder(key: .kind, ascending: true), foldersFirst: true,
            kindName: { names[$0.path] ?? "" }
        )
        // "Thư mục" < "Tài liệu" alphabetically either way; the point is foldersFirst did not insert an extra
        // folders-before-files pass above the kind comparison (there is only one plausible order here regardless,
        // so this mainly guards that passing foldersFirst: true does not crash or reorder unexpectedly elsewhere).
        XCTAssertEqual(Set(result.map(\.name)), ["AAA file", "ZZZ dir"])
    }

    // MARK: - sorted: created / added / lastOpened

    func testSortedByCreatedAscending() {
        let old = entry(name: "Old", created: Date(timeIntervalSince1970: 0))
        let new = entry(name: "New", created: Date(timeIntervalSince1970: 1000))
        let result = EntryRules.sorted(
            [new, old], by: SortOrder(key: .created, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Old", "New"])
    }

    func testSortedByAddedNilSortsLast() {
        let withDate = entry(name: "HasDate", added: Date(timeIntervalSince1970: 0))
        let noDate = entry(name: "NoDate", added: nil)
        let result = EntryRules.sorted(
            [noDate, withDate], by: SortOrder(key: .added, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["HasDate", "NoDate"])
    }

    func testSortedByAddedNilSortsLastEvenDescending() {
        // nil dates are "last" regardless of sort direction, not merely "smallest" (which would put them first when
        // descending) — ascending=false must still leave the undated entry at the very end.
        let withDate = entry(name: "HasDate", added: Date(timeIntervalSince1970: 1000))
        let noDate = entry(name: "NoDate", added: nil)
        let result = EntryRules.sorted(
            [noDate, withDate], by: SortOrder(key: .added, ascending: false), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["HasDate", "NoDate"])
    }

    func testSortedByLastOpenedNilSortsLast() {
        let opened = entry(name: "Opened", lastOpened: Date(timeIntervalSince1970: 500))
        let neverOpened = entry(name: "Never", lastOpened: nil)
        let result = EntryRules.sorted(
            [neverOpened, opened], by: SortOrder(key: .lastOpened, ascending: true), foldersFirst: false,
            kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Opened", "Never"])
    }

    func testSortedByLastOpenedTiesBreakByName() {
        let date = Date(timeIntervalSince1970: 500)
        let a = entry(name: "Beta", lastOpened: date)
        let b = entry(name: "Alpha", lastOpened: date)
        let result = EntryRules.sorted(
            [a, b], by: SortOrder(key: .lastOpened, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Alpha", "Beta"])
    }

    func testSortedByAddedAllNilKeepsStableNameTieBreak() {
        let a = entry(name: "Beta", added: nil)
        let b = entry(name: "Alpha", added: nil)
        let result = EntryRules.sorted(
            [a, b], by: SortOrder(key: .added, ascending: true), foldersFirst: false, kindName: { _ in "" }
        )
        XCTAssertEqual(result.map(\.name), ["Alpha", "Beta"])
    }

    // MARK: - sorted: empty / single

    func testSortedEmptyInput() {
        XCTAssertEqual(
            EntryRules.sorted([], by: .finderDefault, foldersFirst: false, kindName: { _ in "" }), []
        )
    }

    func testFinderDefaultIsNameAscending() {
        XCTAssertEqual(SortOrder.finderDefault.key, .name)
        XCTAssertTrue(SortOrder.finderDefault.ascending)
    }

    // MARK: - TypeSelect

    func testTypeSelectAccumulatesWithinTimeout() {
        var ts = EntryRules.TypeSelect()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(ts.type("r", at: t0), "r")
        XCTAssertEqual(ts.type("e", at: t0.addingTimeInterval(0.3)), "re")
        XCTAssertEqual(ts.type("p", at: t0.addingTimeInterval(0.6)), "rep")
    }

    func testTypeSelectResetsAfterTimeout() {
        var ts = EntryRules.TypeSelect()
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = ts.type("r", at: t0)
        let result = ts.type("x", at: t0.addingTimeInterval(1.5))
        XCTAssertEqual(result, "x")
    }

    func testTypeSelectExactlyAtTimeoutBoundaryStillAccumulates() {
        // "quá timeout" (strictly greater than) resets; exactly at the boundary does not.
        var ts = EntryRules.TypeSelect()
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = ts.type("r", at: t0)
        let result = ts.type("e", at: t0.addingTimeInterval(EntryRules.TypeSelect.timeout))
        XCTAssertEqual(result, "re")
    }

    func testTypeSelectInitialBufferEmpty() {
        let ts = EntryRules.TypeSelect()
        XCTAssertEqual(ts.buffer, "")
    }

    // MARK: - TypeSelect.match

    func testTypeSelectMatchFindsFirstPrefixMatch() {
        let names = ["Alpha", "Beta", "Bravo", "Charlie"]
        XCTAssertEqual(EntryRules.TypeSelect.match(prefix: "b", in: names), 1)
    }

    func testTypeSelectMatchIsCaseAndDiacriticInsensitive() {
        let names = ["alpha", "Đơn hàng", "zeta"]
        XCTAssertEqual(EntryRules.TypeSelect.match(prefix: "don", in: names), 1)
    }

    func testTypeSelectMatchFallsBackToFirstGreaterWhenNoPrefixMatch() {
        let names = ["Alpha", "Delta", "Zeta"]
        // No name starts with "c", but "Delta" is the first entry that sorts after "c".
        XCTAssertEqual(EntryRules.TypeSelect.match(prefix: "c", in: names), 1)
    }

    func testTypeSelectMatchFallsBackToLastWhenPrefixSortsAfterEverything() {
        let names = ["Alpha", "Beta", "Charlie"]
        XCTAssertEqual(EntryRules.TypeSelect.match(prefix: "zzz", in: names), 2)
    }

    func testTypeSelectMatchEmptyNamesReturnsNil() {
        XCTAssertNil(EntryRules.TypeSelect.match(prefix: "a", in: []))
    }

    func testTypeSelectMatchEmptyPrefixReturnsNil() {
        XCTAssertNil(EntryRules.TypeSelect.match(prefix: "", in: ["Alpha"]))
    }

    func testTypeSelectMatchUsesExistingOrderNotSortedOrder() {
        // "existing order" ("theo thứ tự hiện có"): names is NOT sorted here; the fallback scans the
        // array's own order rather than re-sorting it. "zz" prefix-matches nothing and sorts after
        // every name below, so the result must be the LAST index (the "none left" fallback), which
        // only makes sense if the scan went through the array in the given (unsorted) order.
        let names = ["Zeta", "Alpha", "Mango"]
        XCTAssertEqual(EntryRules.TypeSelect.match(prefix: "zz", in: names), 2)
    }

    func testTypeSelectMatchFirstGreaterScansGivenOrderNotSorted() {
        // No name has prefix "c"; in ARRAY order (not sorted order) "Delta" at index 0 is the first
        // element that sorts after "c", even though "Alpha" later in the array would sort before
        // "Delta" if the whole array were sorted first.
        let names = ["Delta", "Alpha"]
        XCTAssertEqual(EntryRules.TypeSelect.match(prefix: "c", in: names), 0)
    }

    func testTypeSelectMatchFallbackUsesNaturalOrderNotPlainStringCompare() {
        // Bug found in review: the list a real pane shows is sorted with `localizedStandardCompare`
        // (EntryRules.sorted / spec's name rule), which treats "file2" < "file10" < "file99" (natural
        // sort, digits compared as numbers). A plain Swift `String >` instead compares byte-by-byte,
        // where the character '1' < '5' makes "file10" look SMALLER than "file5" even though natural
        // order puts "file10" right after it. Typing "file5" with no exact match in this (naturally
        // sorted) list must land at the natural insertion point — between "file2" and "file10", i.e.
        // index 1 — not skip past "file10" to "file99" (index 2) the way raw lexical comparison does.
        let names = ["file2", "file10", "file99"]
        XCTAssertEqual(EntryRules.TypeSelect.match(prefix: "file5", in: names), 1)
    }

    func testTypeSelectMatchFallbackNaturalOrderWithCaseVariants() {
        // Plain `String >` is also case-sensitive in a way that disagrees with localizedStandardCompare
        // (and with `foldKey`, which this whole type already uses for prefix matching): "Banana" should
        // land after "apple" in natural/case-insensitive order, not be skipped because 'B' < 'a' in
        // raw Unicode scalar order.
        let names = ["apple", "cherry"]
        XCTAssertEqual(EntryRules.TypeSelect.match(prefix: "banana", in: names), 1)
    }
}

/// 2026-10-24 — the precomputed fold key and natural compare that took filtering from 363 ms to 2 ms and name sorting
/// from 735 ms to 38 ms per 100 000 entries (-O). Semantics must stay Finder's: case/accent-insensitive, "đ" = "d",
/// numbers by value, digits before letters.
final class DirectoryEntryFoldKeyTests: XCTestCase {
    func entry(_ name: String) -> DirectoryEntry {
        DirectoryEntry(name: name, path: "/t/\(name)", kind: .file, isPackage: false, isHidden: false, size: 1,
                       modified: Date(timeIntervalSince1970: 0), created: Date(timeIntervalSince1970: 0), volumeID: 1)
    }

    func testNameKeyIsTheFoldedName() {
        for n in ["Report.PDF", "Đơn hàng Ảnh.xlsx", "ĐỒNG Ý", "café ß", "日本語ファイル", "Ứng dụng"] {
            XCTAssertEqual(entry(n).nameKey, Array(EntryRules.foldKey(n).utf8), n)
        }
        XCTAssertEqual(EntryRules.foldKey("Đơn HÀNG Ảnh Tiếng Việt"), "don hang anh tieng viet")
        XCTAssertEqual(EntryRules.foldKey("ỨNG dụng Ộ ữ"), "ung dung o u")
    }

    func testVietnameseFilterWithoutAccents() {
        let list = ["Đơn hàng 12.xlsx", "Ảnh chụp màn hình.png", "Report.pdf"].map(entry)
        XCTAssertEqual(EntryRules.filter(list, query: "don hang").map(\.name), ["Đơn hàng 12.xlsx"])
        XCTAssertEqual(EntryRules.filter(list, query: "ĐƠN").map(\.name), ["Đơn hàng 12.xlsx"])
        XCTAssertEqual(EntryRules.filter(list, query: "anh chup").map(\.name), ["Ảnh chụp màn hình.png"])
        XCTAssertEqual(EntryRules.filter(list, query: "chụp ảnh").map(\.name), ["Ảnh chụp màn hình.png"], "any word order")
    }

    func testNaturalCompare() {
        func c(_ a: String, _ b: String) -> Int { EntryRules.naturalCompare(Array(EntryRules.foldKey(a).utf8), Array(EntryRules.foldKey(b).utf8)) }
        XCTAssertEqual(c("File 2", "File 10"), -1)
        XCTAssertEqual(c("File 10", "File 2"), 1)
        XCTAssertEqual(c("file 007", "file 7"), 0, "leading zeros do not change the value")
        XCTAssertEqual(c("a99", "a100"), -1)
        XCTAssertEqual(c("9 lives", "apple"), -1, "digits before letters, as in Finder")
        XCTAssertEqual(c("Ảnh", "anh"), 0, "accents and case are a tie at this level")
        XCTAssertEqual(c("abc", "abcd"), -1)
        XCTAssertEqual(c("", "a"), -1)
    }

    func testNameSortIsNaturalAndAccentInsensitiveWithPathTieBreak() {
        let list = ["file10", "File2", "ảnh 3", "anh 20", "Anh 1"].map(entry)
        let sorted = EntryRules.sorted(list, by: .finderDefault, foldersFirst: false, kindName: { _ in "" }).map(\.name)
        XCTAssertEqual(sorted, ["Anh 1", "ảnh 3", "anh 20", "File2", "file10"])
        let twins = [entry("B"), entry("b")]   // a case-sensitive volume can hold both
        let t = EntryRules.sorted(twins, by: .finderDefault, foldersFirst: false, kindName: { _ in "" }).map(\.path)
        XCTAssertEqual(t, ["/t/B", "/t/b"], "equal keys break by path, deterministically")
    }
}
