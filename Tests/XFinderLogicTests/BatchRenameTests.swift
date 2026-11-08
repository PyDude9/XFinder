import XCTest

/// Batch-rename planning.
///
/// This is the highest-risk pure logic in the app: it proposes file moves. A
/// collision bug here does not draw a wrong pixel — it overwrites somebody's
/// file. The engine's own guard is `collides`, so these tests concentrate on
/// the cases where two rows can be driven onto the same name.
///
/// Mirrors `BatchRenameEngine.plan`. See GeometryTests for why logic is
/// duplicated rather than imported.
final class BatchRenameTests: XCTestCase {

    struct Options {
        var mode: Mode = .prefix
        var affix = ""
        var find = ""
        var replaceWith = ""
        var sequenceStart = 1
        var sequenceDigits = 2
        var sequenceSeparator = "_"
        var keepExtension = true
    }
    enum Mode { case prefix, suffix, replace, sequence, lowercase, uppercase }

    struct Plan: Equatable {
        var source: URL
        var proposed: URL
        var collides: Bool
    }

    /// `existsOnDisk` is injected so the test never touches the file system.
    private func plan(_ files: [URL],
                      _ options: Options,
                      existsOnDisk: (String) -> Bool = { _ in false }) -> [Plan] {
        var seen = Set<String>()
        var counter = options.sequenceStart
        return files.map { url in
            let ext = url.pathExtension
            var stem = url.deletingPathExtension().lastPathComponent
            switch options.mode {
            case .prefix:  stem = options.affix + stem
            case .suffix:  stem = stem + options.affix
            case .replace:
                if !options.find.isEmpty {
                    stem = stem.replacingOccurrences(of: options.find, with: options.replaceWith)
                }
            case .sequence:
                let num = String(format: "%0\(max(1, options.sequenceDigits))d", counter)
                stem = stem + options.sequenceSeparator + num
                counter += 1
            case .lowercase: stem = stem.lowercased()
            case .uppercase: stem = stem.uppercased()
            }
            let newName = (options.keepExtension && !ext.isEmpty) ? "\(stem).\(ext)" : stem
            let proposed = url.deletingLastPathComponent().appendingPathComponent(newName)
            // XF-T37: mirrors the engine's new rule — an invalid name blocks, and a target that exists on disk only
            // blocks when it is NOT this same item (case-only renames find themselves on a case-insensitive volume).
            let key = url.deletingLastPathComponent().path + "/" + RenameRules.nameKey(newName)
            let invalid = RenameRules.problem(for: newName) != nil
            let takenOnDisk = existsOnDisk(proposed.path) && !RenameRules.isSameName(newName, url.lastPathComponent)
            let collides = invalid || takenOnDisk || seen.contains(key)
            seen.insert(key)
            return Plan(source: url, proposed: proposed, collides: collides)
        }
    }

    private func urls(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/xf/\($0)") }
    }

    // MARK: Basic modes

    func testPrefixKeepsExtension() {
        let p = plan(urls(["report.pdf"]), Options(mode: .prefix, affix: "2026_"))
        XCTAssertEqual(p[0].proposed.lastPathComponent, "2026_report.pdf")
    }

    func testSuffixInsertsBeforeExtension() {
        let p = plan(urls(["report.pdf"]), Options(mode: .suffix, affix: "_final"))
        XCTAssertEqual(p[0].proposed.lastPathComponent, "report_final.pdf",
                       "The suffix must land on the stem, never after the extension")
    }

    func testSequencePadsAndIncrements() {
        let p = plan(urls(["a.png", "b.png", "c.png"]),
                     Options(mode: .sequence, sequenceStart: 8, sequenceDigits: 3))
        XCTAssertEqual(p.map(\.proposed.lastPathComponent),
                       ["a_008.png", "b_009.png", "c_010.png"])
    }

    func testFileWithNoExtensionIsUnharmed() {
        let p = plan(urls(["Makefile"]), Options(mode: .prefix, affix: "old_"))
        XCTAssertEqual(p[0].proposed.lastPathComponent, "old_Makefile")
    }

    /// A dotfile's leading dot is its name, not an extension separator.
    func testDotfileKeepsItsLeadingDot() {
        let p = plan(urls([".gitignore"]), Options(mode: .prefix, affix: "x"))
        XCTAssertTrue(p[0].proposed.lastPathComponent.contains("gitignore"),
                      "A dotfile must not lose its name")
    }

    // MARK: Collisions — the dangerous cases

    /// Lowercasing two names that differ only in case drives both to the same
    /// target. The second row MUST be flagged, or one file overwrites the other.
    func testCaseOnlyDifferenceIsFlaggedAsCollision() {
        let p = plan(urls(["Photo.JPG", "photo.jpg"]), Options(mode: .lowercase))
        XCTAssertFalse(p[0].collides)
        XCTAssertTrue(p[1].collides,
                      "Two files differing only by case collide once lowercased")
    }

    /// Replacing text can also converge two different names onto one.
    func testReplaceConvergenceIsFlagged() {
        let p = plan(urls(["draft-v1.txt", "draft-v2.txt"]),
                     Options(mode: .replace, find: "-v1", replaceWith: ""))
        // "draft-v1.txt" -> "draft.txt"; the second is unchanged, so no clash.
        XCTAssertFalse(p[0].collides)
        XCTAssertFalse(p[1].collides)

        let q = plan(urls(["a-x.txt", "b-x.txt"]),
                     Options(mode: .replace, find: "a-x", replaceWith: "b-x"))
        XCTAssertTrue(q[1].collides, "Renaming a-x to b-x collides with the real b-x")
    }

    /// An existing file on disk is a collision even when no other row claims it.
    func testExistingFileOnDiskIsACollision() {
        let p = plan(urls(["new.txt"]),
                     Options(mode: .prefix, affix: "old_"),
                     existsOnDisk: { $0.hasSuffix("old_new.txt") })
        XCTAssertTrue(p[0].collides)
    }

    /// A no-op rename must not be reported as colliding with itself.
    func testIdentityRenameIsNotACollision() {
        let p = plan(urls(["same.txt"]), Options(mode: .prefix, affix: ""))
        XCTAssertEqual(p[0].source, p[0].proposed)
        XCTAssertFalse(p[0].collides,
                       "Renaming a file to its own name is a no-op, not a clash")
    }

    // MARK: Edge cases

    func testEmptyInputProducesEmptyPlan() {
        XCTAssertTrue(plan([], Options()).isEmpty)
    }

    /// Zero digits must still render at least one digit, never an empty string.
    func testSequenceDigitsFloorsAtOne() {
        let p = plan(urls(["a.txt"]),
                     Options(mode: .sequence, sequenceStart: 5, sequenceDigits: 0))
        XCTAssertEqual(p[0].proposed.lastPathComponent, "a_5.txt")
    }

    /// The plan never moves a file to a different directory.
    func testRenameStaysInTheSameFolder() {
        let p = plan(urls(["deep.txt"]), Options(mode: .prefix, affix: "p_"))
        XCTAssertEqual(p[0].proposed.deletingLastPathComponent(),
                       p[0].source.deletingLastPathComponent())
    }

    // MARK: XF-T37 — case-only renames and invalid names

    /// The default volume ignores case: `fileExists("REPORT.TXT")` is true when only "report.txt" exists (measured
    /// 2026-11-08), so the uppercase mode used to mark every row as a collision and rename nothing.
    func testUppercaseModeIsNotBlockedByTheItemItself() {
        let onDisk: Set<String> = ["/tmp/xf/report.txt"]
        let p = plan(urls(["report.txt"]), Options(mode: .uppercase),
                     existsOnDisk: { path in onDisk.contains { $0.compare(path, options: .caseInsensitive) == .orderedSame } })
        XCTAssertEqual(p[0].proposed.lastPathComponent, "REPORT.txt")
        XCTAssertFalse(p[0].collides)
    }

    func testAnotherItemWithTheNameStillBlocks() {
        let onDisk: Set<String> = ["/tmp/xf/a.txt", "/tmp/xf/x_a.txt"]
        let p = plan(urls(["a.txt"]), Options(mode: .prefix, affix: "X_"),
                     existsOnDisk: { path in onDisk.contains { $0.compare(path, options: .caseInsensitive) == .orderedSame } })
        XCTAssertTrue(p[0].collides)
    }

    func testInvalidNameBlocks() {
        let p = plan(urls(["a.txt"]), Options(mode: .prefix, affix: "x/"))
        XCTAssertTrue(p[0].collides)
    }
}

