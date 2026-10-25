import XCTest

/// XF-T28 — workspaces and session restore: layouts round-trip, names stay unique, damaged entries cost only themselves,
/// and a missing folder never leaves a pane pointing nowhere.
final class BrowserWorkspaceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    func window(_ paths: [String]) -> WindowSnapshot {
        var tree = PaneTree()
        var ids = [tree.panes[0]]
        while ids.count < paths.count, let new = tree.split(ids.last!, .right) { ids.append(new) }
        let panes = zip(ids, paths).map { id, p in
            PaneSnapshot(id: id, path: p, viewMode: .list, sort: .finderDefault, history: PaneHistory(current: p), showHidden: false)
        }
        return WindowSnapshot(frame: CGRect(x: 10, y: 20, width: 900, height: 600), tree: tree, panes: panes,
                              activePane: ids[0], shelfVisible: true)
    }

    func testSaveNamesAreUniqueAndNeverEmpty() {
        var store = WorkspaceStore()
        XCTAssertEqual(store.save(name: "Client review", windows: [], now: now).name, "Client review")
        XCTAssertEqual(store.save(name: "client review ", windows: [], now: now).name, "client review 2")
        XCTAssertEqual(store.save(name: "  ", windows: [], now: now).name, "Workspace")
        XCTAssertEqual(store.save(name: "", windows: [], now: now).name, "Workspace 2")
        XCTAssertEqual(store.workspaces.count, 4)
    }

    func testRenameRefusesEmptyAndTakenNames() {
        var store = WorkspaceStore()
        let a = store.save(name: "A", windows: [], now: now)
        let b = store.save(name: "B", windows: [], now: now)
        XCTAssertFalse(store.rename(a.id, to: "  "))
        XCTAssertFalse(store.rename(a.id, to: "b"))
        XCTAssertTrue(store.rename(a.id, to: " Alpha "))
        XCTAssertEqual(store.workspaces.first { $0.id == a.id }?.name, "Alpha")
        XCTAssertTrue(store.rename(b.id, to: "B"), "renaming to its own name is fine")
        XCTAssertFalse(store.rename(UUID(), to: "X"))
    }

    func testDuplicateAndDelete() throws {
        var store = WorkspaceStore()
        let a = store.save(name: "Docs", windows: [window(["/a", "/b"])], now: now)
        let copy = try XCTUnwrap(store.duplicate(a.id, now: now))
        XCTAssertEqual(copy.name, "Docs copy")
        XCTAssertEqual(copy.windows, a.windows)
        XCTAssertNotEqual(copy.id, a.id)
        XCTAssertEqual(store.duplicate(a.id, now: now)?.name, "Docs copy 2")
        store.delete(a.id)
        XCTAssertFalse(store.workspaces.contains { $0.id == a.id })
        XCTAssertNil(store.duplicate(a.id, now: now))
    }

    func testExportRoundTripsEveryField() {
        var store = WorkspaceStore()
        var w = window(["/Users/me", "/Volumes/Disk/Photos"])
        w.panes[1].viewMode = .gallery
        w.panes[1].sort = SortOrder(key: .size, ascending: false)
        w.panes[1].history.visit("/Volumes/Disk/Photos/2026")
        _ = store.save(name: "Two panes", windows: [w], now: now)
        let decoded = WorkspaceStore.decode(store.exportJSON())
        XCTAssertEqual(decoded.skipped, 0)
        XCTAssertEqual(decoded.store, store)
        XCTAssertTrue(String(decoding: store.exportJSON(), as: UTF8.self).contains("\"name\" : \"Two panes\""))
    }

    func testOneDamagedWorkspaceCostsOnlyItself() throws {
        var store = WorkspaceStore()
        _ = store.save(name: "Good", windows: [window(["/a"])], now: now)
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: store.exportJSON()) as? [Any])
        array.append(["id": "not-a-uuid", "name": 3])
        let data = try JSONSerialization.data(withJSONObject: array)
        let decoded = WorkspaceStore.decode(data)
        XCTAssertEqual(decoded.skipped, 1)
        XCTAssertEqual(decoded.store.workspaces.map(\.name), ["Good"])
        XCTAssertEqual(WorkspaceStore.decode(Data("garbage".utf8)).skipped, 1)
        XCTAssertEqual(WorkspaceStore.decode(Data()).skipped, 0)
    }

    /// v2 (XF-T30 W1): a tab whose current folder vanished becomes a dead tab — it KEEPS its path (the model/view
    /// layer shows "Try Again" for it) instead of falling back to Home; only its history is pruned of missing entries.
    func testRestoreKeepsDeadTabPathAndFiltersHistory() {
        var w = window(["/gone", "/kept"])
        w.panes[1].history.visit("/gone/a")          // a folder that is gone sits IN the Back history…
        w.panes[1].history.visit("/kept/sub")
        w.panes[1].history.visit("/gone/deeper")     // …and is also the current folder
        w.panes[1].path = "/gone/deeper"
        XCTAssertTrue(w.panes[1].history.back.contains("/gone/a"), "precondition: the test must put a gone folder in Back")
        let exists: (String) -> Bool = { !$0.hasPrefix("/gone") }
        let r = SessionRestore.restored(w, exists: exists, home: "/Users/me")
        XCTAssertEqual(r.missing, ["/gone", "/gone/deeper"])
        XCTAssertEqual(r.window.panes[0].path, "/gone", "a dead tab keeps its path, it never falls back to Home")
        XCTAssertEqual(r.window.panes[1].path, "/gone/deeper", "a dead tab keeps its path, it never falls back to Home")
        XCTAssertFalse(r.window.panes[1].history.back.contains { $0.hasPrefix("/gone") })
        XCTAssertTrue(r.window.panes[1].history.back.contains("/kept/sub"))
    }

    func testRestoreClampsAnOutOfRangeSelectedTab() {
        var w = window(["/a"])
        let t1 = TabSnapshot(path: "/a", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/a"), showHidden: false)
        let t2 = TabSnapshot(path: "/b", viewMode: .icons, sort: .finderDefault, history: PaneHistory(current: "/b"), showHidden: false)
        w.panes[0] = PaneSnapshot(id: w.panes[0].id, tabs: [t1, t2], selectedTab: 1)
        w.panes[0].selectedTab = 7                       // a hand-edited / damaged file
        let r = SessionRestore.restored(w, exists: { _ in true }, home: "/h")
        XCTAssertEqual(r.window.panes[0].selectedTab, 1, "the stored index is clamped, so the next save is clean too")
        XCTAssertEqual(r.window.panes[0].path, "/b", "the v1 mirror follows the clamped tab")
    }

    func testRestoreRepairsATreeAndPaneListThatDisagree() {
        var w = window(["/a", "/b"])
        let orphan = PaneSnapshot(id: PaneID(raw: 99), path: "/x", viewMode: .list, sort: .finderDefault,
                                  history: PaneHistory(current: "/x"), showHidden: false)
        w.panes.append(orphan)
        w.panes.removeAll { $0.id == w.tree.panes[1] }
        w.activePane = PaneID(raw: 99)
        let r = SessionRestore.restored(w, exists: { _ in true }, home: "/h")
        XCTAssertEqual(Set(r.window.panes.map(\.id)), Set(w.tree.panes))
        XCTAssertEqual(r.window.panes.first { $0.id == w.tree.panes[1] }?.path, "/h")
        XCTAssertEqual(r.window.activePane, w.tree.panes[0])
    }

    func testShiftAtLaunchSkipsRestore() {
        XCTAssertTrue(SessionRestore.shouldRestore(shiftHeld: false, reopenEnabled: true))
        XCTAssertFalse(SessionRestore.shouldRestore(shiftHeld: true, reopenEnabled: true))
        XCTAssertFalse(SessionRestore.shouldRestore(shiftHeld: false, reopenEnabled: false))
    }

    // MARK: - XF-T30 W1: PaneSnapshot.allTabs / selectedTabIndex / init(id:tabs:selectedTab:)

    func testAllTabsOnAV1SnapshotIsOneTabFromTopLevelFields() {
        let history = PaneHistory(current: "/a")
        let snap = PaneSnapshot(id: PaneID(raw: 0), path: "/a", viewMode: .gallery,
                                 sort: SortOrder(key: .size, ascending: false), history: history, showHidden: true)
        XCTAssertNil(snap.tabs, "precondition: a v1 snapshot has no tabs array")
        let tabs = snap.allTabs
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs[0].path, "/a")
        XCTAssertEqual(tabs[0].viewMode, .gallery)
        XCTAssertEqual(tabs[0].sort, SortOrder(key: .size, ascending: false))
        XCTAssertEqual(tabs[0].history, history)
        XCTAssertEqual(tabs[0].showHidden, true)
    }

    func testSelectedTabIndexOnAV1SnapshotIsZero() {
        let snap = PaneSnapshot(id: PaneID(raw: 0), path: "/a", viewMode: .list, sort: .finderDefault,
                                 history: PaneHistory(current: "/a"), showHidden: false)
        XCTAssertEqual(snap.selectedTabIndex, 0)
    }

    func testAllTabsOnAV2SnapshotReturnsTheTabsArray() {
        let t1 = TabSnapshot(path: "/a", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/a"), showHidden: false)
        let t2 = TabSnapshot(path: "/b", viewMode: .gallery, sort: .finderDefault, history: PaneHistory(current: "/b"), showHidden: false)
        let snap = PaneSnapshot(id: PaneID(raw: 0), tabs: [t1, t2], selectedTab: 1)
        XCTAssertEqual(snap.allTabs, [t1, t2])
    }

    func testSelectedTabIndexClampsAboveRange() {
        let t1 = TabSnapshot(path: "/a", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/a"), showHidden: false)
        var snap = PaneSnapshot(id: PaneID(raw: 0), tabs: [t1], selectedTab: 0)
        snap.selectedTab = 99
        XCTAssertEqual(snap.selectedTabIndex, 0, "clamped to the last valid index (0) for a single tab")
    }

    func testSelectedTabIndexClampsBelowRange() {
        let t1 = TabSnapshot(path: "/a", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/a"), showHidden: false)
        var snap = PaneSnapshot(id: PaneID(raw: 0), tabs: [t1], selectedTab: 0)
        snap.selectedTab = -5
        XCTAssertEqual(snap.selectedTabIndex, 0)
    }

    func testInitWithTabsMirrorsSelectedTabIntoTopLevelFields() {
        let t1 = TabSnapshot(path: "/a", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/a"), showHidden: false)
        let t2 = TabSnapshot(path: "/b", viewMode: .gallery, sort: SortOrder(key: .size, ascending: true),
                              history: PaneHistory(current: "/b"), showHidden: true)
        let snap = PaneSnapshot(id: PaneID(raw: 3), tabs: [t1, t2], selectedTab: 1)
        XCTAssertEqual(snap.path, "/b")
        XCTAssertEqual(snap.viewMode, .gallery)
        XCTAssertEqual(snap.sort, SortOrder(key: .size, ascending: true))
        XCTAssertEqual(snap.showHidden, true)
        XCTAssertEqual(snap.history, t2.history)
        XCTAssertEqual(snap.tabs, [t1, t2])
        XCTAssertEqual(snap.selectedTab, 1)
    }

    func testInitWithTabsClampsOutOfRangeSelectedTab() {
        let t1 = TabSnapshot(path: "/a", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/a"), showHidden: false)
        let snap = PaneSnapshot(id: PaneID(raw: 0), tabs: [t1], selectedTab: 99)
        XCTAssertEqual(snap.path, "/a", "an out-of-range selectedTab must not crash; it falls back within bounds")
    }

    func testInitWithEmptyTabsFallsBackToRootDefaults() {
        let snap = PaneSnapshot(id: PaneID(raw: 0), tabs: [], selectedTab: 0)
        XCTAssertEqual(snap.path, "/")
        XCTAssertEqual(snap.viewMode, .list)
    }

    // MARK: - XF-T30 W1: v1 decodes to one tab, v2 round-trips

    func testV1JSONDecodesIntoASnapshotWhoseAllTabsHasExactlyOneTab() throws {
        // A hand-built v1 PaneSnapshot JSON (no "tabs"/"selectedTab" keys at all) must still decode and behave
        // as a single-tab pane.
        let json = """
        {"id": {"raw": 0}, "path": "/a", "viewMode": "list", "sort": {"key": "name", "ascending": true},
         "history": {"back": [], "forward": [], "current": "/a", "rememberedOrder": [], "remembered": {}}, "showHidden": false}
        """
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.tabs)
        XCTAssertEqual(decoded.allTabs.count, 1)
        XCTAssertEqual(decoded.allTabs[0].path, "/a")
        XCTAssertEqual(decoded.selectedTabIndex, 0)
    }

    func testV2SnapshotRoundTripsThroughJSON() throws {
        let t1 = TabSnapshot(path: "/a", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/a"), showHidden: false)
        let t2 = TabSnapshot(path: "/b", viewMode: .columns, sort: .finderDefault, history: PaneHistory(current: "/b"),
                              showHidden: true, selectedNames: ["x.txt"], groupBy: .kind, columnPath: ["/b", "/b/sub"])
        let snap = PaneSnapshot(id: PaneID(raw: 2), tabs: [t1, t2], selectedTab: 1)
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: data)
        XCTAssertEqual(decoded, snap)
        XCTAssertEqual(decoded.allTabs, [t1, t2])
        XCTAssertEqual(decoded.selectedTabIndex, 1)
    }

    // MARK: - XF-T30 W1: SessionRestore v2 — dead tab, multi-tab history pruning, selectedTab clamping

    func testRestoreV2MultiTabPaneOnlyDeadTabKeepsItsPathOthersUnaffected() {
        let t1 = TabSnapshot(path: "/kept1", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/kept1"), showHidden: false)
        let t2 = TabSnapshot(path: "/gone", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/gone"), showHidden: false)
        var tree = PaneTree()
        let pane = PaneSnapshot(id: tree.panes[0], tabs: [t1, t2], selectedTab: 1)
        let w = WindowSnapshot(frame: nil, tree: tree, panes: [pane], activePane: tree.panes[0], shelfVisible: false)
        let exists: (String) -> Bool = { !$0.hasPrefix("/gone") }
        let r = SessionRestore.restored(w, exists: exists, home: "/home")
        let tabs = r.window.panes[0].allTabs
        XCTAssertEqual(tabs[0].path, "/kept1")
        XCTAssertEqual(tabs[1].path, "/gone", "the dead tab keeps its path")
        XCTAssertEqual(r.missing, ["/gone"])
    }

    func testRestoreV2SelectedTabClampedWhenTabsArrayShrinks() {
        // A hand-edited / damaged file could carry a selectedTab index beyond the tabs it actually has.
        let t1 = TabSnapshot(path: "/a", viewMode: .list, sort: .finderDefault, history: PaneHistory(current: "/a"), showHidden: false)
        var tree = PaneTree()
        var pane = PaneSnapshot(id: tree.panes[0], tabs: [t1], selectedTab: 0)
        pane.selectedTab = 5
        let w = WindowSnapshot(frame: nil, tree: tree, panes: [pane], activePane: tree.panes[0], shelfVisible: false)
        let r = SessionRestore.restored(w, exists: { _ in true }, home: "/home")
        XCTAssertEqual(r.window.panes[0].selectedTabIndex, 0)
    }

    func testRestoreV2NeverMountsAnything() {
        // "Never mounts anything" — restoring must not depend on any side effect beyond the `exists` closure the
        // caller supplies; calling `restored` twice with the same inputs must be perfectly idempotent.
        var tree = PaneTree()
        let pane = PaneSnapshot(id: tree.panes[0], path: "/a", viewMode: .list, sort: .finderDefault,
                                history: PaneHistory(current: "/a"), showHidden: false)
        let w = WindowSnapshot(frame: nil, tree: tree, panes: [pane], activePane: tree.panes[0], shelfVisible: false)
        let r1 = SessionRestore.restored(w, exists: { _ in true }, home: "/home")
        let r2 = SessionRestore.restored(w, exists: { _ in true }, home: "/home")
        XCTAssertEqual(r1.window, r2.window)
        XCTAssertEqual(r1.missing, r2.missing)
    }
}
