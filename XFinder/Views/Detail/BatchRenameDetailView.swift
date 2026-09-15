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
            VStack(alignment: .leading, spacing: 16) {
                Text("Đổi tên hàng loạt")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 16)

                SettingsCard(title: "Tập tin cần đổi tên",
                             subtitle: files.isEmpty ? "Chưa chọn gì" : "\(files.count) mục") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Chọn tập tin…") { pickFiles() }
                            if !files.isEmpty {
                                Button("Xóa hết") { files = [] }
                                    .font(.system(size: 12)).foregroundColor(.red)
                            }
                        }
                        if blocked > 0 {
                            Text("\(blocked) mục bị chặn (trùng tên hoặc trùng đích).")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: "Kiểu đổi tên") {
                    VStack(alignment: .leading, spacing: 10) {
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
                        Picker("Kiểu", selection: $options.mode) {
                            ForEach(BatchRenameEngine.Mode.allCases) { m in
                                Text(m.titleVI).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 240, alignment: .leading)

                        switch options.mode {
                        case .prefix, .suffix:
                            TextField(options.mode == .prefix ? "Tiền tố" : "Hậu tố",
                                      text: $options.affix)
                                .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        case .replace:
                            HStack {
                                TextField("Tìm", text: $options.find)
                                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                                Text("→").foregroundColor(.secondary)
                                TextField("Thay bằng", text: $options.replaceWith)
                                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                            }
                        case .sequence:
                            HStack {
                                Stepper("Bắt đầu từ \(options.sequenceStart)",
                                        value: $options.sequenceStart, in: 0...9999)
                                    .font(.system(size: 12)).frame(maxWidth: 220)
                                Stepper("Số chữ số \(options.sequenceDigits)",
                                        value: $options.sequenceDigits, in: 1...5)
                                    .font(.system(size: 12))
                            }
                            TextField("Ký tự ngăn cách", text: $options.sequenceSeparator)
                                .textFieldStyle(.roundedBorder).font(.system(size: 12))
                                .frame(maxWidth: 140)
                        case .lowercase, .uppercase:
                            EmptyView()
                        }

                        ToggleRow(title: "Giữ phần mở rộng (.pdf, .jpg…)",
                                  isOn: $options.keepExtension)
                    }
                }
                .padding(.horizontal, 20)

                if !files.isEmpty {
                    SettingsCard(title: "Xem trước (\(runnable.count) sẽ đổi)") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(plans.prefix(12)) { plan in
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
                                        .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                    Text("→").font(.system(size: 11)).foregroundColor(.secondary)
                                        .layoutPriority(1)
                                    Text(plan.proposed.lastPathComponent)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1).truncationMode(.middle)
                                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(plan.collides ? .red : .primary)
                                    if plan.collides {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red).font(.caption)
                                    }
                                }
                            }
                            if plans.count > 12 {
                                Text("…và \(plans.count - 12) mục nữa")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Button {
                    apply()
                } label: {
                    Text(runnable.isEmpty ? "Chưa có gì để đổi" : "Đổi \(runnable.count) mục")
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(runnable.isEmpty)
                .padding(.horizontal, 20)

                if let msg = outcome {
                    SettingsCard(title: isError ? "Lỗi" : "Kết quả") {
                        Text(msg).font(.system(size: 12))
                            .foregroundColor(isError ? .red : .primary)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                } else {
                    Spacer().padding(.bottom, 20)
                }
            }
            // Standing rule (CLAUDE.md): every detail page clamps its ideal
            // width so no single control can push the split view wider than
            // the window. This page is why the rule exists.
            .pageWidthSafe()
        }
        .background(Color(.windowBackgroundColor))
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
            outcome = "Không đổi được mục nào (\(failed) thất bại)."
        } else {
            isError = false
            outcome = failed == 0
                ? "Đã đổi tên \(moved.count) mục. Xem Lịch sử thao tác để hoàn tác."
                : "Đã đổi \(moved.count) mục, \(failed) mục thất bại."
            files = files.filter { url in !moved.contains { $0.old == url } }
                .map { url in moved.first { $0.old == url }?.new ?? url }
        }
    }
}
