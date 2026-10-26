import SwiftUI
import AppKit

/// XF-T32 W3 (contract XF-T32-w23 §G) — the 28 pt strip between the location bar and the content (Tilde: "+ Add
/// related items" on the left, 🔍 · ⋯ · + on the right). Left: "+ Thêm mục liên quan" (folder picker ⇒
/// `metadata.addRelation`), then one pill per related folder (click navigates, context menu "Bỏ liên kết"). Right: 🔍
/// focuses this pane's filter field, ⋯ opens the folder menu (`RowActionsMenu.folderMenu`), + makes a new folder
/// through the existing `.newFolder` command. Every action first makes this pane the active one, because the
/// commands it reuses act on `model.active`.
struct RelatedItemsStrip: View {
    let pane: PaneState
    let model: BrowserWindowModel
    let metadata: BrowserMetadata

    var body: some View {
        // Read `revision` so a relation added/removed anywhere (another pane, another window) re-renders the pills.
        let _: Int = metadata.revision
        let isVirtual: Bool = VirtualLocation.parse(pane.path) != nil
        let related: [String] = isVirtual ? [] : metadata.related(to: pane.path)

        HStack(spacing: XFinderTokens.Space.tight) {
            if !isVirtual {
                RelatedAddButton(action: addRelated)
                if !related.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: XFinderTokens.Space.tight) {
                            ForEach(related, id: \.self) { (path: String) in
                                RelatedPill(path: path,
                                            open: { open(path) },
                                            unlink: { metadata.removeRelation(pane.path, path) })
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            StripIconButton(systemName: "magnifyingglass", help: L10n.t("Bộ lọc"), action: focusFilter)
            FolderMenuButton(help: L10n.t("Tuỳ chọn thư mục")) {
                model.focus(pane.id)
                return RowActionsMenu.folderMenu(pane: pane, model: model)
            }
            .frame(width: XFinderTokens.PaneChrome.stripIconSide, height: XFinderTokens.PaneChrome.stripIconSide)
            if !isVirtual {
                StripIconButton(systemName: "plus", help: L10n.t("Thư mục mới"), action: newFolder)
            }
        }
        .frame(height: XFinderTokens.PaneChrome.stripHeight)
        .padding(.horizontal, XFinderTokens.Space.tight)
    }

    // MARK: Actions

    private func open(_ path: String) {
        model.focus(pane.id)
        guard path != pane.path else { return }
        pane.navigate(to: path)
    }

    private func focusFilter() {
        model.focus(pane.id)
        model.filterFocusRequest = pane.id
    }

    private func newFolder() {
        model.focus(pane.id)
        model.perform(.newFolder)
    }

    /// Folders only (contract). Several at once are allowed; the pane's own folder and folders already related are
    /// skipped, so a repeated pick never duplicates a pill. The source path is captured before the modal runs.
    private func addRelated() {
        model.focus(pane.id)
        let source: String = pane.path
        guard VirtualLocation.parse(source) == nil else { return }
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: (source as NSString).deletingLastPathComponent, isDirectory: true)
        panel.message = L10n.t("Chọn thư mục liên quan tới thư mục này.")
        panel.prompt = L10n.t("Thêm")
        guard panel.runModal() == .OK else { return }
        var existing: Set<String> = Set(metadata.related(to: source))
        for url in panel.urls {
            let picked: String = url.standardizedFileURL.path
            guard !picked.isEmpty, picked != source, !existing.contains(picked) else { continue }
            metadata.addRelation(source, picked)
            existing.insert(picked)
        }
    }
}

// MARK: - Pieces

private struct RelatedAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: XFinderTokens.PaneChrome.componentSpacing) {
                Image(systemName: "plus")
                Text(L10n.t("Thêm mục liên quan"))
                    .lineLimit(1)
            }
            .font(XFinderTokens.Font.rowValue)
            .foregroundColor(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// A related folder: icon + display name in a light capsule; full path as tooltip.
private struct RelatedPill: View {
    let path: String
    let open: () -> Void
    let unlink: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: XFinderTokens.PaneChrome.componentSpacing) {
                Image(nsImage: FileIconCache.shared.icon(forPath: path))
                    .resizable()
                    .frame(width: XFinderTokens.PaneChrome.pathIconSize, height: XFinderTokens.PaneChrome.pathIconSize)
                Text(PaneChromeNameCache.shared.displayName(forPath: path))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, XFinderTokens.Space.tight)
            .padding(.vertical, XFinderTokens.PaneChrome.pillVerticalPadding)
            .background(Capsule().fill(XFinderTokens.Fill.inset))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: XFinderTokens.PaneChrome.pillMaxWidth)
        .help(path)
        .contextMenu {
            Button(L10n.t("Bỏ liên kết"), action: unlink)
        }
    }
}

private struct StripIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.secondary)
                .frame(width: XFinderTokens.PaneChrome.stripIconSide, height: XFinderTokens.PaneChrome.stripIconSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// ⋯ — an `NSMenu` built fresh on every click, popped under the button. `NSMenu.popUp` runs its own tracking loop,
/// so the menu is fully built before it is called (see LocationBarView for the bug that taught this).
private struct FolderMenuButton: NSViewRepresentable {
    let help: String
    let makeMenu: @MainActor () -> NSMenu

    init(help: String, makeMenu: @escaping @MainActor () -> NSMenu) {
        self.help = help
        self.makeMenu = makeMenu
    }

    func makeNSView(context: Context) -> NSButton {
        let image: NSImage? = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: help)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: XFinderTokens.PaneChrome.stripSymbolPointSize,
                                                                 weight: .regular))
        let button: NSButton = NSButton(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = image
        button.title = ""
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        context.coordinator.makeMenu = makeMenu
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.makeMenu = makeMenu
        nsView.toolTip = help
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var makeMenu: (@MainActor () -> NSMenu)?

        @objc func clicked(_ sender: NSButton) {
            guard let makeMenu else { return }
            let menu: NSMenu = makeMenu()
            guard !menu.items.isEmpty else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        }
    }
}

// MARK: - Tokens

/// XF-T32 W3 pane chrome geometry (Tilde measurements, contract §G). Declared here because `XFinderTokens.swift` is
/// owned by another unit in this wave; the integrator may move this block into that file verbatim.
extension XFinderTokens {
    enum PaneChrome {
        /// Bottom breadcrumb bar height.
        static let pathBarHeight: CGFloat = 24
        /// Folder icon per breadcrumb component / related pill.
        static let pathIconSize: CGFloat = 12
        static let componentSpacing: CGFloat = 4
        static let separatorFont: SwiftUI.Font = SwiftUI.Font.system(size: 9, weight: .semibold)
        /// "+ Thêm mục liên quan … 🔍 ⋯ +" strip height.
        static let stripHeight: CGFloat = 28
        static let stripIconSide: CGFloat = 22
        static let stripSymbolPointSize: CGFloat = 12
        static let pillVerticalPadding: CGFloat = 2
        static let pillMaxWidth: CGFloat = 180
        /// Content opacity of an inactive pane when `fileBrowser.paneFocusStyle == "dim"`.
        static let inactivePaneOpacity: Double = 0.55
        /// Settings ▸ General "Làm nổi ngăn đang dùng" menu width (fits "Viền ngăn đang dùng" / "Outline the active pane").
        static let focusPickerWidth: CGFloat = 200
    }
}
