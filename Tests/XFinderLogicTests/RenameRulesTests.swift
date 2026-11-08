import XCTest

/// XF-T37 L1 — the one name rule. The length cases are the measured APFS boundary (2026-11-08): 255 UTF-16 units of
/// the NFD name, so "a×253+ả" is legal (256 UTF-8 bytes) and "a×254+ả" is not (255 characters).
final class RenameRulesTests: XCTestCase {

    func testProblemTable() {
        let cases: [(String, RenameRules.Problem?)] = [
            ("Report.pdf", nil),
            ("File ", nil),                       // Finder's own default custom format ends with a space
            ("...", nil),
            ("", .empty),
            ("   ", .empty),
            ("\n", .empty),
            ("a/b", .separator),
            ("a:b", .separator),
            (".", .reserved),
            ("..", .reserved),
            (".xfinder-rename-1", .reserved),
            ("a\u{07}b", .control),
            ("a\nb", .control),
            ("a\u{7F}", .control),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(RenameRules.problem(for: name), expected, "name \(name.debugDescription)")
        }
    }

    func testLengthIsCountedInDecomposedUTF16Units() {
        XCTAssertNil(RenameRules.problem(for: String(repeating: "a", count: 255)))
        XCTAssertEqual(RenameRules.problem(for: String(repeating: "a", count: 256)), .tooLong)
        XCTAssertNil(RenameRules.problem(for: String(repeating: "a", count: 253) + "ả"), "256 UTF-8 bytes, 255 NFD units — APFS accepts it")
        XCTAssertEqual(RenameRules.problem(for: String(repeating: "a", count: 254) + "ả"), .tooLong, "255 characters, 256 NFD units")
        XCTAssertNil(RenameRules.problem(for: String(repeating: "ệ", count: 85)))
        XCTAssertEqual(RenameRules.problem(for: String(repeating: "ệ", count: 86)), .tooLong)
        XCTAssertNil(RenameRules.problem(for: String(repeating: "😀", count: 127)))
        XCTAssertEqual(RenameRules.problem(for: String(repeating: "😀", count: 128)), .tooLong)
    }

    func testSameNameIgnoresCaseAndUnicodeForm() {
        XCTAssertTrue(RenameRules.isSameName("report.txt", "REPORT.txt"))
        XCTAssertTrue(RenameRules.isSameName("Ảnh.png", "ảnh.png"))
        XCTAssertTrue(RenameRules.isSameName("\u{1EA3}", "a\u{0309}"), "NFC ả and NFD a+hook are one name")
        XCTAssertFalse(RenameRules.isSameName("report.txt", "report.txt "))
        XCTAssertFalse(RenameRules.isSameName("a.txt", "b.txt"))
    }

    func testSplitExtension() {
        XCTAssertTrue(RenameRules.splitExtension("a.tar.gz", isFolder: false) == ("a.tar", "gz"))
        XCTAssertTrue(RenameRules.splitExtension(".zshrc", isFolder: false) == (".zshrc", ""))
        XCTAssertTrue(RenameRules.splitExtension("Report.", isFolder: false) == ("Report.", ""))
        XCTAssertTrue(RenameRules.splitExtension("Photos.v2", isFolder: true) == ("Photos.v2", ""))
    }

    func testNotes() {
        XCTAssertEqual(RenameRules.notes(old: "a.txt", new: "a.txt", isFolder: false), [])
        XCTAssertEqual(RenameRules.notes(old: "report.txt", new: "Report.txt", isFolder: false), [.caseOnly])
        XCTAssertEqual(RenameRules.notes(old: "a.txt", new: ".a.txt", isFolder: false), [.hidden])
        XCTAssertEqual(RenameRules.notes(old: "a.pdf", new: "a.txt", isFolder: false), [.extensionChanged(from: "pdf", to: "txt")])
        XCTAssertEqual(RenameRules.notes(old: "a.pdf", new: "a", isFolder: false), [.extensionRemoved("pdf")])
        XCTAssertEqual(RenameRules.notes(old: "a", new: "a.md", isFolder: false), [.extensionAdded("md")])
        XCTAssertEqual(RenameRules.notes(old: "a.JPG", new: "a.jpg", isFolder: false), [.caseOnly], "an extension's case is not a new extension")
        XCTAssertEqual(RenameRules.notes(old: "Photos", new: "Photos.old", isFolder: true), [], "a folder has no extension")
    }

    /// Get Info's rename field goes through the same rule (it used to reject only "", ":" and "/").
    func testGetInfoUsesTheSameRule() {
        XCTAssertEqual(FileInfoRules.renameRejectionKey(for: ".."), RenameRules.Problem.reserved.key)
        XCTAssertEqual(FileInfoRules.renameRejectionKey(for: String(repeating: "ệ", count: 86)), RenameRules.Problem.tooLong.key)
        XCTAssertEqual(FileInfoRules.renameRejectionKey(for: "  Report.txt  "), nil, "typed spaces around a name are trimmed")
    }
}

