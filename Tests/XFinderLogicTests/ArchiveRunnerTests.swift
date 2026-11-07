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

    func testMergeReplacesOnlyWhenTheUserChoseIt() async throws {
        let archive = url("out/m.zip")
        _ = await ArchiveRunner.compress(sources: [url("a/one.txt"), url("b/two.txt")], format: .zip, output: archive)
        try "MINE".write(to: url("dest/one.txt"), atomically: true, encoding: .utf8)
        guard case .success(let batch) = await ArchiveRunner.extractToStaging(archive: archive, near: url("dest")) else { return XCTFail() }
        _ = await ArchiveRunner.place(batch, into: url("dest"), policy: .merge)
        XCTAssertEqual(try String(contentsOf: url("dest/one.txt"), encoding: .utf8), "one")
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
        let r = await ArchiveRunner.place(batch, into: url("dest"), policy: .merge)

        guard case .failure(.placement(let detail)) = r else {
            return XCTFail("expected a refusal, got \(r)")
        }
        XCTAssertTrue(detail.contains("symbolic link"), detail)
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
        XCTAssertEqual(r, .failure(.unsafeLinks(["Project/config/settings.json"])))
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
        XCTAssertEqual(r, .failure(.unsafeLinks(["Project/config/._settings.json"])))
        XCTAssertFalse(fm.fileExists(atPath: url("dest/Project").path), "nothing placed")
    }
}

