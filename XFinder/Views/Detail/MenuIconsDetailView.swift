import SwiftUI
import AppKit

/// XF-T22 — Biểu tượng thanh menu: explainer trung thực + một công tắc ẩn icon của chính XFinder.
struct MenuIconsDetailView: View {
    @AppStorage("menubar.hideOwnIcon") private var hideOwnIcon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(
                    title: L10n.t("Biểu tượng thanh menu"),
                    subtitle: L10n.t("Ẩn biểu tượng của XFinder khi muốn thanh menu gọn hơn, và mở nhanh cài đặt thanh menu của macOS.")
                )

                SettingsSection(
                    title: L10n.t("Biểu tượng XFinder"),
                    footer: L10n.t("Khi ẩn biểu tượng trên thanh menu, bạn vẫn mở được XFinder từ trang Tổng quan, Dock hoặc phím tắt ⌘,.")
                ) {
                    ToggleRow(
                        title: L10n.t("Ẩn biểu tượng XFinder trên thanh menu"),
                        subtitle: L10n.t("Giấu biểu tượng chính của XFinder; tắt lại để hiện ngay ở vùng bên phải notch."),
                        isOn: $hideOwnIcon
                    )
                    .onChange(of: hideOwnIcon) { _, _ in
                        if let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.menubarController?.applyIconVisibility()
                        }
                    }
                    .settingsRow()

                    SettingsDivider()

                    HStack {
                        Button(L10n.t("Mở Cài đặt thanh menu của macOS")) {
                            MenubarController.openSystemMenuBarSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Spacer()
                    }
                    .settingsRow()
                }

                SettingsSection(
                    title: L10n.t("Vì sao không ẩn được biểu tượng ứng dụng khác"),
                    footer: L10n.t("Để sắp xếp hoặc tắt biểu tượng hệ thống, dùng Trung tâm điều khiển ▸ Thanh menu hoặc giữ phím ⌘ rồi kéo biểu tượng.")
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet(L10n.t("Đo thực tế ngày 2026-10-18 trên macOS 27.0.1 (2 màn hình): 12/12 biểu tượng vẫn hiện trên màn hình dù bật ẩn mặc định."))
                        bullet(L10n.t("API đánh giá của macOS chỉ tác động mô-đun hệ thống, không ẩn được biểu tượng thanh menu của ứng dụng bên thứ ba."))
                        bullet(L10n.t("macOS 27 gộp thanh menu thành một cửa sổ chung nên mẹo chèn khoảng trắng phân cách cũ không còn tác dụng."))
                    }
                    .settingsRow()
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            Text(text)
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
