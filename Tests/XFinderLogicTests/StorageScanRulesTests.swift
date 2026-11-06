import Foundation
import XCTest

final class StorageScanRulesTests: XCTestCase {
    private func file(_ path: String, _ size: Int64) -> StorageScanFile {
        StorageScanFile(name: URL(fileURLWithPath: path).lastPathComponent, relativePath: path, logicalSize: size)
    }

    func testLargestFilesAreBoundedAndOrderedBySizeThenPath() {
        var top: [StorageScanFile] = []
        for index in (0..<200).reversed() {
            StorageScanRules.insert(file("f\(index)", Int64(index)), into: &top, limit: 50)
        }
        XCTAssertEqual(top.count, 50)
        XCTAssertEqual(top.first?.logicalSize, 199)
        XCTAssertEqual(top.last?.logicalSize, 150)

        var ties: [StorageScanFile] = []
        for candidate in [file("zeta", 10), file("alpha", 10), file("beta", 10)] {
            StorageScanRules.insert(candidate, into: &ties, limit: 50)
        }
        XCTAssertEqual(ties.map(\.relativePath), ["alpha", "beta", "zeta"])
    }

    func testTopFileLimitCanBeZero() {
        var top = [file("already-present", 5)]
        StorageScanRules.insert(file("a", 1), into: &top, limit: 0)
        XCTAssertTrue(top.isEmpty)
    }

    func testEmptyScanProducesAnEmptyCompletedResult() {
        let result = StorageScanAccumulator().result(status: .completed)
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.visitedEntries, 0)
        XCTAssertEqual(result.fileCount, 0)
        XCTAssertEqual(result.logicalBytes, 0)
        XCTAssertTrue(result.largestFiles.isEmpty)
        XCTAssertFalse(result.didOverflow)
    }

    func testLogicalBytesAndFileCountAccumulateWithoutDirectorySizes() {
        var accumulator = StorageScanAccumulator()
        accumulator.include(file("folder/a.txt", 12))
        accumulator.include(file("folder/nested/b.txt", 30))
        let result = accumulator.result(status: .completed)
        XCTAssertEqual(result.logicalBytes, 42)
        XCTAssertEqual(result.fileCount, 2)
        XCTAssertEqual(result.status, .completed)
    }

    func testOverflowSaturatesAndMarksTheResultPartial() {
        var accumulator = StorageScanAccumulator()
        accumulator.include(file("large-a", Int64.max))
        accumulator.include(file("large-b", 1))
        let result = accumulator.result(status: .completed)
        XCTAssertEqual(result.logicalBytes, Int64.max)
        XCTAssertTrue(result.didOverflow)
        XCTAssertEqual(result.status, .partial)
    }

    func testSkippedEntriesMakeCompletedScanPartialButKeepCancelledStatus() {
        var accumulator = StorageScanAccumulator()
        accumulator.skipEntry()
        XCTAssertEqual(accumulator.result(status: .completed).status, .partial)
        XCTAssertEqual(accumulator.result(status: .cancelled).status, .cancelled)
    }

    func testNegativeFileSizeIsSkippedInsteadOfReducingTotal() {
        var accumulator = StorageScanAccumulator()
        accumulator.include(file("bad", -1))
        let result = accumulator.result(status: .completed)
        XCTAssertEqual(result.logicalBytes, 0)
        XCTAssertEqual(result.fileCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.status, .partial)
    }

    func testSecondPathToAHardLinkedFileIsVisitedButNotCountedAgain() {
        var accumulator = StorageScanAccumulator()
        let id = StorageScanAccumulator.HardLinkID(device: 1, inode: 42)
        accumulator.include(file("a/big.bin", 100), hardLink: id)
        accumulator.include(file("b/big.bin", 100), hardLink: id)
        accumulator.include(file("c/other.bin", 7), hardLink: .init(device: 2, inode: 42))
        accumulator.include(file("d/plain.bin", 3), hardLink: nil)
        let result = accumulator.result(status: .completed)
        XCTAssertEqual(result.visitedEntries, 4)
        XCTAssertEqual(result.fileCount, 3)
        XCTAssertEqual(result.logicalBytes, 110)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.largestFiles.map(\.relativePath), ["a/big.bin", "c/other.bin", "d/plain.bin"])
    }

    func testAscendingInputKeepsOnlyTheLargestFiles() {
        var top: [StorageScanFile] = []
        for index in 0..<120 { StorageScanRules.insert(file("f\(index)", Int64(index)), into: &top, limit: 50) }
        XCTAssertEqual(top.count, 50)
        XCTAssertEqual(top.first?.logicalSize, 119)
        XCTAssertEqual(top.last?.logicalSize, 70)
    }
}
