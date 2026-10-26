import XCTest

/// XF-T32 W1 review fixes (verifier findings on properties, pins, store, spaces).
final class XFT32W1ReviewTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("xf-w1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func store() -> MetadataStore {
        MetadataStore(databaseURL: directory.appendingPathComponent("metadata.sqlite"))
    }

    // MARK: Properties

    func testToneMarksKeepPropertyNamesDistinctButNFDEqualsNFC() {
        var catalog: PropertyCatalog = PropertyCatalog()
        XCTAssertEqual(catalog.add(name: "Ma").name, "Ma")
        XCTAssertEqual(catalog.add(name: "Mã").name, "Mã")
        XCTAssertEqual(catalog.add(name: "Má").name, "Má")
        XCTAssertEqual(catalog.add(name: "mã").name, "mã 2", "case alone is still a duplicate")
        let nfd: String = "Tra\u{0300}"
        XCTAssertEqual(catalog.add(name: "Trà").name, "Trà")
        XCTAssertEqual(catalog.add(name: nfd).name, nfd + " 2", "NFD spelling of the same word is a duplicate")
    }

    // MARK: Nicknames

    func testNicknameIsStoredNFCAndSearchKeyMatchesBothForms() {
        let nfd: String = "Ba\u{0301}o ca\u{0301}o"
        let normalized: String? = NicknameRules.normalized(nfd)
        XCTAssertEqual(normalized.map { Array($0.utf8) }, Array("Báo cáo".utf8))
        XCTAssertEqual(NicknameRules.searchKey(name: "a.txt", nickname: nfd),
                       NicknameRules.searchKey(name: "a.txt", nickname: "Báo cáo"))
    }

    func testSearchKeySeparatorIsNULSoANewlineInANameCannotBridgeTheFields() {
        let key: [UInt8] = NicknameRules.searchKey(name: "ab", nickname: "cd")
        XCTAssertEqual(key.filter { $0 == 0 }.count, 1)
        XCTAssertFalse(key.contains(0x0A))
    }

    // MARK: Store

    func testStoreKeysAreNFCAndCollapsedSoEitherSpellingFindsTheRow() async {
        let db: MetadataStore = store()
        let nfd: String = "/Users/u/Ta\u{0300}i lie\u{0323}\u{0302}u//a.txt"
        await db.setNickname("Hợp đồng", for: nfd)
        let viaNFC: String? = await db.nickname(for: "/Users/u/Tài liệu/a.txt")
        XCTAssertEqual(viaNFC, "Hợp đồng")
        let inFolder: [String: String] = await db.nicknames(in: "/Users/u/Tài liệu/")
        XCTAssertEqual(inFolder.count, 1)
        XCTAssertEqual(inFolder["/Users/u/Ta\u{0300}i lie\u{0323}\u{0302}u/a.txt"], "Hợp đồng",
                       "Swift String keys compare canonically, so an NFD listing path still finds the NFC key")
        XCTAssertEqual(MetadataStore.normalized("//"), "/")
        XCTAssertEqual(MetadataStore.normalized(""), "")
        XCTAssertEqual(MetadataStore.normalized("/a//b///"), "/a/b")
    }

    func testStoreNormalizesNicknameAndRejectsNonEmojiText() async {
        let db: MetadataStore = store()
        await db.setNickname("  hai\n\tdòng  ", for: "/x/a")
        let nickname: String? = await db.nickname(for: "/x/a")
        XCTAssertEqual(nickname, "hai dòng")
        await db.setEmoji("🚀", for: "/x")
        let rocket: String? = await db.emoji(for: "/x")
        XCTAssertEqual(rocket, "🚀")
        await db.setEmoji("abc", for: "/x")
        let cleared: String? = await db.emoji(for: "/x")
        XCTAssertNil(cleared, "text that is not one emoji clears instead of being stored")
    }

    func testSaveCatalogOnlyPurgesWhatTheSaveRemoved() async throws {
        let db: MetadataStore = store()
        var catalog: PropertyCatalog = PropertyCatalog()
        let status: PropertyDefinition = catalog.add(name: "Trạng thái")
        let done: PropertyOption = try XCTUnwrap(catalog.addOption(status.id, title: "Xong", color: .green))
        let todo: PropertyOption = try XCTUnwrap(catalog.addOption(status.id, title: "Chưa", color: .red))
        await db.saveCatalog(catalog)
        await db.select(path: "/p/a", property: status.id, option: done.id)
        await db.select(path: "/p/b", property: status.id, option: todo.id)
        // A selection whose property the stored catalog never knew (newer build, damaged row) must survive.
        let foreign: UUID = UUID(), foreignOption: UUID = UUID()
        await db.select(path: "/p/c", property: foreign, option: foreignOption)

        catalog.removeOption(status.id, option: todo.id)
        await db.saveCatalog(catalog)
        let kept: [String: UUID] = await db.selections(property: status.id)
        XCTAssertEqual(kept, ["/p/a": done.id], "only the removed option's selection goes")
        let foreignKept: [String: UUID] = await db.selections(property: foreign)
        XCTAssertEqual(foreignKept, ["/p/c": foreignOption])

        catalog.delete(status.id)
        await db.saveCatalog(catalog)
        let afterDelete: [String: UUID] = await db.selections(property: status.id)
        XCTAssertTrue(afterDelete.isEmpty)
        let foreignStill: [String: UUID] = await db.selections(property: foreign)
        XCTAssertEqual(foreignStill.count, 1)
    }

    // MARK: Spaces

    func testBrokenSidebarResetsOnlyTheSidebarAndBlankNameGetsTheDefault() throws {
        let id: UUID = UUID(), workspace: UUID = UUID()
        let json: [String: Any] = [
            "schemaVersion": 1,
            "activeID": id.uuidString,
            "spaces": [["id": id.uuidString, "name": "   ", "sidebar": "not an object",
                        "workspaceIDs": [workspace.uuidString]]]
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: json)
        let decoded: SpaceStore = SpaceStore.decode(data, fallbackLayout: SidebarLayout())
        XCTAssertEqual(decoded.spaces.count, 1)
        XCTAssertEqual(decoded.spaces.first?.id, id, "the Space survives, not the fallback migration")
        XCTAssertEqual(decoded.spaces.first?.name, SpaceStore.defaultNewSpaceName)
        XCTAssertEqual(decoded.spaces.first?.workspaceIDs, [workspace])
        XCTAssertEqual(decoded.activeID, id)
    }
}
