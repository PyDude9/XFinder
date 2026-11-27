import XCTest
import Foundation

final class NotchNotesRulesTests: XCTestCase {

    private func makeNote(
        id: UUID = UUID(),
        title: String? = nil,
        content: String = "",
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        isPinned: Bool = false,
        isArchived: Bool = false
    ) -> NotchNoteSnapshot {
        NotchNoteSnapshot(
            id: id,
            title: title,
            content: content,
            updatedAt: updatedAt,
            isPinned: isPinned,
            isArchived: isArchived
        )
    }

    // MARK: - Empty & archived filtering

    func testEmptyNotesReturnsEmptyAndNoActiveState() {
        let visible = NotchNotesRules.visibleNotes(from: [], query: "")
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(
            NotchNotesRules.emptyState(allNotes: [], visibleNotes: visible, query: ""),
            .noActiveNotes
        )
    }

    func testArchivedNotesAreHiddenAndAllArchivedReportsNoActiveNotes() {
        let archived = makeNote(title: "Cũ", content: "Đã lưu trữ", isPinned: true, isArchived: true)
        let visible = NotchNotesRules.visibleNotes(from: [archived], query: "")
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(
            NotchNotesRules.emptyState(allNotes: [archived], visibleNotes: visible, query: "cu"),
            .noActiveNotes
        )
    }

    // MARK: - Pinned priority & recency sorting

    func testPinnedNotesSortBeforeNewerUnpinnedNotes() {
        let olderPinned = makeNote(
            title: "Ghim cũ",
            updatedAt: Date(timeIntervalSince1970: 100),
            isPinned: true
        )
        let newerPinned = makeNote(
            title: "Ghim mới",
            updatedAt: Date(timeIntervalSince1970: 200),
            isPinned: true
        )
        let newestRegular = makeNote(
            title: "Thường mới nhất",
            updatedAt: Date(timeIntervalSince1970: 500),
            isPinned: false
        )
        let olderRegular = makeNote(
            title: "Thường cũ",
            updatedAt: Date(timeIntervalSince1970: 300),
            isPinned: false
        )

        let visible = NotchNotesRules.visibleNotes(
            from: [olderRegular, newestRegular, olderPinned, newerPinned],
            query: ""
        )

        XCTAssertEqual(visible.map(\.id), [newerPinned.id, olderPinned.id, newestRegular.id, olderRegular.id])
    }

    // MARK: - Vietnamese case- & diacritic-insensitive search

    func testVietnameseDiacriticAndCaseInsensitiveSearchIncludesDWithStroke() {
        let vnNote = makeNote(
            title: "Đơn hàng tháng 11",
            content: "Kiểm tra hóa đơn điện nước và ghi chú đi chợ"
        )
        let otherNote = makeNote(title: "Lịch họp", content: "Thứ Sáu 10h")

        // Matches Đ/đ folded to d, uppercase/lowercase, and stripped tone/vowel marks
        let match1 = NotchNotesRules.visibleNotes(from: [vnNote, otherNote], query: "don hang")
        XCTAssertEqual(match1.map(\.id), [vnNote.id])

        let match2 = NotchNotesRules.visibleNotes(from: [vnNote, otherNote], query: "HOA DON DIEN")
        XCTAssertEqual(match2.map(\.id), [vnNote.id])

        let match3 = NotchNotesRules.visibleNotes(from: [vnNote, otherNote], query: "di cho")
        XCTAssertEqual(match3.map(\.id), [vnNote.id])

        // Multi-token search spanning title + content
        let match4 = NotchNotesRules.visibleNotes(from: [vnNote, otherNote], query: "thang nuoc")
        XCTAssertEqual(match4.map(\.id), [vnNote.id])
    }

    func testNoSearchMatchesReportsNoSearchMatchesWhenActiveNotesExist() {
        let active = makeNote(title: "Ý tưởng", content: "Thiết kế Dynamic Island")
        let visible = NotchNotesRules.visibleNotes(from: [active], query: "khongton")
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(
            NotchNotesRules.emptyState(allNotes: [active], visibleNotes: visible, query: "khongton"),
            .noSearchMatches
        )
    }

    // MARK: - Selection reconciliation after archive, delete, or editor edits

    func testSelectionReconcilesWhenSelectedNoteIsArchivedOrDeleted() {
        let a = makeNote(title: "A", updatedAt: Date(timeIntervalSince1970: 300))
        let b = makeNote(title: "B", updatedAt: Date(timeIntervalSince1970: 200))

        // B was selected, then B is archived externally
        let bArchived = makeNote(id: b.id, title: b.title, updatedAt: b.updatedAt, isArchived: true)
        let afterArchive = NotchNotesRules.visibleNotes(from: [a, bArchived], query: "")
        XCTAssertEqual(
            NotchNotesRules.reconciledSelection(currentSelection: b.id, visibleNotes: afterArchive),
            a.id
        )

        // Last remaining note A is deleted externally -> nil
        let afterDeleteAll = NotchNotesRules.visibleNotes(from: [], query: "")
        XCTAssertNil(
            NotchNotesRules.reconciledSelection(currentSelection: a.id, visibleNotes: afterDeleteAll)
        )
    }

    func testSelectionPreservesNoteIDAfterEditorUpdateAndResort() {
        let a = makeNote(title: "A", updatedAt: Date(timeIntervalSince1970: 300))
        let b = makeNote(title: "B", updatedAt: Date(timeIntervalSince1970: 200))

        // Editor updates B's title and updatedAt so B moves above A
        let bEdited = makeNote(
            id: b.id,
            title: "B (đã sửa)",
            content: "Nội dung mới",
            updatedAt: Date(timeIntervalSince1970: 900)
        )
        let visible = NotchNotesRules.visibleNotes(from: [a, bEdited], query: "")
        XCTAssertEqual(visible.map(\.id), [b.id, a.id])
        XCTAssertEqual(
            NotchNotesRules.reconciledSelection(currentSelection: b.id, visibleNotes: visible),
            b.id
        )
    }

    // MARK: - Keyboard navigation

    func testKeyboardNavigationClampsAtBoundsAndHandlesNilSelection() {
        let a = makeNote(title: "A", updatedAt: Date(timeIntervalSince1970: 300))
        let b = makeNote(title: "B", updatedAt: Date(timeIntervalSince1970: 200))
        let c = makeNote(title: "C", updatedAt: Date(timeIntervalSince1970: 100))
        let list = [a, b, c]

        // From nil: down -> first, up -> last
        XCTAssertEqual(NotchNotesRules.moveSelection(currentSelection: nil, delta: 1, visibleNotes: list), a.id)
        XCTAssertEqual(NotchNotesRules.moveSelection(currentSelection: nil, delta: -1, visibleNotes: list), c.id)

        // Step down and clamp at end
        XCTAssertEqual(NotchNotesRules.moveSelection(currentSelection: a.id, delta: 1, visibleNotes: list), b.id)
        XCTAssertEqual(NotchNotesRules.moveSelection(currentSelection: c.id, delta: 1, visibleNotes: list), c.id)

        // Step up and clamp at start
        XCTAssertEqual(NotchNotesRules.moveSelection(currentSelection: b.id, delta: -1, visibleNotes: list), a.id)
        XCTAssertEqual(NotchNotesRules.moveSelection(currentSelection: a.id, delta: -1, visibleNotes: list), a.id)

        // Empty list always returns nil
        XCTAssertNil(NotchNotesRules.moveSelection(currentSelection: a.id, delta: 1, visibleNotes: []))
    }

    // MARK: - Long text & title/excerpt formatting

    func testLongTitleAndMultilineContentTruncateCleanly() {
        let longTitle = String(repeating: "Ghi chú rất dài ", count: 12)
        let longBody = "   Dòng đầu tiên   có   nhiều   khoảng trắng\n\nDòng hai " + String(repeating: "nội dung ", count: 30)
        let note = makeNote(title: longTitle, content: longBody)

        let title = NotchNotesRules.displayTitle(for: note, maxLength: 40)
        XCTAssertNotNil(title)
        XCTAssertLessThanOrEqual(title?.count ?? 0, 40)
        XCTAssertTrue(title?.hasSuffix("…") == true)

        let excerpt = NotchNotesRules.previewExcerpt(for: note, maxLength: 60)
        XCTAssertFalse(excerpt.contains("\n"))
        XCTAssertFalse(excerpt.contains("  "))
        XCTAssertLessThanOrEqual(excerpt.count, 60)
        XCTAssertTrue(excerpt.hasSuffix("…"))
    }

    func testImplicitTitleFromFirstLineIsNotDuplicatedInExcerpt() {
        let note = makeNote(title: nil, content: "\n  Tiêu đề dòng một  \nDòng hai chi tiết\nDòng ba")
        XCTAssertEqual(NotchNotesRules.displayTitle(for: note), "Tiêu đề dòng một")
        XCTAssertEqual(NotchNotesRules.previewExcerpt(for: note), "Dòng hai chi tiết · Dòng ba")

        let blankNote = makeNote(title: "   ", content: "\n   \t ")
        XCTAssertNil(NotchNotesRules.displayTitle(for: blankNote))
        XCTAssertEqual(NotchNotesRules.previewExcerpt(for: blankNote), "")
    }
}
