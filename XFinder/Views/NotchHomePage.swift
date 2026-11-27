import SwiftUI

/// Dynamic Island Home ("Tổng quan") view.
///
/// Reads ONLY existing snapshots on `NotchSurfaceModel` (Now Playing, Calendar, active Clock / Agents / Files)
/// strictly gated by `model.tabCatalog` and `model.destinationAvailability`. Starts no monitors, requests no
/// permissions, and performs no network or EventKit calls. Adapts cleanly between wide (`612 pt`) and narrow
/// (`382 pt`) Island bodies with full VoiceOver labels and XFinder dark-glass styling.
struct NotchHomePage: View {
    var model: NotchSurfaceModel
    var excludedQuickDestinationID: NotchDestinationID? = nil
    @Environment(\.notchAccent) private var accent

    private var snapshot: NotchHomeRules.Snapshot {
        let now = model.timerNow
        let npInput: NotchHomeRules.NowPlayingInput? = model.nowPlaying.map { np in
            NotchHomeRules.NowPlayingInput(
                headline: np.headline,
                subline: np.subline,
                isPlaying: np.playing,
                appName: model.nowPlayingAppName
            )
        }

        let calInput: NotchHomeRules.CalendarInput? = {
            guard model.calendarAccess == .granted else { return nil }
            let upNext = GlanceRules.upNext(model.calendarEvents, now: now)
            return NotchHomeRules.CalendarInput(
                isAuthorized: true,
                title: upNext?.title,
                start: upNext?.start,
                end: upNext?.end,
                isAllDay: upNext?.isAllDay ?? false,
                hasMeetingLink: upNext.flatMap { GlanceRules.meetingURL(in: $0) } != nil,
                todayCount: model.calendarEvents.count
            )
        }()

        let workInput = NotchHomeRules.ActiveWorkInput(
            clockLabel: model.timerText,
            clockMode: model.timerBadgeMode,
            clockSymbol: model.timerBadgeSymbol,
            clockPaused: model.timerBadgePaused,
            agentCount: model.agentCount,
            agentsNeedingYou: model.agentsNeedingYou,
            agentBusy: model.agentBusy,
            stagedFileCount: model.itemCount,
            hasActiveFileTask: model.task != nil
        )

        return NotchHomeRules.build(
            NotchHomeRules.Input(
                catalog: model.tabCatalog,
                availability: model.destinationAvailability,
                now: now,
                nowPlaying: npInput,
                calendar: calInput,
                activeWork: workInput,
                excludedQuickDestinationID: excludedQuickDestinationID
            )
        )
    }

    var body: some View {
        let snap = snapshot
        GeometryReader { geo in
            let isNarrow = geo.size.width < 460
            if snap.isEmpty {
                emptyState(quickDestinations: snap.quickDestinations, isNarrow: isNarrow)
            } else if isNarrow {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(snap.cards) { card in
                            narrowCardRow(card)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ForEach(snap.cards) { card in
                            wideCard(card)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !snap.quickDestinations.isEmpty {
                        quickStrip(snap.quickDestinations)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 140, alignment: .top)
    }

    // MARK: - Empty State

    private func emptyState(quickDestinations: [NotchDestinationID], isNarrow: Bool) -> some View {
        VStack(spacing: isNarrow ? 6 : 8) {
            Spacer(minLength: 0)
            Image(systemName: "house.fill")
                .font(.system(size: isNarrow ? 16 : 18, weight: .semibold))
                .foregroundStyle(accent)
            Text(L10n.t("Chưa có hoạt động nào từ các tab đang bật"))
                .font(.system(size: isNarrow ? 11 : 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(L10n.t("Bật nhạc, lịch hoặc bắt đầu tác vụ để xem nhanh tại đây."))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: isNarrow ? 320 : 420)

            HStack(spacing: 6) {
                ForEach(quickDestinations.prefix(isNarrow ? 3 : 4), id: \.self) { id in
                    quickChip(id)
                }
                Button {
                    NotchSurfaceController.shared.openNotchSettings()
                } label: {
                    Label(L10n.t("Cài đặt"), systemImage: "gearshape")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Cài đặt"))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Wide Card (3-up dark glass)

    private func wideCard(_ card: NotchHomeRules.Card) -> some View {
        let tint = color(for: card.tint)
        let title = resolvedTitle(card)
        let sub = resolvedSubtitle(card)
        let badge = resolvedBadge(card)

        return Button {
            NotchSurfaceController.shared.selectGalleryDestination(card.destination)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.20))
                            .frame(width: 22, height: 22)
                        Image(systemName: card.symbol)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text(L10n.t(card.headerKey))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(tint.opacity(0.16)))
                            .lineLimit(1)
                    }
                }

                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text(sub)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if card.extraActiveCount > 0 {
                        Text("+\(card.extraActiveCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.065))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L10n.t(card.headerKey)): \(title), \(sub)")
        .accessibilityHint("\(L10n.t("Mở "))\(L10n.t(card.destinationID.titleKey))")
    }

    // MARK: - Narrow Row Card

    private func narrowCardRow(_ card: NotchHomeRules.Card) -> some View {
        let tint = color(for: card.tint)
        let title = resolvedTitle(card)
        let sub = resolvedSubtitle(card)
        let badge = resolvedBadge(card)

        return Button {
            NotchSurfaceController.shared.selectGalleryDestination(card.destination)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.20))
                        .frame(width: 26, height: 26)
                    Image(systemName: card.symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(sub)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(tint.opacity(0.16)))
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.065))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L10n.t(card.headerKey)): \(title), \(sub)")
        .accessibilityHint("\(L10n.t("Mở "))\(L10n.t(card.destinationID.titleKey))")
    }

    // MARK: - Quick Open Strip

    private func quickStrip(_ ids: [NotchDestinationID]) -> some View {
        HStack(spacing: 6) {
            Text(L10n.t("Mở nhanh"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            ForEach(ids, id: \.self) { id in
                quickChip(id)
            }
            Spacer(minLength: 0)
        }
    }

    private func quickChip(_ id: NotchDestinationID) -> some View {
        Button {
            NotchSurfaceController.shared.selectGalleryDestination(id.destination)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: id.symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(L10n.t(id.titleKey))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L10n.t("Mở "))\(L10n.t(id.titleKey))")
    }

    // MARK: - Formatting

    private func resolvedTitle(_ card: NotchHomeRules.Card) -> String {
        if let literal = card.titleLiteral, !literal.isEmpty { return literal }
        if let key = card.titleKey { return L10n.t(key) }
        return L10n.t(card.headerKey)
    }

    private func resolvedSubtitle(_ card: NotchHomeRules.Card) -> String {
        switch card.subtitle {
        case .literal(let text):
            return text
        case .statusKey(let key):
            return L10n.t(key)
        case .clockTime(let modeKey, let paused):
            let status = paused ? L10n.t("Đang tạm dừng") : L10n.t("Đang chạy")
            return "\(L10n.t(modeKey)) · \(status)"
        case .agentCount(let total, let waiting, let busy):
            if waiting > 0 {
                return "\(waiting)\(L10n.t(" chờ phản hồi")) · \(total)\(L10n.t(" phiên"))"
            }
            let state = busy ? L10n.t("Đang bận") : L10n.t("Đang chạy")
            return "\(total)\(L10n.t(" phiên")) · \(state)"
        case .fileCount(let count, let activeTask):
            if activeTask && count == 0 {
                return L10n.t("Đang chạy")
            }
            return "\(count)\(L10n.t(" tệp"))"
        case .calendarTime(let start, let inProgress):
            let time = NotchHomeRules.formatEventTime(start)
            return inProgress ? "\(L10n.t("Đang diễn ra")) · \(time)" : time
        }
    }

    private func resolvedBadge(_ card: NotchHomeRules.Card) -> String? {
        switch card.badge {
        case .none:
            return nil
        case .status(let key):
            return L10n.t(key)
        case .countWaiting(let n):
            return "\(n)\(L10n.t(" chờ phản hồi"))"
        }
    }

    private func color(for tint: NotchHomeRules.CardTint) -> Color {
        switch tint {
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .purple: return .purple
        case .mint: return .mint
        case .cyan: return .cyan
        }
    }
}
