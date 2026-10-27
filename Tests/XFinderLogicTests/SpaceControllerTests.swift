import XCTest

/// XF-T32 W2 contract §B — `SpaceController` with in-memory closures standing in for UserDefaults.
@MainActor final class SpaceControllerTests: XCTestCase {

    /// In-memory stand-ins for `fileBrowser.spaces` and `fileBrowser.sidebarLayout`, counting every call.
    @MainActor private final class Harness {
        var data: Data?
        var mirror: SidebarLayout
        var saves: Int = 0
        var writes: [SidebarLayout] = []

        init(data: Data? = nil, mirror: SidebarLayout = SidebarLayout()) {
            self.data = data
            self.mirror = mirror
        }

        func make() -> SpaceController {
            SpaceController(
                load: { [unowned self] in self.data },
                save: { [unowned self] (bytes: Data) in self.data = bytes; self.saves += 1 },
                legacyLayout: { [unowned self] in self.mirror },
                writeLayout: { [unowned self] (layout: SidebarLayout) in self.mirror = layout; self.writes.append(layout) })
        }

        var persisted: SpaceStore { SpaceStore.decode(data, fallbackLayout: SidebarLayout()) }
    }

    private func layout(pinning path: String) -> SidebarLayout {
        var layout: SidebarLayout = SidebarLayout()
        layout.addItem(path: path, toGroup: nil)
        return layout
    }

    private func paths(_ layout: SidebarLayout) -> [String] { layout.favorites.map(\.path) }

    // MARK: - Launch

    func testFirstLaunchMigratesMirrorIntoOnePersonalSpaceAndSavesIt() {
        let harness: Harness = Harness(mirror: layout(pinning: "/tmp/projects"))
        let controller: SpaceController = harness.make()
        XCTAssertEqual(controller.store.spaces.count, 1)
        XCTAssertEqual(controller.active.name, SpaceStore.migratedSpaceNameKey)
        XCTAssertEqual(controller.active.sidebar, harness.mirror)
        XCTAssertEqual(harness.saves, 1, "the migrated Space is saved so its id survives the next launch")
        XCTAssertEqual(harness.persisted, controller.store)
        XCTAssertTrue(harness.writes.isEmpty, "the mirror already equals the active sidebar")
    }

    func testCorruptDataMigrates() {
        let harness: Harness = Harness(data: Data("not json".utf8), mirror: layout(pinning: "/tmp/x"))
        let controller: SpaceController = harness.make()
        XCTAssertEqual(controller.store.spaces.count, 1)
        XCTAssertEqual(controller.active.name, SpaceStore.migratedSpaceNameKey)
        XCTAssertEqual(paths(controller.active.sidebar), paths(harness.mirror))
        XCTAssertEqual(harness.persisted, controller.store, "the repaired store replaces the corrupt bytes")
    }

    func testCleanRelaunchKeepsStoreAndWritesNothing() {
        let harness: Harness = Harness(mirror: layout(pinning: "/tmp/a"))
        let first: SpaceController = harness.make()
        first.add(name: "Công việc")
        let savesBefore: Int = harness.saves
        let writesBefore: Int = harness.writes.count
        let second: SpaceController = harness.make()
        XCTAssertEqual(second.store, first.store)
        XCTAssertEqual(harness.saves, savesBefore)
        XCTAssertEqual(harness.writes.count, writesBefore)
    }

    func testRelaunchAdoptsMirrorEditedOutsideTheController() {
        let harness: Harness = Harness()
        let first: SpaceController = harness.make()
        let other: Space = first.add(name: "B")
        harness.mirror = layout(pinning: "/tmp/edited")
        let second: SpaceController = harness.make()
        XCTAssertEqual(second.active.id, other.id)
        XCTAssertEqual(second.active.sidebar, harness.mirror)
        XCTAssertEqual(harness.persisted.active.sidebar, harness.mirror)
        XCTAssertEqual(second.store.spaces.count, 2)
    }

    // MARK: - Activation

    func testActivateWritesLayoutAndSaves() {
        let harness: Harness = Harness(mirror: layout(pinning: "/tmp/one"))
        let controller: SpaceController = harness.make()
        let firstID: UUID = controller.active.id
        let firstSidebar: SidebarLayout = controller.active.sidebar
        controller.add(name: "Hai")
        controller.sidebarDidChange(layout(pinning: "/tmp/two"))
        controller.activate(firstID)
        XCTAssertEqual(controller.active.id, firstID)
        XCTAssertEqual(harness.writes.last, firstSidebar)
        XCTAssertEqual(harness.mirror, firstSidebar)
        XCTAssertEqual(harness.persisted.activeID, firstID)
    }

    func testActivateUnknownIDChangesNothing() {
        let harness: Harness = Harness()
        let controller: SpaceController = harness.make()
        let saves: Int = harness.saves
        let before: SpaceStore = controller.store
        controller.activate(UUID())
        XCTAssertEqual(controller.store, before)
        XCTAssertEqual(harness.saves, saves)
        XCTAssertTrue(harness.writes.isEmpty)
    }

    func testActivateNextAndPreviousWrapAndMirror() {
        let harness: Harness = Harness()
        let controller: SpaceController = harness.make()
        let a: UUID = controller.active.id
        let b: UUID = controller.add(name: "B").id
        let c: UUID = controller.add(name: "C").id
        let cLayout: SidebarLayout = layout(pinning: "/tmp/c")
        controller.sidebarDidChange(cLayout)
        controller.activateNext()
        XCTAssertEqual(controller.active.id, a)
        XCTAssertEqual(harness.mirror, controller.active.sidebar)
        controller.activatePrevious()
        XCTAssertEqual(controller.active.id, c)
        XCTAssertEqual(harness.mirror, cLayout)
        controller.activatePrevious()
        XCTAssertEqual(controller.active.id, b)
        XCTAssertEqual(harness.persisted.activeID, b)
    }

    func testActivateNextWithOneSpaceIsNoOp() {
        let harness: Harness = Harness()
        let controller: SpaceController = harness.make()
        let saves: Int = harness.saves
        controller.activateNext()
        controller.activatePrevious()
        XCTAssertEqual(harness.saves, saves)
        XCTAssertTrue(harness.writes.isEmpty)
    }

    // MARK: - Add / rename / delete

    func testAddClonesActiveSidebarAndActivates() {
        let harness: Harness = Harness(mirror: layout(pinning: "/tmp/projects"))
        let controller: SpaceController = harness.make()
        let source: Space = controller.active
        let added: Space = controller.add(name: "Công việc")
        XCTAssertEqual(controller.active.id, added.id)
        XCTAssertNotEqual(added.id, source.id)
        XCTAssertEqual(added.name, "Công việc")
        XCTAssertEqual(paths(added.sidebar), paths(source.sidebar))
        XCTAssertTrue(Set(added.sidebar.favorites.map(\.id)).isDisjoint(with: Set(source.sidebar.favorites.map(\.id))))
        XCTAssertEqual(harness.writes.last, added.sidebar)
        XCTAssertEqual(harness.persisted, controller.store)
    }

    func testRenamePersistsAndRefusalsDoNotSave() {
        let harness: Harness = Harness()
        let controller: SpaceController = harness.make()
        let id: UUID = controller.active.id
        controller.add(name: "B")
        let saves: Int = harness.saves
        XCTAssertFalse(controller.rename(id, to: "  "))
        XCTAssertFalse(controller.rename(id, to: "b"))
        XCTAssertFalse(controller.rename(UUID(), to: "Z"))
        XCTAssertEqual(harness.saves, saves)
        XCTAssertTrue(controller.rename(id, to: " Nhà "))
        XCTAssertEqual(harness.persisted.spaces.first?.name, "Nhà")
    }

    func testDeleteLastSpaceRefused() {
        let harness: Harness = Harness()
        let controller: SpaceController = harness.make()
        let saves: Int = harness.saves
        XCTAssertFalse(controller.delete(controller.active.id))
        XCTAssertEqual(controller.store.spaces.count, 1)
        XCTAssertEqual(harness.saves, saves)
        XCTAssertTrue(harness.writes.isEmpty)
    }

    func testDeleteActiveMirrorsSuccessor() {
        let harness: Harness = Harness(mirror: layout(pinning: "/tmp/first"))
        let controller: SpaceController = harness.make()
        let first: Space = controller.active
        let second: Space = controller.add(name: "B")
        controller.sidebarDidChange(layout(pinning: "/tmp/second"))
        XCTAssertTrue(controller.delete(second.id))
        XCTAssertEqual(controller.active.id, first.id)
        XCTAssertEqual(harness.mirror, first.sidebar)
        XCTAssertEqual(harness.persisted.spaces.map(\.id), [first.id])
    }

    func testDeleteInactiveDoesNotRewriteMirror() {
        let harness: Harness = Harness()
        let controller: SpaceController = harness.make()
        let first: UUID = controller.active.id
        controller.add(name: "B")
        controller.activate(first)
        let other: UUID = controller.store.spaces[1].id
        let writes: Int = harness.writes.count
        XCTAssertTrue(controller.delete(other))
        XCTAssertEqual(harness.writes.count, writes)
        XCTAssertEqual(harness.persisted.spaces.count, 1)
    }

    // MARK: - Active Space content

    func testSidebarDidChangeStoresIntoActiveOnlyWithoutWritingBack() {
        let harness: Harness = Harness(mirror: layout(pinning: "/tmp/first"))
        let controller: SpaceController = harness.make()
        let first: Space = controller.active
        controller.add(name: "B")
        let writes: Int = harness.writes.count
        let edited: SidebarLayout = layout(pinning: "/tmp/edited")
        controller.sidebarDidChange(edited)
        XCTAssertEqual(harness.writes.count, writes, "no feedback write into the mirror")
        XCTAssertEqual(controller.active.sidebar, edited)
        XCTAssertEqual(controller.store.spaces.first { $0.id == first.id }?.sidebar, first.sidebar)
        XCTAssertEqual(harness.persisted.active.sidebar, edited)
    }

    func testSidebarDidChangeWithSameLayoutDoesNotSave() {
        let harness: Harness = Harness()
        let controller: SpaceController = harness.make()
        let saves: Int = harness.saves
        controller.sidebarDidChange(controller.active.sidebar)
        XCTAssertEqual(harness.saves, saves)
    }

    func testToggleLiveGroupPersistsInActiveSpace() {
        let harness: Harness = Harness()
        let controller: SpaceController = harness.make()
        let group: LiveGroupRef = LiveGroupRef(propertyID: UUID(), optionID: UUID())
        controller.toggleLiveGroup(group)
        XCTAssertEqual(controller.active.liveGroups, [group])
        XCTAssertEqual(harness.persisted.active.liveGroups, [group])
        controller.toggleLiveGroup(group)
        XCTAssertTrue(harness.persisted.active.liveGroups.isEmpty)
        XCTAssertTrue(harness.writes.isEmpty)
    }
}
