import SwiftUI
import AppKit

/// Đồng bộ thư mục — layout follows the reference screenshot: a master
/// auto-sync switch, an explainer strip, then the list of sync pairs.
struct FolderSyncDetailView: View {
    @State private var controller = FolderSyncController.shared
    @AppStorage("sync.autoEnabled") private var autoEnabled = false
    @State private var editing: FolderSyncController.Pair?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(
                    icon: "arrow.triangle.2.circlepath",
                    title: L10n.t("Đồng bộ thư mục"),
                    subtitle: L10n.t("Sao lưu thư mục một chiều."),
                    trailing: AnyView(
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(autoEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                                Toggle("", isOn: $autoEnabled)
                                    .labelsHidden()
                                    .onChange(of: autoEnabled) { controller.applySettings() }
                            }
                            Text(L10n.t("Đồng bộ tự động"))
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        }
                    ))

                HStack(alignment: .top, spacing: 8) {
                    Text(L10n.t("Điều khiển các lượt Khi thay đổi và Hằng ngày. Đồng bộ ngay thủ công vẫn khả dụng."))
                        .font(XFinderTokens.Font.rowValue)
                    Spacer(minLength: 8)
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                        .help(L10n.t("Tắt công tắc này chỉ dừng các lượt tự động; nút “Đồng bộ ngay” vẫn chạy được."))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                    .fill(Color(.controlBackgroundColor).opacity(0.6)))
                .padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    HStack(alignment: .top) {
                        SectionHeader(
                            icon: "folder.badge.gearshape",
                            title: L10n.t("Các cặp đồng bộ"),
                            subtitle: L10n.t("Tệp được đồng bộ một chiều từ từng thư mục nguồn sang thư mục đích."))
                        Spacer()
                        Button {
                            addPair()
                        } label: {
                            Label(L10n.t("Thêm đồng bộ thư mục"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.trailing, XFinderTokens.Space.page)
                    }

                    if let err = controller.lastError {
                        Text(err).font(XFinderTokens.Font.caption).foregroundColor(.red)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }

                    if controller.pairs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(L10n.t("Chưa có cặp đồng bộ nào"), systemImage: "arrow.triangle.2.circlepath")
                                .font(XFinderTokens.Font.sectionTitle)
                            Text(L10n.t("Thêm thư mục nguồn và đích để tạo tác vụ đồng bộ đầu tiên."))
                                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, XFinderTokens.Space.page)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(controller.pairs) { pair in
                                pairRow(pair)
                                if pair.id != controller.pairs.last?.id {
                                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                                }
                            }
                        }
                    }
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "questionmark.circle", title: L10n.t("Cách hoạt động"))
                    note(L10n.md("Đồng bộ **một chiều**: nguồn → đích. Thay đổi ở đích không quay về nguồn."))
                    InlineNote(text: L10n.t("Dùng rsync tăng dần — chỉ tệp thay đổi mới được chép, nên lần chạy sau rất nhanh."))
                        .padding(.horizontal, XFinderTokens.Space.page)
                    InlineNote(text: L10n.t("“Xóa tệp thừa ở đích” mặc định TẮT. Bật thì đích sẽ giống hệt nguồn, kể cả việc xóa."))
                        .padding(.horizontal, XFinderTokens.Space.page)
                    InlineNote(text: L10n.t("“Khi thay đổi” theo dõi thư mục nguồn và chờ 3 giây sau thay đổi cuối rồi mới chạy."))
                        .padding(.horizontal, XFinderTokens.Space.page)
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Fill.window)
        .onAppear { controller.applySettings() }
        .sheet(item: $editing) { pair in
            PairSettingsSheet(pair: pair, editing: $editing)
        }
    }

    /// For the one markdown-bearing note (`**one-way**`) — `InlineNote` takes plain text, so a
    /// bold key needs `Text(.init(…))` to render instead of showing literal asterisks.
    private func note(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(XFinderTokens.Font.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, XFinderTokens.Space.page)
    }

    private func pairRow(_ pair: FolderSyncController.Pair) -> some View {
        let running = controller.runningIDs.contains(pair.id)
        return VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundColor(.accentColor)
                Text(pair.sourceName).font(XFinderTokens.Font.row).fileNameRowSafe()
                Image(systemName: "arrow.right").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                Text(pair.destName).font(XFinderTokens.Font.row).fileNameRowSafe()
                Spacer()
                if running {
                    ProgressView().scaleEffect(0.5)
                } else {
                    Button(L10n.t("Đồng bộ ngay")) { Task { await controller.run(pair) } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Menu {
                    Button(L10n.t("Tùy chọn…")) { editing = pair }
                    Button(L10n.t("Hiện nguồn trong Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: pair.sourcePath)])
                    }
                    Divider()
                    Button(role: .destructive) { controller.remove(pair) } label: { Text(L10n.t("Xóa cặp này")) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }

            HStack(spacing: 10) {
                if pair.onChange { tag(L10n.t("Khi thay đổi")) }
                if pair.daily { tag("\(L10n.t("Hằng ngày "))\(pair.dailyHour):00") }
                if pair.deleteExtras { tag(L10n.t("Xóa tệp thừa")) }
                Spacer()
                if let r = pair.lastResult {
                    Text(r).font(XFinderTokens.Font.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }

            Text("\(pair.sourcePath)  →  \(pair.destPath)")
                .font(XFinderTokens.Font.mono)
                .foregroundColor(.secondary)
                .fileNameRowSafe()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(XFinderTokens.Font.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }

    private func addPair() {
        let src = NSOpenPanel()
        src.canChooseFiles = false
        src.canChooseDirectories = true
        src.prompt = L10n.t("Chọn nguồn")
        src.message = L10n.t("Chọn thư mục NGUỒN (sẽ được sao chép đi)")
        guard src.runModal() == .OK, let source = src.url else { return }

        let dst = NSOpenPanel()
        dst.canChooseFiles = false
        dst.canChooseDirectories = true
        dst.canCreateDirectories = true
        dst.prompt = L10n.t("Chọn đích")
        dst.message = L10n.t("Chọn thư mục ĐÍCH (nơi nhận bản sao)")
        guard dst.runModal() == .OK, let dest = dst.url else { return }

        controller.add(source: source, dest: dest)
    }
}

private struct PairSettingsSheet: View {
    @State var pair: FolderSyncController.Pair
    @Binding var editing: FolderSyncController.Pair?
    @State private var controller = FolderSyncController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text(L10n.t("Tùy chọn đồng bộ")).font(XFinderTokens.Font.sectionTitle)

            Text("\(pair.sourceName) → \(pair.destName)")
                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ToggleRow(title: L10n.t("Đồng bộ khi thư mục nguồn thay đổi"), isOn: $pair.onChange)
                ToggleRow(title: L10n.t("Đồng bộ hằng ngày"), isOn: $pair.daily)
                if pair.daily {
                    PickerRow(title: L10n.t("Vào lúc"), selection: $pair.dailyHour, width: 100) {
                        ForEach(0..<24, id: \.self) { h in Text("\(h):00").tag(h) }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ToggleRow(title: L10n.t("Xóa tệp thừa ở đích (mirror hoàn toàn)"), isOn: $pair.deleteExtras)
                if pair.deleteExtras {
                    // Red on purpose: this deletes for real, not to the Trash (CLAUDE.md contract).
                    InlineNote(kind: .error, text: L10n.t("Cảnh báo: tệp có ở đích nhưng không có ở nguồn sẽ bị XÓA VĨNH VIỄN, không vào Thùng rác."))
                }
            }

            HStack {
                Spacer()
                Button(L10n.t("Hủy")) { editing = nil }.buttonStyle(.bordered)
                Button(L10n.t("Lưu")) {
                    controller.update(pair)
                    editing = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(XFinderTokens.Space.page)
        .frame(width: 430)
    }
}
