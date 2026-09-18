import SwiftUI
import AppKit

/// Chia sẻ nhanh — share files over the LAN with a link.
struct QuickShareDetailView: View {
    @State private var controller = QuickShareController.shared
    @AppStorage("quickShare.expiryHours") private var expiryHours = 24.0
    @State private var copied: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: "square.and.arrow.up.on.square",
                    title: L10n.t("Chia sẻ nhanh"),
                    subtitle: L10n.t("Chia sẻ file qua mạng nội bộ bằng một liên kết."),
                    trailing: AnyView(
                        Text(controller.isRunning ? L10n.t("Đang chạy") : L10n.t("Đang tắt"))
                            .font(.system(size: 12))
                            .foregroundColor(controller.isRunning ? .green : .secondary)
                    ))

                HStack {
                    Button { pickAndShare() } label: {
                        Label(L10n.t("Chọn file để chia sẻ…"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)

                    if !controller.shares.isEmpty {
                        Button(L10n.t("Thu hồi tất cả")) { controller.revokeAll() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text(L10n.t("Hết hạn sau")).font(.system(size: 12)).foregroundColor(.secondary)
                        Picker("", selection: $expiryHours) {
                            Text(L10n.t("1 giờ")).tag(1.0)
                            Text(L10n.t("6 giờ")).tag(6.0)
                            Text(L10n.t("24 giờ")).tag(24.0)
                            Text(L10n.t("7 ngày")).tag(168.0)
                        }
                        .labelsHidden().frame(width: 100)
                    }
                }
                .padding(.horizontal, 20)

                if let err = controller.lastError {
                    Text(err).font(.system(size: 11)).foregroundColor(.red)
                        .padding(.horizontal, 20)
                }

                if controller.shares.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 34)).foregroundColor(.secondary)
                        Text(L10n.t("Chưa chia sẻ file nào"))
                            .font(.system(size: 16, weight: .semibold))
                        Text(L10n.t("Chọn file để tạo liên kết cho thiết bị trong cùng mạng Wi-Fi."))
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    VStack(spacing: 8) {
                        ForEach(controller.shares) { share in
                            shareRow(share)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Divider().padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Cách hoạt động")).font(.system(size: 14, weight: .semibold))
                    note(L10n.t("File **ở nguyên trên máy Mac này**. XFinder mở một máy chủ HTTP nhỏ trong mạng nội bộ và trả về liên kết."))
                    note(L10n.t("Chỉ thiết bị trong **cùng mạng Wi-Fi/LAN** mở được liên kết. Không có tài khoản, không qua máy chủ trung gian."))
                    note(L10n.t("Mỗi liên kết có mã ngẫu nhiên 160-bit và tự hết hạn; máy chủ tự tắt khi không còn liên kết nào."))
                    note(L10n.t("Cần gửi ra ngoài mạng nội bộ? Dùng AirDrop hoặc ứng dụng cloud sẵn có — XFinder không có hạ tầng cloud và sẽ không giả vờ là có."))
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
    }

    private func note(_ t: String) -> some View {
        Text(.init(t)).font(.system(size: 12)).foregroundColor(.secondary)
    }

    private func shareRow(_ share: QuickShareController.Share) -> some View {
        let link = controller.link(for: share)
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: share.url.path))
                .resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(share.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(link ?? L10n.t("Đang chờ địa chỉ mạng…"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(expiryText(share))
                .font(.system(size: 11)).foregroundColor(.secondary)
            Button(copied == share.id ? L10n.t("Đã chép") : L10n.t("Chép link")) {
                guard let link else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                copied = share.id
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(link == nil)
            Button { controller.revoke(share) } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func expiryText(_ share: QuickShareController.Share) -> String {
        let remaining = share.expiresAt.timeIntervalSinceNow
        if remaining <= 0 { return L10n.t("Hết hạn") }
        if remaining < 3600 { return "\(L10n.t("còn "))\(Int(remaining / 60))\(L10n.t(" phút"))" }
        return "\(L10n.t("còn "))\(Int(remaining / 3600))\(L10n.t(" giờ"))"
    }

    private func pickAndShare() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false   // a directory has no single payload
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.t("Chia sẻ")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        _ = controller.share(files: panel.urls)
    }
}
