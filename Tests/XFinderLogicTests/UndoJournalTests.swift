import XCTest
import Foundation

final class UndoJournalTests: XCTestCase {
    private func step(_ kind: UndoStep.Kind = .move, items: [UndoItem] = [UndoItem(from: "/dst/a", to: "/src/a", inode: 1, size: 10, modified: Date(timeIntervalSince1970: 100))],
                       date: Date = Date()) -> UndoStep {
        UndoStep(id: UUID(), kind: kind, items: items, date: date)
    }

    // MARK: record / limit / redo clearing

    func testRecordAppendsToUndoStack() {
        var journal = UndoJournal()
        let s = step()
        journal.record(s, now: Date())
        XCTAssertEqual(journal.undo, [s])
    }

    func testRecordClearsRedoStack() {
        var journal = UndoJournal()
        journal.record(step(), now: Date())
        _ = journal.popUndo()
        XCTAssertFalse(journal.redo.isEmpty)
        journal.record(step(), now: Date())
        XCTAssertTrue(journal.redo.isEmpty, "a fresh action must invalidate any previously-undone redo")
    }

    func testRecordEnforcesTwentyStepLimitByDroppingOldest() {
        var journal = UndoJournal()
        var steps: [UndoStep] = []
        for i in 0..<25 {
            let s = step(date: Date(timeIntervalSince1970: Double(i)))
            steps.append(s)
            journal.record(s, now: Date())
        }
        XCTAssertEqual(journal.undo.count, UndoJournal.limit)
        // The newest 20 survive — the oldest 5 (indices 0..<5) are dropped.
        XCTAssertEqual(journal.undo.map(\.id), steps.suffix(20).map(\.id))
    }

    func testRecordAtExactlyTheLimitKeepsAll() {
        var journal = UndoJournal()
        for i in 0..<UndoJournal.limit {
            journal.record(step(date: Date(timeIntervalSince1970: Double(i))), now: Date())
        }
        XCTAssertEqual(journal.undo.count, UndoJournal.limit)
    }

    // MARK: popUndo / popRedo

    func testPopUndoMovesStepToRedo() {
        var journal = UndoJournal()
        let s = step()
        journal.record(s, now: Date())
        let popped = journal.popUndo()
        XCTAssertEqual(popped, s)
        XCTAssertTrue(journal.undo.isEmpty)
        XCTAssertEqual(journal.redo, [s])
    }

    func testPopUndoOnEmptyStackReturnsNil() {
        var journal = UndoJournal()
        XCTAssertNil(journal.popUndo())
    }

    func testPopRedoMovesStepBackToUndo() {
        var journal = UndoJournal()
        let s = step()
        journal.record(s, now: Date())
        _ = journal.popUndo()
        let redone = journal.popRedo()
        XCTAssertEqual(redone, s)
        XCTAssertEqual(journal.undo, [s])
        XCTAssertTrue(journal.redo.isEmpty)
    }

    func testPopRedoOnEmptyStackReturnsNil() {
        var journal = UndoJournal()
        XCTAssertNil(journal.popRedo())
    }

    // MARK: pruned — 24 h age

    func testPrunedRemovesStepsOlderThanTwentyFourHours() {
        var journal = UndoJournal()
        let now = Date(timeIntervalSince1970: 100_000)
        let old = step(date: now.addingTimeInterval(-UndoJournal.maxAge - 1))
        let recent = step(date: now.addingTimeInterval(-10))
        journal.record(old, now: now)
        journal.record(recent, now: now)
        journal.pruned(now: now)
        XCTAssertEqual(journal.undo, [recent])
    }

    func testPrunedKeepsStepExactlyAtBoundary() {
        var journal = UndoJournal()
        let now = Date(timeIntervalSince1970: 100_000)
        let boundary = step(date: now.addingTimeInterval(-UndoJournal.maxAge))
        journal.record(boundary, now: now)
        journal.pruned(now: now)
        XCTAssertEqual(journal.undo, [boundary], "exactly 24h old is not yet older than 24h")
    }

    func testPrunedAlsoPrunesRedoStack() {
        var journal = UndoJournal()
        let now = Date(timeIntervalSince1970: 100_000)
        let old = step(date: now.addingTimeInterval(-UndoJournal.maxAge - 1))
        journal.record(old, now: now)
        _ = journal.popUndo()
        journal.pruned(now: now)
        XCTAssertTrue(journal.redo.isEmpty)
    }

    // MARK: availability — disk missing

    func testAvailabilityDiskMissingWhenDestinationVolumeUnmounted() {
        let journal = UndoJournal()
        let s = step()
        let result = journal.availability(of: s, exists: { _ in true },
                                           identity: { _ in (inode: 1, size: 10, modified: Date(timeIntervalSince1970: 100)) },
                                           volumeMounted: { path in path != "/dst/a" })
        XCTAssertEqual(result, .diskMissing)
    }

    func testAvailabilityDiskMissingWhenSourceVolumeUnmounted() {
        let journal = UndoJournal()
        let s = step()
        let result = journal.availability(of: s, exists: { _ in true },
                                           identity: { _ in (inode: 1, size: 10, modified: Date(timeIntervalSince1970: 100)) },
                                           volumeMounted: { path in path != "/src/a" })
        XCTAssertEqual(result, .diskMissing)
    }

    // MARK: availability — identity mismatch

    func testAvailabilityUnavailableWhenIdentityChanged() {
        let journal = UndoJournal()
        let s = step()
        let result = journal.availability(of: s, exists: { _ in true },
                                           identity: { _ in (inode: 1, size: 999, modified: Date(timeIntervalSince1970: 100)) },
                                           volumeMounted: { _ in true })
        guard case .unavailable = result else { return XCTFail("expected unavailable, got \(result)") }
    }

    func testAvailabilityUnavailableWhenInodeChanged() {
        let journal = UndoJournal()
        let s = step()
        let result = journal.availability(of: s, exists: { _ in true },
                                           identity: { _ in (inode: 2, size: 10, modified: Date(timeIntervalSince1970: 100)) },
                                           volumeMounted: { _ in true })
        guard case .unavailable = result else { return XCTFail("expected unavailable, got \(result)") }
    }

    func testAvailabilityUnavailableWhenModifiedDateChanged() {
        let journal = UndoJournal()
        let s = step()
        let result = journal.availability(of: s, exists: { _ in true },
                                           identity: { _ in (inode: 1, size: 10, modified: Date(timeIntervalSince1970: 999)) },
                                           volumeMounted: { _ in true })
        guard case .unavailable = result else { return XCTFail("expected unavailable, got \(result)") }
    }

    func testAvailabilityUnavailableWhenItemNoLongerExists() {
        let journal = UndoJournal()
        let s = step()
        let result = journal.availability(of: s, exists: { _ in false },
                                           identity: { _ in nil },
                                           volumeMounted: { _ in true })
        guard case .unavailable = result else { return XCTFail("expected unavailable, got \(result)") }
    }

    func testAvailabilityAvailableWhenIdentityMatchesExactly() {
        let journal = UndoJournal()
        let s = step()
        let result = journal.availability(of: s, exists: { _ in true },
                                           identity: { _ in (inode: 1, size: 10, modified: Date(timeIntervalSince1970: 100)) },
                                           volumeMounted: { _ in true })
        XCTAssertEqual(result, .available)
    }

    func testAvailabilityPassesThroughWhenNoIdentityWasRecorded() {
        // A rename step legitimately has nothing to compare — nil inode/size/modified must not be treated as a
        // mismatch, it must pass through as available (assuming exists() is true).
        let journal = UndoJournal()
        let s = UndoStep(id: UUID(), kind: .rename, items: [UndoItem(from: "/a/old", to: "/a/new", inode: nil, size: nil, modified: nil)], date: Date())
        let result = journal.availability(of: s, exists: { _ in true }, identity: { _ in nil }, volumeMounted: { _ in true })
        XCTAssertEqual(result, .available)
    }

    // MARK: availability — all-or-nothing multi-item

    func testAvailabilityRefusesWholeStepWhenOneOfMultipleItemsFails() {
        let journal = UndoJournal()
        let items = [
            UndoItem(from: "/dst/a", to: "/src/a", inode: 1, size: 10, modified: Date(timeIntervalSince1970: 100)),
            UndoItem(from: "/dst/b", to: "/src/b", inode: 2, size: 20, modified: Date(timeIntervalSince1970: 200)),
        ]
        let s = UndoStep(id: UUID(), kind: .move, items: items, date: Date())
        let result = journal.availability(of: s, exists: { path in path != "/dst/b" },
                                           identity: { path in path == "/dst/a" ? (inode: 1, size: 10, modified: Date(timeIntervalSince1970: 100)) : nil },
                                           volumeMounted: { _ in true })
        guard case .unavailable = result else { return XCTFail("one failing item must refuse the whole step, got \(result)") }
    }

    func testAvailabilityAvailableOnlyWhenEveryItemChecksOut() {
        let journal = UndoJournal()
        let items = [
            UndoItem(from: "/dst/a", to: "/src/a", inode: 1, size: 10, modified: Date(timeIntervalSince1970: 100)),
            UndoItem(from: "/dst/b", to: "/src/b", inode: 2, size: 20, modified: Date(timeIntervalSince1970: 200)),
        ]
        let s = UndoStep(id: UUID(), kind: .move, items: items, date: Date())
        let identities: [String: (inode: UInt64, size: Int64, modified: Date)] = [
            "/dst/a": (inode: 1, size: 10, modified: Date(timeIntervalSince1970: 100)),
            "/dst/b": (inode: 2, size: 20, modified: Date(timeIntervalSince1970: 200)),
        ]
        let result = journal.availability(of: s, exists: { _ in true }, identity: { identities[$0] }, volumeMounted: { _ in true })
        XCTAssertEqual(result, .available)
    }

    func testAvailabilityUnavailableForStepWithNoItems() {
        let journal = UndoJournal()
        let s = UndoStep(id: UUID(), kind: .move, items: [], date: Date())
        let result = journal.availability(of: s, exists: { _ in true }, identity: { _ in nil }, volumeMounted: { _ in true })
        guard case .unavailable = result else { return XCTFail("expected unavailable, got \(result)") }
    }

    // MARK: titleKey

    func testTitleKeyIsDistinctPerKind() {
        let kinds: [UndoStep.Kind] = [.move, .copy, .duplicate, .trash, .rename, .newFolder, .merge, .compress, .infoEdit]
        let keys = kinds.map { UndoStep(id: UUID(), kind: $0, items: [], date: Date()).titleKey }
        XCTAssertEqual(Set(keys).count, kinds.count, "every kind must have its own verb key")
        XCTAssertTrue(keys.allSatisfy { !$0.isEmpty })
    }

    // MARK: encode / decode round trip

    func testEncodedDecodeRoundTrip() {
        var journal = UndoJournal()
        journal.record(step(), now: Date())
        let data = journal.encoded()
        let decoded = UndoJournal.decode(data)
        XCTAssertEqual(decoded, journal)
    }

    func testDecodeNilDataReturnsEmptyJournal() {
        XCTAssertEqual(UndoJournal.decode(nil), UndoJournal())
    }

    func testDecodeGarbageDataReturnsEmptyJournalRatherThanCrashing() {
        let garbage = Data([0xFF, 0x00, 0x12, 0x34])
        XCTAssertEqual(UndoJournal.decode(garbage), UndoJournal())
    }

    /// Review 2026-10-25: after a real move the ORIGINAL place is empty and the item sits at its new place — the step
    /// must be available (it checked the original place and was never available).
    func testAvailabilityAfterARealMoveChecksTheCurrentPlace() {
        let item = UndoItem(from: "/dst/a", to: "/src/a", inode: 7, size: 3, modified: Date(timeIntervalSince1970: 5))
        let s = UndoStep(id: UUID(), kind: .move, items: [item], date: Date())
        let result = UndoJournal().availability(of: s, exists: { $0 == "/dst/a" },
                                                identity: { $0 == "/dst/a" ? (inode: 7, size: 3, modified: Date(timeIntervalSince1970: 5)) : nil },
                                                volumeMounted: { _ in true })
        XCTAssertEqual(result, .available)
    }

    /// Mutant W27-23: in a multi-item step, a missing disk for ANY item (not just the first) is diskMissing.
    func testDiskMissingForASecondItemOnAnotherVolume() {
        let items = [
            UndoItem(from: "/Volumes/A/x", to: "/Users/me/x", inode: 1, size: 1, modified: Date(timeIntervalSince1970: 1)),
            UndoItem(from: "/Volumes/B/y", to: "/Users/me/y", inode: 2, size: 2, modified: Date(timeIntervalSince1970: 2)),
        ]
        let s = UndoStep(id: UUID(), kind: .move, items: items, date: Date())
        let result = UndoJournal().availability(of: s, exists: { _ in true },
                                                identity: { $0 == "/Volumes/A/x" ? (inode: 1, size: 1, modified: Date(timeIntervalSince1970: 1)) : (inode: 2, size: 2, modified: Date(timeIntervalSince1970: 2)) },
                                                volumeMounted: { !$0.hasPrefix("/Volumes/B") })
        XCTAssertEqual(result, .diskMissing)
    }
}
