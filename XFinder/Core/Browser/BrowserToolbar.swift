import AppKit
import SwiftUI

/// XF-T30 W1 — the browser window's native `NSToolbar` (FileOctopus order: Back/Forward, View, Group, Pane Layout,
/// Share, Action, Search; customizable, plus Enclosing Folder, Go to Folder, Workspaces, Shelf, Operations).
/// Contract docs/specs/XF-T30-w1-contract.md §5. W1 builder (chrome): implement.
///
/// One instance per browser window (the contract: "controller giữ strong"); `BrowserWindowController` keeps it
/// alive for the window's lifetime. Every item's enabled/selected state is kept in step with the model through
/// `withObservationTracking`, re-armed after each fire (the pattern already used by `BrowserWindowController`'s
/// own `observeTitle`/`observeQuickLookSelection`): `onChange` fires once per registration, so each handler below
/// re-registers itself at its own end, and all closures capture `self` weakly so a closed window's toolbar (and
/// the `NSToolbar`/`NSWindow` it references) can still be freed once nothing else references it.
@MainActor
final class BrowserToolbarController: NSObject, NSToolbarDelegate, BrowserChrome {
    private enum ID {
        static let backForward = NSToolbarItem.Identifier("com.xfinder.browser.backForward")
        static let view = NSToolbarItem.Identifier("com.xfinder.browser.view")
        static let group = NSToolbarItem.Identifier("com.xfinder.browser.group")
        static let paneLayout = NSToolbarItem.Identifier("com.xfinder.browser.paneLayout")
        static let share = NSToolbarItem.Identifier("com.xfinder.browser.share")
        static let action = NSToolbarItem.Identifier("com.xfinder.browser.action")
        static let search = NSToolbarItem.Identifier("com.xfinder.browser.search")
        static let enclosingFolder = NSToolbarItem.Identifier("com.xfinder.browser.enclosingFolder")
        static let goToFolder = NSToolbarItem.Identifier("com.xfinder.browser.goToFolder")
        static let workspaces = NSToolbarItem.Identifier("com.xfinder.browser.workspaces")
        static let shelf = NSToolbarItem.Identifier("com.xfinder.browser.shelf")
        static let operations = NSToolbarItem.Identifier("com.xfinder.browser.operations")
    }

    let model: BrowserWindowModel
    weak var window: NSWindow?
    private var toolbar: NSToolbar?

    private var backForwardControl: NSSegmentedControl?
    private var paneLayoutItem: NSToolbarItem?
    private var shelfItem: NSToolbarItem?
    private var operationsItem: NSToolbarItem?
    private var searchItem: NSSearchToolbarItem?
    private weak var operationsPopover: NSPopover?
    /// Identity references for `menuNeedsUpdate` to tell the four context-sensitive pull-down menus apart —
    /// comparing the delegate callback's `menu` by reference, not by re-deriving it from the toolbar's current
    /// items (a customizable toolbar can have an item removed by the user, at which point `toolbar.items` no
    /// longer contains it at all, but a still-open or still-cached `NSMenu` reference stays valid).
    private weak var groupMenuRef: NSMenu?
    private weak var actionMenuRef: NSMenu?
    private weak var workspacesMenuRef: NSMenu?
    private weak var paneLayoutMenuRef: NSMenu?

    /// Guards the two re-entrant `onChange` chains below (history + badge) against firing after `install()`'s
    /// window has been torn down — `BrowserWindowController.windowClosed` drops every strong reference to this
    /// controller, but an in-flight `Task` scheduled by `onChange` right before that still runs once.
    private var tornDown = false

    init(model: BrowserWindowModel, window: NSWindow) {
        self.model = model
        self.window = window
        super.init()
    }

    /// Builds the toolbar, attaches it to `window`, and becomes `model.chrome`.
    func install() {
        model.chrome = self
        let toolbar = NSToolbar(identifier: "XFinderBrowserToolbar.v1")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        self.toolbar = toolbar
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
        observeBackForward()
        observePaneLayoutIcon()
        observeOperationsBadge()
    }

    func tearDown() {
        tornDown = true
        operationsPopover?.performClose(nil)
    }

    // MARK: - BrowserChrome

    func focusSearchField() {
        searchItem?.beginSearchInteraction()
    }

    func toggleToolbarShown() { window?.toggleToolbarShown(nil) }
    func runToolbarCustomization() { window?.runToolbarCustomizationPalette(nil) }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ID.backForward, ID.view, ID.group, ID.paneLayout, .flexibleSpace, ID.share, ID.action, ID.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [
            ID.enclosingFolder, ID.goToFolder, ID.workspaces, ID.shelf, ID.operations,
            .flexibleSpace, .space,
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case ID.backForward: return makeBackForwardItem()
        case ID.view: return makeViewItem()
        case ID.group: return makeGroupItem()
        case ID.paneLayout: return makePaneLayoutItem()
        case ID.share: return makeShareItem()
        case ID.action: return makeActionItem()
        case ID.search: return makeSearchItem()
        case ID.enclosingFolder: return makeButtonItem(ID.enclosingFolder, command: .openEnclosing, symbol: "arrow.up.square")
        case ID.goToFolder: return makeButtonItem(ID.goToFolder, command: .goToFolder, symbol: "arrow.right.doc.on.clipboard")
        case ID.workspaces: return makeWorkspacesItem()
        case ID.shelf: return makeShelfItem()
        case ID.operations: return makeOperationsItem()
        default: return nil
        }
    }

    // MARK: - Back / Forward

    /// Two momentary segments; press-and-hold on either shows that direction's history as a jump list
    /// (`setMenu(_:forSegment:)`), nearest visit on top, firing `goBack(steps:)`/`goForward(steps:)`.
    private func makeBackForwardItem() -> NSToolbarItem {
        let control = NSSegmentedControl()
        control.segmentStyle = .separated
        control.trackingMode = .momentary
        control.segmentCount = 2
        control.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: L10n.t("Lùi lại")), forSegment: 0)
        control.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: L10n.t("Tiến tới")), forSegment: 1)
        control.target = self
        control.action = #selector(backForwardClicked(_:))
        backForwardControl = control
        refreshBackForward()

        let item = NSToolbarItem(itemIdentifier: ID.backForward)
        item.view = control
        item.label = L10n.t("Lùi lại")
        item.paletteLabel = L10n.t("Lùi lại")
        return item
    }

    @objc private func backForwardClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            _ = model.perform(.back)
        } else {
            _ = model.perform(.forward)
        }
    }

    /// Re-arms itself after every change (the `withObservationTracking` pattern this file follows throughout):
    /// enabled state and the two jump-list menus both track the ACTIVE pane's own history, so switching panes
    /// updates the toolbar immediately, same as switching tabs would once pane tabs exist.
    private func observeBackForward() {
        withObservationTracking {
            _ = model.activePane
            _ = model.active.history
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.tornDown else { return }
                self.refreshBackForward()
                self.observeBackForward()
            }
        }
    }

    private func refreshBackForward() {
        guard let control = backForwardControl else { return }
        let history = model.active.history
        control.setEnabled(history.canGoBack, forSegment: 0)
        control.setEnabled(history.canGoForward, forSegment: 1)
        control.setMenu(historyMenu(history.back.reversed(), goingBack: true), forSegment: 0)
        control.setMenu(historyMenu(history.forward.reversed(), goingBack: false), forSegment: 1)
    }

    /// `entries`: most-recent-first (the caller already reversed the stack) — the menu's top item is one step away.
    private func historyMenu(_ entries: [String], goingBack: Bool) -> NSMenu? {
        guard !entries.isEmpty else { return nil }
        let menu = NSMenu()
        for (index, path) in entries.enumerated() {
            let item = NSMenuItem(title: (path as NSString).lastPathComponent, action: #selector(historyMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = HistoryJump(steps: index + 1, goingBack: goingBack)
            menu.addItem(item)
        }
        return menu
    }

    private final class HistoryJump: NSObject {
        let steps: Int
        let goingBack: Bool
        init(steps: Int, goingBack: Bool) { self.steps = steps; self.goingBack = goingBack }
    }

    @objc private func historyMenuItemClicked(_ sender: NSMenuItem) {
        guard let jump = sender.representedObject as? HistoryJump else { return }
        if jump.goingBack {
            model.active.goBack(steps: jump.steps)
        } else {
            model.active.goForward(steps: jump.steps)
        }
    }

    // MARK: - View

    /// Icons/List/Columns/Gallery, ⌘1–4 (the chord is only a label hint here — `BrowserWindow.performKeyEquivalent`
    /// is the actual dispatcher).
    private func makeViewItem() -> NSToolbarItem {
        let control = NSSegmentedControl()
        control.segmentStyle = .separated
        control.trackingMode = .selectOne
        control.segmentCount = 4
        let symbols = ["square.grid.2x2", "list.bullet", "rectangle.split.3x1", "rectangle.grid.1x2"]
        let labels = [L10n.t("Xem dạng biểu tượng"), L10n.t("Xem dạng danh sách"), L10n.t("Xem dạng cột"), L10n.t("Xem dạng gallery")]
        for (i, symbol) in symbols.enumerated() {
            control.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: labels[i]), forSegment: i)
        }
        control.target = self
        control.action = #selector(viewSegmentClicked(_:))
        syncViewSegment(control)

        let item = NSToolbarItem(itemIdentifier: ID.view)
        item.view = control
        item.label = L10n.t("Xem")
        item.paletteLabel = L10n.t("Xem")
        observeViewMode(control: control)
        return item
    }

    private func syncViewSegment(_ control: NSSegmentedControl) {
        let index: Int
        switch model.active.viewMode {
        case .icons: index = 0
        case .list: index = 1
        case .columns: index = 2
        case .gallery: index = 3
        }
        control.selectedSegment = index
    }

    @objc private func viewSegmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: _ = model.perform(.viewIcons)
        case 1: _ = model.perform(.viewList)
        case 2: _ = model.perform(.viewColumns)
        default: _ = model.perform(.viewGallery)
        }
    }

    private func observeViewMode(control: NSSegmentedControl) {
        withObservationTracking {
            _ = model.activePane
            _ = model.active.viewMode
        } onChange: { [weak self, weak control] in
            Task { @MainActor in
                guard let self, !self.tornDown, let control else { return }
                self.syncViewSegment(control)
                self.observeViewMode(control: control)
            }
        }
    }

    /// An image-only pull-down button: AppKit's `NSButton` has no "show this menu on click" switch of its own
    /// (that is a SwiftUI `Menu` behavior) — a pull-down `NSPopUpButton` is the AppKit equivalent, showing `menu`
    /// immediately on click with no extra target/action wiring. `pullsDown` buttons display their FIRST menu item
    /// as the button's own face, so that item carries the image and is otherwise inert (no action, no target).
    private func makeMenuButton(image: NSImage, title: String, menu: NSMenu) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .texturedRounded
        let faceItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        faceItem.image = image
        menu.insertItem(faceItem, at: 0)
        button.menu = menu
        button.imagePosition = .imageOnly
        button.toolTip = title
        return button
    }

    // MARK: - Group / Sort By

    /// Icon/List/Column ⇒ "Group By" (`GroupBy.allCases` + Use Groups, ⌃⌘0); Gallery ⇒ "Sort By" (`SortKey`,
    /// Gallery "has no groups" per the reference app). Same button, menu rebuilt on open from the active pane's
    /// current view mode — `NSMenuDelegate.menuNeedsUpdate` rebuilds the real items below the inert face item
    /// every time the menu opens, since the view mode can change without this toolbar item itself being rebuilt.
    private func makeGroupItem() -> NSToolbarItem {
        let title = L10n.t("Dùng nhóm")
        let image = NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: title)!
        let button = makeMenuButton(image: image, title: title, menu: groupMenu())

        let item = NSToolbarItem(itemIdentifier: ID.group)
        item.view = button
        item.label = title
        item.paletteLabel = title
        return item
    }

    private func groupMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        rebuildGroupMenu(menu)
        groupMenuRef = menu
        return menu
    }

    /// Pull-down menus built by `makeMenuButton` keep an inert face item at index 0 (the button's own face/image) —
    /// every rebuild here clears everything AFTER it instead of `removeAllItems()`, which would also delete the
    /// face and leave the button showing no image at all.
    private func clearMenuKeepingFace(_ menu: NSMenu) {
        while menu.items.count > 1 {
            menu.removeItem(at: menu.items.count - 1)
        }
    }

    private func rebuildGroupMenu(_ menu: NSMenu) {
        clearMenuKeepingFace(menu)
        if model.active.viewMode == .gallery {
            for key in SortKey.allCases {
                let item = NSMenuItem(title: sortKeyTitle(key), action: #selector(sortByClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = key
                item.state = model.active.sort.key == key ? .on : .off
                menu.addItem(item)
            }
        } else {
            for field in GroupBy.allCases {
                let item = NSMenuItem(title: L10n.t(field.titleKey), action: #selector(groupByClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = field
                item.state = model.active.groupBy == field ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let use = NSMenuItem(title: L10n.t("Dùng nhóm"), action: #selector(useGroupsClicked), keyEquivalent: "")
            use.target = self
            use.state = model.active.useGroups ? .on : .off
            menu.addItem(use)
        }
    }

    private func sortKeyTitle(_ key: SortKey) -> String {
        switch key {
        case .name: return L10n.t("Tên")
        case .modified: return L10n.t("Ngày sửa")
        case .size: return L10n.t("Cỡ")
        case .kind: return L10n.t("Loại")
        case .created: return L10n.t("Ngày tạo")
        case .added: return L10n.t("Ngày thêm")
        case .lastOpened: return L10n.t("Ngày mở gần nhất")
        }
    }

    @objc private func groupByClicked(_ sender: NSMenuItem) {
        guard let field = sender.representedObject as? GroupBy else { return }
        model.active.groupBy = field
    }

    @objc private func sortByClicked(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? SortKey else { return }
        model.active.sort = SortOrder(key: key, ascending: model.active.sort.ascending)
    }

    @objc private func useGroupsClicked() {
        _ = model.perform(.useGroups)
    }

    // MARK: - Pane Layout

    /// Icon follows `tree.currentPreset` (nil ⇒ a "custom" glyph) — FileOctopus 1.0.3. Menu: 4 presets +
    /// Split Right/Left/Down/Up + Equalize + Zoom.
    private func makePaneLayoutItem() -> NSToolbarItem {
        let title = L10n.t("Bố cục ngăn")
        let button = makeMenuButton(image: paneLayoutImage(), title: title, menu: paneLayoutMenu())

        let item = NSToolbarItem(itemIdentifier: ID.paneLayout)
        item.view = button
        item.label = title
        item.paletteLabel = title
        paneLayoutItem = item
        return item
    }

    private func paneLayoutImage() -> NSImage {
        let symbol: String
        switch model.tree.currentPreset {
        case .single: symbol = "square"
        case .sideBySide: symbol = "rectangle.split.2x1"
        case .stacked: symbol = "rectangle.split.1x2"
        case .grid: symbol = "square.grid.2x2"
        case nil: symbol = "rectangle.3.group"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: L10n.t("Bố cục ngăn"))!
    }

    private func paneLayoutMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        rebuildPaneLayoutMenu(menu)
        paneLayoutMenuRef = menu
        return menu
    }

    private func rebuildPaneLayoutMenu(_ menu: NSMenu) {
        clearMenuKeepingFace(menu)
        menu.addItem(presetMenuItem(L10n.t("Một ngăn"), .presetSingle))
        menu.addItem(presetMenuItem(L10n.t("Cạnh nhau"), .presetSideBySide))
        menu.addItem(presetMenuItem(L10n.t("Chồng lên nhau"), .presetStacked))
        menu.addItem(presetMenuItem(L10n.t("Lưới 2×2"), .presetGrid))
        menu.addItem(.separator())
        menu.addItem(presetMenuItem(L10n.t("Chia ngăn sang phải"), .splitRight))
        menu.addItem(presetMenuItem(L10n.t("Chia ngăn sang trái"), .splitLeft))
        menu.addItem(presetMenuItem(L10n.t("Chia ngăn xuống dưới"), .splitDown))
        menu.addItem(presetMenuItem(L10n.t("Chia ngăn lên trên"), .splitUp))
        menu.addItem(.separator())
        menu.addItem(presetMenuItem(L10n.t("Chia đều các ngăn"), .equalizePanes))
        menu.addItem(presetMenuItem(L10n.t("Phóng to ngăn"), .zoomPane))
    }

    private func presetMenuItem(_ title: String, _ command: BrowserCommand) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(commandMenuItemClicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command
        item.isEnabled = model.canPerform(command)
        return item
    }

    @objc private func commandMenuItemClicked(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? BrowserCommand else { return }
        _ = model.perform(command)
    }

    private func observePaneLayoutIcon() {
        withObservationTracking {
            _ = model.tree
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.tornDown else { return }
                if let button = self.paneLayoutItem?.view as? NSPopUpButton, let faceItem = button.menu?.items.first {
                    faceItem.image = self.paneLayoutImage()
                }
                self.observePaneLayoutIcon()
            }
        }
    }

    // MARK: - Share

    private func makeShareItem() -> NSToolbarItem {
        let item = NSSharingServicePickerToolbarItem(itemIdentifier: ID.share)
        item.delegate = self
        item.label = L10n.t("Chia sẻ")
        item.paletteLabel = L10n.t("Chia sẻ")
        return item
    }

    // MARK: - Action ("…")

    /// Rebuilt on every open from the active selection's commands, filtered by `canPerform` — "the same commands
    /// as the selection's context menu" (reference app). A fixed, representative set of file-operation commands
    /// (not literally every `BrowserCommand`, which would also list window/pane-layout chrome that does not belong
    /// in a per-item action menu).
    private static let actionCommands: [BrowserCommand] = [
        .open, .openEnclosing, .getInfo, .rename, .duplicate, .copy, .paste, .pasteMove, .copyPath,
        .compress, .addToShelf, .showInFinder, .quickLook, .moveToTrash,
    ]

    private func makeActionItem() -> NSToolbarItem {
        let title = L10n.t("Thao tác")
        let menu = NSMenu()
        menu.delegate = self
        rebuildActionMenu(menu)
        actionMenuRef = menu
        let image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: title)!
        let button = makeMenuButton(image: image, title: title, menu: menu)

        let item = NSToolbarItem(itemIdentifier: ID.action)
        item.view = button
        item.label = title
        item.paletteLabel = title
        return item
    }

    private func rebuildActionMenu(_ menu: NSMenu) {
        clearMenuKeepingFace(menu)
        for command in Self.actionCommands {
            menu.addItem(presetMenuItem(L10n.t(BrowserCommands.titleKey(command)), command))
        }
    }

    // MARK: - Search

    private func makeSearchItem() -> NSToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: ID.search)
        item.searchField.delegate = self
        item.searchField.placeholderString = L10n.t("Tìm kiếm")
        item.label = L10n.t("Tìm kiếm")
        item.paletteLabel = L10n.t("Tìm kiếm")
        searchItem = item
        return item
    }

    // MARK: - Customizable extras

    private func makeButtonItem(_ identifier: NSToolbarItem.Identifier, command: BrowserCommand, symbol: String) -> NSToolbarItem {
        let title = L10n.t(BrowserCommands.titleKey(command))
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: #selector(toolbarButtonClicked(_:)))
        button.bezelStyle = .texturedRounded
        button.tag = Self.tag(for: command)
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = button
        item.label = title
        item.paletteLabel = title
        return item
    }

    @objc private func toolbarButtonClicked(_ sender: NSButton) {
        guard let command = Self.command(forTag: sender.tag) else { return }
        _ = model.perform(command)
    }

    /// `BrowserCommand` is not an `Int`-backed enum (its cases carry no raw value beyond `String`), so a plain
    /// `NSButton.tag` round-trip needs its own tiny lookup rather than `rawValue`.
    private static func tag(for command: BrowserCommand) -> Int {
        BrowserCommand.allCases.firstIndex(of: command) ?? -1
    }

    private static func command(forTag tag: Int) -> BrowserCommand? {
        let all = BrowserCommand.allCases
        guard all.indices.contains(tag) else { return nil }
        return all[tag]
    }

    private func makeWorkspacesItem() -> NSToolbarItem {
        let title = L10n.t("Các Workspace")
        let image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: title)!
        let button = makeMenuButton(image: image, title: title, menu: workspacesMenu())
        let item = NSToolbarItem(itemIdentifier: ID.workspaces)
        item.view = button
        item.label = title
        item.paletteLabel = title
        return item
    }

    private func workspacesMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        rebuildWorkspacesMenu(menu)
        workspacesMenuRef = menu
        return menu
    }

    private func rebuildWorkspacesMenu(_ menu: NSMenu) {
        clearMenuKeepingFace(menu)
        let saveItem = NSMenuItem(title: L10n.t("Lưu Workspace"), action: #selector(saveWorkspaceClicked), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)
        let workspaces = model.workspaces
        if !workspaces.isEmpty {
            menu.addItem(.separator())
            for workspace in workspaces {
                let item = NSMenuItem(title: workspace.name, action: #selector(openWorkspaceClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = workspace.id
                menu.addItem(item)
            }
        }
    }

    @objc private func saveWorkspaceClicked() {
        model.sheet = .saveWorkspace
    }

    @objc private func openWorkspaceClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.openWorkspace(id)
    }

    private func makeShelfItem() -> NSToolbarItem {
        let title = L10n.t("Hiện hoặc ẩn Shelf")
        let button = NSButton(image: NSImage(systemSymbolName: model.shelfVisible ? "tray.full.fill" : "tray", accessibilityDescription: title)!,
                              target: self, action: #selector(shelfClicked))
        button.bezelStyle = .texturedRounded
        button.setButtonType(.pushOnPushOff)
        button.state = model.shelfVisible ? .on : .off
        let item = NSToolbarItem(itemIdentifier: ID.shelf)
        item.view = button
        item.label = title
        item.paletteLabel = title
        shelfItem = item
        observeShelfVisible()
        return item
    }

    @objc private func shelfClicked() {
        _ = model.perform(.toggleShelf)
    }

    private func observeShelfVisible() {
        withObservationTracking {
            _ = model.shelfVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.tornDown else { return }
                if let button = self.shelfItem?.view as? NSButton {
                    button.state = self.model.shelfVisible ? .on : .off
                    button.image = NSImage(systemSymbolName: self.model.shelfVisible ? "tray.full.fill" : "tray", accessibilityDescription: nil)
                }
                self.observeShelfVisible()
            }
        }
    }

    /// Operations button badge = active + queued job count, same source `BrowserRootView`'s own button used.
    private func makeOperationsItem() -> NSToolbarItem {
        let title = L10n.t("Hàng đợi thao tác")
        let button = NSButton(image: NSImage(systemSymbolName: "arrow.left.arrow.right.circle", accessibilityDescription: title)!,
                              target: self, action: #selector(operationsClicked(_:)))
        button.bezelStyle = .texturedRounded
        let item = NSToolbarItem(itemIdentifier: ID.operations)
        item.view = button
        item.label = title
        item.paletteLabel = title
        operationsItem = item
        refreshOperationsBadge()
        return item
    }

    @objc private func operationsClicked(_ sender: NSButton) {
        if let popover = operationsPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingControllerBox.make(OperationsPanelView(queue: FileOperationQueue.shared))
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        operationsPopover = popover
    }

    private func refreshOperationsBadge() {
        guard let button = operationsItem?.view as? NSButton else { return }
        let count = FileOperationQueue.shared.queue.jobs.filter { !$0.isFinished }.count
        button.title = count > 0 ? "\(count)" : ""
        button.imagePosition = count > 0 ? .imageLeading : .imageOnly
    }

    private func observeOperationsBadge() {
        withObservationTracking {
            _ = FileOperationQueue.shared.queue
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.tornDown else { return }
                self.refreshOperationsBadge()
                self.observeOperationsBadge()
            }
        }
    }
}

// MARK: - NSMenuDelegate (rebuild-on-open for the context-sensitive menus)

extension BrowserToolbarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === groupMenuRef {
            rebuildGroupMenu(menu)
        } else if menu === actionMenuRef {
            rebuildActionMenu(menu)
        } else if menu === workspacesMenuRef {
            rebuildWorkspacesMenu(menu)
        } else if menu === paneLayoutMenuRef {
            rebuildPaneLayoutMenu(menu)
        }
    }
}

// MARK: - NSSearchFieldDelegate (Return runs the search; clearing ends it)

extension BrowserToolbarController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let text = (control as? NSSearchField)?.stringValue ?? ""
        model.runSearch(text, scope: .folder)
        return true
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField, field.stringValue.isEmpty else { return }
        model.active.endSearch()
    }
}

// MARK: - NSSharingServicePickerToolbarItemDelegate (selected URLs)

extension BrowserToolbarController: NSSharingServicePickerToolbarItemDelegate {
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        model.active.selectedEntries.map { URL(fileURLWithPath: $0.path) }
    }
}

/// `OperationsPanelView` is SwiftUI; the operations toolbar button's popover needs an `NSViewController`. A tiny
/// wrapper keeps every other call site in this file from having to spell out `NSHostingController<OperationsPanelView>`.
private enum NSHostingControllerBox {
    static func make(_ view: OperationsPanelView) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.preferredContentSize = NSSize(width: 360, height: 280)
        return controller
    }
}
