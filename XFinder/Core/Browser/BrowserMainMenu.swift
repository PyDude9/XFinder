import AppKit

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
    private var insertedGoMenuItem: NSMenuItem?
    private weak var activeModel: BrowserWindowModel?

    private init() {}

    /// A browser window became key: show menus for `model`. Idempotent — calling it again (e.g. the same window
    /// re-gaining key status, or a defensive re-arm) first removes whatever this class last inserted.
    func activate(for model: BrowserWindowModel) {
        deactivate()
        activeModel = model
        guard let mainMenu = NSApp.mainMenu else { return }

        if let fileMenu = submenu(in: mainMenu, matching: ["File", "Tệp"]) {
            insert(.newWindowTab, into: fileMenu, model: model, before: 0)
            insert(.closeWindow, into: fileMenu, model: model, before: 1)
        }
        if let viewMenu = submenu(in: mainMenu, matching: ["View", "Xem"]) {
            var index = 0
            for command: BrowserCommand in [.viewIcons, .viewList, .viewColumns, .viewGallery] {
                insert(command, into: viewMenu, model: model, before: index)
                index += 1
            }
            insertSeparator(into: viewMenu, before: index)
            index += 1
            for command: BrowserCommand in [.toggleLocationBar, .togglePathBar, .toggleStatusBar, .toggleSidebar, .toggleToolbar] {
                insert(command, into: viewMenu, model: model, before: index)
                index += 1
            }
        }
        if let windowMenu = submenu(in: mainMenu, matching: ["Window", "Cửa sổ"]) {
            insert(.newPaneTab, into: windowMenu, model: model, before: 0)
            insert(.closePane, into: windowMenu, model: model, before: 1)
            insertSeparator(into: windowMenu, before: 2)
        }
        insertGoMenu(into: mainMenu, model: model)
    }

    /// No browser window is key any more: remove the browser menus.
    func deactivate() {
        for (menu, item) in insertedItems where menu.items.contains(item) {
            menu.removeItem(item)
        }
        insertedItems.removeAll()
        if let goItem = insertedGoMenuItem, let mainMenu = NSApp.mainMenu, mainMenu.items.contains(goItem) {
            mainMenu.removeItem(goItem)
        }
        insertedGoMenuItem = nil
        activeModel = nil
        recentFoldersModel = nil
        savedSearchesModel = nil
    }

    // MARK: - Building blocks

    private func submenu(in mainMenu: NSMenu, matching titles: [String]) -> NSMenu? {
        mainMenu.items.first { item in titles.contains(item.title) }?.submenu
    }

    @discardableResult
    private func insert(_ command: BrowserCommand, into menu: NSMenu, model: BrowserWindowModel, before index: Int) -> NSMenuItem {
        let item = NSMenuItem(title: L10n.t(BrowserCommands.titleKey(command)), action: #selector(dispatch(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Box(command: command, model: model)
        applyKeyEquivalent(command, to: item)
        let clampedIndex = max(0, min(index, menu.items.count))
        menu.insertItem(item, at: clampedIndex)
        insertedItems.append((menu, item))
        return item
    }

    private func insertSeparator(into menu: NSMenu, before index: Int) {
        let item = NSMenuItem.separator()
        let clampedIndex = max(0, min(index, menu.items.count))
        menu.insertItem(item, at: clampedIndex)
        insertedItems.append((menu, item))
    }

    /// A brand-new top-level "Đi" (Go) menu, inserted right before "Window" — fully synthetic, so it cannot collide
    /// with any `CommandMenu`/`CommandGroup` SwiftUI's `.commands` block already declares. Contract §3: every Go
    /// command, plus a "Thư mục gần đây" (Recent Folders) submenu built when it opens, plus Clear Menu.
    private func insertGoMenu(into mainMenu: NSMenu, model: BrowserWindowModel) {
        let goMenu = NSMenu(title: L10n.t("Đi"))
        let goItem = NSMenuItem(title: L10n.t("Đi"), action: nil, keyEquivalent: "")
        goItem.submenu = goMenu

        let primaryCommands: [BrowserCommand] = [.openEnclosing, .goToFolder, .editLocation, .quickOpen]
        for command in primaryCommands {
            addCommandItem(command, to: goMenu, model: model)
        }
        goMenu.addItem(.separator())

        let destinationCommands: [BrowserCommand] = [
            .goRecents, .goDocuments, .goDesktop, .goDownloads, .goHome, .goAirDrop, .goNetwork, .goICloud,
            .goApplications, .goUtilities, .goComputer,
        ]
        for command in destinationCommands {
            addCommandItem(command, to: goMenu, model: model)
        }
        goMenu.addItem(.separator())

        let recentItem = NSMenuItem(title: L10n.t("Thư mục gần đây"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: L10n.t("Thư mục gần đây"))
        recentMenu.delegate = recentFoldersMenuDelegate
        recentMenu.autoenablesItems = false
        recentItem.submenu = recentMenu
        recentFoldersModel = model
        goMenu.addItem(recentItem)
        goMenu.addItem(.separator())

        // XF-T30 W5b — "Tìm kiếm đã lưu" (contract §"Tìm đã lưu": "menu Đi ▸ Tìm kiếm đã lưu (Hiện trong sidebar /
        // Đổi tên / Xoá / Sao chép câu tìm)"), built fresh each time it opens, same pattern as Recent Folders above.
        let savedSearchesItem = NSMenuItem(title: L10n.t("Tìm kiếm đã lưu"), action: nil, keyEquivalent: "")
        let savedSearchesMenu = NSMenu(title: L10n.t("Tìm kiếm đã lưu"))
        savedSearchesMenu.delegate = savedSearchesMenuDelegate
        savedSearchesMenu.autoenablesItems = false
        savedSearchesItem.submenu = savedSearchesMenu
        savedSearchesModel = model
        goMenu.addItem(savedSearchesItem)
        goMenu.addItem(.separator())

        for command: BrowserCommand in [.connectToServer, .eject] {
            addCommandItem(command, to: goMenu, model: model)
        }

        let windowMenuIndex = mainMenu.items.firstIndex { ["Window", "Cửa sổ"].contains($0.title) } ?? mainMenu.items.count
        mainMenu.insertItem(goItem, at: windowMenuIndex)
        insertedGoMenuItem = goItem
    }

    private func addCommandItem(_ command: BrowserCommand, to menu: NSMenu, model: BrowserWindowModel) {
        let item = NSMenuItem(title: L10n.t(BrowserCommands.titleKey(command)), action: #selector(dispatch(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Box(command: command, model: model)
        applyKeyEquivalent(command, to: item)
        menu.addItem(item)
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
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText,
           let chord = BrowserCommands.chord(for: box.command), !chord.control, !chord.option {
            return false
        }
        return box.model.canPerform(box.command)
    }

    /// Carries both the command and which window's model should receive it — `representedObject` only holds one
    /// value, and the active window can change between when a menu item was built and when it fires.
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
