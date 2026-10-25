import AppKit
import SwiftUI

/// XF-T30 W2 (was XF-T28 cluster D) — Biểu tượng (NSCollectionView, flow layout). Same selection/drag/drop/menu/
/// type-select rules as `FileListView`, but a grid of icon + 2-line middle-truncated name. AppKit for the same
/// reason: 100 000 items must reuse cells (`NSCollectionView`'s own item-reuse pool), which a SwiftUI `LazyVGrid`
/// inside a `ScrollView` does not do for anything approaching that count. W2 adds: section headers when
/// `pane.useGroups`, icon/text size from `pane.folderPrefs`, a tag dot under the name, a cloud badge over the icon,
/// stable layout at very narrow pane widths (FileOctopus 1.0.2 bug), and drop acceptance onto a folder's own icon
/// (1.0.4 bug).
struct FileIconView: NSViewRepresentable {
    let pane: PaneState
    let model: BrowserWindowModel

    /// Narrowest a grid item is ever laid out at (contract: "ổn định khi ngăn rất hẹp" — FileOctopus 1.0.2 let the
    /// flow layout's item width collapse toward zero in a very narrow pane, which both mis-wrapped the name and made
    /// `NSCollectionViewFlowLayout` thrash between 0- and 1-column layouts on every tiny resize).
    static let minimumItemWidth: CGFloat = 72

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = context.coordinator.itemSize
        layout.headerReferenceSize = NSSize(width: 0, height: 22)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let collectionView = KeyRoutingCollectionView(frame: .zero)
        collectionView.coordinator = context.coordinator
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.delegate = context.coordinator
        collectionView.dataSource = context.coordinator
        collectionView.register(IconItem.self, forItemWithIdentifier: IconItem.identifier)
        collectionView.register(SectionHeaderView.self,
                                forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: SectionHeaderView.identifier)
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.menu = context.coordinator.makeContextMenu()

        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleClicked(_:)))
        doubleClick.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClick)

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        context.coordinator.collectionView = collectionView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.pane = pane
        context.coordinator.model = model
        context.coordinator.reloadIfNeeded()
        context.coordinator.syncSelection()
        context.coordinator.beginRenameIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator(pane: pane, model: model) }

    /// Routes `keyDown` (type-select / Return-to-rename) to the coordinator before `NSCollectionView`'s own
    /// handling, same reasoning as `FileListView.KeyRoutingTableView`. Also retargets the selection to the
    /// right-clicked item before the context menu opens, same contract `FileListView.populateContextMenu` already
    /// follows for `NSTableView` — `NSCollectionView` has no `clickedRow`, so this reads the click location straight
    /// off the event instead.
    final class KeyRoutingCollectionView: NSCollectionView {
        weak var coordinator: Coordinator?
        override func keyDown(with event: NSEvent) {
            if coordinator?.handleKeyDown(event) == true { return }
            super.keyDown(with: event)
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            coordinator?.retargetSelectionForRightClick(at: convert(event.locationInWindow, from: nil))
            return super.menu(for: event)
        }
    }

    /// A section's "Today" / "Hôm qua" / kind / tag-name label above its row of items (contract: "section + header
    /// khi có nhóm"), the collection-view analogue of `FileListView`'s table group rows.
    final class SectionHeaderView: NSView, NSCollectionViewElement {
        static let identifier = NSUserInterfaceItemIdentifier("FileIconView.SectionHeaderView")
        private let label = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(titleKey: String, titleArg: String?) {
            // Same text as every other view (kind / application / tag groups have no key, only the name).
            label.stringValue = EntrySection(titleKey: titleKey, titleArg: titleArg, entries: []).displayTitle { L10n.t($0) }
        }
    }

    /// One grid cell: icon (or thumbnail for images, fetched lazily only while visible) + a 2-line
    /// middle-truncated name below it, a cloud badge over the icon's corner, and a tag dot under the name.
    final class IconItem: NSCollectionViewItem {
        static let identifier = NSUserInterfaceItemIdentifier("FileIconView.IconItem")
        private let nameField = NSTextField(labelWithString: "")
        private let badgeView = NSImageView()
        private let tagDot = TagDotView()
        private var renamingField: NSTextField?
        weak var coordinator: Coordinator?
        private(set) var path: String?
        private var imageSide: CGFloat = FileIconView.Coordinator.defaultIconSide

        override func loadView() {
            let container = NSView()
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)
            self.imageView = imageView

            badgeView.imageScaling = .scaleProportionallyDown
            badgeView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(badgeView)

            tagDot.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tagDot)

            nameField.alignment = .center
            nameField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            nameField.lineBreakMode = .byTruncatingMiddle
            nameField.maximumNumberOfLines = 2
            nameField.cell?.wraps = true
            nameField.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(nameField)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                badgeView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 2),
                badgeView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
                badgeView.widthAnchor.constraint(equalToConstant: 11),
                badgeView.heightAnchor.constraint(equalToConstant: 11),
                nameField.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
                nameField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
                nameField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                tagDot.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 2),
                tagDot.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                tagDot.widthAnchor.constraint(equalToConstant: 6),
                tagDot.heightAnchor.constraint(equalToConstant: 6),
            ])
            self.imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: imageSide)
            self.imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: imageSide)
            imageWidthConstraint?.isActive = true
            imageHeightConstraint?.isActive = true
            view = container
        }

        private var imageWidthConstraint: NSLayoutConstraint?
        private var imageHeightConstraint: NSLayoutConstraint?

        override var isSelected: Bool {
            didSet { view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).cgColor : nil }
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.wantsLayer = true
            view.layer?.cornerRadius = 8
        }

        func configure(entry: DirectoryEntry, coordinator: Coordinator, iconSide: CGFloat) {
            self.coordinator = coordinator
            path = entry.path
            nameField.stringValue = entry.name
            nameField.font = .systemFont(ofSize: coordinator.textSize)
            if imageSide != iconSide {
                imageSide = iconSide
                imageWidthConstraint?.constant = iconSide
                imageHeightConstraint?.constant = iconSide
            }
            imageView?.image = FileIconCache.shared.icon(for: entry)
            if entry.kind == .file, Self.isImageExtension(entry.ext) {
                FileIconCache.shared.thumbnail(forPath: entry.path, side: iconSide, scale: 2) { [weak self] image in
                    guard let self, self.path == entry.path, let image else { return }
                    self.imageView?.image = image
                }
            }
            let badge = coordinator.cloudBadgeSymbol(for: coordinator.cloudFacts(for: entry.path))
            badgeView.image = badge
            badgeView.isHidden = badge == nil
            let tagColor = coordinator.tagColor(for: entry)
            tagDot.color = tagColor.flatMap(Coordinator.dotColor(for:))
            tagDot.isHidden = tagDot.color == nil
        }

        private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp", "webp"]
        private static func isImageExtension(_ ext: String) -> Bool { imageExtensions.contains(ext) }

        /// Begins inline rename of the name label itself, replacing it with an editable field positioned over it.
        func beginRename() {
            guard renamingField == nil else { return }
            let field = NSTextField(string: nameField.stringValue)
            field.font = nameField.font
            field.alignment = .center
            field.frame = nameField.frame
            field.isEditable = true
            field.delegate = coordinator
            nameField.superview?.addSubview(field)
            nameField.isHidden = true
            renamingField = field
            view.window?.makeFirstResponder(field)
            if let name = path.map({ ($0 as NSString).lastPathComponent }) {
                let ext = (name as NSString).pathExtension
                let stemLength = ext.isEmpty ? name.count : max(0, name.count - ext.count - 1)
                field.currentEditor()?.selectedRange = NSRange(location: 0, length: stemLength)
            }
        }

        func endRename() {
            renamingField?.removeFromSuperview()
            renamingField = nil
            nameField.isHidden = false
        }
    }

    /// A small filled circle for the Finder-tag dot under a grid item's name; nil `color` hides it entirely rather
    /// than drawing a transparent dot (contract: a plain file shows no dot at all, not an empty-colour one).
    final class TagDotView: NSView {
        var color: NSColor? { didSet { needsDisplay = true } }
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            guard let color else { return }
            color.setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout, NSTextFieldDelegate {
        var pane: PaneState
        var model: BrowserWindowModel
        weak var collectionView: NSCollectionView?

        static let defaultIconSide: CGFloat = 64

        private var lastCount = -1
        private var lastFirstID: String?
        private var lastLastID: String?
        private var lastUseGroups = false
        private var isSyncingSelection = false
        private var typeSelect = EntryRules.TypeSelect()
        private var renamingPath: String?
        private var cloudFactsCache: [String: CloudFacts] = [:]
        /// Last `pane.selection` this coordinator pushed into/read from the grid, so `syncSelection()` can skip its
        /// O(entries.count) scan on an `updateNSView` call where selection did not change (contract: "no O(n) work
        /// per updateNSView/frame"). Cleared by `reloadIfNeeded()` since a reload can move the same paths to new
        /// index paths (e.g. a resort) even though the selected path set itself stays the same.
        private var lastSyncedSelection: Set<String> = []
        /// Sections to show (contract: "section + header khi có nhóm"): `pane.sections` while `pane.useGroups` and
        /// there is more than one non-empty section to show, otherwise one flat section with every entry — the same
        /// fallback `FileColumnView.rows(forColumn:)` uses, so a stub `GroupBy.sections` (always one untitled
        /// section) renders identically to "not grouped" instead of showing an empty header bar.
        private var sections: [EntrySection] = []

        var folderPrefs: FolderViewPrefs { pane.folderPrefs ?? .defaults(viewMode: .icons) }
        var itemSize: NSSize {
            let side = CGFloat(folderPrefs.iconSize)
            let width = max(FileIconView.minimumItemWidth, side + 24)
            return NSSize(width: width, height: side + 40)
        }
        var textSize: CGFloat { CGFloat(folderPrefs.textSize) }

        init(pane: PaneState, model: BrowserWindowModel) {
            self.pane = pane
            self.model = model
        }

        private func fingerprint() -> (Int, String?, String?, Bool) {
            (pane.entries.count, pane.entries.first?.id, pane.entries.last?.id, pane.useGroups)
        }

        func reloadIfNeeded() {
            let (count, first, last, useGroups) = fingerprint()
            guard count != lastCount || first != lastFirstID || last != lastLastID || useGroups != lastUseGroups else { return }
            lastCount = count
            lastFirstID = first
            lastLastID = last
            lastUseGroups = useGroups
            lastSyncedSelection = []
            cloudFactsCache.removeAll()
            rebuildSections()
            (collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize = itemSize
            collectionView?.reloadData()
        }

        /// Mirrors `FileColumnView.rows(forColumn:)`'s "only group when there is something to show" guard, so an
        /// unimplemented/stub `GroupBy.sections` (always one untitled section) is indistinguishable from "not
        /// grouped" rather than drawing an empty header bar above every item.
        private func rebuildSections() {
            guard pane.useGroups else {
                sections = [EntrySection(titleKey: "", titleArg: nil, entries: pane.entries)]
                return
            }
            let grouped = GroupBy.sections(pane.entries, by: pane.groupBy, sort: pane.sort, foldersFirst: pane.foldersFirst,
                                           now: Date(), calendar: .current,
                                           kindName: { FileIconCache.shared.kindName(for: $0) },
                                           appName: { FileMetadataCache.shared.appName(for: $0.path) })
            let nonEmpty = grouped.filter { !$0.entries.isEmpty }
            sections = nonEmpty.count > 1 || nonEmpty.first?.titleKey.isEmpty == false
                ? nonEmpty
                : [EntrySection(titleKey: "", titleArg: nil, entries: pane.entries)]
        }

        private func entry(at indexPath: IndexPath) -> DirectoryEntry? {
            guard indexPath.section < sections.count, indexPath.item < sections[indexPath.section].entries.count else { return nil }
            return sections[indexPath.section].entries[indexPath.item]
        }

        /// `(section, item)` of `path` across every section — selection/rename/type-select all need this since a
        /// path's index can no longer be computed from `pane.entries` alone once items are split into sections.
        private func indexPath(forPath path: String) -> IndexPath? {
            for (s, section) in sections.enumerated() {
                if let i = section.entries.firstIndex(where: { $0.path == path }) { return IndexPath(item: i, section: s) }
            }
            return nil
        }

        // MARK: - Selection (two-way)

        func syncSelection() {
            guard let collectionView, !isSyncingSelection else { return }
            guard pane.selection != lastSyncedSelection else { return }
            let wanted = pane.selection
            var indexPaths = Set<IndexPath>()
            for (s, section) in sections.enumerated() {
                for (i, entry) in section.entries.enumerated() where wanted.contains(entry.path) {
                    indexPaths.insert(IndexPath(item: i, section: s))
                }
            }
            lastSyncedSelection = wanted
            guard indexPaths != collectionView.selectionIndexPaths else { return }
            isSyncingSelection = true
            collectionView.selectionIndexPaths = indexPaths
            isSyncingSelection = false
        }

        private func pushSelectionToModel() {
            guard let collectionView, !isSyncingSelection else { return }
            isSyncingSelection = true
            let paths = collectionView.selectionIndexPaths.compactMap { entry(at: $0)?.path }
            let selection = Set(paths)
            pane.selection = selection
            lastSyncedSelection = selection
            isSyncingSelection = false
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { pushSelectionToModel() }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { pushSelectionToModel() }

        // MARK: - NSCollectionViewDataSource

        func numberOfSections(in collectionView: NSCollectionView) -> Int { max(1, sections.count) }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            guard section < sections.count else { return 0 }
            return sections[section].entries.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: IconItem.identifier, for: indexPath)
            guard let iconItem = item as? IconItem, let entry = entry(at: indexPath) else { return item }
            iconItem.configure(entry: entry, coordinator: self, iconSide: CGFloat(folderPrefs.iconSize))
            return iconItem
        }

        func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                            at indexPath: IndexPath) -> NSView {
            let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: SectionHeaderView.identifier, for: indexPath)
            guard let header = header as? SectionHeaderView, indexPath.section < sections.count else { return header }
            let section = sections[indexPath.section]
            header.configure(titleKey: section.titleKey, titleArg: section.titleArg)
            return header
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            referenceSizeForHeaderInSection section: Int) -> NSSize {
            guard section < sections.count, !sections[section].titleKey.isEmpty else { return .zero }
            return NSSize(width: 0, height: 22)
        }

        // MARK: - Cloud badge / tag dot (lazy, visible rows only — same cache shape as FileListView's)

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

        func cloudBadgeSymbol(for facts: CloudFacts) -> NSImage? {
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

        /// First tag's colour (a grid item shows one dot, same simplification as the Column view's).
        func tagColor(for entry: DirectoryEntry) -> TagColor? {
            guard let raw = entry.tags?.first else { return nil }
            return FinderTags.parse(raw).color
        }

        /// Finder's seven tag colours — a literal RGB table, not a design token (CLAUDE.md §3.2 exemption also used
        /// by `FileColumnView.ColumnBrowserCell`): these have to match Finder's own tag dots, not XFinder's palette.
        static func dotColor(for tagColor: TagColor) -> NSColor? {
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

        // MARK: - Double-click / Return / type-select

        @objc func doubleClicked(_ sender: NSClickGestureRecognizer) {
            guard let collectionView else { return }
            let point = sender.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: point), let entry = entry(at: indexPath) else { return }
            pane.open(entry)
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
            let buffer = typeSelect.type(characters, at: Date())
            let names = pane.entries.map(\.name)
            guard let index = EntryRules.TypeSelect.match(prefix: buffer, in: names) else { return false }
            select(path: pane.entries[index].path)
            return true
        }

        private func select(path: String) {
            guard let collectionView, let indexPath = indexPath(forPath: path) else { return }
            collectionView.selectionIndexPaths = [indexPath]
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
        }

        // MARK: - Inline rename

        func beginRenameIfNeeded() {
            guard model.renaming == pane.id, renamingPath == nil,
                  let path = pane.selection.count == 1 ? pane.selection.first : nil,
                  let indexPath = indexPath(forPath: path),
                  let item = collectionView?.item(at: indexPath) as? IconItem else { return }
            renamingPath = path
            item.beginRename()
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
            if let indexPath = indexPath(forPath: path), let item = collectionView?.item(at: indexPath) as? IconItem {
                item.endRename()
            }
            if model.renaming == pane.id { model.renaming = nil }
            guard commit, let field else { return }
            _ = model.commitRename(path, to: field.stringValue)
        }

        // MARK: - Drag source

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard let entry = entry(at: indexPath) else { return nil }
            let item = NSPasteboardItem()
            item.setString(URL(fileURLWithPath: entry.path).absoluteString, forType: .fileURL)
            return item
        }

        // MARK: - Drop target

        /// Contract: "nhận thả lên biểu tượng thư mục" (FileOctopus 1.0.4 bug) — a drop whose proposed index path
        /// lands `.on` a folder item's cell is accepted into that folder; everything else (between items, or `.on` a
        /// non-folder) falls back to the pane's own current folder, same as the other three views.
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                             proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                             dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            guard draggingInfo.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
            let indexPath = proposedDropIndexPath.pointee as IndexPath
            if proposedDropOperation.pointee == .on, let entry = entry(at: indexPath), entry.isFolderLike {
                return dragOperation(for: draggingInfo)
            }
            proposedDropOperation.pointee = .before
            return dragOperation(for: draggingInfo)
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                             indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            guard let paths = draggedPaths(from: draggingInfo) else { return false }
            let destination: String
            if dropOperation == .on, let entry = entry(at: indexPath), entry.isFolderLike {
                destination = entry.path
            } else {
                destination = pane.path
            }
            model.drop(paths, into: destination, copy: copyFlag(for: draggingInfo))
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

        /// XF-T30 W2: the ONE menu for all four views (contract §3).
        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        /// Right-click on an item outside the current selection re-targets the selection first (contract, same as
        /// `FileListView.populateContextMenu`'s table-row equivalent); a click on empty background, or inside the
        /// existing selection, leaves it alone.
        func retargetSelectionForRightClick(at point: NSPoint) {
            guard let collectionView, let indexPath = collectionView.indexPathForItem(at: point),
                  let clickedEntry = entry(at: indexPath), !pane.selection.contains(clickedEntry.path) else { return }
            collectionView.selectionIndexPaths = [indexPath]
            pushSelectionToModel()
        }
    }
}

extension FileIconView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = BrowserContextMenu.menu(for: model, pane: pane)
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
}
