import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// XF-T30 W2 (builder "w2l", contract docs/specs/XF-T30-w2-contract.md §3) — Danh sách, rewritten on `NSOutlineView`
/// so a folder can disclose its children in place (Finder's own List view), replacing the XF-T28 `NSTableView` flat
/// list. Source of truth for the TOP LEVEL is still `pane.entries` (already hidden/filtered/sorted by `PaneState`)
/// or, when `pane.useGroups` is on, `pane.sections` (group header rows interleaved, `GroupBy.sections`); a disclosed
/// subfolder's children are NOT in either of those (the pane only ever loads its own one folder) — this view reads
/// them itself through `DirectoryReader.list`, exactly how `FileColumnView` already loads its columns, and owns one
/// `DirectoryWatcher` per expanded folder, cancelled the moment that row collapses (contract ca hỏng: "không rò
/// DirectoryWatcher").
struct FileListView: NSViewRepresentable {
    let pane: PaneState
    let model: BrowserWindowModel

    /// Row height is a named constant per the contract (AppKit-only exemption from `XFinderTokens`): a table row
    /// drawn by `NSTableCellView` is laid out in points the same way regardless of which SwiftUI token scale is
    /// active, so this is not a design-system value, it is a measurement of the 16×16 icon + single text line.
    static let rowHeight: CGFloat = 22
    static let groupRowHeight: CGFloat = 20

    /// ⌥→/⌥← recursive expand/collapse (contract §3): stop and show a banner past this many additionally-opened
    /// rows in one gesture, rather than hanging on a tree with millions of descendants.
    static let recursiveExpandCap = 10_000

    /// Routes `keyDown` to the coordinator (type-select / Return-to-rename / ← → navigation) before falling back to
    /// `NSOutlineView`'s own handling, since the base class never calls the delegate for raw key events.
    final class KeyRoutingOutlineView: NSOutlineView , PaneActivating {
        var activatePane: (() -> Void)?
        weak var coordinator: Coordinator?
        override func keyDown(with event: NSEvent) {
            if coordinator?.handleKeyDown(event) == true { return }
            super.keyDown(with: event)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = KeyRoutingOutlineView()
        outlineView.coordinator = context.coordinator
        outlineView.activatePane = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.model.focus(coordinator.pane.id)
        }
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.rowHeight = Self.rowHeight
        outlineView.headerView = NSTableHeaderView()
        outlineView.allowsMultipleSelection = true
        outlineView.allowsColumnReordering = false
        outlineView.allowsColumnResizing = true
        outlineView.focusRingType = .none
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = false
        outlineView.floatsGroupRows = false
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.doubleClicked)
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        outlineView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        outlineView.menu = context.coordinator.makeContextMenu()
        outlineView.headerView?.menu = context.coordinator.makeHeaderMenu()

        context.coordinator.rebuildColumns(in: outlineView)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        context.coordinator.outlineView = outlineView
        context.coordinator.syncSortIndicator()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.pane = pane
        context.coordinator.model = model
        let metadataRevision = BrowserMetadata.shared.revision
        context.coordinator.reloadIfNeeded()
        context.coordinator.redrawMetadataIfNeeded(metadataRevision)
        context.coordinator.syncSelection()
        context.coordinator.syncSortIndicator()
        context.coordinator.beginRenameIfNeeded()
        context.coordinator.redrawIfCutChanged(CutBoardStore.shared.version)
        if let window = context.coordinator.outlineView?.window as? BrowserWindow, let view = context.coordinator.outlineView {
            window.focusFileView(view, paneIsActive: model.activePane == pane.id)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(pane: pane, model: model) }

    // MARK: - Outline node

    /// One row of the outline: a real file/folder entry, or a group header (`isGroupItem`, unselectable, arrow keys
    /// skip it — contract §3). A folder node's children are loaded lazily and cached per-path by the coordinator;
    /// Hashable/Equatable by identity (path for an entry, title for a header) so `NSOutlineView`'s item identity
    /// (`itemForPersistentObject`, `isExpandable` memoization) stays stable across reloads of the SAME listing.
    enum Node: Hashable {
        case entry(DirectoryEntry)
        case header(String)
        case pinnedHeader

        var entry: DirectoryEntry? {
            if case .entry(let e) = self { return e }
            return nil
        }

        static func == (lhs: Node, rhs: Node) -> Bool {
            switch (lhs, rhs) {
            case (.entry(let a), .entry(let b)): return a.path == b.path
            case (.header(let a), .header(let b)): return a == b
            case (.pinnedHeader, .pinnedHeader): return true
            default: return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .entry(let e): hasher.combine(0); hasher.combine(e.path)
            case .header(let t): hasher.combine(1); hasher.combine(t)
            case .pinnedHeader: hasher.combine(2)
            }
        }
    }

    /// A plain `NSView`'s `tag` is get-only (returns -1 unless a subclass overrides it) — this tiny subclass is the
    /// Finder-tag colour dot in the Name cell, found later by `viewWithTag(_:)` the same way the cloud badge
    /// `NSImageView` already is (which inherits a settable `tag` from `NSControl`; a plain `NSView` does not).
    final class TagDotView: NSView {
        private var storedTag = 0
        override var tag: Int {
            get { storedTag }
            set { storedTag = newValue }
        }
    }

    /// These views live inside the Name cell, so the outline keeps ownership of mouseDown, drag and rename.
    private struct PropertyChips: View {
        let options: [PropertyOption]
        var body: some View {
            HStack(spacing: XFinderTokens.Space.tight) {
                ForEach(options) { option in
                    Text(option.title)
                        .font(XFinderTokens.Font.caption.weight(.semibold))
                        .foregroundStyle(XFinderTokens.PropertyTint.color(option.color))
                        .padding(.horizontal, XFinderTokens.Space.tight)
                        .padding(.vertical, XFinderTokens.Space.hairline)
                        .background(XFinderTokens.PropertyTint.color(option.color).opacity(XFinderTokens.PropertyTint.chipFill),
                                    in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge))
                }
            }
            .fixedSize()
        }
    }

    private final class ChipStrip: NSHostingView<PropertyChips> {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class TreeNameCell: NSTableCellView {
        let emojiLabel = NSTextField(labelWithString: "")
        let nicknameLabel = NSTextField(labelWithString: "")
        let folderArrow = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        let actions = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil) ?? NSImage(),
                               target: nil, action: nil)
        private let chips = ChipStrip(rootView: PropertyChips(options: []))
        private var tracking: NSTrackingArea?
        var onActions: (() -> NSMenu)?
        private var hovering = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            let icon = NSImageView()
            icon.imageScaling = .scaleProportionallyDown
            imageView = icon
            let name = NSTextField(labelWithString: "")
            name.lineBreakMode = .byTruncatingMiddle
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField = name
            nicknameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            nicknameLabel.textColor = .secondaryLabelColor
            nicknameLabel.lineBreakMode = .byTruncatingMiddle
            nicknameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            emojiLabel.alignment = .center
            folderArrow.contentTintColor = .secondaryLabelColor
            actions.isBordered = false
            actions.target = self
            actions.action = #selector(showActions)
            actions.toolTip = L10n.t("Thao tác trên mục đang chọn")
            actions.setAccessibilityLabel(L10n.t("Thao tác trên mục đang chọn"))
            let labels = NSStackView(views: [name, nicknameLabel])
            labels.spacing = XFinderTokens.Space.tight
            labels.alignment = .centerY
            let content = NSStackView(views: [icon, labels, chips, actions, folderArrow])
            content.spacing = XFinderTokens.Space.tight
            content.alignment = .centerY
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            emojiLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(emojiLabel)
            let badge = NSImageView()
            badge.tag = Coordinator.cloudBadgeTag
            badge.imageScaling = .scaleProportionallyDown
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            let tagDot = TagDotView()
            tagDot.tag = Coordinator.tagDotTag
            tagDot.wantsLayer = true
            tagDot.layer?.cornerRadius = XFinderTokens.Space.tight / 2
            tagDot.translatesAutoresizingMaskIntoConstraints = false
            labels.addArrangedSubview(tagDot)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: XFinderTokens.Space.hairline),
                content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -XFinderTokens.Space.tight),
                content.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: XFinderTokens.Space.row + XFinderTokens.Space.tight),
                icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
                emojiLabel.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
                emojiLabel.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
                badge.trailingAnchor.constraint(equalTo: icon.trailingAnchor),
                badge.bottomAnchor.constraint(equalTo: icon.bottomAnchor),
                badge.widthAnchor.constraint(equalToConstant: XFinderTokens.Space.row),
                badge.heightAnchor.constraint(equalTo: badge.widthAnchor),
                actions.widthAnchor.constraint(equalToConstant: XFinderTokens.Space.page),
                folderArrow.widthAnchor.constraint(equalToConstant: XFinderTokens.Space.row),
                tagDot.widthAnchor.constraint(equalToConstant: XFinderTokens.Space.tight),
                tagDot.heightAnchor.constraint(equalTo: tagDot.widthAnchor),
            ])
            actions.alphaValue = 0
        }
        required init?(coder: NSCoder) { nil }

        func setOptions(_ options: [PropertyOption]) {
            chips.rootView = PropertyChips(options: options)
            chips.isHidden = options.isEmpty
        }
        override func updateTrackingAreas() {
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            tracking = area
            addTrackingArea(area)
            super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) { hovering = true; actions.alphaValue = 1 }
        override func mouseExited(with event: NSEvent) { hovering = false; actions.alphaValue = 0 }
        @objc private func showActions() {
            guard let menu = onActions?() else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: actions.bounds.minX, y: actions.bounds.maxY), in: actions)
            actions.alphaValue = hovering ? 1 : 0
        }
    }

    final class PinnedRowView: NSTableRowView {
        var pinned = false
        var first = false
        var last = false
        override func drawBackground(in dirtyRect: NSRect) {
            guard pinned else { super.drawBackground(in: dirtyRect); return }
            let card = bounds.insetBy(dx: XFinderTokens.Space.hairline, dy: 0)
            let radius = XFinderTokens.Settings.cardRadius
            NSColor(XFinderTokens.Fill.inset).setFill()
            NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius).fill()
            // Square just the shared edge: adjacent rows then form one card, with corners only at its ends.
            if !first {
                NSRect(x: card.minX, y: isFlipped ? card.minY : card.midY,
                       width: card.width, height: card.height / 2).fill()
            }
            if !last {
                NSRect(x: card.minX, y: isFlipped ? card.midY : card.minY,
                       width: card.width, height: card.height / 2).fill()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {

        var pane: PaneState
        var model: BrowserWindowModel
        weak var outlineView: NSOutlineView?
        /// Spring-loaded folders (system timing; off when System Settings turns it off) — integration audit 2026-10-25.
        private let springLoader: DragDropCoordinator.SpringLoader = DragDropCoordinator.SpringLoader()
        private var lastCutVersion: Int = -1

        /// A ⌘X cut started or ended: redraw the visible rows so cut items fade / un-fade.
        func redrawIfCutChanged(_ version: Int) {
            guard version != lastCutVersion else { return }
            lastCutVersion = version
            guard let outlineView else { return }
            let visible: NSRange = outlineView.rows(in: outlineView.visibleRect)
            guard visible.length > 0 else { return }
            outlineView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                                   columnIndexes: IndexSet(integersIn: 0..<outlineView.numberOfColumns))
        }

        /// `PaneState.listingRevision` last applied — one Int compare per `updateNSView` (the old count/first/last
        /// fingerprint missed a change in the middle of the list, e.g. a rename that keeps the sort position).
        private var lastMetadataRevision = -1
        private var lastPins: [String] = []
        private var pinnedPaths: [String] = []
        private var pinnedSet: Set<String> = []
        private var selfEntry: DirectoryEntry?
        private var lastPath: String?
        private var isTreeMode: Bool { activeColumns() == [.name] && pane.search == nil }
        private var lastRevision = -1
        private var lastUseGroups = false
        private var isSyncingSelection = false
        private var typeSelect = EntryRules.TypeSelect()
        private var renamingPath: String?
        private let cloudCache: CloudFactsCache = CloudFactsCache()
        private var lastSyncedSelection: Set<String> = []
        private var lastColumns: [ListColumn] = []
        private var originalIntercellSpacing: NSSize?
        private var lastShowingParentFolderColumn = false

        /// Per-folder-path state for every row that has ever been expanded: its off-main listing (sorted the same
        /// way as the top level), a `DirectoryWatcher` so a change inside it refreshes without the user re-opening
        /// it, and whether a load is currently in flight (so a rapid expand/collapse/expand does not double-fetch).
        private final class ExpandedFolder {
            var children: [DirectoryEntry] = []
            var loaded = false
            var loading = false
            var watcher: DirectoryWatcher?
        }
        private var expanded: [String: ExpandedFolder] = [:]

        init(pane: PaneState, model: BrowserWindowModel) {
            self.pane = pane
            self.model = model
            // Primed before `makeNSView` assigns `dataSource` — AppKit can query `numberOfChildrenOfItem`/`child`
            // synchronously as soon as that assignment happens, ahead of this type's own `reloadIfNeeded()`.
            self.cachedRootNodes = pane.entries.map(Node.entry)
        }

        // No explicit `deinit` here: `expanded`'s `ExpandedFolder`s release their `DirectoryWatcher` along with the
        // dictionary when this coordinator goes away, and `DirectoryWatcher.deinit` already cancels its own
        // `DispatchSourceFileSystemObject` (contract ca hỏng: "không rò DirectoryWatcher" — the watcher's own
        // teardown, not this type's, is what closes the fd). A `deinit` here reading `expanded` would need to hop
        // back to the main actor from a nonisolated context for no benefit over just letting ARC do it.

        /// `rootNodes()` result, rebuilt only by `reloadIfNeeded()` (on the same fingerprint it already tracks).
        /// `outlineView(_:numberOfChildrenOfItem:)`/`child(index:ofItem:)` call this once PER ROW during a reload —
        /// rebuilding the array (and, with groups on, re-running `L10n.t` per header) on every single one of those
        /// calls would turn a 100 000-row reload quadratic (contract §5: "mở List ≤ 150 ms / 100 000 hàng").
        private var cachedRootNodes: [Node] = []

        // MARK: - Columns

        /// `NSUserInterfaceItemIdentifier` namespace for the outline's own disclosure/name column vs. the plain
        /// value columns the contract lets the user toggle (Date Modified, Size, Kind, …).
        private static func identifier(for column: ListColumn) -> NSUserInterfaceItemIdentifier {
            NSUserInterfaceItemIdentifier(column.rawValue)
        }

        /// XF-T30 W5b — "Nơi chứa" (parent folder), shown only while searching (contract §"Một đường tìm": "cột 'Nơi
        /// chứa' ... trong List khi đang tìm"). A synthetic column OUTSIDE `ListColumn` (that enum is a different
        /// builder's file, `FolderViewOptions.swift`, and is also the user-toggleable set `FolderViewPrefs` persists
        /// — this column is neither user-toggleable nor ever saved to a folder's remembered columns) rather than a
        /// case added there.
        private static let parentFolderIdentifier = NSUserInterfaceItemIdentifier("xfSearchParentFolder")

        private func activeColumns() -> [ListColumn] {
            pane.folderPrefs?.columns ?? FolderViewPrefs.defaultColumns
        }

        /// Rebuilds the table columns from `activeColumns()` (+ "Nơi chứa" while searching) when they differ from
        /// what is on screen — called from `makeNSView` and again whenever the header's toggle menu, `FolderViewPrefs`,
        /// or `pane.search` starting/ending changes the set, never on every `updateNSView` (contract: "no O(n)/layout
        /// work per frame" applies to column churn too).
        func rebuildColumns(in outlineView: NSOutlineView) {
            if originalIntercellSpacing == nil { originalIntercellSpacing = outlineView.intercellSpacing }
            if var spacing = originalIntercellSpacing {
                // No white gap between the row backgrounds that form the pinned card.
                if isTreeMode || !pinnedPaths.isEmpty { spacing.height = 0 }
                if outlineView.intercellSpacing != spacing { outlineView.intercellSpacing = spacing }
            }
            let wanted = activeColumns()
            let searching = pane.search != nil
            guard wanted != lastColumns || searching != lastShowingParentFolderColumn
                    || outlineView.tableColumns.count != wanted.count + (searching ? 1 : 0)
            else { return }
            lastColumns = wanted
            lastShowingParentFolderColumn = searching
            outlineView.headerView = isTreeMode ? nil : NSTableHeaderView()
            outlineView.headerView?.menu = makeHeaderMenu()
            outlineView.rowHeight = isTreeMode ? XFinderTokens.Settings.rowMinHeight : FileListView.rowHeight
            outlineView.usesAlternatingRowBackgroundColors = !isTreeMode
            outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<outlineView.numberOfRows))
            let existing = Dictionary(uniqueKeysWithValues: outlineView.tableColumns.map { ($0.identifier, $0) })
            for column in outlineView.tableColumns { outlineView.removeTableColumn(column) }
            for (index, column) in wanted.enumerated() {
                let identifier = Self.identifier(for: column)
                let tableColumn = existing[identifier] ?? Self.makeTableColumn(column)
                outlineView.addTableColumn(tableColumn)
                if index == 0 { outlineView.outlineTableColumn = tableColumn }
            }
            if searching {
                let parentColumn = existing[Self.parentFolderIdentifier] ?? Self.makeParentFolderColumn()
                outlineView.addTableColumn(parentColumn)
            }
        }

        private static func makeTableColumn(_ column: ListColumn) -> NSTableColumn {
            let tableColumn = NSTableColumn(identifier: identifier(for: column))
            tableColumn.title = L10n.t(column.titleKey)
            tableColumn.minWidth = column.minWidth
            tableColumn.width = column.defaultWidth
            if let sortKey = column.sortKey {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: sortKey.rawValue, ascending: true)
            }
            return tableColumn
        }

        private static func makeParentFolderColumn() -> NSTableColumn {
            let tableColumn = NSTableColumn(identifier: parentFolderIdentifier)
            tableColumn.title = L10n.t("Nơi chứa")
            tableColumn.minWidth = 120
            tableColumn.width = 200
            return tableColumn
        }

        func reloadColumnsIfNeeded() {
            guard let outlineView else { return }
            rebuildColumns(in: outlineView)
        }

        func reloadIfNeeded() {
            let revision = pane.listingRevision
            let useGroups = pane.useGroups
            let pins = BrowserMetadata.shared.pins(in: pane.path)
            let pinsChanged = pins != lastPins
            // A pin reorder must not destroy an active field editor. It will be applied when editing ends.
            let applyPins = pinsChanged && renamingPath == nil
            guard revision != lastRevision || useGroups != lastUseGroups || applyPins || lastPath != pane.path else {
                reloadColumnsIfNeeded()
                return
            }
            let pathChanged = lastPath != pane.path
            lastPath = pane.path
            lastPins = pins
            lastRevision = revision
            let newNodes = rebuildRootNodes()
            cloudCache.removeAll()
            defer { reloadColumnsIfNeeded() }

            // Same folder refreshed (watcher, ⌘R, an operation): patch the rows that changed and keep everything else —
            // selection, scroll, disclosure, a rename in progress, the click in flight. Groups and search results are
            // header/row mixes that still take the full reload; so does a resort (kept rows change order).
            if let outlineView, !pathChanged, !useGroups, !lastUseGroups, pane.search == nil, Self.canPatch(from: cachedRootNodes, to: newNodes) {
                let plan = ListingDiff.plan(old: cachedRootNodes.map(Self.identity), new: newNodes.map(Self.identity))
                if ListingDiff.shouldPatch(plan), case .patch(let removed, let inserted) = plan {
                    for index in removed {
                        guard let gone = cachedRootNodes[index].entry else { continue }
                        expanded[gone.path]?.watcher?.cancel()
                        expanded[gone.path] = nil
                        // The row under an inline rename is leaving: end the rename without committing, otherwise the
                        // field editor outlives its row.
                        if gone.path == renamingPath { endRename(commit: false, field: nil) }
                    }
                    cachedRootNodes = newNodes
                    if !removed.isEmpty || !inserted.isEmpty {
                        outlineView.beginUpdates()
                        outlineView.removeItems(at: removed, inParent: nil, withAnimation: [])
                        outlineView.insertItems(at: inserted, inParent: nil, withAnimation: [])
                        outlineView.endUpdates()
                    }
                    // Kept rows may show new metadata (size, date, cloud state): redraw what is on screen — except the
                    // row being renamed (reloading it would replace the field editor; FileOctopus removes `editedRow`
                    // from the same set, decompiled 2026-10-26).
                    let visible: NSRange = outlineView.rows(in: outlineView.visibleRect)
                    if visible.length > 0 {
                        var rows = IndexSet(integersIn: visible.location..<(visible.location + visible.length))
                        if outlineView.editedRow >= 0 { rows.remove(outlineView.editedRow) }
                        if !rows.isEmpty {
                            outlineView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<outlineView.numberOfColumns))
                        }
                    }
                    lastUseGroups = useGroups
                    return
                }
            }
            lastUseGroups = useGroups
            lastSyncedSelection = []
            stopWatchingAll()
            cachedRootNodes = newNodes
            outlineView?.reloadData()
        }

        /// Row identity for `ListingDiff`: an entry's path; a header its title behind a NUL no path can contain.
        private static func identity(_ node: Node) -> String {
            switch node {
            case .entry(let e): return e.path
            case .header(let t): return "\u{0}" + t
            case .pinnedHeader: return "\u{0}pinned"
            }
        }

        /// Entry rows and the unique pinned header are patchable; user group headers retain the full reload path.
        private static func canPatch(from old: [Node], to new: [Node]) -> Bool {
            func patchable(_ node: Node) -> Bool {
                if case .pinnedHeader = node { return true }
                return node.entry != nil
            }
            return old.allSatisfy(patchable) && new.allSatisfy(patchable)
        }

        func syncSortIndicator() {
            guard let outlineView else { return }
            for column in outlineView.tableColumns {
                guard let key = ListColumn(rawValue: column.identifier.rawValue)?.sortKey else { continue }
                if key == pane.sort.key {
                    outlineView.setIndicatorImage(
                        NSImage(named: pane.sort.ascending ? NSImage.Name("NSAscendingSortIndicator")
                                                            : NSImage.Name("NSDescendingSortIndicator")),
                        in: column)
                } else {
                    outlineView.setIndicatorImage(nil, in: column)
                }
            }
        }

        // MARK: - Root items (flat list or grouped sections)

        /// Top-level rows in display order: either `pane.entries` directly, or — with `pane.useGroups` — a header
        /// node ahead of each non-empty `EntrySection` (contract §3: "nhóm rỗng không hiện", already guaranteed by
        /// `GroupBy.sections`). `pane.sections` is only meaningful when `useGroups` is on; the stub/implementation
        /// still rebuilds it on every `applyEntries` regardless, so this reads `pane.entries` directly when groups
        /// are off instead of trusting `pane.sections` to degenerate to one section (keeps this view correct even
        /// before/while the model-side grouping lands).
        private func rootNodes() -> [Node] { cachedRootNodes }

        private func rebuildRootNodes() -> [Node] {
            let split = PinRules.split(pane.entries, folder: pane.path, pins: BrowserMetadata.shared.pins(in: pane.path))
            var pinned = split.pinned
            selfEntry = nil
            if split.pinsFolderItself, pane.search == nil {
                let entry = DirectoryEntry(name: pane.path == "/" ? "/" : (pane.path as NSString).lastPathComponent, path: pane.path,
                                           kind: .directory, isPackage: false, isHidden: false, size: -1,
                                           modified: .distantPast, created: .distantPast, volumeID: 0)
                selfEntry = entry
                pinned.removeAll { $0.path == pane.path }
                pinned.insert(entry, at: 0)
            }
            pinnedPaths = pinned.map(\.path)
            pinnedSet = Set(pinnedPaths)
            var nodes: [Node] = pinned.isEmpty ? [] : [.pinnedHeader] + pinned.map(Node.entry)
            if !pane.useGroups {
                return nodes + split.rest.filter { !pinnedSet.contains($0.path) }.map(Node.entry)
            }
            for section in pane.sections {
                let entries = section.entries.filter { !pinnedSet.contains($0.path) }
                guard !entries.isEmpty else { continue }
                nodes.append(.header(sectionHeaderTitle(section)))
                nodes.append(contentsOf: entries.map(Node.entry))
            }
            return nodes.isEmpty ? pane.entries.map(Node.entry) : nodes
        }

        func redrawMetadataIfNeeded(_ revision: Int) {
            guard revision != lastMetadataRevision else { return }
            lastMetadataRevision = revision
            guard let outlineView else { return }
            let visible = outlineView.rows(in: outlineView.visibleRect)
            guard visible.location != NSNotFound, visible.length > 0 else { return }
            var rows = IndexSet(integersIn: visible.location..<(visible.location + visible.length))
            if outlineView.editedRow >= 0 { rows.remove(outlineView.editedRow) }
            if let renamingPath, let entry = findEntry(path: renamingPath) {
                let row = outlineView.row(forItem: Node.entry(entry))
                if row >= 0 { rows.remove(row) }
            }
            outlineView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<outlineView.numberOfColumns))
            for index in rows {
                guard let row = outlineView.rowView(atRow: index, makeIfNecessary: false) as? PinnedRowView,
                      let entry = (outlineView.item(atRow: index) as? Node)?.entry else { continue }
                row.pinned = pinnedSet.contains(entry.path)
                row.first = entry.path == pinnedPaths.first
                row.last = entry.path == pinnedPaths.last
                row.needsDisplay = true
            }
        }

        private func sectionHeaderTitle(_ section: EntrySection) -> String {
            let title = section.titleKey.isEmpty ? "" : L10n.t(section.titleKey)
            guard let arg = section.titleArg, !arg.isEmpty else { return title }
            return title.isEmpty ? arg : "\(title) \(arg)"
        }

        /// The `EntrySection` a header node belongs to (by its rendered title) — used to find that section's
        /// entries for "skip group headers" arrow-key navigation.
        private func section(forHeaderTitle title: String) -> EntrySection? {
            pane.sections.first { sectionHeaderTitle($0) == title }
        }

        // MARK: - Children (lazy, off-main, watched)

        private func folderState(for path: String) -> ExpandedFolder {
            if let existing = expanded[path] { return existing }
            let folder = ExpandedFolder()
            expanded[path] = folder
            return folder
        }

        /// Starts (if not already running) an off-main listing of `path`'s children, sorted the same way as the top
        /// level, and installs a watcher that reloads them on change. Safe to call repeatedly (e.g. once per
        /// `outlineView(_:isItemExpandable:)` call) — a second call while one is already loading or already loaded
        /// is a no-op.
        private func ensureChildrenLoaded(_ path: String) {
            let folder = folderState(for: path)
            guard !folder.loaded, !folder.loading else { return }
            folder.loading = true
            Task { [weak self] in
                let result = await DirectoryReader.list(path, timeout: 5)
                await MainActor.run {
                    guard let self else { return }
                    self.applyLoadedChildren(result, to: path)
                }
            }
            if folder.watcher == nil {
                folder.watcher = DirectoryWatcher(
                    path: path,
                    onChange: { [weak self] in self?.reloadExpandedFolder(path) },
                    onGone: { [weak self] in self?.collapseGoneFolder(path) }
                )
            }
        }

        private func applyLoadedChildren(_ result: Result<[DirectoryEntry], DirectoryReadError>, to path: String) {
            guard let folder = expanded[path] else { return }
            folder.loading = false
            switch result {
            case .success(let entries):
                let visible = EntryRules.visible(entries, showHidden: pane.showHidden)
                folder.children = EntryRules.sorted(visible, by: pane.sort, foldersFirst: pane.foldersFirst) {
                    FileIconCache.shared.kindName(for: $0)
                }
            case .failure:
                folder.children = []
            }
            BrowserMetadata.shared.load(folder: path)
            folder.loaded = true
            guard let outlineView, let parentEntry = findEntry(path: path) else { return }
            let wasExpanded = outlineView.isItemExpanded(Node.entry(parentEntry))
            outlineView.reloadItem(Node.entry(parentEntry), reloadChildren: true)
            if wasExpanded { outlineView.expandItem(Node.entry(parentEntry)) }
        }

        private func reloadExpandedFolder(_ path: String) {
            guard let folder = expanded[path] else { return }
            folder.loaded = false
            ensureChildrenLoaded(path)
        }

        /// The watched folder itself vanished (deleted/renamed out from under an open disclosure triangle): drop
        /// its state and collapse it — its parent's own watcher/reload will show it gone on the next listing.
        private func collapseGoneFolder(_ path: String) {
            expanded[path]?.watcher?.cancel()
            expanded[path] = nil
            guard let outlineView, let entry = findEntry(path: path) else { return }
            outlineView.collapseItem(Node.entry(entry))
        }

        /// Finds a `DirectoryEntry` for `path` among every folder this coordinator currently knows about (top level
        /// plus every expanded folder's children) — needed because `reloadItem`/`collapseItem` want the actual
        /// `Node` value, not just its path.
        private func findEntry(path: String) -> DirectoryEntry? {
            if let selfEntry, selfEntry.path == path { return selfEntry }
            if let hit = pane.entries.first(where: { $0.path == path }) { return hit }
            for folder in expanded.values {
                if let hit = folder.children.first(where: { $0.path == path }) { return hit }
            }
            for section in pane.sections {
                if let hit = section.entries.first(where: { $0.path == path }) { return hit }
            }
            return nil
        }

        /// Cancels the watcher and drops the cached listing for a folder that just collapsed, AND every
        /// already-expanded descendant underneath it (contract ca hỏng: "không rò DirectoryWatcher"). Collapsing a
        /// folder in `NSOutlineView` only fires `outlineViewItemDidCollapse` for the item the user actually
        /// collapsed — a subfolder expanded earlier underneath it (e.g. A then A/B both opened, then A collapsed)
        /// never gets its own collapse notification, so without walking `children` here its watcher would keep
        /// firing forever on rows no longer visible. A later re-expand starts a fresh load at every level.
        private func stopWatching(_ path: String) {
            guard let folder = expanded[path] else { return }
            for child in folder.children where child.isFolderLike {
                stopWatching(child.path)
            }
            folder.watcher?.cancel()
            expanded.removeValue(forKey: path)
        }

        /// Cancels every watcher this coordinator currently owns — used when the pane navigates to a different
        /// folder entirely (contract ca hỏng: "không rò DirectoryWatcher"). `reloadData()` resets every disclosure
        /// state in the outline, so any folder that was expanded under the OLD top-level listing must have its
        /// watcher torn down here; nothing else ever calls `outlineViewItemDidCollapse` for it once its row is gone.
        private func stopWatchingAll() {
            for folder in expanded.values { folder.watcher?.cancel() }
            expanded.removeAll()
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item else { return rootNodes().count }
            guard let node = item as? Node, let entry = node.entry, entry.isFolderLike else { return 0 }
            ensureChildrenLoaded(entry.path)
            return folderState(for: entry.path).children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item else { return rootNodes()[index] }
            guard let node = item as? Node, let entry = node.entry else { return Node.header("") }
            return Node.entry(folderState(for: entry.path).children[index])
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? Node, let entry = node.entry else { return false }
            // Packages are leaves (contract: "packages are leaves") even though they are directories on disk.
            return entry.isFolderLike && entry.path != pane.path
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = outlineView.sortDescriptors.first,
                  let key = descriptor.key, let sortKey = SortKey(rawValue: key) else { return }
            pane.sort = SortOrder(key: sortKey, ascending: descriptor.ascending)
            // Every already-loaded expanded folder was sorted with the OLD order baked in; re-sort each in place
            // (no re-read of disk needed — `EntryRules.sorted` is pure) so a deep expansion does not silently keep
            // showing the stale order until the user collapses and re-expands it.
            for (path, folder) in expanded where folder.loaded {
                folder.children = EntryRules.sorted(folder.children, by: pane.sort, foldersFirst: pane.foldersFirst) {
                    FileIconCache.shared.kindName(for: $0)
                }
                if let entry = findEntry(path: path) {
                    outlineView.reloadItem(Node.entry(entry), reloadChildren: true)
                }
            }
        }

        // MARK: - NSOutlineViewDelegate (rows + cells)

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            if node.entry == nil { return true }
            return false
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            if node.entry == nil { return false }   // group header rows: unselectable (contract §3)
            return true
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let row = PinnedRowView()
            if let entry = (item as? Node)?.entry {
                row.pinned = pinnedSet.contains(entry.path)
                row.first = entry.path == pinnedPaths.first
                row.last = entry.path == pinnedPaths.last
            }
            return row
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let node = item as? Node, node.entry == nil else { return isTreeMode ? XFinderTokens.Settings.rowMinHeight : FileListView.rowHeight }
            return FileListView.groupRowHeight
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            if node.entry == nil {
                let title: String
                if case .header(let value) = node { title = value } else { title = L10n.t("Đã ghim") }
                // Only the outline (name) column draws the header's title; the other columns show an empty cell so
                // the row still spans the full width without a title fighting the row-spanning drawing.
                guard tableColumn == outlineView.outlineTableColumn || tableColumn == outlineView.tableColumns.first
                else { return NSTableCellView() }
                return Self.makeHeaderCell(title: title)
            }
            guard let tableColumn, let entry = node.entry else { return nil }
            // The self pin is synthetic: never present its placeholder dates/size as real filesystem metadata.
            if entry.path == selfEntry?.path, tableColumn.identifier != Self.identifier(for: .name) {
                return NSTableCellView()
            }
            if tableColumn.identifier == Self.parentFolderIdentifier {
                return parentFolderCell(for: entry, in: outlineView)
            }
            guard let column = ListColumn(rawValue: tableColumn.identifier.rawValue) else { return nil }
            let identifier = column == .name && isTreeMode ? NSUserInterfaceItemIdentifier("xfTreeName") : tableColumn.identifier
            let cell: NSTableCellView
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                if column == .name && isTreeMode {
                    cell = TreeNameCell()
                    cell.identifier = identifier
                } else {
                    cell = Self.makeCell(column: column, identifier: identifier)
                }
            }
            configure(cell: cell, column: column, entry: entry)
            return cell
        }

        /// XF-T30 W5b — "Nơi chứa" cell: the result's parent folder, truncated from the middle (contract rule 14:
        /// every filename-bearing row needs `.truncationMode(.middle)`) — a search hit can live anywhere on disk, so
        /// this is the one place in List view where the shown text is a whole path rather than a single name.
        private func parentFolderCell(for entry: DirectoryEntry, in outlineView: NSOutlineView) -> NSTableCellView {
            let cell: NSTableCellView
            if let reused = outlineView.makeView(withIdentifier: Self.parentFolderIdentifier, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = Self.parentFolderIdentifier
                let text = NSTextField(labelWithString: "")
                text.font = .systemFont(ofSize: NSFont.systemFontSize)
                text.lineBreakMode = .byTruncatingMiddle
                text.translatesAutoresizingMaskIntoConstraints = false
                cell.textField = text
                cell.addSubview(text)
                NSLayoutConstraint.activate([
                    text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = (entry.path as NSString).deletingLastPathComponent
            return cell
        }

        private static func makeHeaderCell(title: String) -> NSTableCellView {
            let cell = NSTableCellView()
            let text = NSTextField(labelWithString: title)
            text.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            text.textColor = .secondaryLabelColor
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = text
            cell.addSubview(text)
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private static func makeCell(column: ListColumn, identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
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
                let tagDot = TagDotView()
                tagDot.tag = Self.tagDotTag
                tagDot.wantsLayer = true
                tagDot.layer?.cornerRadius = 3
                tagDot.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(tagDot)
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
                    tagDot.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 4),
                    tagDot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    tagDot.widthAnchor.constraint(equalToConstant: 6),
                    tagDot.heightAnchor.constraint(equalToConstant: 6),
                    text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -12),
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

        /// Fixed tags for the small overlays on the Name column: the cloud badge over the icon, and the Finder-tag
        /// colour dot after the name (contract §3: "chấm màu thẻ ... ở cả 4 kiểu xem").
        static let cloudBadgeTag = 9001
        static let tagDotTag = 9002

        private func configure(cell: NSTableCellView, column: ListColumn, entry: DirectoryEntry) {
            switch column {
            case .name:
                cell.textField?.attributedStringValue = nameCellText(for: entry)
                cell.imageView?.alphaValue = model.isCut(entry.path) ? XFinderTokens.Emphasis.cutItemAlpha : 1
                cell.imageView?.image = FileIconCache.shared.icon(for: entry)
                if let tree = cell as? TreeNameCell {
                    let metadata = BrowserMetadata.shared
                    let emoji = entry.isFolderLike ? metadata.emoji(for: entry.path) : nil
                    tree.emojiLabel.stringValue = emoji ?? ""
                    tree.emojiLabel.alphaValue = model.isCut(entry.path) ? XFinderTokens.Emphasis.cutItemAlpha : 1
                    tree.imageView?.isHidden = emoji != nil
                    tree.folderArrow.isHidden = !entry.isFolderLike
                    if entry.path == selfEntry?.path {
                        tree.nicknameLabel.stringValue = L10n.t("Thư mục này")
                    } else if let nickname = metadata.nickname(for: entry.path) {
                        tree.nicknameLabel.stringValue = L10n.t("còn gọi là ") + nickname
                    } else {
                        tree.nicknameLabel.stringValue = ""
                    }
                    tree.nicknameLabel.isHidden = tree.nicknameLabel.stringValue.isEmpty
                    let folder = (entry.path as NSString).deletingLastPathComponent
                    let properties = metadata.visibleProperties(in: entry.path == selfEntry?.path ? pane.path : folder)
                    tree.setOptions(properties.compactMap { metadata.option(for: entry.path, property: $0.id) })
                    tree.onActions = { [weak self] in
                        guard let self else { return NSMenu() }
                        self.model.focus(self.pane.id)
                        return RowActionsMenu.menu(for: [entry], pane: self.pane, model: self.model)
                    }
                }
                let badge = cloudBadgeSymbol(for: cloudFacts(for: entry.path))
                (cell.viewWithTag(Self.cloudBadgeTag) as? NSImageView)?.image = badge
                let dot = cell.viewWithTag(Self.tagDotTag)
                if let color = primaryTagColor(for: entry) {
                    dot?.isHidden = false
                    dot?.layer?.backgroundColor = Self.nsColor(for: color).cgColor
                } else {
                    dot?.isHidden = true
                }
            case .dateModified:
                cell.textField?.stringValue = Self.dateText(entry.modified)
            case .dateCreated:
                cell.textField?.stringValue = Self.dateText(entry.created)
            case .dateAdded:
                cell.textField?.stringValue = entry.added.map(Self.dateText) ?? ""
            case .dateLastOpened:
                cell.textField?.stringValue = entry.lastOpened.map(Self.dateText) ?? ""
            case .size:
                cell.textField?.stringValue = entry.size >= 0 ? Self.sizeText(entry.size) : ""
            case .kind:
                cell.textField?.stringValue = FileIconCache.shared.kindName(for: entry)
            case .tags:
                cell.textField?.stringValue = (entry.tags ?? []).joined(separator: ", ")
            }
        }

        /// XF-T30 W5b — while searching, the Name cell gets a grayed suffix: the source label (tên / Spotlight / nội
        /// dung — `DirectoryEntry` itself has no field for this, so it comes from `PaneSearchState.sources`/
        /// `snippets`, see `BrowserWindowModel.applySearchResults`) and, for a content-index hit, its snippet.
        /// Plain `entry.name` outside a search, same as before this feature existed.
        @MainActor private static let middleTruncating: NSParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingMiddle
            return style
        }()

        private func nameCellText(for entry: DirectoryEntry) -> NSAttributedString {
            let shown: String = BrowserWindowModel.displayName(for: entry, showAllExtensions: BrowserSettings.showAllExtensions)
            let colour: NSColor = model.isCut(entry.path)
                ? NSColor.labelColor.withAlphaComponent(XFinderTokens.Emphasis.cutItemAlpha) : NSColor.labelColor
            // An attributed value replaces the field's own `lineBreakMode`: without a paragraph style a long name wrapped
            // onto a second line drawn over the row above (owner screenshot 2026-10-26, "…2025.xl" / "sx").
            let name = NSMutableAttributedString(string: shown, attributes: [.foregroundColor: colour,
                                                                              .paragraphStyle: Self.middleTruncating])
            if entry.path == selfEntry?.path, !isTreeMode {
                name.append(NSAttributedString(string: "  " + L10n.t("Thư mục này"),
                                               attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                                                            .paragraphStyle: Self.middleTruncating]))
            }
            guard let search = pane.search else { return name }
            var suffixParts: [String] = []
            if let sources = search.sources[entry.path], !sources.isEmpty {
                suffixParts.append(sourceLabel(sources))
            }
            if let snippet = search.snippets[entry.path], !snippet.isEmpty {
                suffixParts.append(snippet)
            }
            guard !suffixParts.isEmpty else { return name }
            let suffix = NSAttributedString(
                string: "  —  " + suffixParts.joined(separator: " · "),
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                             .paragraphStyle: Self.middleTruncating]
            )
            name.append(suffix)
            return name
        }

        /// Vietnamese label for a result's source set (contract: "nhãn nguồn (tên / Spotlight / nội dung)") — a hit
        /// found by more than one source shows every label it matched under, joined, same ordering as
        /// `SearchCoordinator.Source`'s declaration (name, Spotlight, content).
        private func sourceLabel(_ sources: Set<SearchCoordinator.Source>) -> String {
            var labels: [String] = []
            if sources.contains(.name) { labels.append(L10n.t("tên")) }
            if sources.contains(.spotlight) { labels.append(L10n.t("Spotlight")) }
            if sources.contains(.content) { labels.append(L10n.t("nội dung")) }
            return labels.joined(separator: ", ")
        }

        /// The first Finder tag's colour (dot shown is the primary tag, same as Finder's own single-dot summary in
        /// list rows with multiple tags); nil when the entry has no tags or they have not been read yet.
        private func primaryTagColor(for entry: DirectoryEntry) -> TagColor? {
            guard let first = entry.tags?.first else { return nil }
            return FinderTags.parse(first).color
        }

        private static func nsColor(for color: TagColor) -> NSColor {
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

        /// One formatter on the main actor (cells are configured there). A fresh `DateFormatter` per cell was 170 ms of
        /// one scroll's 3,3 s main-thread stall (sampled 2026-10-26) — creating one loads locale data every time.
        @MainActor private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter
        }()

        @MainActor private static func dateText(_ date: Date) -> String {
            dateFormatter.string(from: date)
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

        // MARK: - Header right-click menu (toggle columns + Right Size)

        func makeHeaderMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        private func populateHeaderMenu(_ menu: NSMenu) {
            menu.removeAllItems()
            for column in ListColumn.allCases {
                let item = NSMenuItem(title: L10n.t(column.titleKey), action: #selector(toggleColumn(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = column.rawValue
                item.state = activeColumns().contains(column) ? .on : .off
                item.isEnabled = column != .name   // Name is always present (contract §1).
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let fitThis = NSMenuItem(title: L10n.t("Vừa cỡ cột này"), action: #selector(sizeThisColumnToFit(_:)), keyEquivalent: "")
            fitThis.target = self
            menu.addItem(fitThis)
            let fitEachIndividually = NSMenuItem(title: L10n.t("Vừa cỡ mọi cột riêng"), action: #selector(sizeAllColumnsToFitIndividually(_:)), keyEquivalent: "")
            fitEachIndividually.target = self
            menu.addItem(fitEachIndividually)
            let fitAllEqually = NSMenuItem(title: L10n.t("Vừa cỡ mọi cột bằng nhau"), action: #selector(sizeAllColumnsEqually(_:)), keyEquivalent: "")
            fitAllEqually.target = self
            menu.addItem(fitAllEqually)
        }

        @objc private func toggleColumn(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let column = ListColumn(rawValue: raw),
                  column != .name, let outlineView else { return }
            var prefs = pane.folderPrefs ?? FolderViewPrefs.defaults(viewMode: pane.viewMode)
            if let index = prefs.columns.firstIndex(of: column) {
                prefs.columns.remove(at: index)
            } else {
                prefs.columns.append(column)
            }
            pane.folderPrefs = prefs
            rebuildColumns(in: outlineView)
            syncSortIndicator()
        }

        /// The column the header was right-clicked on, from `NSTableView.clickedColumn` (set by AppKit for the
        /// click that opened the header's context menu) — defaults to the outline/name column when the click
        /// location did not register one (menu opened via keyboard, say).
        private func clickedColumn() -> NSTableColumn? {
            guard let outlineView else { return nil }
            let index = outlineView.clickedColumn
            guard index >= 0, index < outlineView.tableColumns.count else { return outlineView.outlineTableColumn }
            return outlineView.tableColumns[index]
        }

        @objc private func sizeThisColumnToFit(_ sender: NSMenuItem) {
            guard let outlineView, let column = clickedColumn() else { return }
            sizeToFit(column, in: outlineView)
        }

        @objc private func sizeAllColumnsToFitIndividually(_ sender: NSMenuItem) {
            guard let outlineView else { return }
            for column in outlineView.tableColumns { sizeToFit(column, in: outlineView) }
        }

        @objc private func sizeAllColumnsEqually(_ sender: NSMenuItem) {
            guard let outlineView, !outlineView.tableColumns.isEmpty else { return }
            let total = outlineView.tableColumns.reduce(0) { $0 + $1.width }
            let each = max(1, total / CGFloat(outlineView.tableColumns.count))
            for column in outlineView.tableColumns { column.width = each }
        }

        /// Widens `column` to the widest content currently loaded for it (double-click on a column edge does the
        /// same, through `NSOutlineView`'s own `doubleAction`-free resize gesture — this is the explicit menu path).
        private func sizeToFit(_ column: NSTableColumn, in outlineView: NSOutlineView) {
            guard let kind = ListColumn(rawValue: column.identifier.rawValue) else { return }
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            var widest = column.minWidth
            for node in rootNodes() {
                guard let entry = node.entry else { continue }
                let text = Self.previewText(column: kind, entry: entry)
                let width = (text as NSString).size(withAttributes: [.font: font]).width + 24
                widest = max(widest, width)
            }
            column.width = widest
        }

        private static func previewText(column: ListColumn, entry: DirectoryEntry) -> String {
            switch column {
            case .name: return entry.name
            case .dateModified: return dateText(entry.modified)
            case .dateCreated: return dateText(entry.created)
            case .dateAdded: return entry.added.map(dateText) ?? ""
            case .dateLastOpened: return entry.lastOpened.map(dateText) ?? ""
            case .size: return entry.size >= 0 ? sizeText(entry.size) : ""
            case .kind: return FileIconCache.shared.kindName(for: entry)
            case .tags: return (entry.tags ?? []).joined(separator: ", ")
            }
        }

        // MARK: - Selection (two-way)

        func syncSelection() {
            guard let outlineView, !isSyncingSelection else { return }
            guard pane.selection != lastSyncedSelection else { return }
            let wanted = pane.selection
            var rows = IndexSet()
            for row in 0..<outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? Node, let entry = node.entry,
                      wanted.contains(entry.path) else { continue }
                rows.insert(row)
            }
            lastSyncedSelection = wanted
            guard rows != outlineView.selectedRowIndexes else { return }
            isSyncingSelection = true
            outlineView.selectRowIndexes(rows, byExtendingSelection: false)
            isSyncingSelection = false
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView, !isSyncingSelection else { return }
            isSyncingSelection = true
            let paths = outlineView.selectedRowIndexes.compactMap { row -> String? in
                guard let node = outlineView.item(atRow: row) as? Node else { return nil }
                return node.entry?.path
            }
            let selection = Set(paths)
            pane.selection = selection
            lastSyncedSelection = selection
            isSyncingSelection = false
        }

        // MARK: - Double-click / Return / type-select / disclosure navigation

        @objc func doubleClicked() {
            guard let outlineView, outlineView.clickedRow >= 0,
                  let node = outlineView.item(atRow: outlineView.clickedRow) as? Node, let entry = node.entry else { return }
            pane.open(entry)
        }

        /// Return starts an inline rename; → expands a collapsed folder (or, already expanded/a plain file, does
        /// nothing — `NSOutlineView` itself moves into the first child when already expanded, contract: "→ mở"); ←
        /// collapses an expanded folder, or selects the parent when already collapsed/a plain row (Finder's own
        /// rule); ⌥→/⌥← do the same recursively with a cap. Everything else (plain arrows while NOT on a disclosure
        /// row, Up/Down) is left to `NSOutlineView`'s own handling.
        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard let characters = event.charactersIgnoringModifiers else { return false }
            if characters == "\r" || characters == "\u{3}" {
                if pane.selection.count == 1 { model.renaming = pane.id }
                return true
            }
            if let arrow = Self.arrowKey(for: event) {
                return handleArrow(arrow, option: event.modifierFlags.contains(.option))
            }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let scalar = characters.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) || characters == " "
            else { return false }
            let buffer = typeSelect.type(characters, at: Date())
            let names = rootNodes().compactMap { $0.entry?.name }
            guard let index = EntryRules.TypeSelect.match(prefix: buffer, in: names) else { return false }
            selectEntryNamed(at: index, in: names)
            return true
        }

        private enum Arrow { case left, right }

        private static func arrowKey(for event: NSEvent) -> Arrow? {
            switch event.specialKey {
            case .some(.leftArrow): return .left
            case .some(.rightArrow): return .right
            default: return nil
            }
        }

        private func handleArrow(_ arrow: Arrow, option: Bool) -> Bool {
            guard let outlineView, outlineView.selectedRow >= 0,
                  let node = outlineView.item(atRow: outlineView.selectedRow) as? Node, let entry = node.entry,
                  entry.isFolderLike, entry.path != selfEntry?.path else { return false }
            switch arrow {
            case .right:
                if option {
                    expandRecursively(node, outlineView: outlineView)
                } else if !outlineView.isItemExpanded(node) {
                    outlineView.expandItem(node)
                } else {
                    return false   // already expanded: let NSOutlineView move selection into the first child.
                }
            case .left:
                if option {
                    collapseRecursively(node, outlineView: outlineView)
                } else if outlineView.isItemExpanded(node) {
                    outlineView.collapseItem(node)
                } else {
                    return false   // already collapsed on a folder row: let NSOutlineView select the parent.
                }
            }
            return true
        }

        /// Opens `node` and every descendant folder, breadth-first, stopping at `recursiveExpandCap` additional
        /// rows opened (contract §3: "⌥→/⌥← đệ quy với trần 10 000 mục mở thêm, quá trần dừng + banner"). Only
        /// ALREADY-LOADED children are walked into synchronously; a folder whose children are still loading when
        /// its turn comes is simply expanded (it will show its own contents once the load lands) without the
        /// recursion continuing into ITS children — a 100 000-entry tree cannot be walked synchronously to disk
        /// depth-first without blocking the main thread, and the contract's budget is about the already-visible
        /// result, not a guarantee every nested descendant starts loaded.
        private func expandRecursively(_ root: Node, outlineView: NSOutlineView) {
            var opened = 0
            var queue = [root]
            var hitCap = false
            while !queue.isEmpty {
                let node = queue.removeFirst()
                guard let entry = node.entry, entry.isFolderLike, entry.path != selfEntry?.path else { continue }
                if !outlineView.isItemExpanded(node) {
                    if opened >= FileListView.recursiveExpandCap { hitCap = true; break }
                    ensureChildrenLoaded(entry.path)
                    outlineView.expandItem(node)
                    opened += 1
                }
                guard let folder = expanded[entry.path], folder.loaded else { continue }
                queue.append(contentsOf: folder.children.map(Node.entry))
            }
            if hitCap {
                model.banner = "Đã mở quá nhiều thư mục con, dừng lại"
            }
        }

        private func collapseRecursively(_ root: Node, outlineView: NSOutlineView) {
            guard let entry = root.entry else { return }
            if let folder = expanded[entry.path] {
                for child in folder.children where child.isFolderLike {
                    collapseRecursively(.entry(child), outlineView: outlineView)
                }
            }
            if outlineView.isItemExpanded(root) {
                outlineView.collapseItem(root)
            }
        }

        /// `outlineViewItemDidCollapse` cancels that row's watcher/cache (contract ca hỏng: "không rò
        /// DirectoryWatcher") — a later re-expand starts a fresh load, same as `FileColumnView`'s own cache
        /// invalidation on display-setting changes.
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? Node, let entry = node.entry else { return }
            stopWatching(entry.path)
        }

        private func selectEntryNamed(at index: Int, in names: [String]) {
            guard let outlineView else { return }
            let wantedName = names[index]
            for row in 0..<outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? Node, let entry = node.entry,
                      entry.name == wantedName else { continue }
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                return
            }
        }

        // MARK: - Inline rename

        func beginRenameIfNeeded() {
            guard model.renaming == pane.id, renamingPath == nil,
                  let path = pane.selection.count == 1 ? pane.selection.first : nil,
                  let outlineView, let entry = findEntry(path: path) else { return }
            let row = outlineView.row(forItem: Node.entry(entry))
            guard row >= 0,
                  let column = outlineView.tableColumns.firstIndex(where: { $0.identifier == outlineView.outlineTableColumn?.identifier }),
                  let cell = outlineView.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView,
                  let field = cell.textField else { return }
            renamingPath = path
            let name = entry.name
            field.isEditable = true
            field.delegate = self
            field.stringValue = name
            outlineView.window?.makeFirstResponder(field)
            // Select the stem only (contract: "select the stem without extension").
            let ext = entry.ext
            let stemLength = ext.isEmpty ? name.count : max(0, name.count - ext.count - 1)
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: 0, length: stemLength)
            }
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
            defer { reloadIfNeeded() }
            field?.isEditable = false
            field?.delegate = nil
            if model.renaming == pane.id { model.renaming = nil }
            guard commit, let field else { return }
            _ = model.commitRename(path, to: field.stringValue)
        }

        // MARK: - Drag source

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? Node, let entry = node.entry else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(URL(fileURLWithPath: entry.path).absoluteString, forType: .fileURL)
            return pasteboardItem
        }

        // MARK: - Drop target

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                          proposedChildIndex index: Int) -> NSDragOperation {
            guard info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
            let operation = dragOperation(for: info)
            if index == NSOutlineViewDropOnItemIndex, let node = item as? Node, let entry = node.entry, entry.isFolderLike {
                let target: String = entry.path
                springLoader.begin(hovering: target) { [weak self] in self?.pane.navigate(to: target) }
                return operation
            }
            springLoader.cancel()
            outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return operation
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            springLoader.cancel()
            guard let paths = draggedPaths(from: info) else { return false }
            let destination: String
            if index == NSOutlineViewDropOnItemIndex, let node = item as? Node, let entry = node.entry, entry.isFolderLike {
                destination = entry.path
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

        /// Hands off to the ONE shared menu builder (contract §3: "MỘT nơi dựng menu cho cả 4 kiểu xem"); this view
        /// only re-targets the selection on a right-click outside it first, same as the XF-T28 table view did.
        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        private func populateContextMenu(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView else { return }
            let clickedRow = outlineView.clickedRow
            if clickedRow >= 0, !outlineView.selectedRowIndexes.contains(clickedRow),
               let node = outlineView.item(atRow: clickedRow) as? Node, node.entry != nil {
                outlineView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
            model.focus(pane.id)
            let built = BrowserContextMenu.menu(for: model, pane: pane)
            for item in built.items {
                built.removeItem(item)
                menu.addItem(item)
            }
        }

        // MARK: - NSMenuDelegate (both the row menu and the header's column-toggle menu use this coordinator)

        func menuNeedsUpdate(_ menu: NSMenu) {
            if menu === outlineView?.headerView?.menu {
                populateHeaderMenu(menu)
            } else {
                populateContextMenu(menu)
            }
        }

        // MARK: - Cloud badge (lazy, visible rows only)

        func cloudFacts(for path: String) -> CloudFacts { cloudCache.facts(for: path) }
    }
}

private extension ListColumn {
    var titleKey: String {
        switch self {
        case .name: return "Tên"
        case .dateModified: return "Ngày sửa"
        case .dateCreated: return "Ngày tạo"
        case .dateAdded: return "Ngày thêm"
        case .dateLastOpened: return "Ngày mở gần nhất"
        case .size: return "Cỡ"
        case .kind: return "Loại"
        case .tags: return "Các thẻ"
        }
    }
    var minWidth: CGFloat {
        switch self {
        case .name: return 160
        case .dateModified, .dateCreated, .dateAdded, .dateLastOpened: return 110
        case .size: return 70
        case .kind: return 90
        case .tags: return 90
        }
    }
    var defaultWidth: CGFloat {
        switch self {
        case .name: return 280
        case .dateModified, .dateCreated, .dateAdded, .dateLastOpened: return 140
        case .size: return 80
        case .kind: return 120
        case .tags: return 120
        }
    }
    var sortKey: SortKey? {
        switch self {
        case .name: return .name
        case .dateModified: return .modified
        case .dateCreated: return .created
        case .dateAdded: return .added
        case .dateLastOpened: return .lastOpened
        case .size: return .size
        case .kind: return .kind
        case .tags: return nil   // no SortKey.tags (contract's Sort By list has no "Tags" entry — Group By does).
        }
    }
}
