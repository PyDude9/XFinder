import XCTest
@testable import XFinderLogicTests

/// Pure-rule tests for XF-MFGAP-03 stage 03A. No files are created: every case is metadata, so a
/// failure here is a decision bug, not a filesystem accident. The hostile shapes mirror what the
/// system reader actually returned on 2026-11-07 (`ArchiveSafetyRules` header).
final class ArchiveSafetyRulesTests: XCTestCase {

    private func file(_ path: String, size: Int64 = 10) -> ArchiveManifestEntry {
        ArchiveManifestEntry(rawPath: path, declaredSize: size, sizeIsSet: true, kind: .regular, linkTarget: nil)
    }
    private func dir(_ path: String) -> ArchiveManifestEntry {
        ArchiveManifestEntry(rawPath: path, declaredSize: 0, sizeIsSet: true, kind: .directory, linkTarget: nil)
    }
    private func symlink(_ path: String, to target: String) -> ArchiveManifestEntry {
        ArchiveManifestEntry(rawPath: path, declaredSize: 0, sizeIsSet: true, kind: .symlink, linkTarget: target)
    }
    private func hardlink(_ path: String, to target: String) -> ArchiveManifestEntry {
        ArchiveManifestEntry(rawPath: path, declaredSize: 0, sizeIsSet: true, kind: .hardlink, linkTarget: target)
    }

    private func reasons(_ manifest: [ArchiveManifestEntry],
                         compressed: Int64? = nil,
                         available: Int64? = 1_000_000_000,
                         limits: ArchiveSafetyRules.Limits = .proposed) -> [ArchiveSafetyRules.Reason] {
        ArchiveSafetyRules.validate(manifest: manifest, compressedSize: compressed,
                                    availableBytes: available, limits: limits).reasons
    }

    // MARK: Happy path

    func testOrdinaryArchiveIsAcceptedAndPlansConservativePeak() {
        let manifest = [dir("docs"), file("docs/a.txt", size: 100), file("b.txt", size: 200)]
        let verdict = ArchiveSafetyRules.validate(manifest: manifest, compressedSize: 150,
                                                  availableBytes: 1_000_000_000)
        guard case .accepted(let plan) = verdict else { return XCTFail("expected acceptance, got \(verdict)") }
        XCTAssertEqual(plan.declaredPayloadBytes, 300)
        // payload + 3 entries of overhead + reserve
        let expected = 300 + 3 * ArchiveSafetyRules.Limits.proposed.perEntryOverheadBytes
            + ArchiveSafetyRules.Limits.proposed.capacityReserveBytes
        XCTAssertEqual(plan.peakBytes, expected)
        XCTAssertEqual(plan.orderedEntries.count, 3)
    }

    // MARK: Path containment — the measured ditto/tar normalisation must not be relied on

    func testDotDotIsRejectedRatherThanNormalised() {
        XCTAssertEqual(reasons([file("../escaped.txt")]), [.escapesRoot("../escaped.txt")])
    }

    func testAbsolutePathIsRejectedRatherThanStripped() {
        XCTAssertEqual(reasons([file("/tmp/absolute.txt")]), [.absolutePath("/tmp/absolute.txt")])
    }

    func testDotDotCancelledByLaterComponentIsStillRejected() {
        // "a/../b" would land safely at "b", but resolving it is decoder-dependent.
        XCTAssertEqual(reasons([file("a/../b.txt")]), [.escapesRoot("a/../b.txt")])
    }

    func testInteriorDotDotThatStaysInsideIsRejected() {
        let r = reasons([dir("a"), dir("a/b"), file("a/b/../c.txt")])
        XCTAssertTrue(r.contains(.escapesRoot("a/b/../c.txt")), "got \(r)")
    }

    func testDriveUNCAndSeparatorAmbiguity() {
        XCTAssertTrue(reasons([file("C:/x.txt")]).contains(.ambiguousSeparator("C:/x.txt")))
        XCTAssertTrue(reasons([file("//server/share/x.txt")]).contains(.driveOrUNCPath("//server/share/x.txt")))
        XCTAssertTrue(reasons([file("a\\b.txt")]).contains(.ambiguousSeparator("a\\b.txt")))
    }

    func testEmptyAndControlCharacterPaths() {
        XCTAssertEqual(reasons([file("")]), [.emptyPath])
        XCTAssertEqual(reasons([file("a\u{001B}b")]), [.controlCharacter("a\u{001B}b")])
        XCTAssertEqual(reasons([file("a\u{0}b")]), [.controlCharacter("a\u{0}b")])
    }

    func testTrailingAndRepeatedSeparatorsNormaliseAway() {
        XCTAssertTrue(reasons([file("a//b.txt")]).isEmpty, "\(reasons([file("a//b.txt")]))")
        XCTAssertTrue(reasons([file("a/./b.txt")]).isEmpty)
    }

    // MARK: Duplicate and alias detection — measured through libarchive

    func testDuplicateRawEntryNamesAreRejected() {
        // Measured: libarchive reports both entries; unzip kept only the last one's data.
        XCTAssertTrue(reasons([file("same.txt"), file("same.txt", size: 15)]).contains(.duplicatePath("same.txt")))
    }

    func testCaseAliasIsRejectedBecauseAPFSWouldCollapseIt() {
        let r = reasons([file("Report.txt"), file("report.txt")])
        XCTAssertTrue(r.contains(.aliasedPath("Report.txt", "report.txt")), "got \(r)")
    }

    func testUnicodeCompositionAliasIsRejected() {
        let nfc = "t\u{1EC7}p.txt"          // tệp.txt precomposed
        let nfd = "te\u{0302}\u{0323}p.txt" // same word, decomposed
        let r = reasons([file(nfc), file(nfd)])
        XCTAssertTrue(r.contains(.aliasedPath(nfc, nfd)), "got \(r)")
    }

    func testDiacriticsAreNotFolded() {
        // "tệp" and "tep" are genuinely different files on APFS; folding them would refuse valid archives.
        XCTAssertTrue(reasons([file("t\u{1EC7}p.txt"), file("tep.txt")]).isEmpty)
    }

    func testFileUsedAsParentIsRejected() {
        let r = reasons([file("docs"), file("docs/a.txt")])
        XCTAssertTrue(r.contains(.fileUsedAsParent("docs")), "got \(r)")
    }

    func testDirectoryThenChildIsAccepted() {
        XCTAssertTrue(reasons([dir("docs"), file("docs/a.txt")]).isEmpty)
    }

    // MARK: Limits

    func testEntryCountLimit() {
        var limits = ArchiveSafetyRules.Limits.proposed
        limits.maxEntries = 2
        let r = reasons([file("a"), file("b"), file("c")], limits: limits)
        XCTAssertEqual(r, [.tooManyEntries(count: 3, limit: 2)])
    }

    func testSingleFileCeiling() {
        var limits = ArchiveSafetyRules.Limits.proposed
        limits.maxBytesPerFile = 100
        XCTAssertTrue(reasons([file("a", size: 101)], limits: limits).contains(.fileTooLarge("a", declared: 101, limit: 100)))
        XCTAssertTrue(reasons([file("a", size: 100)], limits: limits).isEmpty)
    }

    func testCumulativeCeiling() {
        var limits = ArchiveSafetyRules.Limits.proposed
        limits.maxCumulativeBytes = 150
        let r = reasons([file("a", size: 100), file("b", size: 100)], limits: limits)
        XCTAssertTrue(r.contains(.payloadTooLarge(declared: 200, limit: 150)), "got \(r)")
    }

    func testUndeclaredSizeIsRejectedNotAssumedSmall() {
        let entry = ArchiveManifestEntry(rawPath: "stream.bin", declaredSize: 0, sizeIsSet: false,
                                         kind: .regular, linkTarget: nil)
        XCTAssertEqual(reasons([entry]), [.undeclaredSize("stream.bin")])
    }

    func testOverflowRefusesInsteadOfWrapping() {
        var limits = ArchiveSafetyRules.Limits.proposed
        limits.maxCumulativeBytes = Int64.max
        limits.maxBytesPerFile = Int64.max
        let r = reasons([file("a", size: Int64.max - 1), file("b", size: Int64.max - 1)], limits: limits)
        XCTAssertTrue(r.contains(.sizeOverflow), "got \(r)")
    }

    func testPathBounds() {
        var limits = ArchiveSafetyRules.Limits.proposed
        limits.maxPathComponents = 3
        XCTAssertTrue(reasons([file("a/b/c/d.txt")], limits: limits).contains(.tooManyComponents("a/b/c/d.txt", count: 4)))

        limits = .proposed
        limits.maxPathBytes = 8
        XCTAssertTrue(reasons([file("longname.txt")], limits: limits).contains(.pathTooLong("longname.txt", bytes: 12)))
    }

    // MARK: Expansion ratio — the measured benign fixture must not be refused

    func testBenignHighRatioFixtureIsAccepted() {
        // Measured: an 8,273-byte ZIP yielded 8,388,608 bytes (~1,014x) and is under the ratio floor.
        let r = reasons([file("zeros.bin", size: 8_388_608)], compressed: 8_273)
        XCTAssertTrue(r.isEmpty, "a small high-ratio archive must not be refused: \(r)")
    }

    func testAboveFloorHighRatioIsRejected() {
        var limits = ArchiveSafetyRules.Limits.proposed
        limits.expansionRatioFloorBytes = 1_000
        limits.maxExpansionRatio = 100
        let r = reasons([file("bomb.bin", size: 1_000_000)], compressed: 1_000, limits: limits)
        XCTAssertTrue(r.contains { if case .expansionRatioTooHigh = $0 { return true }; return false }, "got \(r)")
    }

    // MARK: Links — the measured absolute symlink and the escape it feeds

    func testAbsoluteSymlinkIsRejected() {
        XCTAssertEqual(reasons([symlink("jump", to: "/tmp")]), [.absoluteLink("jump", target: "/tmp")])
    }

    func testTildeSymlinkIsRejected() {
        XCTAssertEqual(reasons([symlink("home", to: "~/Documents")]), [.absoluteLink("home", target: "~/Documents")])
    }

    func testEscapingRelativeSymlinkIsRejected() {
        XCTAssertEqual(reasons([symlink("up", to: "../../outside")]), [.escapingLink("up", target: "../../outside")])
    }

    func testContainedRelativeSymlinkIsAcceptedAndPlacedLast() {
        let manifest = [file("target.txt"), dir("sub"), symlink("sub/link", to: "../target.txt")]
        guard case .accepted(let plan) = ArchiveSafetyRules.validate(manifest: manifest, availableBytes: 1_000_000_000) else {
            return XCTFail("expected acceptance: \(reasons(manifest))")
        }
        XCTAssertEqual(plan.orderedEntries.last?.rawPath, "sub/link", "links must be created last")
    }

    func testSymlinkCycleIsRejected() {
        let r = reasons([symlink("a", to: "b"), symlink("b", to: "a")])
        XCTAssertTrue(r.contains { if case .linkCycle = $0 { return true }; return false }, "got \(r)")
    }

    func testSelfReferencingSymlinkIsRejected() {
        let r = reasons([symlink("loop", to: "loop")])
        XCTAssertTrue(r.contains { if case .linkCycle = $0 { return true }; return false }, "got \(r)")
    }

    func testHardLinkOnlyToAnEntryInsideTheArchive() {
        XCTAssertTrue(reasons([file("a.txt"), hardlink("b.txt", to: "a.txt")]).isEmpty)
        let outside = reasons([hardlink("b.txt", to: "/etc/passwd")])
        XCTAssertTrue(outside.contains(.hardLinkOutside("b.txt", target: "/etc/passwd")), "got \(outside)")
        let missing = reasons([hardlink("b.txt", to: "nowhere.txt")])
        XCTAssertTrue(missing.contains(.hardLinkOutside("b.txt", target: "nowhere.txt")), "got \(missing)")
    }

    func testSymlinkWithNoTargetIsRejected() {
        let entry = ArchiveManifestEntry(rawPath: "x", declaredSize: 0, sizeIsSet: true, kind: .symlink, linkTarget: nil)
        XCTAssertEqual(reasons([entry]), [.linkTargetMissing("x", target: "")])
    }

    func testSymlinkChainTooDeepIsRejected() {
        var limits = ArchiveSafetyRules.Limits.proposed
        limits.maxLinkChainDepth = 3
        // l0 -> l1 -> l2 -> l3 -> l4 ... a chain, not a cycle
        var manifest: [ArchiveManifestEntry] = [file("target.txt")]
        for i in 0..<8 { manifest.append(symlink("l\(i)", to: i == 7 ? "target.txt" : "l\(i + 1)")) }
        let r = reasons(manifest, limits: limits)
        XCTAssertTrue(r.contains { if case .linkCycle = $0 { return true }; return false }, "a too-deep chain must be refused: \(r)")
    }

    // MARK: Unsupported entry kinds

    func testSpecialFilesAreRejected() {
        let fifo = ArchiveManifestEntry(rawPath: "pipe", declaredSize: 0, sizeIsSet: true, kind: .unsupported, linkTarget: nil)
        XCTAssertEqual(reasons([fifo]), [.unsupportedEntry("pipe")])
    }

    // MARK: Space

    func testUnknownCapacityIsRefusedRatherThanTreatedAsInfinite() {
        let v = ArchiveSafetyRules.validate(manifest: [file("a", size: 10)], availableBytes: nil)
        XCTAssertEqual(v.reasons, [.spaceUnknown])
    }

    func testInsufficientSpaceReportsRequiredAndAvailable() {
        let v = ArchiveSafetyRules.validate(manifest: [file("a", size: 10_000)], availableBytes: 1_000)
        XCTAssertTrue(v.reasons.contains { if case .insufficientSpace = $0 { return true }; return false }, "got \(v.reasons)")
    }

    func testExactlyEnoughSpaceIsAccepted() {
        let peak = 10 + ArchiveSafetyRules.Limits.proposed.perEntryOverheadBytes
            + ArchiveSafetyRules.Limits.proposed.capacityReserveBytes
        let v = ArchiveSafetyRules.validate(manifest: [file("a", size: 10)], availableBytes: peak)
        XCTAssertTrue(v.isAccepted, "boundary must be deterministic: \(v.reasons)")
    }

    func testOneByteShortIsRejected() {
        let peak = 10 + ArchiveSafetyRules.Limits.proposed.perEntryOverheadBytes
            + ArchiveSafetyRules.Limits.proposed.capacityReserveBytes
        let v = ArchiveSafetyRules.validate(manifest: [file("a", size: 10)], availableBytes: peak - 1)
        XCTAssertFalse(v.isAccepted)
    }

    // MARK: Whole-archive rejection

    func testOneBadEntryRejectsTheWholeArchive() {
        let manifest = [file("fine1.txt"), file("fine2.txt"), symlink("bad", to: "/etc")]
        let verdict = ArchiveSafetyRules.validate(manifest: manifest, availableBytes: 1_000_000_000)
        XCTAssertFalse(verdict.isAccepted, "a single hostile entry must refuse the batch")
        XCTAssertEqual(verdict.reasons, [.absoluteLink("bad", target: "/etc")])
    }

    func testReasonsAreDeduplicated() {
        let r = reasons([file("../a"), file("../a")])
        XCTAssertEqual(r.filter { $0 == .escapesRoot("../a") }.count, 1, "duplicate reasons must collapse: \(r)")
    }

    func testEmptyManifestIsRejected() {
        XCTAssertEqual(ArchiveSafetyRules.validate(manifest: [], availableBytes: 1_000).reasons, [.emptyPath])
    }
}
