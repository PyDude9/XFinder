import SwiftUI

/// Vorssaint-inspired 3×3 Section Gallery for the expanded Dynamic Island (612 × 156 wide body,
/// inner budget 584 × 140). Lets the user jump straight to any page or inline telemetry/audio
/// deck by clicking a tile or pressing its letter / 1–9 key.
struct NotchSectionsView: View {
    var model: NotchSurfaceModel
    @State private var hoveredID: String?
    @Environment(\.notchAccent) private var accent

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var galleryItems: [NotchGalleryItem] {
        NotchGalleryRules.items(
            catalog: model.tabCatalog,
            availability: model.destinationAvailability
        )
    }

    var body: some View {
        let items = galleryItems
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                Text(L10n.t("Tất cả mục Dynamic Island đang ẩn"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Button {
                    NotchSurfaceController.shared.openNotchSettings()
                } label: {
                    Label(L10n.t("Mở Cài đặt Dynamic Island"), systemImage: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Mở Cài đặt Dynamic Island"))
            }
            .frame(maxWidth: .infinity, maxHeight: 140)
        } else {
            let compactRows = items.count > 9
            ScrollView {
                LazyVGrid(columns: columns, spacing: compactRows ? 5 : 6) {
                    ForEach(items) { item in
                        tile(item, height: compactRows ? 31 : 42)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 140, alignment: .top)
        }
    }

    @ViewBuilder
    private func tile(_ item: NotchGalleryItem, height: CGFloat = 42) -> some View {
        let active = isAvailable(item.destination)
        let hovered = hoveredID == item.id
        let isCurrent = isCurrentSelection(item.destination)

        Button {
            if active {
                NotchSurfaceController.shared.selectGalleryDestination(item.destination)
            } else if let settingsDest = settingsDestination(for: item.destination) {
                NotchSurfaceController.shared.dismiss()
                AppState.shared.navigate(to: settingsDest)
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tileTint(item.destination).opacity(active ? 0.20 : 0.08))
                        .frame(width: 26, height: 26)
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(active ? tileTint(item.destination) : .white.opacity(0.35))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t(item.titleKey))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(active ? .white : .white.opacity(0.45))
                        .lineLimit(1)
                    if let sub = liveBadge(for: item.destination, available: active) {
                        Text(sub)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(badgeColor(for: item.destination, available: active))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !item.shortcutKey.isEmpty {
                    Text(item.shortcutKey)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(hovered ? 0.85 : 0.45))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(hovered ? 0.16 : 0.07))
                        )
                }
            }
            .padding(.horizontal, 8)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? accent.opacity(0.22) : Color.white.opacity(hovered ? 0.14 : 0.065))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isCurrent ? accent.opacity(0.7) : Color.white.opacity(hovered ? 0.22 : 0.08),
                        lineWidth: isCurrent ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { over in hoveredID = over ? item.id : (hoveredID == item.id ? nil : hoveredID) }
        .help(active ? L10n.t(item.titleKey) : L10n.t("Cần bật trong Cài đặt"))
    }

    private func isAvailable(_ dest: NotchGalleryDestination) -> Bool {
        switch dest {
        case .extra(.weather):
            return model.weatherAvailable
        case .extra(.stocks):
            return model.stocksAvailable
        case .extra(.revenue):
            return model.revenueAvailable
        case .page(.files), .page(.clipboard), .page(.timer), .extra:
            return true
        case .page(.nowPlaying):
            return model.nowPlayingAvailability != .off
        case .page(.agents), .page(.aiUsage):
            return model.agentsEnabled
        case .page(.calendar):
            return model.calendarEnabled
        }
    }

    private func isCurrentSelection(_ dest: NotchGalleryDestination) -> Bool {
        if case .extra(let e) = dest, model.extraModule == e { return true }
        return false
    }

    private func settingsDestination(for dest: NotchGalleryDestination) -> SidebarDestination? {
        guard let id = NotchDestinationID(destination: dest) else { return nil }
        let readiness = model.destinationAvailability.readiness(for: id)
        guard let target = id.settingsTarget(for: readiness) else { return nil }
        return SidebarDestination(rawValue: target)
    }

    private func liveBadge(for dest: NotchGalleryDestination, available: Bool) -> String? {
        guard available else { return L10n.t("Tắt") }
        switch dest {
        case .page(.files):
            return model.itemCount > 0 ? "\(model.itemCount)\(L10n.t(" tệp"))" : nil
        case .page(.nowPlaying):
            return model.nowPlaying?.playing == true ? model.nowPlaying?.headline : nil
        case .page(.agents):
            if model.agentsNeedingYou > 0 { return "\(model.agentsNeedingYou)\(L10n.t(" đang chờ"))" }
            return model.agentCount > 0 ? "\(model.agentCount)" : nil
        case .page(.timer):
            return model.timerText
        case .page(.calendar):
            return model.calendarEvents.first?.title
        default:
            return nil
        }
    }

    private func badgeColor(for dest: NotchGalleryDestination, available: Bool) -> Color {
        guard available else { return .white.opacity(0.35) }
        switch dest {
        case .page(.agents) where model.agentsNeedingYou > 0: return .orange
        case .page(.timer): return .orange
        case .page(.nowPlaying): return .green.opacity(0.9)
        default: return .white.opacity(0.55)
        }
    }

    private func tileTint(_ dest: NotchGalleryDestination) -> Color {
        switch dest {
        case .page(.files): return .mint
        case .page(.clipboard): return .green
        case .page(.nowPlaying): return .pink
        case .page(.agents): return .purple
        case .page(.calendar): return .red
        case .page(.timer): return .orange
        case .page(.aiUsage): return .indigo
        case .extra(.home): return .blue
        case .extra(.system), .extra(.sections), .extra(.settings): return .cyan
        case .extra(.audio): return .blue
        case .extra(.reminders): return .orange
        case .extra(.weather): return .teal
        case .extra(.stocks): return .green
        case .extra(.revenue): return .mint
        case .extra(.websiteAnalytics): return .cyan
        case .extra(.mirror): return .teal
        case .extra(.teleprompter): return .orange
        case .extra(.notes): return .yellow
        case .extra(.capture): return .indigo
        case .extra(.units): return .teal
        case .extra(.scratchpad): return .yellow
        case .extra(.emoji): return .pink
        case .extra(.fileBrowser): return .blue
        case .extra(.links): return .cyan
        case .extra(.imageConvert): return .purple
        case .extra(.sounds): return .teal
        case .extra(.todos): return .green
        case .extra(.shortcuts): return .purple
        case .extra(.appUsage): return .indigo
        case .extra(.localChat): return .blue
        case .extra(.message): return .mint
        case .extra(.feedback): return .pink
        }
    }
}
