import XCTest

final class SidebarLayoutTests: XCTestCase {

    // MARK: - init / defaults

    func testFreshLayoutHasDefaultFavoritesInOrder() {
        let layout = SidebarLayout()
        XCTAssertEqual(layout.favorites.map(\.path), [
            NSHomeDirectory(),
            NSHomeDirectory() + "/Desktop",
            NSHomeDirectory() + "/Documents",
            NSHomeDirectory() + "/Downloads",
            "/Applications",
        ])
        XCTAssertTrue(layout.groups.isEmpty)
        XCTAssertTrue(layout.hiddenVolumeUUIDs.isEmpty)
    }

    func testFreshLayoutWritesCurrentSchemaVersion() {
        XCTAssertEqual(SidebarLayout().schemaVersion, SidebarLayout.currentSchemaVersion)
    }

    // MARK: - groups

    func testAddGroupAppendsNamedGroup() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "Dự án")
        XCTAssertEqual(group?.name, "Dự án")
        XCTAssertEqual(layout.groups.map(\.name), ["Dự án"])
    }

    func testAddGroupTrimsWhitespace() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "  Dự án  ")
        XCTAssertEqual(group?.name, "Dự án")
    }

    func testAddGroupRejectsEmptyName() {
        var layout = SidebarLayout()
        XCTAssertNil(layout.addGroup(named: "   "))
        XCTAssertTrue(layout.groups.isEmpty)
    }

    func testAddGroupRejectsCaseInsensitiveDuplicateName() {
        var layout = SidebarLayout()
        _ = layout.addGroup(named: "Dự án")
        XCTAssertNil(layout.addGroup(named: "dự án"))
        XCTAssertEqual(layout.groups.count, 1)
    }

    func testRenameGroupChangesName() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "Cũ")!
        XCTAssertTrue(layout.renameGroup(group.id, to: "Mới"))
        XCTAssertEqual(layout.groups.first?.name, "Mới")
    }

    func testRenameGroupRejectsDuplicateOfAnotherGroup() {
        var layout = SidebarLayout()
        let a = layout.addGroup(named: "A")!
        _ = layout.addGroup(named: "B")
        XCTAssertFalse(layout.renameGroup(a.id, to: "B"))
        XCTAssertEqual(layout.groups.first(where: { $0.id == a.id })?.name, "A")
    }

    func testRenameGroupAllowsKeepingItsOwnName() {
        var layout = SidebarLayout()
        let a = layout.addGroup(named: "A")!
        XCTAssertTrue(layout.renameGroup(a.id, to: "A"))
    }

    func testDeleteGroupReturnsItemsToFavorites() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "Dự án")!
        layout.addItem(path: "/tmp/project", toGroup: group.id)
        layout.deleteGroup(group.id)
        XCTAssertTrue(layout.groups.isEmpty)
        XCTAssertTrue(layout.favorites.contains { $0.path == "/tmp/project" })
    }

    func testDeleteGroupDedupesAgainstExistingFavorite() {
        var layout = SidebarLayout()
        let home = NSHomeDirectory()
        let group = layout.addGroup(named: "Dự án")!
        layout.addItem(path: home, toGroup: group.id)   // already a favorite
        layout.deleteGroup(group.id)
        XCTAssertEqual(layout.favorites.filter { $0.path == home }.count, 1)
    }

    func testDeleteGroupWithUnknownIDDoesNothing() {
        var layout = SidebarLayout()
        let before = layout
        layout.deleteGroup(UUID())
        XCTAssertEqual(layout, before)
    }

    // MARK: - items

    func testAddItemToFavorites() {
        var layout = SidebarLayout()
        layout.addItem(path: "/tmp/x", toGroup: nil)
        XCTAssertTrue(layout.favorites.contains { $0.path == "/tmp/x" })
    }

    func testAddItemToGroup() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "G")!
        layout.addItem(path: "/tmp/x", toGroup: group.id)
        XCTAssertEqual(layout.groups.first?.items.map(\.path), ["/tmp/x"])
    }

    func testAddItemDoesNotDuplicateSamePathInSameList() {
        var layout = SidebarLayout()
        layout.addItem(path: "/tmp/x", toGroup: nil)
        layout.addItem(path: "/tmp/x", toGroup: nil)
        XCTAssertEqual(layout.favorites.filter { $0.path == "/tmp/x" }.count, 1)
    }

    func testAddItemToUnknownGroupDoesNothing() {
        var layout = SidebarLayout()
        let before = layout
        layout.addItem(path: "/tmp/x", toGroup: UUID())
        XCTAssertEqual(layout, before)
    }

    func testAddItemIgnoresEmptyPath() {
        var layout = SidebarLayout()
        let before = layout
        layout.addItem(path: "", toGroup: nil)
        XCTAssertEqual(layout, before)
    }

    func testRemoveItemFromFavorites() {
        var layout = SidebarLayout()
        let id = layout.favorites[0].id
        layout.removeItem(id)
        XCTAssertFalse(layout.favorites.contains { $0.id == id })
    }

    func testRemoveItemFromGroup() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "G")!
        layout.addItem(path: "/tmp/x", toGroup: group.id)
        let id = layout.groups.first!.items.first!.id
        layout.removeItem(id)
        XCTAssertTrue(layout.groups.first!.items.isEmpty)
    }

    func testMoveItemBetweenGroups() {
        var layout = SidebarLayout()
        let a = layout.addGroup(named: "A")!
        let b = layout.addGroup(named: "B")!
        layout.addItem(path: "/tmp/x", toGroup: a.id)
        let id = layout.groups[0].items[0].id
        layout.moveItem(id, toGroup: b.id, index: 0)
        XCTAssertTrue(layout.groups.first { $0.id == a.id }!.items.isEmpty)
        XCTAssertEqual(layout.groups.first { $0.id == b.id }!.items.map(\.path), ["/tmp/x"])
    }

    func testMoveItemToFavoritesFromGroup() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "G")!
        layout.addItem(path: "/tmp/x", toGroup: group.id)
        let id = layout.groups[0].items[0].id
        layout.moveItem(id, toGroup: nil, index: 0)
        XCTAssertEqual(layout.favorites.first?.path, "/tmp/x")
    }

    func testMoveItemReordersWithinSameList() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "G")!
        layout.addItem(path: "/tmp/a", toGroup: group.id)
        layout.addItem(path: "/tmp/b", toGroup: group.id)
        let firstID = layout.groups[0].items[0].id
        layout.moveItem(firstID, toGroup: group.id, index: 1)
        XCTAssertEqual(layout.groups[0].items.map(\.path), ["/tmp/b", "/tmp/a"])
    }

    func testMoveItemClampsOutOfRangeIndex() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "G")!
        layout.addItem(path: "/tmp/a", toGroup: group.id)
        let id = layout.groups[0].items[0].id
        layout.moveItem(id, toGroup: group.id, index: 999)
        XCTAssertEqual(layout.groups[0].items.map(\.path), ["/tmp/a"])
    }

    func testMoveItemWithUnknownIDDoesNothing() {
        var layout = SidebarLayout()
        let before = layout
        layout.moveItem(UUID(), toGroup: nil, index: 0)
        XCTAssertEqual(layout, before)
    }

    func testMoveItemToDeletedGroupFallsBackToFavoritesInsteadOfDroppingIt() {
        var layout = SidebarLayout()
        layout.addItem(path: "/tmp/x", toGroup: nil)
        let id = layout.favorites.first { $0.path == "/tmp/x" }!.id
        layout.moveItem(id, toGroup: UUID(), index: 0)
        XCTAssertTrue(layout.favorites.contains { $0.path == "/tmp/x" })
    }

    // MARK: - display name

    func testSetDisplayNameOnFavorite() {
        var layout = SidebarLayout()
        let id = layout.favorites[0].id
        layout.setDisplayName(id, to: "Nhà của tôi")
        XCTAssertEqual(layout.favorites[0].displayName, "Nhà của tôi")
    }

    func testSetDisplayNameOnGroupItem() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "G")!
        layout.addItem(path: "/tmp/x", toGroup: group.id)
        let id = layout.groups[0].items[0].id
        layout.setDisplayName(id, to: "X riêng")
        XCTAssertEqual(layout.groups[0].items[0].displayName, "X riêng")
    }

    func testSetDisplayNameWithEmptyStringActsAsReset() {
        var layout = SidebarLayout()
        let id = layout.favorites[0].id
        layout.setDisplayName(id, to: "Tạm")
        layout.setDisplayName(id, to: "   ")
        XCTAssertNil(layout.favorites[0].displayName)
    }

    func testResetDisplayNameClearsIt() {
        var layout = SidebarLayout()
        let id = layout.favorites[0].id
        layout.setDisplayName(id, to: "Tạm")
        layout.resetDisplayName(id)
        XCTAssertNil(layout.favorites[0].displayName)
    }

    // MARK: - hidden volumes

    func testHideVolumePersistsUUID() {
        var layout = SidebarLayout()
        layout.hideVolume(uuid: "ABC-123")
        XCTAssertTrue(layout.isVolumeHidden(uuid: "ABC-123"))
    }

    func testShowVolumeClearsIt() {
        var layout = SidebarLayout()
        layout.hideVolume(uuid: "ABC-123")
        layout.showVolume(uuid: "ABC-123")
        XCTAssertFalse(layout.isVolumeHidden(uuid: "ABC-123"))
    }

    func testHideVolumeIgnoresEmptyUUID() {
        var layout = SidebarLayout()
        layout.hideVolume(uuid: "")
        XCTAssertTrue(layout.hiddenVolumeUUIDs.isEmpty)
    }

    func testHiddenVolumeSurvivesRoundTripEncodeDecode() {
        var layout = SidebarLayout()
        layout.hideVolume(uuid: "VOL-UUID-1")
        let data = layout.encoded()
        let decoded = SidebarLayout.decode(data)
        XCTAssertTrue(decoded.isVolumeHidden(uuid: "VOL-UUID-1"))
    }

    // MARK: - tolerant decode

    func testDecodeNilDataReturnsDefaultLayout() {
        let layout = SidebarLayout.decode(nil)
        XCTAssertEqual(layout.favorites.map(\.path), SidebarLayout().favorites.map(\.path))
        XCTAssertTrue(layout.groups.isEmpty)
        XCTAssertTrue(layout.hiddenVolumeUUIDs.isEmpty)
    }

    func testDecodeEmptyDataReturnsDefaultLayout() {
        let layout = SidebarLayout.decode(Data())
        XCTAssertEqual(layout.favorites.map(\.path), SidebarLayout().favorites.map(\.path))
        XCTAssertTrue(layout.groups.isEmpty)
        XCTAssertTrue(layout.hiddenVolumeUUIDs.isEmpty)
    }

    func testDecodeGarbageDataReturnsDefaultLayout() {
        let layout = SidebarLayout.decode(Data("not json at all".utf8))
        XCTAssertEqual(layout.favorites.map(\.path), SidebarLayout().favorites.map(\.path))
        XCTAssertTrue(layout.groups.isEmpty)
        XCTAssertTrue(layout.hiddenVolumeUUIDs.isEmpty)
    }

    func testRoundTripEncodeDecodePreservesCustomLayout() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "Dự án")!
        layout.addItem(path: "/tmp/x", toGroup: group.id)
        layout.setDisplayName(layout.favorites[0].id, to: "Nhà")
        layout.hideVolume(uuid: "V1")

        let decoded = SidebarLayout.decode(layout.encoded())
        XCTAssertEqual(decoded, layout)
    }

    /// FileOctopus pitfall: a document missing the schema field entirely (older-than-versioning file) must still
    /// read back its favorites and groups, not bail out to a blank layout.
    func testDecodeMissingSchemaVersionStillReadsFavoritesAndGroups() {
        let json = """
        {"favorites": [{"id": "\(UUID().uuidString)", "path": "/tmp/a"}], "groups": []}
        """
        let decoded = SidebarLayout.decode(Data(json.utf8))
        XCTAssertEqual(decoded.favorites.map(\.path), ["/tmp/a"])
    }

    /// One damaged group (missing name) is dropped; a sibling good group and every favorite still come back —
    /// the FileOctopus failure mode this schema exists to avoid.
    func testDecodeDropsOnlyTheDamagedGroupKeepingGoodParts() {
        let json = """
        {
          "schemaVersion": 1,
          "favorites": [{"id": "\(UUID().uuidString)", "path": "/tmp/a"}],
          "groups": [
            {"id": "\(UUID().uuidString)", "items": []},
            {"id": "\(UUID().uuidString)", "name": "Good", "items": [{"id": "\(UUID().uuidString)", "path": "/tmp/b"}]}
          ]
        }
        """
        let decoded = SidebarLayout.decode(Data(json.utf8))
        XCTAssertEqual(decoded.favorites.map(\.path), ["/tmp/a"])
        XCTAssertEqual(decoded.groups.map(\.name), ["Good"])
        XCTAssertEqual(decoded.groups.first?.items.map(\.path), ["/tmp/b"])
    }

    /// An item missing its path is dropped; the item beside it survives.
    func testDecodeDropsOnlyTheDamagedItemKeepingGoodParts() {
        let json = """
        {
          "schemaVersion": 1,
          "favorites": [{"id": "\(UUID().uuidString)"}, {"id": "\(UUID().uuidString)", "path": "/tmp/good"}],
          "groups": []
        }
        """
        let decoded = SidebarLayout.decode(Data(json.utf8))
        XCTAssertEqual(decoded.favorites.map(\.path), ["/tmp/good"])
    }

    /// A field only a newer build understands must not break today's reader (CLAUDE.md: newer-version fields ignored).
    func testDecodeIgnoresUnknownFieldsFromANewerSchema() {
        let json = """
        {
          "schemaVersion": 2,
          "favorites": [{"id": "\(UUID().uuidString)", "path": "/tmp/a", "colorTag": "red"}],
          "groups": [],
          "somethingFromTheFuture": true
        }
        """
        let decoded = SidebarLayout.decode(Data(json.utf8))
        XCTAssertEqual(decoded.favorites.map(\.path), ["/tmp/a"])
    }

    /// Re-encoding (e.g. after any edit) always stamps the schema this binary knows, even if the document just read
    /// back claimed a newer one — this build cannot promise to preserve fields it never parsed.
    func testEncodedAlwaysWritesCurrentSchemaVersion() {
        let decoded = SidebarLayout.decode(Data("""
        {"schemaVersion": 99, "favorites": [], "groups": []}
        """.utf8))
        let reencoded = SidebarLayout.decode(decoded.encoded())
        XCTAssertEqual(reencoded.schemaVersion, SidebarLayout.currentSchemaVersion)
    }

    /// An explicitly empty favorites array (the person removed every pin) must round-trip as empty, not silently
    /// repopulate the five defaults — only a *missing* key falls back to defaults.
    func testDecodeExplicitlyEmptyFavoritesStaysEmpty() {
        let json = """
        {"schemaVersion": 1, "favorites": [], "groups": []}
        """
        let decoded = SidebarLayout.decode(Data(json.utf8))
        XCTAssertTrue(decoded.favorites.isEmpty)
    }

    // MARK: - schema 2: currentSchemaVersion

    func testCurrentSchemaVersionIsTwo() {
        XCTAssertEqual(SidebarLayout.currentSchemaVersion, 2)
    }

    // MARK: - schema 2: isDefault

    func testFreshLayoutMarksAllFiveFavoritesAsDefault() {
        let layout = SidebarLayout()
        XCTAssertEqual(layout.favorites.count, 5)
        XCTAssertTrue(layout.favorites.allSatisfy(\.isDefault))
    }

    func testItemAddedThroughAddItemIsNeverDefault() {
        var layout = SidebarLayout()
        layout.addItem(path: "/tmp/custom", toGroup: nil)
        let added = layout.favorites.first { $0.path == "/tmp/custom" }
        XCTAssertEqual(added?.isDefault, false)
    }

    func testGroupItemsAreNeverDefault() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "G")!
        layout.addItem(path: "/tmp/x", toGroup: group.id)
        XCTAssertEqual(layout.groups[0].items[0].isDefault, false)
    }

    // MARK: - schema 2: resetFavoritesToDefault

    func testResetFavoritesToDefaultRestoresShippedFiveInOrder() {
        var layout = SidebarLayout()
        layout.addItem(path: "/tmp/extra", toGroup: nil)
        layout.removeItem(layout.favorites[0].id)
        layout.resetFavoritesToDefault()
        XCTAssertEqual(layout.favorites.map(\.path), SidebarLayout().favorites.map(\.path))
        XCTAssertTrue(layout.favorites.allSatisfy(\.isDefault))
    }

    func testResetFavoritesToDefaultDoesNotTouchCustomGroups() {
        var layout = SidebarLayout()
        let group = layout.addGroup(named: "Dự án")!
        layout.addItem(path: "/tmp/x", toGroup: group.id)
        layout.resetFavoritesToDefault()
        XCTAssertEqual(layout.groups.map(\.name), ["Dự án"])
        XCTAssertEqual(layout.groups[0].items.map(\.path), ["/tmp/x"])
    }

    func testResetFavoritesToDefaultDiscardsAnyNonDefaultFavoritePin() {
        var layout = SidebarLayout()
        layout.addItem(path: "/tmp/extra", toGroup: nil)
        layout.resetFavoritesToDefault()
        XCTAssertFalse(layout.favorites.contains { $0.path == "/tmp/extra" })
    }

    func testResetFavoritesToDefaultClearsDisplayNameOverrides() {
        var layout = SidebarLayout()
        layout.setDisplayName(layout.favorites[0].id, to: "Tên riêng")
        layout.resetFavoritesToDefault()
        XCTAssertTrue(layout.favorites.allSatisfy { $0.displayName == nil })
    }

    // MARK: - schema 2: tag order

    func testFreshLayoutHasNoTagOrder() {
        XCTAssertTrue(SidebarLayout().userTagOrder.isEmpty)
    }

    func testMoveTagAddsItToOrder() {
        var layout = SidebarLayout()
        layout.moveTag("Đỏ", toIndex: 0)
        XCTAssertEqual(layout.userTagOrder, ["Đỏ"])
    }

    func testMoveTagReordersExistingEntry() {
        var layout = SidebarLayout()
        layout.moveTag("A", toIndex: 0)
        layout.moveTag("B", toIndex: 1)
        layout.moveTag("A", toIndex: 1)
        XCTAssertEqual(layout.userTagOrder, ["B", "A"])
    }

    func testMoveTagClampsOutOfRangeIndex() {
        var layout = SidebarLayout()
        layout.moveTag("A", toIndex: 0)
        layout.moveTag("B", toIndex: 999)
        XCTAssertEqual(layout.userTagOrder, ["A", "B"])
    }

    func testMoveTagIgnoresEmptyName() {
        var layout = SidebarLayout()
        layout.moveTag("", toIndex: 0)
        XCTAssertTrue(layout.userTagOrder.isEmpty)
    }

    func testForgetTagOrderRemovesIt() {
        var layout = SidebarLayout()
        layout.moveTag("A", toIndex: 0)
        layout.forgetTagOrder("A")
        XCTAssertTrue(layout.userTagOrder.isEmpty)
    }

    func testForgetTagOrderOnUnknownNameIsHarmless() {
        var layout = SidebarLayout()
        layout.moveTag("A", toIndex: 0)
        layout.forgetTagOrder("Z")
        XCTAssertEqual(layout.userTagOrder, ["A"])
    }

    func testOrderedTagsFallsBackToFinderOrderWhenNoUserOrder() {
        let layout = SidebarLayout()
        XCTAssertEqual(layout.orderedTags(["Đỏ", "Xanh", "Vàng"]), ["Đỏ", "Xanh", "Vàng"])
    }

    func testOrderedTagsAppliesUserOrderFirst() {
        var layout = SidebarLayout()
        layout.moveTag("Xanh", toIndex: 0)
        layout.moveTag("Đỏ", toIndex: 1)
        XCTAssertEqual(layout.orderedTags(["Đỏ", "Xanh", "Vàng"]), ["Xanh", "Đỏ", "Vàng"])
    }

    func testOrderedTagsAppendsUnorderedNamesInFinderOrder() {
        var layout = SidebarLayout()
        layout.moveTag("Vàng", toIndex: 0)
        // "Đỏ" and "Xanh" were never dragged; they should appear after "Vàng", in the order Finder gave them.
        XCTAssertEqual(layout.orderedTags(["Đỏ", "Xanh", "Vàng"]), ["Vàng", "Đỏ", "Xanh"])
    }

    func testOrderedTagsDropsARememberedNameNoLongerInFinder() {
        var layout = SidebarLayout()
        layout.moveTag("Đã xoá", toIndex: 0)
        layout.moveTag("Đỏ", toIndex: 1)
        XCTAssertEqual(layout.orderedTags(["Đỏ", "Xanh"]), ["Đỏ", "Xanh"])
    }

    // MARK: - schema 1 → schema 2 decode compatibility

    /// A document written by the schema-1 binary (no `isDefault`, no `userTagOrder` keys at all) must still decode
    /// in full — the FileOctopus pitfall this whole file exists to avoid, now exercised across the schema bump.
    func testDecodeSchema1DocumentReadsFavoritesWithIsDefaultFalse() {
        let json = """
        {
          "schemaVersion": 1,
          "favorites": [{"id": "\(UUID().uuidString)", "path": "/tmp/a"}],
          "groups": []
        }
        """
        let decoded = SidebarLayout.decode(Data(json.utf8))
        XCTAssertEqual(decoded.favorites.map(\.path), ["/tmp/a"])
        XCTAssertEqual(decoded.favorites.first?.isDefault, false)
        XCTAssertTrue(decoded.userTagOrder.isEmpty)
    }

    func testDecodeSchema2DocumentReadsIsDefaultAndTagOrder() {
        let json = """
        {
          "schemaVersion": 2,
          "favorites": [{"id": "\(UUID().uuidString)", "path": "/tmp/a", "isDefault": true}],
          "groups": [],
          "userTagOrder": ["Xanh", "Đỏ"]
        }
        """
        let decoded = SidebarLayout.decode(Data(json.utf8))
        XCTAssertEqual(decoded.favorites.first?.isDefault, true)
        XCTAssertEqual(decoded.userTagOrder, ["Xanh", "Đỏ"])
    }

    func testRoundTripEncodeDecodePreservesIsDefaultAndTagOrder() {
        var layout = SidebarLayout()
        layout.moveTag("Xanh", toIndex: 0)
        let decoded = SidebarLayout.decode(layout.encoded())
        XCTAssertEqual(decoded, layout)
        XCTAssertTrue(decoded.favorites.allSatisfy(\.isDefault))
        XCTAssertEqual(decoded.userTagOrder, ["Xanh"])
    }

    func testEncodedAfterSchema1DecodeWritesCurrentSchemaVersion() {
        let decoded = SidebarLayout.decode(Data("""
        {"schemaVersion": 1, "favorites": [], "groups": []}
        """.utf8))
        let reencoded = SidebarLayout.decode(decoded.encoded())
        XCTAssertEqual(reencoded.schemaVersion, SidebarLayout.currentSchemaVersion)
    }
}
