import SwiftUI
import AppKit

/// Ghi chú — real note browser over NoteStore (shared with SideNotesPanel and
/// the menubar flyout). Grid of note cards with search, color filter, pin /
/// archive, and the same editor sheet (Save actually persists).
struct NotesDetailView: View {
    @State private var store = NoteStore.shared
    /// Master switch in the page header — same key the edge panel reads.
    @AppStorage("notes.edgeEnabled") private var edgeEnabled = false
    @AppStorage("notes.font") private var noteFont = "system"
    @State private var searchText = ""
    @State private var showArchived = false
    @State private var selectedColorName: String? = nil
    @State private var showCreateSheet = false
    @State private var editingNote: QuickNote? = nil
    @State private var showCreateSheetForEdit = false
    @State private var importError: String? = nil

    private var visible: [QuickNote] {
        store.notes.filter { note in
            if note.isArchived != showArchived { return false }
            if let c = selectedColorName,
               CodableColor.presetName(for: note.color) != c { return false }
            if !searchText.isEmpty {
                let hit = note.content.localizedCaseInsensitiveContains(searchText)
                    || (note.title?.localizedCaseInsensitiveContains(searchText) ?? false)
                if !hit { return false }
            }
            return true
        }
        .sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    /// Settings only. Notes themselves are read and edited in the screen-edge
    /// panel (hover a screen edge), so duplicating the grid here would just
    /// take space and split the same feature across two places.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: "note.text",
                    title: L10n.t("Ghi chú"),
                    subtitle: L10n.t("Lưu ghi chú, danh sách công việc và ý tưởng ngay mép màn hình."),
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(edgeEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Toggle("", isOn: $edgeEnabled)
                                .labelsHidden()
                                .onChange(of: edgeEnabled) {
                                    EdgeNotesController.shared.applySettings()
                                }
                        }
                    ))

                summaryRow
                filterRow
                notesGrid
                Divider().padding(.horizontal, 20)
                EdgeNotesSettingsCard()
                AppearanceCard()
                ShortcutsCard()
                ImportExportCard(importError: $importError)
            }
            .padding(.vertical, 16)
        }
        .background(Color(.windowBackgroundColor))
        .onChange(of: store.pendingNewNote) { _, newValue in
            if newValue { store.pendingNewNote = false; showCreateSheet = true }
        }
        .sheet(isPresented: $showCreateSheet) {
            NoteEditorSheet(isPresented: $showCreateSheet, note: nil)
        }
        .sheet(isPresented: $showCreateSheetForEdit) {
            if let n = editingNote {
                NoteEditorSheet(isPresented: $showCreateSheetForEdit, note: n)
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text").foregroundColor(.accentColor).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.notes.filter { !$0.isArchived }.count)\(L10n.t(" ghi chú đang dùng"))")
                    .font(.system(size: 13))
                Text("\(store.notes.filter(\.isArchived).count)\(L10n.t(" đã lưu trữ"))")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: $noteFont) {
                ForEach(NoteStore.NoteFont.allCases) { f in Text(f.titleVI).tag(f.rawValue) }
            }
            .pickerStyle(.menu).frame(width: 110)
            Button(L10n.t("Ghi chú mới")) { showCreateSheet = true }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 20)
    }

    private var header: some View {
        HStack {
            Text(L10n.t("Ghi chú"))
                .font(.system(size: 22, weight: .bold))
            Text("\(store.notes.filter { !$0.isArchived }.count)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            Spacer()
            Button(L10n.t("Ghi chú mới")) { showCreateSheet = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var filterRow: some View {
        filterBar
            .padding(.horizontal, 20)
    }

    private var notesGrid: some View {
        Group {
            if visible.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(visible) { note in
                        BrowserNoteCard(note: note,
                                        onEdit: { editingNote = note; showCreateSheetForEdit = true },
                                        onPin: { store.togglePin(note) },
                                        onArchive: { store.toggleArchive(note) },
                                        onDelete: { store.delete(note) })
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                TextField(L10n.t("Tìm ghi chú…"), text: $searchText)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(.controlBackgroundColor).opacity(0.7))
            .cornerRadius(6)
            .frame(maxWidth: 260)

            Picker(L10n.t("Màu"), selection: $selectedColorName) {
                Text(L10n.t("Mọi màu")).tag(nil as String?)
                ForEach(CodableColor.presetNames, id: \.self) { name in
                    Text(name).tag(name as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Picker("", selection: $showArchived) {
                Text(L10n.t("Đang dùng")).tag(false)
                Text(L10n.t("Lưu trữ")).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text").font(.system(size: 36)).foregroundColor(.secondary)
            Text(showArchived ? L10n.t("Không có ghi chú lưu trữ") : L10n.t("Chưa có ghi chú"))
                .font(.headline)
            Text(L10n.t("Bấm “Ghi chú mới” để tạo ghi chú đầu tiên."))
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EdgeNotesSettingsCard: View {
    @AppStorage("notes.edgeSide") private var edgeSide = "Right"
    @AppStorage("notes.edgeHotspot") private var edgeHotspot = 12.0
    @AppStorage("notes.fullscreen") private var showFullscreen = false
    @AppStorage("notes.hideOnLeave") private var hideOnLeave = true
    @State private var store = NoteStore.shared

    var body: some View {
        SettingsCard(title: L10n.t("Ghi chú ở mép màn hình"),
                     subtitle: store.notes.isEmpty
                         ? L10n.t("Dải mép chỉ hiện khi có ít nhất một ghi chú.")
                         : L10n.t("Di chuột tới mép màn hình để mở ghi chú.")) {
            VStack(spacing: 10) {
                Picker(L10n.t("Cạnh màn hình"), selection: $edgeSide) {
                    Text(L10n.t("Trái")).tag("Left")
                    Text(L10n.t("Phải")).tag("Right")
                }
                .pickerStyle(.segmented)
                .onChange(of: edgeSide) { EdgeNotesController.shared.applySettings() }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(L10n.t("Độ nhạy vùng chạm "))\(Int(edgeHotspot)) pt")
                        .font(.system(size: 13, weight: .medium))
                    Slider(value: $edgeHotspot, in: 4...40, step: 1)
                        .onChange(of: edgeHotspot) { EdgeNotesController.shared.applySettings() }
                }
                ToggleRow(title: L10n.t("Hiện trên ứng dụng toàn màn hình"),
                          subtitle: "Best-effort qua .stationary",
                          isOn: $showFullscreen)
                    .onChange(of: showFullscreen) { EdgeNotesController.shared.applySettings() }
                ToggleRow(title: L10n.t("Ẩn khi con trỏ rời khỏi"), isOn: $hideOnLeave)
                    .onChange(of: hideOnLeave) { EdgeNotesController.shared.applySettings() }
                if store.notes.isEmpty {
                    Text(L10n.t("Chưa có ghi chú — dải mép đang ẩn. Tạo ghi chú đầu tiên để dùng."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct AppearanceCard: View {
    @AppStorage("notes.font") private var noteFont = "system"
    @State private var store = NoteStore.shared

    var body: some View {
        SettingsCard(title: L10n.t("Giao diện ghi chú"),
                     subtitle: L10n.t("Markdown và danh sách công việc vẫn chỉnh sửa được dưới dạng văn bản thuần.")) {
            VStack(spacing: 10) {
                HStack {
                    Text(L10n.t("Phông chữ")).font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $noteFont) {
                        ForEach(NoteStore.NoteFont.allCases) { f in Text(f.titleVI).tag(f.rawValue) }
                    }
                    .pickerStyle(.menu).frame(width: 120)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(L10n.t("Cỡ chữ")) \(String(format: "%.1f", store.fontSize)) pt")
                        .font(.system(size: 13))
                    Slider(value: Binding(
                        get: { store.fontSize },
                        set: { store.setFontSize($0) }
                    ), in: 11...20, step: 0.5)
                }
                ToggleRow(title: L10n.t("Định dạng Markdown khi nhập"), isOn: Binding(
                    get: { store.markdownEnabled },
                    set: { store.markdownEnabled = $0 }
                ))
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct ShortcutsCard: View {
    var body: some View {
        SettingsCard(title: L10n.t("Phím tắt"),
                     subtitle: L10n.t("Mở ghi chú từ bất kỳ ứng dụng nào.")) {
            VStack(spacing: 8) {
                shortcutRow(L10n.t("Ghi chú mới"), keys: "⌥⌘N")
                shortcutRow(L10n.t("Tất cả ghi chú"), keys: "⌥⌘A")
                shortcutRow(L10n.t("Ghi chú đã lưu trữ"), keys: "⌥⌘L")
                Text(L10n.t("Trong ghi chú: ⌘T ô đánh dấu · ⌘F tìm · ⌘P ghim · Esc đóng"))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    private func shortcutRow(_ label: String, keys: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            Text(keys)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct ImportExportCard: View {
    @Binding var importError: String?
    @State private var store = NoteStore.shared

    var body: some View {
        SettingsCard(title: L10n.t("Nhập / Xuất ghi chú")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Menu(L10n.t("Nhập…")) {
                        Button("Markdown (.md)") { pickImport(["md", "markdown"]) { store.importMarkdown($0) } }
                        Button(L10n.t("Văn bản (.txt)")) { pickImport(["txt"]) { store.importText($0) } }
                        Button("JSON") { importJSON() }
                    }
                    .fixedSize()
                    Menu(L10n.t("Xuất…")) {
                        Button("Markdown (.md)") { saveText("xnotes.md", store.exportMarkdown()) }
                        Button(L10n.t("Văn bản (.txt)")) { saveText("xnotes.txt", store.exportText()) }
                        Button("JSON") { exportJSON() }
                    }
                    .fixedSize()
                    Spacer()
                }
                Text(L10n.t("Markdown/JSON tương thích các app ghi chú nhanh (Antinote, Simplenote…). Nhập sẽ thay thế toàn bộ danh sách hiện tại."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if let err = importError {
                    Text(err).font(.system(size: 11)).foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func pickImport(_ types: [String], _ apply: @escaping (String) -> Void) {
        importError = nil
        let panel = NSOpenPanel()
        panel.allowedFileTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(readText(url))
    }

    private func readText(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func saveText(_ name: String, _ text: String) {
        let panel = NSSavePanel()
        panel.allowedFileTypes = [(name as NSString).pathExtension]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = "xnotes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(store.notes) else { return }
        try? data.write(to: url)
    }

    private func importJSON() {
        importError = nil
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        guard let decoded = try? JSONDecoder().decode([QuickNote].self, from: data) else {
            importError = L10n.t("File không đúng định dạng ghi chú XFinder.")
            return
        }
        store.replaceAll(with: decoded)
    }
}

private struct BrowserNoteCard: View {
    let note: QuickNote
    let onEdit: () -> Void
    let onPin: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if note.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange)
                }
                Text(note.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Circle().fill(note.color.color).frame(width: 12, height: 12)
            }
            Text(note.content).font(.system(size: 12)).foregroundColor(.primary).lineLimit(5)
            Spacer(minLength: 2)
            Text(note.timeString).font(.caption2).foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(note.color.color.opacity(0.14))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(note.color.color.opacity(0.3), lineWidth: 1))
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button { onEdit() } label: { Label(L10n.t("Sửa"), systemImage: "pencil") }
            Button { onPin() } label: { Label(note.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"), systemImage: "pin") }
            Button { onArchive() } label: { Label(note.isArchived ? L10n.t("Khôi phục") : L10n.t("Lưu trữ"), systemImage: "archivebox") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label(L10n.t("Xóa"), systemImage: "trash") }
        }
    }
}
