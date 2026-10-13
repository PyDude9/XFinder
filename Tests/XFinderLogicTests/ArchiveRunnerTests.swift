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

