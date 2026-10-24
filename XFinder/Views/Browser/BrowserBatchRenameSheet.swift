import SwiftUI

/// XF-T28 cluster E — the Browser's batch-rename sheet: same engine as `Views/Detail/BatchRenameDetailView.swift`
/// (`BatchRenameEngine.Options`/`plan`/`execute`), pre-loaded with `sources` (Shelf or selection) instead of asking
/// the user to pick files, with a full preview table and `ActionHistoryStore.shared.recordRenames` so ⌘Z works.
struct BrowserBatchRenameSheet: View {
    let sources: [String]
    let model: BrowserWindowModel

    @State private var options = BatchRenameEngine.Options()
    @State private var outcome: String?
    @State private var isError = false
    @Environment(\.dismiss) private var dismiss

    private var files: [URL] { sources.map { URL(fileURLWithPath: $0) } }
    private var plans: [BatchRenameEngine.Plan] {
        BatchRenameEngine.plan(files: files, options: options)
    }
    private var runnable: [BatchRenameEngine.Plan] {
        plans.filter { !$0.collides && $0.source != $0.proposed }
    }
    private var blockedCount: Int { plans.count - runnable.count }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Đổi tên hàng loạt"))
                .font(XFinderTokens.Font.sectionTitle)

            modeControls

            if blockedCount > 0 {
                Text("\(blockedCount)\(L10n.t(" mục bị chặn (trùng tên hoặc trùng đích)."))")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.orange)
            }

            previewTable

            if let outcome {
                Text(outcome)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(isError ? .red : .green)
            }

            HStack {
                Button(L10n.t("Dừng")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t("Đổi tên hàng loạt")) { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(runnable.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 560, height: 480)
    }

    private var modeControls: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Picker(L10n.t("Kiểu"), selection: $options.mode) {
                ForEach(BatchRenameEngine.Mode.allCases) { mode in
                    Text(mode.titleVI).tag(mode)
                }
            }
            .pickerStyle(.menu)

            switch options.mode {
            case .prefix, .suffix:
                TextField(options.mode == .prefix ? L10n.t("Tiền tố") : L10n.t("Hậu tố"), text: $options.affix)
                    .textFieldStyle(.roundedBorder)
            case .replace:
                HStack {
                    TextField(L10n.t("Tìm"), text: $options.find).textFieldStyle(.roundedBorder)
                    Text("→").foregroundColor(.secondary)
                    TextField(L10n.t("Thay bằng"), text: $options.replaceWith).textFieldStyle(.roundedBorder)
                }
            case .sequence:
                HStack {
                    Stepper("\(L10n.t("Bắt đầu từ "))\(options.sequenceStart)", value: $options.sequenceStart, in: 0...9999)
                    Stepper("\(L10n.t("Số chữ số "))\(options.sequenceDigits)", value: $options.sequenceDigits, in: 1...5)
                }
                TextField(L10n.t("Ký tự ngăn cách"), text: $options.sequenceSeparator)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
            case .lowercase, .uppercase:
                EmptyView()
            }

            Toggle(L10n.t("Giữ phần mở rộng (.pdf, .jpg…)"), isOn: $options.keepExtension)
        }
        .font(XFinderTokens.Font.rowValue)
    }

    private var previewTable: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(plans) { plan in
                    HStack {
                        Text(plan.source.lastPathComponent)
                            .font(XFinderTokens.Font.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                        Text(plan.proposed.lastPathComponent)
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(plan.collides ? .red : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    SettingsDivider()
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func apply() {
        let (moved, failed) = BatchRenameEngine.execute(runnable)
        if !moved.isEmpty { ActionHistoryStore.shared.recordRenames(pairs: moved) }
        if moved.isEmpty, failed > 0 {
            isError = true
            outcome = "\(L10n.t("Không đổi được mục nào ("))\(failed)\(L10n.t(" thất bại)."))"
        } else {
            isError = false
            outcome = failed == 0
                ? "\(L10n.t("Đã đổi tên "))\(moved.count)\(L10n.t(" mục. Xem Lịch sử thao tác để hoàn tác."))"
                : "\(L10n.t("Đã đổi "))\(moved.count)\(L10n.t(" mục, "))\(failed)\(L10n.t(" mục thất bại."))"
            if failed == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            }
        }
    }
}
