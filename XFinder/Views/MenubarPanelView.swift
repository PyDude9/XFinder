import SwiftUI

/// Compact menu-bar entry points for features that do not live in Notch tabs.
struct MenubarPanelView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            HStack(spacing: XFinderTokens.Space.inline) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous))
                Text("XFinder")
                    .font(XFinderTokens.Font.sectionTitle)
                Spacer()
            }
            VStack(spacing: 0) {
                if BrowserSettings.isEnabled {
                    actionRow("Trình duyệt tệp", symbol: "square.split.2x2") {
                        onClose()
                        BrowserWindowController.shared.openWindow(path: nil)
                    }
                    SettingsDivider()
                }

                actionRow("Gỡ ứng dụng", symbol: "xmark.bin") {
                    onClose()
                    AppState.shared.navigate(to: .uninstaller)
                }
                SettingsDivider()

                actionRow("Cài đặt…", symbol: "gearshape") {
                    onClose()
                    AppState.shared.navigate(to: .dashboard)
                }
                SettingsDivider()

                actionRow("Thoát", symbol: "power", opensWindow: false) {
                    onClose()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, XFinderTokens.Settings.cardInset)
            .background(XFinderTokens.Settings.cardFill, in: RoundedRectangle(
                cornerRadius: XFinderTokens.Settings.cardRadius, style: .continuous))
        }
        .padding(14)
        .frame(width: MenubarPanelRules.panelWidth, height: MenubarPanelRules.panelHeight)
        .background(XFinderTokens.Fill.window)
    }

    private func actionRow(_ title: String, symbol: String, opensWindow: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: XFinderTokens.Space.row) {
                Image(systemName: symbol)
                    .font(XFinderTokens.Font.sectionIcon)
                    .foregroundColor(.accentColor)
                    .frame(width: XFinderTokens.Settings.tileSize)
                Text(L10n.t(title))
                    .font(XFinderTokens.Font.row)
                    .foregroundStyle(.primary)
                Spacer()
                if opensWindow {
                    Image(systemName: "chevron.right")
                        .font(XFinderTokens.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .settingsRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
