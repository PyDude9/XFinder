import AppKit
import SwiftUI

/// XF-T30 W2 (was XF-T28 cluster D) — Cột (NSBrowser). Each column is one directory; selecting a folder opens the
/// next column to its right (packages are leaves — contract: "packages are leaves"); the last column, when the
/// final selection is a plain file, shows a small preview (icon + name + size + kind) instead of another column of
/// children. W2 adds: cloud badge + tag dot on every row, a non-selectable pseudo group-header row per
/// `GroupBy`/`pane.useGroups`, Esc cancelling an in-flight drag, no leftover empty column after the preview column
/// closes (FileOctopus 1.0.4 bug), and restoring the WHOLE column trail from `pane.columnPath` (Q-T30-7) instead of
/// only re-deriving it from `pane.path`'s ancestry.
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
        browser.setCellClass(ColumnBrowserCell.self)
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

    /// Routes `keyDown` (type-select / Return-to-rename / arrow keys skipping a group-header row) to the coordinator
    /// before `NSBrowser`'s own handling.
    final class KeyRoutingBrowser: NSBrowser {
        weak var coordinator: Coordinator?
        override func keyDown(with event: NSEvent) {
            if coordinator?.handleKeyDown(event) == true { return }
            super.keyDown(with: event)
        }
    }

    /// One row of a column: a real file/folder, or a non-selectable pseudo group-header (contract: "hàng tiêu đề
    /// nhóm giả — không chọn, mũi tên bỏ qua"). `NSBrowser`'s row/column delegate has no native concept of a
    /// header row, so this coordinator keeps its own per-column row list and maps `NSBrowser`'s row indices
    /// through it.
    enum ColumnRow {
        case header(titleKey: String, titleArg: String?)
        case entry(DirectoryEntry)

        var entry: DirectoryEntry? {
            if case .entry(let e) = self { return e }
            return nil
        }

        var isHeader: Bool {
            if case .header = self { return true }
            return false
        }
    }

    /// `NSBrowserCell` draws its own image/string; there is no subview to overlay a badge on, so this subclass
    /// paints the cloud badge (bottom-right) and tag dot (bottom-left) directly over the icon it already drew,
    /// using the coordinator-populated `tagColor`/`cloudBadge`. `isGroupHeader` draws a plain bold label instead of
    /// an icon+name row and reports itself non-selectable.
    final class ColumnBrowserCell: NSBrowserCell {
        var tagColor: TagColor?
        var cloudBadge: CloudBadge = .none
        var isGroupHeader = false

        override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
            if isGroupHeader {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                let text = stringValue as NSString
                let size = text.size(withAttributes: attrs)
                let origin = NSPoint(x: cellFrame.minX + 6, y: cellFrame.midY - size.height / 2)
                text.draw(at: origin, withAttributes: attrs)
                return
            }
            super.drawInterior(withFrame: cellFrame, in: controlView)
            guard image != nil else { return }
            // NSBrowserCell draws its icon at a fixed 16x16 leading inset; the badge sits over its bottom-right
            // corner and the tag dot over its bottom-left, same relative placement as the Name column in
            // FileListView's NSTableCellView overlay.
            let iconSide: CGFloat = 16
            let iconOrigin = NSPoint(x: cellFrame.minX + 2, y: cellFrame.midY - iconSide / 2)
            if let badgeImage = Self.badgeImage(for: cloudBadge) {
                let badgeSide: CGFloat = 9
                let badgeRect = NSRect(x: iconOrigin.x + iconSide - badgeSide + 2, y: iconOrigin.y - 2,
                                       width: badgeSide, height: badgeSide)
                badgeImage.draw(in: badgeRect)
            }
            if let tagColor, tagColor != .none, let dotColor = Self.dotColor(for: tagColor) {
                let dotSide: CGFloat = 6
                let dotRect = NSRect(x: iconOrigin.x - 1, y: iconOrigin.y - 1, width: dotSide, height: dotSide)
                let path = NSBezierPath(ovalIn: dotRect)
                dotColor.setFill()
                path.fill()
            }
        }

        private static func badgeImage(for badge: CloudBadge) -> NSImage? {
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

        /// Finder's seven tag colours (matches `TagColor`'s own ordering/meaning) — a literal RGB table, not a
        /// design token: these are fixed values that have to visually match Finder's own tag dots, not XFinder's
        /// own palette (`XFinderTokens` is exempt here the same way `FileListView`'s SF Symbol badges are).
        private static func dotColor(for tagColor: TagColor) -> NSColor? {
            switch tagColor {
            case .none: return nil
            case .gray: return NSColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1)
            case .green: return NSColor(red: 0.35, green: 0.74, blue: 0.35, alpha: 1)
            case .purple: return NSColor(red: 0.69, green: 0.40, blue: 0.86, alpha: 1)
            case .blue: return NSColor(red: 0.29, green: 0.56, blue: 0.95, alpha: 1)
            case .yellow: return NSColor(red: 0.98, green: 0.78, blue: 0.25, alpha: 1)
            case .red: return NSColor(red: 0.94, green: 0.33, blue: 0.31, alpha: 1)
            case .orange: return NSColor(red: 0.98, green: 0.58, blue: 0.24, alpha: 1)
            }
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
        private var cloudFactsCache: [String: CloudFacts] = [:]
        /// Set while a drag started from this browser is in flight, so a local Escape-key monitor can end it
        /// (contract: "Esc huỷ kéo").
        private var dragEscapeMonitor: Any?

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

        /// Q-T30-7: when `pane.columnPath` already names a trail that still starts at the same place `pane.path`'s
        /// own ancestry would (a restored session, or a trail this coordinator wrote on an earlier navigation),
        /// that full trail is used instead of only re-deriving the ancestors of `pane.path` — "khôi phục cả đường
        /// cột", not only the last folder like FileOctopus does. A trail whose last element is not `pane.path`
        /// itself and not an ancestor of it (stale/unrelated) is ignored.
        func loadColumnsForCurrentPath(initial: Bool) {
            let ancestry = Self.ancestry(of: pane.path)
            if initial, let remembered = Self.usableColumnPath(pane.columnPath, ancestry: ancestry) {
                columnPaths = remembered
            } else {
                columnPaths = ancestry
            }
            pane.columnPath = columnPaths
            lastSyncedPath = pane.path
            for path in columnPaths { ensureLoaded(path) }
            browser?.loadColumnZero()
        }

        /// `remembered` is usable when its elements are, in order, a prefix chain down to-or-through `ancestry`
        /// (i.e. it still agrees with `pane.path`'s own lineage) — anything else is a stale/unrelated trail from a
        /// different folder and must not be trusted blindly.
        private static func usableColumnPath(_ remembered: [String], ancestry: [String]) -> [String]? {
            guard !remembered.isEmpty, remembered.count >= ancestry.count else { return nil }
            for (index, path) in ancestry.enumerated() where remembered[index] != path { return nil }
            return remembered
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
            rows(forColumn: columnPaths.firstIndex(of: parentPath) ?? -1).firstIndex { $0.entry?.path == path } ?? 0
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
            guard column >= 0, column < columnPaths.count else { return [] }
            return columnEntries[columnPaths[column]] ?? []
        }

        /// The display rows of a column: grouped into pseudo-header + entry rows when `pane.useGroups`, otherwise
        /// one row per entry. Group headers are not selectable and arrow keys skip them (contract).
        private func rows(forColumn column: Int) -> [ColumnRow] {
            let flat = entries(forColumn: column)
            guard pane.useGroups else { return flat.map { .entry($0) } }
            let sections = GroupBy.sections(flat, by: pane.groupBy, sort: pane.sort, foldersFirst: pane.foldersFirst,
                                            now: Date(), calendar: .current,
                                            kindName: { FileIconCache.shared.kindName(for: $0) },
                                            appName: { FileMetadataCache.shared.appName(for: $0.path) })
            guard sections.count > 1 || sections.first?.titleKey.isEmpty == false else { return flat.map { .entry($0) } }
            var out: [ColumnRow] = []
            for section in sections where !section.entries.isEmpty {
                out.append(.header(titleKey: section.titleKey, titleArg: section.titleArg))
                out.append(contentsOf: section.entries.map { .entry($0) })
            }
            return out
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
            return rows(forColumn: column).count
        }

        func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
            guard let browserCell = cell as? ColumnBrowserCell else { return }
            browserCell.tagColor = nil
            browserCell.cloudBadge = .none
            browserCell.isGroupHeader = false
            if column == columnPaths.count, let path = previewPath() {
                configurePreviewCell(browserCell, path: path)
                return
            }
            let displayRows = rows(forColumn: column)
            guard row < displayRows.count else { return }
            switch displayRows[row] {
            case .header(let titleKey, let titleArg):
                browserCell.isGroupHeader = true
                browserCell.isLeaf = true
                browserCell.image = nil
                browserCell.stringValue = EntrySection(titleKey: titleKey, titleArg: titleArg, entries: [])
                    .displayTitle { L10n.t($0) }
            case .entry(let entry):
                browserCell.stringValue = entry.name
                browserCell.image = FileIconCache.shared.icon(for: entry)
                // Packages are leaves (contract): never shows the disclosure arrow even though it is a directory.
                browserCell.isLeaf = !entry.isFolderLike
                browserCell.cloudBadge = CloudRules.badge(cloudFacts(for: entry.path))
                browserCell.tagColor = tagColor(for: entry)
            }
        }

        /// First tag's colour (a row shows one dot, same simplification `FileListView`'s Name-column overlay would
        /// make — `entry.tags` is nil until `FileMetadataCache`/the reader has filled it in, not "no tags").
        private func tagColor(for entry: DirectoryEntry) -> TagColor? {
            guard let raw = entry.tags?.first else { return nil }
            return FinderTags.parse(raw).color
        }

        private func configurePreviewCell(_ cell: ColumnBrowserCell, path: String) {
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
            cell.cloudBadge = CloudRules.badge(cloudFacts(for: path))
            cell.tagColor = tagColor(for: entry)
        }

        // MARK: - Selection

        /// Group-header pseudo-rows are not selectable (contract).
        func browser(_ sender: NSBrowser, selectRow row: Int, inColumn column: Int) -> Bool {
            let displayRows = rows(forColumn: column)
            guard row < displayRows.count else { return true }
            return !displayRows[row].isHeader
        }

        /// The rightmost column that actually holds `DirectoryEntry` rows — `browser.lastColumn` instead points at
        /// the synthetic preview column once one has been appended (`addColumn()` below), which holds no entries.
        private var lastRealColumn: Int { columnPaths.count - 1 }

        /// `NSBrowser.selectedRowIndexes(inColumn:)` returns `IndexSet?` (nil for an out-of-range/unloaded column);
        /// every call site here wants "empty" for that case, not an optional to keep threading through.
        private func selectedRows(_ browser: NSBrowser, inColumn column: Int) -> IndexSet {
            browser.selectedRowIndexes(inColumn: column) ?? IndexSet()
        }

        /// Maps selected display-row indices (which may include header rows interleaved by `rows(forColumn:)`)
        /// back to the `DirectoryEntry` values they stand for.
        private func selectedEntries(_ browser: NSBrowser, inColumn column: Int) -> [DirectoryEntry] {
            let displayRows = rows(forColumn: column)
            return selectedRows(browser, inColumn: column).compactMap { $0 < displayRows.count ? displayRows[$0].entry : nil }
        }

        /// Fired by `NSBrowser.action` on every selection change (there is no delegate callback or notification for
        /// this — `NSBrowser` is an `NSControl` and reports selection the same way a button reports a click).
        @objc func selectionChanged() {
            guard !isSyncingSelection, let browser, lastRealColumn >= 0 else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            let column = lastRealColumn
            let selected = selectedEntries(browser, inColumn: column)
            if selected.count == 1, selected[0].isFolderLike {
                pane.selection = []
                if selected[0].path != pane.path {
                    pane.navigate(to: selected[0].path)
                }
            } else {
                pane.selection = Set(selected.map(\.path))
            }
            updatePreviewColumn()
        }

        /// Appends or drops the trailing preview column so its row count (0 or 1, from `numberOfRowsInColumn`)
        /// matches whether a single file is selected right now. FileOctopus 1.0.4 bug: dropping the preview column
        /// left a blank strip where it used to be — `lastColumn` alone tells `NSBrowser` which column is rightmost,
        /// but does not itself ask it to recompute the scroll content width, so the now-gone column's frame stayed
        /// reserved until some unrelated resize; `tile()` forces that recomputation the same frame.
        private func updatePreviewColumn() {
            guard let browser else { return }
            let wantsPreview = previewPath() != nil
            let hasPreview = browser.lastColumn == columnPaths.count
            if wantsPreview, !hasPreview {
                browser.addColumn()
                browser.tile()
            } else if !wantsPreview, hasPreview {
                browser.lastColumn = max(0, columnPaths.count - 1)
                browser.tile()
            } else if wantsPreview {
                browser.reloadColumn(columnPaths.count)
            }
        }

        func syncSelection() {
            // Two-way: if `pane.selection` was set by another view (e.g. palette), reflect it in the last column.
            guard !isSyncingSelection, let browser, lastRealColumn >= 0,
                  let path = pane.selection.count == 1 ? pane.selection.first : nil else { return }
            let column = lastRealColumn
            guard let row = rows(forColumn: column).firstIndex(where: { $0.entry?.path == path }) else { return }
            if !selectedRows(browser, inColumn: column).contains(row) {
                isSyncingSelection = true
                browser.selectRow(row, inColumn: column)
                isSyncingSelection = false
            }
            updatePreviewColumn()
        }

        // MARK: - Double-click / Return / type-select / arrow-skips-header

        @objc func doubleClicked() {
            guard let browser, lastRealColumn >= 0 else { return }
            for entry in selectedEntries(browser, inColumn: lastRealColumn) { pane.open(entry) }
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard let characters = event.charactersIgnoringModifiers else { return false }
            if characters == "\r" || characters == "\u{3}" {
                if pane.selection.count == 1 { model.renaming = pane.id }
                return true
            }
            if let arrowRow = handleArrowSkippingHeader(event) { return arrowRow }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let scalar = characters.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) || characters == " "
            else { return false }
            guard let browser, lastRealColumn >= 0 else { return false }
            let column = lastRealColumn
            let displayRows = rows(forColumn: column)
            let names = displayRows.compactMap { $0.entry?.name }
            let buffer = typeSelect.type(characters, at: Date())
            guard let nameIndex = EntryRules.TypeSelect.match(prefix: buffer, in: names) else { return false }
            // `nameIndex` is into the entry-only `names` list; translate back to the display-row index it came from.
            var seen = -1
            for (rowIndex, displayRow) in displayRows.enumerated() where displayRow.entry != nil {
                seen += 1
                if seen == nameIndex {
                    browser.selectRow(rowIndex, inColumn: column)
                    break
                }
            }
            return true
        }

        /// Up/Down arrow landing on a group-header row (contract: "mũi tên bỏ qua") steps one further in the same
        /// direction instead of stopping there — `nil` when the key is not an arrow (caller falls through to its
        /// own handling), `true`/`false` once this has fully handled (or declined) the arrow itself.
        private func handleArrowSkippingHeader(_ event: NSEvent) -> Bool? {
            guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  let browser, lastRealColumn >= 0 else { return nil }
            let delta: Int
            switch event.keyCode {
            case 125: delta = 1     // Down
            case 126: delta = -1    // Up
            default: return nil
            }
            let column = lastRealColumn
            let displayRows = rows(forColumn: column)
            guard !displayRows.isEmpty else { return nil }
            let current = selectedRows(browser, inColumn: column).max() ?? (delta > 0 ? -1 : displayRows.count)
            var next = current + delta
            while next >= 0, next < displayRows.count, displayRows[next].isHeader { next += delta }
            guard next >= 0, next < displayRows.count else { return true }
            browser.selectRow(next, inColumn: column)
            return true
        }

        // MARK: - Inline rename (last column's selected row)

        func beginRenameIfNeeded() {
            guard model.renaming == pane.id, renamingPath == nil,
                  let path = pane.selection.count == 1 ? pane.selection.first : nil,
                  let browser, lastRealColumn >= 0 else { return }
            let column = lastRealColumn
            guard let row = rows(forColumn: column).firstIndex(where: { $0.entry?.path == path }) else { return }
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
            let displayRows = rows(forColumn: column)
            let urls = rowIndexes.compactMap { row -> URL? in
                guard row < displayRows.count, let entry = displayRows[row].entry else { return nil }
                return URL(fileURLWithPath: entry.path)
            }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            installDragEscapeMonitor()
            return true
        }

        /// Contract: "Esc huỷ kéo". `NSBrowser`'s legacy `writeRowsWithIndexes:inColumn:toPasteboard:` drag source
        /// is the browser itself, not this delegate, so there is no `NSDraggingSession` callback here to hang
        /// cleanup off of; a pair of local monitors (installed only while a drag from this browser is in flight)
        /// stands in for it instead — Escape ends the OS-level drag-and-drop session (the system's own drag manager
        /// treats it as a cancel the same way it would for a `Finder` drag), and a mouse-up monitor is the fallback
        /// that tears both monitors down once the drag ends on its own (drop, or released outside any target).
        private func installDragEscapeMonitor() {
            guard dragEscapeMonitor == nil else { return }
            dragEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { [weak self] event in
                if event.type == .leftMouseUp {
                    self?.removeDragEscapeMonitor()
                    return event
                }
                guard event.keyCode == 53 else { return event }   // 53 = Escape
                self?.removeDragEscapeMonitor()
                return nil   // swallow it; the drag manager's own Escape handling takes it from here
            }
        }

        private func removeDragEscapeMonitor() {
            guard let dragEscapeMonitor else { return }
            NSEvent.removeMonitor(dragEscapeMonitor)
            self.dragEscapeMonitor = nil
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
            let displayRows = rows(forColumn: column)
            let destination: String
            if row >= 0, row < displayRows.count, let entry = displayRows[row].entry, entry.isFolderLike {
                destination = entry.path
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

        /// XF-T30 W2: the ONE menu for all four views (contract §3) — `BrowserContextMenu.menu(for:pane:)` rebuilds
        /// fully on every open, so this just hands it the live model/pane each time instead of keeping its own copy.
        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        // MARK: - Cloud badge (lazy, visible rows only — same cache shape as FileListView's)

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

extension FileColumnView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = BrowserContextMenu.menu(for: model, pane: pane)
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
}
