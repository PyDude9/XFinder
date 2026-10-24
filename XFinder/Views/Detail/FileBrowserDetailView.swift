import SwiftUI
import AppKit

/// XF-T28 — Trình duyệt tệp. Job: "the person comes here to open the file browser and decide how it starts".
/// Every switch here has its ONE reader in `BrowserSettings`; the defaults below must equal those readers.
struct FileBrowserDetailView: View {
    @AppStorage("fileBrowser.enabled") private var enabled = true
    @AppStorage("fileBrowser.reopenWindows") private var reopenWindows = true
    @AppStorage("fileBrowser.showHidden") private var showHidden = false
    @AppStorage("fileBrowser.foldersFirst") private var foldersFirst = false
    @AppStorage("fileBrowser.defaultView") private var defaultView = "list"
    @AppStorage("fileBrowser.globalHotkey") private var globalHotkey = false
    @State private var settings = BrowserSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Trình duyệt tệp"),
                           subtitle: L10n.t("Duyệt, gom và chép tệp giữa nhiều thư mục trong một cửa sổ — như Finder, chia được tới 16 ngăn."))

                SettingsSection(title: L10n.t("Mở trình duyệt")) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        Button {
                            BrowserWindowController.shared.openWindow(path: nil)
                        } label: {
                            Label(L10n.t("Mở cửa sổ mới"), systemImage: "square.split.2x2")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!enabled)
                        if !enabled {
                            Text(L10n.t("Trình duyệt tệp đang tắt — bật ở công tắc bên dưới."))
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        }
                    }
                    .settingsRow()
                    SettingsDivider()
                    ToggleRow(title: L10n.t("Bật trình duyệt tệp"),
                              subtitle: L10n.t("Không chạy gì khi chưa mở cửa sổ; đóng cửa sổ là hết theo dõi thư mục."),
                              isOn: $enabled)
                        .settingsRow()
                        .onChange(of: enabled) { _, _ in FeatureHub.apply(.fileBrowser) }
                    SettingsDivider()
                    ToggleRow(title: L10n.t("Phím tắt toàn cục ⌃⌥⌘F"),
                              subtitle: globalHotkey && enabled && !settings.hotkeyRegistered
                                  ? L10n.t("Một ứng dụng khác đang giữ ⌃⌥⌘F — phím tắt chưa hoạt động.")
                                  : L10n.t("Mở trình duyệt từ mọi ứng dụng. Tắt sẵn vì nó chiếm phím này của mọi ứng dụng khác."),
                              isOn: $globalHotkey)
                        .settingsRow()
                        .disabled(!enabled)
                        .onChange(of: globalHotkey) { _, _ in BrowserSettings.shared.applySettings() }
                }

                SettingsSection(title: L10n.t("Khi mở")) {
                    ToggleRow(title: L10n.t("Mở lại cửa sổ lần trước"),
                              subtitle: L10n.t("Cửa sổ, ngăn, thư mục và lịch sử quay lại trở về khi XFinder mở. Giữ Shift khi mở để bắt đầu với cửa sổ trống."),
                              isOn: $reopenWindows)
                        .settingsRow()
                    SettingsDivider()
                    HStack {
                        Text(L10n.t("Kiểu xem của ngăn mới")).font(XFinderTokens.Font.row)
                        Spacer()
                        Picker("", selection: $defaultView) {
                            Text(L10n.t("Xem dạng biểu tượng")).tag("icons")
                            Text(L10n.t("Xem dạng danh sách")).tag("list")
                            Text(L10n.t("Xem dạng cột")).tag("columns")
                            Text(L10n.t("Xem dạng gallery")).tag("gallery")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .settingsRow()
                    SettingsDivider()
                    ToggleRow(title: L10n.t("Hiện tệp ẩn"),
                              subtitle: L10n.t("Áp dụng cho ngăn mới; ⇧⌘. bật/tắt cho từng ngăn."),
                              isOn: $showHidden)
                        .settingsRow()
                    SettingsDivider()
                    ToggleRow(title: L10n.t("Thư mục luôn ở trên"),
                              subtitle: L10n.t("Như tuỳ chọn “Giữ thư mục ở trên cùng” của Finder."),
                              isOn: $foldersFirst)
                        .settingsRow()
                }

                SettingsSection(title: L10n.t("Phím tắt trong cửa sổ"),
                                footer: L10n.t("Mọi lệnh cũng có trong bảng lệnh: ⌃⇧⌘P, hoặc gõ > trong ⌃⌘P.")) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        ForEach(Self.highlighted, id: \.self) { command in
                            HStack {
                                Text(L10n.t(BrowserCommands.titleKey(command))).font(XFinderTokens.Font.rowValue)
                                Spacer()
                                if let chord = BrowserCommands.chord(for: command) {
                                    Text(BrowserCommands.display(chord))
                                        .font(XFinderTokens.Font.mono).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .settingsRow()
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    /// The shortcuts a newcomer needs first; the palette lists the rest.
    static let highlighted: [BrowserCommand] = [
        .splitRight, .splitDown, .zoomPane, .copyToOtherPane, .moveToOtherPane, .filter, .find,
        .quickOpen, .commandPalette, .toggleShelf, .operations, .batchRename,
    ]
}
