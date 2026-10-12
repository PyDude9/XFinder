import XCTest
import Foundation

/// Real `FileManager` I/O against a temp folder — the same shape as `ArchiveRunnerTests` and
/// `ImageEngineTests`. `ClipExport` itself is pure (the only I/O goes through `FileOps`), so this
/// is the one place that wires it to the real filesystem.
final class ClipExportTests: XCTestCase {
    typealias X = ClipExport
    let fm = FileManager.default
    var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("xf-clipexport-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    func url(_ p: String) -> URL { root.appendingPathComponent(p) }

    /// The real filesystem, behind the injectable seam — mirrors how the app wires this at runtime.
    static let realOps = ClipExport.FileOps(
        exists: { FileManager.default.fileExists(atPath: $0) },
        copy: { try FileManager.default.copyItem(atPath: $0, toPath: $1) },
        makeDir: { try FileManager.default.createDirectory(atPath: $0, withIntermediateDirectories: true) },
        write: { try $0.write(to: URL(fileURLWithPath: $1)) },
        read: { try Data(contentsOf: URL(fileURLWithPath: $0)) }
    )

    /// `CodableColor`'s only public initializer takes a SwiftUI `Color`, which this Foundation-only
    /// test target cannot import — so tests build the plain value directly, the same way
    /// `ClipExport`/the manifest JSON round-trip it.
    func makeColor() -> CodableColor { CodableColor(red: 0, green: 0.5, blue: 1, alpha: 1) }

    func makeBoard(name: String, isBuiltIn: Bool = false, itemIDs: [UUID] = []) -> Pinboard {
        Pinboard(name: name, color: makeColor(), itemIDs: itemIDs, isBuiltIn: isBuiltIn)
    }

    // MARK: - 1. Stage: payload + thumbnail + missing file, relative names only

    func testStageCopiesExistingFilesReportsMissingAndRewritesToRelativeNames() throws {
        let payloadsSrc = url("originals"); try fm.createDirectory(at: payloadsSrc, withIntermediateDirectories: true)
        let textPayload = payloadsSrc.appendingPathComponent("note.txt")
        try "hello clipboard".write(to: textPayload, atomically: true, encoding: .utf8)
        let imagePayload = payloadsSrc.appendingPathComponent("shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imagePayload)
        let imageThumb = payloadsSrc.appendingPathComponent("shot.thumb.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00]).write(to: imageThumb)

        let textRecord = ClipboardRecord(type: .text, textSnippet: "hello clipboard", payloadPath: textPayload.path)
        let imageRecord = ClipboardRecord(type: .image, thumbnailPath: imageThumb.path, payloadPath: imagePayload.path)
        let missingRecord = ClipboardRecord(type: .text, textSnippet: "gone", payloadPath: url("does-not-exist.txt").path)

        let staging = url("stage1")
        let result = X.stage(
            records: [textRecord, imageRecord, missingRecord],
            boards: [makeBoard(name: "Board A"), makeBoard(name: "Board B")],
            appVersion: "1.0.0", date: Date(), excludedBundleIDs: [],
            into: staging.path, ops: Self.realOps
        )

        guard case .success(let report) = result else { return XCTFail("expected success") }
        XCTAssertEqual(report.manifest.records.count, 3)
        XCTAssertEqual(report.copiedFiles, 3, "text payload + image payload + image thumbnail")
        XCTAssertEqual(report.missingFiles, 1)
        XCTAssertEqual(report.skippedRecords, 0)

        let payloadsDir = staging.appendingPathComponent("payloads")
        let copied = try fm.contentsOfDirectory(atPath: payloadsDir.path)
        XCTAssertEqual(copied.count, 3)

        // Relative names only — never the user's absolute originals.
        for entry in report.manifest.records {
            if let p = entry.payloadPath { XCTAssertTrue(p.hasPrefix("payloads/"), p) }
            if let t = entry.thumbnailPath { XCTAssertTrue(t.hasPrefix("payloads/"), t) }
        }
        let missingEntry = report.manifest.records.first { $0.textSnippet == "gone" }
        XCTAssertNotNil(missingEntry)
        XCTAssertNil(missingEntry?.payloadPath, "a missing source file leaves the path nil, but the record still exports")

        let manifestData = try Data(contentsOf: staging.appendingPathComponent("manifest.json"))
        let manifestString = String(decoding: manifestData, as: UTF8.self)
        XCTAssertFalse(manifestString.contains("/Users"), "no absolute home-directory path leaked into the manifest")
        XCTAssertFalse(manifestString.contains(root.path), "no absolute temp path leaked into the manifest")
    }

    // MARK: - 2. Excluded bundle IDs are skipped entirely

    func testRecordsFromExcludedBundleIDsAreSkippedAndCounted() throws {
        let secret = ClipboardRecord(type: .text, sourceBundleID: "com.1password.1password", textSnippet: "master password")
        let normal = ClipboardRecord(type: .text, sourceBundleID: "com.apple.Safari", textSnippet: "a url")

        let staging = url("stage2")
        let result = X.stage(
            records: [secret, normal], boards: [], appVersion: "1.0.0", date: Date(),
            excludedBundleIDs: ["com.1password.1password"], into: staging.path, ops: Self.realOps
        )

        guard case .success(let report) = result else { return XCTFail("expected success") }
        XCTAssertEqual(report.manifest.records.count, 1)
        XCTAssertEqual(report.manifest.records.first?.sourceBundleID, "com.apple.Safari")
        XCTAssertEqual(report.skippedRecords, 1)
    }

    // MARK: - 3. Exporting twice produces byte-identical manifests

    func testExportingTwiceProducesIdenticalManifestBytes() throws {
        let records = [
            ClipboardRecord(type: .text, sourceAppName: "Notes", textSnippet: "first"),
            ClipboardRecord(type: .link, textSnippet: "https://example.com", metadata: ["k": "v"]),
        ]
        let boards = [makeBoard(name: "Board A"), makeBoard(name: "Board B", isBuiltIn: true)]
        let date = Date(timeIntervalSince1970: 1_760_000_000)

        let stagingA = url("stageA"); let stagingB = url("stageB")
        guard case .success = X.stage(records: records, boards: boards, appVersion: "2.0.0", date: date,
                                       excludedBundleIDs: [], into: stagingA.path, ops: Self.realOps),
              case .success = X.stage(records: records, boards: boards, appVersion: "2.0.0", date: date,
                                       excludedBundleIDs: [], into: stagingB.path, ops: Self.realOps)
        else { return XCTFail("expected both stages to succeed") }

        let a = try Data(contentsOf: stagingA.appendingPathComponent("manifest.json"))
        let b = try Data(contentsOf: stagingB.appendingPathComponent("manifest.json"))
        XCTAssertEqual(a, b, "same input ⇒ byte-identical manifest (sorted keys, ISO 8601 dates)")
    }

    // MARK: - 4. Plan: new / duplicate records, new / merged boards, built-in skipped

    func testPlanClassifiesRecordsAndBoards() throws {
        let existingID = UUID()
        let newID1 = UUID(); let newID2 = UUID()
        let existingBoardID = UUID()
        let newBoardID = UUID()

        let manifest = X.Manifest(
            version: X.formatVersion, exportedAt: Date(), appVersion: "1.0",
            records: [
                X.RecordEntry(id: existingID, type: .text, timestamp: Date(), sourceBundleID: nil, sourceAppName: nil,
                              textSnippet: "dup", thumbnailPath: nil, payloadPath: nil, ocrText: nil, pinboardID: nil, metadata: [:]),
                X.RecordEntry(id: newID1, type: .text, timestamp: Date(), sourceBundleID: nil, sourceAppName: nil,
                              textSnippet: "new1", thumbnailPath: nil, payloadPath: nil, ocrText: nil, pinboardID: nil, metadata: [:]),
                X.RecordEntry(id: newID2, type: .text, timestamp: Date(), sourceBundleID: nil, sourceAppName: nil,
                              textSnippet: "new2", thumbnailPath: nil, payloadPath: nil, ocrText: nil, pinboardID: nil, metadata: [:]),
            ],
            boards: [
                Pinboard(id: existingBoardID, name: "Existing", color: makeColor(), isBuiltIn: false),
                Pinboard(id: newBoardID, name: "New Board", color: makeColor(), isBuiltIn: false),
                Pinboard(id: UUID(), name: "Clipboard History", color: makeColor(), isBuiltIn: true),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let result = X.plan(manifestData: data, existingIDs: [existingID, existingBoardID])
        guard case .success(let plan) = result else { return XCTFail("expected success") }

        XCTAssertEqual(plan.newRecords.count, 2)
        XCTAssertEqual(Set(plan.newRecords.map(\.id)), [newID1, newID2])
        XCTAssertEqual(plan.duplicates, 1)

        XCTAssertEqual(plan.newBoards.count, 1)
        XCTAssertEqual(plan.newBoards.first?.id, newBoardID)
        XCTAssertEqual(plan.mergedBoards, 2, "one id-collision board + one built-in board")
    }

    // MARK: - 5. Plan rejects garbage and unsupported versions

    func testPlanRejectsGarbageAndFutureVersions() throws {
        let garbage = Data("not a manifest at all".utf8)
        XCTAssertEqual(X.plan(manifestData: garbage, existingIDs: []), .failure(.notAManifest))

        let futureManifest = X.Manifest(version: 99, exportedAt: Date(), appVersion: "9.0", records: [], boards: [])
        let futureEncoder = JSONEncoder()
        futureEncoder.dateEncodingStrategy = .iso8601
        let futureData = try futureEncoder.encode(futureManifest)
        XCTAssertEqual(X.plan(manifestData: futureData, existingIDs: []), .failure(.unsupportedVersion(99)))
    }

    // MARK: - 6. Materialize: fresh naming on collision, nil for a missing image file

    func testMaterializeCopiesUnderAFreshNameWhenTargetExists() throws {
        let unzipped = url("unzipped6"); try fm.createDirectory(at: unzipped.appendingPathComponent("payloads"), withIntermediateDirectories: true)
        let archivedPayload = unzipped.appendingPathComponent("payloads/abc.txt")
        try "archived text".write(to: archivedPayload, atomically: true, encoding: .utf8)

        let payloadDir = url("payloaddir6"); try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        let existing = payloadDir.appendingPathComponent("abc.txt")
        try "already here".write(to: existing, atomically: true, encoding: .utf8)

        let entry = X.RecordEntry(id: UUID(), type: .text, timestamp: Date(), sourceBundleID: nil, sourceAppName: nil,
                                   textSnippet: "archived text", thumbnailPath: nil, payloadPath: "payloads/abc.txt",
                                   ocrText: nil, pinboardID: nil, metadata: [:])

        let record = try X.materialize(entry, from: unzipped.path, payloadDir: payloadDir.path, ops: Self.realOps)
        XCTAssertNotNil(record)
        guard let newPath = record?.payloadPath else { return XCTFail("expected a payload path") }
        XCTAssertNotEqual(newPath, existing.path, "must not overwrite the file that was already there")
        XCTAssertTrue(fm.fileExists(atPath: existing.path), "the pre-existing file must survive untouched")
        XCTAssertTrue(fm.fileExists(atPath: newPath), "the newly materialized file must exist under its fresh name")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: existing.path), encoding: .utf8), "already here")
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: newPath), encoding: .utf8), "archived text")
    }

    func testMaterializeReturnsNilForAnImageWhoseFileIsAbsentFromTheArchive() throws {
        let unzipped = url("unzipped6b"); try fm.createDirectory(at: unzipped, withIntermediateDirectories: true)
        let payloadDir = url("payloaddir6b"); try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        let entry = X.RecordEntry(id: UUID(), type: .image, timestamp: Date(), sourceBundleID: nil, sourceAppName: nil,
                                   textSnippet: nil, thumbnailPath: nil, payloadPath: "payloads/missing.png",
                                   ocrText: nil, pinboardID: nil, metadata: [:])

        let record = try X.materialize(entry, from: unzipped.path, payloadDir: payloadDir.path, ops: Self.realOps)
        XCTAssertNil(record, "an image entry whose archived file is missing must not materialize a card with no bytes")
    }

    // MARK: - 7. suggestedFileName

    func testSuggestedFileNameUsesTheUsersCalendar() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 12
        components.hour = 15; components.minute = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: components)!
        XCTAssertEqual(X.suggestedFileName(for: date), "XFinder Clipboard 2026-10-12.xfinderclip")
    }
}
