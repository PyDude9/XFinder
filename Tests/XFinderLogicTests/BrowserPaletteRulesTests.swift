import XCTest

final class BrowserPaletteRulesTests: XCTestCase {
    private func item(_ id: String, _ title: String, kind: BrowserPaletteRules.Kind = .location, aliases: [String] = []) -> BrowserPaletteRules.Item {
        .init(id: id, title: title, subtitle: "", target: id, kind: kind, aliases: aliases)
    }
    func testUsageRanksTiesButNotBetterMatches() {
        let items = [item("a", "Alpha"), item("b", "Alpha"), item("c", "A l p h a")]
        XCTAssertEqual(BrowserPaletteRules.rank(query: "", items: items, usage: ["b": 5], destinationsOnly: false).map(\.id), ["b", "a", "c"])
        XCTAssertEqual(BrowserPaletteRules.rank(query: "Alpha", items: items, usage: ["c": 100], destinationsOnly: false).map(\.id), ["a", "b", "c"])
    }
    func testModesAliasAndStableOrder() {
        let items = [item("folder", "Project", aliases: ["biệt danh"]), item("cmd", "Rename", kind: .command), item("move", "Move", kind: .move)]
        XCTAssertEqual(BrowserPaletteRules.rank(query: "biet danh", items: items, usage: [:], destinationsOnly: false).map(\.id), ["folder"])
        XCTAssertEqual(BrowserPaletteRules.rank(query: ">", items: items, usage: [:], destinationsOnly: false).map(\.id), ["cmd", "move"])
        XCTAssertEqual(BrowserPaletteRules.rank(query: "", items: items, usage: [:], destinationsOnly: true).map(\.id), ["folder"])
    }
    func testCorruptUsageAndBoundedHistory() throws {
        XCTAssertTrue(BrowserPaletteRules.usage(Data("bad".utf8)).isEmpty)
        let original = try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: (0..<600).map { ("id\($0)", 1) }))
        let result = BrowserPaletteRules.usage(BrowserPaletteRules.recording("chosen", in: original))
        XCTAssertEqual(result.count, 512); XCTAssertEqual(result["chosen"], 1)
    }
    func testExplicitCmdKOverrideKeepsOwnership() {
        var keys = KeyBindings()
        keys.overrides[BrowserCommand.connectToServer.rawValue] = .init(primary: KeyChord("k", command: true), extra: nil)
        XCTAssertEqual(keys.command(for: KeyChord("k", command: true)), .connectToServer)
        XCTAssertNil(keys.binding(for: .quickOpen).primary)
        XCTAssertEqual(keys.command(for: KeyChord("p", command: true, control: true)), .quickOpen)
    }
    func testDefaultShortcutAndAliasRespectOverrides() {
        var keys = KeyBindings()
        XCTAssertEqual(keys.command(for: KeyChord("k", command: true)), .quickOpen)
        XCTAssertEqual(keys.command(for: KeyChord("p", command: true, control: true)), .quickOpen)
        keys.overrides[BrowserCommand.quickOpen.rawValue] = .empty
        XCTAssertNil(keys.command(for: KeyChord("k", command: true)))
        XCTAssertNil(keys.command(for: KeyChord("p", command: true, control: true)))
    }
}
