import SwiftUI

/// Biểu tượng thanh menu — the Bartender-style hidden tray.
/// Copy and structure follow the reference screenshot; the mechanism is
/// described honestly in `MenuBarHiderController` (a user-performed ⌘-drag
/// across XFinder's own separator item, no permission required).
struct MenuIconsDetailView: View {
    @AppStorage("menubar.hiderEnabled") private var enabled = true
    @AppStorage("menubar.autoHide") private var autoHide = true
    @AppStorage("menubar.autoHideDelay") private var autoHideDelay = 5.0
    @State private var hider = MenuBarHiderController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: "menubar.rectangle",
                    title: "Biểu tượng thanh menu",
                    subtitle: "Ẩn và hiện các biểu tượng ít dùng trên thanh menu macOS.",
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(enabled ? "Bật" : "Tắt")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Toggle("", isOn: $enabled)
                                .labelsHidden()
                                .onChange(of: enabled) { hider.applySettings() }
                        }
                    ))

                SectionHeader(icon: "menubar.dock.rectangle",
                              title: "Thanh biểu tượng ẩn",
                              subtitle: "Gom các biểu tượng ít dùng sau một mũi tên trên thanh menu, giống như Bartender.")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Tự động ẩn lại sau khi hiện").font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $autoHide)
                            .labelsHidden()
                            .disabled(!enabled)
                        Picker("", selection: $autoHideDelay) {
                            Text("3 giây").tag(3.0)
                            Text("5 giây").tag(5.0)
                            Text("10 giây").tag(10.0)
                            Text("30 giây").tag(30.0)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .disabled(!enabled || !autoHide)
                    }

                    HStack(spacing: 8) {
                        Button("Hiện biểu tượng ẩn ngay") { hider.revealNow() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(!enabled)
                        Button("Đặt lại bố cục") { hider.resetLayout() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(!enabled)
                    }

                    Text("Đặt lại bố cục chỉ sửa mũi tên và vạch ngăn của XFinder, không sắp xếp lại các ứng dụng khác.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "hand.point.up.left",
                              title: "Cách chọn biểu tượng để ẩn",
                              subtitle: "Ẩn biểu tượng không cần cấp quyền.")

                VStack(alignment: .leading, spacing: 8) {
                    step(1, "XFinder thêm một mũi tên ‹ và một vạch ngăn mảnh vào thanh menu.")
                    step(2, "Giữ ⌘ và kéo những biểu tượng muốn giấu sang bên trái vạch ngăn.")
                    step(3, "Giữ những biểu tượng luôn muốn thấy ở bên phải vạch ngăn.")
                    step(4, "Bấm mũi tên để hiện hoặc ẩn nhóm.")
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ứng dụng mới mở có thể xuất hiện bên trái vạch ngăn và nằm sẵn trong nhóm bị ẩn.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Text("Cách này dùng chính các mục trạng thái của XFinder nên không cần quyền Trợ năng hay Ghi màn hình. macOS không có API cho phép một ứng dụng ẩn biểu tượng của ứng dụng khác, nên thao tác ⌘-kéo phải do bạn thực hiện.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear { hider.applySettings() }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text).font(.system(size: 12))
            Spacer(minLength: 0)
        }
    }
}
