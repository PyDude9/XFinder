import XCTest
import Foundation
import CryptoKit

/// `BoardLock` is pure except for the injected `FileOps`, so most of this suite runs against an
/// in-memory, dictionary-backed fake (fast, deterministic, no cleanup) — the same house style as
/// `ClipExportTests`' `realOps` vs. a fake would be, just inverted: here the DEFAULT is the fake,
/// and exactly one test (`testLockAndUnlockRoundTripAgainstARealTempDirectory`) wires the real
/// filesystem to prove the seam is not hiding a path-construction bug the fake could not see.
///
/// All key material is a software `P256.KeyAgreement.PrivateKey` — `BoardLock.open`/`lock`/`unlock`
/// are generic over `some HPKEDiffieHellmanPrivateKey`, so nothing here ever touches the Secure
/// Enclave or prompts Touch ID.
final class BoardLockTests: XCTestCase {
    typealias X = BoardLock

    // MARK: - In-memory FileOps fake

    /// A dictionary-backed fake filesystem. Class (not struct) so the `ops` closures can share one
    /// mutable backing store across the calls `BoardLock.lock`/`unlock`/`restorePlain` make.
    final class FakeFS {
        var files: [String: Data] = [:]

        var ops: BoardLock.FileOps {
            BoardLock.FileOps(
                read: { path in
                    guard let data = self.files[path] else {
                        throw NSError(domain: "FakeFS", code: 1, userInfo: [NSLocalizedDescriptionKey: "no file at \(path)"])
                    }
                    return data
                },
                write: { data, path in self.files[path] = data },
                remove: { path in
                    guard self.files[path] != nil else {
                        throw NSError(domain: "FakeFS", code: 2, userInfo: [NSLocalizedDescriptionKey: "no file at \(path)"])
                    }
                    self.files.removeValue(forKey: path)
                },
                exists: { path in self.files[path] != nil }
            )
        }
    }

    // MARK: - Helpers

    func makeKeyPair() -> (privateKey: P256.KeyAgreement.PrivateKey, publicKeyX963: Data) {
        let key = P256.KeyAgreement.PrivateKey()
        return (key, key.publicKey.x963Representation)
    }

    func makeRecord(
        id: UUID = UUID(),
        type: ContentType = .text,
        textSnippet: String? = "hello board lock",
        thumbnailPath: String? = nil,
        payloadPath: String? = nil,
        ocrText: String? = nil,
        metadata: [String: String] = [:]
    ) -> ClipboardRecord {
        ClipboardRecord(
            id: id,
            type: type,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceBundleID: "com.example.app",
            sourceAppName: "Example",
            textSnippet: textSnippet,
            thumbnailPath: thumbnailPath,
            payloadPath: payloadPath,
            ocrText: ocrText,
            pinboardID: nil,
            metadata: metadata
        )
    }

    // MARK: - 1. seal/open round trip

    func testSealOpenRoundTripBytesIdenticalAndBlobLengthIsExact() throws {
        let (key, pub) = makeKeyPair()
        let plaintext = Data("the quick brown fox jumps over the lazy dog".utf8)

        let blob = try X.seal(plaintext, publicKeyX963: pub)

        // version(1) + encapsulated key(65) + ciphertext(plaintext + 16-byte AES-GCM tag)
        XCTAssertEqual(blob.count, 1 + 65 + plaintext.count + 16)
        XCTAssertNotEqual(blob, plaintext)
        XCTAssertFalse(blob.dropFirst(66).elementsEqual(plaintext), "ciphertext must not equal plaintext")

        let opened = try X.open(blob, with: key)
        XCTAssertEqual(opened, plaintext)
    }

    func testSealOpenRoundTripOnEmptyData() throws {
        let (key, pub) = makeKeyPair()
        let blob = try X.seal(Data(), publicKeyX963: pub)
        XCTAssertEqual(blob.count, 1 + 65 + 0 + 16)
        let opened = try X.open(blob, with: key)
        XCTAssertEqual(opened, Data())
    }

    // MARK: - 2. wrong key

    func testOpenWithWrongKeyThrowsWrongKey() throws {
        let (_, pub) = makeKeyPair()
        let (wrongKey, _) = makeKeyPair()
        let blob = try X.seal(Data("secret".utf8), publicKeyX963: pub)

        XCTAssertThrowsError(try X.open(blob, with: wrongKey)) { error in
            XCTAssertEqual(error as? BoardLock.Error, .wrongKey)
        }
    }

    // MARK: - 3. truncated / unknown-version blob

    func testOpenWithTruncatedBlobThrowsBadBlob() throws {
        let (key, _) = makeKeyPair()
        XCTAssertThrowsError(try X.open(Data([0x01, 0x02, 0x03]), with: key)) { error in
            XCTAssertEqual(error as? BoardLock.Error, .badBlob)
        }
        XCTAssertThrowsError(try X.open(Data(), with: key)) { error in
            XCTAssertEqual(error as? BoardLock.Error, .badBlob)
        }
    }

    func testOpenWithUnknownVersionByteThrowsBadBlob() throws {
        let (key, pub) = makeKeyPair()
        var blob = try X.seal(Data("hi".utf8), publicKeyX963: pub)
        blob[0] = 0x02 // mutate the version byte to an unknown value
        XCTAssertThrowsError(try X.open(blob, with: key)) { error in
            XCTAssertEqual(error as? BoardLock.Error, .badBlob)
        }
    }

    // MARK: - 4. lock() strips content, keeps flags, writes sealed files, removes plain files

    func testLockRemovesContentKeepsFlagsSetsLockKeysWritesEnvelopeAndRemovesPlainFiles() throws {
        let fs = FakeFS()
        let (_, pub) = makeKeyPair()
        let boardID = UUID()
        let recordID = UUID()
        let lockedDir = "/locked"

        fs.files["/payload/note.txt"] = Data("payload bytes".utf8)
        fs.files["/thumb/note.png"] = Data("thumb bytes".utf8)

        let record = makeRecord(
            id: recordID,
            thumbnailPath: "/thumb/note.png",
            payloadPath: "/payload/note.txt",
            ocrText: "ocr text here",
            metadata: [
                "isPinned": "true",
                "usageCount": "3",
                "isSaved": "true",
                "customTitle": "My secret note",
                "url": "https://example.com/secret",
                "path": "/Users/me/secret.txt",
                "dimensions": "100x200",
            ]
        )

        let locked = try X.lock(record, boardID: boardID, publicKeyX963: pub, lockedDir: lockedDir, ops: fs.ops)

        // content gone from the row
        XCTAssertNil(locked.textSnippet)
        XCTAssertNil(locked.ocrText)
        XCTAssertNil(locked.thumbnailPath)
        XCTAssertNil(locked.metadata["customTitle"])
        XCTAssertNil(locked.metadata["url"])
        XCTAssertNil(locked.metadata["path"])
        XCTAssertNil(locked.metadata["dimensions"])

        // flags + identity fields kept
        XCTAssertEqual(locked.metadata["isPinned"], "true")
        XCTAssertEqual(locked.metadata["usageCount"], "3")
        XCTAssertEqual(locked.metadata["isSaved"], "true")
        XCTAssertEqual(locked.type, record.type)
        XCTAssertEqual(locked.timestamp, record.timestamp)
        XCTAssertEqual(locked.sourceBundleID, record.sourceBundleID)
        XCTAssertEqual(locked.sourceAppName, record.sourceAppName)
        XCTAssertEqual(locked.id, record.id)

        // lock keys set
        XCTAssertEqual(locked.metadata["locked"], "1")
        XCTAssertEqual(locked.metadata["lockedBoard"], boardID.uuidString)
        XCTAssertTrue(locked.isLocked)
        XCTAssertEqual(locked.lockedBoardID, boardID)

        // sealed files written
        XCTAssertEqual(locked.payloadPath, "\(lockedDir)/\(recordID.uuidString).env")
        XCTAssertNotNil(fs.files["\(lockedDir)/\(recordID.uuidString).env"])
        XCTAssertNotNil(fs.files["\(lockedDir)/\(recordID.uuidString).payload"])
        XCTAssertNotNil(fs.files["\(lockedDir)/\(recordID.uuidString).thumb"])

        // plain files removed
        XCTAssertNil(fs.files["/payload/note.txt"])
        XCTAssertNil(fs.files["/thumb/note.png"])
    }

    func testLockWithNoPayloadOrThumbnailWritesOnlyTheEnvelope() throws {
        let fs = FakeFS()
        let (_, pub) = makeKeyPair()
        let recordID = UUID()
        let record = makeRecord(id: recordID, textSnippet: "just text")

        let locked = try X.lock(record, boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)

        XCTAssertNotNil(fs.files["/locked/\(recordID.uuidString).env"])
        XCTAssertNil(fs.files["/locked/\(recordID.uuidString).payload"])
        XCTAssertNil(fs.files["/locked/\(recordID.uuidString).thumb"])
        XCTAssertEqual(locked.payloadPath, "/locked/\(recordID.uuidString).env")
    }

    // MARK: - 5. lock() on an already-locked row

    func testLockOnAlreadyLockedRowThrowsAlreadyLocked() throws {
        let fs = FakeFS()
        let (_, pub) = makeKeyPair()
        let lockedRow = makeRecord(metadata: ["locked": "1", "lockedBoard": UUID().uuidString])

        XCTAssertThrowsError(try X.lock(lockedRow, boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)) { error in
            XCTAssertEqual(error as? BoardLock.Error, .alreadyLocked)
        }
    }

    // MARK: - 6. unlock(lock(r)) restores every field and the bytes

    func testUnlockOfLockedRecordRestoresEveryFieldAndThePayloadAndThumbnailBytes() throws {
        let fs = FakeFS()
        let (key, pub) = makeKeyPair()
        let recordID = UUID()
        let boardID = UUID()
        let payloadBytes = Data("payload bytes here".utf8)
        let thumbBytes = Data("thumb bytes here".utf8)

        fs.files["/payload/note.txt"] = payloadBytes
        fs.files["/thumb/note.png"] = thumbBytes

        let original = makeRecord(
            id: recordID,
            textSnippet: "the original snippet",
            thumbnailPath: "/thumb/note.png",
            payloadPath: "/payload/note.txt",
            ocrText: "the original ocr text",
            metadata: [
                "isPinned": "true",
                "usageCount": "7",
                "customTitle": "Original Title",
                "url": "https://example.com/original",
                "dimensions": "640x480",
            ]
        )

        let locked = try X.lock(original, boardID: boardID, publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)
        let unlocked = try X.unlock(locked, with: key, ops: fs.ops)

        XCTAssertEqual(unlocked.record.textSnippet, original.textSnippet)
        XCTAssertEqual(unlocked.record.ocrText, original.ocrText)
        XCTAssertEqual(unlocked.record.metadata["customTitle"], "Original Title")
        XCTAssertEqual(unlocked.record.metadata["url"], "https://example.com/original")
        XCTAssertEqual(unlocked.record.metadata["dimensions"], "640x480")
        XCTAssertEqual(unlocked.record.metadata["isPinned"], "true")
        XCTAssertEqual(unlocked.record.metadata["usageCount"], "7")
        XCTAssertNil(unlocked.record.metadata["locked"])
        XCTAssertNil(unlocked.record.metadata["lockedBoard"])
        XCTAssertFalse(unlocked.record.isLocked)
        XCTAssertNil(unlocked.record.thumbnailPath)
        XCTAssertNil(unlocked.record.payloadPath)
        XCTAssertEqual(unlocked.record.id, original.id)
        XCTAssertEqual(unlocked.record.type, original.type)
        XCTAssertEqual(unlocked.record.timestamp, original.timestamp)

        XCTAssertEqual(unlocked.payloadData, payloadBytes)
        XCTAssertEqual(unlocked.thumbnailData, thumbBytes)
        XCTAssertEqual(unlocked.originalPayloadFileName, "note.txt")
        XCTAssertEqual(unlocked.originalThumbnailFileName, "note.png")
    }

    func testUnlockOfLockedRecordWithNoFilesRestoresTextOnly() throws {
        let fs = FakeFS()
        let (key, pub) = makeKeyPair()
        let original = makeRecord(textSnippet: "text only clip")

        let locked = try X.lock(original, boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)
        let unlocked = try X.unlock(locked, with: key, ops: fs.ops)

        XCTAssertEqual(unlocked.record.textSnippet, "text only clip")
        XCTAssertNil(unlocked.payloadData)
        XCTAssertNil(unlocked.thumbnailData)
        XCTAssertNil(unlocked.originalPayloadFileName)
        XCTAssertNil(unlocked.originalThumbnailFileName)
    }

    // MARK: - 7. unlock on a plain row

    func testUnlockOnAPlainRowThrowsNotLocked() throws {
        let fs = FakeFS()
        let (key, _) = makeKeyPair()
        let plain = makeRecord()

        XCTAssertThrowsError(try X.unlock(plain, with: key, ops: fs.ops)) { error in
            XCTAssertEqual(error as? BoardLock.Error, .notLocked)
        }
    }

    // MARK: - 8. unlock with a missing envelope

    func testUnlockWithMissingEnvelopeThrowsMissingFile() throws {
        let fs = FakeFS()
        let (key, pub) = makeKeyPair()
        let recordID = UUID()
        let locked = try X.lock(makeRecord(id: recordID), boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)

        fs.files.removeValue(forKey: "/locked/\(recordID.uuidString).env")

        XCTAssertThrowsError(try X.unlock(locked, with: key, ops: fs.ops)) { error in
            XCTAssertEqual(error as? BoardLock.Error, .missingFile("/locked/\(recordID.uuidString).env"))
        }
    }

    // MARK: - 9. restorePlain writes bytes back under original names, returns unlocked row

    func testRestorePlainWritesBytesBackUnderOriginalNamesAndReturnsUnlockedRow() throws {
        let fs = FakeFS()
        let (key, pub) = makeKeyPair()
        let recordID = UUID()
        let boardID = UUID()

        fs.files["/payload/photo.png"] = Data("image bytes".utf8)
        fs.files["/thumb/photo.thumb.png"] = Data("thumb bytes".utf8)

        let original = makeRecord(
            id: recordID,
            type: .image,
            textSnippet: nil,
            thumbnailPath: "/thumb/photo.thumb.png",
            payloadPath: "/payload/photo.png",
            metadata: ["isPinned": "true"]
        )

        let locked = try X.lock(original, boardID: boardID, publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)
        let unlocked = try X.unlock(locked, with: key, ops: fs.ops)
        let restored = try X.restorePlain(unlocked, lockedRecord: locked, plainDir: "/payload", ops: fs.ops)

        XCTAssertEqual(restored.payloadPath, "/payload/photo.png")
        XCTAssertEqual(fs.files["/payload/photo.png"], Data("image bytes".utf8))
        XCTAssertEqual(restored.thumbnailPath, "/payload/photo.thumb.png")
        XCTAssertEqual(fs.files["/payload/photo.thumb.png"], Data("thumb bytes".utf8))

        XCTAssertFalse(restored.isLocked)
        XCTAssertNil(restored.metadata["locked"])
        XCTAssertNil(restored.metadata["lockedBoard"])
        XCTAssertEqual(restored.metadata["isPinned"], "true")

        // sealed files removed
        for path in X.sealedFiles(of: locked) {
            XCTAssertNil(fs.files[path], "sealed file \(path) should have been removed by restorePlain")
        }
    }

    func testRestorePlainOnANonLockedRecordThrowsNotLocked() throws {
        let fs = FakeFS()
        let (key, pub) = makeKeyPair()
        let plain = makeRecord()
        // Build a bogus UnlockedClip directly (restorePlain should refuse before touching it).
        let locked = try X.lock(makeRecord(), boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)
        let unlocked = try X.unlock(locked, with: key, ops: fs.ops)

        XCTAssertThrowsError(try X.restorePlain(unlocked, lockedRecord: plain, plainDir: "/payload", ops: fs.ops)) { error in
            XCTAssertEqual(error as? BoardLock.Error, .notLocked)
        }
    }

    // MARK: - 10. sealedFiles

    func testSealedFilesListsExactlyTheFilesLockWrote() throws {
        let fs = FakeFS()
        let (_, pub) = makeKeyPair()
        let recordID = UUID()

        let textOnly = try X.lock(makeRecord(id: recordID, textSnippet: "x"), boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)
        XCTAssertEqual(Set(X.sealedFiles(of: textOnly)), [
            "/locked/\(recordID.uuidString).env",
            "/locked/\(recordID.uuidString).payload",
            "/locked/\(recordID.uuidString).thumb",
        ])

        // sealedFiles lists candidate paths regardless of whether a payload/thumbnail was actually
        // sealed — callers that need "does this exist" check ops.exists themselves (restorePlain does).
        XCTAssertNil(fs.files["/locked/\(recordID.uuidString).payload"])
    }

    func testSealedFilesOnAPlainRecordIsEmpty() {
        XCTAssertEqual(X.sealedFiles(of: makeRecord()), [])
    }

    // MARK: - 11. fenced

    func testFencedDropsLockedRowsAndKeepsOrderOfTheRest() throws {
        let fs = FakeFS()
        let (_, pub) = makeKeyPair()
        let a = makeRecord(textSnippet: "a")
        let b = try X.lock(makeRecord(textSnippet: "b"), boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)
        let c = makeRecord(textSnippet: "c")
        let d = try X.lock(makeRecord(textSnippet: "d"), boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops)
        let e = makeRecord(textSnippet: "e")

        let result = X.fenced([a, b, c, d, e])

        XCTAssertEqual(result.map(\.id), [a.id, c.id, e.id])
        XCTAssertTrue(result.allSatisfy { !$0.isLocked })
    }

    func testFencedOnAllPlainRecordsReturnsEverything() {
        let records = (0..<3).map { _ in makeRecord() }
        XCTAssertEqual(X.fenced(records).map(\.id), records.map(\.id))
    }

    func testFencedOnAllLockedRecordsReturnsEmpty() throws {
        let fs = FakeFS()
        let (_, pub) = makeKeyPair()
        let records = try (0..<3).map { _ in try X.lock(makeRecord(), boardID: UUID(), publicKeyX963: pub, lockedDir: "/locked", ops: fs.ops) }
        XCTAssertEqual(X.fenced(records), [])
    }

    // MARK: - 12. real temp directory (the one non-fake test)

    func testLockAndUnlockRoundTripAgainstARealTempDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("xf-boardlock-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let lockedDir = root.appendingPathComponent("locked")
        try fm.createDirectory(at: lockedDir, withIntermediateDirectories: true)
        let payloadDir = root.appendingPathComponent("payload")
        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        let realOps = BoardLock.FileOps(
            read: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
            write: { data, path in try data.write(to: URL(fileURLWithPath: path)) },
            remove: { try fm.removeItem(atPath: $0) },
            exists: { fm.fileExists(atPath: $0) }
        )

        let payloadPath = payloadDir.appendingPathComponent("doc.txt")
        try "real file system payload".write(to: payloadPath, atomically: true, encoding: .utf8)

        let (key, pub) = makeKeyPair()
        let recordID = UUID()
        let original = makeRecord(id: recordID, textSnippet: "real fs snippet", payloadPath: payloadPath.path)

        let locked = try X.lock(original, boardID: UUID(), publicKeyX963: pub, lockedDir: lockedDir.path, ops: realOps)
        XCTAssertFalse(fm.fileExists(atPath: payloadPath.path), "plain payload must be removed after lock")
        XCTAssertTrue(fm.fileExists(atPath: lockedDir.appendingPathComponent("\(recordID.uuidString).env").path))
        XCTAssertTrue(fm.fileExists(atPath: lockedDir.appendingPathComponent("\(recordID.uuidString).payload").path))

        let unlocked = try X.unlock(locked, with: key, ops: realOps)
        XCTAssertEqual(unlocked.record.textSnippet, "real fs snippet")
        XCTAssertEqual(unlocked.payloadData, Data("real file system payload".utf8))

        let restored = try X.restorePlain(unlocked, lockedRecord: locked, plainDir: payloadDir.path, ops: realOps)
        XCTAssertTrue(fm.fileExists(atPath: restored.payloadPath!))
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: restored.payloadPath!), encoding: .utf8), "real file system payload")
        XCTAssertFalse(fm.fileExists(atPath: lockedDir.appendingPathComponent("\(recordID.uuidString).env").path), "sealed envelope must be removed after restorePlain")
    }

    // MARK: - Review: a planted envelope cannot steer restorePlain outside plainDir

    func testSafeFileNameRejectsTraversalAbsoluteAndDotNames() {
        XCTAssertEqual(BoardLock.safeFileName("note.txt", fallback: "fb"), "note.txt")
        XCTAssertEqual(BoardLock.safeFileName("../evil", fallback: "fb"), "fb")
        XCTAssertEqual(BoardLock.safeFileName("/etc/passwd", fallback: "fb"), "fb")
        XCTAssertEqual(BoardLock.safeFileName("..", fallback: "fb"), "fb")
        XCTAssertEqual(BoardLock.safeFileName(".", fallback: "fb"), "fb")
        XCTAssertEqual(BoardLock.safeFileName("~/x", fallback: "fb"), "fb")
        XCTAssertEqual(BoardLock.safeFileName("", fallback: "fb"), "fb")
        XCTAssertEqual(BoardLock.safeFileName(nil, fallback: "fb"), "fb")
    }

    func testRestorePlainWithATraversalNameWritesUnderPlainDirWithTheFallbackName() throws {
        let key = P256.KeyAgreement.PrivateKey()
        var files: [String: Data] = [:]
        let ops = BoardLock.FileOps(
            read: { path in guard let d = files[path] else { throw BoardLock.Error.missingFile(path) }; return d },
            write: { data, path in files[path] = data },
            remove: { path in files[path] = nil },
            exists: { path in files[path] != nil })
        let id = UUID()
        let lockedRow = ClipboardRecord(id: id, type: .text, textSnippet: nil, payloadPath: "/locked/\(id.uuidString).env",
                                        metadata: ["locked": "1", "lockedBoard": UUID().uuidString])
        let clip = BoardLock.UnlockedClip(record: ClipboardRecord(id: id, type: .text, textSnippet: "hello"),
                                          payloadData: Data("payload".utf8), thumbnailData: nil,
                                          originalPayloadFileName: "../evil.txt", originalThumbnailFileName: nil)
        let restored = try BoardLock.restorePlain(clip, lockedRecord: lockedRow, plainDir: "/plain", ops: ops)
        XCTAssertEqual(restored.payloadPath, "/plain/\(id.uuidString).bin", "the planted name is ignored; the fallback is used")
        XCTAssertNil(files["/plain/../evil.txt"])
        XCTAssertEqual(files["/plain/\(id.uuidString).bin"], Data("payload".utf8))
    }
}
