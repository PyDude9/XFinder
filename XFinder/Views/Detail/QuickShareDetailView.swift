import SwiftUI
import AppKit

/// Chia sẻ nhanh — share files over the LAN with a link.
struct QuickShareDetailView: View {
    @State private var controller = QuickShareController.shared
    @AppStorage("quickShare.expiryHours") private var expiryHours = 24.0
    @State private var copied: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Chia sẻ nhanh"),
                    subtitle: L10n.t("Chia sẻ file qua mạng nội bộ bằng một liên kết."),
                    trailing: AnyView(
                        Text(controller.isRunning ? L10n.t("Đang chạy") : L10n.t("Đang tắt"))
                            .font(XFinderTokens.Font.rowValue)
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
                    PickerRow(title: L10n.t("Hết hạn sau"), selection: $expiryHours, width: 100) {
                        Text(L10n.t("1 giờ")).tag(1.0)
                        Text(L10n.t("6 giờ")).tag(6.0)
                        Text(L10n.t("24 giờ")).tag(24.0)
                        Text(L10n.t("7 ngày")).tag(168.0)
                    }
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                if let err = controller.lastError {
                    Text(err).font(XFinderTokens.Font.caption).foregroundColor(.red)
                        .padding(.horizontal, XFinderTokens.Space.page)
                }

                if controller.shares.isEmpty {
                    VStack(spacing: XFinderTokens.Space.inline) {
                        Image(systemName: "link")
                            .font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
                        Text(L10n.t("Chưa chia sẻ file nào"))
                            .font(XFinderTokens.Font.sectionTitle)
                        Text(L10n.t("Chọn file để tạo liên kết cho thiết bị trong cùng mạng Wi-Fi."))
                            .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, XFinderTokens.Space.section)
                } else {
                    VStack(spacing: XFinderTokens.Space.inline) {
                        ForEach(controller.shares) { share in
                            shareRow(share)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                SettingsSection(title: L10n.t("Cách hoạt động")) {
                    note(L10n.t("File **ở nguyên trên máy Mac này**. XFinder mở một máy chủ HTTP nhỏ trong mạng nội bộ và trả về liên kết."))
                        .settingsRow()
                    SettingsDivider()
                    note(L10n.t("Chỉ thiết bị trong **cùng mạng Wi-Fi/LAN** mở được liên kết. Không có tài khoản, không qua máy chủ trung gian."))
                        .settingsRow()
                    SettingsDivider()
                    note(L10n.t("Mỗi liên kết có mã ngẫu nhiên 160-bit và tự hết hạn; máy chủ tự tắt khi không còn liên kết nào."))
                        .settingsRow()
                    SettingsDivider()
                    note(L10n.t("Cần gửi ra ngoài mạng nội bộ? Dùng AirDrop hoặc ứng dụng cloud sẵn có — XFinder không có hạ tầng cloud và sẽ không giả vờ là có."))
                        .settingsRow()
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    private func note(_ t: String) -> some View {
        Text(.init(t)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
    }

    private func shareRow(_ share: QuickShareController.Share) -> some View {
        let link = controller.link(for: share)
        return HStack(spacing: XFinderTokens.Space.inline) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: share.url.path))
                .resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(share.name).font(XFinderTokens.Font.row).fileNameRowSafe()
                Text(link ?? L10n.t("Đang chờ địa chỉ mạng…"))
                    .font(XFinderTokens.Font.mono)
                    .foregroundColor(.secondary).fileNameRowSafe()
            }
            Spacer(minLength: XFinderTokens.Space.inline)
            Text(expiryText(share))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
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
        .padding(XFinderTokens.Space.row)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).fill(XFinderTokens.Fill.inset))
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
