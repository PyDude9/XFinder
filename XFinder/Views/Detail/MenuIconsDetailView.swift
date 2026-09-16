import SwiftUI

/// Biểu tượng thanh menu.
///
/// Corrected after measuring, twice. The first conclusion ("no mechanism
/// exists on macOS 27") was wrong — MFinder does it, which was the user's
/// counter-evidence. What the probes actually established:
///
/// * The old Bartender-style trick **is** dead: `NSStatusItem.length = 10_000`
///   is clamped to ~5016 pt and, more importantly, neighbouring items are no
///   longer displaced at all (measured: a neighbour moved *right*, 952 → 988,
///   and stayed on screen).
/// * macOS 27 ships `MenuBarClientCore.framework` (private). `dlopen` succeeds
///   from an ordinary app, and `MBMenuBarItemManager` instantiates with an
///   `xpcSession` ivar talking to `com.apple.MenuBarAgent`. It exposes
///   `setGloballyHidden:completionHandler:` and `setItems:completionHandler:`.
/// * **But there is no read path** — no delegate protocol, no enumeration API
///   reachable from the framework alone. MFinder ships its own
///   `MenuBarItemReader`, so selective hiding needs machinery XFinder does not
///   have, and `setGloballyHidden:` is all-or-nothing on the entire menu bar.
///
/// So the honest position: XFinder will not ship a half-feature built on a
/// private XPC surface that can only hide *everything* and would break on the
/// next OS update. The page explains this and links to what macOS supports.
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
                              title: "Dùng cài đặt của macOS",
                              subtitle: "Từ macOS 26, việc ẩn/hiện biểu tượng nằm trong Cài đặt hệ thống.")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Mở Cài đặt hệ thống → Trung tâm điều khiển để chọn biểu tượng nào hiện trên thanh menu. Giữ ⌘ rồi kéo để đổi thứ tự ngay trên thanh menu.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Mở Cài đặt thanh menu của macOS") {
                        hider.openSystemMenuBarSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "flask",
                              title: "Vì sao XFinder chưa tự ẩn giúp bạn",
                              subtitle: "Kết quả đo thật trên macOS 27, không phải phỏng đoán.")

                VStack(alignment: .leading, spacing: 8) {
                    bullet("Cách của Bartender / Hidden Bar (dwarvesf/hidden) — dùng 2 biểu tượng: một nút bấm + một vạch ngăn phình từ 1pt lên ~4000pt để đẩy các biểu tượng bên trái ra ngoài, kèm `autosaveName` nhớ vị trí. Trên macOS 27 cách này **không còn tác dụng**: biểu tượng bên cạnh không bị đẩy đi mà chỉ dịch chỗ.")
                    bullet("macOS 27 có sẵn một framework riêng tư điều khiển thanh menu. XFinder mở được nó và thấy hàm “ẩn toàn bộ thanh menu”, nhưng **không có hàm đọc danh sách biểu tượng**.")
                    bullet("Nghĩa là chỉ có thể ẩn **tất cả**, chứ không chọn được từng biểu tượng như bạn muốn. Ứng dụng nào làm được việc chọn lọc đều phải tự viết thêm bộ đọc riêng.")
                    bullet("Đây là API riêng tư của Apple: không được tài liệu hóa, có thể hỏng ở bản macOS kế tiếp và không qua được App Store.")

                    Text("Khi nào có cách làm ổn định và chọn lọc được, tính năng này sẽ quay lại. Trước mắt XFinder không thêm biểu tượng nào vào thanh menu cho mục này — một nút bấm không làm đúng điều nó ghi thì tệ hơn là không có nút.")
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
            Text(.init(text))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
