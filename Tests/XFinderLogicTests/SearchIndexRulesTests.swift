import XCTest

/// XF-T30 W5a — exclusions (whole path component, not substring), content-kind table, FSEvents flag mapping (real
/// `kFSEventStreamEventFlag*` raw values), `validateNewRoot`, and the L10n key for every status.
final class SearchIndexRulesTests: XCTestCase {
    let home = "/Users/alice"

    // MARK: Exclusions

    func testLibraryItselfIsExcluded() {
        XCTAssertTrue(SearchIndexRules.isExcluded("/Users/alice/Library", home: home))
    }

    func testBelowLibraryIsExcluded() {
        XCTAssertTrue(SearchIndexRules.isExcluded("/Users/alice/Library/Application Support/Foo", home: home))
    }

    func testOutsideLibraryIsNotExcluded() {
        XCTAssertFalse(SearchIndexRules.isExcluded("/Users/alice/Documents/Report.pdf", home: home))
    }

    func testEachExcludedNameAsAPathComponentIsExcluded() {
        for name in SearchIndexRules.excludedDirectoryNames {
            XCTAssertTrue(SearchIndexRules.isExcluded("/Users/alice/Projects/app/\(name)/x.txt", home: home), name)
            XCTAssertTrue(SearchIndexRules.isExcluded("/Users/alice/Projects/app/\(name)", home: home), name)
        }
    }

    // Not a substring: a folder literally named "node_modules-archive" is a different component and must NOT match.
    func testExcludedNameAsASubstringOfALongerComponentIsNotExcluded() {
        XCTAssertFalse(SearchIndexRules.isExcluded("/Users/alice/Projects/node_modules-archive/x.txt", home: home))
        XCTAssertFalse(SearchIndexRules.isExcluded("/Users/alice/Projects/my.build/x.txt", home: home))
        XCTAssertFalse(SearchIndexRules.isExcluded("/Users/alice/Projects/rebuild/x.txt", home: home))
    }

    func testPositiveControlPlainPathIsNeverExcluded() {
        XCTAssertFalse(SearchIndexRules.isExcluded("/Users/alice/Desktop/notes.txt", home: home))
    }

    // MARK: contentKind

    func testContentKindTable() {
        let cases: [(String, IndexContentKind)] = [
            ("txt", .plainText), ("TXT", .plainText), ("md", .plainText), ("json", .plainText), ("swift", .plainText),
            ("pdf", .pdf), ("PDF", .pdf),
            ("rtf", .richText), ("rtfd", .richText), ("doc", .richText), ("docx", .richText), ("odt", .richText),
            ("html", .richText), ("htm", .richText),
            ("png", .image), ("jpg", .image), ("jpeg", .image), ("heic", .image), ("tiff", .image), ("gif", .image),
            ("bmp", .image), ("webp", .image),
            ("pages", .none), ("zip", .none), ("mp4", .none), ("", .none),
        ]
        for (ext, expected) in cases {
            XCTAssertEqual(SearchIndexRules.contentKind(forExtension: ext), expected, ext)
        }
    }

    // MARK: FSEvents flag mapping — real raw values, verified against the live CoreServices SDK by probe (positive
    // control: every constant checked equal to its documented hex value in the same run).

    func testMustScanSubDirsRescans() {
        XCTAssertEqual(SearchIndexRules.action(path: "/a", flags: 0x1), .rescanSubtree("/a"))
    }

    func testUserDroppedRescans() {
        XCTAssertEqual(SearchIndexRules.action(path: "/a", flags: 0x2), .rescanSubtree("/a"))
    }

    func testKernelDroppedRescans() {
        XCTAssertEqual(SearchIndexRules.action(path: "/a", flags: 0x4), .rescanSubtree("/a"))
    }

    func testRootChangedWinsOverEverythingElse() {
        // RootChanged combined with other flags still reports rootChanged — the root itself moved/was replaced.
        XCTAssertEqual(SearchIndexRules.action(path: "/a", flags: 0x20 | 0x200), .rootChanged)
        XCTAssertEqual(SearchIndexRules.action(path: "/a", flags: 0x20), .rootChanged)
    }

    func testRootChangedWinsSpecificallyOverMustScanSubDirs() {
        // The one combination that actually distinguishes "RootChanged checked first" from "rescan checked first":
        // RootChanged (0x20) together with MustScanSubDirs (0x1) must still report rootChanged, not rescanSubtree.
        XCTAssertEqual(SearchIndexRules.action(path: "/a", flags: 0x20 | 0x1), .rootChanged)
    }

    func testItemRemovedRemovesThePath() {
        XCTAssertEqual(SearchIndexRules.action(path: "/a/gone.txt", flags: 0x200), .removePath("/a/gone.txt"))
    }

    func testPlainChangeUpdatesThePath() {
        // kFSEventStreamEventFlagItemModified = 0x1000, none of the special flags above.
        XCTAssertEqual(SearchIndexRules.action(path: "/a/b.txt", flags: 0x1000), .updatePath("/a/b.txt"))
    }

    func testNoFlagsAtAllIsAPlainUpdate() {
        XCTAssertEqual(SearchIndexRules.action(path: "/a/b.txt", flags: 0), .updatePath("/a/b.txt"))
    }

    func testPositiveControlDistinctFlagsGiveDistinctActions() {
        let rescan = SearchIndexRules.action(path: "/a", flags: 0x1)
        let removed = SearchIndexRules.action(path: "/a", flags: 0x200)
        XCTAssertNotEqual(rescan, removed)
    }

    // MARK: validateNewRoot

    func testPlainNewRootIsOK() {
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/Documents", isDirectory: true, existing: [], home: home), .ok)
    }

    func testNotADirectoryIsRejected() {
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/notes.txt", isDirectory: false, existing: [], home: home), .notADirectory)
    }

    func testExcludedPathIsRejected() {
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/Library", isDirectory: true, existing: [], home: home), .excluded)
    }

    func testNewRootInsideAnExistingOneIsAlreadyCovered() {
        let existing = [IndexRoot(id: "1", path: "/Users/alice/Documents", contents: false, textInImages: false, paused: false, device: nil, inode: nil)]
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/Documents/Reports", isDirectory: true, existing: existing, home: home),
                       .alreadyCovered(by: "/Users/alice/Documents"))
    }

    func testIdenticalRootIsAlreadyCovered() {
        let existing = [IndexRoot(id: "1", path: "/Users/alice/Documents", contents: false, textInImages: false, paused: false, device: nil, inode: nil)]
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/Documents", isDirectory: true, existing: existing, home: home),
                       .alreadyCovered(by: "/Users/alice/Documents"))
    }

    func testNewRootContainingExistingRootsCoversThem() {
        let existing = [
            IndexRoot(id: "1", path: "/Users/alice/Documents/Reports", contents: false, textInImages: false, paused: false, device: nil, inode: nil),
            IndexRoot(id: "2", path: "/Users/alice/Documents/Invoices", contents: false, textInImages: false, paused: false, device: nil, inode: nil),
        ]
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/Documents", isDirectory: true, existing: existing, home: home),
                       .coversExisting(["/Users/alice/Documents/Reports", "/Users/alice/Documents/Invoices"]))
    }

    // Trailing-slash and lexical comparison: no real symlink resolution here (pure), just path components.
    func testTrailingSlashDoesNotChangeTheComparison() {
        let existing = [IndexRoot(id: "1", path: "/Users/alice/Documents/", contents: false, textInImages: false, paused: false, device: nil, inode: nil)]
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/Documents", isDirectory: true, existing: existing, home: home),
                       .alreadyCovered(by: "/Users/alice/Documents/"))
    }

    func testDoubleSlashesAndDotComponentsCollapseTheSameWay() {
        let existing = [IndexRoot(id: "1", path: "/Users/alice//Documents/./", contents: false, textInImages: false, paused: false, device: nil, inode: nil)]
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/Documents", isDirectory: true, existing: existing, home: home),
                       .alreadyCovered(by: "/Users/alice//Documents/./"))
    }

    func testUnrelatedExistingRootIsOK() {
        let existing = [IndexRoot(id: "1", path: "/Users/alice/Downloads", contents: false, textInImages: false, paused: false, device: nil, inode: nil)]
        XCTAssertEqual(SearchIndexRules.validateNewRoot("/Users/alice/Documents", isDirectory: true, existing: existing, home: home), .ok)
    }

    // MARK: statusKey
    //
    // The keys below are added to the shipped L10n store by `scripts/add-xf-t30-w5a-p-l10n-entries.py` (add-only;
    // run to verify, then reverted before commit per the W5a fan-out process — the integrator applies every
    // builder's script together, see CLAUDE.md §18 "L10n là việc của người tích hợp"). This test only checks the
    // property that is this file's own responsibility (every status reads distinctly, never empty); the store
    // membership was confirmed by running the script locally (see the commit message).

    func testEveryStatusHasADistinctNonEmptyKey() {
        let statuses: [IndexRootStatus] = [.indexing(done: 1), .updating(changes: 2), .ready, .paused, .offline,
                                            .noAccess, .movedOrReplaced, .failed]
        let keys = statuses.map(SearchIndexRules.statusKey)
        for k in keys { XCTAssertFalse(k.isEmpty) }
        XCTAssertEqual(Set(keys).count, keys.count, "every status must read differently")
    }

    func testIndexingAndUpdatingShareTheSameKeyRegardlessOfCount() {
        // The count is reported elsewhere (progress UI, not W5a) — the key itself must not vary per count.
        XCTAssertEqual(SearchIndexRules.statusKey(.indexing(done: 1)), SearchIndexRules.statusKey(.indexing(done: 999)))
        XCTAssertEqual(SearchIndexRules.statusKey(.updating(changes: 1)), SearchIndexRules.statusKey(.updating(changes: 999)))
    }
}
