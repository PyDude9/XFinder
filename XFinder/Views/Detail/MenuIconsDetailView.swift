import SwiftUI

/// Biểu tượng thanh menu.
///
/// This page used to advertise Bartender-style hiding of *other* apps' icons.
/// Measured on macOS 27.0 (26A428), that mechanism no longer works — see the
/// probe results recorded in `MenuBarHiderController`. Rather than leave a
/// toggle that quietly does nothing, the page now states what macOS actually
/// supports and links to the pane that does it.
struct MenuIconsDetailView: View {
    @State private var hider = MenuBarHiderController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: "menubar.rectangle",
                    title: "Biểu tượng thanh menu",
                    subtitle: "Sắp xếp và ẩn biểu tượng trên thanh menu macOS.")

                SectionHeader(icon: "gearshape",
                              title: "macOS quản lý thanh menu",
                              subtitle: "Từ macOS 26, việc ẩn/hiện biểu tượng nằm trong Cài đặt hệ thống.")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Mở Cài đặt hệ thống → Trung tâm điều khiển để chọn biểu tượng nào hiện trên thanh menu, biểu tượng nào ẩn đi.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Mở Cài đặt thanh menu của macOS") {
                        hider.openSystemMenuBarSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Text("Bạn cũng có thể giữ ⌘ rồi kéo để đổi thứ tự biểu tượng ngay trên thanh menu.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "exclamationmark.triangle",
                              title: "Vì sao XFinder không tự ẩn giúp bạn",
                              subtitle: "Đo đạc thật trên macOS 27, không phải phỏng đoán.")

                VStack(alignment: .leading, spacing: 8) {
                    bullet("Cách cũ (giống Bartender) là dùng một vạch ngăn rộng 10.000 pt để đẩy các biểu tượng bên trái ra khỏi màn hình.")
                    bullet("macOS 27 giới hạn vạch ngăn còn ~5.016 pt — vẫn rộng hơn màn hình 1.728 pt, nên bề rộng không phải vấn đề.")
                    bullet("Nhưng biểu tượng bên cạnh không hề bị đẩy đi: nó dịch sang phải (x=952 → 988) và vẫn nằm trên thanh menu sau 7 giây.")
                    bullet("macOS cũng không cho ứng dụng nhìn thấy biểu tượng của ứng dụng khác, nên không có cách nào lách.")

                    Text("Vì vậy XFinder không thêm biểu tượng nào vào thanh menu cho chức năng này nữa — một nút bấm không làm được việc nó hứa thì tệ hơn là không có nút.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.system(size: 12)).foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
