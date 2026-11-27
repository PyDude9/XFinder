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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("XFinder")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
            }
            .padding(.bottom, 4)

            Text(L10n.t("CHUNG"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.7)

            VStack(spacing: 5) {
                if BrowserSettings.isEnabled {
                    actionRow("Trình duyệt tệp", symbol: "square.split.2x2") {
                        onClose()
                        BrowserWindowController.shared.openWindow(path: nil)
                    }
                }

                actionRow("Gỡ ứng dụng", symbol: "xmark.bin") {
                    onClose()
                    AppState.shared.navigate(to: .uninstaller)
                }

                actionRow("Cài đặt…", symbol: "gearshape") {
                    onClose()
                    AppState.shared.navigate(to: .dashboard)
                }
            }
        }
        .padding(14)
        .frame(width: MenubarPanelRules.panelWidth, height: MenubarPanelRules.panelHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                Text(L10n.t(title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
