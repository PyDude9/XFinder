import AppKit

/// XF-T30 W2 — the ONE right-click menu of the browser (all four views and the toolbar's "…"), Finder's order
/// (contract docs/specs/XF-T30-w2-contract.md §3). W2 builder (menu).
///
/// Every item dispatches through `model.perform`/`model.canPerform` (the one dispatcher, CLAUDE.md §2) for anything
/// that already has a `BrowserCommand`; the few actions that are not commands (Open With ▸ a specific app, Tags ▸ a
/// colour) call the matching `BrowserWindowModel`/`PaneState` API directly, same as the contract's §4 lists them.
/// The menu is rebuilt fresh on every open (`menu(for:pane:)` is called right before `NSMenu.popUp`/the toolbar's
/// `menuNeedsUpdate`), so it always reflects the selection and `canPerform` at that instant — no stale state to
/// invalidate.
@MainActor
enum BrowserContextMenu {

    /// The menu for the active tab's selection (or the background menu when nothing is selected).
    static func menu(for model: BrowserWindowModel, pane: PaneState) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if pane.selectedEntries.isEmpty {
            buildBackgroundMenu(menu, model: model, pane: pane)
        } else {
            buildSelectionMenu(menu, model: model, pane: pane)
            let metadataActions = RowActionsMenu.menu(for: pane.selectedEntries, pane: pane, model: model)
            if !metadataActions.items.isEmpty { menu.addItem(.separator()) }
            for item in metadataActions.items {
                metadataActions.removeItem(item)
                menu.addItem(item)
            }
        }
        return menu
    }

    // MARK: - Selection menu (Finder order, contract §3)

    private static func buildSelectionMenu(_ menu: NSMenu, model: BrowserWindowModel, pane: PaneState) {
        let inTrash = isTrash(pane.path)
        let single = pane.selectedEntries.count == 1

        add(menu, .open, model: model, pane: pane)
        addPlain(menu, title: L10n.t("Mở trong tab mới"), command: .openInNewTab, model: model, pane: pane)
        menu.addItem(openWithItem(model: model, pane: pane))

        menu.addItem(.separator())
        add(menu, .moveToTrash, model: model, pane: pane, forceDisabled: inTrash ? true : nil)

        menu.addItem(.separator())
        add(menu, .getInfo, model: model, pane: pane)
        add(menu, .rename, model: model, pane: pane)
        add(menu, .compress, model: model, pane: pane, forceDisabled: inTrash)
        add(menu, .duplicate, model: model, pane: pane, forceDisabled: inTrash)
        addPlain(menu, title: L10n.t("Tạo bí danh"), command: .makeAlias, model: model, pane: pane, forceDisabled: inTrash)
        add(menu, .quickLook, model: model, pane: pane)

        menu.addItem(.separator())
        addCopyPair(menu, model: model, pane: pane, single: single)
        addPlain(menu, title: L10n.t("Chia sẻ…"), command: .share, model: model, pane: pane, forceDisabled: inTrash)

        menu.addItem(.separator())
        menu.addItem(tagsItem(model: model, pane: pane))

        menu.addItem(.separator())
        addPlain(menu, title: L10n.t("Thêm vào sidebar"), command: .addToSidebar, model: model, pane: pane)
        addPlain(menu, title: L10n.t("Thêm vào Shelf"), command: .addToShelf, model: model, pane: pane)

        menu.addItem(.separator())
        addPlain(menu, title: showOriginalTitle(for: pane), command: .showOriginal, model: model, pane: pane)
        addPlain(menu, title: L10n.t("Hiện trong Finder"), command: .showInFinder, model: model, pane: pane)

        // Cloud pair: gated entirely through `canPerform` (the one source of truth, CLAUDE.md §2) rather than this
        // file re-reading `URLResourceValues` itself — that would be a second disk read per item on every menu open,
        // duplicating the one `FileListView`'s own badge cache already does.
        menu.addItem(.separator())
        addPlain(menu, title: L10n.t("Tải về ngay"), command: .downloadNow, model: model, pane: pane)
        addPlain(menu, title: L10n.t("Gỡ bản tải"), command: .removeDownload, model: model, pane: pane)
    }

    // MARK: - Background menu (nothing selected)

    private static func buildBackgroundMenu(_ menu: NSMenu, model: BrowserWindowModel, pane: PaneState) {
        addPlain(menu, title: L10n.t("Thư mục mới"), command: .newFolder, model: model, pane: pane)
        add(menu, .getInfo, model: model, pane: pane)

        menu.addItem(.separator())
        add(menu, .paste, model: model, pane: pane)

        menu.addItem(.separator())
        menu.addItem(viewModeSubmenu(model: model, pane: pane))
        let folderActions = RowActionsMenu.folderMenu(pane: pane, model: model)
        for item in folderActions.items {
            folderActions.removeItem(item)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        addPlain(menu, title: L10n.t("Hiện tuỳ chọn xem"), command: .showViewOptions, model: model, pane: pane)
    }

    // MARK: - Submenus

    /// Open With ▸ — populated from `NSWorkspace.urlsForApplications(toOpen:)`, computed off the main thread (the
    /// contract: "khi menu mở off the main thread if needed") since LaunchServices resolution for several selected
    /// documents can take a few ms each; the submenu's own `NSMenuDelegate.menuNeedsUpdate` kicks the async refill off
    /// only when the user actually opens it, not on every context-menu build.
    private static func openWithItem(model: BrowserWindowModel, pane: PaneState) -> NSMenuItem {
        let title = L10n.t("Mở bằng")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.delegate = OpenWithMenuDelegate.shared
        OpenWithMenuDelegate.shared.register(submenu, model: model, paths: pane.selectedEntries.map(\.path))
        item.submenu = submenu
        item.isEnabled = !pane.selectedEntries.isEmpty
        return item
    }

    /// Copy — Option-held relabels to "Copy as Pathname" via a second, `isAlternate` item stacked on the same slot
    /// (contract §3: "Option-held relabel of Copy to 'Copy as Pathname' variants via NSMenuItem.isAlternate"); AppKit
    /// shows whichever one matches the Option key's live state, no observer needed. Both items must be added to the
    /// SAME menu, back to back, for AppKit to treat them as a pair.
    private static func addCopyPair(_ menu: NSMenu, model: BrowserWindowModel, pane: PaneState, single: Bool) {
        let plain = NSMenuItem(title: L10n.t("Sao chép"), action: #selector(Dispatcher.fire(_:)), keyEquivalent: "")
        plain.target = Dispatcher.shared
        plain.representedObject = Dispatcher.Box(command: .copy, model: model, pane: pane)
        plain.isEnabled = canPerform(.copy, model: model, pane: pane)
        menu.addItem(plain)

        let pathTitle = single
            ? copyAsPathnameSingleTitle(name: pane.selectedEntries.first?.name ?? "")
            : copyAsPathnameManyTitle(count: pane.selectedEntries.count)
        let alternate = NSMenuItem(title: pathTitle, action: #selector(Dispatcher.fire(_:)), keyEquivalent: "")
        alternate.target = Dispatcher.shared
        alternate.representedObject = Dispatcher.Box(command: .copyPath, model: model, pane: pane)
        alternate.isEnabled = canPerform(.copyPath, model: model, pane: pane)
        alternate.isAlternate = true
        alternate.keyEquivalentModifierMask = .option
        menu.addItem(alternate)
    }

    // MARK: - Tags ▸

    private static func tagsItem(model: BrowserWindowModel, pane: PaneState) -> NSMenuItem {
        let title = L10n.t("Thẻ")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        let selectedPaths = pane.selectedEntries.map(\.path)
        let activeColors = Set(
            pane.selectedEntries
                .flatMap { $0.tags ?? [] }
                .map { FinderTags.parse($0).color }
        )
        for color in TagColor.allCases where color != .none {
            let colorItem = NSMenuItem(title: L10n.t(color.titleKey), action: #selector(Dispatcher.fireTag(_:)), keyEquivalent: "")
            colorItem.target = Dispatcher.shared
            colorItem.image = tagSwatch(color)
            colorItem.state = activeColors.contains(color) ? .on : .off
            colorItem.representedObject = Dispatcher.TagBox(color: color, model: model, paths: selectedPaths)
            colorItem.isEnabled = !selectedPaths.isEmpty
            submenu.addItem(colorItem)
        }
        submenu.addItem(.separator())
        let more = NSMenuItem(title: L10n.t("Thẻ…"), action: #selector(Dispatcher.fireShowTagEditor(_:)), keyEquivalent: "")
        more.target = Dispatcher.shared
        more.representedObject = Dispatcher.Box(command: .getInfo, model: model, pane: pane)
        more.isEnabled = !selectedPaths.isEmpty
        submenu.addItem(more)
        item.submenu = submenu
        item.isEnabled = !selectedPaths.isEmpty
        return item
    }

    private static func tagSwatch(_ color: TagColor) -> NSImage? {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        nsColor(color).setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func nsColor(_ color: TagColor) -> NSColor {
        switch color {
        case .none: return .clear
        case .gray: return .systemGray
        case .green: return .systemGreen
        case .purple: return .systemPurple
        case .blue: return .systemBlue
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .orange: return .systemOrange
        }
    }

    // MARK: - Background-menu submenus

    private static func viewModeSubmenu(model: BrowserWindowModel, pane: PaneState) -> NSMenuItem {
        let title = L10n.t("Xem dạng")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        let modes: [(BrowserCommand, BrowserViewMode)] = [
            (.viewIcons, .icons), (.viewList, .list), (.viewColumns, .columns), (.viewGallery, .gallery),
        ]
        for (command, mode) in modes {
            let entry = NSMenuItem(title: L10n.t(BrowserCommands.titleKey(command)), action: #selector(Dispatcher.fire(_:)), keyEquivalent: "")
            entry.target = Dispatcher.shared
            entry.representedObject = Dispatcher.Box(command: command, model: model, pane: pane)
            entry.state = pane.viewMode == mode ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    private static func sortBySubmenu(model: BrowserWindowModel, pane: PaneState) -> NSMenuItem {
        let title = L10n.t("Sắp theo")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        for key in SortKey.allCases {
            let entry = NSMenuItem(title: L10n.t(sortKeyTitleKey(key)), action: #selector(Dispatcher.fireSort(_:)), keyEquivalent: "")
            entry.target = Dispatcher.shared
            entry.representedObject = Dispatcher.SortBox(key: key, model: model, pane: pane)
            entry.state = pane.sort.key == key ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    private static func sortKeyTitleKey(_ key: SortKey) -> String {
        switch key {
        case .name: return "Tên"
        case .modified: return "Ngày sửa"
        case .size: return "Cỡ"
        case .kind: return "Loại"
        case .created: return "Ngày tạo"
        case .added: return "Ngày thêm"
        case .lastOpened: return "Ngày mở gần nhất"
        }
    }

    private static func groupBySubmenu(model: BrowserWindowModel, pane: PaneState) -> NSMenuItem {
        let title = L10n.t("Nhóm theo")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        for group in GroupBy.allCases {
            let entry = NSMenuItem(title: L10n.t(group.titleKey), action: #selector(Dispatcher.fireGroup(_:)), keyEquivalent: "")
            entry.target = Dispatcher.shared
            entry.representedObject = Dispatcher.GroupBox(group: group, model: model, pane: pane)
            entry.state = pane.groupBy == group ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Helpers

    private static func isTrash(_ path: String) -> Bool {
        path == FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path
    }

    /// "Show Original" relabels to "Show in Enclosing Folder" when the active tab is showing search results
    /// (contract §3 / spec-productivity §10).
    private static func showOriginalTitle(for pane: PaneState) -> String {
        pane.search != nil ? L10n.t("Hiện trong thư mục chứa") : L10n.t(BrowserCommands.titleKey(.showOriginal))
    }

    private static func copyAsPathnameSingleTitle(name: String) -> String {
        L10n.t("Sao chép ") + name + L10n.t(" dưới dạng đường dẫn")
    }

    private static func copyAsPathnameManyTitle(count: Int) -> String {
        L10n.t("Sao chép ") + "\(count)" + L10n.t(" mục dưới dạng đường dẫn")
    }

    /// Adds a `BrowserCommand`-backed item whose title is the command's own stock L10n title.
    @discardableResult
    private static func add(_ menu: NSMenu, _ command: BrowserCommand, model: BrowserWindowModel, pane: PaneState,
                            forceDisabled: Bool? = nil) -> NSMenuItem {
        addPlain(menu, title: L10n.t(BrowserCommands.titleKey(command)), command: command, model: model, pane: pane,
                forceDisabled: forceDisabled)
    }

    /// Adds a `BrowserCommand`-backed item with an explicit title (search-result relabels, Option-free Copy variants).
    @discardableResult
    private static func addPlain(_ menu: NSMenu, title: String, command: BrowserCommand, model: BrowserWindowModel,
                                 pane: PaneState, forceDisabled: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(Dispatcher.fire(_:)), keyEquivalent: "")
        item.target = Dispatcher.shared
        item.representedObject = Dispatcher.Box(command: command, model: model, pane: pane)
        item.isEnabled = forceDisabled == true ? false : canPerform(command, model: model, pane: pane)
        menu.addItem(item)
        return item
    }

    /// `canPerform` is asked against `model`'s ACTIVE pane; a right-click on a non-active pane's row must focus that
    /// pane first for the answer (and the eventual dispatch) to be about the right selection — `Dispatcher.fire`
    /// does the same `focus` before `perform`, so the enabled state computed here and the action that later runs
    /// agree on which pane they're both talking about.
    private static func canPerform(_ command: BrowserCommand, model: BrowserWindowModel, pane: PaneState) -> Bool {
        let previous = model.activePane
        model.focus(pane.id)
        defer { model.focus(previous) }
        return model.canPerform(command)
    }
}

// MARK: - Dispatch targets (NSMenuItem needs an NSObject target)

@MainActor
private final class Dispatcher: NSObject {
    static let shared = Dispatcher()

    final class Box: NSObject {
        let command: BrowserCommand
        let model: BrowserWindowModel
        let pane: PaneState
        init(command: BrowserCommand, model: BrowserWindowModel, pane: PaneState) {
            self.command = command; self.model = model; self.pane = pane
        }
    }

    final class TagBox: NSObject {
        let color: TagColor
        let model: BrowserWindowModel
        let paths: [String]
        init(color: TagColor, model: BrowserWindowModel, paths: [String]) {
            self.color = color; self.model = model; self.paths = paths
        }
    }

    final class SortBox: NSObject {
        let key: SortKey
        let model: BrowserWindowModel
        let pane: PaneState
        init(key: SortKey, model: BrowserWindowModel, pane: PaneState) { self.key = key; self.model = model; self.pane = pane }
    }

    final class GroupBox: NSObject {
        let group: GroupBy
        let model: BrowserWindowModel
        let pane: PaneState
        init(group: GroupBy, model: BrowserWindowModel, pane: PaneState) { self.group = group; self.model = model; self.pane = pane }
    }

    @objc func fire(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box else { return }
        box.model.focus(box.pane.id)
        _ = box.model.perform(box.command)
    }

    @objc func fireTag(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? TagBox else { return }
        box.model.toggleTag(box.color)
    }

    @objc func fireShowTagEditor(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box else { return }
        box.model.focus(box.pane.id)
        _ = box.model.perform(.getInfo)
    }

    @objc func fireSort(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? SortBox else { return }
        box.pane.sort = SortOrder(key: box.key, ascending: box.pane.sort.ascending)
    }

    @objc func fireGroup(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? GroupBox else { return }
        box.pane.groupBy = box.group
    }
}

/// Open With ▸ — resolved lazily (contract: "computed when the menu opens ... off the main thread if needed"), since
/// `NSWorkspace.urlsForApplications(toOpen:)` does its own LaunchServices lookup that can cost real time for a
/// multi-item selection. `menuNeedsUpdate` fires every time AppKit is about to show the submenu; a generation counter
/// throws away a stale background result if the user already closed and reopened it against a different selection.
@MainActor
private final class OpenWithMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = OpenWithMenuDelegate()

    private final class Entry {
        let model: BrowserWindowModel
        let paths: [String]
        var generation = 0
        init(model: BrowserWindowModel, paths: [String]) { self.model = model; self.paths = paths }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func register(_ menu: NSMenu, model: BrowserWindowModel, paths: [String]) {
        entries[ObjectIdentifier(menu)] = Entry(model: model, paths: paths)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let entry = entries[ObjectIdentifier(menu)], !entry.paths.isEmpty else { return }
        let loading = NSMenuItem(title: L10n.t("Đang tải…"), action: nil, keyEquivalent: "")
        loading.isEnabled = false
        menu.addItem(loading)

        entry.generation += 1
        let generation = entry.generation
        let paths = entry.paths
        let model = entry.model
        Task {
            let resolvedPaths = await Self.resolveApplications(for: paths)
            guard generation == entry.generation else { return }   // a later open already superseded this one
            menu.removeAllItems()
            guard !resolvedPaths.isEmpty else {
                let none = NSMenuItem(title: L10n.t("Không có ứng dụng nào"), action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
                return
            }
            for appPath in resolvedPaths {
                let name = FileManager.default.displayName(atPath: appPath)
                let item = NSMenuItem(title: name, action: #selector(Dispatcher.fire(_:)), keyEquivalent: "")
                item.image = NSWorkspace.shared.icon(forFile: appPath)
                item.image?.size = NSSize(width: 16, height: 16)
                item.target = OpenWithDispatcher.shared
                item.representedObject = OpenWithDispatcher.Box(app: URL(fileURLWithPath: appPath), model: model)
                menu.addItem(item)
            }
        }
    }

    /// Off the main thread (contract: "computed when the menu opens off the main thread if needed") — only plain
    /// `Sendable` strings cross the hop, never the `NSMenu`/`NSMenuItem`/`BrowserWindowModel` themselves, which keeps
    /// Swift 6 region isolation happy without `@unchecked Sendable` anywhere (CLAUDE.md rule 12).
    private nonisolated static func resolveApplications(for paths: [String]) async -> [String] {
        await Task.detached(priority: .userInitiated) { () -> [String] in
            let urls = paths.map { URL(fileURLWithPath: $0) }
            // Intersection across every selected item, like Finder: an app offered must open ALL of them.
            var apps: Set<URL>? = nil
            for url in urls {
                let candidates = Set(NSWorkspace.shared.urlsForApplications(toOpen: url))
                apps = apps.map { $0.intersection(candidates) } ?? candidates
                if apps?.isEmpty == true { break }
            }
            return (apps.map(Array.init) ?? [])
                .map(\.path)
                .sorted { ($0 as NSString).lastPathComponent < ($1 as NSString).lastPathComponent }
        }.value
    }
}

@MainActor
private final class OpenWithDispatcher: NSObject {
    static let shared = OpenWithDispatcher()

    final class Box: NSObject {
        let app: URL
        let model: BrowserWindowModel
        init(app: URL, model: BrowserWindowModel) { self.app = app; self.model = model }
    }

    @objc func fire(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box else { return }
        box.model.openSelection(with: box.app)
    }
}
