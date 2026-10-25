import XCTest
import Foundation

final class FolderMergeTests: XCTestCase {
    private func node(_ path: String, dir: Bool = false, pkg: Bool = false, link: Bool = false,
                       size: Int64 = 100, modified: Date = Date(timeIntervalSince1970: 1000), cloud: Bool = false) -> MergeNode {
        MergeNode(relativePath: path, isDirectory: dir, isPackage: pkg, isSymlink: link, size: size, modified: modified, isCloudFolder: cloud)
    }

    // MARK: newerThreshold

    func testNewerThresholdIsOneSecondOnNormalVolumes() {
        XCTAssertEqual(FolderMerge.newerThreshold(fat: false), 1)
    }

    func testNewerThresholdIsTwoSecondsOnFAT() {
        XCTAssertEqual(FolderMerge.newerThreshold(fat: true), 2)
    }

    // MARK: refusal

    func testRefusalNilForUnrelatedFolders() {
        XCTAssertNil(FolderMerge.refusal(source: "/a/b", destination: "/a/c"))
    }

    func testRefusalNestedWhenDestinationInsideSource() {
        XCTAssertEqual(FolderMerge.refusal(source: "/a/b", destination: "/a/b/c"), .nested)
    }

    func testRefusalNestedWhenSourceInsideDestination() {
        XCTAssertEqual(FolderMerge.refusal(source: "/a/b/c", destination: "/a/b"), .nested)
    }

    func testRefusalSameFolder() {
        XCTAssertEqual(FolderMerge.refusal(source: "/a/b", destination: "/a/b"), .sameFolder)
    }

    func testRefusalSameFolderDifferentStringSamePath() {
        // Trailing slash / double slash must normalize to the same path, not escape the nesting check.
        XCTAssertEqual(FolderMerge.refusal(source: "/a/b/", destination: "/a/b"), .sameFolder)
    }

    func testRefusalDoesNotFalsePositiveOnPrefixString() {
        // "/a/bc" is not inside "/a/b" even though it has that string as a textual prefix.
        XCTAssertNil(FolderMerge.refusal(source: "/a/b", destination: "/a/bc"))
    }

    // MARK: plan — new items (no collision)

    func testPlanNewItemCopiesStraightAcross() {
        let plan = FolderMerge.plan(source: [node("new.txt")], destination: [], policy: .keepBoth, fat: false)
        XCTAssertEqual(plan.steps, [.copy("new.txt")])
        XCTAssertEqual(plan.willCopy, 1)
    }

    func testPlanItemsOnlyAtDestinationAreUntouched() {
        // Merge only adds/overwrites from source; it never produces a step for something the source never mentioned.
        let plan = FolderMerge.plan(source: [], destination: [node("onlyHere.txt")], policy: .keepBoth, fat: false)
        XCTAssertEqual(plan.steps, [])
    }

    // MARK: plan — Keep Both policy

    func testPlanKeepBothRenamesCollidingFile() {
        let source = [node("Report.pdf", modified: Date(timeIntervalSince1970: 2000))]
        let destination = [node("Report.pdf", modified: Date(timeIntervalSince1970: 1000))]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        XCTAssertEqual(plan.steps, [.keepBoth(from: "Report.pdf", to: "Report 2.pdf")])
        XCTAssertEqual(plan.willRename, 1)
    }

    func testPlanKeepBothAvoidsCollisionWithAlreadyRenamedSibling() {
        let source = [node("Report.pdf"), node("Report 2.pdf")]
        let destination = [node("Report.pdf"), node("Report 2.pdf")]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        // Both source items collide; the second one to be renamed must skip the name the first one just took.
        XCTAssertTrue(plan.steps.contains(.keepBoth(from: "Report.pdf", to: "Report 3.pdf")) ||
                      plan.steps.contains(.keepBoth(from: "Report 2.pdf", to: "Report 3.pdf")))
        let renamedTargets = plan.steps.compactMap { step -> String? in
            if case .keepBoth(_, let to) = step { return to }
            return nil
        }
        XCTAssertEqual(Set(renamedTargets).count, renamedTargets.count, "two renames must not collide with each other")
    }

    func testPlanKeepBothOnFolderVsFolderRecursesIntoChildren() {
        let source = [node("Dir", dir: true), node("Dir/file.txt")]
        let destination = [node("Dir", dir: true), node("Dir/file.txt")]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        // The directory pair itself is not a conflict; only the colliding child file is.
        XCTAssertEqual(plan.steps, [.keepBoth(from: "Dir/file.txt", to: "Dir/file 2.txt")])
    }

    func testPlanFolderVsFolderWithNoCollidingChildProducesNoStep() {
        let source = [node("Dir", dir: true), node("Dir/onlyInSource.txt")]
        let destination = [node("Dir", dir: true)]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        XCTAssertEqual(plan.steps, [.copy("Dir/onlyInSource.txt")])
    }

    // MARK: plan — Skip policy

    func testPlanSkipLeavesExistingUntouched() {
        let source = [node("Report.pdf")]
        let destination = [node("Report.pdf")]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .skip, fat: false)
        XCTAssertEqual(plan.steps, [.skip("Report.pdf")])
        XCTAssertEqual(plan.willSkip, 1)
    }

    // MARK: plan — Keep the newer policy + FAT threshold

    func testPlanKeepNewerReplacesWhenSourceAtLeastOneSecondNewer() {
        let source = [node("a.txt", modified: Date(timeIntervalSince1970: 1001))]
        let destination = [node("a.txt", modified: Date(timeIntervalSince1970: 1000))]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepNewer, fat: false)
        XCTAssertEqual(plan.steps, [.replace("a.txt")])
        XCTAssertEqual(plan.willReplace, 1)
    }

    func testPlanKeepNewerSkipsWhenUnderOneSecondOnNormalVolume() {
        let source = [node("a.txt", modified: Date(timeIntervalSince1970: 1000.5))]
        let destination = [node("a.txt", modified: Date(timeIntervalSince1970: 1000))]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepNewer, fat: false)
        XCTAssertEqual(plan.steps, [.skip("a.txt")])
    }

    func testPlanKeepNewerOnFATRequiresTwoSeconds() {
        // 1.5 s newer: not enough on FAT (needs 2 s), would be enough on APFS/HFS+.
        let source = [node("a.txt", modified: Date(timeIntervalSince1970: 1001.5))]
        let destination = [node("a.txt", modified: Date(timeIntervalSince1970: 1000))]
        let fatPlan = FolderMerge.plan(source: source, destination: destination, policy: .keepNewer, fat: true)
        XCTAssertEqual(fatPlan.steps, [.skip("a.txt")])
        let normalPlan = FolderMerge.plan(source: source, destination: destination, policy: .keepNewer, fat: false)
        XCTAssertEqual(normalPlan.steps, [.replace("a.txt")])
    }

    func testPlanKeepNewerSkipsWhenOlder() {
        let source = [node("a.txt", modified: Date(timeIntervalSince1970: 999))]
        let destination = [node("a.txt", modified: Date(timeIntervalSince1970: 1000))]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepNewer, fat: false)
        XCTAssertEqual(plan.steps, [.skip("a.txt")])
    }

    // MARK: plan — exclusions (R27)

    func testPlanExcludesPackageCollisionUnderKeepBoth() {
        let source = [node("App.app", pkg: true)]
        let destination = [node("App.app", pkg: true)]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        guard case .excluded(let path, _) = plan.steps.first else { return XCTFail("expected excluded step") }
        XCTAssertEqual(path, "App.app")
    }

    func testPlanExcludesSymlinkCollision() {
        let source = [node("link", link: true)]
        let destination = [node("link", link: true)]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        guard case .excluded = plan.steps.first else { return XCTFail("expected excluded step") }
    }

    func testPlanExcludesCloudFolderCollision() {
        let source = [node("Dropbox", dir: true, cloud: true)]
        let destination = [node("Dropbox", dir: true, cloud: true)]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        guard case .excluded = plan.steps.first else { return XCTFail("expected excluded step") }
    }

    func testPlanExcludesTypeMismatchFileVsFolder() {
        let source = [node("thing", dir: false)]
        let destination = [node("thing", dir: true)]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        guard case .excluded = plan.steps.first else { return XCTFail("expected excluded step") }
    }

    func testPlanExcludedUnderSkipPolicyBecomesSkip() {
        // Skip policy still needs SOME disposition for the collision; it is reported as skip rather than excluded
        // so "skip" consistently means "left alone" regardless of why.
        let source = [node("App.app", pkg: true)]
        let destination = [node("App.app", pkg: true)]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .skip, fat: false)
        XCTAssertEqual(plan.steps, [.skip("App.app")])
    }

    func testPlanExcludedPackageChildrenNeverGetOwnSteps() {
        let source = [node("App.app", pkg: true), node("App.app/Contents/Info.plist")]
        let destination = [node("App.app", pkg: true)]
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        XCTAssertEqual(plan.steps.count, 1)
        guard case .excluded(let path, _) = plan.steps[0] else { return XCTFail("expected excluded step") }
        XCTAssertEqual(path, "App.app")
    }

    // MARK: tallies

    func testPlanTalliesCountEachStepKindIndependently() {
        let source = [
            node("new.txt"),
            node("replaceMe.txt", modified: Date(timeIntervalSince1970: 2000)),
            node("skipMe.txt"),
            node("renameMe.txt"),
        ]
        let destination = [
            node("replaceMe.txt", modified: Date(timeIntervalSince1970: 1000)),
            node("skipMe.txt"),
            node("renameMe.txt"),
        ]
        // Use keepNewer only for the replace/skip pair by calling plan twice is unnecessary — instead verify
        // keepBoth's tally shape directly (copy + 3 renames, since keepBoth renames every collision).
        let plan = FolderMerge.plan(source: source, destination: destination, policy: .keepBoth, fat: false)
        XCTAssertEqual(plan.willCopy, 1)
        XCTAssertEqual(plan.willRename, 3)
        XCTAssertEqual(plan.willReplace, 0)
        XCTAssertEqual(plan.willSkip, 0)
    }
}
