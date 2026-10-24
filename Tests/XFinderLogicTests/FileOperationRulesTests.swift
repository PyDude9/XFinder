import XCTest
import Foundation

final class FileOperationRulesTests: XCTestCase {
    // MARK: keepBothName

    func testKeepBothNameFirstCollisionIsNumber2() {
        XCTAssertEqual(FileOperationRules.keepBothName(for: "Report.pdf", existing: ["Report.pdf"]), "Report 2.pdf")
    }

    func testKeepBothNameSkipsTakenNumbersInOrder() {
        let existing: Set<String> = ["Report.pdf", "Report 2.pdf"]
        XCTAssertEqual(FileOperationRules.keepBothName(for: "Report.pdf", existing: existing), "Report 3.pdf")
    }

    func testKeepBothNameNeverProducesDoubleNumber() {
        // "Report 2.pdf" already exists — the next try must be "Report 3.pdf", never "Report 2 2.pdf".
        let existing: Set<String> = ["Report.pdf", "Report 2.pdf"]
        let result = FileOperationRules.keepBothName(for: "Report.pdf", existing: existing)
        XCTAssertFalse(result.contains("2 2"))
        XCTAssertEqual(result, "Report 3.pdf")
    }

    func testKeepBothNameNoExtensionFolder() {
        XCTAssertEqual(FileOperationRules.keepBothName(for: "Folder", existing: ["Folder"]), "Folder 2")
    }

    func testKeepBothNameDotfileHasNoExtension() {
        XCTAssertEqual(FileOperationRules.keepBothName(for: ".zshrc", existing: [".zshrc"]), ".zshrc 2")
    }

    func testKeepBothNameOnlyLastExtensionCounts() {
        XCTAssertEqual(FileOperationRules.keepBothName(for: "a.tar.gz", existing: ["a.tar.gz"]), "a.tar 2.gz")
    }

    func testKeepBothNameEmptyExistingStillStartsAtTwo() {
        // Keep Both is only invoked when a conflict already exists, so the bare name is implicitly taken.
        XCTAssertEqual(FileOperationRules.keepBothName(for: "x.txt", existing: []), "x 2.txt")
    }

    // MARK: duplicateName

    func testDuplicateNameFirstTryHasNoNumber() {
        XCTAssertEqual(FileOperationRules.duplicateName(for: "Report.pdf", existing: ["Report.pdf"]), "Report copy.pdf")
    }

    func testDuplicateNameSecondTryIsNumbered() {
        let existing: Set<String> = ["Report.pdf", "Report copy.pdf"]
        XCTAssertEqual(FileOperationRules.duplicateName(for: "Report.pdf", existing: existing), "Report copy 2.pdf")
    }

    func testDuplicateNameOfAlreadyDuplicatedNameKeepsCounting() {
        // "Report copy.pdf" duplicated again must become "Report copy 2.pdf", not "Report copy copy.pdf".
        let existing: Set<String> = ["Report copy.pdf"]
        let result = FileOperationRules.duplicateName(for: "Report copy.pdf", existing: existing)
        XCTAssertEqual(result, "Report copy 2.pdf")
        XCTAssertFalse(result.contains("copy copy"))
    }

    func testDuplicateNameOfBareCopyWord() {
        XCTAssertEqual(FileOperationRules.duplicateName(for: "copy", existing: ["copy"]), "copy 2")
    }

    func testDuplicateNameNoExtension() {
        XCTAssertEqual(FileOperationRules.duplicateName(for: "Folder", existing: ["Folder"]), "Folder copy")
    }

    // MARK: duplicateName — bug found in adversarial review: duplicating an ALREADY-NUMBERED duplicate must keep
    // counting forward ("Report copy 2" -> "Report copy 3"), not stack a second "copy" token onto it. The first
    // implementation only special-cased the bare "<stem> copy" form, so "Report copy 2.pdf" duplicated became
    // "Report copy 2 copy.pdf" — a real Finder behaviour mismatch (Finder never produces a double "copy").

    func testDuplicateNameOfNumberedDuplicateContinuesCounting() {
        let result = FileOperationRules.duplicateName(for: "Report copy 2.pdf", existing: ["Report copy 2.pdf"])
        XCTAssertEqual(result, "Report copy 3.pdf")
        XCTAssertFalse(result.contains("copy 2 copy"))
    }

    func testDuplicateNameOfNumberedDuplicateWithTwoDigitNumber() {
        XCTAssertEqual(
            FileOperationRules.duplicateName(for: "Report copy 10.pdf", existing: ["Report copy 10.pdf"]),
            "Report copy 11.pdf"
        )
    }

    func testDuplicateNameOfNumberedDuplicateSkipsAlreadyTakenNumbers() {
        let existing: Set<String> = ["Report copy 2.pdf", "Report copy 3.pdf"]
        XCTAssertEqual(FileOperationRules.duplicateName(for: "Report copy 2.pdf", existing: existing), "Report copy 4.pdf")
    }

    func testDuplicateNameOfNumberedDuplicateDoesNotFallBackToBareName() {
        // Even though the bare "Report copy.pdf" is free, Finder never regresses a numbered duplicate back to the
        // bare form — it only ever counts forward from the number already in the name.
        let result = FileOperationRules.duplicateName(for: "Report copy 2.pdf", existing: ["Report copy 2.pdf"])
        XCTAssertNotEqual(result, "Report copy.pdf")
        XCTAssertEqual(result, "Report copy 3.pdf")
    }

    func testDuplicateNameNumberThatLooksLikeAYearStillIncrements() {
        // "Q4 copy 2020" must be read as stem "Q4", suffix "copy", number 2020 — not misparsed as a literal word.
        XCTAssertEqual(
            FileOperationRules.duplicateName(for: "Q4 copy 2020.pdf", existing: ["Q4 copy 2020.pdf"]),
            "Q4 copy 2021.pdf"
        )
    }

    func testDuplicateNameUnrelatedNameEndingInCopyWordIsStillHandled() {
        // "My copy.pdf" is not itself a generated duplicate of anything else in this call, but it still matches the
        // bare "<stem> copy" shape, so the normal (non-numbered) suffix path applies.
        XCTAssertEqual(FileOperationRules.duplicateName(for: "My copy.pdf", existing: ["My copy.pdf"]), "My copy 2.pdf")
    }

    // MARK: isInside

    func testIsInsideTrueForDirectChild() {
        XCTAssertTrue(FileOperationRules.isInside("/a/b/c", ancestor: "/a/b"))
    }

    func testIsInsideFalseForPrefixThatIsNotAnAncestor() {
        // "/a/bc" must not be considered inside "/a/b" just because the string "/a/b" is a prefix.
        XCTAssertFalse(FileOperationRules.isInside("/a/bc", ancestor: "/a/b"))
    }

    func testIsInsideFalseForEqualPaths() {
        XCTAssertFalse(FileOperationRules.isInside("/a/b", ancestor: "/a/b"))
    }

    func testIsInsideFalseForAncestorDeeperThanPath() {
        XCTAssertFalse(FileOperationRules.isInside("/a", ancestor: "/a/b"))
    }

    func testIsInsideTrueForDeeplyNestedPath() {
        XCTAssertTrue(FileOperationRules.isInside("/a/b/c/d/e", ancestor: "/a/b"))
    }

    // MARK: nestingViolation

    func testNestingViolationWhenDestinationEqualsSource() {
        let violation = FileOperationRules.nestingViolation(sources: ["/a/Folder"], destination: "/a/Folder")
        XCTAssertEqual(violation, "/a/Folder")
    }

    func testNestingViolationWhenDestinationIsInsideSource() {
        let violation = FileOperationRules.nestingViolation(sources: ["/a/Folder"], destination: "/a/Folder/sub")
        XCTAssertEqual(violation, "/a/Folder")
    }

    func testNestingViolationNoneWhenDestinationIsUnrelated() {
        XCTAssertNil(FileOperationRules.nestingViolation(sources: ["/a/Folder"], destination: "/b/Other"))
    }

    func testNestingViolationFindsFirstOffendingSourceAmongMany() {
        let violation = FileOperationRules.nestingViolation(
            sources: ["/x/one", "/a/Folder", "/x/two"],
            destination: "/a/Folder/sub"
        )
        XCTAssertEqual(violation, "/a/Folder")
    }

    func testNestingViolationSiblingFolderIsNotAViolation() {
        // "/a/bc" is not inside "/a/b" — copying "/a/b" into "/a/bc" must be allowed.
        XCTAssertNil(FileOperationRules.nestingViolation(sources: ["/a/b"], destination: "/a/bc"))
    }

    // MARK: strategy

    func testStrategyTrashIsAlwaysTrash() {
        XCTAssertEqual(FileOperationRules.strategy(kind: .trash, sameVolume: true), .trash)
        XCTAssertEqual(FileOperationRules.strategy(kind: .trash, sameVolume: false), .trash)
    }

    func testStrategyDuplicateIsAlwaysCloneOrCopy() {
        XCTAssertEqual(FileOperationRules.strategy(kind: .duplicate, sameVolume: true), .cloneOrCopy)
        XCTAssertEqual(FileOperationRules.strategy(kind: .duplicate, sameVolume: false), .cloneOrCopy)
    }

    func testStrategyCopyIsAlwaysCloneOrCopy() {
        XCTAssertEqual(FileOperationRules.strategy(kind: .copy, sameVolume: true), .cloneOrCopy)
        XCTAssertEqual(FileOperationRules.strategy(kind: .copy, sameVolume: false), .cloneOrCopy)
    }

    func testStrategyMoveSameVolumeIsRename() {
        XCTAssertEqual(FileOperationRules.strategy(kind: .move, sameVolume: true), .rename)
    }

    func testStrategyMoveCrossVolumeIsCopyVerifyTrash() {
        XCTAssertEqual(FileOperationRules.strategy(kind: .move, sameVolume: false), .copyVerifyTrash)
    }

    // MARK: isNewer

    func testIsNewerTrueAtOrAboveOneSecond() {
        let a = Date(timeIntervalSince1970: 1000)
        let b = Date(timeIntervalSince1970: 998.9)
        XCTAssertTrue(FileOperationRules.isNewer(a, than: b, coarseTimestamps: false))
    }

    func testIsNewerFalseBelowOneSecond() {
        let a = Date(timeIntervalSince1970: 1000)
        let b = Date(timeIntervalSince1970: 999.5)
        XCTAssertFalse(FileOperationRules.isNewer(a, than: b, coarseTimestamps: false))
    }

    func testIsNewerTrueAtExactlyOneSecondBoundary() {
        // The rule is "at least" the tolerance, so an exact 1.0s gap must already count as newer.
        let a = Date(timeIntervalSince1970: 1000)
        let b = Date(timeIntervalSince1970: 999)
        XCTAssertTrue(FileOperationRules.isNewer(a, than: b, coarseTimestamps: false))
    }

    func testIsNewerTrueAtExactlyTwoSecondCoarseBoundary() {
        let a = Date(timeIntervalSince1970: 1000)
        let b = Date(timeIntervalSince1970: 998)
        XCTAssertTrue(FileOperationRules.isNewer(a, than: b, coarseTimestamps: true))
    }

    func testIsNewerCoarseRequiresTwoSeconds() {
        let a = Date(timeIntervalSince1970: 1000)
        let b = Date(timeIntervalSince1970: 998.5)
        // 1.5s gap: not newer under FAT/exFAT's 2s resolution, but would be newer under the 1s default.
        XCTAssertFalse(FileOperationRules.isNewer(a, than: b, coarseTimestamps: true))
        XCTAssertTrue(FileOperationRules.isNewer(a, than: b, coarseTimestamps: false))
    }

    func testIsNewerFalseWhenOlder() {
        let a = Date(timeIntervalSince1970: 1000)
        let b = Date(timeIntervalSince1970: 1002)
        XCTAssertFalse(FileOperationRules.isNewer(a, than: b, coarseTimestamps: false))
    }

    // MARK: replaceAllowed

    func testReplaceAllowedFileToFile() {
        XCTAssertTrue(FileOperationRules.replaceAllowed(sourceIsFolder: false, destinationIsFolder: false))
    }

    func testReplaceNotAllowedFolderToFile() {
        XCTAssertFalse(FileOperationRules.replaceAllowed(sourceIsFolder: true, destinationIsFolder: false))
    }

    func testReplaceNotAllowedFileToFolder() {
        XCTAssertFalse(FileOperationRules.replaceAllowed(sourceIsFolder: false, destinationIsFolder: true))
    }

    func testReplaceNotAllowedFolderToFolder() {
        XCTAssertFalse(FileOperationRules.replaceAllowed(sourceIsFolder: true, destinationIsFolder: true))
    }

    // MARK: canPause

    func testCanPauseOnlyWhileRunning() {
        XCTAssertTrue(FileOperationRules.canPause(.running))
        for state: JobState in [.waiting, .pausing, .paused, .verifying, .finishing, .done, .failed, .cancelled] {
            XCTAssertFalse(FileOperationRules.canPause(state), "\(state) must not allow pause")
        }
    }

    // MARK: smoothedSpeed

    func testSmoothedSpeedFirstSampleIsUsedAsIs() {
        XCTAssertEqual(FileOperationRules.smoothedSpeed(previous: nil, sample: 500), 500)
    }

    func testSmoothedSpeedAppliesEMA() {
        // alpha 0.2: 0.2*1000 + 0.8*500 = 600
        XCTAssertEqual(FileOperationRules.smoothedSpeed(previous: 500, sample: 1000), 600, accuracy: 0.0001)
    }

    func testSmoothedSpeedConvergesTowardSteadySample() {
        var speed: Double? = nil
        for _ in 0..<200 {
            speed = FileOperationRules.smoothedSpeed(previous: speed, sample: 1000)
        }
        XCTAssertEqual(speed ?? -1, 1000, accuracy: 0.01)
    }

    // MARK: eta

    func testETAComputesRemainingOverSpeed() {
        let eta = FileOperationRules.eta(bytesDone: 500, bytesTotal: 1500, bytesPerSecond: 100)
        XCTAssertEqual(eta ?? -1, 10, accuracy: 0.0001)
    }

    func testETANilWhenSpeedIsZero() {
        XCTAssertNil(FileOperationRules.eta(bytesDone: 0, bytesTotal: 100, bytesPerSecond: 0))
    }

    func testETANilWhenSpeedIsNegative() {
        XCTAssertNil(FileOperationRules.eta(bytesDone: 0, bytesTotal: 100, bytesPerSecond: -5))
    }

    func testETANilWhenAlreadyDone() {
        XCTAssertNil(FileOperationRules.eta(bytesDone: 100, bytesTotal: 100, bytesPerSecond: 50))
    }

    func testETANilWhenOverDone() {
        XCTAssertNil(FileOperationRules.eta(bytesDone: 150, bytesTotal: 100, bytesPerSecond: 50))
    }

    // MARK: eta — bug found in adversarial review: `bytesTotal - bytesDone` on raw `Int64` traps on overflow when a
    // caller passes malformed counts (e.g. a corrupted progress update with a negative `bytesDone`). The queue must
    // degrade to "no ETA" on nonsensical input, not crash the whole app.

    func testETADoesNotCrashOnNegativeBytesDoneNearInt64Bounds() {
        // bytesTotal - bytesDone would overflow Int64 with raw subtraction; must not trap.
        XCTAssertNil(FileOperationRules.eta(bytesDone: -1, bytesTotal: .max, bytesPerSecond: 50))
    }

    func testETADoesNotCrashOnOppositeExtremeBytesCounts() {
        // The point of this test is that it returns *some* value (nil or a number) instead of trapping; with wrapping
        // subtraction the exact number is an artifact of modular arithmetic on nonsensical input, not a contract.
        _ = FileOperationRules.eta(bytesDone: .max, bytesTotal: .min, bytesPerSecond: 50)
    }

    func testETAStillComputesCorrectlyNearNormalMagnitudes() {
        // A sanity check that the overflow-safe subtraction didn't change ordinary results (1 GiB job at 1 GB/s).
        let bytesTotal: Int64 = 1_073_741_824
        let bytesDone: Int64 = 536_870_912
        let eta = FileOperationRules.eta(bytesDone: bytesDone, bytesTotal: bytesTotal, bytesPerSecond: 1_000_000_000)
        XCTAssertEqual(eta ?? -1, 0.536870912, accuracy: 0.0001)
    }

    // MARK: recoveryReport

    func testRecoveryReportStartedPhase() {
        let job = UUID()
        let entries = [JournalEntry(job: job, kind: .copy, source: "/a", destination: "/b/a", phase: .started, at: Date())]
        let report = FileOperationRules.recoveryReport(entries)
        XCTAssertEqual(report.count, 1)
        XCTAssertEqual(report[0].source, "/a")
        XCTAssertEqual(report[0].messageKey, "Có thể còn tệp chép dở ở đích")
    }

    func testRecoveryReportCopiedPhase() {
        let job = UUID()
        let entries = [JournalEntry(job: job, kind: .move, source: "/a", destination: "/b/a", phase: .copied, at: Date())]
        let report = FileOperationRules.recoveryReport(entries)
        XCTAssertEqual(report.first?.messageKey, "Bản sao chưa được kiểm")
    }

    func testRecoveryReportVerifiedPhase() {
        let job = UUID()
        let entries = [JournalEntry(job: job, kind: .move, source: "/a", destination: "/b/a", phase: .verified, at: Date())]
        let report = FileOperationRules.recoveryReport(entries)
        XCTAssertEqual(report.first?.messageKey, "Bản gốc vẫn còn ở chỗ cũ")
    }

    func testRecoveryReportTrashingPhase() {
        let job = UUID()
        let entries = [JournalEntry(job: job, kind: .move, source: "/a", destination: "/b/a", phase: .trashing, at: Date())]
        let report = FileOperationRules.recoveryReport(entries)
        XCTAssertEqual(report.first?.messageKey, "Bản gốc có thể đã vào Thùng rác — kiểm tra trước khi coi là mất")
    }

    func testRecoveryReportSourceRemovedIsConsideredFine() {
        let job = UUID()
        let entries = [JournalEntry(job: job, kind: .move, source: "/a", destination: "/b/a", phase: .sourceRemoved, at: Date())]
        XCTAssertTrue(FileOperationRules.recoveryReport(entries).isEmpty)
    }

    func testRecoveryReportDoneIsExcluded() {
        let job = UUID()
        let entries = [JournalEntry(job: job, kind: .copy, source: "/a", destination: "/b/a", phase: .done, at: Date())]
        XCTAssertTrue(FileOperationRules.recoveryReport(entries).isEmpty)
    }

    func testRecoveryReportUsesLatestAppendOrderNotTimestamp() {
        // Two entries share a timestamp (clock resolution); append order says .trashing came after .verified,
        // and append order must win, not `at`.
        let job = UUID()
        let t = Date()
        let entries = [
            JournalEntry(job: job, kind: .move, source: "/a", destination: "/b/a", phase: .verified, at: t),
            JournalEntry(job: job, kind: .move, source: "/a", destination: "/b/a", phase: .trashing, at: t),
        ]
        let report = FileOperationRules.recoveryReport(entries)
        XCTAssertEqual(report.first?.messageKey, "Bản gốc có thể đã vào Thùng rác — kiểm tra trước khi coi là mất")
    }

    func testRecoveryReportMultipleJobsAndSourcesIndependent() {
        let jobA = UUID()
        let jobB = UUID()
        let entries = [
            JournalEntry(job: jobA, kind: .copy, source: "/a", destination: "/x/a", phase: .started, at: Date()),
            JournalEntry(job: jobB, kind: .move, source: "/a", destination: "/y/a", phase: .done, at: Date()),
            JournalEntry(job: jobA, kind: .copy, source: "/c", destination: "/x/c", phase: .copied, at: Date()),
        ]
        let report = FileOperationRules.recoveryReport(entries)
        XCTAssertEqual(report.count, 2)
        XCTAssertTrue(report.contains(where: { $0.source == "/a" && $0.messageKey == "Có thể còn tệp chép dở ở đích" }))
        XCTAssertTrue(report.contains(where: { $0.source == "/c" && $0.messageKey == "Bản sao chưa được kiểm" }))
    }

    func testRecoveryReportPreservesFirstSeenOrder() {
        let job = UUID()
        let entries = [
            JournalEntry(job: job, kind: .copy, source: "/b", destination: "/x/b", phase: .started, at: Date()),
            JournalEntry(job: job, kind: .copy, source: "/a", destination: "/x/a", phase: .started, at: Date()),
        ]
        let report = FileOperationRules.recoveryReport(entries)
        XCTAssertEqual(report.map(\.source), ["/b", "/a"])
    }

    func testRecoveryReportEmptyJournalIsEmpty() {
        XCTAssertTrue(FileOperationRules.recoveryReport([]).isEmpty)
    }

    // MARK: FileJob

    func testFileJobInitialStateIsWaiting() {
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        XCTAssertEqual(job.state, .waiting)
        XCTAssertFalse(job.isActive)
        XCTAssertFalse(job.isFinished)
    }

    func testFileJobIsActiveStates() {
        for state: JobState in [.running, .pausing, .paused, .verifying, .finishing] {
            var job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
            job.state = state
            XCTAssertTrue(job.isActive, "\(state) should be active")
            XCTAssertFalse(job.isFinished, "\(state) should not be finished")
        }
    }

    func testFileJobIsFinishedStates() {
        for state: JobState in [.done, .failed, .cancelled] {
            var job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
            job.state = state
            XCTAssertTrue(job.isFinished, "\(state) should be finished")
            XCTAssertFalse(job.isActive, "\(state) should not be active")
        }
    }

    func testFileJobWaitingIsNeitherActiveNorFinished() {
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        XCTAssertFalse(job.isActive)
        XCTAssertFalse(job.isFinished)
    }

    // MARK: FileJobQueue — enqueue / startNextIfIdle

    func testQueueStartsFirstWaitingJobWhenIdle() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        let started = queue.startNextIfIdle()
        XCTAssertEqual(started, job.id)
        XCTAssertEqual(queue.jobs.first?.state, .running)
    }

    func testQueueDoesNotStartSecondJobWhileOneIsActive() {
        var queue = FileJobQueue()
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/c"], destination: "/d")
        queue.enqueue(first)
        queue.enqueue(second)
        XCTAssertNotNil(queue.startNextIfIdle())
        XCTAssertNil(queue.startNextIfIdle())
        XCTAssertEqual(queue.jobs[1].state, .waiting)
    }

    func testQueuePausedJobStillCountsAsActiveForStartNextIfIdle() {
        var queue = FileJobQueue()
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/c"], destination: "/d")
        queue.enqueue(first)
        queue.enqueue(second)
        _ = queue.startNextIfIdle()
        XCTAssertTrue(queue.pause(first.id))
        XCTAssertTrue(queue.didPause(first.id))
        // first is .paused, which is still "active" — second must not start.
        XCTAssertNil(queue.startNextIfIdle())
    }

    func testQueueActiveReturnsTheOneActiveJob() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        XCTAssertNil(queue.active)
        _ = queue.startNextIfIdle()
        XCTAssertEqual(queue.active?.id, job.id)
    }

    // MARK: pause / didPause / resume

    func testPauseOnlyFromRunning() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        XCTAssertFalse(queue.pause(job.id)) // still waiting
        _ = queue.startNextIfIdle()
        XCTAssertTrue(queue.pause(job.id))
        XCTAssertEqual(queue.jobs[0].state, .pausing)
    }

    func testPauseFailsWhenAlreadyPausing() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        XCTAssertTrue(queue.pause(job.id))
        XCTAssertFalse(queue.pause(job.id))
    }

    func testDidPauseOnlyFromPausing() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        XCTAssertFalse(queue.didPause(job.id)) // still running, not pausing yet
        _ = queue.pause(job.id)
        XCTAssertTrue(queue.didPause(job.id))
        XCTAssertEqual(queue.jobs[0].state, .paused)
    }

    func testResumeFromPausedOrPausing() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        _ = queue.pause(job.id)
        XCTAssertTrue(queue.resume(job.id)) // from pausing
        XCTAssertEqual(queue.jobs[0].state, .running)
        _ = queue.pause(job.id)
        _ = queue.didPause(job.id)
        XCTAssertTrue(queue.resume(job.id)) // from paused
        XCTAssertEqual(queue.jobs[0].state, .running)
    }

    func testResumeFailsWhenNotPaused() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        XCTAssertFalse(queue.resume(job.id)) // waiting
    }

    // MARK: cancel

    func testCancelWaitingJob() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        XCTAssertTrue(queue.cancel(job.id))
        XCTAssertEqual(queue.jobs[0].state, .cancelled)
    }

    func testCancelActiveJob() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        XCTAssertTrue(queue.cancel(job.id))
        XCTAssertEqual(queue.jobs[0].state, .cancelled)
    }

    func testCancelFailsForFinishedJob() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        queue.finish(job.id, failedWith: nil, detail: nil)
        XCTAssertFalse(queue.cancel(job.id))
    }

    func testCancelUnknownIDFails() {
        var queue = FileJobQueue()
        XCTAssertFalse(queue.cancel(UUID()))
    }

    // MARK: setPhase

    func testSetPhaseAdvancesRunningToVerifyingToFinishing() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .move, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        XCTAssertTrue(queue.setPhase(job.id, .verifying))
        XCTAssertEqual(queue.jobs[0].state, .verifying)
        XCTAssertTrue(queue.setPhase(job.id, .finishing))
        XCTAssertEqual(queue.jobs[0].state, .finishing)
    }

    func testSetPhaseBlocksVerifyingWhenPausing() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .move, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        _ = queue.pause(job.id)
        XCTAssertFalse(queue.setPhase(job.id, .verifying))
        XCTAssertEqual(queue.jobs[0].state, .pausing)
    }

    func testSetPhaseAllowsFinishingEvenWhenPausing() {
        // Only entering .verifying is blocked by a pending pause; other transitions are not restricted by this rule.
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .move, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        _ = queue.pause(job.id)
        XCTAssertTrue(queue.setPhase(job.id, .finishing))
        XCTAssertEqual(queue.jobs[0].state, .finishing)
    }

    // MARK: finish / progress

    func testFinishSuccessSetsDone() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        queue.finish(job.id, failedWith: nil, detail: nil)
        XCTAssertEqual(queue.jobs[0].state, .done)
        XCTAssertNil(queue.jobs[0].errorKey)
    }

    func testFinishFailureSetsFailedWithErrorKeyAndDetail() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        queue.finish(job.id, failedWith: "Đầy đĩa", detail: "ENOSPC")
        XCTAssertEqual(queue.jobs[0].state, .failed)
        XCTAssertEqual(queue.jobs[0].errorKey, "Đầy đĩa")
        XCTAssertEqual(queue.jobs[0].errorDetail, "ENOSPC")
    }

    func testProgressUpdatesBytesAndItems() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        queue.progress(job.id, bytesDone: 1024, itemsDone: 3)
        XCTAssertEqual(queue.jobs[0].bytesDone, 1024)
        XCTAssertEqual(queue.jobs[0].itemsDone, 3)
    }

    // MARK: pauseAll / resumeAll

    func testPauseAllOnlyAffectsRunningJob() {
        var queue = FileJobQueue()
        let running = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        let waiting = FileJob(id: UUID(), kind: .copy, sources: ["/c"], destination: "/d")
        queue.enqueue(running)
        queue.enqueue(waiting)
        _ = queue.startNextIfIdle()
        queue.pauseAll()
        XCTAssertEqual(queue.jobs[0].state, .pausing)
        XCTAssertEqual(queue.jobs[1].state, .waiting)
    }

    func testResumeAllBringsPausedAndPausingBackToRunning() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        _ = queue.pause(job.id)
        _ = queue.didPause(job.id)
        queue.resumeAll()
        XCTAssertEqual(queue.jobs[0].state, .running)
    }

    // MARK: runNext / moveUp / moveDown

    func testRunNextMovesWaitingJobToFrontOfWaitingGroup() {
        var queue = FileJobQueue()
        let running = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/dest")
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/b"], destination: "/dest")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/c"], destination: "/dest")
        queue.enqueue(running)
        queue.enqueue(first)
        queue.enqueue(second)
        _ = queue.startNextIfIdle() // running starts
        XCTAssertTrue(queue.runNext(second.id))
        XCTAssertEqual(queue.jobs.map(\.id), [running.id, second.id, first.id])
    }

    func testRunNextFailsForNonWaitingJob() {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        XCTAssertFalse(queue.runNext(job.id))
    }

    func testRunNextSkipsOverFinishedJobsInterleavedWithWaiting() {
        // Finished jobs sitting ahead of the waiting group (already .done, never removed by clearFinished) must not
        // shift where a "run next" job lands — it belongs right after them, not at absolute index 0.
        var queue = FileJobQueue()
        let done = FileJob(id: UUID(), kind: .copy, sources: ["/z"], destination: "/dest")
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/dest")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/b"], destination: "/dest")
        let third = FileJob(id: UUID(), kind: .copy, sources: ["/c"], destination: "/dest")
        queue.enqueue(done)
        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(third)
        _ = queue.startNextIfIdle() // `done` is first in queue, so it becomes the one running job...
        queue.finish(done.id, failedWith: nil, detail: nil) // ...then finish() moves it straight to `.done`.
        XCTAssertTrue(queue.runNext(third.id))
        XCTAssertEqual(queue.jobs.map(\.id), [done.id, third.id, first.id, second.id])
    }

    func testMoveUpSwapsOnlyAmongWaitingJobs() {
        var queue = FileJobQueue()
        let running = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/dest")
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/b"], destination: "/dest")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/c"], destination: "/dest")
        queue.enqueue(running)
        queue.enqueue(first)
        queue.enqueue(second)
        _ = queue.startNextIfIdle()
        XCTAssertTrue(queue.moveUp(second.id))
        XCTAssertEqual(queue.jobs.map(\.id), [running.id, second.id, first.id])
    }

    func testMoveUpFailsForFirstWaitingJob() {
        var queue = FileJobQueue()
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/dest")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/b"], destination: "/dest")
        queue.enqueue(first)
        queue.enqueue(second)
        XCTAssertFalse(queue.moveUp(first.id))
    }

    func testMoveDownSwapsOnlyAmongWaitingJobs() {
        var queue = FileJobQueue()
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/dest")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/b"], destination: "/dest")
        queue.enqueue(first)
        queue.enqueue(second)
        XCTAssertTrue(queue.moveDown(first.id))
        XCTAssertEqual(queue.jobs.map(\.id), [second.id, first.id])
    }

    func testMoveDownFailsForLastWaitingJob() {
        var queue = FileJobQueue()
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/dest")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/b"], destination: "/dest")
        queue.enqueue(first)
        queue.enqueue(second)
        XCTAssertFalse(queue.moveDown(second.id))
    }

    func testMoveUpDoesNotTouchActiveOrFinishedJobs() {
        var queue = FileJobQueue()
        let done = FileJob(id: UUID(), kind: .copy, sources: ["/z"], destination: "/dest")
        let first = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/dest")
        let second = FileJob(id: UUID(), kind: .copy, sources: ["/b"], destination: "/dest")
        queue.enqueue(done)
        queue.enqueue(first)
        queue.enqueue(second)
        queue.finish(done.id, failedWith: nil, detail: nil) // done is .waiting until finish(); force to .done path:
        // finish() requires the job to exist; it transitions whatever state it is in to .done/.failed, which is fine here.
        XCTAssertTrue(queue.moveUp(second.id))
        XCTAssertEqual(queue.jobs.map(\.id), [done.id, second.id, first.id])
    }

    // MARK: clearFinished

    func testClearFinishedRemovesOnlyFinishedJobs() {
        var queue = FileJobQueue()
        let waiting = FileJob(id: UUID(), kind: .copy, sources: ["/a"], destination: "/b")
        let toFinish = FileJob(id: UUID(), kind: .copy, sources: ["/c"], destination: "/d")
        queue.enqueue(toFinish)
        queue.enqueue(waiting)
        _ = queue.startNextIfIdle()
        queue.finish(toFinish.id, failedWith: nil, detail: nil)
        queue.clearFinished()
        XCTAssertEqual(queue.jobs.map(\.id), [waiting.id])
    }

    // MARK: Codable round-trip (public API relies on Codable per contract)

    func testFileJobQueueCodableRoundTrip() throws {
        var queue = FileJobQueue()
        let job = FileJob(id: UUID(), kind: .move, sources: ["/a", "/b"], destination: "/dest")
        queue.enqueue(job)
        _ = queue.startNextIfIdle()
        queue.progress(job.id, bytesDone: 42, itemsDone: 1)
        let data = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(FileJobQueue.self, from: data)
        XCTAssertEqual(decoded, queue)
    }

    func testJournalEntryCodableRoundTrip() throws {
        let entry = JournalEntry(job: UUID(), kind: .move, source: "/a", destination: "/b", phase: .trashing, at: Date())
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }
}
