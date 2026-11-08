import XCTest
import Foundation

/// Integration tests: the real `ditto`, `zip`, `tar` and `unzip` on this Mac, in a temporary folder.
/// Each test reproduces a failure the old code shipped with.
final class ArchiveRunnerTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("xf-archive-\(UUID().uuidString)")
        for d in ["a", "b", "out", "dest"] { try fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true) }
        try "one".write(to: root.appendingPathComponent("a/one.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: root.appendingPathComponent("b/two.txt"), atomically: true, encoding: .utf8)
        try "A".write(to: root.appendingPathComponent("a/same.txt"), atomically: true, encoding: .utf8)
        try "B".write(to: root.appendingPathComponent("b/same.txt"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: root.appendingPathComponent("a/folder"), withIntermediateDirectories: true)
        try "deep".write(to: root.appendingPathComponent("a/folder/deep.txt"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    func url(_ p: String) -> URL { root.appendingPathComponent(p) }

    func sh(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try? p.run(); let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: d, as: UTF8.self))
    }
    func zipEntries(_ u: URL) -> [String] { sh("/usr/bin/unzip", ["-Z1", u.path]).1.split(separator: "\n").map(String.init).sorted() }

    /// The most common compression there is — ONE file, ZIP, default level, no password — failed on every entry
    /// point since `0a184ba` (measured 2026-11-08 by OpenCode and Boss independently): `ditto --keepParent` on a
    /// single FILE stores it under its parent folder's name (`a/one.txt`), the read-back looked for `one.txt`,
    /// and `compress` reported `.missingData` and deleted a ZIP it had just written. Every other compress test
    /// uses two sources, which is why nothing caught it.
    func testOneFileZipsWithTheFileAtTheTopLevel() async throws {
        let out = url("out/one.zip")
        let r = await ArchiveRunner.compress(sources: [url("a/one.txt")], format: .zip, output: out)
        XCTAssertEqual(r, .success(out), "one file, default ZIP must succeed")
        let entries = zipEntries(out).filter { !$0.hasPrefix("__MACOSX") }
        XCTAssertEqual(entries, ["one.txt"], "the file must be at the top level, not inside its parent folder's name")
    }

    /// A single symlinked source: `ditto` would follow it and name the entry after the TARGET (measured), so the read
    /// back missed the link's name the same way. It is staged like a multi-source entry and keeps its own name.
    func testOneLinkedFileZipsUnderTheLinksOwnName() async throws {
        let link = url("a/link.txt")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "one.txt")
        let out = url("out/link.zip")
        let r = await ArchiveRunner.compress(sources: [link], format: .zip, output: out)
        XCTAssertEqual(r, .success(out))
        XCTAssertEqual(zipEntries(out).filter { !$0.hasPrefix("__MACOSX") }, ["link.txt"])
    }

    /// Control for the fix above: ONE folder keeps `--keepParent`, so the folder itself is the top-level entry.
    func testOneFolderZipsAsItsOwnTopLevelFolder() async throws {
        let out = url("out/folder.zip")
        let r = await ArchiveRunner.compress(sources: [url("a/folder")], format: .zip, output: out)
        XCTAssertEqual(r, .success(out))
        let entries = zipEntries(out).filter { !$0.hasPrefix("__MACOSX") }
        XCTAssertEqual(entries, ["folder/", "folder/deep.txt"])
    }

    /// The default path of all three call sites used to be `ditto` with N sources — exit 1 for N ≥ 2.
    func testTwoFilesFromTwoFoldersZipWithBothInside() async throws {
        let out = url("out/two.zip")
        let r = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: out)
        XCTAssertEqual(r, .success(out))
        XCTAssertEqual(zipEntries(out), ["one.txt", "two.txt"])
    }

    func testSameNameFromTwoFoldersKeepsBothFiles() async throws {
        let out = url("out/same.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/same.txt"), url("b/same.txt")], format: .zip, output: out)
        XCTAssertEqual(zipEntries(out), ["same 2.txt", "same.txt"])
        XCTAssertEqual(sh("/usr/bin/unzip", ["-p", out.path, "same 2.txt"]).1, "B", "the second file's content, not a copy of the first")
    }

    func testAFolderSourceIsArchivedRecursively() async throws {
        let out = url("out/mix.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/folder"), url("b/two.txt")], format: .zip, output: out)
        XCTAssertTrue(zipEntries(out).contains("folder/deep.txt"), "\(zipEntries(out))")
    }

    func testOneFolderDefaultZipStillUsesDittoAndWorks() async throws {
        let out = url("out/folder.zip")
        let r = await ArchiveRunner.compress(sources: [url("a/folder")], format: .zip, output: out)
        XCTAssertEqual(r, .success(out))
        XCTAssertTrue(zipEntries(out).contains("folder/deep.txt"))
    }

    func testPasswordZipIsEncryptedWithThatPassword() async throws {
        let out = url("out/enc.zip")
        for pw in ["two words", #"quo"te"#, #"back\slash"#, "mật khẩu"] {
            try? fm.removeItem(at: out)
            _ = await ArchiveRunner.compress(sources: [url("a/one.txt")], format: .zip, password: pw, output: out)
            XCTAssertEqual(sh("/usr/bin/unzip", ["-P", pw, "-tq", out.path]).0, 0, "right password must open it: [\(pw)]")
            XCTAssertNotEqual(sh("/usr/bin/unzip", ["-P", "wrong", "-tq", out.path]).0, 0, "a wrong password must not: [\(pw)]")
        }
    }

    func testTarGzFromTwoFoldersHoldsBothRealFiles() async throws {
        let out = url("out/two.tar.gz")
        let r = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .tarGz, output: out)
        XCTAssertEqual(r, .success(out))
        let list = sh("/usr/bin/tar", ["-tvzf", out.path]).1
        XCTAssertTrue(list.contains("one.txt") && list.contains("two.txt"), list)
        XCTAssertFalse(list.hasPrefix("l"), "stored as symlinks instead of files:\n\(list)")
        XCTAssertEqual(sh("/usr/bin/tar", ["-xOzf", out.path, "two.txt"]).1, "two")
    }

    /// zip and tar both exit 0 and print nothing for a missing (staged) source — measured. TAR has no
    /// read-back check, so this case is guarded by the up-front existence check alone.
    func testAMissingSourceFailsInsteadOfProducingAPartialArchive() async throws {
        for (name, format) in [("missing.zip", ArchiveEngine.Format.zip), ("missing.tar.gz", .tarGz)] {
            let out = url("out/\(name)")
            let r = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/gone.txt")], format: format, output: out)
            XCTAssertEqual(r, .failure(.missingSource(["gone.txt"])), name)
            XCTAssertFalse(fm.fileExists(atPath: out.path), "a partial archive was left behind: \(name)")
        }
    }

    /// The read-back check on its own: a source that disappears AFTER the up-front check (simulated by
    /// a zip built from a staging link that dangles) must still fail. Uses the engine directly.
    func testZipReadBackCatchesAnEntryTheToolSilentlyDropped() async throws {
        let listing = "one.txt\n"
        XCTAssertEqual(ArchiveEngine.missingTopLevelEntries(expected: ["one.txt", "two.txt"], listing: listing), ["two.txt"])
    }

    func testExtractionNeverOverwritesUnderKeepBoth() async throws {
        let archive = url("out/x.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        try "MINE".write(to: url("dest/one.txt"), atomically: true, encoding: .utf8)
        guard case .success(let batch) = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest")) else { return XCTFail() }
        XCTAssertEqual(ArchiveRunner.conflicts(batch, in: url("dest")), ["one.txt"])
        _ = await ArchiveRunner.place(batch, into: url("dest"), policy: .keepBoth)
        XCTAssertEqual(try String(contentsOf: url("dest/one.txt"), encoding: .utf8), "MINE", "the user's file was overwritten")
        XCTAssertEqual(try String(contentsOf: url("dest/one 2.txt"), encoding: .utf8), "one")
        XCTAssertTrue(fm.fileExists(atPath: url("dest/two.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: batch.staging.path), "staging folder leaked")
    }

    /// Merge no longer replaces (Boss decision 1). Same-named files both survive, numbered, so the
    /// user's file is intact and the archive's copy is reachable next to it.
    func testMergeKeepsBothLeafFilesInsteadOfReplacingThem() async throws {
        let archive = url("out/m.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        try "MINE".write(to: url("dest/one.txt"), atomically: true, encoding: .utf8)
        guard case .success(let batch) = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest")) else { return XCTFail() }
        guard case .success(let outcome) = await ArchiveRunner.place(batch, into: url("dest"), policy: .merge) else {
            return XCTFail("merge failed")
        }
        XCTAssertTrue(outcome.isComplete)
        XCTAssertEqual(try String(contentsOf: url("dest/one.txt"), encoding: .utf8), "MINE",
                       "the user's file must not be replaced")
        XCTAssertEqual(try String(contentsOf: url("dest/one 2.txt"), encoding: .utf8), "one",
                       "the archive's copy must still be placed, numbered")
        XCTAssertEqual(outcome.renamed, ["one 2.txt"])
    }

    func testPlainTarAndTarBz2Extract() async throws {
        _ = sh("/usr/bin/tar", ["-cf", url("out/p.tar").path, "-C", url("a").path, "one.txt"])
        _ = sh("/usr/bin/tar", ["-cjf", url("out/p.tar.bz2").path, "-C", url("b").path, "two.txt"])
        for (name, item) in [("p.tar", "one.txt"), ("p.tar.bz2", "two.txt")] {
            guard case .success(let batch) = await ArchiveRunner.extractToStaging(archive: url("out/\(name)"), near: url("dest"))
            else { XCTFail(name); continue }
            XCTAssertEqual(batch.items, [item], name)
            ArchiveRunner.discard(batch)
        }
    }

    func testStderrIsReadSoALoudToolCannotDeadlock() async throws {
        // 200 KB on stderr — far beyond a pipe buffer. With the old unread Pipe the child blocked forever.
        let r = await ArchiveRunner.run(ArchiveEngine.Command(executable: "/bin/sh",
                                                             arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' x >&2"],
                                                             currentDirectory: nil))
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.stderr.count, 200_000)
    }

    func testCancellingTerminatesTheChild() async throws {
        let task = Task { await ArchiveRunner.run(ArchiveEngine.Command(executable: "/bin/sleep", arguments: ["20"], currentDirectory: nil)) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let started = Date()
        task.cancel()
        let r = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "cancel did not stop the process")
        XCTAssertNotEqual(r.status, 0)
    }

    /// The measured race: `pid` used to be published only after `try p.run()`, so a cancel landing in
    /// that window read pid 0, skipped `kill`, and the child ran on with nobody able to stop it. This
    /// cancels before the child can plausibly have been launched — the category of window the old
    /// code lost — and requires the side effect to be absent afterwards.
    func testCancelArrivingBeforeTheChildPidIsPublishedStillStopsIt() async throws {
        let marker = url("late-child-marker")
        let command = ArchiveEngine.Command(executable: "/bin/sh",
                                            arguments: ["-c", "sleep 1; : > '\(marker.path)'"],
                                            currentDirectory: nil)
        let task = Task { await ArchiveRunner.run(command) }
        // No sleep at all: cancel immediately, which lands before or around `p.run()`.
        task.cancel()
        let r = await task.value
        XCTAssertNotEqual(r.status, 0, "a cancelled run must not report success")
        // The child would have touched the marker after 1s; give it time to have done so if it lived.
        try await Task.sleep(nanoseconds: 1_600_000_000)
        XCTAssertFalse(fm.fileExists(atPath: marker.path),
                       "the child survived cancellation and executed its side effect")
    }

    // MARK: - Ownership and cleanup

    /// Measured before 03B: compressing into an existing non-empty directory removed the directory and
    /// its contents when the tool failed. A path the call did not create must never be deleted.
    func testAFailedCompressionNeverDeletesAnOutputThatAlreadyExisted() async throws {
        let existing = url("out/keep-me")
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try "SENTINEL".write(to: existing.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)

        let r = await ArchiveRunner.compress(sources: [url("a/one.txt")], format: .zip, output: existing)

        XCTAssertNotEqual(r, .success(existing), "zipping onto a directory cannot succeed")
        XCTAssertTrue(fm.fileExists(atPath: existing.appendingPathComponent("sentinel.txt").path),
                      "the existing directory and its contents were deleted by failure cleanup")
    }

    /// The counterpart: an output that did not exist at entry IS the job's, and a failed run must not
    /// leave a half-written file behind.
    func testAFailedCompressionRemovesThePartialOutputItCreated() async throws {
        let out = url("out/partial.zip")
        // A source that disappears after the up-front check makes the tool fail mid-run.
        let r = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/gone.txt")], format: .zip, output: out)
        XCTAssertEqual(r, .failure(.missingSource(["gone.txt"])))
        XCTAssertFalse(fm.fileExists(atPath: out.path))
    }

    /// `discard` must not delete a folder the job no longer owns. The recorded inode is what proves
    /// ownership: replace the path with a different directory and the removal has to be refused.
    func testDiscardRefusesADirectoryTheJobNoLongerOwns() async throws {
        let archive = url("out/own.zip")
        // Two sources on purpose: the single-file `ditto --keepParent` path has its own measured
        // read-back bug (see the worklog), and this test is about ownership, not about creation.
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        let staged = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest"))
        guard case .success(let batch) = staged else { return XCTFail("\(staged)") }
        let staging = batch.staging
        try fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try "NOT MINE".write(to: staging.appendingPathComponent("user.txt"), atomically: true, encoding: .utf8)

        ArchiveRunner.discard(batch)

        XCTAssertTrue(fm.fileExists(atPath: staging.appendingPathComponent("user.txt").path),
                      "discard deleted a directory that replaced the job's staging folder")
        try? fm.removeItem(at: staging)
    }

    /// Staging holds the archive's contents before the user has decided anything, so it must not be
    /// readable by other users on the machine.
    func testStagingIsCreatedPrivate() async throws {
        let archive = url("out/priv.zip")
        // Two sources: see the ownership test above for why the single-file path is avoided here.
        let compressed = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        XCTAssertEqual(compressed, .success(archive))
        let staged = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest"))
        guard case .success(let batch) = staged else { return XCTFail("\(staged)") }
        defer { ArchiveRunner.discard(batch) }
        let attributes = try fm.attributesOfItem(atPath: batch.staging.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o700, "staging must not be readable by other users")
    }

    /// The refusal itself, not just the happy path: the system hands out 0700 folders, so the guard
    /// is pinned on a folder that is deliberately not private. Without this the guard could be
    /// deleted and every other test would still pass.
    func testThePrivacyGuardRefusesAWorldReadableDirectory() throws {
        let open = url("out/open")
        try fm.createDirectory(at: open, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: open.path)
        XCTAssertFalse(ArchiveRunner.isPrivateDirectory(open))

        let closed = url("out/closed")
        try fm.createDirectory(at: closed, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: closed.path)
        XCTAssertTrue(ArchiveRunner.isPrivateDirectory(closed))

        XCTAssertFalse(ArchiveRunner.isPrivateDirectory(url("out/does-not-exist")))
    }

    // MARK: - Destination symlinks

    /// Measured (spec §2): with `dest/folder` a symlink to another directory, Merge reported success
    /// and wrote the payload outside the folder the user chose. Nothing may be written through it.
    func testMergeRefusesToWriteThroughADestinationSymlink() async throws {
        let archive = url("out/sym.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/folder")], format: .zip, output: archive)
        let outside = url("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try "ORIGINAL".write(to: outside.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: url("dest/folder").path, withDestinationPath: outside.path)

        guard case .success(let batch) = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest")) else {
            return XCTFail()
        }
        let r = await ArchiveRunner.place(batch, into: url("dest"), policy: .merge,
                                          recoveryRoot: url("recovery"))

        // Spec §5 allows either refusing or preserving the incoming object under an explicitly safe
        // numbered name; this app numbers it, and the whole point is that the payload does NOT land in
        // `outside/`. Nothing may be written through the link, and the rename is reported.
        guard case .success(let outcome) = r else { return XCTFail("expected a placement result, got \(r)") }
        XCTAssertTrue(outcome.isComplete, "\(outcome)")
        XCTAssertEqual(outcome.renamed, ["folder 2"], "\(outcome.renamed)")
        XCTAssertTrue(fm.fileExists(atPath: url("dest/folder 2/deep.txt").path),
                      "the payload must land under a numbered folder beside the link")
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("deep.txt"), encoding: .utf8), "ORIGINAL",
                       "the archive was written through the destination symlink")
    }

    /// The helper is pure enough to pin directly: `base` is the folder the user chose and is trusted
    /// (macOS itself spells `/var` and `/tmp` as symlinks, so checking above it would refuse every
    /// temporary folder); anything *below* it that is a link must be reported.
    func testSymlinkedComponentOnlyLooksBelowTheChosenDestination() throws {
        let outside = url("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: url("dest/folder").path, withDestinationPath: outside.path)

        // A write to dest/folder/deep.txt would go through the link at dest/folder.
        XCTAssertEqual(ArchiveRunner.symlinkedComponent(of: url("dest/folder/deep.txt"), under: url("dest")),
                       url("dest/folder"))
        XCTAssertEqual(ArchiveRunner.symlinkedComponent(of: url("dest/folder"), under: url("dest")),
                       url("dest/folder"))
        // The base itself is trusted, so a link *at* it is not reported when it is the base.
        XCTAssertNil(ArchiveRunner.symlinkedComponent(of: url("dest/folder/deep.txt"), under: url("dest/folder")))
        XCTAssertNil(ArchiveRunner.symlinkedComponent(of: url("dest"), under: url("dest")))
        // A path that does not exist yet is not a link.
        XCTAssertNil(ArchiveRunner.symlinkedComponent(of: url("dest/plain/x.txt"), under: url("dest")))
        // A target outside the base is not this function's business.
        XCTAssertNil(ArchiveRunner.symlinkedComponent(of: url("outside/x.txt"), under: url("dest")))
    }

    /// B2a review, reproduced: a nested link to an outside file, merged into an existing folder,
    /// replaced the user's file and wrote through to the outside target. Now nothing is placed.
    func testAnArchiveWithAnEscapingLinkIsRefusedBeforeAnythingIsPlaced() async throws {
        let secret = url("secret.txt"); try "SECRET".write(to: secret, atomically: true, encoding: .utf8)
        let src = url("evil/Project/config")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: src.appendingPathComponent("settings.json").path, withDestinationPath: secret.path)
        _ = sh("/usr/bin/ditto", ["-c", "-k", "--keepParent", url("evil/Project").path, url("out/evil.zip").path])
        try fm.createDirectory(at: url("dest/Project/config"), withIntermediateDirectories: true)
        try "ORIGINAL".write(to: url("dest/Project/config/settings.json"), atomically: true, encoding: .utf8)
        let r = await ArchiveRunner.extractToStaging(archive: url("out/evil.zip"), near: url("dest"))
        // Stage 03B refuses this from the manifest, before any decoder runs: an absolute link target
        // is a rules verdict, not something discovered after materialisation.
        guard case .failure(.unsafeArchive(let reasons, _)) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(reasons, [.absoluteLink("Project/config/settings.json", target: secret.path)])
        XCTAssertEqual(try String(contentsOf: url("dest/Project/config/settings.json"), encoding: .utf8), "ORIGINAL")
        XCTAssertEqual(try String(contentsOf: secret, encoding: .utf8), "SECRET")
    }

    /// Suspected bypass, measured NOT to be one — kept as a regression guard. FileManager's listings hide regular files
    /// named "._…" (F1, macOS 27), and `tar -xf` (bsdtar) DOES create a "._settings.json" symlink from an archive made
    /// elsewhere (`ditto -x -k` does not). If the guard could not see that link, a merge would place it and XFinder's
    /// own `zip -r` (which follows links) would later pack the outside file. It can: FileManager still lists LINKS
    /// named "._…". This pins both facts. `--no-mac-metadata` makes macOS tar store the "._" entry literally, like GNU tar.
    func testAnEscapingLinkNamedLikeAppleDoubleIsRefusedToo() async throws {
        let secret = url("secret.txt"); try "SECRET".write(to: secret, atomically: true, encoding: .utf8)
        let src = url("evil/Project/config")
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try "real".write(to: src.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: src.appendingPathComponent("._settings.json").path, withDestinationPath: secret.path)
        let made = sh("/usr/bin/tar", ["--no-mac-metadata", "-czf", url("out/evil.tar.gz").path, "-C", url("evil").path, "Project"])
        XCTAssertEqual(made.0, 0, made.1)
        XCTAssertTrue(sh("/usr/bin/tar", ["-tf", url("out/evil.tar.gz").path]).1.contains("Project/config/._settings.json"),
                      "the fixture must actually carry the ._ link, or this test proves nothing")
        let r = await ArchiveRunner.extractToStaging(archive: url("out/evil.tar.gz"), near: url("dest"))
        guard case .failure(.unsafeArchive(let reasons, _)) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(reasons, [.absoluteLink("Project/config/._settings.json", target: secret.path)])
        XCTAssertFalse(fm.fileExists(atPath: url("dest/Project").path), "nothing placed")
    }

    /// The second identity check covers a different instant from the first: the decoder has already
    /// run, so the validated manifest describes a file that no longer exists on disk. Driven through
    /// `finishExtraction` because the real window is microseconds wide; both checks use the same
    /// comparison, so removing either leaves the other refusing the obvious case, but only this one
    /// covers a swap *during* extraction.
    func testAnArchiveSwappedWhileTheDecoderRunsIsRefusedAfterwards() throws {
        let archive = url("out/during.zip")
        writeHostileZip(archive, names: ["ok.txt"])
        let inspection = try SystemArchiveReader().inspect(at: archive)
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                             appropriateFor: url("dest"), create: true)
        guard let owned = ArchiveRunner.OwnedDirectory.adopt(dir) else { return XCTFail("no ownership") }
        try fm.removeItem(at: archive)   // the swap lands while the decoder is "running"

        let r = ArchiveRunner.finishExtraction(archive: archive, inspection: inspection, dir: dir,
                                               owned: owned, result: .init(status: 0, stderr: ""))

        guard case .failure(.archiveChanged) = r else { return XCTFail("a swap during extraction must be refused: \(r)") }
        XCTAssertFalse(fm.fileExists(atPath: dir.path), "the staging folder must be cleaned up on refusal")
    }

    /// The stage 03A second layer, tested directly. It runs *after* a decoder has written into staging,
    /// so its input is whatever is on disk — including a `._`-prefixed link, which `bsdtar` creates when
    /// unpacking a foreign tar and which any listing that applies AppleDouble conventions would skip.
    /// The manifest check above refuses hostile links before writing; this walk is what catches a
    /// decoder materialising a link the manifest did not describe, so it must see every name.
    func testThePostExtractionLinkWalkSeesEveryEscapingLink() throws {
        let dir = url("staging")
        try fm.createDirectory(at: dir.appendingPathComponent("Project/config"), withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("Project/plain.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: dir.appendingPathComponent("Project/config/._settings.json").path,
                                  withDestinationPath: "/etc/passwd")
        try fm.createSymbolicLink(atPath: dir.appendingPathComponent("up").path,
                                  withDestinationPath: "../../etc/passwd")
        try fm.createSymbolicLink(atPath: dir.appendingPathComponent("Project/inside.txt").path,
                                  withDestinationPath: "plain.txt")

        XCTAssertEqual(ArchiveRunner.escapingLinks(in: dir),
                       ["Project/config/._settings.json", "up"],
                       "a link that stays inside the folder is fine; every escaping one must be named")
    }

    /// The pre-extraction identity guard must refuse **before a decoder runs**. With the inspected file
    /// deleted, a guard that fires reports "the archive changed"; a missing guard lets `ditto` notice
    /// instead and the user is told the tool failed — a different failure, and one that leaves no doubt
    /// that the validated manifest was never checked against the bytes.
    func testAMissingArchiveIsRefusedByTheIdentityGuardBeforeTheDecoderRuns() async throws {
        let archive = url("out/gone.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        let inspection = try SystemArchiveReader().inspect(at: archive)
        try fm.removeItem(at: archive)

        let r = await ArchiveRunner.extractVerified(archive: archive, inspection: inspection, near: url("dest"))

        guard case .failure(.archiveChanged) = r else {
            return XCTFail("the decoder must never be the one to notice a stale manifest: \(r)")
        }
    }

    // MARK: - Shared pre-flight (stage 03B)

    /// Builds a ZIP whose entry names are hostile, without any tool normalising them first.
    ///
    /// `zip` and `ditto` both rewrite `../` and a leading `/` (measured, spec §2), so a fixture for
    /// "the app refuses this" has to be written byte by byte. Only stored (uncompressed) entries are
    /// produced, which is enough: the reader and the rules never look at compression.
    func writeHostileZip(_ path: URL, names: [String], payload: String = "x") {
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func crc32(_ data: Data) -> UInt32 {
            var table = [UInt32](repeating: 0, count: 256)
            for i in 0..<256 {
                var value = UInt32(i)
                for _ in 0..<8 { value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1) }
                table[i] = value
            }
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
            return crc ^ 0xFFFF_FFFF
        }
        let bytes = Data(payload.utf8)
        var out = Data(), central = Data()
        for name in names {
            let nameBytes = Data(name.utf8)
            let offset = UInt32(out.count)
            out.append(le32(0x0403_4b50)); out.append(le16(20)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0)); out.append(le16(0))
            out.append(le32(crc32(bytes))); out.append(le32(UInt32(bytes.count))); out.append(le32(UInt32(bytes.count)))
            out.append(le16(UInt16(nameBytes.count))); out.append(le16(0)); out.append(nameBytes); out.append(bytes)

            central.append(le32(0x0201_4b50)); central.append(le16(0x0314)); central.append(le16(20))
            central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le32(crc32(bytes))); central.append(le32(UInt32(bytes.count))); central.append(le32(UInt32(bytes.count)))
            central.append(le16(UInt16(nameBytes.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0o100644 << 16))
            central.append(le32(offset)); central.append(nameBytes)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(names.count))); out.append(le16(UInt16(names.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset)); out.append(le16(0))
        try? out.write(to: path)
    }

    /// Measured before 03B: two ZIP entries named `same.txt` both existed in the archive, `ditto`
    /// silently kept the LAST one, and the runner reported success — so a user lost the first entry
    /// with no message. The whole archive must now be refused before anything is written.
    func testDuplicateEntryNamesRejectTheWholeArchiveBeforeAnythingIsWritten() async throws {
        let archive = url("out/dup.zip")
        writeHostileZip(archive, names: ["same.txt", "same.txt"])
        XCTAssertEqual(sh("/usr/bin/unzip", ["-Z1", archive.path]).1.split(separator: "\n").count, 2,
                       "the fixture must really carry two entries")

        let before = try fm.contentsOfDirectory(atPath: url("dest").path).sorted()
        let r = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest"))

        guard case .failure(.unsafeArchive(let reasons, _)) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(reasons.contains(.duplicatePath("same.txt")), "\(reasons)")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: url("dest").path).sorted(), before,
                       "a refused archive must not write into the destination")
    }

    /// Measured before 03B: `ditto -x` normalised `../escaped.txt` to `escaped.txt` inside the
    /// extraction root and stripped a leading `/` from an absolute entry — exit 0 both times. That is
    /// a tool accident, not a policy: the app must refuse the raw names.
    func testDotDotAndAbsoluteEntryNamesRejectTheWholeArchive() async throws {
        for (name, expected) in [("../escaped.txt", ArchiveSafetyRules.Reason.escapesRoot("../escaped.txt")),
                                 ("/tmp/absolute.txt", .absolutePath("/tmp/absolute.txt"))] {
            let archive = url("out/hostile-\(UUID().uuidString).zip")
            writeHostileZip(archive, names: [name])
            let outsideMarker = url("escaped.txt")

            let r = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest"))

            guard case .failure(.unsafeArchive(let reasons, _)) = r else { return XCTFail("\(name): \(r)") }
            XCTAssertTrue(reasons.contains(expected), "\(name): \(reasons)")
            XCTAssertFalse(fm.fileExists(atPath: outsideMarker.path), "\(name) escaped into the parent")
        }
    }

    /// The archive is inspected, then the file is replaced before extraction: the validated manifest no
    /// longer describes the bytes on disk, so extraction must refuse rather than extract something the
    /// rules never saw. Driven through the split API because the real window is microseconds wide.
    func testAnArchiveSwappedAfterInspectionIsRefusedBeforeExtraction() async throws {
        let archive = url("out/swap.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        let inspection = try SystemArchiveReader().inspect(at: archive)

        // Same path, different inode: write a new file over it.
        try fm.removeItem(at: archive)
        _ = await ArchiveRunner.compress(sources: [url("a/same.txt"), url("b/same.txt")], format: .zip, output: archive)

        let r = await ArchiveRunner.extractVerified(archive: archive, inspection: inspection, near: url("dest"))

        guard case .failure(.archiveChanged(let detail)) = r else { return XCTFail("\(r)") }
        XCTAssertFalse(detail.isEmpty)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: url("dest").path), [], "nothing may be extracted")
    }

    /// An archive that is not one of the approved formats is refused by the reader, and the app says
    /// "cannot be checked here" rather than extracting it unverified through `tar`/`ditto`.
    func testAnUnsupportedFormatIsRefusedRatherThanExtractedUnverified() async throws {
        let archive = url("out/random.zip")
        try Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: archive)

        let r = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest"))

        guard case .failure(.unsafeArchive(let reasons, let diagnostic)) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(reasons.isEmpty, "a format refusal is not a path-rule verdict: \(reasons)")
        XCTAssertNotNil(diagnostic, "the refusal must keep the reader's diagnostic for the log")
    }

    /// The reader's missing-symbol path must read as "cannot check here", not as "your archive is bad".
    func testReaderUnavailabilityIsMappedToItsOwnFailure() {
        XCTAssertEqual(ArchiveRunner.map(.libraryUnavailable), .readerUnavailable)
        XCTAssertEqual(ArchiveRunner.map(.formatRegistrationFailed(symbol: "x")), .readerUnavailable)
        guard case .archiveChanged = ArchiveRunner.map(.notMaterialised) else {
            return XCTFail("a cloud placeholder is a change of state, not a hostile archive")
        }
    }

    /// Free-space planning must refuse honestly. An ordinary archive into a temporary folder has
    /// capacity, so this pins that the query really is wired (a missing query would surface as
    /// `.spaceUnknown`, which is itself a refusal — so assert success here).
    func testTheCapacityQueryIsWiredForAnOrdinaryDestination() async throws {
        let archive = url("out/cap.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        XCTAssertNotNil(ArchiveRunner.availableBytes(for: url("dest")),
                        "the volume query must return a number, or every extraction is refused")
        let staged = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest"))
        guard case .success(let batch) = staged else { return XCTFail("\(staged)") }
        ArchiveRunner.discard(batch)
    }

    /// The capacity query must find a volume for a destination that does not exist yet: the callers
    /// pass "the folder I am about to create", not an existing path.
    func testTheCapacityQueryWorksForADestinationThatDoesNotExistYet() {
        XCTAssertNotNil(ArchiveRunner.availableBytes(for: url("not-created-yet/new-folder")))
    }

    /// A rejection that says "not enough space" must reach the caller as its own sentence, not as
    /// "this archive is unsafe": on a full disk the archive is perfectly ordinary and the remedy is
    /// different. Split out because a temporary folder always has room, so the real path cannot
    /// produce this refusal here.
    func testSpaceRejectionsBecomeTheirOwnFailure() {
        XCTAssertEqual(ArchiveRunner.spaceFailure(from: [.insufficientSpace(required: 900, available: 100)]),
                       .outOfSpace(required: 900, available: 100))
        // Unknown capacity is its own case: it used to be reported as "0 / 0", which the page printed
        // as "Không đủ dung lượng" next to "Zero KB / Zero KB" — a shortage the user does not have.
        XCTAssertEqual(ArchiveRunner.spaceFailure(from: [.spaceUnknown]), .spaceUnknown)
        XCTAssertNil(ArchiveRunner.spaceFailure(from: [.duplicatePath("a"), .escapesRoot("../b")]),
                     "an ordinary rules rejection is not a space problem")
    }

    /// The identity comparison itself. It is called at two points (before and after extraction) and
    /// each call on its own is enough to refuse a swap, which is why removing either one leaves every
    /// other test green — the guard is pinned here so the comparison itself cannot rot.
    func testIdentityComparisonDetectsEveryKindOfChange() async throws {
        let archive = url("out/id.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        let inspection = try SystemArchiveReader().inspect(at: archive)
        XCTAssertTrue(ArchiveRunner.identityStillMatches(inspection.identity, at: archive))

        // Same path, different inode.
        try fm.removeItem(at: archive)
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        XCTAssertFalse(ArchiveRunner.identityStillMatches(inspection.identity, at: archive))

        // A symlink where the file was is not the file, even if it points at an identical copy.
        try fm.removeItem(at: archive)
        let copy = url("out/id-copy.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: copy)
        try fm.createSymbolicLink(atPath: archive.path, withDestinationPath: copy.path)
        XCTAssertFalse(ArchiveRunner.identityStillMatches(inspection.identity, at: archive))

        // Nothing there at all.
        XCTAssertFalse(ArchiveRunner.identityStillMatches(inspection.identity, at: url("out/gone.zip")))
    }

    /// A reader that cannot run must read as "cannot check here", which the mapping already produces
    /// from `inspect` throwing. The explicit availability check in `extractToStaging` is a fast path
    /// on top of that, not a separate guarantee.
    func testReaderUnavailabilityMappingCoversTheInspectPath() {
        XCTAssertEqual(ArchiveRunner.map(.libraryUnavailable), .readerUnavailable)
    }
}

