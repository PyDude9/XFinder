import Foundation

/// XF-T38 — the file browser's menu bar as data (owner, 2026-11-08: "Nhớ làm cả Menubar, Navigation Bar cho XFinder",
/// with seven screenshots of FileOctopus 1.0.10's menus). One source for `BrowserMainMenu` (which builds the NSMenus),
/// the command palette (which shows each command's menu under its title, as FileOctopus does) and the tests.
///
/// Order follows the screenshots. Items FileOctopus has that XFinder already owns as a page of its own (Q-T37-4: "XFinder
/// có hết rồi") are links to that page. Not here on purpose (Q-T38-3): Print and Empty Trash; Check for Updates, License
/// and Server Transfers/Log (XFinder has no such thing).
enum BrowserMenuLayout {

    enum Menu: String, CaseIterable, Sendable { case app, file, edit, view, go, window }

    /// Built when opened (selection, state or a store decides their items) — except the three static ones, see `entries(_:)`.
    enum Submenu: String, CaseIterable, Sendable {
        case openWith, tags, groupBy, sortBy, shelf, paneLayout, panes, recentFolders, savedSearches
        case openWorkspace, renameWorkspace, duplicateWorkspace, deleteWorkspace
    }

    /// FileOctopus items that XFinder covers with an existing page.
    enum Link: String, CaseIterable, Sendable {
        case compareFolders, findDuplicates, remoteServer

        var destination: SidebarDestination {
            switch self {
            case .compareFolders: return .sync
            case .findDuplicates: return .duplicateFinder
            case .remoteServer: return .remoteConnect
            }
        }
    }

    /// Menu actions that are not palette commands (they need a panel only the menu presents).
    enum Action: String, CaseIterable, Sendable { case exportWorkspaces }

    enum Entry: Equatable, Sendable {
        case command(BrowserCommand)
        case submenu(Submenu)
        case link(Link)
        case action(Action)
        case separator
    }

    static func titleKey(_ menu: Menu) -> String {
        switch menu {
        case .app: return "XFinder"
        case .file: return "Tệp"
        case .edit: return "Sửa"
        case .view: return "Xem"
        case .go: return "Đi"
        case .window: return "Cửa sổ"
        }
    }

    static func titleKey(_ submenu: Submenu) -> String {
        switch submenu {
        case .openWith: return "Mở bằng"
        case .tags: return "Thẻ"
        case .groupBy: return "Nhóm theo"
        case .sortBy: return "Sắp theo"
        case .shelf: return "Shelf"
        case .paneLayout: return "Bố cục ngăn"
        case .panes: return "Ngăn"
        case .recentFolders: return "Thư mục gần đây"
        case .savedSearches: return "Tìm kiếm đã lưu"
        case .openWorkspace: return "Mở workspace"
        case .renameWorkspace: return "Đổi tên workspace"
        case .duplicateWorkspace: return "Nhân bản workspace"
        case .deleteWorkspace: return "Xoá workspace"
        }
    }

    static func titleKey(_ link: Link) -> String {
        switch link {
        case .compareFolders: return "So sánh thư mục…"
        case .findDuplicates: return "Tìm tệp trùng…"
        case .remoteServer: return "Kết nối máy chủ từ xa…"
        }
    }

    static func titleKey(_ action: Action) -> String {
        switch action {
        case .exportWorkspaces: return "Xuất các workspace…"
        }
    }

    /// The items of a top-level menu, without leading/trailing separators (`BrowserMainMenu` adds the separator that
    /// parts a block from the system's own items in Edit, View and Window).
    static func entries(_ menu: Menu) -> [Entry] {
        switch menu {
        case .app:
            return [.command(.openBrowserSettings), .command(.clearOperationHistory)]
        case .file:
            return [
                .command(.newWindow), .command(.newFolder), .command(.newFolderWithSelection), .command(.newWindowTab),
                .command(.open), .submenu(.openWith), .command(.closePane), .command(.closeWindow), .separator,
                .command(.getInfo), .command(.rename), .command(.compress), .command(.duplicate), .command(.makeAlias),
                .command(.copyToOtherPane), .command(.moveToOtherPane), .link(.compareFolders), .link(.findDuplicates),
                .command(.quickLook), .separator,
                .command(.share), .separator,
                .command(.showOriginal), .command(.showInFinder), .command(.addToSidebar), .command(.addToShelf), .separator,
                .command(.moveToTrash), .command(.eject), .separator,
                .submenu(.tags), .separator,
                .command(.find), .command(.saveSearch),
            ]
        case .edit:
            return [.command(.copyPath), .command(.pasteMove), .command(.batchRename)]
        case .view:
            return [
                .command(.viewIcons), .command(.viewList), .command(.viewColumns), .command(.viewGallery), .separator,
                .command(.useGroups), .submenu(.groupBy), .submenu(.sortBy), .separator,
                .command(.toggleSidebar), .command(.filter), .command(.togglePreview), .submenu(.shelf), .separator,
                .command(.toggleToolbar), .command(.togglePathBar), .command(.toggleStatusBar), .command(.toggleLocationBar),
                .command(.editLocation), .command(.refresh), .command(.toggleHidden), .separator,
                .submenu(.paneLayout), .submenu(.panes), .separator,
                .command(.customizeToolbar), .command(.showViewOptions), .separator,
                .command(.commandPalette),
            ]
        case .go:
            return [
                .command(.back), .command(.forward), .command(.openEnclosing), .separator,
                .command(.goRecents), .command(.goDocuments), .command(.goDesktop), .command(.goDownloads), .command(.goHome),
                .command(.goComputer), .command(.goAirDrop), .command(.goNetwork), .command(.goICloud),
                .command(.goApplications), .command(.goUtilities), .separator,
                .submenu(.recentFolders), .separator,
                .command(.goToFolder), .command(.connectToServer), .link(.remoteServer), .command(.quickOpen), .separator,
                .submenu(.savedSearches),
            ]
        case .window:
            return [
                .command(.operations), .separator,
                .command(.previousPaneTab), .command(.nextPaneTab), .command(.moveTabToWindow), .separator,
                .command(.saveWorkspace), .submenu(.openWorkspace), .submenu(.renameWorkspace),
                .submenu(.duplicateWorkspace), .submenu(.deleteWorkspace), .action(.exportWorkspaces),
            ]
        }
    }

    /// The submenus whose items never change; nil for the ones built when they open.
    static func entries(_ submenu: Submenu) -> [Entry]? {
        switch submenu {
        case .shelf:
            return [.command(.toggleShelf), .command(.addToShelf)]
        case .paneLayout:
            return [.command(.presetSingle), .command(.presetSideBySide), .command(.presetStacked), .command(.presetGrid)]
        case .panes:
            return [
                .command(.splitRight), .command(.splitLeft), .command(.splitDown), .command(.splitUp), .separator,
                .command(.nextPane), .command(.previousPane), .command(.swapWithNextPane), .command(.zoomPane),
                .command(.equalizePanes), .separator,
                .command(.makePaneWider), .command(.makePaneNarrower), .command(.makePaneTaller), .command(.makePaneShorter),
                .separator, .command(.closePane),
            ]
        case .openWith, .tags, .groupBy, .sortBy, .recentFolders, .savedSearches,
             .openWorkspace, .renameWorkspace, .duplicateWorkspace, .deleteWorkspace:
            return nil
        }
    }

    /// Every command a menu shows, including those in its static submenus, in menu order.
    static func commands(in menu: Menu) -> [BrowserCommand] {
        entries(menu).flatMap { entry -> [BrowserCommand] in
            switch entry {
            case .command(let command): return [command]
            case .submenu(let submenu):
                return (entries(submenu) ?? []).compactMap { if case .command(let c) = $0 { return c }; return nil }
            case .link, .action, .separator: return []
            }
        }
    }

    /// The menu a command lives in — the palette's subtitle ("Tệp", "Xem", …); nil when no menu has it.
    static func menu(containing command: BrowserCommand) -> Menu? {
        [Menu.file, .edit, .view, .go, .window, .app].first { commands(in: $0).contains(command) }
    }

    // MARK: - Menu bar ownership

    /// macOS shows a menu bar only for a regular app (one with a Dock icon). The browser needs its menu bar, so XFinder
    /// is regular while a browser window is open even when the user hid the Dock icon; otherwise the user's choice holds.
    static func needsRegularApp(showDockIcon: Bool, browserWindowsOpen: Bool) -> Bool {
        showDockIcon || browserWindowsOpen
    }

    // MARK: - Toolbar ("Navigation Bar")

    /// Where to insert toolbar items a saved configuration does not have yet: each `(id, before)` goes right before
    /// the first existing `before` item, or at the end; items already present are left where the user put them.
    /// Applied once per new item set, so later customizations stick.
    static func toolbarInsertions(current: [String], add: [(id: String, before: String?)]) -> [(id: String, index: Int)] {
        var items = current
        var result: [(id: String, index: Int)] = []
        for (id, before) in add where !items.contains(id) {
            let index = before.flatMap { items.firstIndex(of: $0) } ?? items.count
            items.insert(id, at: index)
            result.append((id, index))
        }
        return result
    }
}
