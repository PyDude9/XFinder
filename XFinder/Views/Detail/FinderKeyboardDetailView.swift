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
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "keyboard",
                           title: L10n.t("Bàn phím Finder"),
                           subtitle: L10n.t("Tùy chỉnh phím tắt và cách hoạt động của bàn phím trong Finder."))

                if !trusted {
                    permissionBanner
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                }

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "keyboard",
                                  title: L10n.t("Cắt & Dán trong Finder"),
                                  subtitle: L10n.t("Dùng cùng cách bấm phím như khi chỉnh sửa văn bản lúc Finder đang hoạt động."))

                    ToggleRow(title: L10n.t("Bật Cắt & Dán (⌘X / ⌘V) trong Finder"), isOn: $cutPaste)
                        .onChange(of: cutPaste) { controller.applySettings() }
                        .disabled(!trusted)
                        .padding(.horizontal, XFinderTokens.Space.page)
                }

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "keyboard.badge.ellipsis",
                                  title: L10n.t("Hành vi bàn phím trong Finder"),
                                  subtitle: L10n.t("Các phím tắt kiểu Windows tùy chọn, chỉ hoạt động trong vùng duyệt file của Finder."))

                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        ToggleRow(title: L10n.t("Phím Delete chuyển mục đã chọn vào Thùng rác"), isOn: $deleteToTrash)
                            .onChange(of: deleteToTrash) { controller.applySettings() }
                            .disabled(!trusted)

                        ToggleRow(title: L10n.t("Phím Return mở mục đã chọn"), isOn: $returnOpens)
                            .onChange(of: returnOpens) { controller.applySettings() }
                            .disabled(!trusted)

                        Text(L10n.t("XFinder giữ nguyên chức năng của hai phím khi bạn đang đổi tên hoặc nhập nội dung trong Finder."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "questionmark.circle", title: L10n.t("Cách hoạt động"))

                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        bullet(L10n.t("Chọn một file trong Finder rồi nhấn ⌘X để cắt."))
                        bullet(L10n.t("Nhấn ⌘V ở thư mục khác để DI CHUYỂN file tới đó."))
                        bullet(L10n.t("⌘Z vẫn hoàn tác được — vì dùng lệnh di chuyển của chính Finder."))
                        bullet(L10n.t("Cần quyền Trợ năng để nhận phím."))
                        bullet(L10n.t("Không ảnh hưởng ⌘X ở app khác như TextEdit."))
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear {
            trusted = WindowManager.isTrusted
            controller.applySettings()
        }
    }

    private func bullet(_ text: String) -> some View {
        Text(text).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Label(L10n.t("Cần quyền Trợ năng"), systemImage: "exclamationmark.triangle.fill")
                .font(XFinderTokens.Font.row)
                .foregroundColor(.orange)
            Text(L10n.t("Các phím tắt này cần quyền Trợ năng để XFinder nhận được phím trước Finder."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            HStack {
                Button(L10n.t("Mở Cài đặt Trợ năng")) { WindowManager.openAccessibilityPane() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(L10n.t("Kiểm tra lại")) {
                    trusted = WindowManager.isTrusted
                    controller.applySettings()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }
}
