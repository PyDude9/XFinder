import AppKit
import SwiftUI

/// XF-T28 cluster D — Cột (NSBrowser). Each column is one directory; selecting a folder opens the next column to
/// its right (packages are leaves — contract: "packages are leaves"); the last column, when the final selection is
/// a plain file, shows a small preview (icon + name + size + kind) instead of another column of children.
struct FileColumnView: NSViewRepresentable {
    let pane: PaneState
    let model: BrowserWindowModel

    func makeNSView(context: Context) -> NSBrowser {
        let browser = KeyRoutingBrowser()
        browser.coordinator = context.coordinator
        browser.delegate = context.coordinator
        browser.target = context.coordinator
        browser.action = #selector(Coordinator.selectionChanged)
        browser.doubleAction = #selector(Coordinator.doubleClicked)
        browser.allowsMultipleSelection = true
        browser.takesTitleFromPreviousColumn = false
        browser.separatesColumns = true
        browser.isTitled = false
        browser.registerForDraggedTypes([.fileURL])
        browser.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        browser.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        browser.menu = context.coordinator.makeContextMenu()
        context.coordinator.browser = browser
        context.coordinator.loadColumnsForCurrentPath(initial: true)
        return browser
    }

    func updateNSView(_ nsView: NSBrowser, context: Context) {
        context.coordinator.pane = pane
        context.coordinator.model = model
        context.coordinator.invalidateCacheIfDisplaySettingsChanged()
        context.coordinator.syncPathIfNeeded()
        context.coordinator.syncSelection()
        context.coordinator.beginRenameIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator(pane: pane, model: model) }

    /// Routes `keyDown` (type-select / Return-to-rename) to the coordinator before `NSBrowser`'s own handling.
    final class KeyRoutingBrowser: NSBrowser {
        weak var coordinator: Coordinator?
        override func keyDown(with event: NSEvent) {
            if coordinator?.handleKeyDown(event) == true { return }
            super.keyDown(with: event)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSBrowserDelegate, NSTextFieldDelegate {
        var pane: PaneState
        var model: BrowserWindowModel
        weak var browser: NSBrowser?

        /// Directory listing per column path, loaded off-main via `DirectoryReader.list` and cached so scrolling
        /// back and forth across columns does not re-hit the disk; invalidated by the directory watcher the model
        /// owns (reload on watcher — this view only re-asks when `pane.path`/`pane.entries` move it forward), and
        /// also by `invalidateCacheIfDisplaySettingsChanged()` below when sort/hidden-files settings change (those
        /// are baked into each cached array at load time, not read again later).
        private var columnEntries: [String: [DirectoryEntry]] = [:]
        private var loadingPaths: Set<String> = []
        private var columnPaths: [String] = []
        private var lastSyncedPath = ""
        private var isSyncingSelection = false
        private var typeSelect = EntryRules.TypeSelect()
        private var renamingPath: String?
        private var lastDisplaySettings: DisplaySettings?

        private struct DisplaySettings: Equatable {
            let showHidden: Bool
            let sort: SortOrder
            let foldersFirst: Bool
        }

        init(pane: PaneState, model: BrowserWindowModel) {
            self.pane = pane
            self.model = model
            self.lastDisplaySettings = DisplaySettings(showHidden: pane.showHidden, sort: pane.sort, foldersFirst: pane.foldersFirst)
        }

        /// Sort order, hidden-files, or folders-first flipped since the last read: every cached column was built
        /// with the old settings baked in (contract: "children loaded off-main and cached" — stale here means wrong
        /// order/visibility until the user navigates away and back, not just a slow reload).
        func invalidateCacheIfDisplaySettingsChanged() {
            let current = DisplaySettings(showHidden: pane.showHidden, sort: pane.sort, foldersFirst: pane.foldersFirst)
            guard current != lastDisplaySettings else { return }
            lastDisplaySettings = current
            columnEntries.removeAll()
            for path in columnPaths { ensureLoaded(path) }
            for index in columnPaths.indices { browser?.reloadColumn(index) }
            updatePreviewColumn()
        }

        // MARK: - Column path tracking

        func loadColumnsForCurrentPath(initial: Bool) {
            columnPaths = Self.ancestry(of: pane.path)
            lastSyncedPath = pane.path
            for path in columnPaths { ensureLoaded(path) }
            browser?.loadColumnZero()
        }

        func syncPathIfNeeded() {
            guard pane.path != lastSyncedPath else { return }
            loadColumnsForCurrentPath(initial: false)
            if let browser {
                let components = columnPaths
                for (index, path) in components.enumerated() where index > 0 {
                    browser.selectRow(rowIndex(of: path, in: components[index - 1]), inColumn: index - 1)
                }
            }
        }

        /// Every ancestor from the volume root down to `path` itself, root first — one NSBrowser column per level.
        private static func ancestry(of path: String) -> [String] {
            var components: [String] = []
            var current = path
            while true {
                components.append(current)
                let parent = (current as NSString).deletingLastPathComponent
                if parent == current || parent.isEmpty { break }
                current = parent
            }
            return components.reversed()
        }

        private func rowIndex(of path: String, in parentPath: String) -> Int {
            (columnEntries[parentPath] ?? []).firstIndex { $0.path == path } ?? 0
        }

        private func ensureLoaded(_ path: String) {
            guard columnEntries[path] == nil, !loadingPaths.contains(path) else { return }
            loadingPaths.insert(path)
            Task { [weak self] in
                let result = await DirectoryReader.list(path, timeout: 5)
                await MainActor.run {
                    guard let self else { return }
                    self.loadingPaths.remove(path)
                    switch result {
                    case .success(let entries):
                        let visible = EntryRules.visible(entries, showHidden: self.pane.showHidden)
                        self.columnEntries[path] = EntryRules.sorted(visible, by: self.pane.sort, foldersFirst: self.pane.foldersFirst) {
                            FileIconCache.shared.kindName(for: $0)
                        }
                    case .failure:
                        self.columnEntries[path] = []
                    }
                    self.browser?.reloadColumn(self.columnPaths.firstIndex(of: path) ?? 0)
                }
            }
        }

        private func entries(forColumn column: Int) -> [DirectoryEntry] {
            guard column < columnPaths.count else { return [] }
            return columnEntries[columnPaths[column]] ?? []
        }

        /// The path of the single selected file that earns this browser its trailing preview column — nil whenever
        /// the selection is empty, multiple, or itself a folder (a folder already has its own children column).
        private func previewPath() -> String? {
            guard browser != nil, pane.selection.count == 1, let path = pane.selection.first else { return nil }
            guard lastRealColumn >= 0, entries(forColumn: lastRealColumn).contains(where: { $0.path == path && !$0.isFolderLike }) else { return nil }
            return path
        }

        // MARK: - NSBrowserDelegate

        /// One extra synthetic row-of-one column after the real path columns, used only to render the file
        /// preview (contract: "the last column of a file shows a preview"). The legacy row/column `NSBrowser`
        /// delegate has no dedicated preview-column API (that only exists on the item-based `NSBrowser`, which
        /// this file does not use), so the preview is just another column whose one "row" is drawn specially.
        func browser(_ sender: NSBrowser, numberOfRowsInColumn column: Int) -> Int {
            if column == columnPaths.count { return previewPath() == nil ? 0 : 1 }
            let path = column < columnPaths.count ? columnPaths[column] : nil
            if let path { ensureLoaded(path) }
            return entries(forColumn: column).count
        }

        func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
            guard let browserCell = cell as? NSBrowserCell else { return }
            if column == columnPaths.count, let path = previewPath() {
                configurePreviewCell(browserCell, path: path)
                return
            }
            let rows = entries(forColumn: column)
            guard row < rows.count else { return }
            let entry = rows[row]
            browserCell.stringValue = entry.name
            browserCell.image = FileIconCache.shared.icon(for: entry)
            // Packages are leaves (contract): never shows the disclosure arrow even though it is a directory.
            browserCell.isLeaf = !entry.isFolderLike
        }

        private func configurePreviewCell(_ cell: NSBrowserCell, path: String) {
            cell.isLeaf = true
            cell.image = FileIconCache.shared.icon(forPath: path)
            let name = (path as NSString).lastPathComponent
            guard let entry = entries(forColumn: columnPaths.count - 1).first(where: { $0.path == path }) else {
                cell.stringValue = name
                return
            }
            let size = entry.size >= 0 ? ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file) : ""
            let kind = FileIconCache.shared.kindName(for: entry)
            cell.stringValue = "\(name)\n\(kind) · \(size)"
        }

        // MARK: - Selection

        func browser(_ sender: NSBrowser, selectRow row: Int, inColumn column: Int) -> Bool { true }

        /// The rightmost column that actually holds `DirectoryEntry` rows — `browser.lastColumn` instead points at
        /// the synthetic preview column once one has been appended (`addColumn()` below), which holds no entries.
        private var lastRealColumn: Int { columnPaths.count - 1 }

        /// `NSBrowser.selectedRowIndexes(inColumn:)` returns `IndexSet?` (nil for an out-of-range/unloaded column);
        /// every call site here wants "empty" for that case, not an optional to keep threading through.
        private func selectedRows(_ browser: NSBrowser, inColumn column: Int) -> IndexSet {
            browser.selectedRowIndexes(inColumn: column) ?? IndexSet()
        }

        /// Fired by `NSBrowser.action` on every selection change (there is no delegate callback or notification for
        /// this — `NSBrowser` is an `NSControl` and reports selection the same way a button reports a click).
        @objc func selectionChanged() {
            guard !isSyncingSelection, let browser, lastRealColumn >= 0 else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            let column = lastRealColumn
            let selectedRows = selectedRows(browser, inColumn: column)
            let rows = entries(forColumn: column)
            let selectedPaths = selectedRows.compactMap { $0 < rows.count ? rows[$0].path : nil }
            if selectedPaths.count == 1, let entry = rows.first(where: { $0.path == selectedPaths[0] }), entry.isFolderLike {
                pane.selection = []
                if entry.path != pane.path {
                    pane.navigate(to: entry.path)
                }
            } else {
                pane.selection = Set(selectedPaths)
            }
            updatePreviewColumn()
        }

        /// Appends or drops the trailing preview column so its row count (0 or 1, from `numberOfRowsInColumn`)
        /// matches whether a single file is selected right now.
        private func updatePreviewColumn() {
            guard let browser else { return }
            let wantsPreview = previewPath() != nil
            let hasPreview = browser.lastColumn == columnPaths.count
            if wantsPreview, !hasPreview {
                browser.addColumn()
            } else if !wantsPreview, hasPreview {
                browser.lastColumn = max(0, columnPaths.count - 1)
            } else if wantsPreview {
                browser.reloadColumn(columnPaths.count)
            }
        }

        func syncSelection() {
            // Two-way: if `pane.selection` was set by another view (e.g. palette), reflect it in the last column.
            guard !isSyncingSelection, let browser, lastRealColumn >= 0,
                  let path = pane.selection.count == 1 ? pane.selection.first : nil else { return }
            let column = lastRealColumn
            guard let row = entries(forColumn: column).firstIndex(where: { $0.path == path }) else { return }
            if !selectedRows(browser, inColumn: column).contains(row) {
                isSyncingSelection = true
                browser.selectRow(row, inColumn: column)
                isSyncingSelection = false
            }
            updatePreviewColumn()
        }

        // MARK: - Double-click / Return / type-select

        @objc func doubleClicked() {
            guard let browser, lastRealColumn >= 0 else { return }
            let column = lastRealColumn
            let rows = entries(forColumn: column)
            for row in selectedRows(browser, inColumn: column) where row < rows.count {
                pane.open(rows[row])
            }
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard let characters = event.charactersIgnoringModifiers else { return false }
            if characters == "\r" || characters == "\u{3}" {
                if pane.selection.count == 1 { model.renaming = pane.id }
                return true
            }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let scalar = characters.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) || characters == " "
            else { return false }
            guard let browser, lastRealColumn >= 0 else { return false }
            let column = lastRealColumn
            let rows = entries(forColumn: column)
            let buffer = typeSelect.type(characters, at: Date())
            guard let index = EntryRules.TypeSelect.match(prefix: buffer, in: rows.map(\.name)) else { return false }
            browser.selectRow(index, inColumn: column)
            return true
        }

        // MARK: - Inline rename (last column's selected row)

        func beginRenameIfNeeded() {
            guard model.renaming == pane.id, renamingPath == nil,
                  let path = pane.selection.count == 1 ? pane.selection.first : nil,
                  let browser, lastRealColumn >= 0 else { return }
            let column = lastRealColumn
            guard let row = entries(forColumn: column).firstIndex(where: { $0.path == path }) else { return }
            renamingPath = path
            // NSBrowser does not support arbitrary inline editing of a cell by default; emulate it with a field
            // editor positioned over the row's frame, already given in the browser's own coordinate space.
            let frame = browser.frame(ofRow: row, inColumn: column)
            let field = NSTextField(string: (path as NSString).lastPathComponent)
            field.frame = frame
            field.isEditable = true
            field.delegate = self
            browser.addSubview(field)
            browser.window?.makeFirstResponder(field)
            let name = (path as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension
            let stemLength = ext.isEmpty ? name.count : max(0, name.count - ext.count - 1)
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: stemLength)
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
            endRename(commit: true, field: obj.object as? NSTextField)
        }

        private func endRename(commit: Bool, field: NSTextField?) {
            guard let path = renamingPath else { return }
            renamingPath = nil
            field?.removeFromSuperview()
            if model.renaming == pane.id { model.renaming = nil }
            guard commit, let field else { return }
            _ = model.commitRename(path, to: field.stringValue)
        }

        // MARK: - Drag source

        /// `browser(_:pasteboardWriterForRow:column:)` only exists from macOS 27 (this contract's deployment target
        /// is 14.0+ — CLAUDE.md §0), so this uses the long-standing `writeRowsWithIndexes:inColumn:toPasteboard:`
        /// instead, which every supported OS version has.
        func browser(_ sender: NSBrowser, writeRowsWith rowIndexes: IndexSet, inColumn column: Int, to pasteboard: NSPasteboard) -> Bool {
            let rows = entries(forColumn: column)
            let urls = rowIndexes.compactMap { row -> URL? in
                guard row < rows.count else { return nil }
                return URL(fileURLWithPath: rows[row].path)
            }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            return true
        }

        // MARK: - Drop target

        func browser(_ sender: NSBrowser, validateDrop info: NSDraggingInfo, proposedRow row: UnsafeMutablePointer<Int>,
                      column: UnsafeMutablePointer<Int>, dropOperation: UnsafeMutablePointer<NSBrowser.DropOperation>) -> NSDragOperation {
            guard info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
            return dragOperation(for: info)
        }

        func browser(_ sender: NSBrowser, acceptDrop info: NSDraggingInfo, atRow row: Int, column: Int,
                      dropOperation: NSBrowser.DropOperation) -> Bool {
            guard let paths = draggedPaths(from: info) else { return false }
            let rows = entries(forColumn: column)
            let destination: String
            if row >= 0, row < rows.count, rows[row].isFolderLike {
                destination = rows[row].path
            } else if column < columnPaths.count {
                destination = columnPaths[column]
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
    }
}

extension FileColumnView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        populateContextMenu(menu)
    }
}
