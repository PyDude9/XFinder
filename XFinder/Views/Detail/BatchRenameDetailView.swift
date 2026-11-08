import SwiftUI
import AppKit

/// Đổi tên hàng loạt — pick files, choose a rename mode, see the live before→after preview with a status per row,
/// then apply. XF-T37 (Q-T37-5): the page keeps its modes and gains Format; names are checked by the same rules as the
/// file browser's batch rename (`BatchRenameRules` — case-only renames allowed, one error blocks the batch), disk facts
/// are read once off the main thread, the rename runs in two phases (swaps work, a failure puts everything back), and
/// it is logged to ActionHistoryStore with one-click undo.
struct BatchRenameDetailView: View {
    @State private var files: [URL] = []
    @State private var options = BatchRenameRules.PageOptions()
    @State private var items: [BatchRenameRules.Item] = []
    @State private var siblings: [String: Set<String>] = [:]
    @State private var isLoading = false
    @State private var isRunning = false
    @State private var outcome: String? = nil
    @State private var isError = false
    @State private var history = ActionHistoryStore.shared

    private var plan: BatchRenameRules.Plan {
        BatchRenameRules.pagePlan(items: items, options: options, siblings: { siblings[$0] }, calendar: .current,
                                  dateConnector: L10n.t(" lúc "))
    }

    var body: some View {
        let plan = plan
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Đổi tên hàng loạt"),
                           subtitle: L10n.t("Đổi tên hàng loạt và Lịch sử thao tác: nhận trực tiếp mục đang chọn, và hoàn tác được."))

                SettingsSection(title: L10n.t("Tập tin cần đổi tên"),
                                footer: files.isEmpty ? L10n.t("Chưa chọn gì") : "\(files.count)\(L10n.t(" mục"))") {
                    HStack {
                        Button(L10n.t("Chọn tập tin…")) { pickFiles() }
                        if !files.isEmpty {
                            Button(L10n.t("Xóa hết")) { files = []; items = []; siblings = [:]; outcome = nil }
                                .font(XFinderTokens.Font.rowValue).foregroundColor(.red)
                        }
                    }
                    .settingsRow()
                    if plan.errorCount > 0 {
                        SettingsDivider()
                        Text("\(plan.errorCount)\(L10n.t(" mục có lỗi — sửa hết mới đổi được."))")
                            .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                            .settingsRow()
                    }
                }

                SettingsSection(title: L10n.t("Kiểu đổi tên")) {
                    // THE recurring window-resize culprit on this page.
                    //
                    // A 6-segment `.segmented` picker sums the intrinsic
                    // width of every label — "Thêm tiền tố", "Đánh số thứ
                    // tự", … — and reports that as its IDEAL width. The
                    // split view honours it, so the detail pane demanded
                    // ~900pt and shoved the sidebar off-screen. Earlier
                    // fixes targeted the preview rows, which is why the bug
                    // survived: it reproduces with zero files selected,
                    // when no preview row exists at all.
                    //
                    // A menu picker has a small fixed ideal width, so the
                    // page can finally shrink to the window.
                    PickerRow(title: L10n.t("Kiểu"), selection: $options.mode, width: 200) {
                        ForEach(BatchRenameRules.PageMode.allCases, id: \.self) { m in
                            Text(BatchRenameEngine.title(m)).tag(m)
                        }
                    }
                    .settingsRow()
                    SettingsDivider()

                    Group {
                        switch options.mode {
                        case .prefix, .suffix:
                            TextField(options.mode == .prefix ? L10n.t("Tiền tố") : L10n.t("Hậu tố"),
                                      text: $options.affix)
                                .textFieldStyle(.roundedBorder).font(XFinderTokens.Font.rowValue)
                        case .replace:
                            HStack {
                                TextField(L10n.t("Tìm"), text: $options.find)
                                    .textFieldStyle(.roundedBorder).font(XFinderTokens.Font.rowValue)
                                Text("→").foregroundColor(.secondary)
                                TextField(L10n.t("Thay bằng"), text: $options.replaceWith)
                                    .textFieldStyle(.roundedBorder).font(XFinderTokens.Font.rowValue)
                            }
                        case .sequence:
                            HStack {
                                Stepper("\(L10n.t("Bắt đầu từ "))\(options.sequenceStart)",
                                        value: $options.sequenceStart, in: 0...9999)
                                    .font(XFinderTokens.Font.rowValue).frame(maxWidth: 220)
                                Stepper("\(L10n.t("Số chữ số "))\(options.sequenceDigits)",
                                        value: $options.sequenceDigits, in: 1...5)
                                    .font(XFinderTokens.Font.rowValue)
                            }
                            TextField(L10n.t("Ký tự ngăn cách"), text: $options.sequenceSeparator)
                                .textFieldStyle(.roundedBorder).font(XFinderTokens.Font.rowValue)
                                .frame(maxWidth: 140)
                        case .lowercase, .uppercase:
                            EmptyView()
                        case .format:
                            formatControls
                        }
                    }
                    .settingsRow()
                    if options.mode != .format {
                        SettingsDivider()
                        ToggleRow(title: L10n.t("Giữ phần mở rộng (.pdf, .jpg…)"),
                                  isOn: $options.keepExtension)
                            .settingsRow()
                    }
                }

                if !files.isEmpty {
                    SettingsSection(title: "\(L10n.t("Xem trước ("))\(plan.renameCount)\(L10n.t(" sẽ đổi)"))") {
                        ForEach(Array(plan.rows.prefix(12).enumerated()), id: \.element.id) { entry in
                            let row = entry.element
                            if entry.offset > 0 { SettingsDivider() }
                            HStack {
                                // `minWidth: 0` lets long file names actually
                                // compress; without it the row keeps a wide
                                // ideal width and resizes the window.
                                // `minWidth: 0` alone is NOT enough — it
                                // permits shrinking but the row still
                                // reports a wide *ideal* width, which is
                                // what pushes the window. `maxWidth:
                                // .infinity` makes each name claim a share
                                // of the available width instead.
                                Text(row.oldName)
                                    .font(XFinderTokens.Font.caption)
                                    .fileNameRowSafe()
                                Text("→").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                    .layoutPriority(1)
                                Text(row.newName)
                                    .font(XFinderTokens.Font.caption)
                                    .fileNameRowSafe()
                                    .foregroundColor(row.issues.isEmpty ? .primary : .red)
                                Text(status(row))
                                    .font(XFinderTokens.Font.caption)
                                    .foregroundColor(row.issues.isEmpty ? .secondary : .red)
                                    .fileNameRowSafe()
                            }
                            .settingsRow()
                        }
                        if plan.rows.count > 12 {
                            SettingsDivider()
                            Text("\(L10n.t("…và "))\(plan.rows.count - 12)\(L10n.t(" mục nữa"))")
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                .settingsRow()
                        }
                    }
                }

                Button {
                    apply(plan)
                } label: {
                    Text(plan.renameCount == 0 ? L10n.t("Chưa có gì để đổi") : "\(L10n.t("Đổi "))\(plan.renameCount)\(L10n.t(" mục"))")
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!plan.canRename || isLoading || isRunning)
                .padding(.horizontal, XFinderTokens.Space.page)

                if let msg = outcome {
                    InlineNote(kind: isError ? .error : .success, text: msg)
                        .padding(.horizontal, XFinderTokens.Space.page)
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            // Standing rule (CLAUDE.md): every detail page clamps its ideal
            // width so no single control can push the split view wider than
            // the window. This page is why the rule exists.
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear {
            // Finder's default custom format is "File " — shown in the UI language (the space is the user's separator).
            if options.format.customName == BatchRenameRules.Options().customName { options.format.customName = L10n.t("Tệp ") }
        }
    }

    /// Format mode's fields — the same three styles as Finder and the file browser (Name and Index / Counter / Date).
    private var formatControls: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                Picker(L10n.t("Kiểu tên"), selection: $options.format.formatStyle) {
                    Text(L10n.t("Tên và chỉ số")).tag(BatchRenameRules.FormatStyle.nameAndIndex)
                    Text(L10n.t("Tên và bộ đếm")).tag(BatchRenameRules.FormatStyle.nameAndCounter)
                    Text(L10n.t("Tên và ngày")).tag(BatchRenameRules.FormatStyle.nameAndDate)
                }
                .pickerStyle(.menu)
                .fixedSize()
                Picker(L10n.t("Đặt ở"), selection: $options.format.formatPosition) {
                    Text(L10n.t("Sau tên")).tag(BatchRenameRules.Position.after)
                    Text(L10n.t("Trước tên")).tag(BatchRenameRules.Position.before)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            HStack {
                TextField(L10n.t("Tên tuỳ chỉnh"), text: $options.format.customName)
                    .textFieldStyle(.roundedBorder).font(XFinderTokens.Font.rowValue)
                if options.format.formatStyle != .nameAndDate {
                    Stepper("\(L10n.t("Bắt đầu từ "))\(options.format.startNumber)", value: $options.format.startNumber, in: 0...99_999)
                        .font(XFinderTokens.Font.rowValue)
                        .fixedSize()
                }
            }
        }
    }

    private func status(_ row: BatchRenameRules.Row) -> String {
        if !row.issues.isEmpty { return row.issues.map { L10n.t($0.key) }.joined(separator: " ") }
        if row.isUnchanged { return L10n.t("Không đổi") }
        if row.notes.isEmpty { return L10n.t("Sẵn sàng") }
        return row.notes.map { note in
            note.detail.isEmpty ? L10n.t(note.key) : "\(L10n.t(note.key)) \(note.detail)"
        }.joined(separator: " ")
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            files = panel.urls.sorted { $0.path < $1.path }
            loadFacts()
        }
    }

    /// Disk facts for the plan, read once off the main thread (never in `body`).
    private func loadFacts() {
        let paths = files.map(\.path)
        isLoading = true
        Task { @MainActor in
            let facts = await Task.detached(priority: .userInitiated) { BatchRenameRules.readFacts(paths) }.value
            items = facts.items
            siblings = facts.siblings
            isLoading = false
        }
    }

    private func apply(_ plan: BatchRenameRules.Plan) {
        guard plan.canRename else { return }
        let pairs = plan.pairs
        isRunning = true
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { BatchRenameRules.execute(pairs) }.value
            isRunning = false
            guard result.succeeded else {
                isError = true
                let failedName = result.failedPath.map { ($0 as NSString).lastPathComponent } ?? ""
                let reason = result.failedErrno.map { String(cString: strerror($0)) } ?? ""
                var text = "\(L10n.t("Không đổi tên được: "))\(failedName) (\(reason))."
                if result.stranded.isEmpty {
                    text += " \(L10n.t("Mọi mục đã trở về tên cũ."))"
                } else {
                    let names = result.stranded.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                    text += " \(result.stranded.count)\(L10n.t(" mục chưa trả về được tên cũ: "))\(names)"
                }
                outcome = text
                loadFacts()
                return
            }
            let moved = pairs.map { (old: URL(fileURLWithPath: $0.from), new: URL(fileURLWithPath: $0.to)) }
            history.recordRenames(pairs: moved)
            isError = false
            outcome = "\(L10n.t("Đã đổi tên "))\(moved.count)\(L10n.t(" mục. Xem Lịch sử thao tác để hoàn tác."))"
            files = files.map { url in moved.first { $0.old == url }?.new ?? url }
            loadFacts()
        }
    }
}
