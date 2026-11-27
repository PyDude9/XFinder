import XCTest
import Foundation

@MainActor
final class NotchScratchpadStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchScratchpadStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    private func draftURL(_ name: String = "scratchpad.txt") -> URL {
        tempDir.appendingPathComponent(name)
    }

    func testFlushPreservesUnreadableDraftWithoutAnEdit() throws {
        let url = draftURL()
        let invalidUTF8 = Data([0xFF, 0xFE])
        try invalidUTF8.write(to: url)

        let store = NotchScratchpadStore(fileURL: url)
        XCTAssertTrue(store.isReadBlocked)
        XCTAssertFalse(store.flush())
        XCTAssertEqual(try Data(contentsOf: url), invalidUTF8)
    }

    func testUnreadableDraftBlocksEditClearFlushAndRecoversAfterReload() throws {
        let url = draftURL()
        let invalidUTF8 = Data([0xFF, 0xFE, 0x00, 0x80])
        try invalidUTF8.write(to: url)

        var writeCount = 0
        let store = NotchScratchpadStore(
            fileURL: url,
            maxCharacters: 200,
            debounceNanoseconds: 0,
            writeData: { data, destination in
                writeCount += 1
                try data.write(to: destination, options: .atomic)
            }
        )

        guard case .readFailed = store.status else {
            return XCTFail("Expected .readFailed, got \(store.status)")
        }
        XCTAssertTrue(store.isReadBlocked)
        XCTAssertFalse(store.canCopy)
        XCTAssertFalse(store.canClear)

        // Attempted edit must NOT overwrite disk or mutate text.
        store.updateText("Không được ghi đè tệp lỗi")
        XCTAssertEqual(store.text, "")
        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), invalidUTF8)

        // Attempted clear must NOT overwrite disk.
        store.requestClear()
        XCTAssertFalse(store.confirmingClear)
        XCTAssertFalse(store.confirmClear())
        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), invalidUTF8)

        // Attempted flush on close/disappear must NOT overwrite disk.
        XCTAssertFalse(store.flush())
        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), invalidUTF8)

        // Repair the file on disk and retry via reload().
        let recoveredText = "Nội dung đã khôi phục"
        try Data(recoveredText.utf8).write(to: url, options: .atomic)
        store.reload()

        XCTAssertFalse(store.isReadBlocked)
        XCTAssertEqual(store.status, .idle)
        XCTAssertEqual(store.text, recoveredText)
        XCTAssertEqual(store.lastSavedText, recoveredText)
        XCTAssertTrue(store.canCopy)
        XCTAssertTrue(store.canClear)

        // Editing works normally after recovery.
        store.updateText("Nội dung đã khôi phục + mới")
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(store.status, .saved)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Nội dung đã khôi phục + mới")
    }

    func testReadIOErrorBlocksWritesUntilReloadSucceeds() throws {
        struct FakeReadError: LocalizedError {
            var errorDescription: String? { "Permission denied" }
        }

        let url = draftURL()
        let original = Data("Dữ liệu gốc".utf8)
        try original.write(to: url)

        var shouldFailRead = true
        var writeCount = 0
        let store = NotchScratchpadStore(
            fileURL: url,
            maxCharacters: 200,
            debounceNanoseconds: 0,
            readData: { target in
                if shouldFailRead { throw FakeReadError() }
                return try Data(contentsOf: target)
            },
            writeData: { data, target in
                writeCount += 1
                try data.write(to: target, options: .atomic)
            }
        )

        XCTAssertEqual(store.status, .readFailed("Permission denied"))
        XCTAssertTrue(store.isReadBlocked)
        store.updateText("Ghi đè khi lỗi đọc")
        XCTAssertFalse(store.flush())
        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), original)

        // Once readable again, reload restores original content.
        shouldFailRead = false
        store.reload()
        XCTAssertFalse(store.isReadBlocked)
        XCTAssertEqual(store.text, "Dữ liệu gốc")
        XCTAssertEqual(store.status, .idle)
    }

    // 1. Nháp trống
    func testEmptyDraftInitialStateAndDisabledActions() {
        let url = draftURL()
        let store = NotchScratchpadStore(fileURL: url, maxCharacters: 100, debounceNanoseconds: 0)

        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(store.text, "")
        XCTAssertEqual(store.lastSavedText, "")
        XCTAssertEqual(store.status, .idle)
        XCTAssertFalse(store.canCopy)
        XCTAssertFalse(store.canClear)
        XCTAssertFalse(store.confirmingClear)

        var copied: String?
        XCTAssertFalse(store.copy { copied = $0; return true })
        XCTAssertNil(copied)

        store.requestClear()
        XCTAssertFalse(store.confirmingClear, "empty draft must not enter clear confirmation")
        XCTAssertFalse(store.confirmClear())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // 2. Tiếng Việt & Unicode round-trip across reopen / restart
    func testVietnameseAndUnicodePersistsAndRestores() throws {
        let url = draftURL()
        let vietnamese = "Bản nháp tiếng Việt: đĐ ăĂ âÂ êÊ ôÔ ơƠ ưƯ — dấu huyền, sắc, hỏi, ngã, nặng.\nDòng hai 🚀"

        let writerStore = NotchScratchpadStore(fileURL: url, maxCharacters: 500, debounceNanoseconds: 0)
        writerStore.updateText(vietnamese)
        XCTAssertEqual(writerStore.status, .saved)
        XCTAssertEqual(writerStore.lastSavedText, vietnamese)

        // Simulate app restart / reopen with a brand-new store instance.
        let reopenedStore = NotchScratchpadStore(fileURL: url, maxCharacters: 500, debounceNanoseconds: 0)
        XCTAssertEqual(reopenedStore.text, vietnamese)
        XCTAssertEqual(reopenedStore.lastSavedText, vietnamese)
        XCTAssertEqual(reopenedStore.status, .idle)
        XCTAssertTrue(reopenedStore.canCopy)
        XCTAssertTrue(reopenedStore.canClear)
    }

    // 3. Nhập nhanh rồi đóng và mở lại (debounced typing + immediate flush)
    func testRapidTypingThenCloseFlushesAndRestores() {
        let url = draftURL()
        // Long debounce (10s) so the timer will NOT fire before close.
        let store = NotchScratchpadStore(
            fileURL: url,
            maxCharacters: 200,
            debounceNanoseconds: 10_000_000_000
        )

        store.updateText("G")
        store.updateText("Gh")
        store.updateText("Ghi nhanh")
        store.updateText("Ghi nhanh trước khi đóng")
        XCTAssertTrue(store.hasPendingSave)
        XCTAssertEqual(store.lastSavedText, "", "debounced write should not have flushed yet")

        // Close / disappear flushes synchronously.
        XCTAssertTrue(store.flush())
        XCTAssertFalse(store.hasPendingSave)
        XCTAssertEqual(store.lastSavedText, "Ghi nhanh trước khi đóng")
        XCTAssertEqual(store.status, .saved)

        // Reopen verifies exact recovery.
        let reopened = NotchScratchpadStore(fileURL: url, maxCharacters: 200, debounceNanoseconds: 0)
        XCTAssertEqual(reopened.text, "Ghi nhanh trước khi đóng")
        XCTAssertEqual(reopened.lastSavedText, "Ghi nhanh trước khi đóng")
    }

    // 4. Nội dung quá dài (over-limit blocks write, notifies, keeps saved copy, recovers when trimmed)
    func testOverLimitPreservesSavedCopyAndRecoversWhenTrimmed() throws {
        let url = draftURL()
        let store = NotchScratchpadStore(fileURL: url, maxCharacters: 10, debounceNanoseconds: 0)

        store.updateText("Hợp lệ 123")
        XCTAssertEqual(store.characterCount, 10)
        XCTAssertEqual(store.status, .saved)
        XCTAssertEqual(store.lastSavedText, "Hợp lệ 123")

        // Exceed limit by 1 character.
        let tooLong = "Hợp lệ 1234"
        store.updateText(tooLong)
        XCTAssertTrue(store.isOverLimit)
        XCTAssertEqual(store.text, tooLong, "editor keeps text so user can trim or copy")
        XCTAssertEqual(store.lastSavedText, "Hợp lệ 123", "previously saved text must be preserved")
        XCTAssertEqual(store.status, .overLimit(count: 11, limit: 10))
        XCTAssertFalse(store.flush(), "flush must refuse to overwrite disk while over limit")

        // Disk still holds the last valid saved copy.
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "Hợp lệ 123")

        // Trimming back within limit resumes saving.
        store.updateText("Ngắn lại")
        XCTAssertFalse(store.isOverLimit)
        XCTAssertEqual(store.status, .saved)
        XCTAssertEqual(store.lastSavedText, "Ngắn lại")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Ngắn lại")
    }

    // 5. Không ghi được (write failure preserves last saved copy and reports error)
    func testWriteFailurePreservesPreviouslySavedCopy() throws {
        struct FakeWriteError: LocalizedError {
            var errorDescription: String? { "Disk full" }
        }

        let url = draftURL()
        var shouldFail = false
        let store = NotchScratchpadStore(
            fileURL: url,
            maxCharacters: 100,
            debounceNanoseconds: 0,
            writeData: { data, destination in
                if shouldFail { throw FakeWriteError() }
                try data.write(to: destination, options: .atomic)
            }
        )

        store.updateText("Bản đã lưu")
        XCTAssertEqual(store.status, .saved)
        XCTAssertEqual(store.lastSavedText, "Bản đã lưu")

        // Next write fails.
        shouldFail = true
        store.updateText("Bản mới lỗi ghi")
        XCTAssertEqual(store.status, .saveFailed("Disk full"))
        XCTAssertEqual(store.lastSavedText, "Bản đã lưu", "lastSavedText must remain unchanged on write failure")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Bản đã lưu", "file on disk must remain intact")

        // Reopening loads the intact previously saved copy.
        let reopened = NotchScratchpadStore(fileURL: url, maxCharacters: 100, debounceNanoseconds: 0)
        XCTAssertEqual(reopened.text, "Bản đã lưu")

        // Once disk is writable again, flush persists the pending edit.
        shouldFail = false
        XCTAssertTrue(store.flush())
        XCTAssertEqual(store.status, .saved)
        XCTAssertEqual(store.lastSavedText, "Bản mới lỗi ghi")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Bản mới lỗi ghi")
    }

    // 6. Hủy xóa và xác nhận xóa (clear confirmation flow)
    func testCancelClearPreservesDraftAndConfirmClearDeletesIt() throws {
        let url = draftURL()
        let store = NotchScratchpadStore(fileURL: url, maxCharacters: 100, debounceNanoseconds: 0)
        store.updateText("Nội dung cần giữ")

        // Confirm without requesting first is a no-op.
        XCTAssertFalse(store.confirmClear())
        XCTAssertEqual(store.text, "Nội dung cần giữ")

        // Request clear then cancel.
        store.requestClear()
        XCTAssertTrue(store.confirmingClear)
        store.cancelClear()
        XCTAssertFalse(store.confirmingClear)
        XCTAssertEqual(store.text, "Nội dung cần giữ")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Nội dung cần giữ")

        // Request clear then confirm.
        store.requestClear()
        XCTAssertTrue(store.confirmingClear)
        XCTAssertTrue(store.confirmClear())
        XCTAssertFalse(store.confirmingClear)
        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(store.lastSavedText, "")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "")

        // Reopen stays empty.
        let reopened = NotchScratchpadStore(fileURL: url, maxCharacters: 100, debounceNanoseconds: 0)
        XCTAssertTrue(reopened.isEmpty)
    }

    // 7. Hủy xác nhận khi sửa tiếp và không xóa mất bản lưu nếu clear ghi lỗi
    func testClearWriteFailurePreservesDraftAndSavedCopy() throws {
        struct FakeWriteError: LocalizedError {
            var errorDescription: String? { "Read-only volume" }
        }

        let url = draftURL()
        var failWrite = false
        let store = NotchScratchpadStore(
            fileURL: url,
            maxCharacters: 100,
            debounceNanoseconds: 0,
            writeData: { data, destination in
                if failWrite { throw FakeWriteError() }
                try data.write(to: destination, options: .atomic)
            }
        )
        store.updateText("Giữ nguyên nếu xóa lỗi")

        failWrite = true
        store.requestClear()
        XCTAssertFalse(store.confirmClear())
        XCTAssertEqual(store.status, .saveFailed("Read-only volume"))
        XCTAssertEqual(store.text, "Giữ nguyên nếu xóa lỗi")
        XCTAssertEqual(store.lastSavedText, "Giữ nguyên nếu xóa lỗi")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Giữ nguyên nếu xóa lỗi")
    }

    // 8. Sao chép (writes exact text, does not mutate draft, works even when over limit)
    func testCopyWritesExactDraftWithoutMutatingStore() {
        let url = draftURL()
        let store = NotchScratchpadStore(fileURL: url, maxCharacters: 20, debounceNanoseconds: 0)
        store.updateText("Sao chép tiếng Việt")

        var copiedPayload: String?
        let ok = store.copy { text in
            copiedPayload = text
            return true
        }
        XCTAssertTrue(ok)
        XCTAssertEqual(copiedPayload, "Sao chép tiếng Việt")
        XCTAssertEqual(store.text, "Sao chép tiếng Việt")
    }
}
