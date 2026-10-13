import XCTest
import Foundation

/// F1 — junk cleanup on a REAL folder tree in a temp directory. Nothing here touches the user's Trash: the mover is
/// injected and moves into a temp "Trash" folder.
final class JunkCleanupTests: XCTestCase {
    typealias J = JunkCleanup

    /// The measured header of a real AppleDouble file (`ditto --sequesterRsrc` + `unzip`, 2026-10-13).
    static let appleDouble = Data([0x00, 0x05, 0x16, 0x07, 0x00, 0x02, 0x00, 0x00]) + Data("Mac OS X        ".utf8) + Data(count: 64)

    var root: URL!
    var outside: URL!
    var trashBin: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("xf-junk-\(UUID().uuidString)")
        root = base.appendingPathComponent("Project")
        outside = base.appendingPathComponent("Outside")
        trashBin = base.appendingPathComponent("Trash")
        for d in [root!, outside!, trashBin!, root.appendingPathComponent("sub"), root.appendingPathComponent("__MACOSX/sub"),
                  root.appendingPathComponent("zips/__MACOSX"), root.appendingPathComponent("Tool.app/Contents"),
                  root.appendingPathComponent(".fseventsd")] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        func put(_ rel: String, _ data: Data, in dir: URL? = nil) throws { try data.write(to: (dir ?? root).appendingPathComponent(rel)) }
        try put(".DS_Store", Data(count: 6148))
        try put("photo.jpg", Data("jpeg".utf8))
        try put("._photo.jpg", Self.appleDouble)
        try put("._data.bin", Data("not apple double, someone's real file".utf8))
        try put("Thumbs.db", Data(count: 1024))
        try put("sub/desktop.ini", Data("[.ShellClassInfo]".utf8))
        try put("__MACOSX/sub/._photo.jpg", Self.appleDouble)
        try put("__MACOSX/.DS_Store", Data(count: 10))
        try put("zips/__MACOSX/real.txt", Data("a real file in an odd folder".utf8))
        try put("Tool.app/Contents/.DS_Store", Data(count: 10))
        try put(".fseventsd/.DS_Store", Data(count: 10))
        try put(".DS_Store", Data(count: 10), in: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func names(_ items: [J.Item]) -> [String] {
        items.map { J.relativePath($0.url, root: root) }.sorted()
    }

    func testOnlyKnownMetadataIsFound() {
        let r = J.scan(root)
        XCTAssertEqual(names(r.items), [".DS_Store", "._photo.jpg", "Thumbs.db", "__MACOSX", "sub/desktop.ini"])
        XCTAssertFalse(r.truncated)
        XCTAssertFalse(r.cancelled)
        XCTAssertGreaterThanOrEqual(r.skippedPackages, 1, "Tool.app is a package: its inside is never walked")
    }

    func testANameAloneIsNotEnoughForAppleDouble() {
        let r = J.scan(root)
        XCTAssertFalse(names(r.items).contains("._data.bin"), "no 00 05 16 07 header ⇒ someone's file, not metadata")
        XCTAssertTrue(J.isAppleDouble(header: Self.appleDouble))
        XCTAssertFalse(J.isAppleDouble(header: Data([0x00, 0x05, 0x16])))
        XCTAssertFalse(J.isAppleDouble(header: Data([0x00, 0x05, 0x16, 0x00])), "AppleSingle is 00 05 16 00 — not ours")
    }

    func testLinksSystemFoldersPackagesAndOddMacosxFoldersAreLeftAlone() {
        let found = names(J.scan(root).items)
        XCTAssertFalse(found.contains { $0.hasPrefix("link") }, "a symlink is never followed")
        XCTAssertFalse(found.contains { $0.hasPrefix(".fseventsd") })
        XCTAssertFalse(found.contains { $0.hasPrefix("Tool.app") })
        XCTAssertFalse(found.contains { $0.hasPrefix("zips") }, "a __MACOSX holding a real file is not junk")
        XCTAssertEqual(J.macosxFolderBytes(root.appendingPathComponent("__MACOSX")), Int64(Self.appleDouble.count + 10))
        XCTAssertNil(J.macosxFolderBytes(root.appendingPathComponent("zips/__MACOSX")))
    }

    func testNamesAreCaseInsensitiveLikeTheDisk() {
        XCTAssertEqual(J.candidate(name: "THUMBS.DB", isDirectory: false), .windowsThumbs)
        XCTAssertEqual(J.candidate(name: "Desktop.ini", isDirectory: false), .desktopIni)
        XCTAssertEqual(J.candidate(name: ".ds_store", isDirectory: false), .dsStore)
        XCTAssertNil(J.candidate(name: ".DS_Store", isDirectory: true), "a folder by that name is not Finder's file")
        XCTAssertNil(J.candidate(name: "._", isDirectory: false))
        XCTAssertNil(J.candidate(name: "__macosx", isDirectory: true), "only the exact name zip tools write")
        XCTAssertNil(J.candidate(name: "notes.tmp", isDirectory: false), "generic temporary files are never selected")
    }

    func testMovingToTheTrashKeepsEverythingElse() throws {
        let r = J.scan(root)
        let out = J.moveToTrash(r.items) { url in
            try FileManager.default.moveItem(at: url, to: self.trashBin.appendingPathComponent(UUID().uuidString + url.lastPathComponent))
        }
        XCTAssertEqual(out.trashed.count, 5)
        XCTAssertEqual(out.changed, 0)
        XCTAssertTrue(out.failed.isEmpty)
        let fm = FileManager.default
        for kept in ["photo.jpg", "._data.bin", "zips/__MACOSX/real.txt", "Tool.app/Contents/.DS_Store", ".fseventsd/.DS_Store"] {
            XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent(kept).path), "kept: \(kept)")
        }
        XCTAssertTrue(fm.fileExists(atPath: outside.appendingPathComponent(".DS_Store").path), "never reached through the link")
        XCTAssertTrue(J.scan(root).items.isEmpty, "nothing left to clean")
    }

    func testAnItemThatChangedSinceThePreviewIsSkipped() throws {
        let r = J.scan(root)
        try Data("now a real file".utf8).write(to: root.appendingPathComponent("._photo.jpg"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("Thumbs.db"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Thumbs.db"), withDestinationURL: outside)
        var moved: [String] = []
        let out = J.moveToTrash(r.items) { moved.append($0.lastPathComponent); try FileManager.default.removeItem(at: $0) }
        XCTAssertEqual(out.changed, 2, "lost its header; became a link")
        XCTAssertEqual(Set(moved), [".DS_Store", "desktop.ini", "__MACOSX"])
    }

    func testAFailedMoveIsReportedNotHidden() {
        let r = J.scan(root)
        let out = J.moveToTrash(r.items) { _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertEqual(out.trashed.count, 0)
        XCTAssertEqual(out.failed.count, 5)
    }

    func testCancelAndLimit() {
        let cancelled = J.scan(root, isCancelled: { true })
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertTrue(cancelled.items.isEmpty)
        let limited = J.scan(root, limit: 3)
        XCTAssertTrue(limited.truncated, "the page must say the list is partial")
        XCTAssertFalse(J.scan(root.appendingPathComponent("link")).truncated, "a linked root is refused, not walked")
        XCTAssertTrue(J.scan(root.appendingPathComponent("link")).items.isEmpty)
    }

    func testGroupsFollowTheKindOrder() {
        let g = J.groups(J.scan(root).items)
        XCTAssertEqual(g.map(\.kind), [.dsStore, .appleDouble, .macosxFolder, .windowsThumbs, .desktopIni])
        XCTAssertEqual(g.first?.bytes, 6148)
        XCTAssertEqual(g.map(\.count), [1, 1, 1, 1, 1])
    }

    func testEveryKindStringIsTranslated() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = (root["entries"] as? [String: Any]) ?? root
        let keys = J.Kind.allCases.flatMap { [$0.titleKey, $0.explanationKey] }
        XCTAssertEqual(keys.count, 10)
        for k in keys {
            XCTAssertFalse(((entries[k] as? [String: Any])?["en"] as? String ?? "").isEmpty, "missing English for \(k)")
        }
    }
}
