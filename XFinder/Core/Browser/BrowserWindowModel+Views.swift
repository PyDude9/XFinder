import AppKit

/// XF-T30 W2 — the model side of the views wave: Group By sections, per-folder view options, Make Alias, Show Original,
/// Add to Sidebar, Share, View Options, Open With, tags. Contract docs/specs/XF-T30-w2-contract.md. W2 builder (model).
extension PaneState {
    /// Rebuilds `sections` from `entries` for `groupBy` / `useGroups` (called at the end of every `applyEntries`).
    /// `.none` or `useGroups == false` ⇒ one section holding everything, same as `GroupBy.sections` already returns
    /// for `.none` — `rebuildSections` just decides WHICH field (if any) to pass it, the grouping rules themselves
    /// live in `GroupBy.sections` (W2 pure builder).
    ///
    /// XF-T32 W3: with `useGroups` on and `propertyGroupID` naming a property of `BrowserMetadata.shared.catalog`, the
    /// sections are that property's options (`PropertyRules.sections`, option order, unset last) instead. A property
    /// id the catalog does not (or not yet — it loads asynchronously) know falls back to `groupBy`; the id is kept so
    /// grouping comes back once the catalog has loaded.
    func rebuildSections() {
        sections = computedSections()
    }

    /// Called when `BrowserMetadata` changed (a selection was set, the catalog edited, a folder's metadata loaded):
    /// only a pane grouped by a property depends on it, and only a real difference is published (a rebuild that
    /// produces the same sections must not make the views redraw).
    func metadataDidChange() {
        guard useGroups, propertyGroupID != nil else { return }
        let updated: [EntrySection] = computedSections()
        if updated != sections {
            sections = updated
            metadataGroupingRevision &+= 1
        }
    }

    private func computedSections() -> [EntrySection] {
        if useGroups, let property: PropertyDefinition = groupingProperty() {
            return propertySections(property)
        }
        let field: GroupBy = useGroups ? groupBy : .none
        return GroupBy.sections(entries, by: field, sort: sort, foldersFirst: foldersFirst, now: Date(),
                                calendar: .current, kindName: { FileIconCache.shared.kindName(for: $0) },
                                appName: { FileMetadataCache.shared.appName(for: $0.path) })
    }

    private func groupingProperty() -> PropertyDefinition? {
        guard let id: UUID = propertyGroupID else { return nil }
        return BrowserMetadata.shared.catalog.definition(id)
    }

    /// `entries` are already filtered + sorted; `PropertyRules.sections` keeps that order inside each section.
    private func propertySections(_ property: PropertyDefinition) -> [EntrySection] {
        let metadata: BrowserMetadata = BrowserMetadata.shared
        var selections: [String: UUID] = [:]
        selections.reserveCapacity(entries.count)
        for entry in entries {
            if let option: PropertyOption = metadata.option(for: entry.path, property: property.id) {
                selections[entry.path] = option.id
            }
        }
        let grouped: [PropertyRules.Section] = PropertyRules.sections(entries, property: property, selections: selections)
        return grouped.map { (section: PropertyRules.Section) -> EntrySection in
            guard let option: PropertyOption = section.option else {
                return EntrySection(titleKey: PropertyRules.unsetTitleKey, titleArg: nil, entries: section.entries)
            }
            return EntrySection(titleKey: "", titleArg: option.title, entries: section.entries)
        }
    }
}

extension BrowserWindowModel {

    // MARK: - Trash / search detection (R46/R72: Share, Duplicate, Compress, Make Alias disabled in the Trash)

    /// The user's Trash directories (there can be more than one — one per mounted volume). Looked up once per call
    /// since a volume can mount/unmount mid-session; cheap (`FileManager.urls` does not touch disk beyond resolving
    /// well-known paths).
    private var trashDirectories: [String] {
        FileManager.default.urls(for: .trashDirectory, in: .allDomainsMask).map(\.path)
    }

    /// Whether `path` is inside (or is) one of the Trash directories — a plain prefix check, same granularity as
    /// `SearchIndexRules.excludedDirectoryNames`'s own `.Trash` entry.
    private func isInTrash(_ path: String) -> Bool {
        trashDirectories.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Spec R46/R72: Share / Duplicate / Compress / Make Alias go gray for anything already in the Trash.
    private func selectionInTrash(_ entries: [DirectoryEntry]) -> Bool {
        !entries.isEmpty && entries.allSatisfy { isInTrash($0.path) }
    }

    // MARK: - Dispatch

    func performViewsCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .makeAlias:
            makeAlias()
            return true
        case .showOriginal:
            showOriginal()
            return true
        case .addToSidebar:
            addSelectionToSidebar()
            return true
        case .share:
            presentSharePicker()
            return true
        case .showViewOptions:
            ViewOptionsPanelController.shared.toggle(for: self)
            return true
        default:
            return false
        }
    }

    func canPerformViewsCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .makeAlias:
            // Contract §3/task: disabled in the Trash and in search results (an alias of a search HIT belongs next to
            // the real file, not implicitly "here" — same restriction FileOctopus documents for Share/Duplicate/
            // Compress in the Trash, extended to search results because there is no single "here" to drop it into).
            let selected = active.selectedEntries
            return !selected.isEmpty && active.search == nil && !selectionInTrash(selected)
        case .showOriginal:
            return aliasOrSymlinkTarget() != nil
        case .addToSidebar:
            return active.selectedEntries.contains { $0.isFolderLike }
        case .share:
            return !selectionInTrash(active.selectedEntries) && !active.selectedEntries.isEmpty
        case .showViewOptions:
            return true
        default:
            return false
        }
    }

    // MARK: - Open With

    /// Opens the selection with `app` (Open With ▸).
    func openSelection(with app: URL) {
        let urls = active.selectedEntries.map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration, completionHandler: nil)
    }

    // MARK: - Tags

    /// Adds (or removes when every selected item already has it) the Finder tag of `color` on the selection. The
    /// xattr write happens off the main thread (CLAUDE.md §3.3: no disk I/O on the main actor); the pane reloads once
    /// every selected item has been updated so `FileMetadataCache`/the dot in the Name column pick up the change.
    func toggleTag(_ color: TagColor) {
        let paths = active.selectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            // Finder semantics: the swatch is a single on/off switch for the WHOLE selection, not per file — only
            // when every selected item already carries `color` does clicking it remove the tag; otherwise it adds
            // the tag to every item (including ones that already have it, idempotently). Deciding this per file
            // (as a naive "has it ⇒ remove, else add" would) swaps tags across a mixed selection instead of
            // unifying it.
            let allHaveColor = paths.allSatisfy { Self.existingTags(at: $0).contains { $0.color == color } }
            for path in paths {
                Self.applyTagToggle(color, at: path, removing: allHaveColor)
            }
            await MainActor.run { [weak self] in
                self?.active.reload()
            }
        }
    }

    /// `nonisolated`: runs inside the detached task above, off the main actor — reads one file's xattr only.
    private nonisolated static func existingTags(at path: String) -> [FinderTag] {
        guard let data = try? URL(fileURLWithPath: path).extendedAttribute(forName: "com.apple.metadata:_kMDItemUserTags") else {
            return []
        }
        return FinderTags.decodeXattr(data)
    }

    /// `nonisolated`: runs inside the detached task above, off the main actor — reads/writes one file's xattr only.
    private nonisolated static func applyTagToggle(_ color: TagColor, at path: String, removing: Bool) {
        let url = URL(fileURLWithPath: path)
        let xattrName = "com.apple.metadata:_kMDItemUserTags"
        let existing = existingTags(at: path)
        let updated = removing ? existing.filter { $0.color != color } : existing + [FinderTag(name: color.titleKey, color: color)]
        let encoded = FinderTags.encodeXattr(updated)
        if updated.isEmpty {
            try? url.removeExtendedAttribute(forName: xattrName)
        } else {
            try? url.setExtendedAttribute(data: encoded, forName: xattrName)
        }
    }

    // MARK: - Make Alias / Show Original

    /// "photo.jpg" → "photo alias.jpg" (suffix before the LAST extension, same convention as Finder's "Report
    /// copy.pdf"); a folder (or extension-less file) gets the bare suffix appended with no dot-splitting at all —
    /// `FileOperationRules.keepBothName` would otherwise treat anything after the file's own last dot (e.g. the
    /// "jpg" in "photo.jpg alias") as the extension to preserve, producing nonsense like "photo 2.jpg alias".
    private func aliasFileName(for entry: DirectoryEntry, existing: Set<String>) -> String {
        guard !entry.isFolderLike, let dot = entry.name.lastIndex(of: "."), dot != entry.name.startIndex else {
            return FileOperationRules.keepBothName(for: "\(entry.name) alias", existing: existing)
        }
        let base = String(entry.name[entry.name.startIndex..<dot])
        let ext = String(entry.name[entry.name.index(after: dot)...])
        let strippedExisting = Set(existing.map {
            // Strip the same extension from each existing name so collisions are detected on the base, not the
            // whole filename (mirrors how `keepBothName` itself compares bases when it owns the extension split).
            $0.hasSuffix(".\(ext)") ? String($0.dropLast(ext.count + 1)) : $0
        })
        let aliasedBase = FileOperationRules.keepBothName(for: "\(base) alias", existing: strippedExisting)
        return "\(aliasedBase).\(ext)"
    }

    private func makeAlias() {
        let selected = active.selectedEntries
        guard !selected.isEmpty, active.search == nil, !selectionInTrash(selected) else { return }
        let folder = active.path
        let existing = Set(active.entries.map(\.name))
        var taken = existing
        var createdNames: [String] = []
        for entry in selected {
            let name = aliasFileName(for: entry, existing: taken)
            taken.insert(name)
            let destination = (folder as NSString).appendingPathComponent(name)
            do {
                let source = URL(fileURLWithPath: entry.path)
                let bookmark = try source.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(bookmark, to: URL(fileURLWithPath: destination))
                createdNames.append(name)
            } catch {
                banner = "Không tạo được bí danh"
            }
        }
        guard !createdNames.isEmpty else { return }
        active.selection = Set(createdNames.map { (folder as NSString).appendingPathComponent($0) })
        active.reload()
    }

    /// Resolves the single selected alias/symlink to its target path, or nil when the selection is not exactly one
    /// such item (spec §3: `showOriginal` only makes sense for one alias/symlink at a time, same as Finder).
    private func aliasOrSymlinkTarget() -> String? {
        guard active.selectedEntries.count == 1, let entry = active.selectedEntries.first else { return nil }
        let url = URL(fileURLWithPath: entry.path)
        if let values = try? url.resourceValues(forKeys: [.isAliasFileKey]), values.isAliasFile == true {
            guard let resolved = try? URL(resolvingAliasFileAt: url) else { return nil }
            return resolved.path
        }
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path) {
            // `destinationOfSymbolicLink` can return a path relative to the link's own folder.
            if destination.hasPrefix("/") { return destination }
            return ((entry.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(destination)
        }
        return nil
    }

    /// Navigates the active tab to the resolved target's PARENT and selects it there — the menu label itself
    /// ("Hiện bản gốc" vs. "Hiện trong thư mục chứa" in search results) is the view's job (contract §3); this only
    /// does the navigation + selection both labels share.
    private func showOriginal() {
        guard let target = aliasOrSymlinkTarget() else {
            banner = "Không tìm thấy bản gốc"
            return
        }
        let parent = (target as NSString).deletingLastPathComponent
        let name = (target as NSString).lastPathComponent
        guard !parent.isEmpty else { return }
        active.selectAfterLoad = name
        active.navigate(to: parent)
    }

    // MARK: - Add to Sidebar

    /// Adds every selected folder to the sidebar's Mục ưa thích (⌃⌘T) through `BrowserSettings.sidebarLayout` — the
    /// ONE reader/writer of that key (CLAUDE.md rule 7); `SidebarLayout.addItem` already de-duplicates by path.
    func addSelectionToSidebar() {
        let folders = active.selectedEntries.filter(\.isFolderLike).map(\.path)
        guard !folders.isEmpty else {
            banner = "Không thêm được vào sidebar"
            return
        }
        var layout = BrowserSettings.sidebarLayout
        for path in folders { layout.addItem(path: path, toGroup: nil) }
        BrowserSettings.sidebarLayout = layout
        SpaceController.shared.sidebarDidChange(layout)
    }

    // MARK: - Share

    /// `NSSharingServicePicker` relative to the key window's content view (task: "shown relative to the key window
    /// content") — the toolbar's own `NSSharingServicePickerToolbarItem` (`BrowserToolbar.swift`) handles the
    /// toolbar button itself; this is the context-menu/Action-menu/⌘-less "Share…" entry, which has no toolbar item
    /// to anchor to.
    private func presentSharePicker() {
        let urls = active.selectedEntries.map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty, let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    // MARK: - Per-folder view options (⌘J "Always open in this view")

    /// Saves the active tab's view options for its folder (`FolderViewOptions.FolderViewStore`, LRU 500 paths,
    /// `~/Library/Application Support/XFinder/Browser/folder-views.json`). The read-modify-write of that store (and
    /// the disk write itself) both happen off the main actor — only what's needed from `active` is captured first.
    func rememberViewOptionsForFolder() {
        let path = active.path
        let prefs = FolderViewPrefs(viewMode: active.viewMode, sort: active.sort, groupBy: active.groupBy,
                                    useGroups: active.useGroups, iconSize: active.folderPrefs?.iconSize ?? 64,
                                    textSize: active.folderPrefs?.textSize ?? 13,
                                    columns: active.folderPrefs?.columns ?? FolderViewPrefs.defaultColumns,
                                    showIconPreview: active.folderPrefs?.showIconPreview ?? true)
        active.folderPrefs = prefs
        Task.detached(priority: .utility) {
            var store = FolderViewStore.decode(Self.readFolderViewStoreData())
            store.set(prefs, for: path)
            Self.writeFolderViewStoreData(store.encoded())
        }
    }

    /// Loads the remembered view options (if any) for `path` and applies them to `tab` — called when a tab
    /// navigates (the task's "loading FolderViewPrefs for a tab when it navigates"). Runs the disk read off the main
    /// actor; applies the result back on main only if the tab is still showing the same folder by the time it lands
    /// (a fast double-navigate must not stamp stale prefs onto a tab that has already moved on).
    func loadViewOptions(for tab: PaneState) {
        Self.applyRememberedViewOptions(to: tab)
    }

    /// Called by every navigation of a tab (navigate / Back / Forward): the folder's remembered view options, if any,
    /// replace the tab's current ones; a folder with nothing remembered keeps the tab's view.
    static func applyRememberedViewOptions(to tab: PaneState) {
        let path: String = tab.path
        guard VirtualLocation.parse(path) == nil else { return }
        Task.detached(priority: .utility) {
            let store = FolderViewStore.decode(Self.readFolderViewStoreData())
            guard let prefs = store.prefs(for: path) else { return }
            await MainActor.run {
                guard tab.path == path else { return }
                tab.folderPrefs = prefs
                tab.viewMode = prefs.viewMode
                tab.sort = prefs.sort
                tab.groupBy = prefs.groupBy
                tab.useGroups = prefs.useGroups
                tab.rebuildSections()
            }
        }
    }

    // MARK: - folder-views.json (nonisolated disk I/O helpers)

    private nonisolated static var folderViewStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder/Browser/folder-views.json", isDirectory: false)
    }

    private nonisolated static func readFolderViewStoreData() -> Data? {
        try? Data(contentsOf: folderViewStoreURL)
    }

    private nonisolated static func writeFolderViewStoreData(_ data: Data) {
        let url = folderViewStoreURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Extended attribute helpers (xattr read/write/remove for Finder tags)

private extension URL {
    func extendedAttribute(forName name: String) throws -> Data {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOATTR) }
        var data = Data(count: length)
        let readCount = data.withUnsafeMutableBytes { buffer -> Int in
            getxattr(path, name, buffer.baseAddress, length, 0, 0)
        }
        guard readCount >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOATTR) }
        return data
    }

    func setExtendedAttribute(data: Data, forName name: String) throws {
        let result = data.withUnsafeBytes { buffer -> Int32 in
            Int32(setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0))
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOATTR) }
    }

    func removeExtendedAttribute(forName name: String) throws {
        let result = removexattr(path, name, 0)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOATTR) }
    }
}
