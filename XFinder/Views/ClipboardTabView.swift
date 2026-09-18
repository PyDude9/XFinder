import AppKit
import QuickLookUI
import SwiftUI

/// Clipboard page — PasteApp-style card deck with:
/// - app-icon accent headers + per-type card bodies (text/code/image/link/color/file)
/// - keyboard nav (←/→, Return paste, ⇧Return plain, ⌘1-9 boards, ⌘P pin, ⌘F search, ⌘⌫ delete, Esc)
/// - Space Quick Look (QLPreviewPanel), drag-to-tab pinning, Paste Stack HUD
struct ClipboardTabView: View {
    @Environment(ClipboardManager.self) var clipboardManager
    @FocusState private var searchFocused: Bool
    @State private var keyMonitor: Any?
    @State private var qlController: ClipboardQLController?
    @State private var showAccessAlert = false

    private var items: [ClipboardRecord] { clipboardManager.boardItems() }

    var body: some View {
        VStack(spacing: 0) {
            ClipboardPinboardBar(showAccessAlert: $showAccessAlert)
                .environment(clipboardManager)

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                // `@Bindable` is how Observation hands out a Binding for an
                // `@Observable` object — `@Environment` alone has no `$`.
                TextField(L10n.t("Tìm kiếm (⌘F) — gồm chữ trong ảnh OCR…"),
                          text: Bindable(clipboardManager).searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !clipboardManager.searchText.isEmpty {
                    Button { clipboardManager.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if clipboardManager.pasteStack.active {
                    PasteStackHUD()
                        .environment(clipboardManager)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            if items.isEmpty {
                ClipboardEmptyView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 12) {
                            ForEach(items) { record in
                                ClipboardCardView(
                                    record: record,
                                    selected: clipboardManager.selectedItemID == record.id,
                                    onPreview: { preview(record) }
                                )
                                .frame(width: 250, height: 320)
                                .id(record.id)
                                .onTapGesture {
                                    clipboardManager.selectedItemID = record.id
                                }
                                .onDrag { NSItemProvider(object: record.id.uuidString as NSString) }
                                .contextMenu {
                                    Button(L10n.t("Dán (Return)")) { pasteSelected(plainText: false) }
                                    Button(L10n.t("Dán dạng text thuần (⇧Return)")) { pasteSelected(plainText: true) }
                                    if let rec = items.first(where: { $0.id == clipboardManager.selectedItemID }),
                                       let ocr = rec.ocrText, !ocr.isEmpty {
                                        Button(L10n.t("Sao chép chữ OCR trong ảnh")) {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(ocr, forType: .string)
                                        }
                                    }
                                    Button(L10n.t("Ghim vào bảng hiện tại (⌘P)")) { pinSelected() }
                                    Button("Xem nhanh (Space)") { preview(record) }
                                    Divider()
                                    Button(L10n.t("Xóa (⌘⌫)"), role: .destructive) { deleteSelected() }
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 16)
                    }
                    .onChange(of: clipboardManager.selectedItemID) {
                        if let id = clipboardManager.selectedItemID {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }

            // Bottom hint bar (keyboard map)
            HStack(spacing: 12) {
                Text(L10n.t("←/→ chọn · Return dán · ⇧Return dán thuần · Space xem · ⌘P ghim · ⌘1-9 bảng · Esc"))
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                if !WindowManager.isTrusted {
                    Button(L10n.t("Bật Dán phím (cần Trợ năng)…")) { showAccessAlert = true }
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(.controlBackgroundColor).opacity(0.5))
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            installKeyMonitor()
            if clipboardManager.selectedItemID == nil {
                clipboardManager.selectedItemID = items.first?.id
            }
        }
        .onDisappear { removeKeyMonitor() }
        .alert(L10n.t("Cần quyền Trợ năng để dán phím"), isPresented: $showAccessAlert) {
            Button(L10n.t("Mở Cài đặt Trợ năng")) { WindowManager.openAccessibilityPane() }
            Button(L10n.t("Để sau"), role: .cancel) {}
        } message: {
            Text(L10n.t("XFinder sẽ ghi nội dung vào clipboard, chuyển tới ứng dụng trước đó và mô phỏng ⌘V. Sao chép vào clipboard vẫn dùng được (bấm \"Sao chép\" trong menu chuột phải)."))
        }
    }

    // MARK: - Keyboard (guide §4 table)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard handleKey(event) else { return event }
            return nil // swallowed
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    /// Returns true when the key was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let chars = event.charactersIgnoringModifiers ?? ""

        // ⌘F focus search / ⌘P pin / ⌘1-9 boards / ⌘⌫ delete / Esc
        if flags == .command, chars == "f" { searchFocused = true; return true }
        if flags == .command, chars == "p" { pinSelected(); return true }
        if flags == .command, chars == "\u{7f}" { deleteSelected(); return true }
        if flags == .command, let n = Int(chars), (1...9).contains(n) {
            let boards = clipboardManager.pinboards
            if n <= boards.count { clipboardManager.currentPinboardID = boards[n - 1].id }
            return true
        }
        // Return / ⇧Return paste
        if flags.isEmpty, event.keyCode == 36 { pasteSelected(plainText: false); return true }
        if flags == .shift, event.keyCode == 36 { pasteSelected(plainText: true); return true }
        // Space Quick Look
        if flags.isEmpty, event.keyCode == 49 {
            if let rec = selected() { preview(rec) }
            return true
        }
        // ←/→ selection walk
        if flags.isEmpty, event.keyCode == 123 { moveSelection(by: -1); return true }
        if flags.isEmpty, event.keyCode == 124 { moveSelection(by: 1); return true }
        // Esc: clear search first, else deselect
        if flags.isEmpty, event.keyCode == 53 {
            if !clipboardManager.searchText.isEmpty { clipboardManager.searchText = "" }
            else { clipboardManager.selectedItemID = nil }
            return true
        }
        return false
    }

    // MARK: - Actions

    private func selected() -> ClipboardRecord? {
        items.first(where: { $0.id == clipboardManager.selectedItemID }) ?? items.first
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let cur = items.firstIndex(where: { $0.id == clipboardManager.selectedItemID }) ?? 0
        let next = min(max(cur + delta, 0), items.count - 1)
        clipboardManager.selectedItemID = items[next].id
    }

    private func pasteSelected(plainText: Bool) {
        guard let rec = selected() else { return }
        // Paste Stack: pop next queued item into clipboard+target app.
        if clipboardManager.pasteStack.active, let next = clipboardManager.pasteStack.popNext() {
            pasteRecord(next, plainText: plainText)
            return
        }
        pasteRecord(rec, plainText: plainText)
    }

    private func pasteRecord(_ rec: ClipboardRecord, plainText: Bool) {
        // Without trust: copy-back fallback (honest, no fake keystroke).
        guard WindowManager.isTrusted else {
            ClipboardPasteEngine.writeToPasteboard(record: rec, plainText: plainText)
            showAccessAlert = true
            return
        }
        ClipboardPasteEngine.paste(record: rec,
                                   to: clipboardManager.lastExternalPID,
                                   plainText: plainText)
    }

    private func pinSelected() {
        guard let rec = selected(), let board = clipboardManager.currentPinboardID else { return }
        clipboardManager.addItemToPinboard(rec.id, pinboardID: board)
    }

    private func deleteSelected() {
        guard let rec = selected() else { return }
        clipboardManager.deleteRecord(rec.id)
    }

    private func preview(_ record: ClipboardRecord) {
        // Image/file with a payload file → native QL panel; else inline popover text.
        if let path = record.payloadPath ?? record.thumbnailPath,
           FileManager.default.fileExists(atPath: path) {
            if qlController == nil { qlController = ClipboardQLController() }
            qlController?.present(url: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Pinboard tab bar (⌘1-9, drag-to-tab, counts)

private struct ClipboardPinboardBar: View {
    @Environment(ClipboardManager.self) var clipboardManager
    @Binding var showAccessAlert: Bool
    @State private var showCreateSheet = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(clipboardManager.pinboards.enumerated()), id: \.element.id) { idx, board in
                        let active = clipboardManager.currentPinboardID == board.id
                        VStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Circle().fill(board.color.color).frame(width: 8, height: 8)
                                Image(systemName: board.icon).font(.caption)
                                Text(board.name)
                                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                                    .foregroundColor(active ? .white : board.color.color)
                                Text("\(count(for: board))")
                                    .font(.caption2).foregroundColor(.secondary)
                                if idx < 9 {
                                    Text("⌘\(idx + 1)").font(.caption2).foregroundColor(.secondary.opacity(0.7))
                                }
                            }
                            .foregroundColor(active ? .white : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(active ? board.color.color : Color.clear)
                            .cornerRadius(4)
                            .onTapGesture { clipboardManager.currentPinboardID = board.id }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                for p in providers {
                                    _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                                        if let s = obj as? String, let id = UUID(uuidString: s) {
                                            Task { @MainActor in
                                                clipboardManager.addItemToPinboard(id, pinboardID: board.id)
                                            }
                                        }
                                    }
                                }
                                return true
                            }
                            if active { board.color.color.frame(height: 3) }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 8)
            }
            Button { showCreateSheet = true } label: {
                Image(systemName: "plus.circle").imageScale(.large).foregroundColor(.secondary)
            }
            .buttonStyle(.plain).padding(.horizontal, 12)
            .help(L10n.t("Tạo bảng ghim mới"))
            Spacer()
        }
        .frame(height: 44)
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $showCreateSheet) {
            CreatePinboardSheet().environment(clipboardManager)
        }
    }

    private func count(for board: Pinboard) -> Int {
        board.isBuiltIn ? clipboardManager.history.count : board.itemIDs.count
    }
}

private struct CreatePinboardSheet: View {
    @Environment(ClipboardManager.self) var clipboardManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var selectedColor = Color.blue

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.t("Tạo bảng ghim")).font(.title2).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.t("Tên"), systemImage: "textformat")
                TextField(L10n.t("Tên bảng"), text: $name).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.t("Màu"), systemImage: "paintbrush")
                HStack {
                    ForEach([Color.blue, Color.green, Color.purple, Color.orange, Color.red, Color.pink], id: \.self) { c in
                        Circle().fill(c).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(selectedColor == c ? Color.white : Color.clear, lineWidth: 2))
                            .onTapGesture { selectedColor = c }
                    }
                    Spacer()
                }
            }
            HStack(spacing: 12) {
                Spacer()
                Button(L10n.t("Hủy"), role: .cancel) { dismiss() }
                Button(L10n.t("Tạo")) {
                    clipboardManager.createPinboard(name: name.isEmpty ? L10n.t("Bảng mới") : name, color: selectedColor)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .padding().frame(minWidth: 400, minHeight: 300)
    }
}

// MARK: - Paste Stack HUD

private struct PasteStackHUD: View {
    @Environment(ClipboardManager.self) var clipboardManager
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill").font(.caption).foregroundColor(.accentColor)
            Text("Stack: \(clipboardManager.pasteStack.remaining)")
                .font(.caption).fontWeight(.medium)
            Button(L10n.t("Hủy")) { clipboardManager.stopPasteStack() }
                .font(.caption2).buttonStyle(.plain).foregroundColor(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12)).cornerRadius(8)
        .help(L10n.t("Paste Stack đang hoạt động — mỗi lần Dán lấy mục tiếp theo. Bấm Hủy để dừng."))
    }
}

private struct ClipboardEmptyView: View {
    var body: some View {
        VStack {
            Image(systemName: "clipboard").font(.system(size: 48))
                .foregroundColor(.secondary).padding(.bottom, 16)
            Text(L10n.t("Chưa có mục nào")).font(.headline).foregroundColor(.secondary)
            Text(L10n.t("Nội dung bạn sao chép sẽ hiện ở đây (ứng dụng mật khẩu và nội dung nhạy cảm được bỏ qua)"))
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Quick Look controller for clipboard payloads

final class ClipboardQLController: NSObject, QLPreviewPanelDataSource {
    private var url: URL?
    func present(url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
        panel.reloadData()
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as QLPreviewItem?
    }
}
