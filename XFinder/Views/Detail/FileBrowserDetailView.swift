import SwiftUI
import AppKit

/// Unified File Browser settings, hosted in the main XFinder window.
struct FileBrowserDetailView: View {
    @AppStorage("fileBrowser.enabled") private var enabled = true
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

                BrowserSettingsContentView()

                SettingsSection(title: L10n.t("Phím tắt trong cửa sổ"),
                                footer: L10n.t("Mọi lệnh cũng có trong bảng lệnh: ⌃⇧⌘P, hoặc gõ > trong ⌃⌘P. Chọn nhóm Bàn phím trên trang này để đổi phím.")) {
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

    /// The shortcuts a newcomer needs first; the palette and the Keyboard tab of Settings list the rest.
    static let highlighted: [BrowserCommand] = [
        .splitRight, .splitDown, .zoomPane, .copyToOtherPane, .moveToOtherPane, .filter, .find,
        .quickOpen, .commandPalette, .toggleShelf, .operations, .batchRename,
    ]
}
