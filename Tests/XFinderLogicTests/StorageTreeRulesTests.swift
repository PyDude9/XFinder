import XCTest

final class StorageTreeRulesTests: XCTestCase {
    func testTopTwentyAndAggregate() {
        var builder = StorageTreeBuilder(name: "root")
        builder.directory("folder")
        for n in 1...30 { builder.file(.init(name: "f\(n)", relativePath: "folder/f\(n)", logicalSize: Int64(n))) }
        let tree = builder.finish()
        XCTAssertEqual(tree.nodes[0].bytes, 465)
        XCTAssertEqual(tree.nodes[0].fileCount, 30)
        let folder = tree.nodes.first { $0.path == "folder" && $0.isDirectory }!
        XCTAssertEqual(folder.children.count, 21)
        XCTAssertEqual(folder.children.filter { tree.nodes[$0].isAggregate }.map { tree.nodes[$0].bytes }, [55])
        XCTAssertEqual(tree.nodes[folder.children[0]].bytes, 55)
    }
    func testCapFoldsIntoAncestorWithExactTotals() {
        var builder = StorageTreeBuilder(name: "root", limit: 6)
        for n in 0..<100 { builder.directory("d\(n)"); builder.file(.init(name: "f", relativePath: "d\(n)/f", logicalSize: 10)) }
        let tree = builder.finish()
        XCTAssertLessThanOrEqual(tree.nodes.count, 6)
        XCTAssertEqual(tree.nodes[0].bytes, 1000)
        XCTAssertEqual(tree.nodes[0].fileCount, 100)
        XCTAssertTrue(tree.simplified)
    }
    func testOverflowAndEmpty() {
        XCTAssertEqual(StorageTreeBuilder.sum(Int64.max, 1), Int64.max)
        var empty = StorageTreeBuilder(name: "root")
        XCTAssertEqual(empty.finish().nodes[0].children, [])
        empty.recordSkippedEntry()
        XCTAssertTrue(empty.finish().nodes[0].skipped)
    }
    func testHundredThousandNodeBound() {
        var builder = StorageTreeBuilder(name: "root")
        for n in 0..<100_000 { builder.directory("d\(n)"); builder.file(.init(name: "f", relativePath: "d\(n)/f", logicalSize: 1)) }
        let tree = builder.finish()
        XCTAssertLessThanOrEqual(tree.nodes.count, 100_000)
        XCTAssertEqual(tree.nodes[0].bytes, 100_000)
        XCTAssertEqual(tree.nodes[0].fileCount, 100_000)
    }
}
