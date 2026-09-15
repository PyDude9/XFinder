import SwiftUI

/// Bàn phím Finder — layout and copy follow the reference screenshot.
struct FinderKeyboardDetailView: View {
    @AppStorage("finderKeyboard.cutPaste") private var cutPaste = false
    @AppStorage("finderKeyboard.deleteToTrash") private var deleteToTrash = false
    @AppStorage("finderKeyboard.returnOpens") private var returnOpens = false
    @State private var controller = FinderKeyboardController.shared
    @State private var trusted = WindowManager.isTrusted

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "keyboard",
                           title: "Bàn phím Finder",
                           subtitle: "Tùy chỉnh phím tắt và cách hoạt động của bàn phím trong Finder.")

                if !trusted {
                    permissionBanner
                    Divider().padding(.horizontal, 20)
                }

                SectionHeader(icon: "keyboard",
                              title: "Cắt & Dán trong Finder",
                              subtitle: "Dùng cùng cách bấm phím như khi chỉnh sửa văn bản lúc Finder đang hoạt động.")

                ToggleRow(title: "Bật Cắt & Dán (⌘X / ⌘V) trong Finder", isOn: $cutPaste)
                    .onChange(of: cutPaste) { controller.applySettings() }
                    .disabled(!trusted)
                    .padding(.horizontal, 20)

                SectionHeader(icon: "keyboard.badge.ellipsis",
                              title: "Hành vi bàn phím trong Finder",
                              subtitle: "Các phím tắt kiểu Windows tùy chọn, chỉ hoạt động trong vùng duyệt file của Finder.")

                VStack(alignment: .leading, spacing: 10) {
                    ToggleRow(title: "Phím Delete chuyển mục đã chọn vào Thùng rác", isOn: $deleteToTrash)
                        .onChange(of: deleteToTrash) { controller.applySettings() }
                        .disabled(!trusted)

                    ToggleRow(title: "Phím Return mở mục đã chọn", isOn: $returnOpens)
                        .onChange(of: returnOpens) { controller.applySettings() }
                        .disabled(!trusted)

                    Text("XFinder giữ nguyên chức năng của hai phím khi bạn đang đổi tên hoặc nhập nội dung trong Finder.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Cách hoạt động").font(.system(size: 15, weight: .semibold))
                    bullet("Chọn một file trong Finder rồi nhấn ⌘X để cắt.")
                    bullet("Nhấn ⌘V ở thư mục khác để DI CHUYỂN file tới đó.")
                    bullet("⌘Z vẫn hoàn tác được — vì dùng lệnh di chuyển của chính Finder.")
                    bullet("Cần quyền Trợ năng để nhận phím.")
                    bullet("Không ảnh hưởng ⌘X ở app khác như TextEdit.")
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            trusted = WindowManager.isTrusted
            controller.applySettings()
        }
    }

    private func bullet(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundColor(.secondary)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cần quyền Trợ năng", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
            Text("Các phím tắt này cần quyền Trợ năng để XFinder nhận được phím trước Finder.")
                .font(.system(size: 12)).foregroundColor(.secondary)
            HStack {
                Button("Mở Cài đặt Trợ năng") { WindowManager.openAccessibilityPane() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Kiểm tra lại") {
                    trusted = WindowManager.isTrusted
                    controller.applySettings()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
    }
}
