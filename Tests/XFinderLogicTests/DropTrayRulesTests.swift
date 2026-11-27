import XCTest
import Foundation

final class DropTrayRulesTests: XCTestCase {

    // MARK: - Availability / error reason classification

    func testStatusEvaluatorDistinguishesReadyMovedPermissionDeniedAndTransferFailure() {
        let ready = DropTrayStatusEvaluator.evaluate(exists: true, isReadable: true, accessDenied: false)
        XCTAssertEqual(ready, .ready)
        XCTAssertTrue(ready.isActionable)
        XCTAssertNil(ready.statusKey)

        let moved = DropTrayStatusEvaluator.evaluate(exists: false, isReadable: false, accessDenied: false)
        XCTAssertEqual(moved, .movedOrMissing)
        XCTAssertFalse(moved.isActionable)
        XCTAssertEqual(moved.statusKey, "Đã di chuyển hoặc bị xoá")

        let deniedByStat = DropTrayStatusEvaluator.evaluate(exists: false, isReadable: false, accessDenied: true)
        XCTAssertEqual(deniedByStat, .permissionDenied)
        XCTAssertFalse(deniedByStat.isActionable)
        XCTAssertEqual(deniedByStat.statusKey, "Không có quyền đọc tệp")

        let unreadable = DropTrayStatusEvaluator.evaluate(exists: true, isReadable: false, accessDenied: false)
        XCTAssertEqual(unreadable, .permissionDenied)

        let failed = DropTrayStatusEvaluator.evaluate(exists: true, isReadable: true, accessDenied: false, transferError: "errno 13")
        XCTAssertEqual(failed, .transferFailed("errno 13"))
        XCTAssertTrue(failed.isActionable, "a file whose previous move failed remains actionable so the user can retry")
        XCTAssertEqual(failed.statusKey, "Chuyển thất bại")
        XCTAssertEqual(failed.failureDetail, "errno 13")
    }

    // MARK: - Multi-selection reducer

    func testMultiSelectionSupportsClickCommandShiftArrowsAndPrune() {
        let ids = (0..<4).map { _ in UUID() }
        var sel = DropTraySelection()
        XCTAssertFalse(sel.isMultiSelection)

        sel.click(ids[0], in: ids, command: false, shift: false)
        XCTAssertEqual(sel.selectedIDs, [ids[0]])
        XCTAssertFalse(sel.isMultiSelection)

        // ⌘-click adds a second item ⇒ multi-select bar appears.
        sel.click(ids[2], in: ids, command: true, shift: false)
        XCTAssertEqual(sel.selectedIDs, [ids[0], ids[2]])
        XCTAssertTrue(sel.isMultiSelection)

        // ⇧-click extends from anchor (ids[2]) to ids[3].
        sel.click(ids[3], in: ids, command: false, shift: true)
        XCTAssertEqual(sel.selectedIDs, [ids[2], ids[3]])

        // ⌘A selects all.
        sel.selectAll(ids)
        XCTAssertEqual(sel.count, 4)

        // Arrow without shift collapses to single item; with shift extends.
        sel.clear()
        sel.move(delta: 1, in: ids, extend: false)
        XCTAssertEqual(sel.selectedIDs, [ids[0]])
        sel.move(delta: 1, in: ids, extend: true)
        XCTAssertEqual(sel.selectedIDs, [ids[0], ids[1]])

        // Pruning drops removed IDs cleanly.
        sel.prune(validIDs: [ids[0]])
        XCTAssertEqual(sel.selectedIDs, [ids[0]])
        XCTAssertFalse(sel.isMultiSelection)
    }

    // MARK: - Post-move reconciliation (XF-T41 failure contract)

    func testCopyAlwaysKeepsAllItemsInTrayAndReportsFailures() {
        let paths = ["/tmp/a.txt", "/tmp/b.txt"]
        let out = DropTrayTransferReconciler.reconcile(
            requestedPaths: paths,
            copy: true,
            succeededPaths: ["/tmp/a.txt"],
            skippedPaths: [],
            failedReasons: ["/tmp/b.txt": "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền."],
            cancelled: false
        )
        XCTAssertTrue(out.pathsToRemove.isEmpty, "copy must never remove staged files")
        XCTAssertEqual(out.clearedErrorPaths, ["/tmp/a.txt"])
        XCTAssertEqual(out.failureReasonsByPath.count, 1)
    }

    func testFailedSkippedAndCancelledMovesStayInTrayWhileSucceededMovesLeave() {
        let paths = ["/tmp/ok.txt", "/tmp/fail.txt", "/tmp/skip.txt", "/tmp/stop.txt"]
        let out = DropTrayTransferReconciler.reconcile(
            requestedPaths: paths,
            copy: false,
            succeededPaths: ["/tmp/ok.txt"],
            skippedPaths: ["/tmp/skip.txt"],
            failedReasons: ["/tmp/fail.txt": "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền."],
            cancelled: true
        )
        XCTAssertEqual(out.pathsToRemove, ["/tmp/ok.txt"], "only the succeeded move leaves the tray")
        XCTAssertEqual(out.failureReasonsByPath["/tmp/fail.txt"], "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.")
        XCTAssertEqual(out.failureReasonsByPath["/tmp/skip.txt"], "Đã bỏ qua khi trùng tên")
        XCTAssertEqual(out.failureReasonsByPath["/tmp/stop.txt"], "Đã dừng trước khi chuyển")
    }

    func testEveryStatusAndReconcilerKeyIsTranslatedInL10nStore() throws {
        let store = try L10nFixture.load()
        let keys = [
            DropTrayItemStatus.movedOrMissing.statusKey,
            DropTrayItemStatus.permissionDenied.statusKey,
            DropTrayItemStatus.transferFailed("x").statusKey,
            "Đã bỏ qua khi trùng tên",
            "Đã dừng trước khi chuyển",
            "Không thể chuyển tệp",
        ].compactMap { $0 }

        for key in keys {
            guard let entry = store.entries[key] else {
                XCTFail("Missing L10n entry for Drop Tray key \(key.debugDescription)")
                continue
            }
            XCTAssertFalse(entry.en.isEmpty, "Empty English translation for \(key)")
        }
    }

    // MARK: - Selection-guarded action resolution (Ref-29)

    func testActionResolutionNeverFallsBackToUnselectedItemsWhenSelectionHasZeroActionable() {
        let readyID = UUID()
        let missingID = UUID()
        let deniedID = UUID()
        let items: [DropTrayActionResolution.Entry] = [
            .init(id: readyID, isActionable: true),
            .init(id: missingID, isActionable: false),
            .init(id: deniedID, isActionable: false),
        ]

        // Empty selection targets all actionable items.
        var sel = DropTraySelection()
        let noneRes = DropTrayActionResolution.resolve(items: items, selection: sel)
        XCTAssertFalse(noneRes.hasSelection)
        XCTAssertFalse(noneRes.hasSelectionWithZeroActionable)
        XCTAssertEqual(noneRes.targets.map(\.id), [readyID])

        // Selecting ONLY non-actionable items yields 0 targets and blocks actions instead of falling back to readyID.
        sel.click(missingID, in: items.map(\.id), command: false, shift: false)
        let missingRes = DropTrayActionResolution.resolve(items: items, selection: sel)
        XCTAssertTrue(missingRes.hasSelection)
        XCTAssertTrue(missingRes.hasSelectionWithZeroActionable)
        XCTAssertEqual(missingRes.targets, [])

        // Mixed selection (ready + missing) isolates strictly the selected actionable item(s).
        sel.click(readyID, in: items.map(\.id), command: true, shift: false)
        let mixedRes = DropTrayActionResolution.resolve(items: items, selection: sel)
        XCTAssertTrue(mixedRes.hasSelection)
        XCTAssertFalse(mixedRes.hasSelectionWithZeroActionable)
        XCTAssertEqual(mixedRes.targets.map(\.id), [readyID])
    }

    func testEveryRef29TrayAndNavKeyIsTranslatedInL10nStore() throws {
        let store = try L10nFixture.load()
        let keys = [
            "Thêm mục",
            "Trang chính",
            "Tiện ích mở rộng",
            "Chép",
            "Chuyển",
            "Gửi tới thiết bị gần",
            "Thiết bị gần",
            "Gửi qua macOS",
            "Thả tệp vào đây",
            "Giữ tạm · Kéo ra hoặc gửi sang ngăn",
            "Kéo ra hoặc gửi ngăn",
            "Thao tác khay",
            "Mục chọn không khả dụng",
            "Không khả dụng",
            "Mục đang chọn đã di chuyển hoặc không thể đọc — bỏ chọn hoặc chọn tệp khả dụng.",
            "Chưa có tệp khả dụng",
            "Khay trống — bấm để chọn tệp gửi qua AirDrop",
            "Xử lý hàng loạt",
            "Xử lý",
        ]
        for key in keys {
            guard let entry = store.entries[key] else {
                XCTFail("Missing Ref-29 L10n entry for \(key.debugDescription)")
                continue
            }
            XCTAssertFalse(entry.en.isEmpty, "Empty English translation for \(key)")
        }
    }
}
