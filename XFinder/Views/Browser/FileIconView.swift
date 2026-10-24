import AppKit
import SwiftUI

/// XF-T28 cluster D — Biểu tượng (NSCollectionView, flow layout). Same selection/drag/drop/menu/type-select rules
/// as `FileListView`, but a grid of icon + 2-line middle-truncated name. AppKit for the same reason: 100 000 items
/// must reuse cells (`NSCollectionView`'s own item-reuse pool), which a SwiftUI `LazyVGrid` inside a `ScrollView`
/// does not do for anything approaching that count.
struct FileIconView: NSViewRepresentable {
    let pane: PaneState
    let model: BrowserWindowModel

    static let itemSize = NSSize(width: 96, height: 96)
    static let thumbnailSide: CGFloat = 64

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = Self.itemSize
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
    /// handling, same reasoning as `FileListView.KeyRoutingTableView`.
    final class KeyRoutingCollectionView: NSCollectionView {
        weak var coordinator: Coordinator?
        override func keyDown(with event: NSEvent) {
            if coordinator?.handleKeyDown(event) == true { return }
            super.keyDown(with: event)
        }
    }

    /// One grid cell: icon (or thumbnail for images, fetched lazily only while visible) + a 2-line
    /// middle-truncated name below it.
    final class IconItem: NSCollectionViewItem {
        static let identifier = NSUserInterfaceItemIdentifier("FileIconView.IconItem")
        private let nameField = NSTextField(labelWithString: "")
        private var renamingField: NSTextField?
        weak var coordinator: Coordinator?
        private(set) var path: String?

        override func loadView() {
            let container = NSView()
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)
            self.imageView = imageView

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
                imageView.widthAnchor.constraint(equalToConstant: FileIconView.thumbnailSide),
                imageView.heightAnchor.constraint(equalToConstant: FileIconView.thumbnailSide),
                nameField.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
                nameField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
                nameField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            ])
            view = container
        }

        override var isSelected: Bool {
            didSet { view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).cgColor : nil }
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.wantsLayer = true
            view.layer?.cornerRadius = 8
        }

        func configure(entry: DirectoryEntry, coordinator: Coordinator) {
            self.coordinator = coordinator
            path = entry.path
            nameField.stringValue = entry.name
            imageView?.image = FileIconCache.shared.icon(for: entry)
            if entry.kind == .file, Self.isImageExtension(entry.ext) {
                let side = FileIconView.thumbnailSide
                FileIconCache.shared.thumbnail(forPath: entry.path, side: side, scale: 2) { [weak self] image in
                    guard let self, self.path == entry.path, let image else { return }
                    self.imageView?.image = image
                }
            }
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

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout, NSTextFieldDelegate {
        var pane: PaneState
        var model: BrowserWindowModel
        weak var collectionView: NSCollectionView?

        private var lastCount = -1
        private var lastFirstID: String?
        private var lastLastID: String?
        private var isSyncingSelection = false
        private var typeSelect = EntryRules.TypeSelect()
        private var renamingPath: String?
        /// Last `pane.selection` this coordinator pushed into/read from the grid, so `syncSelection()` can skip its
        /// O(entries.count) scan on an `updateNSView` call where selection did not change (contract: "no O(n) work
        /// per updateNSView/frame"). Cleared by `reloadIfNeeded()` since a reload can move the same paths to new
        /// index paths (e.g. a resort) even though the selected path set itself stays the same.
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
                lastSyncedSelection = []
                collectionView?.reloadData()
            }
        }

        // MARK: - Selection (two-way)

        func syncSelection() {
            guard let collectionView, !isSyncingSelection else { return }
            guard pane.selection != lastSyncedSelection else { return }
            let wanted = pane.selection
            var indexPaths = Set<IndexPath>()
            for (index, entry) in pane.entries.enumerated() where wanted.contains(entry.path) {
                indexPaths.insert(IndexPath(item: index, section: 0))
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
            let paths = collectionView.selectionIndexPaths.compactMap { indexPath -> String? in
                guard indexPath.item < pane.entries.count else { return nil }
                return pane.entries[indexPath.item].path
            }
            let selection = Set(paths)
            pane.selection = selection
            lastSyncedSelection = selection
            isSyncingSelection = false
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { pushSelectionToModel() }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { pushSelectionToModel() }

        // MARK: - NSCollectionViewDataSource

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { pane.entries.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: IconItem.identifier, for: indexPath)
            guard let iconItem = item as? IconItem, indexPath.item < pane.entries.count else { return item }
            iconItem.configure(entry: pane.entries[indexPath.item], coordinator: self)
            return iconItem
        }

        // MARK: - Double-click / Return / type-select

        @objc func doubleClicked(_ sender: NSClickGestureRecognizer) {
            guard let collectionView else { return }
            let point = sender.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < pane.entries.count else { return }
            pane.open(pane.entries[indexPath.item])
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
            select(itemAt: index)
            return true
        }

        private func select(itemAt index: Int) {
            guard let collectionView, index >= 0, index < pane.entries.count else { return }
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.selectionIndexPaths = [indexPath]
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
        }

        // MARK: - Inline rename

        func beginRenameIfNeeded() {
            guard model.renaming == pane.id, renamingPath == nil,
                  let path = pane.selection.count == 1 ? pane.selection.first : nil,
                  let index = pane.entries.firstIndex(where: { $0.path == path }),
                  let item = collectionView?.item(at: IndexPath(item: index, section: 0)) as? IconItem else { return }
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
            if let index = pane.entries.firstIndex(where: { $0.path == path }),
               let item = collectionView?.item(at: IndexPath(item: index, section: 0)) as? IconItem {
                item.endRename()
            }
            if model.renaming == pane.id { model.renaming = nil }
            guard commit, let field else { return }
            _ = model.commitRename(path, to: field.stringValue)
        }

        // MARK: - Drag source

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard indexPath.item < pane.entries.count else { return nil }
            let item = NSPasteboardItem()
            item.setString(URL(fileURLWithPath: pane.entries[indexPath.item].path).absoluteString, forType: .fileURL)
            return item
        }

        // MARK: - Drop target

        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                             proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                             dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            guard draggingInfo.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
            let index = proposedDropIndexPath.pointee.item
            if proposedDropOperation.pointee == .on, index >= 0, index < pane.entries.count, pane.entries[index].isFolderLike {
                return dragOperation(for: draggingInfo)
            }
            proposedDropOperation.pointee = .before
            return dragOperation(for: draggingInfo)
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                             indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            guard let paths = draggedPaths(from: draggingInfo) else { return false }
            let destination: String
            if dropOperation == .on, indexPath.item < pane.entries.count, pane.entries[indexPath.item].isFolderLike {
                destination = pane.entries[indexPath.item].path
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

extension FileIconView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        populateContextMenu(menu)
    }
}
