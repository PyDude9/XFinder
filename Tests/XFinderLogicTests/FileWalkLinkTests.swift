import XCTest
import Foundation

/// `FileWalk.walk(onLink:)` — a symbolic link is reported to `onLink` (never followed, never `onOther`) so callers such
/// as the Storage Analyzer do not label a complete scan "partial" just because the folder contains links.
final class FileWalkLinkTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("filewalk-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(count: 10).write(to: root.appendingPathComponent("sub/a.bin"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link-to-sub").path,
                                                   withDestinationPath: root.appendingPathComponent("sub").path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("dangling").path,
                                                   withDestinationPath: "/nonexistent-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testLinksGoToOnLinkAndAreNotFollowed() {
        var links = 0, others = 0, files: [String] = []
        _ = FileWalk.walk(root, limit: 100, onOther: { others += 1 }, onLink: { links += 1 }) { url, isDir, _ in
            if !isDir { files.append(url.lastPathComponent) }
            return .descend
        }
        XCTAssertEqual(links, 2)
        XCTAssertEqual(others, 0)
        XCTAssertEqual(files, ["a.bin"])
    }

    func testWithoutOnLinkLinksStillGoToOnOther() {
        var others = 0
        _ = FileWalk.walk(root, limit: 100, onOther: { others += 1 }) { _, _, _ in .descend }
        XCTAssertEqual(others, 2)
    }
}
