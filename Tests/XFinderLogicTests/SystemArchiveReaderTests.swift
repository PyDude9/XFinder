import XCTest
import Foundation

/// Tests for `SystemArchiveReader`, the runtime-bound libarchive manifest reader of XF-MFGAP-03
/// stage 03A.
///
/// These are **not** pure tests: each one builds a real fixture in a unique temporary directory and
/// asks the system libarchive to read it. That is deliberate — the whole point of this file is that
/// the decisions must be made from what the platform actually reports, and every behaviour asserted
/// here was measured first (see the header of `SystemArchiveReader.swift`). Fixtures are created
/// only under `NSTemporaryDirectory()`, each test owns its own directory, and nothing outside it is
/// read or written.
///
/// If the platform ever stops exposing libarchive, `SystemArchiveReader.isAvailable` is false and
/// `testLibraryIsAvailableOnThisSystem` fails loudly rather than letting the suite pass vacuously.
final class SystemArchiveReaderTests: XCTestCase {

    private var root: URL!
    private let reader = SystemArchiveReader()

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xf-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        try super.tearDownWithError()
    }

    // MARK: - Availability

    func testLibraryIsAvailableOnThisSystem() {
        // The SDK ships no archive.h, so this is the only thing standing between the app and a reader
        // that silently does nothing. On a supported macOS it must hold.
        XCTAssertTrue(SystemArchiveReader.isAvailable,
                      "system libarchive must be reachable via dlopen on macOS 14+")
    }

    // MARK: - Fixtures

    @discardableResult
    private func tool(_ executable: String, _ arguments: [String], in directory: URL? = nil) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func makeSource(_ files: [String: String]) throws -> URL {
        let directory = root.appendingPathComponent("src-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, body) in files {
            let url = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func zip(_ files: [String: String], name: String = "fixture.zip") throws -> URL {
        let source = try makeSource(files)
        let archive = root.appendingPathComponent(name)
        XCTAssertEqual(tool("/usr/bin/zip", ["-qr", archive.path, "."], in: source), 0)
        return archive
    }

    private func tar(_ files: [String: String], name: String = "fixture.tar", flags: [String] = ["-cf"]) throws -> URL {
        let source = try makeSource(files)
        let archive = root.appendingPathComponent(name)
        // Archive the top-level items by name rather than ".": the "." form emits a "./" root entry
        // and "./"-prefixed paths, which is a separate, explicitly tested case below.
        let topLevel = Set(files.keys.map { $0.split(separator: "/").first.map(String.init) ?? $0 }).sorted()
        XCTAssertEqual(tool("/usr/bin/tar", flags + [archive.path, "-C", source.path] + topLevel), 0)
        return archive
    }

    /// The `tar -cf out.tar .` shape: every path is "./"-prefixed and a "./" root entry exists.
    private func dotTar(_ files: [String: String], name: String = "dot.tar") throws -> URL {
        let source = try makeSource(files)
        let archive = root.appendingPathComponent(name)
        XCTAssertEqual(tool("/usr/bin/tar", ["-cf", archive.path, "-C", source.path, "."]), 0)
        return archive
    }

    // MARK: - Hand-built archives
    //
    // The hostile shapes are hand-built because every system tool normalises them away: `ditto`
    // strips a leading "/" and `bsdtar` refuses to create "../" at all.

    private func writeZip(_ path: URL,
                          entries: [(name: [UInt8], data: Data, mode: UInt32, flags: UInt16)]) {
        var out = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt32(out.count)
            out.append(le32(0x0403_4b50)); out.append(le16(20)); out.append(le16(entry.flags))
            out.append(le16(0)); out.append(le16(0)); out.append(le16(0))
            out.append(le32(crc32(entry.data)))
            out.append(le32(UInt32(entry.data.count))); out.append(le32(UInt32(entry.data.count)))
            out.append(le16(UInt16(entry.name.count))); out.append(le16(0))
            out.append(Data(entry.name)); out.append(entry.data)

            central.append(le32(0x0201_4b50)); central.append(le16(0x0314)); central.append(le16(20))
            central.append(le16(entry.flags)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le32(crc32(entry.data)))
            central.append(le32(UInt32(entry.data.count))); central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(entry.name.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(entry.mode << 16))
            central.append(le32(offset)); central.append(Data(entry.name))
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset)); out.append(le16(0))
        try! out.write(to: path)
    }

    private func writeTar(_ path: URL,
                          entries: [(name: String, type: UInt8, declared: Int, payload: Data, link: String)]) {
        var out = Data()
        for entry in entries {
            var header = Data(count: 512)
            func put(_ string: String, _ offset: Int, _ length: Int) {
                let bytes = Array(string.utf8).prefix(length)
                header.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
            }
            func putOctal(_ value: Int, _ offset: Int, _ length: Int) {
                let digits = String(value, radix: 8)
                put(String(repeating: "0", count: max(0, length - 1 - digits.count)) + digits, offset, length - 1)
                header[offset + length - 1] = 0
            }
            put(entry.name, 0, 100)
            putOctal(0o644, 100, 8); putOctal(0, 108, 8); putOctal(0, 116, 8)
            putOctal(entry.declared, 124, 12); putOctal(0, 136, 12)
            header.replaceSubrange(148..<156, with: Array("        ".utf8))
            header[156] = entry.type
            put(entry.link, 157, 100)
            put("ustar", 257, 6); put("00", 263, 2)
            var sum = 0
            for byte in header { sum += Int(byte) }
            putOctal(sum, 148, 8)
            out.append(header); out.append(entry.payload)
            let pad = (512 - (entry.payload.count % 512)) % 512
            if pad > 0 { out.append(Data(count: pad)) }
        }
        out.append(Data(count: 1024))
        try! out.write(to: path)
    }

    private func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    private func crc32(_ data: Data) -> UInt32 {
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

    private func refusal(_ url: URL,
                         bounds: SystemArchiveReader.Bounds = .proposed,
                         file: StaticString = #filePath, line: UInt = #line) -> SystemArchiveReader.Failure? {
        do {
            let inspection = try reader.inspect(at: url, bounds: bounds)
            XCTFail("expected a refusal, got \(inspection.manifest.count) entries", file: file, line: line)
            return nil
        } catch let failure as SystemArchiveReader.Failure {
            return failure
        } catch {
            XCTFail("expected Failure, got \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - Approved formats

    func testEveryApprovedFormatIsRead() throws {
        // Each of these must produce the same three entries: the folder, and two files.
        let expectations: [(String, URL)] = [
            ("zip", try zip(["a.txt": "hello", "sub/b.txt": "nested"])),
            ("tar", try tar(["a.txt": "hello", "sub/b.txt": "nested"])),
            ("tar.gz", try tar(["a.txt": "hello", "sub/b.txt": "nested"], name: "f.tar.gz", flags: ["-czf"])),
            ("tar.bz2", try tar(["a.txt": "hello", "sub/b.txt": "nested"], name: "f.tar.bz2", flags: ["-cjf"])),
            ("tar.xz", try tar(["a.txt": "hello", "sub/b.txt": "nested"], name: "f.tar.xz", flags: ["-cJf"])),
        ]
        for (label, url) in expectations {
            let inspection = try reader.inspect(at: url)
            let paths = Set(inspection.manifest.map(\.rawPath))
            XCTAssertTrue(paths.contains("a.txt"), "\(label): \(paths)")
            XCTAssertTrue(paths.contains("sub/b.txt"), "\(label): \(paths)")
            XCTAssertEqual(inspection.decodedBytes, 11, "\(label) must count logical payload bytes")
            XCTAssertEqual(inspection.archiveBytes, Int64((try FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as! NSNumber).intValue), "\(label) size")
        }
    }

    func testOrdinaryArchivePassesThePureRules() throws {
        // The two halves of stage 03A must agree: what the reader produces, the rules accept.
        let url = try zip(["a.txt": "hello", "sub/b.txt": "nested"])
        let inspection = try reader.inspect(at: url)
        let verdict = ArchiveSafetyRules.validate(manifest: inspection.manifest,
                                                 compressedSize: inspection.archiveBytes,
                                                 availableBytes: 1_000_000_000_000)
        XCTAssertTrue(verdict.isAccepted, "ordinary archive refused: \(verdict.reasons)")
    }

    func testDotPrefixedTarIsAccepted() throws {
        // `tar -cf out.tar .` is an ordinary way to archive a folder and it emits a "./" root entry
        // plus "./"-prefixed paths. An earlier revision of the rules mapped that root entry to
        // `emptyPath` and therefore refused every such archive — a false positive found by exactly
        // this test. The root names the staging directory the caller already owns, so it must be
        // accepted as a directory and never appear in the plan as something to create.
        let url = try dotTar(["a.txt": "hello", "sub/b.txt": "nested"])
        let inspection = try reader.inspect(at: url)
        XCTAssertTrue(inspection.manifest.contains { $0.rawPath == "./" && $0.kind == .directory },
                      "the fixture must really contain a root entry: \(inspection.manifest.map(\.rawPath))")

        let verdict = ArchiveSafetyRules.validate(manifest: inspection.manifest,
                                                 compressedSize: inspection.archiveBytes,
                                                 availableBytes: 1_000_000_000_000)
        guard case .accepted(let plan) = verdict else {
            return XCTFail("an ordinary `tar -cf … .` must be accepted, got \(verdict.reasons)")
        }
        XCTAssertFalse(plan.orderedEntries.contains { $0.rawPath == "./" },
                       "the plan must not ask the caller to create the staging root")
        XCTAssertTrue(plan.orderedEntries.contains { $0.rawPath.hasSuffix("a.txt") })
    }

    // MARK: - Hostile paths arrive unnormalised

    func testAbsoluteAndDotDotPathsAreReportedVerbatim() throws {
        // This is the whole reason for a structured reader: the rules must see "../escaped.txt" and
        // "/tmp/absolute.txt" exactly as the archive spells them, before anything writes.
        let url = root.appendingPathComponent("hostile.zip")
        writeZip(url, entries: [
            (name: Array("../escaped.txt".utf8), data: Data("x".utf8), mode: 0o100644, flags: 0),
            (name: Array("/tmp/absolute.txt".utf8), data: Data("x".utf8), mode: 0o100644, flags: 0),
        ])
        let inspection = try reader.inspect(at: url)
        XCTAssertEqual(inspection.manifest.map(\.rawPath), ["../escaped.txt", "/tmp/absolute.txt"])

        let verdict = ArchiveSafetyRules.validate(manifest: inspection.manifest,
                                                 compressedSize: inspection.archiveBytes,
                                                 availableBytes: 1_000_000_000_000)
        XCTAssertFalse(verdict.isAccepted, "hostile paths must be refused by the rules")
    }

    func testAbsoluteSymlinkTargetIsReportedVerbatim() throws {
        let url = root.appendingPathComponent("link.zip")
        writeZip(url, entries: [
            (name: Array("jump".utf8), data: Data("/tmp".utf8), mode: 0o120777, flags: 0),
        ])
        let inspection = try reader.inspect(at: url)
        let link = try XCTUnwrap(inspection.manifest.first)
        XCTAssertEqual(link.kind, .symlink)
        XCTAssertEqual(link.linkTarget, "/tmp")
        XCTAssertFalse(ArchiveSafetyRules.validate(manifest: inspection.manifest,
                                                  availableBytes: 1_000_000_000_000).isAccepted)
    }

    func testDuplicateEntryNamesAreBothReported() throws {
        // Measured: libarchive returns both entries; `unzip` keeps only the last one's data.
        let url = root.appendingPathComponent("dup.zip")
        writeZip(url, entries: [
            (name: Array("same.txt".utf8), data: Data("FIRST".utf8), mode: 0o100644, flags: 0),
            (name: Array("same.txt".utf8), data: Data("LAST-LONGER".utf8), mode: 0o100644, flags: 0),
        ])
        let inspection = try reader.inspect(at: url)
        XCTAssertEqual(inspection.manifest.count, 2, "collapsing duplicates would hide the attack")
        XCTAssertEqual(inspection.decodedBytes, 5 + 11)
        XCTAssertFalse(ArchiveSafetyRules.validate(manifest: inspection.manifest,
                                                  availableBytes: 1_000_000_000_000).isAccepted)
    }

    // MARK: - Refusals

    func testInvalidUTF8NameIsRefused() throws {
        // `pathname` returns a lossy U+FFFD string; `pathname_utf8` returns nil. Accepting the lossy
        // spelling would mean validating a different path than the one that gets written.
        let url = root.appendingPathComponent("badname.zip")
        writeZip(url, entries: [
            (name: [0x61, 0xC0, 0xAF, 0x62], data: Data("x".utf8), mode: 0o100644, flags: 0),
        ])
        guard case .invalidEncoding = refusal(url) else { return XCTFail("expected invalidEncoding") }
    }

    func testVietnameseNameInBothCompositionsIsAccepted() throws {
        // The encoding gate must not refuse legitimate Vietnamese spelling. macOS filenames are NFD;
        // writing the same word in NFC must still round-trip through the reader.
        let nfc = "t\u{1EC7}p.txt"                 // tệp.txt, precomposed
        let url = try zip([nfc: "x"])
        let inspection = try reader.inspect(at: url)
        XCTAssertEqual(inspection.manifest.count, 1)
        XCTAssertEqual(inspection.manifest.first?.rawPath, nfc)
    }

    func testEncryptedEntryIsRefusedAtHeaderTime() throws {
        // ZipCrypto: flag bit 0 set. Measured: `archive_entry_is_encrypted` is 1 before any data call,
        // so the refusal happens before the decoder can fail halfway through.
        let url = root.appendingPathComponent("enc.zip")
        writeZip(url, entries: [
            (name: Array("secret.txt".utf8), data: Data(count: 12) + Data("plain".utf8), mode: 0o100644, flags: 1),
        ])
        guard case .encrypted = refusal(url) else { return XCTFail("expected encrypted") }
    }

    func testSparseEntryIsRefusedRatherThanUndercounted() throws {
        // The trap this reader exists to avoid. Measured: a tar holding a hole-only 200 MiB file
        // reports declared = 209715200 and `archive_read_data` yields **0 bytes with no error**, while
        // `tar -x` faithfully recreates the full file. Any byte budget built on decoded bytes would
        // be defeated, so sparse entries are refused outright.
        let source = root.appendingPathComponent("sparse-src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let hole = source.appendingPathComponent("zeros.bin")
        FileManager.default.createFile(atPath: hole.path, contents: nil)
        let descriptor = open(hole.path, O_WRONLY)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        XCTAssertEqual(ftruncate(descriptor, 4 << 20), 0)
        close(descriptor)

        let archive = root.appendingPathComponent("sparse.tar")
        XCTAssertEqual(tool("/usr/bin/tar", ["-cf", archive.path, "-C", source.path, "zeros.bin"]), 0)
        guard case .sparse = refusal(archive) else { return XCTFail("expected sparse") }
    }

    func testTruncatedPayloadIsRefused() throws {
        // The header declares 8 KiB; the archive carries 1 KiB plus the end-of-archive block. Only a
        // runtime check catches this — the declared size looks entirely reasonable.
        let url = root.appendingPathComponent("truncated.tar")
        writeTar(url, entries: [
            (name: "big.bin", type: UInt8(ascii: "0"), declared: 8192,
             payload: Data(repeating: 0x41, count: 1024), link: ""),
        ])
        guard let failure = refusal(url) else { return }
        switch failure {
        case .sizeMismatch, .damaged: break
        default: XCTFail("expected sizeMismatch or damaged, got \(failure)")
        }
    }

    func testUnapprovedFormatIsRefusedAtOpen() throws {
        // Only zip and tar are registered on purpose. With format_all an unknown container would be
        // handed to a decoder this app has never tested.
        let url = root.appendingPathComponent("random.bin")
        try Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        guard case .unsupportedFormat = refusal(url) else { return XCTFail("expected unsupportedFormat") }
    }

    func testSevenZipSignatureIsRefused() throws {
        let url = root.appendingPathComponent("x.7z")
        try Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C] + [UInt8](repeating: 0, count: 2048)).write(to: url)
        guard case .unsupportedFormat = refusal(url) else { return XCTFail("expected unsupportedFormat") }
    }

    func testDirectoryIsNotAnArchive() throws {
        let directory = try makeSource(["a.txt": "x"])
        XCTAssertEqual(refusal(directory), .notRegularFile)
    }

    func testSymlinkToAnArchiveIsNotFollowed() throws {
        // The layering is deliberate: `lstat` refuses a symlink without opening it, `O_NOFOLLOW`
        // closes the window between that stat and the open, and the `fstat` identity comparison proves
        // the descriptor is the inspected inode. Each is measured; a symlink is caught by the first.
        let archive = try zip(["a.txt": "x"])
        let link = root.appendingPathComponent("link.zip")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: archive.path)
        XCTAssertEqual(refusal(link), .notRegularFile,
                       "a symlink must be refused as a non-regular file, never followed")
    }

    func testSymlinkIsRefusedEvenWithoutO_NOFOLLOW() throws {
        // Guard against the layering being removed wholesale: if `lstat` were skipped, the identity
        // comparison against `fstat` must still refuse. Asserted through the public API only, so it
        // holds whichever layer is doing the work.
        let archive = try zip(["a.txt": "x"])
        let link = root.appendingPathComponent("link2.zip")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: archive.path)
        var byPath = stat()
        XCTAssertEqual(lstat(link.path, &byPath), 0)
        var followed = stat()
        XCTAssertEqual(stat(link.path, &followed), 0, "stat() follows; this is what a missing guard sees")
        XCTAssertNotEqual(byPath.st_ino, followed.st_ino,
                          "the two stats genuinely differ, so the comparison is not vacuous")
        XCTAssertNil(try? reader.inspect(at: link))
    }

    func testSymlinkSwapAfterTheCallersDecisionIsCaught() throws {
        // The scenario the identity comparison exists for: the path is replaced between the caller's
        // decision and this inspection. Verified structurally — the `lstat` inode and the `stat`
        // inode of a symlink genuinely differ, which is exactly what the comparison detects.
        let archive = try zip(["a.txt": "x"])
        let link = root.appendingPathComponent("swapped.zip")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: archive.path)

        var byPath = stat()
        XCTAssertEqual(lstat(link.path, &byPath), 0, "lstat must see the link itself")
        XCTAssertNotEqual(byPath.st_mode & S_IFMT, S_IFREG, "the path must not be a regular file")

        // Whatever the OS returns, the reader must never return an inspection for a path that is not
        // the regular file it stat'ed.
        XCTAssertNil(try? reader.inspect(at: link))
    }

    func testOpeningThroughAFIFOIsNotPossible() throws {
        // A FIFO at the archive path would block a naive open forever. `O_NONBLOCK` plus the
        // regular-file check must turn it into a refusal rather than a hang; the timeout is implicit
        // in the test runner, so a hang here shows up as a stalled suite rather than a wrong answer.
        let fifo = root.appendingPathComponent("pipe.zip")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        guard let failure = refusal(fifo) else { return }
        XCTAssertEqual(failure, .notRegularFile, "a FIFO must be refused, not read")
    }

    func testMissingFileIsRefused() {
        let missing = root.appendingPathComponent("nope.zip")
        guard let failure = refusal(missing) else { return }
        guard case .openFailed(let code) = failure else { return XCTFail("expected openFailed, got \(failure)") }
        XCTAssertEqual(code, ENOENT)
    }

    // MARK: - Entry kinds

    func testEntryKindsAreClassified() throws {
        let url = root.appendingPathComponent("types.tar")
        writeTar(url, entries: [
            (name: "dir/", type: UInt8(ascii: "5"), declared: 0, payload: Data(), link: ""),
            (name: "dir/f.txt", type: UInt8(ascii: "0"), declared: 3, payload: Data("abc".utf8), link: ""),
            (name: "sl", type: UInt8(ascii: "2"), declared: 0, payload: Data(), link: "dir/f.txt"),
            (name: "hl", type: UInt8(ascii: "1"), declared: 0, payload: Data(), link: "dir/f.txt"),
        ])
        let inspection = try reader.inspect(at: url)
        let byPath = Dictionary(uniqueKeysWithValues: inspection.manifest.map { ($0.rawPath, $0) })
        XCTAssertEqual(byPath["dir/"]?.kind, .directory)
        XCTAssertEqual(byPath["dir/f.txt"]?.kind, .regular)
        XCTAssertEqual(byPath["dir/f.txt"]?.declaredSize, 3)
        XCTAssertEqual(byPath["sl"]?.kind, .symlink)
        XCTAssertEqual(byPath["sl"]?.linkTarget, "dir/f.txt")
        // A hard link reports filetype 0, so it is only identifiable through the link accessor.
        XCTAssertEqual(byPath["hl"]?.kind, .hardlink)
        XCTAssertEqual(byPath["hl"]?.linkTarget, "dir/f.txt")
    }

    func testFIFOIsReportedAsUnsupported() throws {
        // The reader classifies it; the rules are what refuse it. Doing both here would hide which
        // layer failed if the refusal ever stopped working.
        let url = root.appendingPathComponent("fifo.tar")
        writeTar(url, entries: [
            (name: "pipe", type: UInt8(ascii: "6"), declared: 0, payload: Data(), link: ""),
        ])
        let inspection = try reader.inspect(at: url)
        XCTAssertEqual(inspection.manifest.first?.kind, .unsupported)
        XCTAssertFalse(ArchiveSafetyRules.validate(manifest: inspection.manifest,
                                                  availableBytes: 1_000_000_000_000).isAccepted)
    }

    // MARK: - Bounds

    func testEntryBoundIsEnforced() throws {
        let url = try zip(["a.txt": "hello", "sub/b.txt": "nested"])
        var bounds = SystemArchiveReader.Bounds.proposed
        bounds.maxEntries = 1
        guard let failure = refusal(url, bounds: bounds) else { return }
        guard case .tooManyEntries(let count, let limit) = failure else {
            return XCTFail("expected tooManyEntries, got \(failure)")
        }
        XCTAssertEqual(limit, 1)
        XCTAssertGreaterThan(count, 1)
    }

    func testByteBudgetIsEnforced() throws {
        let url = try tar(["a.txt": "hello", "sub/b.txt": "nested"])
        var bounds = SystemArchiveReader.Bounds.proposed
        bounds.maxDecodedBytes = 4
        guard case .byteBudgetExceeded = refusal(url, bounds: bounds) else {
            return XCTFail("expected byteBudgetExceeded")
        }
    }

    /// Boss approval point 3, the measured trap: a ledger limited by the *whole* budget lets an entry
    /// decode a full budget and only the cumulative check afterwards notices. With 2 entries of 2 KiB
    /// each and a 3 KiB budget, the first entry must be refused — inside that entry — rather than the
    /// first being allowed to finish and the second refused later. Without the fix the reported entry
    /// would be `b.txt` (or the failure would not name an entry at all).
    func testOneEntryCannotSpendMoreThanWhatIsLeftOfTheBatchBudget() throws {
        let big = String(repeating: "x", count: 2048)
        let url = try zip(["a.txt": big, "b.txt": big])
        var bounds = SystemArchiveReader.Bounds.proposed
        bounds.maxDecodedBytes = 3072
        guard let failure = refusal(url, bounds: bounds) else { return }
        guard case .byteBudgetExceeded(let limit, let entry) = failure else {
            return XCTFail("expected a per-entry byteBudgetExceeded, got \(failure)")
        }
        XCTAssertEqual(limit, 3072)
        XCTAssertEqual(entry, "a.txt",
                       "the FIRST entry must be refused on its own: a per-entry ledger of the whole "
                       + "budget would let it decode 2048 bytes and blame the second entry instead")
    }

    /// Two entries that fit together must still pass: the remaining-budget arithmetic must not
    /// become "one entry may use at most half".
    func testEntriesThatFitTheRemainingBudgetAreAccepted() throws {
        let payload = String(repeating: "x", count: 1024)
        let url = try zip(["a.txt": payload, "b.txt": payload])
        var bounds = SystemArchiveReader.Bounds.proposed
        bounds.maxDecodedBytes = 4096
        let inspection = try reader.inspect(at: url, bounds: bounds)
        XCTAssertEqual(inspection.decodedBytes, 2048)
    }

    /// The deadline must be consulted **inside** the payload loop, not only between entries: for a
    /// streamed format, inflating payload is how the walk reaches the next header, so one entry can
    /// occupy the whole budget with no header boundary to check at.
    ///
    /// The observable property is the number of clock consultations. A walk that only checks between
    /// entries reads the clock exactly `origin + entries + 1` times (one check per header, plus the
    /// final one that reads EOF). Any check inside the block loop adds at least one more per entry,
    /// so the threshold is `entries + 2`. The clock never expires here — this test is about *where*
    /// the check lives; `testTheDeadlineRefusesWhenTheBudgetRunsOut` pins the refusal itself.
    func testTheDeadlineIsConsultedInsideThePayloadLoop() throws {
        var ticks = 0
        let clock: @Sendable () -> TimeInterval = {
            ticks += 1
            return 0
        }
        let recording = SystemArchiveReader(clock: clock)
        let payload = String(repeating: "x", count: 1024)
        let url = try zip(["a.txt": payload, "b.txt": payload])
        let inspection = try recording.inspect(at: url)
        let entries = inspection.manifest.count
        XCTAssertEqual(entries, 2)
        XCTAssertGreaterThan(ticks, entries + 2,
                             "the clock was only consulted once per header (\(ticks) reads), so the "
                             + "deadline is not checked while payload is drained")
    }

    /// The refusal itself: when the injected clock reports the budget is spent, inspection stops with
    /// `timedOut` rather than returning a manifest it never finished verifying.
    func testTheDeadlineRefusesWhenTheBudgetRunsOut() throws {
        var ticks = 0
        let clock: @Sendable () -> TimeInterval = {
            ticks += 1
            return ticks <= 1 ? 0 : 5
        }
        let recording = SystemArchiveReader(clock: clock)
        let url = try zip(["a.txt": String(repeating: "x", count: 4096)])
        var bounds = SystemArchiveReader.Bounds.proposed
        bounds.maxSeconds = 1
        do {
            _ = try recording.inspect(at: url, bounds: bounds)
            XCTFail("expected timedOut")
        } catch let failure as SystemArchiveReader.Failure {
            guard case .timedOut(let after) = failure else { return XCTFail("got \(failure)") }
            XCTAssertGreaterThanOrEqual(after, 1)
        }
    }

    /// A real, uninjected run must not trip the deadline: this pins that the default clock is
    /// monotonic and starts at inspection, not at process launch.
    func testTheDefaultBoundsDoNotExpireOnAnOrdinaryArchive() throws {
        let url = try zip(["a.txt": "hello"])
        XCTAssertNoThrow(try reader.inspect(at: url, bounds: .proposed))
    }

    /// A zero budget is the explicit "no deadline" used by pure arithmetic tests; it must not be read
    /// as "expired immediately".
    func testAZeroTimeBudgetMeansNoDeadline() throws {
        let url = try zip(["a.txt": "hello"])
        var bounds = SystemArchiveReader.Bounds.proposed
        bounds.maxSeconds = 0
        XCTAssertNoThrow(try reader.inspect(at: url, bounds: bounds))
    }

    // MARK: - Identity

    func testIdentityMatchesTheFileOnDisk() throws {
        // Stage 03B revalidates this before commit, so it must describe the bytes actually read.
        let url = try zip(["a.txt": "hello"])
        let inspection = try reader.inspect(at: url)
        var info = stat()
        XCTAssertEqual(lstat(url.path, &info), 0)
        XCTAssertEqual(inspection.identity.inode, UInt64(info.st_ino))
        XCTAssertEqual(inspection.identity.device, UInt64(info.st_dev))
        XCTAssertEqual(inspection.identity.size, Int64(info.st_size))
        XCTAssertEqual(inspection.identity.size, inspection.archiveBytes)
    }

    func testInspectionWritesNothing() throws {
        // The reader must be side-effect free: same directory listing and no new files afterwards.
        let url = try zip(["a.txt": "hello"])
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        _ = try reader.inspect(at: url)
        let after = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(before, after)
    }

    // MARK: - Pure byte accounting
    //
    // These are separated from `inspect` deliberately: the arithmetic has to be provable without an
    // archive, because the cases that matter (a hole reported as a gap, an overflowing total) cannot
    // all be produced from a real fixture.

    func testLedgerCountsHoleGapsAsOccupiedSpace() throws {
        // Measured: a tar of a 200 MiB hole-only file reports the hole as a gap between blocks, and
        // `archive_read_data` hands over 0 bytes. Counting only block sizes would report 0 for a file
        // the user receives as 200 MiB.
        var ledger = SystemArchiveReader.BlockLedger(limit: .max)
        try ledger.consume(offset: 0, size: 4)                  // "HEAD"
        try ledger.consume(offset: (8 << 20) - 4, size: 4)      // "TAIL" after the hole
        XCTAssertEqual(ledger.logical, 8 << 20,
                       "the 8 MiB hole is real extracted size and must be counted")
    }

    func testLedgerCountsContiguousBlocksAsTheirSum() throws {
        var ledger = SystemArchiveReader.BlockLedger(limit: .max)
        try ledger.consume(offset: 0, size: 10)
        try ledger.consume(offset: 10, size: 5)
        XCTAssertEqual(ledger.logical, 15)
        XCTAssertEqual(ledger.cursor, 15)
    }

    func testLedgerRefusesNegativeExtents() {
        var ledger = SystemArchiveReader.BlockLedger(limit: .max)
        XCTAssertThrowsError(try ledger.consume(offset: -1, size: 4)) { error in
            XCTAssertEqual(error as? SystemArchiveReader.ByteLedgerError, .negativeExtent)
        }
        var other = SystemArchiveReader.BlockLedger(limit: .max)
        XCTAssertThrowsError(try other.consume(offset: 0, size: -4)) { error in
            XCTAssertEqual(error as? SystemArchiveReader.ByteLedgerError, .negativeExtent)
        }
    }

    func testLedgerStopsAtTheBudgetMidEntry() {
        // The budget must bite while a single entry is still being decoded, not only after it, or a
        // bomb gets to finish before anyone looks.
        var ledger = SystemArchiveReader.BlockLedger(limit: 10)
        XCTAssertNoThrow(try ledger.consume(offset: 0, size: 10))
        XCTAssertThrowsError(try ledger.consume(offset: 10, size: 1)) { error in
            XCTAssertEqual(error as? SystemArchiveReader.ByteLedgerError, .budgetExceeded)
        }
    }

    func testLedgerCountsTheHoleTowardTheBudget() throws {
        // A hole is free for the decoder but not for the disk; it must trip the budget too.
        var ledger = SystemArchiveReader.BlockLedger(limit: 1000)
        XCTAssertThrowsError(try ledger.consume(offset: 4096, size: 1)) { error in
            XCTAssertEqual(error as? SystemArchiveReader.ByteLedgerError, .budgetExceeded)
        }
    }

    func testLedgerRefusesOverflowInsteadOfWrapping() {
        // Two separate overflow sites, each with its own case so neither can hide the other:
        // the running total (`logical + size`) and the block end (`offset + size`).
        // Both come from archive metadata, so both are attacker-controlled.

        // (a) total overflows: a second, overlapping block at offset 0 keeps `offset + size` small.
        var total = SystemArchiveReader.BlockLedger(limit: .max)
        XCTAssertNoThrow(try total.consume(offset: 0, size: Int.max))
        XCTAssertThrowsError(try total.consume(offset: 0, size: 1)) { error in
            XCTAssertEqual(error as? SystemArchiveReader.ByteLedgerError, .overflow,
                           "the running total must refuse rather than wrap")
        }

        // (b) block end: proven unreachable today (see `consume`), kept as a trap guard. Asserted only
        // for the property that matters — a maximal extent is refused, never a crash.
        var end = SystemArchiveReader.BlockLedger(limit: .max)
        XCTAssertThrowsError(try end.consume(offset: Int64.max, size: 1)) { error in
            XCTAssertEqual(error as? SystemArchiveReader.ByteLedgerError, .overflow)
        }
    }

    func testDeclaredSizeMustMatchDecodedBytes() {
        XCTAssertNoThrow(try SystemArchiveReader.verifyDeclaredSize(
            path: "a.txt", declared: 5, sizeIsSet: true, decoded: 5))
        XCTAssertThrowsError(try SystemArchiveReader.verifyDeclaredSize(
            path: "a.txt", declared: 5, sizeIsSet: true, decoded: 4)) { error in
            XCTAssertEqual(error as? SystemArchiveReader.Failure,
                           .sizeMismatch("a.txt", declared: 5, decoded: 4))
        }
        // Over-declared and under-declared are equally wrong; neither direction is "safe".
        XCTAssertThrowsError(try SystemArchiveReader.verifyDeclaredSize(
            path: "a.txt", declared: 4, sizeIsSet: true, decoded: 5))
    }

    func testUndeclaredSizeIsNotCompared() {
        // Streamed formats may state no size at all; the rules already refuse those entries, and
        // inventing a comparison here would refuse a legitimate streamed archive.
        XCTAssertNoThrow(try SystemArchiveReader.verifyDeclaredSize(
            path: "stream.bin", declared: 0, sizeIsSet: false, decoded: 4096))
    }
}
