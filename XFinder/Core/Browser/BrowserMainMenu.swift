import AppKit
import SwiftUI

/// XF-T30 W1 (Q-T30-13) — the browser's own menus (File, Edit, View, Go, Window items) while a browser window is key,
/// built from `BrowserCommands` (titles + chords) and dispatched to that window's model. Probe first: if SwiftUI's
/// menu management overwrites inserted menus, ship the fallback (no menu changes) and record it. W1 builder (chrome).
///
/// UNMEASURED (see `${scratchpad}/w1-c/menu-probe.txt` for the full reasoning): this builder cannot launch the GUI
/// app. The approach below — inserting tagged `NSMenuItem`s into the existing File/View/Window submenus plus one new
/// "Đi" (Go) top-level menu on `becomeKey`, removing exactly those same item instances on `resignKey` — is reasoned
/// from documented AppKit/SwiftUI behavior (XFinder's own `.commands` block is static, not `@FocusedValue`-scoped,
/// and nothing else in the app replaces `NSApp.mainMenu` wholesale), not verified against a running binary. If it
/// turns out SwiftUI rebuilds the menu bar more aggressively than reasoned here, the safe fallback is to make
/// `activate(for:)` a no-op — every command stays reachable through the toolbar's "…" Action menu, the pane/sidebar
/// context menus, and the command palette, none of which touch the main menu.
@MainActor
final class BrowserMainMenu {
    static let shared = BrowserMainMenu()

    /// Items this class itself inserted, so `deactivate()` removes exactly those (not merely "whatever a tag
    /// matches"), tracked as `(menu, item)` pairs since different submenus can each hold several.
    private var insertedItems: [(menu: NSMenu, item: NSMenuItem)] = []
    private weak var activeModel: BrowserWindowModel?

    private init() {
        // XF-T38, measured in the Atlas helper: when the app is launched BY opening a browser window (xfinder://browser),
        // the window becomes key before SwiftUI has finished installing its menu bar, and SwiftUI's install then drops
        // the items inserted here — the menu bar showed "XFinder · Edit · View · Window · Help", no Tệp and no Đi, until
        // another browser window became key. AppKit posts didUpdate after each batch of events (never while idle), so
        // re-checking there costs nothing at rest and puts the menus back right after SwiftUI's change.
        updateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didUpdateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { BrowserMainMenu.shared.ensureInstalled() }
        }
    }

    private var updateObserver: NSObjectProtocol?
    private var lastActivation: (menu: ObjectIdentifier, at: Date)?

    /// A browser window is key but its top-level menus are no longer in the menu bar (the bar was replaced or rebuilt):
    /// insert everything again — at most twice a second for the same menu bar, so a menu bar that keeps rebuilding
    /// cannot turn this into a loop.
    func ensureInstalled() {
        guard let model = activeModel, let mainMenu = NSApp.mainMenu else { return }
        guard insertedTopLevel.isEmpty || !insertedTopLevel.allSatisfy({ mainMenu.items.contains($0) }) else { return }
        if let last = lastActivation, last.menu == ObjectIdentifier(mainMenu), Date().timeIntervalSince(last.at) < 0.5 { return }
        activate(for: model)
    }

    /// A browser window became key: show the browser's menus for `model` (XF-T38: `BrowserMenuLayout` decides what goes
    /// where, in FileOctopus 1.0.10's order). Idempotent — calling it again first removes whatever was inserted last.
    func activate(for model: BrowserWindowModel) {
        deactivate()
        activeModel = model
        recentFoldersModel = model
        savedSearchesModel = model
        BrowserMenuState.shared.model = model   // the SwiftUI command groups (Edit, View, Window, app menu) follow this
        guard let mainMenu = NSApp.mainMenu else { return }
        lastActivation = (ObjectIdentifier(mainMenu), Date())

        // Tệp and Đi are the browser's own top-level menus. XFinder's SwiftUI menu bar has no File menu (measured in the
        // Atlas helper: "XFinder · Edit · View · Window · Help"). Items inserted INTO SwiftUI's Edit/View/Window menus
        // were wiped when SwiftUI rebuilt them (measured: View showed only Hide Tab Bar / Show All Tabs / Enter Full
        // Screen) — those blocks are `BrowserMenuCommands`, declared through SwiftUI's own `.commands`.
        insertTopLevel(.file, at: min(1, mainMenu.items.count), in: mainMenu)
        let windowIndex = mainMenu.items.firstIndex { ["Window", "Cửa sổ"].contains($0.title) } ?? mainMenu.items.count
        insertTopLevel(.go, at: windowIndex, in: mainMenu)
    }

    /// No browser window is key any more: remove everything the browser inserted.
    func deactivate() {
        for (menu, item) in insertedItems where menu.items.contains(item) {
            menu.removeItem(item)
        }
        insertedItems.removeAll()
        if let mainMenu = NSApp.mainMenu {
            for item in insertedTopLevel where mainMenu.items.contains(item) { mainMenu.removeItem(item) }
        }
        insertedTopLevel.removeAll()
        synthesizedMenus.removeAll()
        dynamicSubmenus.removeAll()
        BrowserMenuState.shared.model = nil
        activeModel = nil
        recentFoldersModel = nil
        savedSearchesModel = nil
    }

    // MARK: - Building blocks

    /// Top-level menus the browser adds (Tệp, Đi) and the NSMenus it rebuilds whenever they open, keyed by identity.
    private var insertedTopLevel: [NSMenuItem] = []
    private var synthesizedMenus: [ObjectIdentifier: BrowserMenuLayout.Menu] = [:]
    private var dynamicSubmenus: [ObjectIdentifier: BrowserMenuLayout.Submenu] = [:]
    private lazy var menuDelegate = LayoutMenuDelegate(owner: self)

    private func submenu(in mainMenu: NSMenu, matching titles: [String]) -> NSMenu? {
        mainMenu.items.first { item in titles.contains(item.title) }?.submenu
    }

    private func insertTopLevel(_ layoutMenu: BrowserMenuLayout.Menu, at index: Int, in mainMenu: NSMenu) {
        let title = L10n.t(BrowserMenuLayout.titleKey(layoutMenu))
        let menu = NSMenu(title: title)
        menu.delegate = menuDelegate
        synthesizedMenus[ObjectIdentifier(menu)] = layoutMenu
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.insertItem(item, at: max(0, min(index, mainMenu.items.count)))
        insertedTopLevel.append(item)
        rebuild(menu, as: layoutMenu)
    }

    /// Fills a browser-owned top-level menu from scratch — runs every time it opens, so Open With, Tags and the
    /// enabled states always describe the current selection.
    fileprivate func rebuild(_ menu: NSMenu, as layoutMenu: BrowserMenuLayout.Menu) {
        menu.removeAllItems()
        guard let model = activeModel else { return }
        for item in makeItems(BrowserMenuLayout.entries(layoutMenu), model: model) { menu.addItem(item) }
    }

    private func makeItems(_ entries: [BrowserMenuLayout.Entry], model: BrowserWindowModel) -> [NSMenuItem] {
        entries.map { entry in
            switch entry {
            case .separator:
                return .separator()
            case .command(let command):
                return commandItem(command, model: model)
            case .link(let link):
                let item = NSMenuItem(title: L10n.t(BrowserMenuLayout.titleKey(link)), action: #selector(dispatchLink(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = link.rawValue
                return item
            case .action(let action):
                let item = NSMenuItem(title: L10n.t(BrowserMenuLayout.titleKey(action)), action: #selector(dispatchAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action.rawValue
                return item
            case .submenu(let submenu):
                return submenuItem(submenu, model: model)
            }
        }
    }

    private func commandItem(_ command: BrowserCommand, model: BrowserWindowModel) -> NSMenuItem {
        let item = NSMenuItem(title: L10n.t(BrowserCommands.titleKey(command)), action: #selector(dispatch(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Box(command: command, model: model)
        applyKeyEquivalent(command, to: item)
        return item
    }

    private func submenuItem(_ submenu: BrowserMenuLayout.Submenu, model: BrowserWindowModel) -> NSMenuItem {
        let pane = model.active
        switch submenu {
        case .openWith:
            return BrowserContextMenu.openWithItem(model: model, pane: pane)   // resolves its apps itself, off main
        case .tags:
            return BrowserContextMenu.tagsItem(model: model, pane: pane)
        case .recentFolders, .savedSearches:
            let title = L10n.t(BrowserMenuLayout.titleKey(submenu))
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            menu.autoenablesItems = false
            menu.delegate = submenu == .recentFolders ? recentFoldersMenuDelegate : savedSearchesMenuDelegate
            item.submenu = menu
            return item
        default:
            let title = L10n.t(BrowserMenuLayout.titleKey(submenu))
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            if let entries = BrowserMenuLayout.entries(submenu) {
                for child in makeItems(entries, model: model) { menu.addItem(child) }
            } else {
                menu.delegate = menuDelegate
                dynamicSubmenus[ObjectIdentifier(menu)] = submenu
            }
            item.submenu = menu
            return item
        }
    }

    /// Group By / Sort By / the workspace lists: rebuilt each time they open (checkmarks, the store's current names).
    fileprivate func rebuildDynamic(_ menu: NSMenu, as submenu: BrowserMenuLayout.Submenu) {
        menu.removeAllItems()
        guard let model = activeModel else { return }
        let pane = model.active
        switch submenu {
        case .groupBy, .sortBy:
            let built = submenu == .groupBy ? BrowserContextMenu.groupBySubmenu(model: model, pane: pane)
                                            : BrowserContextMenu.sortBySubmenu(model: model, pane: pane)
            for item in built.submenu?.items ?? [] {
                built.submenu?.removeItem(item)
                menu.addItem(item)
            }
        case .openWorkspace, .renameWorkspace, .duplicateWorkspace, .deleteWorkspace:
            let workspaces = model.workspaces
            if workspaces.isEmpty {
                let empty = NSMenuItem(title: L10n.t("Chưa có workspace đã lưu"), action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            for workspace in workspaces {
                let item = NSMenuItem(title: workspace.name, action: #selector(dispatchWorkspace(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = WorkspaceBox(id: workspace.id, name: workspace.name, submenu: submenu)
                menu.addItem(item)
            }
        default:
            break
        }
    }

    private final class LayoutMenuDelegate: NSObject, NSMenuDelegate {
        private weak var owner: BrowserMainMenu?
        init(owner: BrowserMainMenu) { self.owner = owner }

        func menuNeedsUpdate(_ menu: NSMenu) {
            MainActor.assumeIsolated {   // AppKit calls menu delegates on the main thread
                guard let owner else { return }
                if let layoutMenu = owner.synthesizedMenus[ObjectIdentifier(menu)] {
                    owner.rebuild(menu, as: layoutMenu)
                } else if let submenu = owner.dynamicSubmenus[ObjectIdentifier(menu)] {
                    owner.rebuildDynamic(menu, as: submenu)
                }
            }
        }
    }

    private final class WorkspaceBox: NSObject {
        let id: UUID
        let name: String
        let submenu: BrowserMenuLayout.Submenu
        init(id: UUID, name: String, submenu: BrowserMenuLayout.Submenu) { self.id = id; self.name = name; self.submenu = submenu }
    }

    /// A FileOctopus item XFinder covers with a page of its own: open that page in XFinder's main window.
    @objc private func dispatchLink(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let link = BrowserMenuLayout.Link(rawValue: raw) else { return }
        AppState.shared.navigate(to: link.destination)
    }

    @objc private func dispatchAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = BrowserMenuLayout.Action(rawValue: raw) else { return }
        run(action)
    }

    /// A menu action (AppKit menus and the SwiftUI command groups both land here).
    func run(_ action: BrowserMenuLayout.Action) {
        guard let model = activeModel else { return }
        switch action {
        case .exportWorkspaces:
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "XFinder Workspaces.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try model.exportWorkspaces().write(to: url, options: .atomic)
            } catch {
                model.banner = "Không xuất được các workspace"
            }
        }
    }

    @objc private func dispatchWorkspace(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? WorkspaceBox else { return }
        run(box.submenu, workspace: box.id, name: box.name)
    }

    /// Open / rename / duplicate / delete one saved workspace (Window ▸ … ▸ name).
    func run(_ submenu: BrowserMenuLayout.Submenu, workspace id: UUID, name: String) {
        guard let model = activeModel else { return }
        let box = (id: id, name: name, submenu: submenu)
        switch box.submenu {
        case .openWorkspace:
            model.openWorkspace(box.id)
        case .duplicateWorkspace:
            model.duplicateWorkspace(box.id)
        case .renameWorkspace:
            let alert = NSAlert()
            alert.messageText = L10n.t("Đổi tên workspace")
            let field = NSTextField(string: box.name)
            field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: L10n.t("Đổi tên"))
            alert.addButton(withTitle: L10n.t("Huỷ"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            _ = model.renameWorkspace(box.id, to: field.stringValue)
        case .deleteWorkspace:
            let alert = NSAlert()
            alert.messageText = "\(L10n.t("Xoá workspace “"))\(box.name)\(L10n.t("”?"))"
            alert.informativeText = L10n.t("Chỉ xoá bản lưu của workspace. Tệp và thư mục của bạn không đổi.")
            alert.addButton(withTitle: L10n.t("Huỷ"))
            alert.addButton(withTitle: L10n.t("Xoá"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            model.deleteWorkspace(box.id)
        default:
            break
        }
    }

    @objc private func dispatch(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box else { return }
        _ = box.model.perform(box.command)
    }

    /// One folder from Go ▸ Recent Folders was chosen: navigate the active tab there, same as any other Go command.
    @objc private func dispatchRecentFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String, let model = recentFoldersModel else { return }
        model.active.navigate(to: path)
    }

    @objc private func dispatchClearRecentFolders(_ sender: NSMenuItem) {
        guard let model = recentFoldersModel else { return }
        _ = model.perform(.clearRecentFolders)
    }

    // MARK: - Recent Folders submenu (built when opened, contract §3)

    /// The model `dispatchRecentFolder(_:)`/`dispatchClearRecentFolders(_:)` act on — the submenu's own items carry a
    /// plain path (or nothing) in `representedObject`, not a `Box`, so the model is kept here instead.
    private weak var recentFoldersModel: BrowserWindowModel?
    private lazy var recentFoldersMenuDelegate = RecentFoldersMenuDelegate(owner: self)

    /// `NSMenuDelegate` that rebuilds the Recent Folders submenu every time it is about to open — contract §3:
    /// "Thư mục gần đây ▸" (xây khi mở) — so a folder noted since the menu was last shown always shows up, and one
    /// that stopped existing can be dropped (`RecentFolders.existing`).
    private final class RecentFoldersMenuDelegate: NSObject, NSMenuDelegate {
        private weak var owner: BrowserMainMenu?
        init(owner: BrowserMainMenu) { self.owner = owner }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let owner else { return }
            menu.removeAllItems()
            let paths = BrowserSettings.recentFolders.existing { FileManager.default.fileExists(atPath: $0) }
            if paths.isEmpty {
                let empty = NSMenuItem(title: L10n.t("Không có thư mục nào"), action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                for path in paths {
                    let item = NSMenuItem(
                        title: (path as NSString).lastPathComponent, action: #selector(owner.dispatchRecentFolder(_:)), keyEquivalent: ""
                    )
                    item.target = owner
                    item.representedObject = path
                    item.toolTip = path
                    menu.addItem(item)
                }
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(
                title: L10n.t(BrowserCommands.titleKey(.clearRecentFolders)), action: #selector(owner.dispatchClearRecentFolders(_:)),
                keyEquivalent: ""
            )
            clear.target = owner
            clear.isEnabled = !paths.isEmpty
            menu.addItem(clear)
        }
    }

    // MARK: - Saved Searches submenu (XF-T30 W5b, built when opened)

    /// The model `dispatchRunSavedSearch`/`dispatchRenameSavedSearch`/`dispatchDeleteSavedSearch`/
    /// `dispatchToggleSavedSearchSidebar`/`dispatchCopySavedSearchText` act on.
    private weak var savedSearchesModel: BrowserWindowModel?
    private lazy var savedSearchesMenuDelegate = SavedSearchesMenuDelegate(owner: self)

    @objc private func dispatchRunSavedSearch(_ sender: NSMenuItem) {
        guard let saved = sender.representedObject as? SavedSearch, let model = savedSearchesModel else { return }
        model.active.runSavedSearch(saved, paneFolders: model.tree.panes.compactMap { model.panes[$0]?.path })
    }

    /// Contract: "Hiện trong sidebar" is a checkmark TOGGLE on the saved search's own row's submenu, not a separate
    /// command — flips `showInSidebar` in place (`BrowserSidebarView`, a different builder's file, is what actually
    /// reads it to decide whether to draw the row).
    @objc private func dispatchToggleSavedSearchSidebar(_ sender: NSMenuItem) {
        guard let saved = sender.representedObject as? SavedSearch else { return }
        var store = BrowserSettings.savedSearches
        store.setShowInSidebar(saved.id, !saved.showInSidebar)
        BrowserSettings.savedSearches = store
    }

    @objc private func dispatchRenameSavedSearch(_ sender: NSMenuItem) {
        guard let saved = sender.representedObject as? SavedSearch else { return }
        let alert = NSAlert()
        alert.messageText = L10n.t("Đổi tên tìm kiếm đã lưu")
        let field = NSTextField(string: saved.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.t("Đổi tên"))
        alert.addButton(withTitle: L10n.t("Huỷ"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var store = BrowserSettings.savedSearches
        store.rename(saved.id, to: field.stringValue)
        BrowserSettings.savedSearches = store
    }

    @objc private func dispatchDeleteSavedSearch(_ sender: NSMenuItem) {
        guard let saved = sender.representedObject as? SavedSearch else { return }
        var store = BrowserSettings.savedSearches
        store.delete(saved.id)
        BrowserSettings.savedSearches = store
    }

    @objc private func dispatchCopySavedSearchText(_ sender: NSMenuItem) {
        guard let saved = sender.representedObject as? SavedSearch else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(saved.query, forType: .string)
    }

    /// `NSMenuDelegate` that rebuilds "Tìm kiếm đã lưu ▸" every time it is about to open (same reasoning as Recent
    /// Folders): clicking a row runs that search; each row's own submenu carries the four per-item actions the
    /// contract lists (Hiện trong sidebar / Đổi tên / Xoá / Sao chép câu tìm — never deletes the matched files,
    /// only the saved query, per the FileOctopus semantic the data layer already documents).
    private final class SavedSearchesMenuDelegate: NSObject, NSMenuDelegate {
        private weak var owner: BrowserMainMenu?
        init(owner: BrowserMainMenu) { self.owner = owner }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let owner else { return }
            menu.removeAllItems()
            let searches = BrowserSettings.savedSearches.searches
            if searches.isEmpty {
                let empty = NSMenuItem(title: L10n.t("Không có tìm kiếm đã lưu nào"), action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
                return
            }
            for saved in searches {
                let item = NSMenuItem(title: saved.name, action: #selector(owner.dispatchRunSavedSearch(_:)), keyEquivalent: "")
                item.target = owner
                item.representedObject = saved
                item.toolTip = saved.query
                item.submenu = Self.itemSubmenu(for: saved, owner: owner)
                menu.addItem(item)
            }
        }

        private static func itemSubmenu(for saved: SavedSearch, owner: BrowserMainMenu) -> NSMenu {
            let submenu = NSMenu(title: saved.name)
            let showInSidebar = NSMenuItem(
                title: L10n.t("Hiện trong sidebar"), action: #selector(owner.dispatchToggleSavedSearchSidebar(_:)), keyEquivalent: ""
            )
            showInSidebar.target = owner
            showInSidebar.representedObject = saved
            showInSidebar.state = saved.showInSidebar ? .on : .off
            submenu.addItem(showInSidebar)
            submenu.addItem(.separator())
            let rename = NSMenuItem(title: L10n.t("Đổi tên tìm kiếm đã lưu"), action: #selector(owner.dispatchRenameSavedSearch(_:)), keyEquivalent: "")
            rename.target = owner
            rename.representedObject = saved
            submenu.addItem(rename)
            let delete = NSMenuItem(title: L10n.t("Xoá tìm kiếm đã lưu"), action: #selector(owner.dispatchDeleteSavedSearch(_:)), keyEquivalent: "")
            delete.target = owner
            delete.representedObject = saved
            submenu.addItem(delete)
            let copyText = NSMenuItem(title: L10n.t("Sao chép câu tìm"), action: #selector(owner.dispatchCopySavedSearchText(_:)), keyEquivalent: "")
            copyText.target = owner
            copyText.representedObject = saved
            submenu.addItem(copyText)
            return submenu
        }
    }

    /// NSMenu asks before showing an item AND before firing its key equivalent. Review 2026-10-25: ⌘T / ⌘/ fired from
    /// the menu bar while the rename editor, location bar or a search field was being typed in (the window had already
    /// left those plain-⌘ chords to the text, the field editor did not use them, AppKit fell through to the menu). A
    /// plain-⌘ item is off while a field editor is first responder; everything else follows `canPerform`.
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let box = menuItem.representedObject as? Box else { return true }
        menuItem.state = Self.state(of: box.command, model: box.model)
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText,
           let chord = BrowserCommands.chord(for: box.command), !chord.control, !chord.option {
            return false
        }
        return box.model.canPerform(box.command)
    }

    /// Carries both the command and which window's model should receive it — `representedObject` only holds one
    /// value, and the active window can change between when a menu item was built and when it fires.
    /// XF-T38: a checkmark where the command shows a state, as FileOctopus's View menu does (the current view mode,
    /// grouping, hidden files, each bar, the preview, the Shelf).
    private static func state(of command: BrowserCommand, model: BrowserWindowModel) -> NSControl.StateValue {
        (isChecked(command, model: model) ?? false) ? .on : .off
    }

    /// nil for commands that are plain actions; true/false for the ones a menu shows with a checkmark.
    static func isChecked(_ command: BrowserCommand, model: BrowserWindowModel) -> Bool? {
        let pane = model.active
        let on: Bool
        switch command {
        case .viewIcons: on = pane.viewMode == .icons
        case .viewList: on = pane.viewMode == .list
        case .viewColumns: on = pane.viewMode == .columns
        case .viewGallery: on = pane.viewMode == .gallery
        case .useGroups: on = pane.groupBy != .none
        case .toggleHidden: on = pane.showHidden
        case .toggleSidebar: on = BrowserSettings.showSidebar
        case .togglePathBar: on = BrowserSettings.showPathBar
        case .toggleStatusBar: on = BrowserSettings.showStatusBar
        case .toggleLocationBar: on = BrowserSettings.showLocationBar
        case .togglePreview: on = BrowserSettings.showPreview
        case .toggleShelf: on = model.shelfVisible
        default: return nil
        }
        return on
    }

    /// The SwiftUI form of `applyKeyEquivalent` (same chords, same editing-key rule).
    static func keyboardShortcut(for command: BrowserCommand) -> KeyboardShortcut? {
        guard let chord = BrowserCommands.chord(for: command), shared.showsKeyEquivalent(for: chord) else { return nil }
        let key: KeyEquivalent
        switch chord.key {
        case "up": key = .upArrow
        case "down": key = .downArrow
        case "left": key = .leftArrow
        case "right": key = .rightArrow
        case "return": key = .return
        case "delete": key = .delete
        case "tab": key = .tab
        case "space": key = .space
        case "escape": key = .escape
        default:
            guard chord.key.count == 1, let character = chord.key.first else { return nil }
            key = KeyEquivalent(character)
        }
        var modifiers: EventModifiers = []
        if chord.command { modifiers.insert(.command) }
        if chord.shift { modifiers.insert(.shift) }
        if chord.option { modifiers.insert(.option) }
        if chord.control { modifiers.insert(.control) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }

    private final class Box: NSObject {
        let command: BrowserCommand
        let model: BrowserWindowModel
        init(command: BrowserCommand, model: BrowserWindowModel) { self.command = command; self.model = model }
    }

    // MARK: - Key-equivalent restriction

    /// Contract: show a `keyEquivalent` only for a chord carrying ⌃ or ⌥, or one whose bare key sits outside the
    /// standard text-editing set — otherwise a GLOBAL `NSMenuItem.keyEquivalent` (installed on the app's menu bar,
    /// not on the browser window) would steal ⌘C/⌘V/⌘X/⌘A/⌘Z/⌘⌫/Return out of whatever text field has focus
    /// (location bar, filter, search, rename editor, command palette) system-wide, bypassing the per-window
    /// carve-out `BrowserWindow.performKeyEquivalent` already does for exactly these chords.
    private static let editingKeys: Set<String> = ["c", "v", "x", "a", "z", "delete", "return"]

    private func showsKeyEquivalent(for chord: KeyChord) -> Bool {
        if chord.control || chord.option { return true }
        return !Self.editingKeys.contains(chord.key)
    }

    private func applyKeyEquivalent(_ command: BrowserCommand, to item: NSMenuItem) {
        guard let chord = BrowserCommands.chord(for: command), showsKeyEquivalent(for: chord) else { return }
        item.keyEquivalent = menuKeyEquivalentCharacter(for: chord.key)
        var mask: NSEvent.ModifierFlags = []
        if chord.command { mask.insert(.command) }
        if chord.shift { mask.insert(.shift) }
        if chord.option { mask.insert(.option) }
        if chord.control { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
    }

    /// `KeyChord.key` uses the same named-key strings `BrowserCommands.display` draws glyphs for; `NSMenuItem`
    /// wants the literal character `NSEvent` would report instead (e.g. `NSUpArrowFunctionKey`), or the plain
    /// lowercase letter for everything else.
    private func menuKeyEquivalentCharacter(for key: String) -> String {
        switch key {
        case "return": return "\r"
        case "delete": return String(UnicodeScalar(NSDeleteCharacter)!)
        case "space": return " "
        case "left": return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case "right": return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case "up": return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case "down": return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case "escape": return String(UnicodeScalar(27))
        case "tab": return "\t"
        default: return key
        }
    }
}

// MARK: - The browser's blocks in SwiftUI's own menus (XF-T38)

/// Which browser window the menu bar serves right now (nil = no browser window is key). `BrowserMainMenu` sets it;
/// `BrowserMenuCommands` reads it, so SwiftUI shows or hides the browser blocks itself.
@MainActor
@Observable
final class BrowserMenuState {
    static let shared = BrowserMenuState()
    var model: BrowserWindowModel?
    private init() {}
}

/// The browser's items in SwiftUI's Edit, View and Window menus and in the app menu — declared through `.commands`
/// so SwiftUI keeps them (items inserted into those menus from outside were wiped on its next rebuild, measured). They
/// render only while a browser window is key; titles, order and submenus come from `BrowserMenuLayout`.
struct BrowserMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appSettings) { BrowserMenuBlock(menu: .app) }
        CommandGroup(after: .pasteboard) { BrowserMenuBlock(menu: .edit) }
        CommandGroup(before: .toolbar) { BrowserMenuBlock(menu: .view) }
        CommandGroup(before: .windowList) { BrowserMenuBlock(menu: .window) }
    }
}

struct BrowserMenuBlock: View {
    let menu: BrowserMenuLayout.Menu

    var body: some View {
        if let model = BrowserMenuState.shared.model {
            if menu == .edit || menu == .window { Divider() }
            BrowserMenuEntries(entries: menu == .app ? BrowserMenuLayout.entries(.app).filter { $0 != .command(.openBrowserSettings) }
                                                      : BrowserMenuLayout.entries(menu),
                               model: model)
            if menu == .view || menu == .window { Divider() }
        }
    }
}

struct BrowserMenuEntries: View {
    let entries: [BrowserMenuLayout.Entry]
    let model: BrowserWindowModel

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .separator:
                Divider()
            case .command(let command):
                BrowserMenuCommandItem(command: command, model: model)
            case .link(let link):
                Button(L10n.t(BrowserMenuLayout.titleKey(link))) { AppState.shared.navigate(to: link.destination) }
            case .action(let action):
                Button(L10n.t(BrowserMenuLayout.titleKey(action))) { BrowserMainMenu.shared.run(action) }
            case .submenu(let submenu):
                Menu(L10n.t(BrowserMenuLayout.titleKey(submenu))) { BrowserSubmenuEntries(submenu: submenu, model: model) }
            }
        }
    }
}

struct BrowserSubmenuEntries: View {
    let submenu: BrowserMenuLayout.Submenu
    let model: BrowserWindowModel

    var body: some View {
        if let entries = BrowserMenuLayout.entries(submenu) {
            BrowserMenuEntries(entries: entries, model: model)
        } else {
            switch submenu {
            case .groupBy:
                ForEach(GroupBy.allCases, id: \.self) { group in
                    Toggle(L10n.t(group.titleKey), isOn: Binding(get: { model.active.groupBy == group },
                                                                 set: { _ in model.active.groupBy = group }))
                }
            case .sortBy:
                ForEach(SortKey.allCases, id: \.self) { key in
                    Toggle(L10n.t(BrowserContextMenu.sortKeyTitleKey(key)),
                           isOn: Binding(get: { model.active.sort.key == key },
                                         set: { _ in model.active.sort = SortOrder(key: key, ascending: model.active.sort.ascending) }))
                }
            case .openWorkspace, .renameWorkspace, .duplicateWorkspace, .deleteWorkspace:
                if model.workspaces.isEmpty {
                    Button(L10n.t("Chưa có workspace đã lưu")) {}.disabled(true)
                }
                ForEach(model.workspaces) { workspace in
                    Button(workspace.name) { BrowserMainMenu.shared.run(submenu, workspace: workspace.id, name: workspace.name) }
                }
            default:
                EmptyView()
            }
        }
    }
}

struct BrowserMenuCommandItem: View {
    let command: BrowserCommand
    let model: BrowserWindowModel

    var body: some View {
        let title = L10n.t(BrowserCommands.titleKey(command))
        Group {
            if let isOn = BrowserMainMenu.isChecked(command, model: model) {
                Toggle(title, isOn: Binding(get: { isOn }, set: { _ in _ = model.perform(command) }))
            } else {
                Button(title) { _ = model.perform(command) }
            }
        }
        .disabled(!model.canPerform(command))
        .modifier(BrowserMenuShortcut(command: command))
    }
}

/// The command's chord as the menu's shortcut glyph — same rule as the AppKit menus: plain ⌘ + an editing key (copy,
/// paste, cut, select all, undo, delete, return) is left to the text system, so typing in a field is never hijacked.
struct BrowserMenuShortcut: ViewModifier {
    let command: BrowserCommand

    func body(content: Content) -> some View {
        if let shortcut = BrowserMainMenu.keyboardShortcut(for: command) {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}
