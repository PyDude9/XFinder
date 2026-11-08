import XCTest

/// XF-T37 L2 — batch rename: Finder's three modes, FileOctopus's "one error blocks the batch", and the two-phase run on a
/// real temporary folder (swap, chain, case-only, rollback after a failure in either phase).
final class BatchRenameRulesTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let date = Date(timeIntervalSince1970: 1_793_000_000)   // 2026-10-26 07:33:20 UTC

    private func item(_ path: String, folder: Bool = false) -> BatchRenameRules.Item {
        BatchRenameRules.Item(path: path, isFolder: folder, modified: date)
    }

    private func names(_ items: [BatchRenameRules.Item], _ options: BatchRenameRules.Options) -> [String] {
        items.enumerated().map { BatchRenameRules.newName(for: $1, index: $0, options: options, calendar: calendar, dateConnector: " at ") }
    }

    private func plan(_ items: [BatchRenameRules.Item], _ options: BatchRenameRules.Options,
                      siblings: [String: Set<String>] = [:]) -> BatchRenameRules.Plan {
        BatchRenameRules.plan(items: items, options: options, siblings: { siblings[$0] }, calendar: calendar, dateConnector: " at ")
    }

    // MARK: - Names

    func testReplaceTextLeavesTheExtensionUnlessIncluded() {
        var o = BatchRenameRules.Options()
        o.mode = .replaceText; o.find = "pdf"; o.replaceWith = "doc"
        XCTAssertEqual(names([item("/d/pdf notes.pdf")], o), ["doc notes.pdf"])
        o.includeExtension = true
        XCTAssertEqual(names([item("/d/pdf notes.pdf")], o), ["doc notes.doc"])
        o.find = ""
        XCTAssertEqual(names([item("/d/a.txt")], o), ["a.txt"], "an empty Find changes nothing")
    }

    func testAddTextBeforeAndAfter() {
        var o = BatchRenameRules.Options()
        o.mode = .addText; o.addText = " v2"; o.addPosition = .after
        XCTAssertEqual(names([item("/d/Report.pdf"), item("/d/Photos", folder: true)], o), ["Report v2.pdf", "Photos v2"])
        o.addText = "Old "; o.addPosition = .before
        XCTAssertEqual(names([item("/d/Report.pdf")], o), ["Old Report.pdf"])
        o.includeExtension = true; o.addText = ".bak"; o.addPosition = .after
        XCTAssertEqual(names([item("/d/Report.pdf")], o), ["Report.pdf.bak"])
    }

    func testFormatStylesFollowFinder() {
        var o = BatchRenameRules.Options()
        o.mode = .format; o.customName = "Trip "; o.startNumber = 1
        let items = [item("/d/a.jpg"), item("/d/b.jpg"), item("/d/c")]
        o.formatStyle = .nameAndIndex
        XCTAssertEqual(names(items, o), ["Trip 1.jpg", "Trip 2.jpg", "Trip 3"])
        o.formatStyle = .nameAndCounter; o.startNumber = 9
        XCTAssertEqual(names(items, o), ["Trip 00009.jpg", "Trip 00010.jpg", "Trip 00011"])
        o.formatPosition = .before; o.formatStyle = .nameAndIndex; o.startNumber = 0
        XCTAssertEqual(names(items, o), ["0Trip .jpg", "1Trip .jpg", "2Trip "], "Finder adds no separator — the space is the user's")
        o.formatPosition = .after; o.formatStyle = .nameAndDate
        XCTAssertEqual(names([item("/d/a.jpg")], o), ["Trip 2026-10-26 at 07.33.20.jpg"])
        o.startNumber = -5; o.formatStyle = .nameAndIndex
        XCTAssertEqual(names([item("/d/a.jpg")], o), ["Trip 0.jpg"], "a negative start is clamped to 0")
    }

    // MARK: - Plan

    func testCaseOnlyRenameIsAllowedNotAConflict() {
        var o = BatchRenameRules.Options()
        o.mode = .replaceText; o.find = "report"; o.replaceWith = "Report"
        let p = plan([item("/d/report.txt")], o, siblings: ["/d": ["report.txt", "other.txt"]])
        XCTAssertEqual(p.rows[0].issues, [])
        XCTAssertEqual(p.rows[0].notes, [.caseOnly])
        XCTAssertTrue(p.canRename)
    }

    func testExistingNameInFolderBlocksTheWholeBatch() {
        var o = BatchRenameRules.Options()
        o.mode = .replaceText; o.find = "a"; o.replaceWith = "b"
        let p = plan([item("/d/a.txt"), item("/d/c-a.txt")], o, siblings: ["/d": ["a.txt", "c-a.txt", "B.TXT"]])
        XCTAssertEqual(p.rows[0].issues, [.existsInFolder], "b.txt vs B.TXT on a case-insensitive volume")
        XCTAssertEqual(p.rows[1].issues, [])
        XCTAssertEqual(p.renameCount, 1)
        XCTAssertEqual(p.errorCount, 1)
        XCTAssertFalse(p.canRename, "FileOctopus: one error disables Rename for every item")
    }

    func testDuplicateInsideTheBatch() {
        let items = [item("/d/1.txt"), item("/d/2.txt")]
        let p = BatchRenameRules.validate(items: items, newNames: ["same.txt", "SAME.txt"], siblings: { _ in ["1.txt", "2.txt"] })
        XCTAssertEqual(p.rows.map(\.issues), [[.duplicateInBatch], [.duplicateInBatch]])
        XCTAssertFalse(p.canRename)
    }

    // MARK: - Name and Date ties (Q-T37-3)

    private func dated(_ path: String, _ seconds: TimeInterval, folder: Bool = false) -> BatchRenameRules.Item {
        BatchRenameRules.Item(path: path, isFolder: folder, modified: Date(timeIntervalSince1970: seconds))
    }

    private var dateOptions: BatchRenameRules.Options {
        var o = BatchRenameRules.Options()
        o.mode = .format; o.formatStyle = .nameAndDate; o.customName = "Scan "
        return o
    }

    func testSameSecondItemsAreNumberedInTimeOrder() {
        let base = 1_793_000_000.0
        // Same second, different sub-second times; the list order is not the time order.
        let items = [dated("/d/b.pdf", base + 0.5), dated("/d/c.pdf", base + 0.9), dated("/d/a.pdf", base + 0.2),
                     dated("/d/z.pdf", base + 7)]
        let p = plan(items, dateOptions, siblings: ["/d": ["a.pdf", "b.pdf", "c.pdf", "z.pdf"]])
        XCTAssertEqual(p.rows.map(\.newName), ["Scan 2026-10-26 at 07.33.20-2.pdf", "Scan 2026-10-26 at 07.33.20-3.pdf",
                                               "Scan 2026-10-26 at 07.33.20-1.pdf", "Scan 2026-10-26 at 07.33.27.pdf"])
        XCTAssertEqual(p.rows.map(\.issues), [[], [], [], []], "a tie never blocks the batch")
        XCTAssertTrue(p.canRename)
        // Sorting the new names puts them in true time order.
        let byName = p.rows.sorted { $0.newName < $1.newName }.map(\.oldName)
        XCTAssertEqual(byName, ["a.pdf", "b.pdf", "c.pdf", "z.pdf"])
    }

    func testTieNumbersArePaddedToTheGroupSize() {
        let items = (1...12).map { dated("/d/\($0).jpg", 1_793_000_000 + Double($0) / 100) }
        let p = plan(items, dateOptions, siblings: ["/d": Set((1...12).map { "\($0).jpg" })])
        XCTAssertEqual(p.rows.first?.newName, "Scan 2026-10-26 at 07.33.20-01.jpg")
        XCTAssertEqual(p.rows.last?.newName, "Scan 2026-10-26 at 07.33.20-12.jpg")
        XCTAssertEqual(p.rows.map(\.newName), p.rows.map(\.newName).sorted(), "zero-padding keeps byte order = time order")
    }

    func testANameAlreadyInTheFolderIsNumberedAround() {
        let items = [dated("/d/a.pdf", 1_793_000_000)]
        let taken: Set<String> = ["a.pdf", "Scan 2026-10-26 at 07.33.20.pdf", "Scan 2026-10-26 at 07.33.20-1.pdf"]
        let p = plan(items, dateOptions, siblings: ["/d": taken])
        XCTAssertEqual(p.rows[0].newName, "Scan 2026-10-26 at 07.33.20-2.pdf")
        XCTAssertEqual(p.rows[0].issues, [])
    }

    func testTiesWithoutAnExtensionAndFolders() {
        let items = [dated("/d/notes", 1_793_000_000), dated("/d/Photos", 1_793_000_000.4, folder: true)]
        let p = plan(items, dateOptions, siblings: ["/d": ["notes", "Photos"]])
        XCTAssertEqual(p.rows.map(\.newName), ["Scan 2026-10-26 at 07.33.20-1", "Scan 2026-10-26 at 07.33.20-2"])
        XCTAssertEqual(p.rows.map(\.notes), [[], []], "the time's dots are not a new extension")
    }

    func testTieName() {
        XCTAssertEqual(BatchRenameRules.tieName("X 07.33.20.jpg", number: 3, width: 2, originalExtension: "jpg"), "X 07.33.20-03.jpg")
        XCTAssertEqual(BatchRenameRules.tieName("X 07.33.20", number: 1, width: 1, originalExtension: ""), "X 07.33.20-1")
        XCTAssertEqual(BatchRenameRules.tieName("X 07.33.20", number: 12, width: 1, originalExtension: ""), "X 07.33.20-12")
    }

    func testIndexModeIsNotRenumbered() {
        var o = BatchRenameRules.Options()
        o.mode = .format; o.formatStyle = .nameAndIndex; o.customName = "A"; o.startNumber = 1
        let p = plan([item("/d/x.txt"), item("/d/y.txt")], o, siblings: ["/d": ["x.txt", "y.txt", "A1.txt"]])
        XCTAssertEqual(p.rows[0].issues, [.existsInFolder], "only Name and Date numbers around clashes")
    }

    func testChainAndSwapAreAllowed() {
        var o = BatchRenameRules.Options()
        o.mode = .format; o.customName = ""; o.startNumber = 1
        // 2.txt → 1.txt and 1.txt → 2.txt (a swap); 3.txt keeps its name.
        let swap = plan([item("/d/2.txt"), item("/d/1.txt"), item("/d/3.txt")], o, siblings: ["/d": ["1.txt", "2.txt", "3.txt"]])
        XCTAssertEqual(swap.rows.map(\.newName), ["1.txt", "2.txt", "3.txt"])
        XCTAssertEqual(swap.rows.map(\.issues), [[], [], []])
        XCTAssertTrue(swap.rows[2].isUnchanged)
        XCTAssertEqual(swap.renameCount, 2)
        XCTAssertTrue(swap.canRename)
        // A chain: 1.txt → 2.txt while 2.txt → 3.txt.
        o.startNumber = 2
        let chain = plan([item("/d/1.txt"), item("/d/2.txt")], o, siblings: ["/d": ["1.txt", "2.txt"]])
        XCTAssertEqual(chain.rows.map(\.newName), ["2.txt", "3.txt"])
        XCTAssertEqual(chain.rows.map(\.issues), [[], []])
        XCTAssertTrue(chain.canRename)
    }

    func testAnUnchangedBatchItemKeepsItsNameTaken() {
        var o = BatchRenameRules.Options()
        o.mode = .replaceText; o.find = "1"; o.replaceWith = "3"
        let p = plan([item("/d/1.txt"), item("/d/3.txt")], o, siblings: ["/d": ["1.txt", "3.txt"]])
        XCTAssertTrue(p.rows[1].isUnchanged)
        XCTAssertEqual(p.rows[0].issues, [.existsInFolder])
        XCTAssertFalse(p.canRename)
    }

    func testNameProblemsAndDiskFacts() {
        var o = BatchRenameRules.Options()
        o.mode = .replaceText; o.find = "x"; o.replaceWith = "a/b"
        var missing = item("/d/x1"); missing.exists = false
        var locked = item("/d/x2"); locked.isLocked = true
        var readOnly = item("/e/x3"); readOnly.parentWritable = false
        let p = plan([item("/d/x0"), missing, locked, readOnly], o)
        XCTAssertEqual(p.rows[0].issues, [.name(.separator)])
        XCTAssertEqual(p.rows[1].issues, [.missing, .name(.separator)])
        XCTAssertEqual(p.rows[2].issues, [.locked, .name(.separator)])
        XCTAssertEqual(p.rows[3].issues, [.noPermission, .name(.separator)])
    }

    func testItemInsideAFolderBeingRenamed() {
        var o = BatchRenameRules.Options()
        o.mode = .addText; o.addText = "_"; o.addPosition = .before
        let p = plan([item("/d/Photos", folder: true), item("/d/Photos/a.jpg")], o)
        XCTAssertEqual(p.rows[0].issues, [])
        XCTAssertEqual(p.rows[1].issues, [.insideRenamedItem])
        XCTAssertFalse(BatchRenameRules.isInsideChanging("/d/Photos2/a.jpg", changing: ["/d/Photos"]), "a sibling with a longer name is not inside")
    }

    func testNothingToRenameDisablesRename() {
        let p = plan([item("/d/a.txt")], BatchRenameRules.Options())
        XCTAssertEqual(p.renameCount, 0)
        XCTAssertFalse(p.canRename)
        XCTAssertTrue(p.pairs.isEmpty)
    }

    // MARK: - Execute (real files)

    private func tempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xf-t37-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func write(_ dir: String, _ name: String, _ text: String) {
        FileManager.default.createFile(atPath: (dir as NSString).appendingPathComponent(name), contents: Data(text.utf8))
    }

    private func read(_ dir: String, _ name: String) -> String? {
        (try? Data(contentsOf: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(name)))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func listing(_ dir: String) -> [String] { (BatchRenameRules.directoryNames(dir) ?? []).sorted() }

    func testSwapCaseOnlyAndChainOnDisk() throws {
        let d = try tempDir()
        write(d, "a.txt", "A"); write(d, "b.txt", "B"); write(d, "report.txt", "R"); write(d, "c.txt", "C")
        func at(_ n: String) -> String { (d as NSString).appendingPathComponent(n) }
        let pairs = [(from: at("a.txt"), to: at("b.txt")), (from: at("b.txt"), to: at("a.txt")),
                     (from: at("report.txt"), to: at("Report.txt")), (from: at("c.txt"), to: at("d.txt"))]
        let outcome = BatchRenameRules.execute(pairs)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(read(d, "b.txt"), "A")
        XCTAssertEqual(read(d, "a.txt"), "B")
        XCTAssertEqual(read(d, "d.txt"), "C")
        XCTAssertEqual(listing(d), ["Report.txt", "a.txt", "b.txt", "d.txt"], "case-only rename landed, no temporary left")
    }

    func testFailureInPhaseTwoPutsEveryItemBack() throws {
        let d = try tempDir()
        write(d, "a.txt", "A"); write(d, "b.txt", "B"); write(d, "taken.txt", "T")
        func at(_ n: String) -> String { (d as NSString).appendingPathComponent(n) }
        // b.txt → taken.txt collides with an item outside the batch: RENAME_EXCL refuses it in phase 2.
        let outcome = BatchRenameRules.execute([(from: at("a.txt"), to: at("x.txt")), (from: at("b.txt"), to: at("taken.txt"))])
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.failedPath, at("b.txt"))
        XCTAssertEqual(outcome.failedErrno, EEXIST)
        XCTAssertEqual(outcome.stranded, [])
        XCTAssertEqual(listing(d), ["a.txt", "b.txt", "taken.txt"])
        XCTAssertEqual(read(d, "a.txt"), "A")
        XCTAssertEqual(read(d, "taken.txt"), "T", "the other item was never replaced")
    }

    func testFailureInPhaseOneRollsBack() throws {
        let d = try tempDir()
        write(d, "a.txt", "A"); write(d, "b.txt", "B")
        func at(_ n: String) -> String { (d as NSString).appendingPathComponent(n) }
        var calls = 0
        let outcome = BatchRenameRules.execute([(from: at("a.txt"), to: at("c.txt")), (from: at("b.txt"), to: at("d.txt"))]) { from, to in
            calls += 1
            return calls == 2 ? EACCES : BatchRenameRules.renameExclusive(from, to)   // fail b.txt → temporary
        }
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.failedErrno, EACCES)
        XCTAssertEqual(listing(d), ["a.txt", "b.txt"])
    }

    func testRenameOne() throws {
        let d = try tempDir()
        write(d, "report.txt", "R"); write(d, "other.txt", "O")
        func at(_ n: String) -> String { (d as NSString).appendingPathComponent(n) }
        XCTAssertEqual(BatchRenameRules.renameOne(at("report.txt"), to: "Report.txt"), .renamed(at("Report.txt")))
        XCTAssertEqual(BatchRenameRules.renameOne(at("Report.txt"), to: "  Report.txt \n"), .unchanged)
        XCTAssertEqual(BatchRenameRules.renameOne(at("Report.txt"), to: "OTHER.txt"), .rejected(key: BatchRenameRules.Issue.existsInFolder.key))
        XCTAssertEqual(BatchRenameRules.renameOne(at("Report.txt"), to: "a:b"), .rejected(key: RenameRules.Problem.separator.key))
        XCTAssertEqual(BatchRenameRules.renameOne(at("missing.txt"), to: "x.txt"), .rejected(key: BatchRenameRules.Issue.missing.key))
        XCTAssertEqual(listing(d), ["Report.txt", "other.txt"])
        XCTAssertEqual(read(d, "other.txt"), "O")
    }

    func testDirectoryNamesSeesAppleDoubleFiles() throws {
        let d = try tempDir()
        write(d, "._a", "x"); write(d, "a", "y")
        XCTAssertEqual(listing(d), ["._a", "a"], "readdir, not FileManager (which hides ._* on macOS 27)")
        XCTAssertNil(BatchRenameRules.directoryNames(d + "/nope"))
    }
}
