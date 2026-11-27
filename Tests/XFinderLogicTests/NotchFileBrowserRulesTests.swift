import XCTest
import Foundation

final class NotchFileBrowserRulesTests: XCTestCase {
    typealias R = NotchFileBrowserRules

    // 1. Giữ ID `files` cho Khay, điểm đến mới dùng `fileBrowser`
    func testPageIDIsFileBrowserAndDistinctFromFiles() {
        XCTAssertEqual(R.pageID, "fileBrowser")
        XCTAssertNotEqual(R.pageID, "files")
    }

    // 2. Không có workspace
    func testEmptyWorkspacesReturnsEmptyList() {
        let rows = R.resolveWorkspaces([], probe: { _ in .accessible })
        XCTAssertTrue(rows.isEmpty)
    }

    // 3. Đường dẫn biến mất (pinned favorite marked missing & disabled; vanished recent dropped; workspace counts missing)
    func testMissingPathsAreSurfacedForPinnedFavoritesDroppedForRecentsAndCountedInWorkspaces() {
        let missingFav = R.FolderInput(path: "/Users/test/DeletedProject", displayName: nil, isPinned: true)
        let okFav = R.FolderInput(path: "/Users/test/Documents", displayName: nil, isPinned: true)

        let folders = R.resolveFolders(
            favorites: [missingFav, okFav],
            recents: ["/Users/test/VanishedRecent", "/Users/test/Downloads"],
            probe: { path in
                if path.contains("Deleted") || path.contains("Vanished") { return .missing }
                return .accessible
            }
        )

        XCTAssertEqual(folders.map(\.path), [
            "/Users/test/DeletedProject",
            "/Users/test/Documents",
            "/Users/test/Downloads",
        ], "missing pinned favorite stays visible as unavailable; missing recent is dropped")

        XCTAssertEqual(folders[0].access, .missing)
        XCTAssertFalse(folders[0].canOpen)
        XCTAssertNil(R.actionForFolder(folders[0], browserEnabled: true))

        XCTAssertEqual(folders[1].access, .accessible)
        XCTAssertTrue(folders[1].canOpen)
        XCTAssertEqual(R.actionForFolder(folders[1], browserEnabled: true), .openFolder(path: "/Users/test/Documents"))

        let wsID = UUID()
        let workspaces = R.resolveWorkspaces([
            R.WorkspaceInput(
                id: wsID,
                name: "Work",
                folderPaths: ["/Users/test/DeletedProject", "/Users/test/DeletedProject", "/Users/test/Documents"],
                windowCount: 1
            )
        ], probe: { path in
            path.contains("Deleted") ? .missing : .accessible
        })

        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces[0].missingFolderCount, 1, "duplicate missing paths count once")
        XCTAssertEqual(workspaces[0].inaccessibleFolderCount, 0)
        XCTAssertTrue(workspaces[0].canOpen, "SessionRestore still opens the workspace and warns on missing folders")
        XCTAssertEqual(R.actionForWorkspace(workspaces[0], browserEnabled: true), .openWorkspace(id: wsID))
    }

    // 4. Mất quyền (inaccessible folder cannot open; workspace reports inaccessible count; probe is cached per path)
    func testInaccessiblePathsBlockFolderOpenAndProbeOnlyListedPathsOnce() {
        var probedPaths: [String] = []
        let fav = R.FolderInput(path: "/Users/test/PrivateVault", displayName: nil, isPinned: true)

        let folders = R.resolveFolders(
            favorites: [fav],
            recents: ["/Users/test/PrivateVault", "/Users/test/LockedRecent"],
            probe: { path in
                probedPaths.append(path)
                return .inaccessible
            }
        )

        XCTAssertEqual(probedPaths, ["/Users/test/PrivateVault", "/Users/test/LockedRecent"],
                       "each unique path is probed at most once; never scans directories")
        XCTAssertEqual(folders.count, 2)
        XCTAssertTrue(folders.allSatisfy { $0.access == .inaccessible && !$0.canOpen })
        XCTAssertNil(R.actionForFolder(folders[0], browserEnabled: true))

        let ws = R.resolveWorkspaces([
            R.WorkspaceInput(id: UUID(), name: "Locked", folderPaths: ["/Users/test/PrivateVault"], windowCount: 1)
        ], probe: { _ in .inaccessible })
        XCTAssertEqual(ws[0].inaccessibleFolderCount, 1)
        XCTAssertTrue(ws[0].hasUnavailableFolders)
    }

    // 5. Tên dài (long folder & workspace names are bounded cleanly while preserving fullName)
    func testLongNamesAreMiddleTruncatedWhilePreservingFullName() {
        let longFolder = "Thư mục dự án rất dài cho bản phát hành quý bốn năm hai nghìn hai mươi sáu"
        let longWorkspace = "Workspace siêu dài chứa nhiều cửa sổ nghiên cứu thiết kế Dynamic Island"

        let folders = R.resolveFolders(
            favorites: [R.FolderInput(path: "/Users/test/\(longFolder)", displayName: nil, isPinned: true)],
            recents: [],
            maxLabelLength: 24,
            probe: { _ in .accessible }
        )
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].fullName, longFolder)
        XCTAssertLessThanOrEqual(folders[0].displayName.count, 24)
        XCTAssertTrue(folders[0].displayName.contains("…"))

        let workspaces = R.resolveWorkspaces(
            [R.WorkspaceInput(id: UUID(), name: longWorkspace, folderPaths: [], windowCount: 2)],
            maxLabelLength: 24,
            probe: { _ in .accessible }
        )
        XCTAssertEqual(workspaces[0].fullName, longWorkspace)
        XCTAssertLessThanOrEqual(workspaces[0].displayName.count, 24)
        XCTAssertTrue(workspaces[0].displayName.contains("…"))
    }

    // 6. Điểm vào khi trình duyệt tắt (`fileBrowser.enabled == false`)
    func testEntryPointAndAllActionsAreBlockedWhenBrowserIsDisabled() {
        XCTAssertFalse(R.isDestinationAvailable(browserEnabled: false))
        XCTAssertEqual(R.entryPoint(browserEnabled: false), .disabled)
        XCTAssertNil(R.actionForOpenBrowser(browserEnabled: false))

        let folder = R.FolderRow(
            path: "/Users/test/Documents",
            fullName: "Documents",
            displayName: "Documents",
            isPinned: true,
            access: .accessible
        )
        let workspace = R.WorkspaceRow(
            id: UUID(),
            fullName: "Dev",
            displayName: "Dev",
            windowCount: 1,
            missingFolderCount: 0,
            inaccessibleFolderCount: 0
        )

        XCTAssertNil(R.actionForFolder(folder, browserEnabled: false))
        XCTAssertNil(R.actionForWorkspace(workspace, browserEnabled: false))

        // When enabled, all three actions resolve cleanly.
        XCTAssertTrue(R.isDestinationAvailable(browserEnabled: true))
        XCTAssertEqual(R.entryPoint(browserEnabled: true), .enabled)
        XCTAssertEqual(R.actionForOpenBrowser(browserEnabled: true), .openBrowser)
        XCTAssertEqual(R.actionForFolder(folder, browserEnabled: true), .openFolder(path: "/Users/test/Documents"))
        XCTAssertEqual(R.actionForWorkspace(workspace, browserEnabled: true), .openWorkspace(id: workspace.id))
    }

    // 7. Tôn trọng thiết lập sidebar và bỏ đường dẫn ảo
    func testRespectsSidebarTogglesAndSkipsVirtualPaths() {
        let fav = R.FolderInput(path: "/Users/test/Desktop", displayName: "Màn hình nền", isPinned: true)
        let rowsNoFavs = R.resolveFolders(
            favorites: [fav],
            recents: ["xfinder-virtual://recents", "/Users/test/Downloads"],
            favoritesEnabled: false,
            recentsEnabled: true,
            probe: { _ in .accessible }
        )
        XCTAssertEqual(rowsNoFavs.map(\.path), ["/Users/test/Downloads"])

        let rowsNoRecents = R.resolveFolders(
            favorites: [fav],
            recents: ["/Users/test/Downloads"],
            favoritesEnabled: true,
            recentsEnabled: false,
            probe: { _ in .accessible }
        )
        XCTAssertEqual(rowsNoRecents.map(\.path), ["/Users/test/Desktop"])
        XCTAssertEqual(rowsNoRecents[0].fullName, "Màn hình nền")
    }
}
