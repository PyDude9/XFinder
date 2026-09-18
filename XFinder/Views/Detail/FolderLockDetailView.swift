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
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "lock.shield",
                           title: L10n.t("Khóa thư mục"),
                           subtitle: L10n.t("Mã hóa thư mục bằng mật khẩu — AES-256, hoàn toàn trên máy."))

                SectionHeader(icon: "plus.rectangle.on.folder",
                              title: L10n.t("Tạo vault mới"),
                              subtitle: L10n.t("Chọn một thư mục để mã hóa thành vault có mật khẩu."))

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
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    if let err = controller.lastError {
                        Text(err).font(.system(size: 11)).foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "lock.doc",
                              title: L10n.t("Vault của bạn"),
                              subtitle: controller.vaults.isEmpty
                                  ? L10n.t("Chưa có vault nào.")
                                  : "\(controller.vaults.count) vault")

                VStack(spacing: 8) {
                    ForEach(controller.vaults) { vault in
                        vaultRow(vault)
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.t("Cách hoạt động")).font(.system(size: 15, weight: .semibold))
                    line(L10n.t("Vault là một disk image mã hóa AES-256 (.sparsebundle) — cùng cơ chế Apple dùng cho ảnh đĩa mã hóa."))
                    line(L10n.t("Mở khóa: nhập mật khẩu → vault gắn vào máy như một ổ đĩa và mở trong Finder."))
                    line(L10n.t("Khóa lại: ngắt ổ đĩa; nội dung trên đĩa trở lại dạng mã hóa, không đọc được."))
                    line(L10n.t("Sparsebundle chỉ chiếm dung lượng thực tế đang dùng, và sao lưu Time Machine hiệu quả hơn ảnh đĩa thường."))
                    line(L10n.t("XFinder KHÔNG lưu mật khẩu. Mất mật khẩu là mất dữ liệu — hãy lưu vào Keychain hoặc trình quản lý mật khẩu."))
                    line(L10n.t("Thư mục gốc chỉ được chuyển vào Thùng rác sau khi đã kiểm tra bản mã hóa thành công."))
                }
                .padding(.horizontal, 20)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(L10n.t("Không dùng cách “ẩn thư mục” (chflags hidden) vì ai cũng có thể hiện lại trong vài giây — đó không phải bảo mật thật."))
                        .font(.system(size: 12))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showCreate) {
            CreateVaultSheet(isPresented: $showCreate)
        }
        .sheet(item: $unlockTarget) { vault in
            UnlockSheet(vault: vault, unlockTarget: $unlockTarget)
        }
    }

    private func line(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundColor(.secondary)
    }

    private func vaultRow(_ vault: FolderLockController.Vault) -> some View {
        HStack(spacing: 10) {
            Image(systemName: vault.isMounted ? "lock.open.fill" : "lock.fill")
                .foregroundColor(vault.isMounted ? .orange : .green)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(vault.name).font(.system(size: 13, weight: .medium))
                Text(vault.isMounted ? L10n.t("Đang mở khóa") : L10n.t("Đã khóa"))
                    .font(.system(size: 11)).foregroundColor(.secondary)
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
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
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
            Text(L10n.t("Tạo vault mã hóa")).font(.system(size: 15, weight: .semibold))

            HStack {
                Button(L10n.t("Chọn thư mục…")) { pick() }
                    .buttonStyle(.bordered).controlSize(.small)
                Text(folder?.lastPathComponent ?? L10n.t("Chưa chọn"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }

            SecureField(L10n.t("Mật khẩu (ít nhất 6 ký tự)"), text: $password)
            SecureField(L10n.t("Nhập lại mật khẩu"), text: $confirm)

            if !password.isEmpty, password != confirm {
                Text(L10n.t("Mật khẩu nhập lại không khớp."))
                    .font(.system(size: 11)).foregroundColor(.red)
            }

            Toggle(L10n.t("Chuyển thư mục gốc vào Thùng rác sau khi mã hóa"), isOn: $deleteOriginal)
                .font(.system(size: 12))

            Text(L10n.t("XFinder không lưu mật khẩu này ở bất cứ đâu. Nếu quên, dữ liệu không thể khôi phục."))
                .font(.system(size: 11)).foregroundColor(.secondary)

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
            Text("\(L10n.t("Mở khóa “"))\(vault.name)”").font(.system(size: 15, weight: .semibold))
            SecureField(L10n.t("Mật khẩu"), text: $password)
            if let err = controller.lastError {
                Text(err).font(.system(size: 11)).foregroundColor(.red)
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
