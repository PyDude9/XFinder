import SwiftUI
import AppKit

/// Chia sẻ nhanh — share files over the LAN with a link.
struct QuickShareDetailView: View {
    @State private var controller = QuickShareController.shared
    @AppStorage("quickShare.expiryHours") private var expiryHours = 24.0
    // XF-T21: the catalog switch (same key + default as QuickShareController.isEnabled).
    @AppStorage("quickShare.enabled") private var enabled = true
    @State private var copied: UUID?
    @State private var qrShare: UUID?
    @State private var qrAll = false
    @State private var license = LicenseManager.shared

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

                SettingsSection {
                    ToggleRow(title: L10n.t("Cho phép Chia sẻ nhanh"),
                              subtitle: L10n.t("Tắt là thu hồi mọi liên kết và dừng máy chủ ngay; không file nào được phục vụ nữa."),
                              isOn: $enabled)
                        .onChange(of: enabled) { FeatureHub.apply(.quickShare) }
                        .settingsRow()
                }

                HStack {
                    Button { pickAndShare() } label: {
                        Label(L10n.t("Chọn file để chia sẻ…"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!enabled)

                    if !controller.shares.isEmpty {
                        Button { qrAll = true } label: { Label(L10n.t("QR cho tất cả"), systemImage: "qrcode") }
                            .buttonStyle(.bordered).controlSize(.small)
                            .popover(isPresented: $qrAll, arrowEdge: .bottom) {
                                QuickShareQRPopover(link: controller.indexLink, title: L10n.t("Mọi file đang chia sẻ"),
                                                    caption: L10n.t("Ai có mã này thấy cả danh sách. Quét bằng Camera của điện thoại cùng Wi-Fi."))
                            }
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

                if controller.blockedByLimit {
                    HStack(spacing: XFinderTokens.Space.tight) {
                        Text(L10n.t("Bản Free chỉ chia sẻ 1 liên kết cùng lúc — thu hồi liên kết cũ hoặc nâng cấp để chia sẻ thêm."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        Button { AppState.shared.navigate(to: .pro) } label: { ProBadge() }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                if controller.shares.isEmpty {
                    VStack(spacing: XFinderTokens.Space.inline) {
                        Image(systemName: "link")
                            .font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
                        Text(L10n.t("Chưa chia sẻ file nào"))
                            .font(XFinderTokens.Font.sectionTitle)
                        Text(enabled ? L10n.t("Chọn file để chia sẻ — mã QR hiện ngay để điện thoại cùng Wi-Fi quét.")
                                     : L10n.t("Chia sẻ nhanh đang tắt — bật ở trên để tạo liên kết."))
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
                    note(L10n.t("Điện thoại lấy liên kết bằng cách **quét mã QR** (nút QR cạnh mỗi file, hoặc một mã chung cho cả danh sách) — Camera của iPhone và Android mở thẳng, không cần cài gì. Wi-Fi khách có bật cách ly thiết bị sẽ chặn."))
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
            // A labelled button, not a bare glyph: the first hand test (2026-10-19) did not find an icon-only QR.
            Button { qrShare = share.id } label: { Label(L10n.t("Mã QR"), systemImage: "qrcode") }
                .buttonStyle(.bordered).controlSize(.small)
                .help(L10n.t("Mã QR cho điện thoại quét"))
                .popover(isPresented: Binding(get: { qrShare == share.id }, set: { if !$0 { qrShare = nil } }), arrowEdge: .bottom) {
                    QuickShareQRPopover(link: link, title: share.name,
                                        caption: L10n.t("Quét bằng Camera của điện thoại cùng Wi-Fi — không cần cài app."))
                }
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
        // The QR opens by itself: the code is what a phone needs, so it should not hide behind a second click.
        let made = controller.share(files: panel.urls)
        if made.count == 1 { qrShare = made[0].id } else if made.count > 1 { qrAll = true }
    }
}

/// A QR code of a share link, with the link under it so the person can read what the phone is about to open.
private struct QuickShareQRPopover: View {
    /// nil while the listener is still coming up (a few ms after the first share) — the popover waits instead of hiding.
    let link: String?
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: XFinderTokens.Space.inline) {
            Text(title).font(XFinderTokens.Font.row).lineLimit(1).truncationMode(.middle)
            if let link {
                QRCodeView(text: link, size: 200)
                Text(link).font(XFinderTokens.Font.mono).foregroundColor(.secondary).textSelection(.enabled)
            } else {
                ProgressView().controlSize(.small).frame(width: 200, height: 200)
                Text(L10n.t("Đang chờ địa chỉ mạng…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            Text(caption).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 280)
    }
}
