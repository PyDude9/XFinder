import SwiftUI
import AppKit

/// Đổi tên hàng loạt — pick files, choose a rename mode, see the live
/// before→after preview, then apply. Applies via FileManager only (no shell),
/// refuses to touch colliding targets, and logs to ActionHistoryStore with
/// one-click undo.
struct BatchRenameDetailView: View {
    @State private var files: [URL] = []
    @State private var options = BatchRenameEngine.Options()
    @State private var outcome: String? = nil
    @State private var isError = false
    @State private var history = ActionHistoryStore.shared

    private var plans: [BatchRenameEngine.Plan] {
        BatchRenameEngine.plan(files: files, options: options)
    }
    private var runnable: [BatchRenameEngine.Plan] {
        plans.filter { !$0.collides && $0.source != $0.proposed }
    }
    private var blocked: Int { plans.count - runnable.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Đổi tên hàng loạt"),
                           subtitle: L10n.t("Đổi tên hàng loạt và Lịch sử thao tác: nhận trực tiếp mục đang chọn, và hoàn tác được."))

                SettingsSection(title: L10n.t("Tập tin cần đổi tên"),
                                footer: files.isEmpty ? L10n.t("Chưa chọn gì") : "\(files.count)\(L10n.t(" mục"))") {
                    HStack {
                        Button(L10n.t("Chọn tập tin…")) { pickFiles() }
                        if !files.isEmpty {
                            Button(L10n.t("Xóa hết")) { files = [] }
                                .font(XFinderTokens.Font.rowValue).foregroundColor(.red)
                        }
                    }
                    .settingsRow()
                    if blocked > 0 {
                        SettingsDivider()
                        Text("\(blocked)\(L10n.t(" mục bị chặn (trùng tên hoặc trùng đích)."))")
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
                        ForEach(BatchRenameEngine.Mode.allCases) { m in
                            Text(m.titleVI).tag(m)
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
                        }
                    }
                    .settingsRow()
                    SettingsDivider()

                    ToggleRow(title: L10n.t("Giữ phần mở rộng (.pdf, .jpg…)"),
                              isOn: $options.keepExtension)
                        .settingsRow()
                }

                if !files.isEmpty {
                    SettingsSection(title: "\(L10n.t("Xem trước ("))\(runnable.count)\(L10n.t(" sẽ đổi)"))") {
                        ForEach(Array(plans.prefix(12).enumerated()), id: \.element.id) { entry in
                            let plan = entry.element
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
                                Text(plan.source.lastPathComponent)
                                    .font(XFinderTokens.Font.caption)
                                    .fileNameRowSafe()
                                Text("→").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                    .layoutPriority(1)
                                Text(plan.proposed.lastPathComponent)
                                    .font(XFinderTokens.Font.caption)
                                    .fileNameRowSafe()
                                    .foregroundColor(plan.collides ? .red : .primary)
                                if plan.collides {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red).font(XFinderTokens.Font.caption)
                                }
                            }
                            .settingsRow()
                        }
                        if plans.count > 12 {
                            SettingsDivider()
                            Text("\(L10n.t("…và "))\(plans.count - 12)\(L10n.t(" mục nữa"))")
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                .settingsRow()
                        }
                    }
                }

                Button {
                    apply()
                } label: {
                    Text(runnable.isEmpty ? L10n.t("Chưa có gì để đổi") : "\(L10n.t("Đổi "))\(runnable.count)\(L10n.t(" mục"))")
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(runnable.isEmpty)
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
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { files = panel.urls.sorted { $0.path < $1.path } }
    }

    private func apply() {
        let (moved, failed) = BatchRenameEngine.execute(runnable)
        if !moved.isEmpty { history.recordRenames(pairs: moved) }
        if moved.isEmpty, failed > 0 {
            isError = true
            outcome = "\(L10n.t("Không đổi được mục nào ("))\(failed)\(L10n.t(" thất bại)."))"
        } else {
            isError = false
            outcome = failed == 0
                ? "\(L10n.t("Đã đổi tên "))\(moved.count)\(L10n.t(" mục. Xem Lịch sử thao tác để hoàn tác."))"
                : "\(L10n.t("Đã đổi "))\(moved.count)\(L10n.t(" mục, "))\(failed)\(L10n.t(" mục thất bại."))"
            files = files.filter { url in !moved.contains { $0.old == url } }
                .map { url in moved.first { $0.old == url }?.new ?? url }
        }
    }
}
