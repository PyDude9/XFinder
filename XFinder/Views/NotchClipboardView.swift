import SwiftUI
import AppKit

/// State of the notch's clipboard page (B5). Owned by `NotchSurfaceController` so the keyboard
/// handler and the view share one selection.
@MainActor
@Observable
final class NotchClipboardModel {
    /// Free text plus `@type` / `@app` tokens (`ClipboardFilterToken`).
    var query = ""
    var selectedID: UUID?
    /// nil ⇒ the full history; a custom board id ⇒ only that board's items.
    var boardID: UUID?
    /// One-line result of the last action (a store key), e.g. a transform that changed nothing.
    var notice: String?

    /// The deck: newest first, capped — this page is a glance at recent clips, the ⌘⇧V shelf is
    /// the place to dig. Filtering is applied here, in front of ClipboardManager's own filters,
    /// so typing in the notch never changes what the shelf shows.
    func items(from manager: ClipboardManager) -> [ClipboardRecord] {
        let parsed = ClipboardFilterToken.parse(query)
        var list = manager.history
        if let id = boardID, let board = manager.pinboards.first(where: { $0.id == id }), !board.isBuiltIn {
            let ids = Set(board.itemIDs)
            list = list.filter { ids.contains($0.id) }
        }
        if let t = parsed.type { list = list.filter { $0.type == t } }
        if parsed.app != nil {
            list = list.filter { ClipboardFilterToken.appMatches(token: parsed.app, appName: $0.sourceAppName, bundleID: $0.sourceBundleID) }
        }
        if !parsed.text.isEmpty {
            let q = parsed.text
            list = list.filter { r in
                (r.textSnippet?.localizedCaseInsensitiveContains(q) ?? false)
                    || (r.ocrText?.localizedCaseInsensitiveContains(q) ?? false)
                    || (r.customTitle?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        return Array(list.sorted { $0.timestamp > $1.timestamp }.prefix(30))
    }

    func moveSelection(_ delta: Int, in items: [ClipboardRecord]) {
        guard !items.isEmpty else { return }
        let i = items.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(i + delta, 0), items.count - 1)
        selectedID = items[next].id
    }
}

/// The clipboard page inside the notch hub: search with `@filter`, board picker, a horizontal deck
/// of the existing `ClipboardCardView`, and the Paste Stack line. Click pastes into the app the
/// user came from; ⌘-click adds to the stack; right-click offers Transform / Đi tới nguồn.
struct NotchClipboardView: View {
    var model: NotchClipboardModel
    @State private var manager = ClipboardManager.shared
    @FocusState private var searchFocused: Bool

    private var items: [ClipboardRecord] { model.items(from: manager) }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight + 2) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "magnifyingglass").font(XFinderTokens.Font.caption).opacity(0.65)
                TextField(L10n.t("Tìm, hoặc @ảnh @link @tênapp…"), text: Bindable(model).query)
                    .textFieldStyle(.plain)
                    .font(XFinderTokens.Font.rowValue)
                    .focused($searchFocused)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").opacity(0.65) }
                        .buttonStyle(.plain)
                }
                boardMenu
            }
            .padding(.horizontal, XFinderTokens.Space.tight + 2).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.white.opacity(0.10)))

            if items.isEmpty {
                Text(manager.history.isEmpty ? L10n.t("Chưa có gì trong clipboard.") : L10n.t("Không có mục nào khớp."))
                    .font(XFinderTokens.Font.caption).opacity(0.65)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: XFinderTokens.Space.tight + 2) {
                            ForEach(items) { record in
                                card(record)
                                    .id(record.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: model.selectedID) { _, id in if let id { withAnimation { proxy.scrollTo(id) } } }
                }
            }

            bottomLine
        }
        .environment(manager)
        .onAppear { searchFocused = true }
    }

    private var boardMenu: some View {
        Menu {
            Button(L10n.t("Toàn bộ lịch sử")) { model.boardID = nil }
            ForEach(manager.pinboards.filter { !$0.isBuiltIn }) { b in
                Button(b.name) { model.boardID = b.id }
            }
        } label: {
            Image(systemName: "square.grid.2x2").font(XFinderTokens.Font.caption).opacity(0.8)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help(L10n.t("Bảng ghim"))
    }

    private func card(_ record: ClipboardRecord) -> some View {
        let inStack = manager.pasteStack.items.contains(record)
        return ClipboardCardView(record: record, selected: model.selectedID == record.id,
                                 onSelect: { select(record) },
                                 onPreview: { NotchSurfaceController.shared.pasteFromClipboardPage(record) })
            .frame(width: 150, height: 112)
            .overlay(alignment: .topTrailing) {
                if inStack {
                    Image(systemName: "square.stack.3d.up.fill").font(XFinderTokens.Font.caption)
                        .padding(4).background(Circle().fill(Color.accentColor)).foregroundColor(.white)
                        .offset(x: 4, y: -4)
                }
            }
            .contextMenu { contextMenu(record) }
    }

    /// Plain click pastes; ⌘-click toggles the Paste Stack membership.
    private func select(_ record: ClipboardRecord) {
        model.selectedID = record.id
        if NSEvent.modifierFlags.contains(.command) {
            manager.togglePasteStackItem(record)
        } else {
            NotchSurfaceController.shared.pasteFromClipboardPage(record)
        }
    }

    @ViewBuilder private func contextMenu(_ record: ClipboardRecord) -> some View {
        Button(L10n.t("Dán")) { NotchSurfaceController.shared.pasteFromClipboardPage(record) }
        Button(manager.pasteStack.items.contains(record) ? L10n.t("Bỏ khỏi Paste Stack") : L10n.t("Thêm vào Paste Stack")) {
            manager.togglePasteStackItem(record)
        }
        if let text = record.textSnippet, !text.isEmpty, record.type != .image, record.type != .file {
            Menu(L10n.t("Biến đổi")) {
                ForEach(Array(ClipboardTransform.groups.enumerated()), id: \.offset) { i, group in
                    ForEach(group) { t in
                        Button(L10n.t(t.labelKey)) { NotchSurfaceController.shared.applyTransform(t, to: record) }
                    }
                    if i < ClipboardTransform.groups.count - 1 { Divider() }
                }
                Divider()
                let s = ClipboardTransform.stats(text)
                Text("\(s.words)\(L10n.t(" từ · "))\(s.characters)\(L10n.t(" ký tự · "))\(s.lines)\(L10n.t(" dòng"))")
            }
        }
        Divider()
        // "Đi tới nguồn" — one row per thing that is actually known about this record.
        if let bid = record.sourceBundleID, !bid.isEmpty {
            Button("\(L10n.t("Mở "))\(record.sourceAppName ?? bid)") { NotchSurfaceController.shared.openSourceApp(bundleID: bid) }
        }
        if let url = sourcePage(record) {
            Button(L10n.t("Mở trang nguồn")) { NSWorkspace.shared.open(url) }
        }
        if let path = record.payloadPath ?? record.metadata["path"], record.type == .file || record.type == .image,
           FileManager.default.fileExists(atPath: path), !path.contains("/XFinder/") {
            Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        }
    }

    /// The page a clip came from: the link itself for a copied URL, or the browser-reported source
    /// (Chromium's `org.chromium.source-url`, captured at copy time). Nothing is guessed.
    private func sourcePage(_ r: ClipboardRecord) -> URL? {
        for key in ["sourceURL", "url"] {
            if let s = r.metadata[key], !s.isEmpty, let u = URL(string: s), ["http", "https"].contains(u.scheme ?? "") { return u }
        }
        return nil
    }

    @ViewBuilder private var bottomLine: some View {
        if manager.pasteStack.active {
            HStack(spacing: XFinderTokens.Space.tight + 2) {
                Image(systemName: "square.stack.3d.up.fill").font(XFinderTokens.Font.caption).foregroundColor(.accentColor)
                Text("Paste Stack · \(L10n.t("Còn lại")): \(manager.pasteStack.remaining)").font(XFinderTokens.Font.caption)
                Text(NotchSurfaceController.shared.pasteStackInterceptsCommandV
                     ? L10n.t("Mỗi ⌘V dán mục kế tiếp.")
                     : L10n.t("Bấm Dán tiếp để dán từng mục."))
                    .font(XFinderTokens.Font.caption).opacity(0.65).lineLimit(1)
                Spacer()
                Button(L10n.t("Dán tiếp")) { NotchSurfaceController.shared.pasteNextFromStack() }
                    .buttonStyle(.bordered).controlSize(.mini)
                Button(L10n.t("Hủy")) { manager.stopPasteStack() }
                    .buttonStyle(.plain).font(XFinderTokens.Font.caption).opacity(0.65)
            }
        } else if let n = model.notice {
            Text(L10n.t(n)).font(XFinderTokens.Font.caption).opacity(0.65).lineLimit(1)
        } else {
            Text(L10n.t("Bấm để dán · ⌘-bấm để xếp vào Paste Stack · chuột phải để biến đổi"))
                .font(XFinderTokens.Font.caption).opacity(0.5).lineLimit(1)
        }
    }
}
