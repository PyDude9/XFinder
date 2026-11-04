import XCTest

final class SpaceModelTests: XCTestCase {

    // MARK: - Fixtures

    private func customLayout() -> SidebarLayout {
        var layout: SidebarLayout = SidebarLayout()
        layout.addItem(path: "/tmp/projects", toGroup: nil)
        let group: SidebarLayout.Group? = layout.addGroup(named: "Dự án")
        layout.addItem(path: "/tmp/a", toGroup: group?.id)
        layout.addItem(path: "/tmp/b", toGroup: group?.id)
        layout.hideVolume(uuid: "VOL-1")
        layout.moveTag("Red", toIndex: 0)
        if let first: SidebarLayout.Item = layout.favorites.first { layout.setDisplayName(first.id, to: "Nhà") }
        return layout
    }

    private func store(names: [String]) -> SpaceStore {
        var store: SpaceStore = SpaceStore.migrated(from: SidebarLayout())
        store.spaces[0].name = names[0]
        for name: String in names.dropFirst() { store.add(name: name, cloningSidebarFrom: nil) }
        return store
    }

    /// A fresh `SidebarLayout()` gets random item UUIDs, so "is a fresh default sidebar" compares paths and flags.
    private func assertFreshDefault(_ layout: SidebarLayout, file: StaticString = #filePath, line: UInt = #line) {
        let fresh: SidebarLayout = SidebarLayout()
        XCTAssertEqual(layout.favorites.map(\.path), fresh.favorites.map(\.path), file: file, line: line)
        XCTAssertTrue(layout.favorites.allSatisfy(\.isDefault), file: file, line: line)
        XCTAssertTrue(layout.groups.isEmpty, file: file, line: line)
        XCTAssertTrue(layout.hiddenVolumeUUIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(layout.userTagOrder.isEmpty, file: file, line: line)
    }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func spaceJSON(id: UUID, name: String) -> [String: Any] {
        ["id": id.uuidString, "name": name, "sidebar": ["favorites": [["path": "/tmp/x"]]],
         "liveGroups": [], "workspaceIDs": []]
    }

    // MARK: - migrated / active

    func testMigratedWrapsExistingLayoutInOnePersonalSpace() {
        let layout: SidebarLayout = customLayout()
        let store: SpaceStore = SpaceStore.migrated(from: layout)
        XCTAssertEqual(store.spaces.count, 1)
        XCTAssertEqual(store.spaces[0].name, "Cá nhân")
        XCTAssertEqual(store.spaces[0].sidebar, layout)
        XCTAssertEqual(store.activeID, store.spaces[0].id)
        XCTAssertEqual(store.schemaVersion, SpaceStore.currentSchemaVersion)
        XCTAssertEqual(store.active, store.spaces[0])
    }

    func testActiveWithOrphanIDFallsBackToFirst() {
        var store: SpaceStore = store(names: ["A", "B"])
        store.activeID = UUID()
        XCTAssertEqual(store.active.name, "A")
    }

    func testActiveWithEmptySpacesDoesNotTrap() {
        var store: SpaceStore = SpaceStore.migrated(from: SidebarLayout())
        store.spaces = []
        XCTAssertEqual(store.active.id, store.activeID)
        store.activateNext()
        store.activatePrevious()
        store.toggleLiveGroup(LiveGroupRef(propertyID: UUID(), optionID: UUID()))
        store.updateActiveSidebar { $0.hideVolume(uuid: "X") }
        store.move(from: 0, to: 1)
        XCTAssertTrue(store.spaces.isEmpty)
    }

    // MARK: - add

    func testAddAppendsWithoutActivatingAndUsesFreshSidebar() {
        var store: SpaceStore = SpaceStore.migrated(from: customLayout())
        let originalActive: UUID = store.activeID
        let added: Space = store.add(name: "  Công việc ", cloningSidebarFrom: nil)
        XCTAssertEqual(store.spaces.count, 2)
        XCTAssertEqual(store.spaces.last, added)
        XCTAssertEqual(added.name, "Công việc")
        assertFreshDefault(added.sidebar)
        XCTAssertTrue(added.liveGroups.isEmpty)
        XCTAssertTrue(added.workspaceIDs.isEmpty)
        XCTAssertNil(added.symbol)
        XCTAssertEqual(store.activeID, originalActive)
    }

    func testAddBlankNameBecomesSpace() {
        var store: SpaceStore = SpaceStore.migrated(from: SidebarLayout())
        XCTAssertEqual(store.add(name: "   \n", cloningSidebarFrom: nil).name, "Space")
        XCTAssertEqual(store.add(name: "", cloningSidebarFrom: nil).name, "Space 2")
        XCTAssertEqual(store.add(name: "space", cloningSidebarFrom: nil).name, "space 3")
    }

    func testAddDuplicateNameGetsNumberSuffixCaseAndNormalizationInsensitive() {
        var store: SpaceStore = store(names: ["Dự án"])
        let nfd: String = "Dự án".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(nfd.unicodeScalars), Array("Dự án".unicodeScalars))
        XCTAssertEqual(store.add(name: nfd, cloningSidebarFrom: nil).name, nfd + " 2")
        XCTAssertEqual(store.add(name: "DỰ ÁN", cloningSidebarFrom: nil).name, "DỰ ÁN 3")
    }

    func testAddCloningCopiesSidebarWithNewIDs() {
        let layout: SidebarLayout = customLayout()
        var store: SpaceStore = SpaceStore.migrated(from: layout)
        let source: UUID = store.spaces[0].id
        let clone: Space = store.add(name: "Copy", cloningSidebarFrom: source)
        let copied: SidebarLayout = clone.sidebar

        XCTAssertEqual(copied.favorites.map(\.path), layout.favorites.map(\.path))
        XCTAssertEqual(copied.favorites.map(\.displayName), layout.favorites.map(\.displayName))
        XCTAssertEqual(copied.favorites.map(\.isDefault), layout.favorites.map(\.isDefault))
        XCTAssertEqual(copied.groups.map(\.name), layout.groups.map(\.name))
        XCTAssertEqual(copied.groups.map { $0.items.map(\.path) }, layout.groups.map { $0.items.map(\.path) })
        XCTAssertEqual(copied.hiddenVolumeUUIDs, layout.hiddenVolumeUUIDs)
        XCTAssertEqual(copied.userTagOrder, layout.userTagOrder)

        let oldIDs: Set<UUID> = Set(layout.favorites.map(\.id) + layout.groups.map(\.id)
            + layout.groups.flatMap { $0.items.map(\.id) })
        let newIDs: [UUID] = copied.favorites.map(\.id) + copied.groups.map(\.id)
            + copied.groups.flatMap { $0.items.map(\.id) }
        XCTAssertEqual(newIDs.count, oldIDs.count)
        XCTAssertTrue(oldIDs.isDisjoint(with: newIDs))
        XCTAssertEqual(Set(newIDs).count, newIDs.count)
        XCTAssertEqual(store.spaces[0].sidebar, layout, "source untouched")
    }

    func testAddCloningUnknownIDGivesFreshSidebar() {
        var store: SpaceStore = SpaceStore.migrated(from: customLayout())
        assertFreshDefault(store.add(name: "X", cloningSidebarFrom: UUID()).sidebar)
    }

    func testAddCloningEmptyFavoritesStaysEmpty() {
        var layout: SidebarLayout = SidebarLayout()
        for item: SidebarLayout.Item in layout.favorites { layout.removeItem(item.id) }
        var store: SpaceStore = SpaceStore.migrated(from: layout)
        XCTAssertTrue(store.add(name: "X", cloningSidebarFrom: store.spaces[0].id).sidebar.favorites.isEmpty)
    }

    func testAddRepairsOrphanActiveID() {
        var store: SpaceStore = store(names: ["A"])
        store.activeID = UUID()
        store.add(name: "B", cloningSidebarFrom: nil)
        XCTAssertEqual(store.activeID, store.spaces[0].id)
    }

    // MARK: - rename

    func testRenameTrimsAndRefusesBlankUnknownAndDuplicate() {
        var store: SpaceStore = store(names: ["A", "B"])
        let a: UUID = store.spaces[0].id
        XCTAssertTrue(store.rename(a, to: "  Nhà "))
        XCTAssertEqual(store.spaces[0].name, "Nhà")
        XCTAssertFalse(store.rename(a, to: "   "))
        XCTAssertFalse(store.rename(UUID(), to: "Z"))
        XCTAssertFalse(store.rename(a, to: "b"))
        XCTAssertEqual(store.spaces[0].name, "Nhà")
        XCTAssertTrue(store.rename(a, to: "NHÀ"), "renaming to its own name in another case is allowed")
        XCTAssertEqual(store.spaces[0].name, "NHÀ")
    }

    // MARK: - delete

    func testNeverDeletesLastSpace() {
        var store: SpaceStore = SpaceStore.migrated(from: SidebarLayout())
        XCTAssertFalse(store.delete(store.activeID))
        XCTAssertEqual(store.spaces.count, 1)
    }

    func testDeleteUnknownIsRefused() {
        var store: SpaceStore = store(names: ["A", "B"])
        XCTAssertFalse(store.delete(UUID()))
        XCTAssertEqual(store.spaces.count, 2)
    }

    func testDeleteActiveOfTwoActivatesTheOther() {
        var store: SpaceStore = store(names: ["A", "B"])
        let b: UUID = store.spaces[1].id
        XCTAssertTrue(store.delete(store.spaces[0].id))
        XCTAssertEqual(store.activeID, b)
        XCTAssertEqual(store.spaces.map(\.name), ["B"])
    }

    func testDeleteActiveMiddleActivatesRightNeighbourAndLastActivatesLeft() {
        var store: SpaceStore = store(names: ["A", "B", "C"])
        XCTAssertTrue(store.activate(store.spaces[1].id))
        XCTAssertTrue(store.delete(store.spaces[1].id))
        XCTAssertEqual(store.active.name, "C")
        XCTAssertTrue(store.delete(store.spaces[1].id))
        XCTAssertEqual(store.active.name, "A")
    }

    func testDeleteInactiveKeepsActive() {
        var store: SpaceStore = store(names: ["A", "B", "C"])
        XCTAssertTrue(store.activate(store.spaces[2].id))
        XCTAssertTrue(store.delete(store.spaces[0].id))
        XCTAssertEqual(store.active.name, "C")
    }

    // MARK: - activation

    func testActivateKnownAndUnknown() {
        var store: SpaceStore = store(names: ["A", "B"])
        let before: UUID = store.activeID
        XCTAssertFalse(store.activate(UUID()))
        XCTAssertEqual(store.activeID, before)
        XCTAssertTrue(store.activate(store.spaces[1].id))
        XCTAssertEqual(store.active.name, "B")
    }

    func testActivateNextAndPreviousWrapAround() {
        var store: SpaceStore = store(names: ["A", "B", "C"])
        store.activateNext()
        XCTAssertEqual(store.active.name, "B")
        store.activateNext()
        store.activateNext()
        XCTAssertEqual(store.active.name, "A")
        store.activatePrevious()
        XCTAssertEqual(store.active.name, "C")
        store.activatePrevious()
        XCTAssertEqual(store.active.name, "B")
    }

    func testActivateNextWithSingleSpaceStays() {
        var store: SpaceStore = SpaceStore.migrated(from: SidebarLayout())
        let only: UUID = store.activeID
        store.activateNext()
        store.activatePrevious()
        XCTAssertEqual(store.activeID, only)
    }

    func testActivateNextFromOrphanStartsAtFirst() {
        var store: SpaceStore = store(names: ["A", "B", "C"])
        store.activeID = UUID()
        store.activateNext()
        XCTAssertEqual(store.active.name, "B")
    }

    // MARK: - move

    func testMoveReordersAndClampsDestination() {
        var store: SpaceStore = store(names: ["A", "B", "C"])
        store.move(from: 0, to: 2)
        XCTAssertEqual(store.spaces.map(\.name), ["B", "C", "A"])
        store.move(from: 2, to: 0)
        XCTAssertEqual(store.spaces.map(\.name), ["A", "B", "C"])
        store.move(from: 0, to: 99)
        XCTAssertEqual(store.spaces.map(\.name), ["B", "C", "A"])
        store.move(from: 2, to: -5)
        XCTAssertEqual(store.spaces.map(\.name), ["A", "B", "C"])
    }

    func testMoveOutOfRangeSourceIsNoOp() {
        var store: SpaceStore = store(names: ["A", "B"])
        store.move(from: 5, to: 0)
        store.move(from: -1, to: 0)
        XCTAssertEqual(store.spaces.map(\.name), ["A", "B"])
    }

    func testMoveKeepsActiveID() {
        var store: SpaceStore = store(names: ["A", "B"])
        let active: UUID = store.activeID
        store.move(from: 0, to: 1)
        XCTAssertEqual(store.activeID, active)
        XCTAssertEqual(store.active.name, "A")
    }

    // MARK: - active content

    func testUpdateActiveSidebarTouchesOnlyActive() {
        var store: SpaceStore = store(names: ["A", "B"])
        XCTAssertTrue(store.activate(store.spaces[1].id))
        store.updateActiveSidebar { $0.addItem(path: "/tmp/only-b", toGroup: nil) }
        XCTAssertTrue(store.spaces[1].sidebar.favorites.contains { $0.path == "/tmp/only-b" })
        XCTAssertFalse(store.spaces[0].sidebar.favorites.contains { $0.path == "/tmp/only-b" })
    }

    func testToggleLiveGroupAddsThenRemovesOnActiveOnly() {
        var store: SpaceStore = store(names: ["A", "B"])
        let ref: LiveGroupRef = LiveGroupRef(propertyID: UUID(), optionID: UUID())
        let other: LiveGroupRef = LiveGroupRef(propertyID: UUID(), optionID: UUID())
        store.toggleLiveGroup(ref)
        store.toggleLiveGroup(other)
        XCTAssertEqual(store.spaces[0].liveGroups, [ref, other])
        XCTAssertTrue(store.spaces[1].liveGroups.isEmpty)
        store.toggleLiveGroup(ref)
        XCTAssertEqual(store.spaces[0].liveGroups, [other])
    }

    // MARK: - encode / decode

    func testRoundTrip() {
        var store: SpaceStore = SpaceStore.migrated(from: customLayout())
        let added: Space = store.add(name: "Work", cloningSidebarFrom: store.spaces[0].id)
        XCTAssertTrue(store.activate(added.id))
        store.spaces[1].symbol = "briefcase"
        store.spaces[1].workspaceIDs = [UUID(), UUID()]
        store.toggleLiveGroup(LiveGroupRef(propertyID: UUID(), optionID: UUID()))
        let decoded: SpaceStore = SpaceStore.decode(store.encoded(), fallbackLayout: SidebarLayout())
        XCTAssertEqual(decoded, store)
    }

    func testDecodeNilEmptyOrGarbageMigratesFallback() {
        let fallback: SidebarLayout = customLayout()
        for data: Data? in [nil, Data(), Data("not json".utf8), Data("[1,2]".utf8)] {
            let store: SpaceStore = SpaceStore.decode(data, fallbackLayout: fallback)
            XCTAssertEqual(store.spaces.count, 1)
            XCTAssertEqual(store.spaces[0].sidebar, fallback)
            XCTAssertEqual(store.spaces[0].name, "Cá nhân")
            XCTAssertEqual(store.activeID, store.spaces[0].id)
        }
    }

    func testDecodeZeroSpacesMigratesFallback() {
        let fallback: SidebarLayout = customLayout()
        let data: Data = json(["schemaVersion": 1, "spaces": [], "activeID": UUID().uuidString])
        let store: SpaceStore = SpaceStore.decode(data, fallbackLayout: fallback)
        XCTAssertEqual(store.spaces.map(\.sidebar), [fallback])
    }

    func testDecodeAllSpacesDamagedMigratesFallback() {
        let data: Data = json(["spaces": [["name": "no id"], 42, "x"]])
        let store: SpaceStore = SpaceStore.decode(data, fallbackLayout: SidebarLayout())
        XCTAssertEqual(store.spaces.map(\.name), ["Cá nhân"])
    }

    func testDecodeToleratesUnknownFieldsAndFutureSchema() {
        let id: UUID = UUID()
        var space: [String: Any] = spaceJSON(id: id, name: "Future")
        space["colour"] = "teal"
        space["nested"] = ["a": [1, 2]]
        let data: Data = json(["schemaVersion": 9, "spaces": [space], "activeID": id.uuidString, "newTopLevel": true])
        let store: SpaceStore = SpaceStore.decode(data, fallbackLayout: SidebarLayout())
        XCTAssertEqual(store.spaces.map(\.name), ["Future"])
        XCTAssertEqual(store.spaces[0].sidebar.favorites.map(\.path), ["/tmp/x"])
        XCTAssertEqual(store.activeID, id)
        XCTAssertEqual(store.schemaVersion, SpaceStore.currentSchemaVersion)
    }

    func testDecodeDropsOnlyTheDamagedSpace() {
        let good1: UUID = UUID()
        let good2: UUID = UUID()
        let damaged: [Any] = [
            ["id": "not-a-uuid", "name": "Bad id"],
            ["id": UUID().uuidString],
            ["id": UUID().uuidString, "name": 7],
            "string element",
        ]
        // A Space whose sidebar alone is damaged keeps its name and gets a default sidebar (review 2026-10-26).
        let badSidebar: UUID = UUID()
        let spaces: [Any] = [spaceJSON(id: good1, name: "One")] + damaged
            + [["id": badSidebar.uuidString, "name": "Bad sidebar", "sidebar": "oops"]] + [spaceJSON(id: good2, name: "Two")]
        let data: Data = json(["spaces": spaces, "activeID": good2.uuidString])
        let store: SpaceStore = SpaceStore.decode(data, fallbackLayout: SidebarLayout())
        XCTAssertEqual(store.spaces.map(\.id), [good1, badSidebar, good2])
        XCTAssertEqual(store.spaces[1].sidebar.favorites.map(\.path), SidebarLayout().favorites.map(\.path))
        XCTAssertEqual(store.active.name, "Two")
    }

    func testDecodeOrphanOrMissingActiveIDUsesFirst() {
        let a: UUID = UUID()
        let b: UUID = UUID()
        let spaces: [Any] = [spaceJSON(id: a, name: "A"), spaceJSON(id: b, name: "B")]
        for active: Any? in [UUID().uuidString, "garbage", nil, 5] {
            var object: [String: Any] = ["spaces": spaces]
            if let active { object["activeID"] = active }
            let store: SpaceStore = SpaceStore.decode(json(object), fallbackLayout: SidebarLayout())
            XCTAssertEqual(store.activeID, a)
        }
    }

    func testDecodeDropsDuplicateSpaceIDsKeepingFirst() {
        let id: UUID = UUID()
        let data: Data = json(["spaces": [spaceJSON(id: id, name: "First"), spaceJSON(id: id, name: "Second")]])
        let store: SpaceStore = SpaceStore.decode(data, fallbackLayout: SidebarLayout())
        XCTAssertEqual(store.spaces.map(\.name), ["First"])
    }

    func testDecodeMissingSidebarIsFreshAndBadSubfieldsAreFiltered() {
        let id: UUID = UUID()
        let ref: [String: Any] = ["propertyID": UUID().uuidString, "optionID": UUID().uuidString]
        let workspace: UUID = UUID()
        let space: [String: Any] = [
            "id": id.uuidString, "name": "S", "symbol": 3,
            "liveGroups": [ref, ref, ["propertyID": "bad"], 1],
            "workspaceIDs": [workspace.uuidString, "nope", 4],
        ]
        let store: SpaceStore = SpaceStore.decode(json(["spaces": [space]]), fallbackLayout: customLayout())
        assertFreshDefault(store.spaces[0].sidebar)
        XCTAssertNil(store.spaces[0].symbol)
        XCTAssertEqual(store.spaces[0].liveGroups.count, 1)
        XCTAssertEqual(store.spaces[0].workspaceIDs, [workspace])
    }

    func testDecodeKeepsReadablePartsOfDamagedSidebar() {
        let id: UUID = UUID()
        let sidebar: [String: Any] = ["favorites": [["path": "/tmp/ok"], ["nopath": true], 3]]
        let space: [String: Any] = ["id": id.uuidString, "name": "S", "sidebar": sidebar]
        let store: SpaceStore = SpaceStore.decode(json(["spaces": [space]]), fallbackLayout: SidebarLayout())
        XCTAssertEqual(store.spaces[0].sidebar.favorites.map(\.path), ["/tmp/ok"])
    }

    func testEncodedWritesCurrentSchemaVersion() {
        var store: SpaceStore = SpaceStore.migrated(from: SidebarLayout())
        store.schemaVersion = 0
        let object: [String: Any]? = (try? JSONSerialization.jsonObject(with: store.encoded())) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, SpaceStore.currentSchemaVersion)
    }

    // MARK: - Source-folder Live Groups

    private func folderGroup(name: String = "Documents", source: String = "/tmp/source") -> FolderLiveGroup {
        FolderLiveGroup(name: name, sourcePath: source,
                        filters: [.init(field: .fileExtension, operation: .equals, value: "pdf")])
    }

    func testLegacySpacePayloadWithoutFolderGroupsDecodesWithoutLosingExistingData() throws {
        var original = store(names: ["A", "B"])
        original.toggleLiveGroup(LiveGroupRef(propertyID: UUID(), optionID: UUID()))
        original.spaces[0].workspaceIDs = [UUID()]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original.encoded()) as? [String: Any])
        var spaces = try XCTUnwrap(object["spaces"] as? [[String: Any]])
        for index in spaces.indices { spaces[index].removeValue(forKey: "folderLiveGroups") }
        object["spaces"] = spaces
        let old = try JSONSerialization.data(withJSONObject: object)
        let tolerant = SpaceStore.decode(old, fallbackLayout: SidebarLayout())
        XCTAssertEqual(tolerant, original)
        XCTAssertEqual(try JSONDecoder().decode(SpaceStore.self, from: old), original)
        XCTAssertTrue(tolerant.spaces.allSatisfy { $0.folderLiveGroups.isEmpty })
    }

    func testFolderGroupRoundTripPreservesLegacyGroupsSidebarsAndWorkspaceIDs() {
        var original = store(names: ["A", "B"])
        let ref = LiveGroupRef(propertyID: UUID(), optionID: UUID())
        original.toggleLiveGroup(ref)
        original.spaces[0].workspaceIDs = [UUID()]
        var group = folderGroup(name: "  Résumés  ", source: "/tmp/source/../documents")
        group.sort = .modifiedNewest
        XCTAssertTrue(original.saveFolderLiveGroup(group, in: original.activeID))
        let decoded = SpaceStore.decode(original.encoded(), fallbackLayout: SidebarLayout())
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.active.folderLiveGroups.first?.name, "Résumés")
        XCTAssertEqual(decoded.active.folderLiveGroups.first?.sourcePath, "/tmp/documents")
        XCTAssertEqual(decoded.active.liveGroups, [ref])
        XCTAssertEqual(decoded.spaces[1].sidebar, original.spaces[1].sidebar)
        XCTAssertTrue(decoded.spaces[1].folderLiveGroups.isEmpty)
    }

    func testDamagedFolderGroupElementsAreDroppedWithoutDroppingSpaceOrOtherGroups() throws {
        var original = store(names: ["A"])
        original.toggleLiveGroup(LiveGroupRef(propertyID: UUID(), optionID: UUID()))
        let group = folderGroup()
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(group)) as? [String: Any])
        var relative = payload; relative["id"] = UUID().uuidString; relative["sourcePath"] = "relative/path"
        var emptyFilters = payload; emptyFilters["id"] = UUID().uuidString; emptyFilters["filters"] = []
        var unknownSort = payload; unknownSort["id"] = UUID().uuidString; unknownSort["sort"] = "future-sort"
        var badFilter = payload; badFilter["id"] = UUID().uuidString
        badFilter["filters"] = [["id": UUID().uuidString, "field": "unknown", "operation": "equals", "value": "pdf"]]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original.encoded()) as? [String: Any])
        var spaces = try XCTUnwrap(object["spaces"] as? [[String: Any]])
        spaces[0]["folderLiveGroups"] = [relative, payload, 42, emptyFilters, unknownSort, badFilter, payload]
        object["spaces"] = spaces
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = SpaceStore.decode(data, fallbackLayout: SidebarLayout())
        XCTAssertEqual(decoded.spaces.count, 1)
        XCTAssertEqual(decoded.active.id, original.activeID)
        XCTAssertEqual(decoded.active.liveGroups, original.active.liveGroups)
        XCTAssertEqual(decoded.active.sidebar, original.active.sidebar)
        XCTAssertEqual(decoded.active.folderLiveGroups, [group])
        XCTAssertEqual(try JSONDecoder().decode(SpaceStore.self, from: data).active.folderLiveGroups, [group])
    }

    func testFolderGroupValidationDoesNotBroadenAnInvalidOrEmptyFilter() {
        var group = folderGroup()
        XCTAssertTrue(group.isValid)
        group.filters = []
        XCTAssertFalse(group.isValid)
        XCTAssertFalse(group.matches(name: "a.pdf", isDirectory: false))
        group = folderGroup(); group.filters[0].value = " . "
        XCTAssertFalse(group.isValid)
        group = folderGroup(); group.filters.append(.init(field: .name, operation: .contains, value: " \n"))
        XCTAssertFalse(group.isValid, "a blank second criterion must not silently broaden an existing group")
        group = folderGroup(); group.name = " \n"
        XCTAssertFalse(group.isValid)
        group = folderGroup(source: "~/Documents")
        XCTAssertFalse(group.isValid)
        group = folderGroup(source: "/tmp/invalid\0path")
        XCTAssertFalse(group.isValid)
        group = folderGroup(); group.filters = [.init(field: .kind, operation: .contains, value: "file")]
        XCTAssertFalse(group.isValid)
        group.filters = [.init(field: .kind, operation: .equals, value: "anything")]
        XCTAssertFalse(group.isValid)
    }

    func testFolderGroupFiltersCombineWithAndAndIgnoreCaseDiacriticsAndLeadingExtensionDot() {
        let group = FolderLiveGroup(name: "PDF reports", sourcePath: "/tmp",
                                    filters: [.init(field: .name, operation: .contains, value: "cafe"),
                                              .init(field: .fileExtension, operation: .equals, value: ".PDF"),
                                              .init(field: .kind, operation: .equals, value: "FILE")])
        XCTAssertTrue(group.matches(name: "Café REPORT.PdF", isDirectory: false))
        XCTAssertTrue(group.matches(name: "Café REPORT.PdF".decomposedStringWithCanonicalMapping, isDirectory: false))
        XCTAssertFalse(group.matches(name: "Café REPORT.txt", isDirectory: false))
        XCTAssertFalse(group.matches(name: "Other.pdf", isDirectory: false))
        XCTAssertFalse(group.matches(name: "Café REPORT.pdf", isDirectory: true))
    }

    func testNameOperatorsAndExtensionEdgeCases() {
        let cases: [(FolderLiveGroup.MatchOperator, String, Bool)] = [
            (.contains, "port", true), (.equals, "rÉport.md", true),
            (.beginsWith, "rép", true), (.endsWith, ".MD", true), (.equals, "report", false),
        ]
        for (operation, value, expected) in cases {
            let group = FolderLiveGroup(name: "Test", sourcePath: "/tmp",
                                        filters: [.init(field: .name, operation: operation, value: value)])
            XCTAssertEqual(group.matches(name: "Report.md", isDirectory: false), expected)
        }
        var group = folderGroup()
        group.filters[0].value = "md"
        XCTAssertTrue(group.matches(name: "README.md", isDirectory: false))
        group.filters[0].value = "gitignore"
        XCTAssertFalse(group.matches(name: ".gitignore", isDirectory: false))
        group.filters[0].value = "gz"
        XCTAssertTrue(group.matches(name: "archive.tar.gz", isDirectory: false))
        XCTAssertFalse(group.matches(name: "archive.tar.gz", isDirectory: true))
        group.filters = [.init(field: .kind, operation: .equals, value: "folder")]
        XCTAssertTrue(group.matches(name: "folder", isDirectory: true))
        XCTAssertFalse(group.matches(name: "folder", isDirectory: false))
    }

    func testFolderGroupSortsNaturallyAndUsesStablePathTies() {
        var group = folderGroup()
        let candidates: [FolderLiveGroup.Candidate] = [
            .init(path: "/z", name: "Café.pdf", isDirectory: false),
            .init(path: "/10", name: "item10.pdf", isDirectory: false),
            .init(path: "/2", name: "item2.pdf", isDirectory: false),
            .init(path: "/a", name: "CAFE.pdf", isDirectory: false),
            .init(path: "/excluded", name: "item1.txt", isDirectory: false),
        ]
        XCTAssertEqual(group.matching(candidates).map(\.path), ["/a", "/z", "/2", "/10"])
        group.sort = .nameDescending
        XCTAssertEqual(group.matching(Array(candidates.reversed())).map(\.path), ["/10", "/2", "/a", "/z"])
    }

    func testFolderGroupModifiedSortKeepsUnknownDatesLastAndTiesByPath() {
        var group = folderGroup()
        let candidates: [FolderLiveGroup.Candidate] = [
            .init(path: "/missing", name: "m.pdf", isDirectory: false),
            .init(path: "/new-z", name: "z.pdf", isDirectory: false, modifiedDate: Date(timeIntervalSince1970: 20)),
            .init(path: "/old", name: "o.pdf", isDirectory: false, modifiedDate: Date(timeIntervalSince1970: 10)),
            .init(path: "/new-a", name: "a.pdf", isDirectory: false, modifiedDate: Date(timeIntervalSince1970: 20)),
        ]
        group.sort = .modifiedNewest
        XCTAssertEqual(group.matching(candidates).map(\.path), ["/new-a", "/new-z", "/old", "/missing"])
        group.sort = .modifiedOldest
        XCTAssertEqual(group.matching(Array(candidates.reversed())).map(\.path), ["/old", "/new-a", "/new-z", "/missing"])
    }

    func testFolderGroupUpsertAndRemovalAreExplicitlyScopedToSpace() {
        var original = store(names: ["A", "B"])
        let first = original.spaces[0].id, second = original.spaces[1].id
        var group = folderGroup()
        original.activate(second)
        XCTAssertTrue(original.saveFolderLiveGroup(group, in: first))
        XCTAssertTrue(original.active.folderLiveGroups.isEmpty)
        group.name = "Renamed"
        XCTAssertTrue(original.saveFolderLiveGroup(group, in: first))
        XCTAssertEqual(original.spaces[0].folderLiveGroups, [group])
        XCTAssertFalse(original.removeFolderLiveGroup(group.id, from: second))
        XCTAssertFalse(original.saveFolderLiveGroup(group, in: UUID()))
        XCTAssertTrue(original.removeFolderLiveGroup(group.id, from: first))
        XCTAssertTrue(original.spaces[0].folderLiveGroups.isEmpty)
    }

}
