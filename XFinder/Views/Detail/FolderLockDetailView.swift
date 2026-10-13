import SwiftUI
import AppKit

/// Khóa thư mục — create and open AES-256 encrypted vaults.
struct FolderLockDetailView: View {
    @State private var controller = FolderLockController.shared
    @State private var showCreate = false
    @State private var unlockTarget: FolderLockController.Vault?
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Khóa thư mục"),
                           subtitle: L10n.t("Mã hóa thư mục bằng mật khẩu — AES-256, hoàn toàn trên máy."))

                SettingsSection(
                    title: L10n.t("Tạo vault mới"),
                    footer: L10n.t("Chọn một thư mục để mã hóa thành vault có mật khẩu.")
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showCreate = true
                        } label: {
                            Label(L10n.t("Chọn thư mục để khóa…"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(controller.busy)

                        if controller.busy {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.6)
                                Text(L10n.t("Đang xử lý… (mã hóa thư mục lớn có thể mất vài phút)"))
                                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            }
                        }
                        if let err = controller.lastError {
                            Text(err).font(XFinderTokens.Font.caption).foregroundColor(.red)
                        }
                    }
                    .settingsRow()
                }

                // P4 review: left flat, this group sat between two cards with nothing separating it. The vault
                // tiles keep their own inset fill inside the card (like the Features hub's bundle tiles).
                SettingsSection(title: L10n.t("Vault của bạn")) {
                    Text(controller.vaults.isEmpty
                         ? L10n.t("Chưa có vault nào.")
                         : "\(controller.vaults.count) vault")
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .settingsRow()
                    if !controller.vaults.isEmpty {
                        SettingsDivider()
                        VStack(spacing: 8) {
                            ForEach(controller.vaults) { vault in
                                vaultRow(vault)
                            }
                        }
                        .settingsRow()
                    }
                }

                SettingsSection(title: L10n.t("Cách hoạt động")) {
                    VStack(alignment: .leading, spacing: 7) {
                        line(L10n.t("Vault là một disk image mã hóa AES-256 (.sparsebundle) — cùng cơ chế Apple dùng cho ảnh đĩa mã hóa."))
                        line(L10n.t("Mở khóa: nhập mật khẩu → vault gắn vào máy như một ổ đĩa và mở trong Finder."))
                        line(L10n.t("Khóa lại: ngắt ổ đĩa; nội dung trên đĩa trở lại dạng mã hóa, không đọc được."))
                        line(L10n.t("Sparsebundle chỉ chiếm dung lượng thực tế đang dùng, và sao lưu Time Machine hiệu quả hơn ảnh đĩa thường."))
                        line(L10n.t("XFinder KHÔNG lưu mật khẩu. Mất mật khẩu là mất dữ liệu — hãy lưu vào Keychain hoặc trình quản lý mật khẩu."))
                        line(L10n.t("Thư mục gốc chỉ được chuyển vào Thùng rác sau khi đã kiểm tra bản mã hóa thành công."))
                    }
                    .settingsRow()

                    SettingsDivider()
                    InlineNote(kind: .warning,
                               text: L10n.t("Không dùng cách “ẩn thư mục” (chflags hidden) vì ai cũng có thể hiện lại trong vài giây — đó không phải bảo mật thật."))
                        .settingsRow()
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .sheet(isPresented: $showCreate) {
            CreateVaultSheet(isPresented: $showCreate)
        }
        .sheet(item: $unlockTarget) { vault in
            UnlockSheet(vault: vault, unlockTarget: $unlockTarget)
        }
    }

    private func line(_ t: String) -> some View {
        Text(t).font(XFinderTokens.Font.row).foregroundColor(.secondary)
    }

    private func vaultRow(_ vault: FolderLockController.Vault) -> some View {
        HStack(spacing: 10) {
            Image(systemName: vault.isMounted ? "lock.open.fill" : "lock.fill")
                .foregroundColor(vault.isMounted ? .orange : .green)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(vault.name).font(XFinderTokens.Font.row).fileNameRowSafe()
                Text(vault.isMounted ? L10n.t("Đang mở khóa") : L10n.t("Đã khóa"))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            Spacer()
            if vault.isMounted {
                Button(L10n.t("Khóa lại")) {
                    Task { await controller.lock(vault) }
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button(L10n.t("Mở khóa…")) { unlockTarget = vault }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Menu {
                Button(L10n.t("Hiện trong Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: vault.imagePath)])
                }
                Button(L10n.t("Bỏ khỏi danh sách")) { controller.forget(vault) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).fill(XFinderTokens.Fill.inset))
    }
}

private struct CreateVaultSheet: View {
    @Binding var isPresented: Bool
    @State private var folder: URL?
    @State private var password = ""
    @State private var confirm = ""
    @State private var deleteOriginal = true
    @State private var controller = FolderLockController.shared

    private var valid: Bool {
        folder != nil && password.count >= 6 && password == confirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("Tạo vault mã hóa")).font(XFinderTokens.Font.sectionTitle)

            HStack {
                Button(L10n.t("Chọn thư mục…")) { pick() }
                    .buttonStyle(.bordered).controlSize(.small)
                Text(folder?.lastPathComponent ?? L10n.t("Chưa chọn"))
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            }

            SecureField(L10n.t("Mật khẩu (ít nhất 6 ký tự)"), text: $password)
            SecureField(L10n.t("Nhập lại mật khẩu"), text: $confirm)

            if !password.isEmpty, password != confirm {
                Text(L10n.t("Mật khẩu nhập lại không khớp."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.red)
            }

            Toggle(L10n.t("Chuyển thư mục gốc vào Thùng rác sau khi mã hóa"), isOn: $deleteOriginal)
                .font(XFinderTokens.Font.rowValue)

            Text(L10n.t("XFinder không lưu mật khẩu này ở bất cứ đâu. Nếu quên, dữ liệu không thể khôi phục."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)

            HStack {
                Spacer()
                Button(L10n.t("Hủy")) { isPresented = false }
                    .buttonStyle(.bordered)
                Button(L10n.t("Mã hóa")) {
                    guard let folder else { return }
                    let pw = password
                    let del = deleteOriginal
                    isPresented = false
                    Task { await controller.createVault(from: folder, password: pw, deleteOriginal: del) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { folder = panel.url }
    }
}

private struct UnlockSheet: View {
    let vault: FolderLockController.Vault
    @Binding var unlockTarget: FolderLockController.Vault?
    @State private var password = ""
    @State private var controller = FolderLockController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(L10n.t("Mở khóa “"))\(vault.name)”").font(XFinderTokens.Font.sectionTitle)
            SecureField(L10n.t("Mật khẩu"), text: $password)
            if let err = controller.lastError {
                Text(err).font(XFinderTokens.Font.caption).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button(L10n.t("Hủy")) { unlockTarget = nil }
                    .buttonStyle(.bordered)
                Button(L10n.t("Mở khóa")) {
                    let pw = password
                    let v = vault
                    unlockTarget = nil
                    Task { await controller.unlock(v, password: pw) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
