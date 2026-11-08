import XCTest

/// XF-T38 — the browser menu bar as data: FileOctopus 1.0.10's order (owner screenshots), every item reachable, nothing
/// doubled, links to pages that exist, and the palette subtitle the menus imply.
final class BrowserMenuLayoutTests: XCTestCase {

    private let topMenus = BrowserMenuLayout.Menu.allCases

    func testNoMenuStartsOrEndsWithASeparatorOrDoublesOne() {
        var blocks: [[BrowserMenuLayout.Entry]] = topMenus.map { BrowserMenuLayout.entries($0) }
        blocks += BrowserMenuLayout.Submenu.allCases.compactMap { BrowserMenuLayout.entries($0) }
        for entries in blocks {
            XCTAssertFalse(entries.isEmpty)
            XCTAssertNotEqual(entries.first, .separator)
            XCTAssertNotEqual(entries.last, .separator)
            for (a, b) in zip(entries, entries.dropFirst()) {
                XCTAssertFalse(a == .separator && b == .separator, "two separators in a row")
            }
        }
    }

    func testNoCommandTwiceInOneMenu() {
        for menu in topMenus {
            let commands = BrowserMenuLayout.commands(in: menu)
            XCTAssertEqual(commands.count, Set(commands).count, "\(menu) repeats a command")
        }
    }

    func testFileMenuFollowsTheScreenshotOrder() {
        let commands = BrowserMenuLayout.commands(in: .file)
        XCTAssertEqual(Array(commands.prefix(4)), [.newWindow, .newFolder, .newFolderWithSelection, .newWindowTab])
        XCTAssertEqual(commands.last, .saveSearch)
        XCTAssertTrue(BrowserMenuLayout.entries(.file).contains(.link(.findDuplicates)))
        XCTAssertTrue(BrowserMenuLayout.entries(.file).contains(.submenu(.openWith)))
        XCTAssertTrue(BrowserMenuLayout.entries(.file).contains(.submenu(.tags)))
    }

    func testGoMenuStartsWithHistoryLikeFinder() {
        XCTAssertEqual(Array(BrowserMenuLayout.commands(in: .go).prefix(3)), [.back, .forward, .openEnclosing])
        XCTAssertTrue(BrowserMenuLayout.entries(.go).contains(.submenu(.recentFolders)))
        XCTAssertEqual(BrowserMenuLayout.entries(.go).last, .submenu(.savedSearches))
    }

    func testViewMenuHasEveryViewModeAndBar() {
        let view = Set(BrowserMenuLayout.commands(in: .view))
        for command: BrowserCommand in [.viewIcons, .viewList, .viewColumns, .viewGallery, .toggleSidebar, .togglePathBar,
                                        .toggleStatusBar, .toggleLocationBar, .toggleToolbar, .toggleHidden, .refresh,
                                        .commandPalette, .presetGrid, .splitRight, .zoomPane] {
            XCTAssertTrue(view.contains(command), "View lacks \(command)")
        }
    }

    func testWindowMenuHasTheWorkspaceBlock() {
        let window = BrowserMenuLayout.entries(.window)
        for entry: BrowserMenuLayout.Entry in [.command(.saveWorkspace), .submenu(.openWorkspace), .submenu(.renameWorkspace),
                                               .submenu(.duplicateWorkspace), .submenu(.deleteWorkspace), .action(.exportWorkspaces)] {
            XCTAssertTrue(window.contains(entry), "Window lacks \(entry)")
        }
    }

    func testStaticAndBuiltSubmenusArePartitioned() {
        let staticOnes = BrowserMenuLayout.Submenu.allCases.filter { BrowserMenuLayout.entries($0) != nil }
        XCTAssertEqual(Set(staticOnes), [.shelf, .paneLayout, .panes])
    }

    func testLinksOpenExistingPages() {
        XCTAssertEqual(BrowserMenuLayout.Link.compareFolders.destination, .sync)
        XCTAssertEqual(BrowserMenuLayout.Link.findDuplicates.destination, .duplicateFinder)
        XCTAssertEqual(BrowserMenuLayout.Link.remoteServer.destination, .remoteConnect)
        for link in BrowserMenuLayout.Link.allCases {
            XCTAssertNotNil(SidebarDestination(rawValue: link.destination.rawValue))
        }
    }

    func testPaletteSubtitleIsTheFirstMenuThatHasTheCommand() {
        XCTAssertEqual(BrowserMenuLayout.menu(containing: .newFolder), .file)
        XCTAssertEqual(BrowserMenuLayout.menu(containing: .closePane), .file, "File comes before View ▸ Panes")
        XCTAssertEqual(BrowserMenuLayout.menu(containing: .zoomPane), .view)
        XCTAssertEqual(BrowserMenuLayout.menu(containing: .goHome), .go)
        XCTAssertEqual(BrowserMenuLayout.menu(containing: .saveWorkspace), .window)
        XCTAssertEqual(BrowserMenuLayout.menu(containing: .copyPath), .edit)
        XCTAssertEqual(BrowserMenuLayout.menu(containing: .openBrowserSettings), .app)
        XCTAssertNil(BrowserMenuLayout.menu(containing: .selectAll), "in no browser menu (the system Edit menu has it)")
    }

    func testToolbarInsertionsKeepTheUsersOrder() {
        let current = ["back", "view", "share", "action", "search"]
        let plan = BrowserMenuLayout.toolbarInsertions(current: current, add: [("sidebar", "back"), ("tags", "action")])
        XCTAssertEqual(plan.map(\.id), ["sidebar", "tags"])
        XCTAssertEqual(plan.map(\.index), [0, 4], "tags lands before action once sidebar shifted everything by one")
        XCTAssertTrue(BrowserMenuLayout.toolbarInsertions(current: ["sidebar", "tags"], add: [("sidebar", nil), ("tags", nil)]).isEmpty)
        XCTAssertEqual(BrowserMenuLayout.toolbarInsertions(current: ["a"], add: [("tags", "missing")]).map(\.index), [1],
                       "an anchor the user removed puts the item at the end")
    }

    /// macOS gives the menu bar only to a regular app: with the Dock icon hidden, the browser had no menu bar (measured).
    func testTheBrowserMakesTheAppRegularWhileItIsOpen() {
        XCTAssertTrue(BrowserMenuLayout.needsRegularApp(showDockIcon: true, browserWindowsOpen: false))
        XCTAssertTrue(BrowserMenuLayout.needsRegularApp(showDockIcon: true, browserWindowsOpen: true))
        XCTAssertTrue(BrowserMenuLayout.needsRegularApp(showDockIcon: false, browserWindowsOpen: true))
        XCTAssertFalse(BrowserMenuLayout.needsRegularApp(showDockIcon: false, browserWindowsOpen: false), "the user's hidden Dock icon holds")
    }
}
