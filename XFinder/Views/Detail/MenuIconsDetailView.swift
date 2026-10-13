import SwiftUI

/// Biểu tượng thanh menu — nút MŨI TÊN ẩn/hiện biểu tượng qua Native Visibility Engine (macOS 27+)
/// và Legacy Length Engine (macOS <= 26).
struct MenuIconsDetailView: View {
    @State private var hider = MenuBarHiderController.shared
    @AppStorage("menubar.hiderEnabled") private var enabled = true
    @AppStorage("menubar.defaultCollapsed") private var defaultCollapsed = true
    @AppStorage("menubar.autoHideEnabled") private var autoHideEnabled = false
    @AppStorage("menubar.autoHideSeconds") private var autoHideSeconds = 5.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(
                    icon: "menubar.rectangle",
                    title: L10n.t("Biểu tượng thanh menu"),
                    subtitle: L10n.t("Ẩn bớt biểu tượng trên thanh menu để gọn gàng hơn.")
                )

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(
                        icon: "chevron.left.chevron.right",
                        title: L10n.t("Nút mũi tên ẩn biểu tượng"),
                        subtitle: L10n.t("Ẩn các biểu tượng ứng dụng nằm bên trái mũi tên.")
                    )

                    ToggleRow(
                        title: L10n.t("Bật ẩn biểu tượng thanh menu"),
                        subtitle: L10n.t("Hiện nút mũi tên trên thanh menu để thu gọn hoặc mở rộng."),
                        isOn: Binding(
                            get: { enabled },
                            set: {
                                enabled = $0
                                hider.isEnabled = $0
                            }
                        )
                    )
                    .padding(.horizontal, XFinderTokens.Space.page)

                    if enabled {
                        Divider().padding(.horizontal, XFinderTokens.Space.page)

                        ToggleRow(
                            title: L10n.t("Mặc định thu gọn khi mở app"),
                            subtitle: L10n.t("Tự động ẩn các biểu tượng ngay khi XFinder khởi động."),
                            isOn: Binding(
                                get: { defaultCollapsed },
                                set: {
                                    defaultCollapsed = $0
                                    hider.defaultCollapsed = $0
                                }
                            )
                        )
                        .padding(.horizontal, XFinderTokens.Space.page)

                        Divider().padding(.horizontal, XFinderTokens.Space.page)

                        ToggleRow(
                            title: L10n.t("Tự động ẩn sau thời gian chờ"),
                            subtitle: L10n.t("Tự động thu gọn các biểu tượng sau khi mở rộng."),
                            isOn: Binding(
                                get: { autoHideEnabled },
                                set: {
                                    autoHideEnabled = $0
                                    hider.isAutoHideEnabled = $0
                                }
                            )
                        )
                        .padding(.horizontal, XFinderTokens.Space.page)

                        if autoHideEnabled {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t("Thời gian tự động ẩn"))
                                        .font(XFinderTokens.Font.row)
                                    Text("\(L10n.t("Thu gọn sau "))\(Int(autoHideSeconds))\(L10n.t(" giây không thao tác"))")
                                        .font(XFinderTokens.Font.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Slider(
                                    value: Binding(
                                        get: { autoHideSeconds },
                                        set: {
                                            autoHideSeconds = $0
                                            hider.autoHideSeconds = $0
                                        }
                                    ),
                                    in: 1...30,
                                    step: 1
                                )
                                .frame(width: 140)
                                Text("\(Int(autoHideSeconds))s")
                                    .font(XFinderTokens.Font.mono)
                                    .frame(width: 32, alignment: .trailing)
                            }
                            .padding(.horizontal, XFinderTokens.Space.page)
                            .padding(.top, 6)
                        }
                    }

                    Divider().padding(.horizontal, XFinderTokens.Space.page)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("Động cơ ẩn biểu tượng"))
                                .font(XFinderTokens.Font.row)
                            Text(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
                                 ? L10n.t("Native Visibility Engine (Assessment Mode)")
                                 : L10n.t("Legacy Length Engine"))
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "macOS 27+ Native" : "Legacy")
                            .font(XFinderTokens.Font.mono)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(XFinderTokens.Fill.inset)
                            .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge))
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(
                        icon: "questionmark.circle",
                        title: L10n.t("Cách sử dụng"),
                        subtitle: L10n.t("Sắp xếp biểu tượng linh hoạt bằng phím ⌘.")
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        bullet(L10n.t("Nhấp vào nút mũi tên trên thanh menu để thu gọn hoặc mở rộng các biểu tượng."))
                        bullet(L10n.t("Giữ phím Command (⌘) và kéo thả bất kỳ biểu tượng nào sang bên phải mũi tên để luôn hiển thị."))
                        bullet(L10n.t("Các biểu tượng nằm bên trái mũi tên sẽ tự động được ẩn khi thu gọn."))
                        bullet(L10n.t("Các biểu tượng hệ thống (Đồng hồ, Wi-Fi, Pin, Trung tâm điều khiển) luôn luôn được giữ lại."))
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)

                    Button(L10n.t("Mở Cài đặt thanh menu của macOS")) {
                        hider.openSystemMenuBarSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.horizontal, XFinderTokens.Space.page)
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
