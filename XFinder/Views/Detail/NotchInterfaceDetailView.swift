import SwiftUI

/// Giao diện notch — the user comes here to decide whether the notch is on, what a hover does, how it
/// looks on each kind of screen, and which pages it shows. Split off "Notch & Khay thả" (P3): this page
/// owns the notch SURFACE; Khay thả (`DropTrayDetailView`) owns the files held in it.
struct NotchInterfaceDetailView: View {
    // Master switch of the whole notch surface (NotchSurfaceController.swift:63-64) — turning it off
    // disables the tray, clipboard, now playing, agents and calendar surfaces all at once.
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true

    // Every hover on the notch is gated by this one switch (NotchSurfaceMachine.swift:151) — off, a
    // file drag and a shake still open the tray, but resting the pointer on the notch never does.
    @AppStorage("dropTray.hoverEnabled") private var hoverEnabled = true
    @AppStorage("notch.hoverOpens") private var hoverOpens = "peek"   // N2 (replaces notch.clipboardOnHover)
    @AppStorage("notch.hoverSpeed") private var hoverSpeed = "medium"

    // B7 notch behaviour. Readers: NotchSurfaceController (defaults must match — FeatureKeyDefaultsTests).
    @AppStorage("notch.pillOnPlainScreens") private var pillOnPlainScreens = true
    @AppStorage("notch.hideFromCapture") private var hideFromCapture = false

    /// D1 #44 — page order + visibility; one reader: `NotchSurfaceController.pageOrderRaw`.
    @AppStorage("notch.pages") private var pagesRaw = "files,clipboard,nowPlaying,agents,calendar,timer,aiUsage"
    /// D1 #47 — accent of the notch surfaces; one reader: `NotchSurfaceController.accentName`.
    @AppStorage("notch.accent") private var accent = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Giao diện notch"),
                    subtitle: L10n.t("Bật tắt notch, chỉnh cách rê chuột mở nó, hình dạng trên từng loại màn hình và các trang nó hiện."),
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(notchEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            Toggle("", isOn: $notchEnabled)
                                .labelsHidden()
                                .onChange(of: notchEnabled) { NotchSurfaceController.shared.applySettings() }
                        }
                    ))

                hoverSection
                    .disabled(!notchEnabled)
                shapeSection
                    .disabled(!notchEnabled)
                pagesSection
                    .disabled(!notchEnabled)
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    /// The user comes here to decide what resting the pointer on the notch does.
    private var hoverSection: some View {
        SettingsSection(title: L10n.t("Rê chuột vào notch"),
                        footer: L10n.t("Áp dụng cho mọi thứ hiện ở notch: khay, clipboard, thông báo, bài đang phát.")) {
            ToggleRow(title: L10n.t("Rê chuột vào notch"),
                      subtitle: L10n.t("Nút chính của mọi hiệu ứng rê chuột trên notch. Tắt thì kéo file vào notch hoặc lắc khi đang kéo file vẫn mở được khay — chỉ riêng việc dừng con trỏ ở notch là không còn phản ứng."),
                      isOn: $hoverEnabled)
                .settingsRow()
            SettingsDivider()
            HStack(alignment: .firstTextBaseline, spacing: XFinderTokens.Space.inline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Rê chuột vào notch mở")).font(XFinderTokens.Font.row)
                    Text(L10n.t("Chỉ xem nhanh: dừng con trỏ hiện tệp đang giữ hoặc bài đang phát; khay trống không mở gì. Các lựa chọn khác mở thẳng trang đó. Theo hoạt động chọn trang theo việc đang diễn ra: agent chờ bạn → Agent AI, nhạc đang phát → Đang phát, có tệp → Khay, còn lại → Clipboard."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $hoverOpens) {
                    ForEach(NotchHoverOpen.allCases, id: \.rawValue) { h in
                        Text(L10n.t(h.labelKey)).tag(h.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 170)
                .onChange(of: hoverOpens) { NotchSurfaceController.shared.applySettings() }
            }
            .disabled(!hoverEnabled)
            .settingsRow()
            SettingsDivider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Độ nhạy rê chuột")).font(XFinderTokens.Font.row)
                    Text(L10n.t("Con trỏ phải đứng yên ở notch bao lâu thì tính là rê vào: 0,12 · 0,25 · 0,5 giây."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $hoverSpeed) {
                    Text(L10n.t("Nhanh")).tag("fast")
                    Text(L10n.t("Vừa")).tag("medium")
                    Text(L10n.t("Chậm")).tag("slow")
                }
                // segmented-ok: 3 cases
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                .onChange(of: hoverSpeed) { NotchSurfaceController.shared.applySettings() }
            }
            .disabled(!hoverEnabled)
            .settingsRow()
        }
    }

    /// The user comes here to decide how the notch looks on this Mac: a notch-less screen, screen
    /// recordings, screen sharing.
    private var shapeSection: some View {
        SettingsSection(
            title: L10n.t("Hình dạng"),
            footer: L10n.t("Trên màn hình không có notch, XFinder vẽ một notch ảo: các bề mặt dính mép trên, ở giữa thanh menu, y như ở notch thật; rê chuột vào giữa mép trên để xem các tệp đang giữ.")
        ) {
            ToggleRow(title: L10n.t("Pill trên màn hình không có notch"),
                      subtitle: L10n.t("Màn hình ngoài / iMac: tệp đang giữ, hẹn giờ và bài đang phát hiện trong một viên thuốc nhỏ dính mép trên, giữa thanh menu. Chưa đo trên màn hình thật — chỉ hình học."),
                      isOn: $pillOnPlainScreens)
                .onChange(of: pillOnPlainScreens) { NotchSurfaceController.shared.applySettings() }
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Không hiện trong ảnh chụp, quay và chia sẻ màn hình"),
                      subtitle: L10n.t("Cửa sổ notch được đánh dấu không chia sẻ (sharingType none) nên screencapture, quay màn hình và chia sẻ qua Zoom/FaceTime không thấy nó. Đo được: kCGWindowSharingState = 0."),
                      isOn: $hideFromCapture)
                .onChange(of: hideFromCapture) { NotchSurfaceController.shared.applySettings() }
                .settingsRow()
        }
    }

    /// D1 #44 / #47: which tabs the hub shows and in what order, and the surfaces' accent.
    private var pagesSection: some View {
        let shown = NotchPages.parse(pagesRaw)
        return SettingsSection(
            title: L10n.t("Các trang trên notch"),
            footer: L10n.t("Bật, tắt và sắp xếp thứ tự các tab trong hub. Tắt Clipboard thì ⌘⇧V mở khay nổi cũ. Vuốt hai ngón ngang trên dải tab để đổi trang.")
        ) {
            ForEach(Array(NotchPages.allInOrder(shown: shown).enumerated()), id: \.element) { entry in
                let page = entry.element
                let isShown = shown.contains(page)
                let index = shown.firstIndex(of: page)
                if entry.offset > 0 { SettingsDivider() }
                HStack(spacing: XFinderTokens.Space.inline) {
                    Image(systemName: pageIcon(page)).font(XFinderTokens.Font.sectionIcon).foregroundColor(.secondary).frame(width: 18)
                    Text(pageTitle(page)).font(XFinderTokens.Font.row)
                    Spacer()
                    Button { pagesRaw = NotchPages.serialize(NotchPages.moved(page, by: -1, in: shown)) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!isShown || index == 0)
                        .help(L10n.t("Lên"))
                        .accessibilityLabel(L10n.t("Lên"))
                    Button { pagesRaw = NotchPages.serialize(NotchPages.moved(page, by: 1, in: shown)) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!isShown || index == shown.count - 1)
                        .help(L10n.t("Xuống"))
                        .accessibilityLabel(L10n.t("Xuống"))
                    Toggle("", isOn: Binding(get: { isShown },
                                             set: { _ in pagesRaw = NotchPages.serialize(NotchPages.toggled(page, in: shown)) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .disabled(isShown && shown.count == 1)
                }
                .settingsRow()
            }
            SettingsDivider()
            HStack {
                Spacer()
                Button(L10n.t("Khôi phục mặc định")) { pagesRaw = NotchPages.defaultRaw }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .settingsRow()
            SettingsDivider()
            PickerRow(title: L10n.t("Màu nhấn"),
                      subtitle: L10n.t("Màu của viền chọn, thẻ đang chọn và các điểm nhấn trên notch."),
                      selection: $accent, width: 150) {
                Text(L10n.t("Theo hệ thống")).tag("system")
                Text(L10n.t("Xanh dương")).tag("blue")
                Text(L10n.t("Tím")).tag("purple")
                Text(L10n.t("Hồng")).tag("pink")
                Text(L10n.t("Cam")).tag("orange")
                Text(L10n.t("Xanh lá")).tag("green")
                Text(L10n.t("Xanh ngọc")).tag("teal")
            }
            .onChange(of: accent) { NotchSurfaceController.shared.applySettings() }
            .settingsRow()
        }
        .onChange(of: pagesRaw) { NotchSurfaceController.shared.applySettings() }
    }

    /// One title and one symbol per page, shared with the hub (`NotchPages`).
    private func pageTitle(_ p: NotchSurfaceMachine.Page) -> String { L10n.t(NotchPages.titleKey(p)) }
    private func pageIcon(_ p: NotchSurfaceMachine.Page) -> String { NotchPages.symbol(p) }
}
