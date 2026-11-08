import XCTest

/// The old Batch Rename page (Q-T37-5). Until XF-T37 this file tested a COPY of the page's planning logic — which is how
/// the case-only bug (every UPPERCASE row marked "collides" on a case-insensitive volume) shipped green. The page now
/// builds names with `BatchRenameRules.pageName` and checks them with the shared `validate`, so these tests call the real
/// code: the page's own modes, Format, and the shared rules on the page's plans.
final class BatchRenameTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func item(_ name: String, folder: Bool = false) -> BatchRenameRules.Item {
        BatchRenameRules.Item(path: "/tmp/xf/\(name)", isFolder: folder, modified: Date(timeIntervalSince1970: 1_793_000_000))
    }

    private func names(_ items: [BatchRenameRules.Item], _ options: BatchRenameRules.PageOptions) -> [String] {
        items.indices.map { BatchRenameRules.pageName(for: items[$0], index: $0, options: options, calendar: calendar, dateConnector: " at ") }
    }

    private func plan(_ items: [BatchRenameRules.Item], _ options: BatchRenameRules.PageOptions,
                      siblings: Set<String> = []) -> BatchRenameRules.Plan {
        BatchRenameRules.pagePlan(items: items, options: options, siblings: { _ in siblings }, calendar: calendar, dateConnector: " at ")
    }

    // MARK: The page's own modes

    func testPrefixAndSuffixKeepTheExtension() {
        var o = BatchRenameRules.PageOptions(); o.mode = .prefix; o.affix = "2026_"
        XCTAssertEqual(names([item("report.pdf")], o), ["2026_report.pdf"])
        o.mode = .suffix; o.affix = "_final"
        XCTAssertEqual(names([item("report.pdf")], o), ["report_final.pdf"])
    }

    func testReplaceOnlyTouchesTheStem() {
        var o = BatchRenameRules.PageOptions(); o.mode = .replace; o.find = "pdf"; o.replaceWith = "doc"
        XCTAssertEqual(names([item("pdf notes.pdf")], o), ["doc notes.pdf"])
    }

    func testSequencePadsAndCounts() {
        var o = BatchRenameRules.PageOptions(); o.mode = .sequence; o.sequenceStart = 8; o.sequenceDigits = 3; o.sequenceSeparator = "-"
        XCTAssertEqual(names([item("a.jpg"), item("b.jpg"), item("c.jpg")], o), ["a-008.jpg", "b-009.jpg", "c-010.jpg"])
    }

    func testCaseModesAndDroppingTheExtension() {
        var o = BatchRenameRules.PageOptions(); o.mode = .uppercase
        XCTAssertEqual(names([item("report.txt")], o), ["REPORT.txt"])
        o.mode = .lowercase; o.keepExtension = false
        XCTAssertEqual(names([item("Report.TXT")], o), ["report"])
    }

    func testFormatModeUsesFindersStyles() {
        var o = BatchRenameRules.PageOptions(); o.mode = .format
        o.format.customName = "Trip "; o.format.formatStyle = .nameAndCounter; o.format.startNumber = 1
        XCTAssertEqual(names([item("a.jpg"), item("b.jpg")], o), ["Trip 00001.jpg", "Trip 00002.jpg"])
    }

    // MARK: The shared rules on the page's plans (the bug this file used to miss)

    /// The default volume ignores case: "report.txt" → "REPORT.txt" finds the item itself — a legal rename.
    func testUppercaseIsNotBlockedByTheItemItself() {
        var o = BatchRenameRules.PageOptions(); o.mode = .uppercase
        let p = plan([item("report.txt")], o, siblings: ["report.txt"])
        XCTAssertEqual(p.rows[0].newName, "REPORT.txt")
        XCTAssertEqual(p.rows[0].issues, [])
        XCTAssertEqual(p.rows[0].notes, [.caseOnly])
        XCTAssertTrue(p.canRename)
    }

    func testAnotherItemWithTheNameBlocksTheBatch() {
        var o = BatchRenameRules.PageOptions(); o.mode = .prefix; o.affix = "X_"
        let p = plan([item("a.txt"), item("b.txt")], o, siblings: ["a.txt", "b.txt", "x_a.txt"])
        XCTAssertEqual(p.rows[0].issues, [.existsInFolder])
        XCTAssertEqual(p.rows[1].issues, [])
        XCTAssertFalse(p.canRename, "one error blocks the whole batch, as in the file browser")
    }

    func testInvalidNameBlocks() {
        var o = BatchRenameRules.PageOptions(); o.mode = .prefix; o.affix = "x/"
        XCTAssertEqual(plan([item("a.txt")], o).rows[0].issues, [.name(.separator)])
    }

    func testTwoRowsOntoOneName() {
        var o = BatchRenameRules.PageOptions(); o.mode = .prefix; o.affix = "x"
        let p = plan([item("1.txt"), item("1.TXT")], o, siblings: [])
        XCTAssertEqual(p.rows.map(\.newName), ["x1.txt", "x1.TXT"])
        XCTAssertEqual(p.rows.map(\.issues), [[.duplicateInBatch], [.duplicateInBatch]], "same name on a case-insensitive volume")
    }
}
