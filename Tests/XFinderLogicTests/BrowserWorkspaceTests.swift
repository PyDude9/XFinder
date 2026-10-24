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

    func testRestoreOpensHomeForAMissingFolderAndFiltersHistory() {
        var w = window(["/gone", "/kept"])
        w.panes[1].history.visit("/kept/sub")
        w.panes[1].history.visit("/gone/deeper")
        w.panes[1].path = "/gone/deeper"
        let exists: (String) -> Bool = { !$0.hasPrefix("/gone") }
        let r = SessionRestore.restored(w, exists: exists, home: "/Users/me")
        XCTAssertEqual(r.missing, ["/gone", "/gone/deeper"])
        XCTAssertEqual(r.window.panes[0].path, "/Users/me")
        XCTAssertEqual(r.window.panes[1].path, "/Users/me")
        XCTAssertFalse(r.window.panes[1].history.back.contains { $0.hasPrefix("/gone") })
        XCTAssertTrue(r.window.panes[1].history.back.contains("/kept/sub"))
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
}
