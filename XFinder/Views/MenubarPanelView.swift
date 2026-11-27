import SwiftUI
import AppKit

/// Shared flat dark card container used across all Menu Bar Popover tabs.
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

private extension MenubarPanelTab {
    var settingsDestination: SidebarDestination {
        switch self {
        case .unsleep, .audio, .controls: return .features
        case .system: return .system
        case .network: return .network
        case .storage: return .storage
        case .battery: return .pin
        case .utilities: return .shortcuts
        }
    }
}

/// Floating Menu Bar Popover (`332 pt` wide) inspired by Vorssaint's clean dark tabbed panel.
/// Zero idle CPU: observers and samplers are retained ONLY while their respective tab is on screen.
struct MenubarPanelView: View {
    let onClose: () -> Void
    let onShowMenu: () -> Void

    @AppStorage("menubar.selectedTab") private var selectedTabRaw = MenubarPanelTab.unsleep.rawValue
    @State private var caffeine = CaffeineController.shared

    private var selectedTab: MenubarPanelTab {
        MenubarPanelRules.parseTab(selectedTabRaw)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            tabBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            HStack {
                Text(L10n.t(selectedTab.titleKey).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
                Spacer()
                Button {
                    onClose()
                    AppState.shared.navigate(to: selectedTab.settingsDestination)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Cài đặt…"))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 8) {
                    switch selectedTab {
                    case .unsleep: MenubarUnsleepTabView(onClose: onClose)
                    case .audio: AudioDisplayPanelTabView()
                    case .system: SystemPanelTabView(onOpenFull: { openSettings(.system) })
                    case .network: NetworkPanelTabView(onOpenFull: { openSettings(.network) })
                    case .storage: StoragePanelTabView(onOpenFull: { openSettings(.storage) })
                    case .battery: BatteryPanelTabView(onOpenFull: { openSettings(.pin) })
                    case .utilities: UtilitiesPanelTabView(onClose: onClose)
                    case .controls: ControlsPanelTabView()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.4)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: MenubarPanelRules.panelWidth, height: MenubarPanelRules.panelHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func openSettings(_ dest: SidebarDestination) {
        onClose()
        AppState.shared.navigate(to: dest)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("XFinder")
                    .font(.system(size: 14, weight: .bold))
                if caffeine.isActive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.yellow).frame(width: 6, height: 6)
                        if let rem = MenubarPanelRules.formatRemaining(seconds: caffeine.remainingSeconds) {
                            Text("\(L10n.t("Đang giữ máy thức")) · \(rem)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.yellow)
                                .monospacedDigit()
                        } else {
                            Text(L10n.t("Đang giữ máy thức"))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.16)))
                }
            }
            Spacer()
        }
    }

    // MARK: - Top Capsule Tab Bar

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(MenubarPanelTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        selectedTabRaw = tab.rawValue
                    }
                } label: {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.t(tab.titleKey))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                openSettings(selectedTab.settingsDestination)
            } label: {
                Label(L10n.t("Cài đặt…"), systemImage: "gearshape")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)

            Button {
                onShowMenu()
            } label: {
                Label(L10n.t("Danh sách"), systemImage: "list.bullet")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(L10n.t("Thoát"), systemImage: "power")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
        }
    }
}
