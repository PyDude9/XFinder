import SwiftUI

/// Biểu tượng thanh menu — nút MŨI TÊN ẩn/hiện biểu tượng, theo cơ chế public
/// API của Hidden Bar/Bartender (`NSStatusItem` separator + arrow). Ghi rõ giới
/// hạn macOS 27 thay vì giấu.
struct MenuIconsDetailView: View {
    @State private var hider = MenuBarHiderController.shared
    @AppStorage("menubar.hiderEnabled") private var enabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "menubar.rectangle",
                           title: "Biểu tượng thanh menu",
                           subtitle: "Ẩn bớt biểu tượng trên thanh menu để gọn hơn.")

                SectionHeader(icon: "chevron.left.chevron.right",
                              title: "Nút mũi tên ẩn biểu tượng",
                              subtitle: "Hoạt động như Hidden Bar — ẩn icon nằm bên trái mũi tên.")

                SettingsCard(title: "Bật nút mũi tên") {
                    VStack(alignment: .leading, spacing: 8) {
                        ToggleRow(title: "Hiện mũi tên trên thanh menu", isOn: $enabled)
                            .onChange(of: enabled) {
                                MenuBarHiderController.shared.applySettings()
                            }

                        Text("Bấm mũi tên → ẩn mọi icon nằm BÊN TRÁI mũi tên. Kéo MŨI TÊN (⌘) sát mép phải để ẩn hết; các icon bạn muốn HIỆN thì kéo qua BÊN PHẢI mũi tên. Có thể ⌘-kéo icon qua lại giữa hai phía bất kỳ lúc nào.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)

                SectionHeader(icon: "exclamationmark.triangle",
                              title: "Giới hạn trên macOS 27",
                              subtitle: "Kết quả đo thật, không phỏng đoán.")

                VStack(alignment: .leading, spacing: 8) {
                    bullet("macOS 26/27 không còn đẩy icon hàng xóm khi vạch ngăn phình rộng (length bị clamp ~5016pt; icon bên cạnh chỉ dịch chỗ chứ không ra khỏi bar) — nên trên macOS mới, mũi tên có thể KHÔNG ẩn được icon của app khác như macOS cũ.")
                    bullet("Không có API công khai nào ẩn icon của app thứ ba; đây là cách public API duy nhất (giống hệt Hidden Bar). Icon HỆ THỐNG do macOS 26+ quản tại Control Centre → Menu Bar.")
                    bullet("Nếu trên máy bạn mũi tên không ẩn được icon thứ ba, tính năng vẫn vô hại — XFinder nói rõ giới hạn thay vì hứa ẩn mà không làm.")
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                Button("Mở Cài đặt thanh menu của macOS") {
                    hider.openSystemMenuBarSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.system(size: 12)).foregroundColor(.secondary)
            Text(.init(text))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
