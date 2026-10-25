import XCTest
import Foundation

final class ProblemsListTests: XCTestCase {
    private func item(_ path: String, _ reason: ProblemReason, beforeWrite: Bool = true, message: String? = nil) -> ProblemItem {
        ProblemItem(path: path, reason: reason, systemMessage: message, beforeWrite: beforeWrite)
    }

    // MARK: ProblemReason.from(posix:)

    func testPosixEACCESMapsToPermissionDenied() {
        XCTAssertEqual(ProblemReason.from(posix: EACCES), .permissionDenied)
    }

    func testPosixEPERMMapsToPermissionDenied() {
        XCTAssertEqual(ProblemReason.from(posix: EPERM), .permissionDenied)
    }

    func testPosixENOSPCMapsToDiskFull() {
        XCTAssertEqual(ProblemReason.from(posix: ENOSPC), .diskFull)
    }

    func testPosixEBUSYMapsToFileInUse() {
        XCTAssertEqual(ProblemReason.from(posix: EBUSY), .fileInUse)
    }

    func testPosixENOTCONNMapsToDisconnected() {
        XCTAssertEqual(ProblemReason.from(posix: ENOTCONN), .disconnected)
    }

    func testPosixEIOMapsToReadWriteError() {
        XCTAssertEqual(ProblemReason.from(posix: EIO), .readWriteError)
    }

    func testPosixETIMEDOUTMapsToTimeout() {
        XCTAssertEqual(ProblemReason.from(posix: ETIMEDOUT), .timeout)
    }

    func testPosixEROFSMapsToReadOnlyVolume() {
        XCTAssertEqual(ProblemReason.from(posix: EROFS), .readOnlyVolume)
    }

    func testPosixENAMETOOLONGMapsToNameTooLong() {
        XCTAssertEqual(ProblemReason.from(posix: ENAMETOOLONG), .nameTooLong)
    }

    func testPosixENOENTMapsToItemGone() {
        XCTAssertEqual(ProblemReason.from(posix: ENOENT), .itemGone)
    }

    func testUnknownPosixCodeFallsBackToOther() {
        XCTAssertEqual(ProblemReason.from(posix: 999_999), .other)
    }

    // MARK: titleKey

    func testEveryCanonicalReasonHasANonEmptyTitleKeyExceptOther() {
        for reason in ProblemReason.allCases where reason != .other {
            XCTAssertFalse(reason.titleKey.isEmpty, "\(reason) must have a canonical title key")
        }
    }

    func testOtherHasEmptyTitleKeySoCallerFallsBackToSystemMessage() {
        XCTAssertEqual(ProblemReason.other.titleKey, "")
    }

    // MARK: ProblemEntry.canRetry

    func testCanRetryTrueWhenAllItemsPreWriteAndTransient() {
        let entry = ProblemEntry(id: UUID(), operationTitleKey: "Sao chép", finished: Date(),
                                  items: [item("/a", .permissionDenied), item("/b", .diskFull)])
        XCTAssertTrue(entry.canRetry)
    }

    func testCanRetryFalseWhenAnyItemIsPostWrite() {
        let entry = ProblemEntry(id: UUID(), operationTitleKey: "Sao chép", finished: Date(),
                                  items: [item("/a", .permissionDenied, beforeWrite: true), item("/b", .readWriteError, beforeWrite: false)])
        XCTAssertFalse(entry.canRetry)
    }

    func testCanRetryFalseForNonTransientReasonEvenIfPreWrite() {
        let entry = ProblemEntry(id: UUID(), operationTitleKey: "Sao chép", finished: Date(),
                                  items: [item("/a", .nameTooLong, beforeWrite: true)])
        XCTAssertFalse(entry.canRetry)
    }

    func testCanRetryFalseForItemGoneEvenIfPreWrite() {
        let entry = ProblemEntry(id: UUID(), operationTitleKey: "Sao chép", finished: Date(),
                                  items: [item("/a", .itemGone, beforeWrite: true)])
        XCTAssertFalse(entry.canRetry)
    }

    func testCanRetryFalseForOtherReason() {
        let entry = ProblemEntry(id: UUID(), operationTitleKey: "Sao chép", finished: Date(),
                                  items: [item("/a", .other, beforeWrite: true)])
        XCTAssertFalse(entry.canRetry)
    }

    func testCanRetryFalseForEmptyItemsList() {
        let entry = ProblemEntry(id: UUID(), operationTitleKey: "Sao chép", finished: Date(), items: [])
        XCTAssertFalse(entry.canRetry)
    }

    func testCanRetryTrueForEachTransientReasonIndividually() {
        let transient: [ProblemReason] = [.permissionDenied, .diskFull, .fileInUse, .disconnected, .readWriteError, .timeout, .readOnlyVolume]
        for reason in transient {
            let entry = ProblemEntry(id: UUID(), operationTitleKey: "x", finished: Date(), items: [item("/a", reason)])
            XCTAssertTrue(entry.canRetry, "\(reason) should be retryable when pre-write")
        }
    }

    // MARK: ProblemsList mutation

    func testAddInsertsNewestFirst() {
        var list = ProblemsList()
        let first = ProblemEntry(id: UUID(), operationTitleKey: "A", finished: Date(timeIntervalSince1970: 1), items: [])
        let second = ProblemEntry(id: UUID(), operationTitleKey: "B", finished: Date(timeIntervalSince1970: 2), items: [])
        list.add(first)
        list.add(second)
        XCTAssertEqual(list.entries.map(\.operationTitleKey), ["B", "A"])
    }

    func testDismissRemovesOnlyMatchingEntry() {
        var list = ProblemsList()
        let a = ProblemEntry(id: UUID(), operationTitleKey: "A", finished: Date(), items: [])
        let b = ProblemEntry(id: UUID(), operationTitleKey: "B", finished: Date(), items: [])
        list.add(a)
        list.add(b)
        list.dismiss(a.id)
        XCTAssertEqual(list.entries.map(\.id), [b.id])
    }

    func testDismissUnknownIdIsNoOp() {
        var list = ProblemsList()
        let a = ProblemEntry(id: UUID(), operationTitleKey: "A", finished: Date(), items: [])
        list.add(a)
        list.dismiss(UUID())
        XCTAssertEqual(list.entries.count, 1)
    }

    func testClearAllRemovesEverything() {
        var list = ProblemsList()
        list.add(ProblemEntry(id: UUID(), operationTitleKey: "A", finished: Date(), items: []))
        list.add(ProblemEntry(id: UUID(), operationTitleKey: "B", finished: Date(), items: []))
        list.clearAll()
        XCTAssertTrue(list.entries.isEmpty)
    }

    func testDismissAndClearAllNeverTouchFiles() {
        // These mutate only the in-memory struct — the type has no file-system dependency at all, which this test
        // documents by confirming the struct is pure value semantics (Equatable, no side channel).
        var list = ProblemsList()
        let a = ProblemEntry(id: UUID(), operationTitleKey: "A", finished: Date(), items: [item("/tmp/x", .diskFull)])
        list.add(a)
        var copy = list
        copy.dismiss(a.id)
        XCTAssertEqual(list.entries.count, 1, "original list must be unaffected by mutating the copy (value semantics)")
    }
}
