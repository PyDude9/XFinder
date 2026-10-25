import SwiftUI
import AppKit

/// XF-T30 W2 — Show View Options (⌘J): a floating panel for the active tab — view, icon size, text size, List columns,
/// Group By, Sort By, "Always open in this view", "Use as Defaults". W2 builder (menu).
///
/// One panel per browser window (not per pane): it always shows and edits whichever pane is `model`'s `active` one,
/// following focus changes the same way Finder's own View Options follows the frontmost window's selected view —
/// `toggle(for:)` opens it (or closes it, if it is already open for the SAME model) rather than stacking several.
/// Every control writes through `BrowserWindowModel`/`PaneState` API (contract §4), never a local copy — there is
/// nothing here to keep in sync but the panel's own open/closed state.
@MainActor
final class ViewOptionsPanelController: NSObject, NSWindowDelegate {
    static let shared = ViewOptionsPanelController()

    private static let contentSize = NSSize(width: 280, height: 360)

    private var panel: NSPanel?
    private weak var openModel: BrowserWindowModel?

    private override init() { super.init() }

    /// ⌘J: opens the panel for `model`'s active tab, or closes it if it is already open for this same model
    /// (pressing ⌘J again is the Finder-familiar way to dismiss it).
    func toggle(for model: BrowserWindowModel) {
        if let panel, openModel === model {
            panel.close()
            return
        }
        present(for: model)
    }

    private func present(for model: BrowserWindowModel) {
        panel?.close()
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isReleasedWhenClosed = false
        newPanel.title = L10n.t("Tuỳ chọn xem")
        newPanel.delegate = self
        newPanel.hidesOnDeactivate = false
        let hosting = NSHostingView(rootView: ViewOptionsPanelContent(model: model))
        hosting.sizingOptions = []
        newPanel.contentView = hosting
        newPanel.contentMinSize = Self.contentSize
        newPanel.center()
        panel = newPanel
        openModel = model
        newPanel.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        runOnMainActor { [weak self] in
            guard let self else { return }
            self.panel = nil
            self.openModel = nil
        }
    }
}

/// The panel's own content: view mode, icon/text size (Icon/Gallery), List columns, Group By, Sort By, and the two
/// "remember this" actions — all bound straight to the active pane's `folderPrefs`/model state (contract §4), so the
/// panel itself holds no state of its own beyond "which model it is showing".
private struct ViewOptionsPanelContent: View {
    @Bindable var model: BrowserWindowModel

    private var pane: PaneState { model.active }

    var body: some View {
        Form {
            Picker(L10n.t("Xem dạng"), selection: Binding(
                get: { pane.viewMode },
                set: { newMode in
                    switch newMode {
                    case .icons: _ = model.perform(.viewIcons)
                    case .list: _ = model.perform(.viewList)
                    case .columns: _ = model.perform(.viewColumns)
                    case .gallery: _ = model.perform(.viewGallery)
                    }
                }
            )) {
                Text(L10n.t(BrowserCommands.titleKey(.viewIcons))).tag(BrowserViewMode.icons)
                Text(L10n.t(BrowserCommands.titleKey(.viewList))).tag(BrowserViewMode.list)
                Text(L10n.t(BrowserCommands.titleKey(.viewColumns))).tag(BrowserViewMode.columns)
                Text(L10n.t(BrowserCommands.titleKey(.viewGallery))).tag(BrowserViewMode.gallery)
            }
            .pickerStyle(.segmented)

            if pane.viewMode == .icons || pane.viewMode == .gallery {
                sizeSliders
            }

            if pane.viewMode == .list {
                columnsSection
            }

            Picker(L10n.t("Nhóm theo"), selection: Binding(
                get: { pane.groupBy },
                set: { pane.groupBy = $0 }
            )) {
                ForEach(GroupBy.allCases, id: \.self) { group in
                    Text(L10n.t(group.titleKey)).tag(group)
                }
            }

            Picker(L10n.t("Sắp theo"), selection: Binding(
                get: { pane.sort.key },
                set: { pane.sort = SortOrder(key: $0, ascending: pane.sort.ascending) }
            )) {
                ForEach(SortKey.allCases, id: \.self) { key in
                    Text(L10n.t(sortKeyTitleKey(key))).tag(key)
                }
            }

            Divider()

            Button(L10n.t("Luôn mở theo kiểu này")) {
                model.rememberViewOptionsForFolder()
            }
            Button(L10n.t("Dùng làm mặc định")) {
                model.rememberViewOptionsForFolder()
            }
        }
        .padding()
    }

    private var sizeSliders: some View {
        let prefs = pane.folderPrefs ?? FolderViewPrefs.defaults(viewMode: pane.viewMode)
        return Group {
            Picker(L10n.t("Cỡ biểu tượng"), selection: Binding(
                get: { prefs.iconSize },
                set: { newValue in applyPrefs { $0.iconSize = newValue } }
            )) {
                ForEach(FolderViewPrefs.iconSizes, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
            Picker(L10n.t("Cỡ chữ"), selection: Binding(
                get: { prefs.textSize },
                set: { newValue in applyPrefs { $0.textSize = newValue } }
            )) {
                ForEach(FolderViewPrefs.textSizes, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
        }
    }

    private var columnsSection: some View {
        let prefs = pane.folderPrefs ?? FolderViewPrefs.defaults(viewMode: pane.viewMode)
        return Section(L10n.t("Cột hiện")) {
            ForEach(ListColumn.allCases, id: \.self) { column in
                Toggle(isOn: Binding(
                    get: { prefs.columns.contains(column) },
                    set: { isOn in
                        applyPrefs { current in
                            if isOn {
                                if !current.columns.contains(column) { current.columns.append(column) }
                            } else if column != .name {
                                current.columns.removeAll { $0 == column }
                            }
                        }
                    }
                )) {
                    Text(L10n.t(columnTitleKey(column)))
                }
                .disabled(column == .name)
            }
        }
    }

    private func applyPrefs(_ mutate: (inout FolderViewPrefs) -> Void) {
        var prefs = pane.folderPrefs ?? FolderViewPrefs.defaults(viewMode: pane.viewMode)
        mutate(&prefs)
        pane.folderPrefs = prefs
    }

    private func sortKeyTitleKey(_ key: SortKey) -> String {
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

    private func columnTitleKey(_ column: ListColumn) -> String {
        switch column {
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
}
