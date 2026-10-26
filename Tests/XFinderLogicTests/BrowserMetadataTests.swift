import XCTest

@MainActor final class BrowserMetadataTests: XCTestCase {
    private func fixture() -> MetadataStore {
        MetadataStore(databaseURL: URL(fileURLWithPath: "/tmp/xfinder-metadata-tests-\(UUID().uuidString)/metadata.sqlite"))
    }

    private func eventually(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true within three seconds", file: file, line: line)
    }

    func testLoadIncludesEmojiOnlyChildrenAndCanonicalPaths() async {
        let store = fixture()
        let folder = "/Mã_%"
        let child = folder + "/Café"
        await store.setEmoji("📁", for: child)
        await store.setEmoji("🌳", for: folder)
        await store.setEmoji("🔥", for: child + "/nested")
        await store.setEmoji("⭐️", for: "/Mã_%other/wrong")
        await store.setNickname("  Work  ", for: folder + "/notes")
        await store.setPins([child], in: folder)
        let metadata = BrowserMetadata(store: store)
        metadata.load(folder: folder.decomposedStringWithCanonicalMapping + "//")
        await eventually { metadata.emoji(for: child) == "📁" && metadata.nickname(for: folder + "/notes") == "Work" }
        XCTAssertEqual(metadata.emoji(for: folder), "🌳")
        XCTAssertNil(metadata.emoji(for: child + "/nested"))
        XCTAssertNil(metadata.emoji(for: "/Mã_%other/wrong"))
        XCTAssertEqual(metadata.pins(in: folder), [child])
        let rootEmoji = await store.emoji(in: "/")
        XCTAssertEqual(rootEmoji[folder], "🌳")
        XCTAssertNil(rootEmoji[child])
    }

    func testMutationsAreImmediateOrderedAndPersisted() async {
        let store = fixture()
        let metadata = BrowserMetadata(store: store)
        metadata.setNickname("First", for: "/f/a")
        metadata.setNickname("Last", for: "/f/a")
        metadata.setEmoji("📁", for: "/f")
        metadata.togglePin("/f/a", in: "/f")
        XCTAssertEqual(metadata.nickname(for: "/f/a"), "Last")
        XCTAssertEqual(metadata.emoji(for: "/f"), "📁")
        XCTAssertEqual(metadata.pins(in: "/f"), ["/f/a"])
        await eventually { await store.nickname(for: "/f/a") == "Last" }
        await eventually { await store.pins(in: "/f") == ["/f/a"] }
        metadata.load(folder: "/f")
        await eventually { metadata.nickname(for: "/f/a") == "Last" && metadata.emoji(for: "/f") == "📁" }
        metadata.setNickname(nil, for: "/f/a")
        metadata.setEmoji("invalid", for: "/f")
        metadata.togglePin("/f/a", in: "/f")
        XCTAssertNil(metadata.nickname(for: "/f/a"))
        XCTAssertNil(metadata.emoji(for: "/f"))
        XCTAssertTrue(metadata.pins(in: "/f").isEmpty)
        await eventually { await store.pins(in: "/f").isEmpty }
        let name = await store.nickname(for: "/f/a")
        XCTAssertNil(name)
    }

    func testCatalogVisibilitySelectionsAndLiveGroups() async {
        let store = fixture()
        var catalog = PropertyCatalog()
        let property = catalog.add(name: "Status")
        let option = catalog.addOption(property.id, title: "Ready", color: .green)!
        await store.saveCatalog(catalog)
        await store.select(path: "/other/z", property: property.id, option: option.id)
        await store.setNickname("Alpha", for: "/other/z")
        await store.setFolderProperties("/f", [(property.id, true)])
        let metadata = BrowserMetadata(store: store)
        metadata.load(folder: "/f")
        await eventually { metadata.visibleProperties(in: "/f").count == 1 }
        let refs = [LiveGroupRef(propertyID: property.id, optionID: option.id)]
        XCTAssertEqual(metadata.liveGroups(refs).first?.paths, ["/other/z"])
        metadata.select(path: "/f/a", property: property.id, option: option.id)
        XCTAssertEqual(metadata.option(for: "/f/a", property: property.id), option)
        XCTAssertEqual(metadata.liveGroups(refs).first?.paths.count, 2)
        metadata.setFolderProperties("/f", [(property.id, false), (property.id, true)])
        XCTAssertEqual(metadata.shownProperties(in: "/f").count, 1)
        XCTAssertTrue(metadata.visibleProperties(in: "/f").isEmpty)
        metadata.updateCatalog { $0.removeOption(property.id, option: option.id) }
        XCTAssertNil(metadata.option(for: "/f/a", property: property.id))
        XCTAssertTrue(metadata.liveGroups(refs).isEmpty)
        await eventually { await store.catalog().definition(property.id)?.options.isEmpty == true }
        let saved = await store.selections(property: property.id)
        XCTAssertTrue(saved.isEmpty)
    }

    func testMoveAndRemoveRewriteDescendantsButNotSiblings() async {
        let store = fixture()
        await store.setNickname("Keep", for: "/f/ab")
        await store.setNickname("Child", for: "/f/a/child")
        await store.setEmoji("📁", for: "/f/a")
        await store.setPins(["/f/a", "/f/a/child", "/f/ab"], in: "/f")
        let metadata = BrowserMetadata(store: store)
        metadata.load(folder: "/f")
        await eventually { metadata.pins(in: "/f").count == 3 }
        metadata.addRelation("/f/a", "/other")
        metadata.itemMoved(from: "/f/a", to: "/new")
        XCTAssertEqual(metadata.nickname(for: "/new/child"), "Child")
        XCTAssertNil(metadata.nickname(for: "/f/a/child"))
        XCTAssertEqual(metadata.emoji(for: "/new"), "📁")
        XCTAssertEqual(metadata.related(to: "/new"), ["/other"])
        XCTAssertEqual(metadata.pins(in: "/f"), ["/new", "/new/child", "/f/ab"])
        metadata.itemRemoved("/new")
        XCTAssertNil(metadata.nickname(for: "/new/child"))
        XCTAssertEqual(metadata.nickname(for: "/f/ab"), "Keep")
        XCTAssertEqual(metadata.pins(in: "/f"), ["/f/ab"])
        XCTAssertTrue(metadata.related(to: "/other").isEmpty)
        await eventually { await store.pins(in: "/f") == ["/f/ab"] }
    }

    func testRepeatedAndCoalescedLoadsDoNotBumpRevision() async {
        let store = fixture()
        await store.setPins(["/f/a"], in: "/f")
        let metadata = BrowserMetadata(store: store)
        for _ in 0..<20 { metadata.load(folder: "/f") }
        await eventually { metadata.pins(in: "/f") == ["/f/a"] }
        let revision = metadata.revision
        for _ in 0..<20 { metadata.load(folder: "/f/") }
        // Unchanged loads deliberately do not publish a completion revision.
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(metadata.revision, revision)
    }

    func testMutationsBeforeBootstrapPreservePersistedData() async {
        let store = fixture()
        var original = PropertyCatalog()
        let existing = original.add(name: "Existing")
        await store.saveCatalog(original)
        await store.setPins(["/f/old"], in: "/f")
        await store.setRelations([FolderRelation(id: UUID(), a: "/f", b: "/old")])
        await store.setNickname("Stored", for: "/f/old")
        let metadata = BrowserMetadata(store: store)
        metadata.load(folder: "/f")
        metadata.togglePin("/f/new", in: "/f")
        metadata.addRelation("/f", "/new")
        metadata.updateCatalog { _ = $0.add(name: "Added") }
        metadata.setNickname("Edited", for: "/f/new")
        await eventually { await store.catalog().definitions.count == 2 }
        await eventually { metadata.catalog.definitions.count == 2 && metadata.pins(in: "/f").count == 2 }
        XCTAssertNotNil(metadata.catalog.definition(existing.id))
        XCTAssertEqual(metadata.nickname(for: "/f/old"), "Stored")
        XCTAssertEqual(metadata.nickname(for: "/f/new"), "Edited")
        XCTAssertEqual(Set(metadata.related(to: "/f")), Set(["/old", "/new"]))
        let savedPins = await store.pins(in: "/f")
        XCTAssertEqual(savedPins, ["/f/old", "/f/new"])
    }

    func testPressureKeepsEightMostRecentlyLoadedFolders() async {
        let store = fixture()
        for index in 0..<10 { await store.setPins(["/f\(index)/a"], in: "/f\(index)") }
        let metadata = BrowserMetadata(store: store)
        for index in 0..<10 { metadata.load(folder: "/f\(index)") }
        await eventually { metadata.pins(in: "/f9").count == 1 }
        metadata.relieve(PressureRules.warningPlan)
        XCTAssertTrue(metadata.pins(in: "/f0").isEmpty)
        XCTAssertTrue(metadata.pins(in: "/f1").isEmpty)
        for index in 2..<10 { XCTAssertEqual(metadata.pins(in: "/f\(index)"), ["/f\(index)/a"]) }
    }
}
