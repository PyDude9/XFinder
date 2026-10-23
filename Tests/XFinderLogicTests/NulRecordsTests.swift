import XCTest

/// `mdfind -0` output read in chunks, stopping at a limit (2026-10-23: a broad query read 134 MB to show 50 rows).
final class NulRecordsTests: XCTestCase {
    func feed(_ text: String, chunks: Int, limit: Int) -> NulRecords {
        let bytes = Array(text.utf8)
        var r = NulRecords(limit: limit)
        let size = max(1, (bytes.count + chunks - 1) / chunks)
        var i = 0
        while i < bytes.count { r.append(Data(bytes[i..<min(i + size, bytes.count)])); i += size }
        r.finish()
        return r
    }

    func testRecordsSplitAcrossChunksAreWhole() {
        let out = "/a/ảnh một.png\0/b/two\0/c/three\0"
        for chunks in 1...out.utf8.count {
            let r = feed(out, chunks: chunks, limit: 10)
            XCTAssertEqual(r.records, ["/a/ảnh một.png", "/b/two", "/c/three"], "chunks \(chunks)")
            XCTAssertFalse(r.truncated)
        }
    }

    func testStopsAtTheLimitAndSaysThereWasMore() {
        let r = feed("1\02\03\04\0", chunks: 1, limit: 2)
        XCTAssertEqual(r.records, ["1", "2"])
        XCTAssertTrue(r.isFull)
        XCTAssertTrue(r.truncated)
    }

    func testExactlyTheLimitIsNotTruncated() {
        for chunks in 1...4 {
            let r = feed("1\02\0", chunks: chunks, limit: 2)
            XCTAssertEqual(r.records, ["1", "2"])
            XCTAssertFalse(r.truncated, "chunks \(chunks)")
        }
    }

    func testMoreArrivingAfterFullIsTruncated() {
        var r = NulRecords(limit: 1)
        r.append(Data("1\0".utf8))
        XCTAssertFalse(r.truncated)
        r.append(Data("2".utf8))
        XCTAssertTrue(r.truncated)
        r.finish()
        XCTAssertEqual(r.records, ["1"])
    }

    func testALastRecordWithoutItsNulCounts() {
        XCTAssertEqual(feed("1\02", chunks: 1, limit: 5).records, ["1", "2"])
        let full = feed("1\02", chunks: 1, limit: 1)
        XCTAssertEqual(full.records, ["1"])
        XCTAssertTrue(full.truncated)
    }

    func testEmptyRecordsAndEmptyOutput() {
        XCTAssertEqual(feed("\0\01\0\0", chunks: 2, limit: 5).records, ["1"])
        XCTAssertEqual(feed("", chunks: 1, limit: 5).records, [])
        let none = feed("1\0", chunks: 1, limit: 0)
        XCTAssertEqual(none.records, [])
        XCTAssertTrue(none.truncated)
    }
}
