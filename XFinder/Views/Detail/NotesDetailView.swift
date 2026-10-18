import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Ghi chú — real note browser over NoteStore (shared with SideNotesPanel and
/// the menubar flyout). Grid of note cards with search, color filter, pin /
/// archive, and the same editor sheet (Save actually persists).
struct NotesDetailView: View {
    @State private var store = NoteStore.shared
    /// Master switch in the page header — same key the edge panel reads.
    @AppStorage("notes.edgeEnabled") private var edgeEnabled = false
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
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Ghi chú"),
                    subtitle: L10n.t("Lưu ghi chú, danh sách công việc và ý tưởng ngay mép màn hình."),
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(edgeEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
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

                edgeNotesSection
                appearanceSection
                shortcutsSection
                importExportSection
            }
            .padding(.bottom, 24)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
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
        HStack(spacing: XFinderTokens.Space.inline) {
            Image(systemName: "note.text").foregroundColor(.accentColor).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.notes.filter { !$0.isArchived }.count)\(L10n.t(" ghi chú đang dùng"))")
                    .font(XFinderTokens.Font.row)
                Text("\(store.notes.filter(\.isArchived).count)\(L10n.t(" đã lưu trữ"))")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(L10n.t("Ghi chú mới")) { showCreateSheet = true }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    private var filterRow: some View {
        filterBar
            .padding(.horizontal, XFinderTokens.Space.page)
    }

    private var notesGrid: some View {
        Group {
            if visible.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: XFinderTokens.Space.inline)], spacing: XFinderTokens.Space.inline) {
                    ForEach(visible) { note in
                        BrowserNoteCard(note: note,
                                        onEdit: { editingNote = note; showCreateSheetForEdit = true },
                                        onPin: { store.togglePin(note) },
                                        onArchive: { store.toggleArchive(note) },
                                        onDelete: { store.delete(note) })
                    }
                }
                .padding(.horizontal, XFinderTokens.Space.page)
            }
        }
    }
    private var filterBar: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(XFinderTokens.Font.caption)
                TextField(L10n.t("Tìm ghi chú…"), text: $searchText)
                    .textFieldStyle(.plain).font(XFinderTokens.Font.rowValue)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                    .help(L10n.t("Xoá tìm kiếm"))
                    .accessibilityLabel(L10n.t("Xoá tìm kiếm"))
                }
            }
            .padding(.horizontal, XFinderTokens.Space.tight + 2).padding(.vertical, 5)
            .background(XFinderTokens.Fill.inset)
            .cornerRadius(XFinderTokens.Radius.control)
            .frame(maxWidth: 260)

            // A labelled menu picker, not `PickerRow(title: "")`: PickerRow hides the
            // native label, so the filter lost its "Màu" caption (A3 review finding).
            Picker(L10n.t("Màu"), selection: $selectedColorName) {
                Text(L10n.t("Mọi màu")).tag(nil as String?)
                ForEach(CodableColor.presetNames, id: \.self) { name in
                    Text(name).tag(name as String?)
                }
            }
            .pickerStyle(.menu).frame(width: 170)

            // Two short labels: segmented is the right control (the gate allows ≤ 4).
            Picker("", selection: $showArchived) {
                Text(L10n.t("Đang dùng")).tag(false)
                Text(L10n.t("Lưu trữ")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 170)
            Spacer()
        }
        .padding(.vertical, XFinderTokens.Space.tight + 2)
    }

    private var emptyState: some View {
        VStack(spacing: XFinderTokens.Space.row) {
            Image(systemName: "note.text").font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
            Text(showArchived ? L10n.t("Không có ghi chú lưu trữ") : L10n.t("Chưa có ghi chú"))
                .font(XFinderTokens.Font.sectionTitle)
            Text(L10n.t("Bấm “Ghi chú mới” để tạo ghi chú đầu tiên."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Edge notes

    private var edgeNotesSection: some View {
        EdgeNotesSettingsSection()
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        AppearanceSection()
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        ShortcutsSection()
    }

    // MARK: - Import / Export

    private var importExportSection: some View {
        ImportExportSection(importError: $importError)
    }
}

private struct EdgeNotesSettingsSection: View {
    @AppStorage("notes.edgeSide") private var edgeSide = "Right"
    @AppStorage("notes.edgeHotspot") private var edgeHotspot = 12.0
    @AppStorage("notes.fullscreen") private var showFullscreen = false
    @AppStorage("notes.hideOnLeave") private var hideOnLeave = true
    /// XF-T24: the reader is EdgeNotesController.globalHotkeyEnabled (same default).
    @AppStorage("notes.globalHotkey") private var globalHotkey = false
    @State private var store = NoteStore.shared

    var body: some View {
        SettingsSection(
            title: L10n.t("Ghi chú ở mép màn hình"),
            footer: store.notes.isEmpty
                ? L10n.t("Dải mép chỉ hiện khi có ít nhất một ghi chú.")
                : L10n.t("Di chuột tới mép màn hình để mở ghi chú.")
        ) {
            HStack(spacing: XFinderTokens.Space.inline) {
                Text(L10n.t("Cạnh màn hình")).font(XFinderTokens.Font.row)
                Spacer()
                Picker("", selection: $edgeSide) {
                    Text(L10n.t("Trái")).tag("Left")
                    Text(L10n.t("Phải")).tag("Right")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            .onChange(of: edgeSide) { EdgeNotesController.shared.applySettings() }
            .settingsRow()
            SettingsDivider()
            VStack(alignment: .leading, spacing: 4) {
                Text("\(L10n.t("Độ nhạy vùng chạm "))\(Int(edgeHotspot)) pt")
                    .font(XFinderTokens.Font.row)
                Slider(value: $edgeHotspot, in: 4...40, step: 1)
                    .onChange(of: edgeHotspot) { EdgeNotesController.shared.applySettings() }
            }
            .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Hiện trên ứng dụng toàn màn hình"),
                      subtitle: L10n.t("Best-effort qua .stationary"),
                      isOn: $showFullscreen)
                .onChange(of: showFullscreen) { EdgeNotesController.shared.applySettings() }
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Ẩn khi con trỏ rời khỏi"), isOn: $hideOnLeave)
                .onChange(of: hideOnLeave) { EdgeNotesController.shared.applySettings() }
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Phím tắt ⌃⌥N mở ghi chú từ mọi app"),
                      subtitle: L10n.t("Mở ghi chú đầu dải (ghim trước, rồi mới sửa gần nhất) để viết ngay; chưa có thì tạo ghi chú mới; bấm lại để đóng. Không cần quyền, nhưng ⌃⌥N sẽ không còn tới app khác."),
                      isOn: $globalHotkey)
                .onChange(of: globalHotkey) { EdgeNotesController.shared.applySettings() }
                .settingsRow()
            if globalHotkey && !EdgeNotesController.shared.globalHotkeyRegistered && EdgeNotesController.shared.isEnabled {
                InlineNote(text: L10n.t("Không đăng ký được ⌃⌥N — có app khác đang giữ tổ hợp này."))
                    .settingsRow()
            }
            if store.notes.isEmpty {
                SettingsDivider()
                InlineNote(text: L10n.t("Chưa có ghi chú — dải mép đang ẩn. Tạo ghi chú đầu tiên để dùng."))
                    .settingsRow()
            }
        }
    }
}

private struct AppearanceSection: View {
    @AppStorage("notes.font") private var noteFont = "system"
    @State private var store = NoteStore.shared

    var body: some View {
        SettingsSection(
            title: L10n.t("Giao diện ghi chú"),
            footer: L10n.t("Markdown và danh sách công việc vẫn chỉnh sửa được dưới dạng văn bản thuần.")
        ) {
            PickerRow(title: L10n.t("Phông chữ"), selection: $noteFont, width: 120) {
                ForEach(NoteStore.NoteFont.allCases) { f in Text(f.titleVI).tag(f.rawValue) }
            }
            .settingsRow()
            SettingsDivider()
            VStack(alignment: .leading, spacing: 4) {
                Text("\(L10n.t("Cỡ chữ")) \(String(format: "%.1f", store.fontSize)) pt")
                    .font(XFinderTokens.Font.row)
                Slider(value: Binding(
                    get: { store.fontSize },
                    set: { store.setFontSize($0) }
                ), in: 11...20, step: 0.5)
            }
            .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Định dạng Markdown khi nhập"), isOn: Binding(
                get: { store.markdownEnabled },
                set: { store.markdownEnabled = $0 }
            ))
            .settingsRow()
        }
    }
}

private struct ShortcutsSection: View {
    var body: some View {
        SettingsSection(
            title: L10n.t("Phím tắt"),
            footer: L10n.t("Chỉ hoạt động khi XFinder đang ở phía trước.")
        ) {
            shortcutRow(L10n.t("Ghi chú mới"), keys: "⌥⌘N")
            SettingsDivider()
            shortcutRow(L10n.t("Mở trang Ghi chú"), keys: "⌥⌘L")
            SettingsDivider()
            shortcutRow(L10n.t("Ghim hoặc bỏ ghim ghi chú đầu danh sách (chưa lưu trữ)"), keys: "⌥⌘P")
        }
    }

    private func shortcutRow(_ label: String, keys: String) -> some View {
        HStack {
            Text(label).font(XFinderTokens.Font.rowValue)
            Spacer()
            Text(keys)
                .font(XFinderTokens.Font.mono)
                .padding(.horizontal, XFinderTokens.Space.tight + 2).padding(.vertical, 4)
                .background(XFinderTokens.Fill.inset)
                .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge))
        }
        .settingsRow()
    }
}

private struct ImportExportSection: View {
    @Binding var importError: String?
    @State private var store = NoteStore.shared
    /// XF-T24: the reader is NoteStore.autoBackupEnabled (same default).
    @AppStorage("notes.autoBackup") private var autoBackup = true

    var body: some View {
        SettingsSection(title: L10n.t("Nhập / Xuất ghi chú")) {
            HStack(spacing: XFinderTokens.Space.inline) {
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
            .settingsRow()
            SettingsDivider()
            InlineNote(text: L10n.t("Markdown/JSON tương thích các app ghi chú nhanh (Antinote, Simplenote…). Nhập sẽ thay thế toàn bộ danh sách hiện tại."))
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Tự sao lưu mỗi ngày"),
                      subtitle: L10n.t("Lần lưu đầu tiên mỗi ngày ghi một bản JSON (Nhập lại được) và một bản Markdown vào thư mục sao lưu trên máy này; giữ 14 ngày gần nhất, bản cũ hơn vào Thùng rác."),
                      isOn: $autoBackup)
                .settingsRow()
            HStack(spacing: XFinderTokens.Space.inline) {
                if let day = store.lastBackupDay {
                    Text("\(L10n.t("Bản gần nhất: "))\(day)")
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                if let err = store.lastBackupError {
                    Text("\(L10n.t("Không sao lưu được: "))\(err)")
                        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(L10n.t("Sao lưu ngay")) { store.backupIfNeeded(force: true) }
                Button(L10n.t("Mở thư mục sao lưu")) {
                    try? FileManager.default.createDirectory(at: NoteStore.backupFolder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(NoteStore.backupFolder)
                }
            }
            .settingsRow()

            if let err = importError {
                SettingsDivider()
                Text(err).font(XFinderTokens.Font.caption).foregroundColor(.red)
                    .settingsRow()
            }
        }
    }

    private func pickImport(_ types: [String], _ apply: @escaping (String) -> Void) {
        importError = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(readText(url))
    }

    private func readText(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func saveText(_ name: String, _ text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: (name as NSString).pathExtension)].compactMap { $0 }
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
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
        panel.allowedContentTypes = [.json]
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
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                if note.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange)
                }
                Text(note.displayTitle).font(XFinderTokens.Font.row).lineLimit(1)
                    .fileNameRowSafe()
                Spacer()
                Circle().fill(note.color.color).frame(width: 12, height: 12)
            }
            Text(note.content).font(XFinderTokens.Font.rowValue).foregroundColor(.primary).lineLimit(5)
            Spacer(minLength: 2)
            Text(note.timeString).font(.caption2).foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(note.color.color.opacity(0.14))
        .cornerRadius(XFinderTokens.Radius.tile)
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).stroke(note.color.color.opacity(0.3), lineWidth: 1))
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
