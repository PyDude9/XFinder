import XCTest

final class BrowserDownloadsRulesTests: XCTestCase {
    private func entry(_ name: String, modified: TimeInterval, hidden: Bool = false) -> DirectoryEntry {
        DirectoryEntry(name: name, path: "/Downloads/" + name, kind: .file, isPackage: false,
                       isHidden: hidden, size: 0, modified: Date(timeIntervalSince1970: modified),
                       created: Date(timeIntervalSince1970: 0), volumeID: 0)
    }
    func testNewestTwentyExcludeHiddenBeforeApplyingLimit() {
        let items = (0..<30).map { entry(String(format: "%02d", $0), modified: Double($0)) }
            + [entry(".hidden", modified: 100, hidden: true)]
        let result = BrowserDownloadsRules.recent(items)
        XCTAssertEqual(result.count, 20)
        XCTAssertEqual(result.first?.name, "29")
        XCTAssertEqual(result.last?.name, "10")
        XCTAssertFalse(result.contains { $0.isHidden })
    }
    func testEqualDatesHaveStablePathOrderRegardlessOfInput() {
        let a = entry("a", modified: 1), b = entry("b", modified: 1)
        XCTAssertEqual(BrowserDownloadsRules.recent([b, a]).map(\.path), [a.path, b.path])
        XCTAssertEqual(BrowserDownloadsRules.recent([a, b]).map(\.path), [a.path, b.path])
    }
    func testEmptyAndHiddenOnlyProduceEmptyTray() {
        XCTAssertTrue(BrowserDownloadsRules.recent([]).isEmpty)
        XCTAssertTrue(BrowserDownloadsRules.recent([entry(".hidden", modified: 1, hidden: true)]).isEmpty)
    }
    func testGlobalChordHasNoFixedOrCaptureDefaultCollision() throws {
        let downloads = try XCTUnwrap(ShortcutCatalog.fixedEntries.first { $0.id == "browser.downloads" })
        XCTAssertEqual(downloads.chord, ShortcutCatalog.Chord(keyCode: 2, modifiers: [.control, .option, .command]))
        XCTAssertEqual(downloads.gateDefault, false)
        for other in ShortcutCatalog.fixedEntries where other.id != downloads.id {
            XCTAssertNotEqual(downloads.chord, other.chord, other.id)
        }
        for shortcut in CaptureRules.oneNotchPreset.values {
            XCTAssertNotEqual(downloads.chord, ShortcutCatalog.Chord(keyCode: UInt16(shortcut.keyCode),
                modifiers: ShortcutCatalog.Modifiers(nsEventRaw: shortcut.modifiers)))
        }
    }
}
