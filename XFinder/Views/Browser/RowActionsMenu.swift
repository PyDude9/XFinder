import AppKit
import SwiftUI

/// XF-T32 W3 (contract XF-T32-w23 §F) — the row `⋯` menu (pin, property values, add property, nickname, emoji) and
/// the folder `⋯` menu (filter, sort, properties, group). Tilde order and look (scratchpad/claude/tilde/
/// sheet-live-groups.png, sheet-properties.png): "Pin in “Projects”" · "Status   [In Progress] ›" (submenu Clear + coloured
/// pills) · "Add property ›"; folder menu Filter · Sort › · Properties (n visible) › · Group (None) ›.
///
/// Every item carries its own closure (`RowMenuItem`), so the menu can be appended to another menu (the integrator moves
/// `menu(for:pane:model:).items` into the context menu) without a shared target object. Menus are rebuilt each time they
/// open, so a closure never outlives the state it read.
enum RowActionsMenu {
    @MainActor static func menu(for entries: [DirectoryEntry], pane: PaneState, model: BrowserWindowModel) -> NSMenu {
        let menu: NSMenu = NSMenu()
        menu.autoenablesItems = false
        guard !entries.isEmpty else { return menu }
        let metadata: BrowserMetadata = BrowserMetadata.shared
        let context: RowMenuContext = RowMenuContext(entries: entries, pane: pane, model: model, metadata: metadata)

        if let pinItem: NSMenuItem = RowPinSection.item(context) {
            menu.addItem(pinItem)
        }
        if context.isRealFolder {
            for item in RowPropertySection.items(context) { menu.addItem(item) }
            menu.addItem(RowAddPropertySection.item(folder: pane.path, pane: pane, metadata: metadata))
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(RowAnnotationSection.nicknameItem(context))
        if let emojiItem: NSMenuItem = RowAnnotationSection.emojiItem(context) {
            menu.addItem(emojiItem)
        }
        return menu
    }

    @MainActor static func folderMenu(pane: PaneState, model: BrowserWindowModel) -> NSMenu {
        let menu: NSMenu = NSMenu()
        menu.autoenablesItems = false
        let metadata: BrowserMetadata = BrowserMetadata.shared
        menu.addItem(FolderMenuSections.filterItem(pane: pane, model: model))
        menu.addItem(FolderMenuSections.sortItem(pane: pane))
        if VirtualLocation.parse(pane.path) == nil {
            menu.addItem(FolderMenuSections.propertiesItem(pane: pane, metadata: metadata))
        }
        if pane.viewMode != .gallery {
            menu.addItem(FolderMenuSections.groupItem(pane: pane, metadata: metadata))
        }
        return menu
    }
}

// MARK: - Shared context

/// What every row-menu section reads, computed once per menu.
@MainActor private struct RowMenuContext {
    let entries: [DirectoryEntry]
    let pane: PaneState
    let model: BrowserWindowModel
    let metadata: BrowserMetadata

    /// Properties, pins and the folder `⋯` menu only make sense in a real folder (not Recents / a tag listing).
    var isRealFolder: Bool { VirtualLocation.parse(pane.path) == nil }

    var folderName: String {
        if let nickname: String = metadata.nickname(for: pane.path), !nickname.isEmpty { return nickname }
        let last: String = (pane.path as NSString).lastPathComponent
        return last.isEmpty ? pane.path : last
    }

    var paths: [String] { entries.map(\.path) }
}

/// Trailing-slash-insensitive path key, the same spelling rule `PinRules` uses for its own comparisons.
private enum RowPathKey {
    static func key(_ path: String) -> String {
        var key: Substring = Substring(path.precomposedStringWithCanonicalMapping)
        while key.count > 1, key.hasSuffix("/") { key = key.dropLast() }
        return String(key)
    }

    static func parent(of path: String) -> String {
        key((key(path) as NSString).deletingLastPathComponent)
    }
}

// MARK: - Closure menu item

/// A menu row that runs a closure. The item is its own (weakly held) target; the menu retains the item.
@MainActor private final class RowMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, symbol: String? = nil, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        if let symbol: String = symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func fire() { handler() }
}

/// A non-clickable parent row (holds a submenu) with an optional SF Symbol.
@MainActor private func submenuItem(title: String, symbol: String?, submenu: NSMenu) -> NSMenuItem {
    let item: NSMenuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    if let symbol: String = symbol {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    submenu.autoenablesItems = false
    item.submenu = submenu
    return item
}

// MARK: - Pin

@MainActor private enum RowPinSection {
    /// "Ghim vào “<folder>”" / "Bỏ ghim khỏi “<folder>”". Shown only when every entry lives directly in the pane's
    /// folder (or is the folder itself — the "This folder" pin): a row disclosed from a subfolder, or a search hit
    /// elsewhere on disk, would be pinned into a folder whose Pinned block can never show it.
    static func item(_ context: RowMenuContext) -> NSMenuItem? {
        guard context.isRealFolder else { return nil }
        let folderKey: String = RowPathKey.key(context.pane.path)
        let pinnable: Bool = context.entries.allSatisfy { (entry: DirectoryEntry) -> Bool in
            RowPathKey.parent(of: entry.path) == folderKey || RowPathKey.key(entry.path) == folderKey
        }
        guard pinnable else { return nil }
        let pinned: Set<String> = Set(context.metadata.pins(in: context.pane.path).map(RowPathKey.key))
        let allPinned: Bool = context.paths.allSatisfy { pinned.contains(RowPathKey.key($0)) }
        let quoted: String = " “" + context.folderName + "”"
        let title: String = (allPinned ? L10n.t("Bỏ ghim khỏi") : L10n.t("Ghim vào")) + quoted
        let folder: String = context.pane.path
        let paths: [String] = context.paths
        let metadata: BrowserMetadata = context.metadata
        return RowMenuItem(title: title, symbol: allPinned ? "pin.slash" : "pin") {
            // `togglePin` flips one path: unpin all when every one is pinned, else pin only the ones that are not yet
            // (toggling a mixed selection blindly would unpin the pinned half).
            let current: Set<String> = Set(metadata.pins(in: folder).map(RowPathKey.key))
            for path in paths where current.contains(RowPathKey.key(path)) == allPinned {
                metadata.togglePin(path, in: folder)
            }
        }
    }
}

// MARK: - Property values

@MainActor private enum RowPropertySection {
    /// One row per catalog property (visibility in this folder is independent): "<Name>    [value pill]" with a submenu "Xoá giá trị" + every option.
    static func items(_ context: RowMenuContext) -> [NSMenuItem] {
        let definitions: [PropertyDefinition] = context.metadata.catalog.definitions
        guard !definitions.isEmpty else { return [] }
        let menuFont: NSFont = NSFont.menuFont(ofSize: .zero)
        let values: [PropertyValueSummary] = definitions.map { PropertyValueSummary(definition: $0, context: context) }
        let nameWidth: CGFloat = definitions.map { (definition: PropertyDefinition) -> CGFloat in
            NSAttributedString(string: definition.name, attributes: [.font: menuFont]).size().width
        }.max() ?? .zero
        let valueWidth: CGFloat = values.map { $0.valueImage(font: menuFont).size.width }.max() ?? .zero
        let tabLocation: CGFloat = nameWidth + XFinderTokens.Space.section + valueWidth
        return values.map { (summary: PropertyValueSummary) -> NSMenuItem in
            let item: NSMenuItem = submenuItem(title: summary.definition.name, symbol: "list.bullet",
                                               submenu: optionsMenu(summary, context: context))
            item.attributedTitle = summary.title(font: menuFont, tabLocation: tabLocation)
            return item
        }
    }

    private static func optionsMenu(_ summary: PropertyValueSummary, context: RowMenuContext) -> NSMenu {
        let menu: NSMenu = NSMenu()
        let propertyID: UUID = summary.definition.id
        let paths: [String] = context.paths
        let metadata: BrowserMetadata = context.metadata
        let pane: PaneState = context.pane
        let clear: RowMenuItem = RowMenuItem(title: L10n.t("Xoá giá trị"), symbol: "circle.slash") {
            for path in paths { metadata.select(path: path, property: propertyID, option: nil) }
            pane.metadataDidChange()
        }
        clear.isEnabled = !summary.optionCounts.isEmpty
        menu.addItem(clear)
        for option in summary.definition.options {
            let item: RowMenuItem = RowMenuItem(title: option.title) {
                for path in paths { metadata.select(path: path, property: propertyID, option: option.id) }
                pane.metadataDidChange()
            }
            item.attributedTitle = PillImageCache.shared.attributedPill(option, font: NSFont.menuFont(ofSize: .zero))
            let count: Int = summary.optionCounts[option.id] ?? 0
            item.state = count == paths.count ? .on : (count > 0 ? .mixed : .off)
            menu.addItem(item)
        }
        if !summary.definition.options.isEmpty {
            let groups = NSMenu()
            for option in summary.definition.options {
                let ref = LiveGroupRef(propertyID: propertyID, optionID: option.id)
                let item = RowMenuItem(title: option.title) { SpaceController.shared.toggleLiveGroup(ref) }
                item.state = SpaceController.shared.active.liveGroups.contains(ref) ? .on : .off
                groups.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(submenuItem(title: L10n.t("Hiện nhóm trong thanh bên"), symbol: "sidebar.left", submenu: groups))
        }
        return menu
    }
}

/// How the selection is set for one property: every item the same option, mixed, or unset.
@MainActor private struct PropertyValueSummary {
    let definition: PropertyDefinition
    /// option id ⇒ how many selected items carry it (orphaned selections are unset — `option(for:)` drops them).
    let optionCounts: [UUID: Int]
    let sharedOption: PropertyOption?
    let isMixed: Bool

    init(definition: PropertyDefinition, context: RowMenuContext) {
        self.definition = definition
        var counts: [UUID: Int] = [:]
        var unset: Int = 0
        var first: PropertyOption?
        for path in context.paths {
            if let option: PropertyOption = context.metadata.option(for: path, property: definition.id) {
                counts[option.id, default: 0] += 1
                if first == nil { first = option }
            } else {
                unset += 1
            }
        }
        optionCounts = counts
        let uniform: Bool = counts.count == 1 && unset == 0
        sharedOption = uniform ? first : nil
        isMixed = counts.count > 1 || (counts.count == 1 && unset > 0)
    }

    /// The right-hand value: the option's pill, or secondary text ("Chưa đặt" / "Nhiều giá trị").
    func valueImage(font: NSFont) -> NSImage {
        if let option: PropertyOption = sharedOption { return PillImageCache.shared.pill(option) }
        let text: String = isMixed ? L10n.t("Nhiều giá trị") : L10n.t(PropertyRules.unsetTitleKey)
        return PillImageCache.shared.secondaryText(text, font: font)
    }

    func title(font: NSFont, tabLocation: CGFloat) -> NSAttributedString {
        let paragraph: NSMutableParagraphStyle = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabLocation)]
        let result: NSMutableAttributedString = NSMutableAttributedString(
            string: definition.name + "\t", attributes: [.font: font, .paragraphStyle: paragraph])
        let attachment: NSAttributedString = PillImageCache.attachmentString(valueImage(font: font), font: font)
        result.append(attachment)
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
}

// MARK: - Add property

@MainActor private enum RowAddPropertySection {
    /// "Thêm thuộc tính ›": catalog properties not yet shown in `folder`, then "Thuộc tính mới…".
    static func item(folder: String, pane: PaneState, metadata: BrowserMetadata) -> NSMenuItem {
        submenuItem(title: L10n.t("Thêm thuộc tính"), symbol: "plus",
                    submenu: addPropertyMenu(folder: folder, pane: pane, metadata: metadata))
    }

    static func addPropertyMenu(folder: String, pane: PaneState, metadata: BrowserMetadata) -> NSMenu {
        let menu: NSMenu = NSMenu()
        let shown: Set<UUID> = Set(metadata.shownProperties(in: folder).map(\.definition.id))
        let available: [PropertyDefinition] = metadata.catalog.definitions.filter { !shown.contains($0.id) }
        for definition in available {
            let propertyID: UUID = definition.id
            menu.addItem(RowMenuItem(title: definition.name, symbol: "list.bullet") {
                FolderPropertyActions.show(propertyID, in: folder, metadata: metadata)
                pane.metadataDidChange()
            })
        }
        if !available.isEmpty { menu.addItem(.separator()) }
        menu.addItem(RowMenuItem(title: L10n.t("Thuộc tính mới…"), symbol: "plus") {
            guard let created: UUID = FolderPropertyActions.create(in: folder, metadata: metadata) else { return }
            PropertyEditorPresenter.shared.show(propertyID: created, folder: folder, metadata: metadata)
        })
        return menu
    }
}

/// Folder-level property bookkeeping shared by the row and folder menus.
@MainActor private enum FolderPropertyActions {
    /// Appends `propertyID` to the folder's list (shown in view); already listed ⇒ just turns "show in view" on.
    static func show(_ propertyID: UUID, in folder: String, metadata: BrowserMetadata) {
        var list: [(property: UUID, showInView: Bool)] = metadata.shownProperties(in: folder).map {
            (property: $0.definition.id, showInView: $0.showInView)
        }
        if let index: Int = list.firstIndex(where: { $0.property == propertyID }) {
            guard !list[index].showInView else { return }
            list[index].showInView = true
        } else {
            list.append((property: propertyID, showInView: true))
        }
        metadata.setFolderProperties(folder, list)
    }

    /// Creates a property named after the localized default ("Thuộc tính", made unique by the catalog) and shows it
    /// in `folder`. Returns its id, nil when the catalog refused (never with the current rules).
    static func create(in folder: String, metadata: BrowserMetadata) -> UUID? {
        var created: UUID?
        let name: String = L10n.t(PropertyCatalog.defaultNameKey)
        metadata.updateCatalog { (catalog: inout PropertyCatalog) in
            created = catalog.add(name: name).id
        }
        guard let id: UUID = created else { return nil }
        show(id, in: folder, metadata: metadata)
        return id
    }
}

// MARK: - Nickname / emoji

@MainActor private enum RowAnnotationSection {
    static func nicknameItem(_ context: RowMenuContext) -> NSMenuItem {
        let paths: [String] = context.paths
        let metadata: BrowserMetadata = context.metadata
        let current: String = paths.count == 1 ? (metadata.nickname(for: paths[0]) ?? "") : ""
        return RowMenuItem(title: L10n.t("Đặt biệt danh…"), symbol: "textformat") {
            OneFieldSheet.run(title: L10n.t("Biệt danh"), initial: current, showsCharacterPalette: false) {
                (text: String) -> Bool in
                let nickname: String? = NicknameRules.normalized(text)
                for path in paths { metadata.setNickname(nickname, for: path) }
                return true
            }
        }
    }

    /// Folders only (a package is a file to the user).
    static func emojiItem(_ context: RowMenuContext) -> NSMenuItem? {
        guard context.entries.allSatisfy(\.isFolderLike) else { return nil }
        let paths: [String] = context.paths
        let metadata: BrowserMetadata = context.metadata
        let current: String = paths.count == 1 ? (metadata.emoji(for: paths[0]) ?? "") : ""
        return RowMenuItem(title: L10n.t("Đặt emoji…"), symbol: "face.smiling") {
            OneFieldSheet.run(title: L10n.t("Biểu tượng emoji"), initial: current, showsCharacterPalette: true) {
                (text: String) -> Bool in
                let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    for path in paths { metadata.setEmoji(nil, for: path) }
                    return true
                }
                guard let emoji: String = EmojiRules.normalized(trimmed) else { return false }
                for path in paths { metadata.setEmoji(emoji, for: path) }
                return true
            }
        }
    }
}

/// A one-field sheet (NSAlert + text field) on the key browser window; app-modal when no window is available.
/// `commit` returns false to reject the text (beep, field stays open with the text selected).
@MainActor private enum OneFieldSheet {
    static func run(title: String, initial: String, showsCharacterPalette: Bool,
                    commit: @escaping @MainActor (String) -> Bool) {
        let alert: NSAlert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: L10n.t("Lưu"))
        alert.addButton(withTitle: L10n.t("Huỷ"))
        let field: NSTextField = NSTextField(string: initial)
        let height: CGFloat = field.fittingSize.height
        field.frame = NSRect(x: .zero, y: .zero, width: XFinderTokens.Settings.sidebarWidth, height: height)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { (response: NSApplication.ModalResponse) in
            guard response == .alertFirstButtonReturn else { return }
            if !commit(field.stringValue) {
                NSSound.beep()
                run(title: title, initial: field.stringValue, showsCharacterPalette: showsCharacterPalette, commit: commit)
            }
        }
        if let window: NSWindow = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { (response: NSApplication.ModalResponse) in
                Task { @MainActor in finish(response) }
            }
            alert.window.makeFirstResponder(field)
            if showsCharacterPalette { NSApp.orderFrontCharacterPalette(field) }
        } else {
            if showsCharacterPalette { NSApp.orderFrontCharacterPalette(field) }
            finish(alert.runModal())
        }
    }
}

// MARK: - Folder menu

@MainActor private enum FolderMenuSections {
    static func filterItem(pane: PaneState, model: BrowserWindowModel) -> NSMenuItem {
        let paneID: PaneID = pane.id
        return RowMenuItem(title: L10n.t("Lọc"), symbol: "line.3.horizontal.decrease") {
            model.focus(paneID)
            model.filterFocusRequest = paneID
        }
    }

    static func sortItem(pane: PaneState) -> NSMenuItem {
        let menu: NSMenu = NSMenu()
        for key in SortKey.allCases {
            let item: RowMenuItem = RowMenuItem(title: sortTitle(key)) {
                pane.sort = SortOrder(key: key, ascending: pane.sort.ascending)
                pane.reload()   // re-derives entries + sections (the listing comes from the shared cache)
            }
            item.state = pane.sort.key == key ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for ascending in [true, false] {
            let item: RowMenuItem = RowMenuItem(title: ascending ? L10n.t("Tăng dần") : L10n.t("Giảm dần")) {
                pane.sort = SortOrder(key: pane.sort.key, ascending: ascending)
                pane.reload()
            }
            item.state = pane.sort.ascending == ascending ? .on : .off
            menu.addItem(item)
        }
        return submenuItem(title: L10n.t("Sắp xếp"), symbol: "arrow.up.arrow.down", submenu: menu)
    }

    /// "Thuộc tính" with "n đang hiện" under it; submenu: this folder's properties (✓ = shown in the list, click opens
    /// the editor), then "Thêm thuộc tính ›".
    static func propertiesItem(pane: PaneState, metadata: BrowserMetadata) -> NSMenuItem {
        let folder: String = pane.path
        let shown: [(definition: PropertyDefinition, showInView: Bool)] = metadata.shownProperties(in: folder)
        let menu: NSMenu = NSMenu()
        for entry in shown {
            let propertyID: UUID = entry.definition.id
            let item: RowMenuItem = RowMenuItem(title: entry.definition.name, symbol: "list.bullet") {
                PropertyEditorPresenter.shared.show(propertyID: propertyID, folder: folder, metadata: metadata)
            }
            item.state = entry.showInView ? .on : .off
            menu.addItem(item)
        }
        if !shown.isEmpty { menu.addItem(.separator()) }
        menu.addItem(RowAddPropertySection.item(folder: folder, pane: pane, metadata: metadata))
        let visibleCount: Int = shown.filter(\.showInView).count
        let item: NSMenuItem = submenuItem(title: L10n.t("Thuộc tính"), symbol: "list.bullet.rectangle", submenu: menu)
        item.attributedTitle = twoLineTitle(L10n.t("Thuộc tính"), detail: "\(visibleCount) " + L10n.t("đang hiện"))
        return item
    }

    /// "Nhóm" with the current grouping under it; submenu Không nhóm · every `GroupBy` field · every property.
    static func groupItem(pane: PaneState, metadata: BrowserMetadata) -> NSMenuItem {
        let menu: NSMenu = NSMenu()
        let catalog: PropertyCatalog = metadata.catalog
        let activeProperty: PropertyDefinition? = pane.useGroups ? pane.propertyGroupID.flatMap(catalog.definition) : nil
        let activeField: GroupBy = (pane.useGroups && activeProperty == nil) ? pane.groupBy : .none

        let none: RowMenuItem = RowMenuItem(title: L10n.t(GroupBy.none.titleKey)) {
            applyGrouping(pane: pane, field: .none, property: nil)
        }
        none.state = activeProperty == nil && activeField == .none ? .on : .off
        menu.addItem(none)
        menu.addItem(.separator())
        for field in GroupBy.allCases where field != .none {
            let item: RowMenuItem = RowMenuItem(title: L10n.t(field.titleKey)) {
                applyGrouping(pane: pane, field: field, property: nil)
            }
            item.state = activeProperty == nil && activeField == field ? .on : .off
            menu.addItem(item)
        }
        if !catalog.definitions.isEmpty { menu.addItem(.separator()) }
        for definition in catalog.definitions {
            let propertyID: UUID = definition.id
            let item: RowMenuItem = RowMenuItem(title: definition.name, symbol: "list.bullet") {
                applyGrouping(pane: pane, field: .none, property: propertyID)
            }
            item.state = activeProperty?.id == propertyID ? .on : .off
            menu.addItem(item)
        }
        let detail: String = activeProperty?.name ?? L10n.t(activeField.titleKey)
        let item: NSMenuItem = submenuItem(title: L10n.t("Nhóm"), symbol: "square.grid.3x1.below.line.grid.1x2", submenu: menu)
        item.attributedTitle = twoLineTitle(L10n.t("Nhóm"), detail: detail)
        return item
    }

    /// The views draw `sections` only with `useGroups` on, so picking a field or property turns it on and "Không
    /// nhóm" turns it off. `reload()` re-derives entries + sections and bumps the listing revision the views watch.
    private static func applyGrouping(pane: PaneState, field: GroupBy, property: UUID?) {
        pane.propertyGroupID = property
        pane.groupBy = field
        pane.useGroups = property != nil || field != .none
        pane.rebuildSections()
        pane.reload()
    }

    private static func twoLineTitle(_ title: String, detail: String) -> NSAttributedString {
        let menuFont: NSFont = NSFont.menuFont(ofSize: .zero)
        let detailFont: NSFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        let result: NSMutableAttributedString = NSMutableAttributedString(string: title, attributes: [.font: menuFont])
        result.append(NSAttributedString(string: "\n" + detail,
                                         attributes: [.font: detailFont, .foregroundColor: NSColor.secondaryLabelColor]))
        return result
    }

    private static func sortTitle(_ key: SortKey) -> String {
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
}

// MARK: - Pill images

/// Coloured option pills (tint at `PropertyTint.chipFill` behind semibold tint text, 11 pt — same chip as the list) drawn
/// ONCE per (colour, title, appearance) into a bitmap and reused by every menu.
@MainActor private final class PillImageCache {
    static let shared: PillImageCache = PillImageCache()

    private struct Key: Hashable {
        let color: PropertyColor?
        let text: String
        let dark: Bool
        let fontSize: CGFloat
    }

    /// A long session with many renamed options must not grow the cache forever.
    private static let capacity: Int = 256
    private var images: [Key: NSImage] = [:]

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func pill(_ option: PropertyOption) -> NSImage {
        let font: NSFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        let key: Key = Key(color: option.color, text: option.title, dark: isDark, fontSize: font.pointSize)
        if let cached: NSImage = images[key] { return cached }
        let tint: NSColor = NSColor(XFinderTokens.PropertyTint.color(option.color))
        let image: NSImage = Self.render(text: option.title, font: font, textColor: tint,
                                         fill: tint.withAlphaComponent(XFinderTokens.PropertyTint.chipFill))
        store(image, for: key)
        return image
    }

    /// Secondary label drawn as an image so it can share the right-aligned value column with the pills.
    func secondaryText(_ text: String, font: NSFont) -> NSImage {
        let key: Key = Key(color: nil, text: text, dark: isDark, fontSize: font.pointSize)
        if let cached: NSImage = images[key] { return cached }
        let image: NSImage = Self.render(text: text, font: font, textColor: .secondaryLabelColor, fill: nil)
        store(image, for: key)
        return image
    }

    func attributedPill(_ option: PropertyOption, font: NSFont) -> NSAttributedString {
        Self.attachmentString(pill(option), font: font)
    }

    /// The image as a text attachment, centred on the font's cap height so it sits on the menu text line.
    static func attachmentString(_ image: NSImage, font: NSFont) -> NSAttributedString {
        let attachment: NSTextAttachment = NSTextAttachment()
        attachment.image = image
        let offset: CGFloat = (font.capHeight - image.size.height) / 2
        attachment.bounds = NSRect(x: .zero, y: offset, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private func store(_ image: NSImage, for key: Key) {
        if images.count >= Self.capacity { images.removeAll(keepingCapacity: true) }
        images[key] = image
    }

    /// Eager bitmap rendering (no lazy drawing handler: the colours resolve now, under the current appearance).
    private static func render(text: String, font: NSFont, textColor: NSColor, fill: NSColor?) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let string: NSAttributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize: NSSize = string.size()
        let horizontal: CGFloat = fill == nil ? .zero : XFinderTokens.Space.tight
        let vertical: CGFloat = fill == nil ? .zero : XFinderTokens.Space.hairline
        let size: NSSize = NSSize(width: ceil(textSize.width + horizontal * 2), height: ceil(textSize.height + vertical * 2))
        let scale: CGFloat = NSScreen.screens.map(\.backingScaleFactor).max() ?? NSScreen.main?.backingScaleFactor ?? 1
        let image: NSImage = NSImage(size: size)
        guard size.width > 0, size.height > 0,
              let rep: NSBitmapImageRep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
              let context: NSGraphicsContext = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds: NSRect = NSRect(origin: .zero, size: size)
        if let fill: NSColor = fill {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        }
        string.draw(at: NSPoint(x: horizontal, y: vertical))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - Property editor popover presenter

/// Shows `PropertyEditorPopover` in a transient NSPopover anchored where the menu was clicked (the menu itself is gone
/// by the time its action runs, and the `⋯` button belongs to another unit). One popover at a time.
@MainActor private final class PropertyEditorPresenter {
    static let shared: PropertyEditorPresenter = PropertyEditorPresenter()

    private static let anchorSide: CGFloat = 1
    private var popover: NSPopover?

    func show(propertyID: UUID, folder: String, metadata: BrowserMetadata) {
        popover?.close()
        guard let window: NSWindow = NSApp.keyWindow ?? NSApp.mainWindow, let contentView: NSView = window.contentView else {
            return
        }
        let popover: NSPopover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        var editor: PropertyEditorPopover = PropertyEditorPopover(propertyID: propertyID, folder: folder, metadata: metadata)
        editor.onClose = { [weak self] in self?.close() }
        let host: NSHostingController<PropertyEditorPopover> = NSHostingController(rootView: editor)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        let windowPoint: NSPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        var point: NSPoint = contentView.convert(windowPoint, from: nil)
        point.x = min(max(point.x, contentView.bounds.minX), contentView.bounds.maxX - Self.anchorSide)
        point.y = min(max(point.y, contentView.bounds.minY), contentView.bounds.maxY - Self.anchorSide)
        let anchor: NSRect = NSRect(origin: point, size: NSSize(width: Self.anchorSide, height: Self.anchorSide))
        popover.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
        self.popover = popover
    }

    func close() {
        popover?.close()
        popover = nil
    }
}
