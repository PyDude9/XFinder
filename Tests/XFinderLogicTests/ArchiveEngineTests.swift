import XCTest
import Foundation

final class ArchiveEngineTests: XCTestCase {
    typealias E = ArchiveEngine
    let dir = URL(fileURLWithPath: "/tmp/x")

    func testNumberingKeepsTheExtensionIncludingCompoundOnes() {
        XCTAssertEqual(E.numbered("Report.pdf", 2), "Report 2.pdf")
        XCTAssertEqual(E.numbered("Folder", 3), "Folder 3")
        XCTAssertEqual(E.numbered("a.tar.gz", 2), "a 2.tar.gz")
        XCTAssertEqual(E.numbered(".hidden", 2), ".hidden 2", "a dot-file has no extension to keep")
    }

    func testEntryNamesKeepEveryFileWhenNamesCollide() {
        let names = E.entryNames(for: [URL(fileURLWithPath: "/a/Report.pdf"), URL(fileURLWithPath: "/b/Report.pdf"),
                                       URL(fileURLWithPath: "/c/report.pdf"), URL(fileURLWithPath: "/d/Notes")])
        XCTAssertEqual(names, ["Report.pdf", "Report 2.pdf", "report 3.pdf", "Notes"],
                       "same name from different folders must both survive (case-insensitive, like APFS)")
    }

    func testArchiveNameIsNeverEmptyAndHasNoPathSeparators() {
        XCTAssertEqual(E.archiveName("   "), "Archive")
        XCTAssertEqual(E.archiveName(" Q3/Q4: report "), "Q3-Q4- report")
    }

    // MARK: Conflict policy

    func testKeepBothNumbersUntilFree() {
        let taken: Set<String> = ["/tmp/x/A.zip", "/tmp/x/A 2.zip"]
        XCTAssertEqual(E.destination(base: dir.appendingPathComponent("A.zip"), policy: .keepBoth, exists: { taken.contains($0.path) }),
                       .write(dir.appendingPathComponent("A 3.zip")))
    }

    /// The old `.ask` branch called itself with the same arguments — infinite recursion. Now it
    /// returns a decision request and touches nothing.
    func testAskNeverDecidesForTheUser() {
        let base = dir.appendingPathComponent("A.zip")
        XCTAssertEqual(E.destination(base: base, policy: .ask, exists: { _ in true }), .needsDecision(existing: base))
        XCTAssertEqual(E.destination(base: base, policy: .ask, exists: { _ in false }), .write(base))
    }

    func testMergeWritesIntoTheExistingItem() {
        let base = dir.appendingPathComponent("Photos")
        XCTAssertEqual(E.destination(base: base, policy: .merge, exists: { _ in true }), .write(base))
    }

    func testPlacementsNeverHandTheSameNameToTwoItems() {
        // Destination already has "a"; the archive holds "a" and "a 2".
        let p = E.placements(items: ["a", "a 2"], into: dir, policy: .keepBoth, exists: { $0.lastPathComponent == "a" })
        let targets = p.compactMap { if case .write(let u) = $0.destination { return u.lastPathComponent } else { return nil } }
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(Set(targets).count, 2, "two items placed onto one name: \(targets)")
        XCTAssertFalse(targets.contains("a"), "the existing 'a' must not be overwritten")
    }

    // MARK: Commands

    func testOneSourceDefaultZipUsesDittoAndKeepsTheParent() {
        let c = E.compressCommand(sources: [URL(fileURLWithPath: "/a/Folder")], format: .zip, level: 6, password: nil,
                                  output: URL(fileURLWithPath: "/a/Folder.zip"), stagingDir: nil, single: .directory)
        XCTAssertEqual(c.executable, "/usr/bin/ditto")
        XCTAssertEqual(c.arguments, ["-c", "-k", "--sequesterRsrc", "--keepParent", "/a/Folder", "/a/Folder.zip"])
    }

    /// Measured 2026-11-08: `--keepParent` on a single FILE stores `parent/one.txt`; without it, `one.txt`.
    func testOneFileDefaultZipUsesDittoWithoutTheParent() {
        let c = E.compressCommand(sources: [URL(fileURLWithPath: "/a/one.txt")], format: .zip, level: 6, password: nil,
                                  output: URL(fileURLWithPath: "/a/one.zip"), stagingDir: nil, single: .file)
        XCTAssertEqual(c.executable, "/usr/bin/ditto")
        XCTAssertEqual(c.arguments, ["-c", "-k", "--sequesterRsrc", "/a/one.txt", "/a/one.zip"])
    }

    /// Measured: `ditto` follows a symlinked source and names the entry after the TARGET; staging names it after
    /// the link, like every multi-source entry.
    func testALinkedSingleSourceIsStagedNotHandedToDitto() {
        XCTAssertTrue(E.needsStaging(sourceCount: 1, format: .zip, level: 6, hasPassword: false, single: .link))
        XCTAssertFalse(E.needsStaging(sourceCount: 1, format: .zip, level: 6, hasPassword: false, single: .file))
        XCTAssertFalse(E.needsStaging(sourceCount: 1, format: .zip, level: 6, hasPassword: false, single: .directory))
    }

    /// Measured: ditto refuses more than one source. Two or more items must never reach it.
    func testTwoSourcesNeverGoToDitto() {
        XCTAssertTrue(E.needsStaging(sourceCount: 2, format: .zip, level: 6, hasPassword: false, single: .file))
        let c = E.compressCommand(sources: [URL(fileURLWithPath: "/a/x"), URL(fileURLWithPath: "/b/x")], format: .zip,
                                  level: 6, password: nil, output: URL(fileURLWithPath: "/o.zip"),
                                  stagingDir: URL(fileURLWithPath: "/stage"), single: .file)
        XCTAssertEqual(c.executable, "/usr/bin/zip")
        XCTAssertEqual(c.currentDirectory?.path, "/stage", "zip must run from the staging folder, not the first source's folder")
        XCTAssertEqual(Array(c.arguments.suffix(2)), ["x", "x 2"])
    }

    func testThePasswordNeverAppearsInTheArguments() {
        let pw = "S3cret pass"
        let c = E.compressCommand(sources: [URL(fileURLWithPath: "/a/x")], format: .zip, level: 6, password: pw,
                                  output: URL(fileURLWithPath: "/o.zip"), stagingDir: URL(fileURLWithPath: "/stage"), single: .file)
        XCTAssertFalse(c.arguments.joined(separator: " ").contains("S3cret"), "argv is world-readable via ps")
        XCTAssertFalse(c.arguments.contains("-P"))
        XCTAssertEqual(c.environment["ZIPOPT"], "-P \"S3cret pass\"")
    }

    func testZipOptQuotingEscapesQuotesAndBackslashes() {
        XCTAssertEqual(E.zipOptPassword(#"a"b\c"#), #"-P "a\"b\\c""#)
    }

    func testTarFollowsTheStagingLinks() {
        let c = E.compressCommand(sources: [URL(fileURLWithPath: "/a/x")], format: .tarGz, level: 6, password: nil,
                                  output: URL(fileURLWithPath: "/o.tar.gz"), stagingDir: URL(fileURLWithPath: "/stage"), single: .file)
        XCTAssertEqual(c.arguments.first, "-czhf", "without -h tar would store the symlinks, not the files")
    }

    func testExtractRoutesOnlyZipToDitto() {
        XCTAssertEqual(E.extractCommand(archive: URL(fileURLWithPath: "/a/b.ZIP"), into: dir).executable, "/usr/bin/ditto")
        for name in ["b.tar.gz", "b.tgz", "b.tar", "b.tar.bz2"] {
            let c = E.extractCommand(archive: URL(fileURLWithPath: "/a/\(name)"), into: dir)
            XCTAssertEqual(c.executable, "/usr/bin/tar", name)
            XCTAssertEqual(c.arguments.first, "-xf", "bsdtar detects the compression itself (\(name))")
        }
    }

    func testFolderNameStripsArchiveExtensions() {
        XCTAssertEqual(E.folderName(forArchive: URL(fileURLWithPath: "/a/Photos.zip")), "Photos")
        XCTAssertEqual(E.folderName(forArchive: URL(fileURLWithPath: "/a/src.tar.gz")), "src")
        XCTAssertEqual(E.folderName(forArchive: URL(fileURLWithPath: "/a/v1.2.tgz")), "v1.2")
    }

    func testZipsSilentSkipIsRecognisedAsMissingData() {
        XCTAssertTrue(E.stderrSignalsMissingData("\tzip warning: name not matched: two.txt\n"))
        XCTAssertFalse(E.stderrSignalsMissingData(""))
    }
}

extension ArchiveEngineTests {
    func testListingCheckFindsADroppedEntryAndAcceptsFolders() {
        let listing = "one.txt\nfolder/\nfolder/deep.txt\n"
        XCTAssertEqual(E.missingTopLevelEntries(expected: ["one.txt", "folder", "two.txt"], listing: listing), ["two.txt"])
        XCTAssertEqual(E.missingTopLevelEntries(expected: ["One.TXT"], listing: listing), [], "APFS names are case-insensitive")
    }
}

extension ArchiveEngineTests {
    /// Every failure sentence the runner can produce reaches the English UI translated.
    func testEveryFailureMessageKeyIsInTheStore() throws {
        let store = try L10nFixture.load()
        XCTAssertEqual(ArchiveRunner.Failure.examples.count, 13, "a case was added without an example")
        for f in ArchiveRunner.Failure.examples {
            let entry = store.entries[f.messageKey]
            XCTAssertNotNil(entry, "\(f.messageKey) is not in L10n.strings.json")
            XCTAssertNotEqual(entry?.en ?? f.messageKey, f.messageKey)
        }
    }
}

extension ArchiveEngineTests {
    func testLinksThatLeaveTheArchiveAreFlagged() {
        let links: [(path: String, target: String)] = [
            ("Project/config/settings.json", "/Users/me/secret.json"),   // absolute
            ("Project/up", "../../outside"),                             // climbs above the root
            ("Project/a/sibling", "../b/file"),                          // stays inside
            ("Project/self", "./x"),                                     // stays inside
            ("top", ".."),                                               // root's parent
            ("Project/home", "~/x"),
        ]
        XCTAssertEqual(E.escapingLinks(links), ["Project/config/settings.json", "Project/up", "top", "Project/home"])
    }
}
