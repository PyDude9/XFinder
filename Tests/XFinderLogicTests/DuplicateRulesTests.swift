import Foundation
import XCTest

final class DuplicateRulesTests: XCTestCase {
    private func fixture(_ contents: [String]) throws -> (URL, [DuplicateFile]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var files: [DuplicateFile] = []
        for (index, content) in contents.enumerated() {
            let url = root.appendingPathComponent("file-\(index)")
            try Data(content.utf8).write(to: url)
            files.append(.init(url: url, relativePath: url.lastPathComponent, fingerprint: try DuplicateScanEngine.fingerprint(url)))
        }
        return (root, files)
    }
    func testSizeGroupingHardLinksAndSelections() throws {
        let (root, files) = try fixture(["same", "same", "other"])
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = DuplicateFile(url: root.appendingPathComponent("alias"), relativePath: "alias", fingerprint: files[0].fingerprint)
        XCTAssertEqual(DuplicateRules.sizeCandidates(files + [alias]).map(\.count), [2])
        let groups = [DuplicateGroup(files: Array(files.prefix(2)))]
        XCTAssertNil(DuplicateRules.plan(groups: groups, selected: [], complete: true))
        XCTAssertNil(DuplicateRules.plan(groups: groups, selected: Set(files.prefix(2).map(\.id)), complete: true))
        XCTAssertNil(DuplicateRules.plan(groups: groups, selected: [files[1].id], complete: false))
        let plan = try XCTUnwrap(DuplicateRules.plan(groups: groups, selected: [files[1].id], complete: true))
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].keeper.id, files[0].id)
    }
    func testForcedHashCollisionStillComparesBytes() throws {
        let (root, files) = try fixture(["aaaa", "bbbb"])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(try DuplicateScanEngine.verify(.init(file: files[1], keeper: files[0]), hash: { _ in "forced-equal-hash" }))
    }
    func testChangedFingerprintRefusesReadAndMove() throws {
        let (root, files) = try fixture(["same", "same"])
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("diff".utf8).write(to: files[1].url, options: .atomic)
        let current = try DuplicateScanEngine.fingerprint(files[1].url)
        XCTAssertFalse(DuplicateRules.fingerprintsMatch(current, files[1].fingerprint))
        XCTAssertThrowsError(try DuplicateScanEngine.digest(files[1]))
        var called = false
        let result = DuplicateTrash.execute([.init(file: files[1], keeper: files[0])], selected: [files[1].id], moveToTrash: { _ in called = true })
        XCTAssertFalse(called)
        XCTAssertEqual(result.skipped.count, 1)
    }
    func testCancellationStopsFurtherMovesAndKeeperIsProtected() throws {
        let (root, files) = try fixture(["same", "same", "same"])
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = [DuplicateMove(file: files[1], keeper: files[0]), .init(file: files[2], keeper: files[0])]
        var moved: [URL] = []
        let result = DuplicateTrash.execute(plan, selected: [files[1].id, files[2].id], cancelled: { !moved.isEmpty }, moveToTrash: { moved.append($0) })
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(result.moved.count, 1)
        XCTAssertTrue(result.cancelled)
        let protected = DuplicateTrash.execute(plan, selected: Set(files.map(\.id)), moveToTrash: { _ in XCTFail("selected keeper must block move") })
        XCTAssertTrue(protected.moved.isEmpty)
    }
    func testKeeperChangedAfterFirstMoveBlocksRemaining() throws {
        let (root, files) = try fixture(["same", "same", "same"])
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = [DuplicateMove(file: files[1], keeper: files[0]), .init(file: files[2], keeper: files[0])]
        var count = 0
        let result = DuplicateTrash.execute(plan, selected: [files[1].id, files[2].id], moveToTrash: { _ in
            count += 1
            try Data("diff".utf8).write(to: files[0].url, options: .atomic)
        })
        XCTAssertEqual(count, 1)
        XCTAssertEqual(result.moved.count, 1)
        XCTAssertEqual(result.skipped.count, 1)
    }
    func testStreamingAndEmptyFilesAndCancellation() throws {
        let (root, files) = try fixture([String(repeating: "a", count: DuplicateRules.chunkSize + 15), String(repeating: "a", count: DuplicateRules.chunkSize + 15), "", ""])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try DuplicateScanEngine.digest(files[0]), try DuplicateScanEngine.digest(files[1]))
        XCTAssertTrue(try DuplicateScanEngine.equalBytes(files[0], files[1]))
        XCTAssertTrue(try DuplicateScanEngine.equalBytes(files[2], files[3]))
        XCTAssertEqual(try DuplicateScanEngine.digest(files[2]), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertThrowsError(try DuplicateScanEngine.digest(files[0], cancelled: { true }))
        XCTAssertEqual(DuplicateRules.workers, 4)
        XCTAssertEqual(DuplicateRules.fileLimit, 500_000)
        XCTAssertEqual(DuplicateRules.chunkSize, 1_048_576)
    }
    func testRealScanFindsOnlyIdenticalContent() async throws {
        let (root, _) = try fixture(["same", "same", "diff", "unique-size"])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = await DuplicateScanEngine.scan(root: root) { _ in }
        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].files.count, 2)
    }
    func testTrashFailurePreservesFilesWithoutFallback() throws {
        let (root, files) = try fixture(["same", "same"])
        defer { try? FileManager.default.removeItem(at: root) }
        var attempts = 0
        let outcome = DuplicateTrash.execute([.init(file: files[1], keeper: files[0])], selected: [files[1].id], moveToTrash: { _ in
            attempts += 1
            throw CocoaError(.fileWriteNoPermission)
        })
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(outcome.failed, [files[1].id])
        XCTAssertTrue(outcome.moved.isEmpty)
        XCTAssertEqual(try Data(contentsOf: files[1].url), Data("same".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[0].url.path))
    }
    func testPreflightRejectsEntireChangedGroup() async throws {
        let (root, files) = try fixture(["same", "same", "same"])
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("diff".utf8).write(to: files[2].url, options: .atomic)
        let checked = await DuplicateTrash.prepare([.init(file: files[1], keeper: files[0]), .init(file: files[2], keeper: files[0])])
        XCTAssertTrue(checked.moves.isEmpty)
        XCTAssertEqual(checked.rejected, 2)
        XCTAssertEqual(checked.rejectedPaths.count, 2)
    }
    func testPhysicalScanSkipsLinksAndRejectsLinkedRoot() async throws {
        let (root, files) = try fixture(["same", "same"])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.linkItem(at: files[0].url, to: root.appendingPathComponent("000-keeper"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("symbolic"), withDestinationURL: files[0].url)
        let result = await DuplicateScanEngine.scan(root: root) { _ in }
        XCTAssertEqual(result.scanned, 2)
        XCTAssertEqual(result.groups.first?.files.count, 2)
        XCTAssertTrue(result.groups[0].files.contains { $0.name == "000-keeper" })
        XCTAssertEqual(result.status, .complete)
        let link = root.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let rejected = await DuplicateScanEngine.scan(root: link) { _ in }
        XCTAssertEqual(rejected.status, .failed)
    }


    /// Two identical Finder alias files are skipped (checked only for same-size candidates), while two identical regular
    /// files in the same folder still form a group.
    func testIdenticalAliasFilesAreSkippedButRegularDuplicatesStillGroup() async throws {
        let (root, files) = try fixture(["same", "same"])
        defer { try? FileManager.default.removeItem(at: root) }
        let bookmark = try files[0].url.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: root.appendingPathComponent("alias-a"))
        try URL.writeBookmarkData(bookmark, to: root.appendingPathComponent("alias-b"))
        XCTAssertEqual(try root.appendingPathComponent("alias-a").resourceValues(forKeys: [.isAliasFileKey]).isAliasFile, true)
        let result = await DuplicateScanEngine.scan(root: root) { _ in }
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(Set(result.groups[0].files.map(\.name)), ["file-0", "file-1"])
        XCTAssertEqual(result.skipped, 2)
    }
}
