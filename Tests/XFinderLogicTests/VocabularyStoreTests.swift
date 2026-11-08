import XCTest
import Foundation

@MainActor
final class VocabularyStoreTests: XCTestCase {
    private func fixture() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("xf-vocabulary-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return path
    }

    func testConcurrentMutationsAreSerializedWithoutDroppingChanges() async throws {
        let folder = try fixture()
        let store = VocabularyStore(directory: folder)
        await store.load()
        let writes = (0..<20).map { index in
            Task { @MainActor in await store.saveBlueprint(id: "test-\(index)", text: "value-\(index)") }
        }
        for write in writes { let ok = await write.value; XCTAssertTrue(ok) }
        await store.flush()
        XCTAssertFalse(store.isSaving)
        let reload = VocabularyStore(directory: folder)
        await reload.load()
        XCTAssertEqual(reload.library.blueprints.count, 20)
        XCTAssertEqual(reload.library.blueprints["test-19"], "value-19")
    }

    func testSaveReviewAndReloadAreDurable() async throws {
        let folder = try fixture()
        let store = VocabularyStore(directory: folder)
        await store.load()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let card = VocabularyCard(term: "performance", meaning: "hiệu suất", createdAt: now, updatedAt: now)
        let saved = await store.saveCard(card, now: now)
        XCTAssertNotNil(saved)
        let reviewed = await store.reviewCard(id: try XCTUnwrap(saved).id, rating: .good, now: now)
        XCTAssertTrue(reviewed)
        let reloaded = VocabularyStore(directory: folder)
        await reloaded.load()
        XCTAssertEqual(reloaded.library.cards.count, 1)
        XCTAssertEqual(reloaded.library.cards.first?.review.repetition, 1)
        XCTAssertEqual(reloaded.library.cards.first?.meaning, "hiệu suất")
        XCTAssertNil(reloaded.issue)
    }

    func testCorruptPrimaryRecoversBackupWithoutOverwritingTheBadBytes() async throws {
        let folder = try fixture()
        let store = VocabularyStore(directory: folder)
        await store.load()
        let saved = await store.saveCard(VocabularyCard(term: "bilingual", meaning: "song ngữ"))
        XCTAssertNotNil(saved)
        let primary = folder.appendingPathComponent("library.json")
        let broken = Data("broken primary".utf8)
        try broken.write(to: primary)
        let recovered = VocabularyStore(directory: folder)
        await recovered.load()
        XCTAssertTrue(recovered.recoveredBackup)
        XCTAssertFalse(recovered.isReadOnly)
        XCTAssertEqual(recovered.library.cards.first?.term, "bilingual")
        XCTAssertEqual(try Data(contentsOf: primary), broken)
    }

    func testBothCorruptFilesBlockMutationAndPreserveRecoveryFiles() async throws {
        let folder = try fixture()
        let bad = Data("invalid library".utf8)
        let primary = folder.appendingPathComponent("library.json")
        let backup = folder.appendingPathComponent("library.backup.json")
        try bad.write(to: primary)
        try bad.write(to: backup)
        let store = VocabularyStore(directory: folder)
        await store.load()
        XCTAssertTrue(store.isReadOnly)
        let saved = await store.saveCard(VocabularyCard(term: "test", meaning: "thử"))
        XCTAssertNil(saved)
        XCTAssertEqual(try Data(contentsOf: primary), bad)
        XCTAssertEqual(try Data(contentsOf: backup), bad)
    }

    func testFuturePrimaryDoesNotFallBackAndOverwriteNewerData() async throws {
        let folder = try fixture()
        let current = try VocabularyLibrary().encoded()
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        future["schemaVersion"] = 2
        let data = try JSONSerialization.data(withJSONObject: future)
        let primary = folder.appendingPathComponent("library.json")
        try data.write(to: primary)
        try current.write(to: folder.appendingPathComponent("library.backup.json"))
        let store = VocabularyStore(directory: folder)
        await store.load()
        XCTAssertTrue(store.isReadOnly)
        XCTAssertEqual(store.issue, .unsupportedVersion)
        let saved = await store.saveCard(VocabularyCard(term: "new", meaning: "mới"))
        XCTAssertNil(saved)
        XCTAssertEqual(try Data(contentsOf: primary), data)
    }

    func testFailedWriteDoesNotPublishOrReplaceAnExistingFile() async throws {
        let folder = try fixture()
        let blocked = folder.appendingPathComponent("not-a-directory")
        let original = Data("keep this file".utf8)
        try original.write(to: blocked)
        let store = VocabularyStore(directory: blocked)
        await store.load()
        let saved = await store.saveCard(VocabularyCard(term: "test", meaning: "thử"))
        XCTAssertNil(saved)
        XCTAssertTrue(store.library.cards.isEmpty)
        XCTAssertEqual(store.issue, .writeFailed)
        XCTAssertEqual(try Data(contentsOf: blocked), original)
    }

    func testSaveCardWithoutPriorLoadAutoLoadsAndPersists() async throws {
        let folder = try fixture()
        let store = VocabularyStore(directory: folder)
        // Notice: do NOT call await store.load() first.
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let card = VocabularyCard(term: "obstacle", meaning: "chướng ngại vật", createdAt: now, updatedAt: now)
        let saved = await store.saveCard(card, now: now)
        XCTAssertNotNil(saved)
        XCTAssertTrue(store.isLoaded)

        let reloaded = VocabularyStore(directory: folder)
        await reloaded.load()
        XCTAssertEqual(reloaded.library.cards.count, 1)
        XCTAssertEqual(reloaded.library.cards.first?.term, "obstacle")
        XCTAssertEqual(reloaded.library.cards.first?.meaning, "chướng ngại vật")
    }
}
