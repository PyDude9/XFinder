import SwiftUI
import AppKit

/// Kết nối từ xa — layout follows the reference screenshot.
struct RemoteConnectDetailView: View {
    @State private var controller = RemoteConnectController.shared
    @State private var editing: RemoteConnectController.Destination?
    @State private var showAdd = false
    // XF-T21: the catalog switch (same key + default as RemoteConnectController.isEnabled).
    @AppStorage("remoteConnect.enabled") private var enabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Kết nối từ xa"),
                           subtitle: L10n.t("Tải file và thư mục đã chọn lên đích từ xa."))

                SettingsSection {
                    ToggleRow(title: L10n.t("Cho phép Kết nối từ xa"),
                              subtitle: L10n.t("Tắt là XFinder không chạy ssh hay scp nữa: Kiểm tra và Tải lên đều bị chặn. Danh sách kết nối vẫn giữ."),
                              isOn: $enabled)
                        .onChange(of: enabled) { FeatureHub.apply(.remoteConnect) }
                        .settingsRow()
                }

                HStack {
                    Text("\(controller.destinations.count)\(L10n.t(" kết nối"))")
                        .font(XFinderTokens.Font.row).foregroundColor(.secondary)
                    Spacer()
                    Button { showAdd = true } label: {
                        Label(L10n.t("Thêm kết nối…"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                if controller.destinations.isEmpty {
                    VStack(spacing: XFinderTokens.Space.inline) {
                        Image(systemName: "globe")
                            .font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
                        Text(L10n.t("Chưa có kết nối từ xa"))
                            .font(XFinderTokens.Font.pageSubtitle.weight(.semibold))
                        Text(L10n.t("Thêm máy chủ để tải lên từ XFinder."))
                            .font(XFinderTokens.Font.row).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    VStack(spacing: XFinderTokens.Space.inline) {
                        ForEach(controller.destinations) { dest in
                            row(dest)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                if case .running(let msg) = controller.state {
                    HStack(spacing: XFinderTokens.Space.inline) {
                        ProgressView().scaleEffect(0.6)
                        Text(msg).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                } else if case .done(let msg) = controller.state {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(XFinderTokens.Font.rowValue).foregroundColor(.green)
                        .padding(.horizontal, XFinderTokens.Space.page)
                } else if case .failed(let msg) = controller.state {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(XFinderTokens.Font.rowValue).foregroundColor(.red)
                        .padding(.horizontal, XFinderTokens.Space.page)
                }

                SettingsSection(title: L10n.t("Cách hoạt động")) {
                    note(L10n.t("Dùng `scp` qua SSH — cùng cơ chế Terminal, không có dịch vụ trung gian."))
                        .settingsRow()
                    SettingsDivider()
                    note(L10n.t("Xác thực bằng **khóa SSH**, không lưu mật khẩu. XFinder chỉ ghi nhớ host/user/đường dẫn và *vị trí* file khóa."))
                        .settingsRow()
                    SettingsDivider()
                    note(L10n.t("File chỉ rời khỏi máy Mac khi bạn bấm Tải lên. Không có đồng bộ nền."))
                        .settingsRow()
                    SettingsDivider()
                    note(L10n.t("Chưa có khóa? Chạy `ssh-keygen -t ed25519` rồi `ssh-copy-id user@host` trong Terminal một lần."))
                        .settingsRow()
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .sheet(isPresented: $showAdd) {
            DestinationSheet(destination: nil, isPresented: $showAdd)
        }
        .sheet(item: $editing) { dest in
            DestinationSheet(destination: dest, editing: $editing)
        }
    }

    private func note(_ t: String) -> some View {
        Text(.init(t)).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
    }

    private func row(_ dest: RemoteConnectController.Destination) -> some View {
        HStack(spacing: XFinderTokens.Space.row) {
            Image(systemName: "server.rack").foregroundColor(.accentColor).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(dest.name).font(XFinderTokens.Font.row)
                Text(dest.displayTarget)
                    .font(XFinderTokens.Font.mono)
                    .foregroundColor(.secondary)
                    .fileNameRowSafe()
            }
            Spacer(minLength: XFinderTokens.Space.inline)
            Button(L10n.t("Tải lên…")) { pickAndUpload(dest) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!enabled)
            Menu {
                Button(L10n.t("Kiểm tra kết nối")) { Task { await controller.test(dest) } }
                    .disabled(!enabled)
                Button(L10n.t("Sửa…")) { editing = dest }
                Divider()
                Button(role: .destructive) { controller.remove(dest) } label: { Text(L10n.t("Xóa")) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).fill(XFinderTokens.Fill.inset))
    }

    private func pickAndUpload(_ dest: RemoteConnectController.Destination) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.t("Tải lên")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { await controller.upload(files: urls, to: dest) }
    }
}

private struct DestinationSheet: View {
    @State var draft: RemoteConnectController.Destination
    private let isNew: Bool
    var isPresented: Binding<Bool>?
    var editing: Binding<RemoteConnectController.Destination?>?
    @State private var controller = RemoteConnectController.shared

    init(destination: RemoteConnectController.Destination?,
         isPresented: Binding<Bool>? = nil,
         editing: Binding<RemoteConnectController.Destination?>? = nil) {
        _draft = State(initialValue: destination ?? .init(
            name: "", host: "", user: NSUserName(), remotePath: "~/"))
        self.isNew = destination == nil
        self.isPresented = isPresented
        self.editing = editing
    }

    private var valid: Bool {
        !draft.name.isEmpty && !draft.host.isEmpty
            && !draft.user.isEmpty && !draft.remotePath.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? L10n.t("Thêm kết nối từ xa") : L10n.t("Sửa kết nối"))
                .font(XFinderTokens.Font.sectionTitle)

            field(L10n.t("Tên hiển thị"), text: $draft.name, placeholder: L10n.t("NAS phòng làm việc"))
            field(L10n.t("Máy chủ"), text: $draft.host, placeholder: L10n.t("192.168.1.10 hoặc nas.local"))
            HStack {
                field(L10n.t("Người dùng"), text: $draft.user, placeholder: NSUserName())
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("Cổng")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    TextField("22", value: $draft.port, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 70)
                }
            }
            field(L10n.t("Thư mục đích"), text: $draft.remotePath, placeholder: "/volume1/backup")

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("Khóa SSH (để trống = dùng khóa mặc định)"))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                HStack {
                    TextField("~/.ssh/id_ed25519", text: $draft.keyPath)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.t("Chọn…")) { pickKey() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }

            Text("\(L10n.t("XFinder không lưu mật khẩu. Nếu chưa có khóa, chạy")) `ssh-keygen -t ed25519` \(L10n.t("rồi")) `ssh-copy-id \(draft.user)@\(draft.host.isEmpty ? "host" : draft.host)`.")
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)

            HStack {
                Button(L10n.t("Kiểm tra")) { Task { await controller.test(draft) } }
                    .buttonStyle(.bordered).disabled(!valid)
                Spacer()
                Button(L10n.t("Hủy")) { close() }.buttonStyle(.bordered)
                Button(L10n.t("Lưu")) {
                    if isNew { controller.add(draft) } else { controller.update(draft) }
                    close()
                }
                .buttonStyle(.borderedProminent).disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func pickKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url { draft.keyPath = url.path }
    }

    private func close() {
        isPresented?.wrappedValue = false
        editing?.wrappedValue = nil
    }
}
