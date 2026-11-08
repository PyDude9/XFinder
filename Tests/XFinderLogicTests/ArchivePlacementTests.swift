import XCTest
import Foundation

/// Stage 03C: the parts of placement that decide **what happens to the user's existing files**.
///
/// Every test here corresponds to a measured behaviour in `docs/specs/XF-MFGAP-03-archive-safety.md`
/// §2 or to a Boss approval decision, and each would fail against the code shipped before 03C.
final class ArchivePlacementTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("xf-place-\(UUID().uuidString)")
        for d in ["src", "dest", "recovery", "out"] {
            try fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    func url(_ p: String) -> URL { root.appendingPathComponent(p) }
    func read(_ p: String) -> String? { try? String(contentsOf: url(p), encoding: .utf8) }
    func write(_ p: String, _ text: String) throws {
        try fm.createDirectory(at: url(p).deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url(p), atomically: true, encoding: .utf8)
    }

    // MARK: - Recursive merge plan (pure)

    /// Boss decision 1: folders combine, colliding leaves are numbered. This is the whole semantic
    /// change, so it is pinned on the pure planner before any file is touched.
    func testMergeCombinesFoldersAndNumbersCollidingLeaves() {
        let items = [ArchiveEngine.StagedItem(path: "Photos", isDirectory: true),
                     ArchiveEngine.StagedItem(path: "Photos/a.txt", isDirectory: false),
                     ArchiveEngine.StagedItem(path: "Photos/b.txt", isDirectory: false)]
        let plan = ArchiveEngine.mergePlan(items: items, into: url("dest")) { candidate in
            // `dest/Photos` already exists and holds `a.txt`; `b.txt` is new.
            if candidate.lastPathComponent == "Photos" { return .directory }
            if candidate.lastPathComponent == "a.txt" { return .file }
            return nil
        }
        XCTAssertEqual(plan.map { $0.target.path.replacingOccurrences(of: url("dest").path + "/", with: "") },
                       ["Photos", "Photos/a 2.txt", "Photos/b.txt"])
        XCTAssertEqual(ArchiveEngine.renamedLeafNames(plan), ["a 2.txt"])
    }

    /// A file where the archive wants a folder, and a folder where it wants a file: the incoming item
    /// is kept under a numbered name instead of either being lost.
    func testMergeNumbersTypeCollisionsBothWays() {
        let items = [ArchiveEngine.StagedItem(path: "report", isDirectory: true),
                     ArchiveEngine.StagedItem(path: "notes", isDirectory: false)]
        let plan = ArchiveEngine.mergePlan(items: items, into: url("dest")) { candidate in
            if candidate.lastPathComponent == "report" { return .file }       // a FILE is in the way
            if candidate.lastPathComponent == "notes" { return .directory }   // a FOLDER is in the way
            return nil
        }
        XCTAssertEqual(Set(plan.map(\.target.lastPathComponent)), ["report 2", "notes 2"])
        XCTAssertTrue(plan.allSatisfy(\.renamed))
    }

    /// A symlink at the destination is an occupied name, never something to write through or replace.
    func testMergeTreatsADestinationLinkAsOccupied() {
        let items = [ArchiveEngine.StagedItem(path: "x.txt", isDirectory: false)]
        let plan = ArchiveEngine.mergePlan(items: items, into: url("dest")) { candidate in
            candidate.lastPathComponent == "x.txt" ? .link : nil
        }
        XCTAssertEqual(plan.map(\.target.lastPathComponent), ["x 2.txt"],
                       "a link must not be replaced, and must not be written through")
    }

    /// The other half, and the case the measured escape (spec §2) came from: a link where the archive
    /// wants a **folder** must never be combined into. Combing into it is what wrote `outside/same.txt`
    /// outside the chosen folder.
    func testMergeNumbersADirectoryOntoALinkInsteadOfCombiningIntoIt() {
        let items = [ArchiveEngine.StagedItem(path: "folder", isDirectory: true),
                     ArchiveEngine.StagedItem(path: "folder/deep.txt", isDirectory: false)]
        let plan = ArchiveEngine.mergePlan(items: items, into: url("dest")) { candidate in
            candidate.lastPathComponent == "folder" ? .link : nil
        }
        XCTAssertEqual(plan.map(\.target.lastPathComponent), ["folder 2", "deep.txt"],
                       "a link must be an occupied name, not a folder to merge into")
        XCTAssertEqual(plan.map(\.target.path), [url("dest/folder 2").path, url("dest/folder 2/deep.txt").path],
                       "the child must follow the numbered folder, not stay under the link")
        // The rename is reported once, as the folder — the user never sees "deep.txt" renamed.
        XCTAssertEqual(ArchiveEngine.renamedLeafNames(plan), ["folder 2"])
    }

    /// Two items of the same batch must never be planned onto one name, even when the first one's
    /// numbering is what the second one is called.
    func testMergeNeverPlansTwoItemsOntoOneName() {
        let items = [ArchiveEngine.StagedItem(path: "a", isDirectory: false),
                     ArchiveEngine.StagedItem(path: "a", isDirectory: false)]
        let plan = ArchiveEngine.mergePlan(items: items, into: url("dest")) { _ in nil }
        XCTAssertEqual(Set(plan.map(\.target.lastPathComponent)).count, 2, "\(plan.map(\.target.lastPathComponent))")
    }

    /// Compound extensions survive numbering — the reason `numbered` exists.
    func testMergeNumberingKeepsCompoundExtensions() {
        let items = [ArchiveEngine.StagedItem(path: "backup.tar.gz", isDirectory: false)]
        let plan = ArchiveEngine.mergePlan(items: items, into: url("dest")) { candidate in
            candidate.lastPathComponent == "backup.tar.gz" ? .file : nil
        }
        XCTAssertEqual(plan[0].target.lastPathComponent, "backup 2.tar.gz")
    }

    // MARK: - Exclusive publication

    /// The primitive the whole no-replace contract rests on: measured to fail with EEXIST and leave the
    /// existing file byte-identical.
    func testPublishExclusivelyRefusesToReplaceAnExistingFile() throws {
        try write("dest/one.txt", "MINE")
        try write("out/one.txt", "ARCHIVE")
        XCTAssertThrowsError(try ArchiveRunner.publishExclusively(from: url("out/one.txt"), to: url("dest/one.txt")))
        XCTAssertEqual(read("dest/one.txt"), "MINE", "the existing file was replaced")
        XCTAssertEqual(read("out/one.txt"), "ARCHIVE", "the source must still be there after a refusal")
    }

    func testPublishExclusivelyMovesIntoAFreeName() throws {
        try write("out/one.txt", "ARCHIVE")
        try ArchiveRunner.publishExclusively(from: url("out/one.txt"), to: url("dest/one.txt"))
        XCTAssertEqual(read("dest/one.txt"), "ARCHIVE")
        XCTAssertFalse(fm.fileExists(atPath: url("out/one.txt").path))
    }

    /// Spec §7, the measured trap: the first item placed, the second failed, and the failure was
    /// reported as though nothing had happened. The remainder must be kept, not deleted, and the report
    /// must say where it went — this is the whole reason the recovery root exists.
    func testAPartialPlacementKeepsTheRemainderAndNamesWhereItWent() async throws {
        try write("src/one.txt", "one")
        try write("src/two/inner.txt", "inner")
        let archive = url("out/p.zip")
        _ = await ArchiveRunner.compress(sources: [url("src/one.txt"), url("src/two")],
                                         format: .zip, output: archive)
        guard case .success(let batch) = await ArchiveRunner.extractToStaging(archive: archive,
                                                                            near: url("dest")) else {
            return XCTFail("staging failed")
        }
        // `dest/two` exists but is read-only, so combining the folders works and publishing the file
        // inside it cannot. That is the measured partial shape: some items land, one does not.
        try fm.createDirectory(at: url("dest/two"), withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: url("dest/two").path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url("dest/two").path) }

        // Merge on purpose: Keep Both would number the whole folder and succeed, which is not the
        // shape being tested — only a folder that is combined into can fail halfway.
        let r = await ArchiveRunner.place(batch, into: url("dest"), policy: .merge,
                                          recoveryRoot: url("recovery"))
        guard case .success(let outcome) = r else { return XCTFail("\(r)") }
        XCTAssertFalse(outcome.isComplete, "a partial placement must never report success")
        XCTAssertNotNil(outcome.failure)
        XCTAssertFalse(outcome.placed.isEmpty, "the item that did land must still be reported")
        guard let recovery = outcome.recoveryRoot else {
            return XCTFail("the unplaced remainder was discarded instead of kept")
        }
        XCTAssertTrue(fm.fileExists(atPath: recovery.path), "the recovery folder must exist")
        let kept = try fm.contentsOfDirectory(atPath: recovery.path)
        XCTAssertTrue(kept.contains("two"), "the unplaced item must still be recoverable: \(kept)")
        XCTAssertFalse(fm.fileExists(atPath: batch.staging.path), "the owned staging root is released")
    }

    /// Measured in spec §2: a ZIP holding a leaf named like its own source replaced that source. The
    /// archive (and the other selected sources) are protected identities — they get a numbered name.
    func testTheSourceArchiveCannotBeOverwrittenByItsOwnContents() async throws {
        try write("src/one.txt", "one")
        try write("src/other.txt", "other")
        // The archive deliberately sits inside the folder it is extracted into, and holds a leaf named
        // `self.zip` — the exact shape that used to replace its own source.
        let archive = url("dest/self.zip")
        guard case .success = await ArchiveRunner.compress(sources: [url("src/one.txt"), url("src/other.txt")],
                                                          format: .zip, output: archive) else {
            return XCTFail("compression failed")
        }
        let original = try Data(contentsOf: archive)
        try write("src/self.zip", "a leaf that shares the archive's name")
        guard case .success = await ArchiveRunner.compress(sources: [url("src/self.zip"), url("src/one.txt")],
                                                          format: .zip, output: url("out/leaf.zip")) else {
            return XCTFail("compression of the leaf archive failed")
        }

        // Extract the leaf archive into `dest`, where `self.zip` already exists.
        guard case .success(let batch) = await ArchiveRunner.extractToStaging(archive: url("out/leaf.zip"),
                                                                            near: url("dest")) else {
            return XCTFail("staging failed")
        }
        let r = await ArchiveRunner.place(batch, into: url("dest"), policy: .merge,
                                          protected: [archive], recoveryRoot: url("recovery"))
        guard case .success(let outcome) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(try Data(contentsOf: archive), original,
                       "the source archive was replaced by its own contents")
        XCTAssertTrue(outcome.isComplete, "\(outcome)")
        XCTAssertEqual(outcome.renamed, ["self 2.zip"], "the protected name must be numbered, not replaced")
    }

    /// The half of the protection that the destination check cannot provide: an existing *file* is
    /// already reported as taken, but an existing **folder** would be **combined into** by Merge — so
    /// without the identity guard a batch could write inside a folder the user selected as a source.
    /// Pinned directly, because `place`'s contract takes any protected URLs and only the guard keeps
    /// them out of the merge plan.
    func testMergeNeverCombinesIntoAProtectedFolder() async throws {
        try write("src/folder/keep.txt", "KEEP")
        try write("src/one.txt", "one")
        let archive = url("out/prot.zip")
        guard case .success = await ArchiveRunner.compress(sources: [url("src/one.txt"), url("src/folder")],
                                                          format: .zip, output: archive) else {
            return XCTFail("compression failed")
        }
        guard case .success(let batch) = await ArchiveRunner.extractToStaging(archive: archive,
                                                                            near: url("dest")) else {
            return XCTFail("staging failed")
        }
        // `destination` is `src` itself: `src/folder` exists and is a directory, so the only thing that
        // stops Merge from combining into it is that it was declared a protected identity.
        let r = await ArchiveRunner.place(batch, into: url("src"), policy: .merge,
                                          protected: [url("src/folder")], recoveryRoot: url("recovery"))
        guard case .success(let outcome) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(read("src/folder/keep.txt"), "KEEP", "the user's folder was written into")
        XCTAssertTrue(outcome.renamed.contains("folder 2"), "\(outcome.renamed)")
        XCTAssertTrue(fm.fileExists(atPath: url("src/folder 2/keep.txt").path),
                      "the incoming folder must land beside the protected one, not inside it")
    }

    /// Boss decision 1: the collision prompt's default is **Cancel**, and the alert's button order is
    /// derived from that single declaration — so no dialog can quietly put a write first again.
    func testAskDefaultsToCancelAndPutsItFirst() {
        XCTAssertEqual(ArchiveEngine.AskChoice.defaultChoice, .cancel)
        XCTAssertEqual(ArchiveEngine.AskChoice.buttonOrder.first, .cancel,
                       "Return must not trigger a write")
        XCTAssertEqual(Set(ArchiveEngine.AskChoice.buttonOrder), Set(ArchiveEngine.AskChoice.all),
                       "every choice must appear exactly once")
        XCTAssertEqual(ArchiveEngine.AskChoice.buttonOrder.count, ArchiveEngine.AskChoice.all.count)
    }

    // MARK: - Creation Replace transaction (Boss decision 5)

    /// The old code trashed the existing archive before building the new one, so a failed build left
    /// nothing. Now: candidate verified → trash → exclusive publish.
    func testReplaceTrashesTheOldFileOnlyAfterTheCandidateExists() throws {
        try write("dest/Report.zip", "OLD")
        try write("out/candidate.zip", "NEW")
        var trashed: [URL] = []
        let r = ArchiveRunner.replace(existing: url("dest/Report.zip"), with: url("out/candidate.zip"),
                                      trash: { source in
                                          trashed.append(source)
                                          let parked = self.url("recovery/parked-\(source.lastPathComponent)")
                                          try FileManager.default.moveItem(at: source, to: parked)
                                          return parked
                                      })
        guard case .success(let url) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(url, self.url("dest/Report.zip"))
        XCTAssertEqual(read("dest/Report.zip"), "NEW")
        XCTAssertEqual(trashed.count, 1)
    }

    /// The failure branch that matters: publishing fails after the original was trashed. The original
    /// must come back, and the failure must say so.
    func testReplaceRestoresTheOriginalWhenPublishingFails() throws {
        try write("dest/Report.zip", "OLD")
        try write("out/candidate.zip", "NEW")
        let r = ArchiveRunner.replace(existing: url("dest/Report.zip"), with: url("out/candidate.zip"),
                                      trash: { source in
                                          let parked = self.url("recovery/parked-Report.zip")
                                          try FileManager.default.moveItem(at: source, to: parked)
                                          return parked
                                      },
                                      publish: { _, _ in throw ArchiveRunner.PlacementError.alreadyExists(self.url("dest/Report.zip")) })
        guard case .failure(.placement(let detail)) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(detail.contains("put back"), detail)
        XCTAssertEqual(read("dest/Report.zip"), "OLD", "the original was not restored")
    }

    /// When even the restore fails, the message must name where the original still is — never imply it
    /// was deleted.
    func testReplaceNamesTheTrashLocationWhenTheOriginalCannotBeRestored() throws {
        try write("dest/Report.zip", "OLD")
        try write("out/candidate.zip", "NEW")
        let r = ArchiveRunner.replace(existing: url("dest/Report.zip"), with: url("out/candidate.zip"),
                                      trash: { source in
                                          let parked = self.url("recovery/parked-Report.zip")
                                          try FileManager.default.moveItem(at: source, to: parked)
                                          return parked
                                      },
                                      publish: { _, _ in
                                          // Restore will fail too: the parked original is gone.
                                          try FileManager.default.removeItem(at: self.url("recovery/parked-Report.zip"))
                                          throw ArchiveRunner.PlacementError.alreadyExists(self.url("dest/Report.zip"))
                                      })
        guard case .failure(.placement(let detail)) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(detail.contains("Trash"), detail)
        XCTAssertTrue(detail.contains("parked-Report.zip"), "the failure must name where the old file is: \(detail)")
    }

    /// A Trash failure means nothing was touched at all — the candidate must not be published.
    func testReplaceDoesNothingWhenTheTrashStepFails() throws {
        try write("dest/Report.zip", "OLD")
        try write("out/candidate.zip", "NEW")
        let r = ArchiveRunner.replace(existing: url("dest/Report.zip"), with: url("out/candidate.zip"),
                                      trash: { _ in throw CocoaError(.fileWriteNoPermission) })
        guard case .failure(.placement(let detail)) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(detail.contains("Trash"), detail)
        XCTAssertEqual(read("dest/Report.zip"), "OLD")
        XCTAssertEqual(read("out/candidate.zip"), "NEW", "the verified candidate must be left for the user")
    }

    // MARK: - Source deletion ("Xóa file nén gốc", Boss decision 6)

    /// Only archives that completed this run may be trashed. A failed or cancelled one stays.
    func testOnlyCompletedArchivesAreDeletable() {
        let a = url("a.zip"), b = url("b.zip"), c = url("c.zip")
        let deletable = ArchiveJob.deletableSources(outcomes: [
            (a, .completed(outputs: [url("dest/a")], renamed: [])),
            (b, .rejected(.unsafeArchive(reasons: [], diagnostic: nil))),
            (c, .cancelledBeforePlacement),
        ])
        XCTAssertEqual(deletable, [a], "a failed or cancelled archive must never be offered for deletion")
    }

    /// A partial placement is **not** a completed archive.
    func testAPartialPlacementIsNotDeletable() {
        let a = url("a.zip")
        let deletable = ArchiveJob.deletableSources(outcomes: [
            (a, .partial(placed: [url("dest/x")], failed: ["y"], recoveryRoot: nil)),
        ])
        XCTAssertTrue(deletable.isEmpty)
    }

    /// Per-file failures are reported instead of being hidden by `try?`.
    func testTrashReportsEachFileThatCouldNotBeRemoved() throws {
        let good = url("good.zip"), bad = url("bad.zip")
        try write("good.zip", "x"); try write("bad.zip", "y")
        let report = ArchiveJob.trashSources([good, bad]) { source in
            if source == bad { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: source)
        }
        XCTAssertEqual(report.trashed, [good])
        XCTAssertEqual(report.failed.map(\.0), [bad])
        XCTAssertFalse(report.isComplete)
    }

    /// The confirmation lists the names and defaults to Cancel.
    func testTheDeleteConfirmationDefaultsToCancel() {
        let c = ArchiveJob.deleteConfirmation(names: ["a.zip", "b.zip"])
        XCTAssertTrue(c.defaultsToCancel)
        XCTAssertTrue(c.title.contains("2"))
        XCTAssertTrue(c.detail.contains("a.zip"))
    }

    // MARK: - Review (spec §4.5)

    func testUnknownCapacityIsItsOwnVerdictNotAShortage() {
        let review = ArchiveJob.review(archive: url("a.zip"), destination: url("dest"), manifest: [],
                                       declaredBytes: 0, availableBytes: nil, requiredBytes: 1024,
                                       conflicts: [])
        XCTAssertEqual(review.capacityVerdict, .unknown)
    }

    func testShortfallIsReportedAsTheExactShortageInBytes() {
        let review = ArchiveJob.review(archive: url("a.zip"), destination: url("dest"), manifest: [],
                                       declaredBytes: 0, availableBytes: 2_000, requiredBytes: 5_000,
                                       conflicts: [])
        XCTAssertEqual(review.capacityVerdict, .doesNotFit(short: 3_000))
    }

    func testARefusalMakesTheReviewNotExtractable() {
        let review = ArchiveJob.review(archive: url("a.zip"), destination: url("dest"), manifest: [],
                                       declaredBytes: 0, availableBytes: 100, requiredBytes: 0,
                                       conflicts: [], refusals: [.escapesRoot("../x")])
        XCTAssertFalse(review.isExtractable, "a refusal must block the extract button, with no bypass")
    }

    /// A refusal makes the plan unextractable, and so does an unchosen custom destination — the page
    /// must never print "ready" for a destination it does not have.
    func testAnUnchosenCustomDestinationBlocksThePlan() {
        XCTAssertEqual(ArchiveJob.destinationProblem(isCustom: true, folder: nil), .customFolderNotChosen)
        XCTAssertNil(ArchiveJob.destinationProblem(isCustom: true, folder: url("dest")))
        XCTAssertNil(ArchiveJob.destinationProblem(isCustom: false, folder: nil),
                     "the other modes derive their destination from the archive, so they are never blocked")
    }

    /// The one sentence the page prints for that state, reachable through the shipped store.
    func testTheDestinationProblemHasATranslatedSentence() throws {
        let store = try L10nFixture.load()
        let key = ArchiveJob.DestinationProblem.customFolderNotChosen.messageKey
        XCTAssertNotNil(store.entries[key], "\(key) is not in L10n.strings.json")
        XCTAssertNotEqual(store.entries[key]?.en, key)
    }

    // MARK: - Recovery store

    func testRecoveryRootStaysInsideApplicationSupport() {
        XCTAssertTrue(ArchiveRecoveryStore.root.path.contains("Application Support"))
        XCTAssertTrue(ArchiveRecoveryStore.root.path.hasSuffix("ArchiveRecovery"))
    }

    /// The store refuses to delete anything outside its own root, so a corrupt listing cannot be used
    /// to remove a user folder.
    func testRecoveryStoreRefusesToDeleteOutsideItsRoot() throws {
        try write("recovery/not-a-batch", "x")
        XCTAssertThrowsError(try ArchiveRecoveryStore.remove(url("recovery/not-a-batch")))
        XCTAssertTrue(fm.fileExists(atPath: url("recovery/not-a-batch").path))
    }
}
