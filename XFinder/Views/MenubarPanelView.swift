import SwiftUI

struct MenubarPanelCardModifier: ViewModifier {
    var padding: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    func menubarPanelCard(padding: CGFloat = 10) -> some View {
        modifier(MenubarPanelCardModifier(padding: padding))
    }
}

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
            }
            .padding(.horizontal, XFinderTokens.Settings.cardInset)
            .background(XFinderTokens.Settings.cardFill, in: RoundedRectangle(
                cornerRadius: XFinderTokens.Settings.cardRadius, style: .continuous))
        }
        .padding(14)
        .frame(width: MenubarPanelRules.panelWidth, height: MenubarPanelRules.panelHeight)
        .background(XFinderTokens.Fill.window)
    }

    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
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
                Image(systemName: "chevron.right")
                    .font(XFinderTokens.Font.caption)
                    .foregroundStyle(.tertiary)
            }
            .settingsRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
