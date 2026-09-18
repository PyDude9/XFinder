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
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: "arrow.triangle.2.circlepath",
                    title: L10n.t("Đồng bộ thư mục"),
                    subtitle: L10n.t("Sao lưu thư mục một chiều."),
                    trailing: AnyView(
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(autoEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                                Toggle("", isOn: $autoEnabled)
                                    .labelsHidden()
                                    .onChange(of: autoEnabled) { controller.applySettings() }
                            }
                            Text(L10n.t("Đồng bộ tự động"))
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    ))

                HStack(alignment: .top, spacing: 8) {
                    Text(L10n.t("Điều khiển các lượt Khi thay đổi và Hằng ngày. Đồng bộ ngay thủ công vẫn khả dụng."))
                        .font(.system(size: 12))
                    Spacer(minLength: 8)
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                        .help(L10n.t("Tắt công tắc này chỉ dừng các lượt tự động; nút “Đồng bộ ngay” vẫn chạy được."))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.controlBackgroundColor).opacity(0.6)))
                .padding(.horizontal, 20)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("Các cặp đồng bộ")).font(.system(size: 14, weight: .semibold))
                        Text(L10n.t("Tệp được đồng bộ một chiều từ từng thư mục nguồn sang thư mục đích."))
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        addPair()
                    } label: {
                        Label(L10n.t("Thêm đồng bộ thư mục"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 20)

                if let err = controller.lastError {
                    Text(err).font(.system(size: 11)).foregroundColor(.red)
                        .padding(.horizontal, 20)
                }

                if controller.pairs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L10n.t("Chưa có cặp đồng bộ nào"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.t("Thêm thư mục nguồn và đích để tạo tác vụ đồng bộ đầu tiên."))
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 8) {
                        ForEach(controller.pairs) { pair in
                            pairRow(pair)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Divider().padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Cách hoạt động")).font(.system(size: 14, weight: .semibold))
                    note(L10n.t("Đồng bộ **một chiều**: nguồn → đích. Thay đổi ở đích không quay về nguồn."))
                    note(L10n.t("Dùng rsync tăng dần — chỉ tệp thay đổi mới được chép, nên lần chạy sau rất nhanh."))
                    note(L10n.t("“Xóa tệp thừa ở đích” mặc định TẮT. Bật thì đích sẽ giống hệt nguồn, kể cả việc xóa."))
                    note(L10n.t("“Khi thay đổi” theo dõi thư mục nguồn và chờ 3 giây sau thay đổi cuối rồi mới chạy."))
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear { controller.applySettings() }
        .sheet(item: $editing) { pair in
            PairSettingsSheet(pair: pair, editing: $editing)
        }
    }

    private func note(_ t: String) -> some View {
        Text(.init(t)).font(.system(size: 12)).foregroundColor(.secondary)
    }

    private func pairRow(_ pair: FolderSyncController.Pair) -> some View {
        let running = controller.runningIDs.contains(pair.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundColor(.accentColor)
                Text(pair.sourceName).font(.system(size: 13, weight: .medium))
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(.secondary)
                Text(pair.destName).font(.system(size: 13, weight: .medium))
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
                    Text(r).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
            }

            Text("\(pair.sourcePath)  →  \(pair.destPath)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary).lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10))
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
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("Tùy chọn đồng bộ")).font(.system(size: 15, weight: .semibold))

            Text("\(pair.sourceName) → \(pair.destName)")
                .font(.system(size: 12)).foregroundColor(.secondary)

            Toggle(L10n.t("Đồng bộ khi thư mục nguồn thay đổi"), isOn: $pair.onChange)
            Toggle(L10n.t("Đồng bộ hằng ngày"), isOn: $pair.daily)
            if pair.daily {
                Picker(L10n.t("Vào lúc"), selection: $pair.dailyHour) {
                    ForEach(0..<24, id: \.self) { h in Text("\(h):00").tag(h) }
                }
                .frame(width: 160)
            }

            Divider()

            Toggle(L10n.t("Xóa tệp thừa ở đích (mirror hoàn toàn)"), isOn: $pair.deleteExtras)
            if pair.deleteExtras {
                Text(L10n.t("Cảnh báo: tệp có ở đích nhưng không có ở nguồn sẽ bị XÓA VĨNH VIỄN, không vào Thùng rác."))
                    .font(.system(size: 11)).foregroundColor(.red)
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
        .padding(20)
        .frame(width: 430)
    }
}
