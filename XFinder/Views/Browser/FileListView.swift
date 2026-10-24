import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// XF-T28 cluster D — Danh sách (NSTableView), view-based, cột Tên / Ngày sửa / Cỡ / Loại. AppKit for speed: at
/// 100 000 rows a `List` rebuilds its diff every keystroke the pane's `filterText` changes, while a table view only
/// ever touches the rows actually on screen (`makeView(withIdentifier:)` reuse). Source of truth is `pane.entries`
/// (already hidden/filtered/sorted by `PaneState`); this view never re-sorts.
struct FileListView: NSViewRepresentable {
    let pane: PaneState
    let model: BrowserWindowModel

    /// Row height is a named constant per the contract (AppKit-only exemption from `XFinderTokens`): a table row
    /// drawn by `NSTableCellView` is laid out in points the same way regardless of which SwiftUI token scale is
    /// active, so this is not a design-system value, it is a measurement of the 16×16 icon + single text line.
    static let rowHeight: CGFloat = 22

    /// Routes `keyDown` to the coordinator (type-select / Return-to-rename) before falling back to
    /// `NSTableView`'s own handling (arrow-key navigation, space for Quick Look via the window's
    /// `performKeyEquivalent`), since the base class never calls the delegate for raw key events.
    final class KeyRoutingTableView: NSTableView {
        weak var coordinator: Coordinator?
        override func keyDown(with event: NSEvent) {
            if coordinator?.handleKeyDown(event) == true { return }
            super.keyDown(with: event)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = KeyRoutingTableView()
        tableView.coordinator = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = Self.rowHeight
        tableView.headerView = NSTableHeaderView()
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.focusRingType = .none
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClicked)
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.menu = context.coordinator.makeContextMenu()

        for column in Coordinator.Column.allCases {
            let identifier = NSUserInterfaceItemIdentifier(column.rawValue)
            let tableColumn = NSTableColumn(identifier: identifier)
            tableColumn.title = L10n.t(column.titleKey)
            tableColumn.minWidth = column.minWidth
            tableColumn.width = column.defaultWidth
            if let sortKey = column.sortKey {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: sortKey.rawValue, ascending: true)
            }
            tableView.addTableColumn(tableColumn)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        context.coordinator.tableView = tableView
        context.coordinator.syncSortIndicator()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.pane = pane
        context.coordinator.model = model
        context.coordinator.reloadIfNeeded()
        context.coordinator.syncSelection()
        context.coordinator.syncSortIndicator()
        context.coordinator.beginRenameIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator(pane: pane, model: model) }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        enum Column: String, CaseIterable {
            case name, modified, size, kind

            var titleKey: String {
                switch self {
                case .name: return "Tên"
                case .modified: return "Ngày sửa"
                case .size: return "Cỡ"
                case .kind: return "Loại"
                }
            }
            var minWidth: CGFloat {
                switch self {
                case .name: return 160
                case .modified: return 110
                case .size: return 70
                case .kind: return 90
                }
            }
            var defaultWidth: CGFloat {
                switch self {
                case .name: return 280
                case .modified: return 140
                case .size: return 80
                case .kind: return 120
                }
            }
            var sortKey: SortKey? {
                switch self {
                case .name: return .name
                case .modified: return .modified
                case .size: return .size
                case .kind: return .kind
                }
            }
        }

        var pane: PaneState
        var model: BrowserWindowModel
        weak var tableView: NSTableView?

        /// Reload-coalescing fingerprint (contract: "chỉ nạp lại khi entries đổi thật"): count + first/last id is
        /// cheap to compare every `updateNSView` without diffing 100 000 rows, and a revision counter catches a
        /// same-count/same-ends reorder (e.g. a sort-key flip that happens to keep the same two end rows).
        private var lastCount = -1
        private var lastFirstID: String?
        private var lastLastID: String?
        private var revision = 0
        private var isSyncingSelection = false
        private var typeSelect = EntryRules.TypeSelect()
        private var renamingPath: String?
        private var cloudFactsCache: [String: CloudFacts] = [:]
        /// Last `pane.selection` this coordinator pushed into/read from the table, so `syncSelection()` can skip its
        /// O(entries.count) scan on the common `updateNSView` call where selection did not change (contract: "no
        /// O(n) work per updateNSView/frame" — this runs on every SwiftUI body re-evaluation, not just on clicks).
        private var lastSyncedSelection: Set<String> = []

        init(pane: PaneState, model: BrowserWindowModel) {
            self.pane = pane
            self.model = model
        }

        private func fingerprint() -> (Int, String?, String?) {
            (pane.entries.count, pane.entries.first?.id, pane.entries.last?.id)
        }

        func reloadIfNeeded() {
            let (count, first, last) = fingerprint()
            if count != lastCount || first != lastFirstID || last != lastLastID {
                lastCount = count
                lastFirstID = first
                lastLastID = last
                revision += 1
                cloudFactsCache.removeAll()
                // Row indices may have moved even when the same set of paths stays selected (e.g. a resort), so
                // force `syncSelection()` to recompute row indices on the next call rather than skipping it.
                lastSyncedSelection = []
                tableView?.reloadData()
            }
        }

        func syncSortIndicator() {
            guard let tableView else { return }
            for column in tableView.tableColumns {
                guard let key = Column(rawValue: column.identifier.rawValue)?.sortKey else { continue }
                if key == pane.sort.key {
                    tableView.setIndicatorImage(
                        NSImage(named: pane.sort.ascending ? NSImage.Name("NSAscendingSortIndicator")
                                                            : NSImage.Name("NSDescendingSortIndicator")),
                        in: column)
                } else {
                    tableView.setIndicatorImage(nil, in: column)
                }
            }
        }

        // MARK: - Selection (two-way)

        func syncSelection() {
            guard let tableView, !isSyncingSelection else { return }
            guard pane.selection != lastSyncedSelection else { return }
            let wanted = pane.selection
            var rows = IndexSet()
            for (index, entry) in pane.entries.enumerated() where wanted.contains(entry.path) {
                rows.insert(index)
            }
            lastSyncedSelection = wanted
            guard rows != tableView.selectedRowIndexes else { return }
            isSyncingSelection = true
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
            isSyncingSelection = false
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView, !isSyncingSelection else { return }
            isSyncingSelection = true
            let paths = tableView.selectedRowIndexes.compactMap { row -> String? in
                guard row < pane.entries.count else { return nil }
                return pane.entries[row].path
            }
            let selection = Set(paths)
            pane.selection = selection
            lastSyncedSelection = selection
            isSyncingSelection = false
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int { pane.entries.count }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key, let sortKey = SortKey(rawValue: key) else { return }
            pane.sort = SortOrder(key: sortKey, ascending: descriptor.ascending)
        }

        // MARK: - NSTableViewDelegate (cells)

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < pane.entries.count, let tableColumn,
                  let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
            let entry = pane.entries[row]
            let identifier = tableColumn.identifier
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                cell = Self.makeCell(column: column, identifier: identifier)
            }
            configure(cell: cell, column: column, entry: entry)
            return cell
        }

        private static func makeCell(column: Column, identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.font = .systemFont(ofSize: NSFont.systemFontSize)
            text.lineBreakMode = .byTruncatingMiddle
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = text
            cell.addSubview(text)
            if column == .name {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                cell.imageView = imageView
                cell.addSubview(imageView)
                let badge = NSImageView()
                badge.tag = Self.cloudBadgeTag
                badge.translatesAutoresizingMaskIntoConstraints = false
                badge.imageScaling = .scaleProportionallyDown
                cell.addSubview(badge)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    badge.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 2),
                    badge.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
                    badge.widthAnchor.constraint(equalToConstant: 9),
                    badge.heightAnchor.constraint(equalToConstant: 9),
                    text.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            return cell
        }

        /// Fixed tag for the small cloud-badge `NSImageView` overlaid on the Name column's icon.
        static let cloudBadgeTag = 9001

        private func configure(cell: NSTableCellView, column: Column, entry: DirectoryEntry) {
            switch column {
            case .name:
                cell.textField?.stringValue = entry.name
                cell.imageView?.image = FileIconCache.shared.icon(for: entry)
                let badge = cloudBadgeSymbol(for: cloudFacts(for: entry.path))
                (cell.viewWithTag(Self.cloudBadgeTag) as? NSImageView)?.image = badge
            case .modified:
                cell.textField?.stringValue = Self.dateText(entry.modified)
            case .size:
                cell.textField?.stringValue = entry.size >= 0 ? Self.sizeText(entry.size) : ""
            case .kind:
                cell.textField?.stringValue = FileIconCache.shared.kindName(for: entry)
            }
        }

        /// A fresh `DateFormatter` per call (Swift 6: no `static let DateFormatter` — not `Sendable`); cheap enough
        /// at table-cell cadence (only visible rows are configured, never all 100 000 at once).
        private static func dateText(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        private static func sizeText(_ bytes: Int64) -> String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }

        /// `CloudBadge` → a small SF Symbol glyph, or nil for `.none` (no overlay drawn at all — the common case,
        /// so most rows pay nothing beyond the one dictionary lookup in `cloudFacts(for:)`).
        private func cloudBadgeSymbol(for facts: CloudFacts) -> NSImage? {
            let badge = CloudRules.badge(facts)
            let name: String
            switch badge {
            case .none: return nil
            case .cloudOnly: name = "icloud"
            case .downloading: name = "icloud.and.arrow.down"
            case .uploading: name = "icloud.and.arrow.up"
            case .downloadFailed, .uploadFailed: name = "exclamationmark.icloud"
            }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }

        // MARK: - Double-click / Return / type-select

        @objc func doubleClicked() {
            guard let tableView, tableView.clickedRow >= 0, tableView.clickedRow < pane.entries.count else { return }
            pane.open(pane.entries[tableView.clickedRow])
        }

        /// Return starts an inline rename of the single selected row (contract: "mục = selection đơn"); Esc cancels
        /// via the cell's own `NSTextFieldDelegate` callback below. Type-select accumulates ordinary character keys.
        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard let characters = event.charactersIgnoringModifiers else { return false }
            if characters == "\r" || characters == "\u{3}" {
                if pane.selection.count == 1 { model.renaming = pane.id }
                return true
            }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let scalar = characters.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) || characters == " "
            else { return false }
            let buffer = typeSelect.type(characters, at: Date())
            let names = pane.entries.map(\.name)
            guard let index = EntryRules.TypeSelect.match(prefix: buffer, in: names) else { return false }
            select(rowAt: index)
            return true
        }

        private func select(rowAt index: Int) {
            guard let tableView, index >= 0, index < pane.entries.count else { return }
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        }

        // MARK: - Inline rename

        func beginRenameIfNeeded() {
            guard model.renaming == pane.id, renamingPath == nil,
                  let path = pane.selection.count == 1 ? pane.selection.first : nil,
                  let row = pane.entries.firstIndex(where: { $0.path == path }),
                  let tableView, let cell = tableView.view(atColumn: nameColumnIndex(), row: row, makeIfNecessary: false) as? NSTableCellView,
                  let field = cell.textField else { return }
            renamingPath = path
            let name = pane.entries[row].name
            field.isEditable = true
            field.delegate = self
            field.stringValue = name
            tableView.window?.makeFirstResponder(field)
            // Select the stem only (contract: "select the stem without extension").
            let ext = pane.entries[row].ext
            let stemLength = ext.isEmpty ? name.count : max(0, name.count - ext.count - 1)
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: 0, length: stemLength)
            }
        }

        private func nameColumnIndex() -> Int {
            tableView?.tableColumns.firstIndex { $0.identifier.rawValue == Column.name.rawValue } ?? 0
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                endRename(commit: false, field: control as? NSTextField)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                endRename(commit: true, field: control as? NSTextField)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, field.isEditable else { return }
            endRename(commit: true, field: field)
        }

        private func endRename(commit: Bool, field: NSTextField?) {
            guard let path = renamingPath else { return }
            renamingPath = nil
            field?.isEditable = false
            field?.delegate = nil
            if model.renaming == pane.id { model.renaming = nil }
            guard commit, let field else { return }
            _ = model.commitRename(path, to: field.stringValue)
        }

        // MARK: - Drag source

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < pane.entries.count else { return nil }
            let item = NSPasteboardItem()
            item.setString(URL(fileURLWithPath: pane.entries[row].path).absoluteString, forType: .fileURL)
            return item
        }

        // MARK: - Drop target

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                        proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
            let operation = dragOperation(for: info)
            if dropOperation == .on, row >= 0, row < pane.entries.count, pane.entries[row].isFolderLike {
                return operation
            }
            tableView.setDropRow(-1, dropOperation: .on)
            return operation
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                        dropOperation: NSTableView.DropOperation) -> Bool {
            guard let paths = draggedPaths(from: info) else { return false }
            let destination: String
            if dropOperation == .on, row >= 0, row < pane.entries.count, pane.entries[row].isFolderLike {
                destination = pane.entries[row].path
            } else {
                destination = pane.path
            }
            model.drop(paths, into: destination, copy: copyFlag(for: info))
            return true
        }

        private func dragOperation(for info: NSDraggingInfo) -> NSDragOperation {
            if info.draggingSourceOperationMask.contains(.generic) { return .generic }
            return info.draggingSourceOperationMask.contains(.move) ? .move : .copy
        }

        /// ⌥ forces copy, ⌘ forces move, else nil ⇒ `model.drop` decides by volume (contract).
        private func copyFlag(for info: NSDraggingInfo) -> Bool? {
            let flags = NSEvent.modifierFlags
            if flags.contains(.option) { return true }
            if flags.contains(.command) { return false }
            return nil
        }

        private func draggedPaths(from info: NSDraggingInfo) -> [String]? {
            guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  !urls.isEmpty else { return nil }
            return urls.map(\.path)
        }

        // MARK: - Context menu

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        private static let menuCommands: [BrowserCommand] = [
            .open, .openEnclosing, .quickLook, .rename, .duplicate, .copy, .paste, .copyPath,
            .moveToTrash, .compress, .showInFinder, .addToShelf,
        ]

        private func populateContextMenu(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            // Right-click on a row outside the current selection re-targets the selection first (contract).
            let clickedRow = tableView.clickedRow
            if clickedRow >= 0, clickedRow < pane.entries.count,
               !tableView.selectedRowIndexes.contains(clickedRow) {
                tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
            for command in Self.menuCommands {
                guard model.canPerform(command) else { continue }
                let item = NSMenuItem(title: L10n.t(BrowserCommands.titleKey(command)),
                                       action: #selector(performMenuCommand(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = command.rawValue
                menu.addItem(item)
            }
        }

        @objc private func performMenuCommand(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let command = BrowserCommand(rawValue: raw) else { return }
            model.focus(pane.id)
            _ = model.perform(command)
        }

        // MARK: - Cloud badge (lazy, visible rows only)

        func cloudFacts(for path: String) -> CloudFacts {
            if let cached = cloudFactsCache[path] { return cached }
            let facts = Self.readCloudFacts(path: path)
            cloudFactsCache[path] = facts
            return facts
        }

        nonisolated private static func readCloudFacts(path: String) -> CloudFacts {
            let url = URL(fileURLWithPath: path)
            let keys: Set<URLResourceKey> = [
                .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
                .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
                .ubiquitousItemDownloadingErrorKey, .ubiquitousItemUploadingErrorKey,
            ]
            guard let values = try? url.resourceValues(forKeys: keys) else { return CloudFacts() }
            return CloudFacts(
                isUbiquitous: values.isUbiquitousItem,
                downloadingStatus: values.ubiquitousItemDownloadingStatus?.rawValue,
                isDownloading: values.ubiquitousItemIsDownloading,
                isUploading: values.ubiquitousItemIsUploading,
                isUploaded: values.ubiquitousItemIsUploaded,
                hasDownloadError: values.ubiquitousItemDownloadingError != nil,
                hasUploadError: values.ubiquitousItemUploadingError != nil)
        }
    }
}

extension FileListView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        populateContextMenu(menu)
    }
}
