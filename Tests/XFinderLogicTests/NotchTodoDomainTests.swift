import XCTest
import os

@MainActor
final class NotchTodoDomainTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xf-notch-todos-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("notch-todos.json")
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - 1. Empty & Long Titles

    func testEmptyAndWhitespaceTitlesAreRejectedOnAddAndEdit() {
        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))

        XCTAssertNil(model.addItem(title: ""))
        XCTAssertNil(model.addItem(title: "   \t\n  "))
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.canSubmitDraft)

        let added = tryUnwrap(model.addItem(title: "  Mua   sữa\n\ttươi  "))
        XCTAssertEqual(added.title, "Mua sữa tươi")
        XCTAssertFalse(model.lastTitleWasTruncated)

        // Inline edit with blank text must not clear or corrupt the existing title.
        model.beginEdit(id: added.id)
        model.editingText = "   \n  "
        XCTAssertFalse(model.commitEdit())
        XCTAssertNil(model.editingItemID)
        XCTAssertEqual(model.items.first?.title, "Mua sữa tươi")
    }

    func testLongTitleIsClampedSafelyToMaxLength() {
        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        let longRaw = String(repeating: "Việc ", count: 60) // 300 chars

        let item = tryUnwrap(model.addItem(title: longRaw))
        XCTAssertLessThanOrEqual(item.title.count, NotchTodoRules.maxTitleLength)
        XCTAssertTrue(model.lastTitleWasTruncated)
        XCTAssertFalse(item.title.hasSuffix(" "))

        // Editing to an overly long title also clamps safely.
        model.beginEdit(id: item.id)
        model.editingText = String(repeating: "ệ", count: NotchTodoRules.maxTitleLength + 40)
        XCTAssertTrue(model.commitEdit())
        XCTAssertEqual(model.items.first?.title.count, NotchTodoRules.maxTitleLength)
        XCTAssertTrue(model.lastTitleWasTruncated)
    }

    // MARK: - 2. Restart Persistence & Tab Hide Independence

    func testPersistenceSurvivesRestartAndTransientEndDoesNotDeleteData() throws {
        let t0 = Date(timeIntervalSince1970: 1_730_000_000)
        let t1 = Date(timeIntervalSince1970: 1_730_000_120)
        var now = t0
        let first = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL), nowProvider: { now })

        let a = tryUnwrap(first.addItem(title: "Gửi báo cáo"))
        now = t1
        let b = tryUnwrap(first.addItem(title: "Kiểm tra PR"))
        XCTAssertTrue(first.toggleCompletion(id: a.id))

        // Simulating hiding the tab / collapsing the notch must keep all persisted items intact.
        first.endTransientState()
        XCTAssertFalse(first.isComposing)
        XCTAssertEqual(first.items.count, 2)

        // Fresh model instance simulating app restart.
        let relaunched = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        XCTAssertNil(relaunched.loadError)
        XCTAssertNil(relaunched.lastWriteError)
        XCTAssertEqual(relaunched.items.count, 2)
        XCTAssertEqual(relaunched.items[0].id, b.id)
        XCTAssertEqual(relaunched.items[0].title, "Kiểm tra PR")
        XCTAssertFalse(relaunched.items[0].isCompleted)
        XCTAssertEqual(relaunched.items[1].id, a.id)
        XCTAssertEqual(relaunched.items[1].title, "Gửi báo cáo")
        XCTAssertTrue(relaunched.items[1].isCompleted)
        XCTAssertEqual(relaunched.items[1].completedAt, t1)
    }

    // MARK: - 3. Editing & Toggling While Filtered

    func testEditingAndTogglingUnderActiveAndDoneFilters() {
        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        let first = tryUnwrap(model.addItem(title: "Việc 1"))
        let second = tryUnwrap(model.addItem(title: "Việc 2"))
        // Order: [second, first]
        XCTAssertEqual(model.filter, .active)
        XCTAssertEqual(model.selectedID, second.id)

        // Marking `second` done removes it from `.active` and advances selection to `first`.
        XCTAssertTrue(model.toggleCompletion(id: second.id))
        XCTAssertEqual(model.visibleItems.map(\.id), [first.id])
        XCTAssertEqual(model.selectedID, first.id)

        // Switch to `.done`: `second` is visible and selected.
        model.setFilter(.done)
        XCTAssertEqual(model.visibleItems.map(\.id), [second.id])
        XCTAssertEqual(model.selectedID, second.id)

        // Editing a done item while in `.done` keeps `isCompleted == true` and stays visible in `.done`.
        model.beginEdit(id: second.id)
        model.editingText = "Việc 2 (đã cập nhật)"
        XCTAssertTrue(model.commitEdit())
        XCTAssertEqual(model.filter, .done)
        XCTAssertEqual(model.visibleItems.first?.title, "Việc 2 (đã cập nhật)")
        XCTAssertEqual(model.visibleItems.first?.isCompleted, true)
        XCTAssertEqual(model.selectedID, second.id)

        // Adding a new task while viewing `.done` switches filter to `.active` and selects the new item.
        let third = tryUnwrap(model.addItem(title: "Việc 3"))
        XCTAssertEqual(model.filter, .active)
        XCTAssertEqual(model.selectedID, third.id)
        XCTAssertEqual(model.visibleItems.map(\.id), [third.id, first.id])

        // Unmarking `second` from `.done` moves it back to `.active` and leaves `.done` empty with `selectedID == nil`.
        model.setFilter(.done)
        XCTAssertTrue(model.toggleCompletion(id: second.id))
        XCTAssertTrue(model.visibleItems.isEmpty)
        XCTAssertNil(model.selectedID)

        model.setFilter(.active)
        XCTAssertEqual(model.activeCount, 3)
        XCTAssertEqual(model.doneCount, 0)
    }

    // MARK: - 4. Delete and Cancel

    func testDeleteConfirmationCancelAndConfirm() {
        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        let a = tryUnwrap(model.addItem(title: "Mục A"))
        let b = tryUnwrap(model.addItem(title: "Mục B"))
        // Visible: [b, a], selected: b

        model.requestDelete(id: b.id)
        XCTAssertEqual(model.pendingDeleteID, b.id)
        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.items.count, 2)

        // Cancel keeps item and selection intact.
        model.cancelDelete()
        XCTAssertNil(model.pendingDeleteID)
        XCTAssertEqual(model.selectedID, b.id)
        XCTAssertEqual(model.items.count, 2)

        // Request again, then confirm removes `b`, persists, and selects `a`.
        model.requestDelete(id: b.id)
        XCTAssertTrue(model.confirmDelete())
        XCTAssertNil(model.pendingDeleteID)
        XCTAssertEqual(model.items.map(\.id), [a.id])
        XCTAssertEqual(model.selectedID, a.id)

        // Verify persisted on disk.
        let reloaded = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        XCTAssertEqual(reloaded.items.map(\.id), [a.id])
    }

    func testSwitchingFilterOrSelectionClearsStalePendingDelete() {
        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        let a = tryUnwrap(model.addItem(title: "Mục A"))
        let b = tryUnwrap(model.addItem(title: "Mục B"))

        model.requestDelete(id: b.id)
        XCTAssertEqual(model.pendingDeleteID, b.id)

        model.select(a.id)
        XCTAssertNil(model.pendingDeleteID)
        XCTAssertEqual(model.selectedID, a.id)

        model.requestDelete(id: a.id)
        model.setFilter(.done)
        XCTAssertNil(model.pendingDeleteID)
    }

    // MARK: - 5. Read & Write Errors (Preserving Unreadable Disk Data)

    func testCorruptedFileOnDiskIsPreservedAndBlocksOverwrite() throws {
        let corruptBytes = Data("{ not valid json at all".utf8)
        try corruptBytes.write(to: fileURL, options: .atomic)

        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        XCTAssertTrue(model.isReadBlocked)
        XCTAssertNotNil(model.loadError)
        XCTAssertTrue(model.items.isEmpty)

        // Mutating attempts must refuse to overwrite the corrupted file.
        XCTAssertNil(model.addItem(title: "Không được ghi đè"))
        XCTAssertEqual(model.lastWriteError, .writeBlockedByUnreadableDisk)
        XCTAssertFalse(model.retrySave())

        // Original corrupted bytes on disk remain byte-for-byte untouched.
        let diskAfter = try Data(contentsOf: fileURL)
        XCTAssertEqual(diskAfter, corruptBytes)

        // Once the file is repaired on disk, reload recovers cleanly.
        let validData = try NotchTodoCodec.encode([NotchTodoItem(title: "Đã khôi phục")])
        try validData.write(to: fileURL, options: .atomic)
        model.reloadFromDisk()
        XCTAssertFalse(model.isReadBlocked)
        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.items.map(\.title), ["Đã khôi phục"])
    }

    func testUnsupportedSchemaVersionPreservesDisk() throws {
        let futureJSON = Data(#"{"schemaVersion":99,"items":[]}"#.utf8)
        try futureJSON.write(to: fileURL, options: .atomic)

        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        XCTAssertEqual(model.loadError, .unsupportedSchemaVersion(99))
        XCTAssertTrue(model.isReadBlocked)
        XCTAssertNil(model.addItem(title: "Test"))
        XCTAssertEqual(try Data(contentsOf: fileURL), futureJSON)
    }

    func testUnreadableFileErrorPreservesDiskAndReportsError() {
        struct FakeReadError: LocalizedError {
            var errorDescription: String? { "permission denied" }
        }
        let store = NotchTodoFileStore(
            fileURL: fileURL,
            readHandler: { _ in throw FakeReadError() }
        )
        let model = NotchTodosModel(store: store)
        XCTAssertTrue(model.isReadBlocked)
        XCTAssertEqual(model.loadError, .unreadableFile(detail: "permission denied"))
    }

    func testWriteErrorIsReportedAndPreviousDiskFileRemainsIntactAndRetryWorks() throws {
        // Seed a valid file on disk first.
        let initial = [NotchTodoItem(title: "Bản cũ trên đĩa")]
        let initialBytes = try NotchTodoCodec.encode(initial)
        try initialBytes.write(to: fileURL, options: .atomic)

        let shouldFail = OSAllocatedUnfairLock(initialState: true)
        struct FakeWriteError: LocalizedError {
            var errorDescription: String? { "disk full" }
        }

        let store = NotchTodoFileStore(
            fileURL: fileURL,
            writeHandler: { data, url in
                if shouldFail.withLock({ $0 }) { throw FakeWriteError() }
                try data.write(to: url, options: .atomic)
            }
        )
        let model = NotchTodosModel(store: store)
        XCTAssertEqual(model.items.map(\.title), ["Bản cũ trên đĩa"])

        _ = model.addItem(title: "Bản mới chưa lưu được")
        XCTAssertEqual(model.lastWriteError, .writeFailed(detail: "disk full"))
        // Disk still has the intact previous valid version.
        XCTAssertEqual(try Data(contentsOf: fileURL), initialBytes)

        // Once disk is writable again, retrySave persists cleanly.
        shouldFail.withLock { $0 = false }
        XCTAssertTrue(model.retrySave())
        XCTAssertNil(model.lastWriteError)

        let reloaded = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        XCTAssertEqual(reloaded.items.map(\.title), ["Bản mới chưa lưu được", "Bản cũ trên đĩa"])
    }

    // MARK: - 6. Legacy Items (Mục cũ)

    func testLegacyArrayAndOlderFieldNamesDecodeCleanly() throws {
        let oldID = UUID()
        let legacyJSON = """
        [
          {
            "id": "\(oldID.uuidString)",
            "title": "  Việc cũ từ bản trước  ",
            "done": true,
            "createdAt": "2025-01-15T08:30:00Z"
          },
          {
            "text": "Mục dùng khóa text cũ",
            "completed": false,
            "extraUnknownField": 42
          },
          {
            "title": "   "
          }
        ]
        """
        try Data(legacyJSON.utf8).write(to: fileURL, options: .atomic)

        let fallback = Date(timeIntervalSince1970: 1_700_000_000)
        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL), nowProvider: { fallback })

        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.items.count, 2)

        XCTAssertEqual(model.items[0].id, oldID)
        XCTAssertEqual(model.items[0].title, "Việc cũ từ bản trước")
        XCTAssertTrue(model.items[0].isCompleted)
        XCTAssertNotNil(model.items[0].completedAt)
        XCTAssertEqual(model.items[0].createdAt.timeIntervalSince1970, 1_736_929_800, accuracy: 1)

        XCTAssertEqual(model.items[1].title, "Mục dùng khóa text cũ")
        XCTAssertFalse(model.items[1].isCompleted)
        XCTAssertNil(model.items[1].completedAt)
        XCTAssertEqual(model.items[1].createdAt, fallback)

        // Saving migrates cleanly to the current versioned envelope.
        XCTAssertTrue(model.retrySave())
        let saved = try Data(contentsOf: fileURL)
        let envelope = try JSONDecoder().decode(NotchTodoEnvelope.self, from: saved)
        XCTAssertEqual(envelope.schemaVersion, NotchTodoEnvelope.currentSchemaVersion)
        XCTAssertEqual(envelope.items.count, 2)
    }

    // MARK: - 7. Keyboard Navigation & Focus Contract

    func testKeyboardNavigationArrowsSpaceReturnDeleteAndEscapeCascade() {
        var panelKeyRequests = 0
        let model = NotchTodosModel(store: NotchTodoFileStore(fileURL: fileURL))
        model.onRequestPanelKey = { panelKeyRequests += 1 }

        let a = tryUnwrap(model.addItem(title: "Việc A"))
        let b = tryUnwrap(model.addItem(title: "Việc B"))
        let c = tryUnwrap(model.addItem(title: "Việc C"))
        // Visible in `.active`: [c, b, a], selected: c

        // Down / Up arrows move selection and clamp at bounds.
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyDownArrow)), .handled)
        XCTAssertEqual(model.selectedID, b.id)
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyDownArrow)), .handled)
        XCTAssertEqual(model.selectedID, a.id)
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyDownArrow)), .handled)
        XCTAssertEqual(model.selectedID, a.id) // clamped at bottom
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyUpArrow)), .handled)
        XCTAssertEqual(model.selectedID, b.id)

        // Space toggles completion when not typing in a text field.
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keySpace)), .handled)
        XCTAssertEqual(model.doneCount, 1)
        XCTAssertEqual(model.activeCount, 2)
        XCTAssertEqual(model.selectedID, a.id)

        // Return enters inline edit and requests panel key focus.
        let prevEditReq = model.focusEditFieldRequest
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyReturn)), .handled)
        XCTAssertEqual(model.editingItemID, a.id)
        XCTAssertTrue(model.isTextInputFocused)
        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.focusEditFieldRequest, prevEditReq + 1)
        XCTAssertGreaterThanOrEqual(panelKeyRequests, 1)

        // While text input is focused, Space and Arrows pass through (.ignored) to the TextField.
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keySpace)), .ignored)
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyDownArrow)), .ignored)

        // Esc cancels inline edit first (does NOT dismiss surface).
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyEscape)), .handled)
        XCTAssertNil(model.editingItemID)
        XCTAssertFalse(model.isTextInputFocused)

        // Delete key opens confirmation; Esc cancels it.
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyDelete)), .handled)
        XCTAssertEqual(model.pendingDeleteID, a.id)
        XCTAssertTrue(model.isComposing)
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyEscape)), .handled)
        XCTAssertNil(model.pendingDeleteID)
        XCTAssertEqual(model.items.count, 3)

        // ⌘⌫ opens confirmation; Return confirms deletion.
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyDelete, command: true)), .handled)
        XCTAssertEqual(model.pendingDeleteID, a.id)
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyReturn)), .handled)
        XCTAssertNil(model.pendingDeleteID)
        XCTAssertEqual(model.items.count, 2)

        // ⌘2 switches to `.done`, ⌘1 switches back to `.active`, Tab toggles.
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.key2, command: true)), .handled)
        XCTAssertEqual(model.filter, .done)
        XCTAssertEqual(model.selectedID, b.id)
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.key1, command: true)), .handled)
        XCTAssertEqual(model.filter, .active)
        XCTAssertEqual(model.selectedID, c.id)
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyTab)), .handled)
        XCTAssertEqual(model.filter, .done)

        // ⌘N focuses add input; Esc clears/blurs add input before dismissing.
        let prevAddReq = model.focusAddFieldRequest
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyN, command: true)), .handled)
        XCTAssertTrue(model.isAddFieldFocused)
        XCTAssertEqual(model.focusAddFieldRequest, prevAddReq + 1)
        model.draftTitle = "Đang gõ dở"
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyEscape)), .handled)
        XCTAssertFalse(model.isAddFieldFocused)
        XCTAssertEqual(model.draftTitle, "")

        // Final Esc on clean state requests surface dismissal.
        XCTAssertEqual(model.handleKeyEvent(.init(keyCode: NotchTodoKeyEvent.keyEscape)), .dismissSurface)
    }

    // MARK: - Helper

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected non-nil value", file: file, line: line)
            fatalError("Unreachable")
        }
        return value
    }
}
