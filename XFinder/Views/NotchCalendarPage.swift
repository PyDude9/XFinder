import SwiftUI
import AppKit

/// P2 + XF-ISLAND 2 — Calendar tool for the NARROW notch body (content 354 × 140).
/// Preserves legacy `CalendarGlanceMonitor` data and lifecycle, adding interactive day selection
/// on the 9-day strip and a compact month grid toggle for browsing dates and agendas.
struct NotchCalendarPage: View {
    var model: NotchSurfaceModel
    @Environment(\.notchAccent) private var accent

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingMonthGrid = false

    private typealias N = XFinderTokens.Notch
    private static let m = NotchSurfaceLayout.Metrics.standard

    private var locale: Locale { Locale(identifier: L10n.isEnglish ? "en_US" : "vi_VN") }

    var body: some View {
        Group {
            if model.calendarAccess != .granted {
                accessState
            } else {
                granted
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Access not granted / denied

    @ViewBuilder private var accessState: some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(XFinderTokens.Font.pageIcon)
                .opacity(0.65)
            Text(model.calendarAccess == .notDetermined || model.calendarAccess == .unknown
                 ? L10n.t("Chưa có quyền Lịch. Cấp quyền để thấy sự kiện hôm nay.")
                 : L10n.t("Quyền Lịch bị từ chối — mở Cài đặt hệ thống ▸ Quyền riêng tư ▸ Lịch."))
                .font(XFinderTokens.Font.caption)
                .opacity(0.65)
                .multilineTextAlignment(.center)
            Button(L10n.t("Cấp quyền Lịch")) { NotchSurfaceController.shared.requestCalendarAccess() }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Granted

    @ViewBuilder private var granted: some View {
        let now = Date()
        let cal = Calendar.current
        let activeDay = cal.startOfDay(for: selectedDay)
        VStack(alignment: .leading, spacing: 0) {
            header(now: now, activeDay: activeDay, calendar: cal)
                .frame(height: Self.m.calendarHeaderHeight, alignment: .top)
            Spacer(minLength: 0).frame(height: Self.m.calendarHeaderGap)
            if showingMonthGrid {
                monthGridView(now: now, activeDay: activeDay, calendar: cal)
                    .frame(height: Self.m.calendarStripHeight + Self.m.calendarStripGap + Self.m.calendarListHeight, alignment: .top)
            } else {
                strip(now: now, activeDay: activeDay, calendar: cal)
                    .frame(height: Self.m.calendarStripHeight, alignment: .top)
                Spacer(minLength: 0).frame(height: Self.m.calendarStripGap)
                list(now: now, activeDay: activeDay, calendar: cal)
                    .frame(height: Self.m.calendarListHeight, alignment: .top)
            }
        }
    }

    // MARK: - Header (28 pt): weekday or month title left; date/lunar right; month toggle + open-Calendar.

    @ViewBuilder private func header(now: Date, activeDay: Date, calendar: Calendar) -> some View {
        let isViewingToday = calendar.isDate(activeDay, inSameDayAs: now)
        HStack(alignment: .center, spacing: XFinderTokens.Space.tight) {
            if showingMonthGrid {
                HStack(spacing: 4) {
                    Button {
                        if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                            displayedMonth = prev
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Tháng trước"))
                    .accessibilityLabel(L10n.t("Tháng trước"))

                    Text(displayedMonth.formatted(.dateTime.month(.abbreviated).year().locale(locale)))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Button {
                        if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                            displayedMonth = next
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Tháng sau"))
                    .accessibilityLabel(L10n.t("Tháng sau"))
                }
            } else {
                Text(activeDay.formatted(.dateTime.weekday(.wide).locale(locale)))
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: XFinderTokens.Space.tight)

            if !isViewingToday || showingMonthGrid {
                Button(L10n.t("Hôm nay")) {
                    let today = calendar.startOfDay(for: now)
                    selectedDay = today
                    displayedMonth = today
                    showingMonthGrid = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(N.capsule))
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(activeDay.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.85)
                HStack(spacing: 2) {
                    Text(activeDay.formatted(.dateTime.year().locale(locale)))
                    Text("\(GlanceRules.lunarLabel(for: activeDay)) \(L10n.t("ÂL"))")
                }
                .font(XFinderTokens.Font.caption)
                .opacity(0.6)
            }
            .lineLimit(1)

            Button {
                displayedMonth = activeDay
                showingMonthGrid.toggle()
            } label: {
                Image(systemName: showingMonthGrid ? "list.bullet" : "calendar")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .opacity(0.75)
            .help(showingMonthGrid ? L10n.t("Xem lịch ngày") : L10n.t("Xem lịch tháng"))
            .accessibilityLabel(showingMonthGrid ? L10n.t("Xem lịch ngày") : L10n.t("Xem lịch tháng"))

            Button {
                NotchSurfaceController.shared.openCalendar(on: activeDay)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .opacity(0.65)
            .help(L10n.t("Mở Lịch"))
            .accessibilityLabel(L10n.t("Mở Lịch"))
        }
    }

    // MARK: - Compact Month Grid (108 pt): 7-column month picker with event dots; tapping a day jumps to its agenda.

    @ViewBuilder private func monthGridView(now: Date, activeDay: Date, calendar: Calendar) -> some View {
        let cells = GlanceRules.monthGrid(for: displayedMonth, calendar: calendar)
        let withEvents = GlanceRules.daysWithEvents(model.calendarEvents, strip: cells.map(\.date), calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(cells, id: \.date) { cell in
                let isToday = calendar.isDate(cell.date, inSameDayAs: now)
                let isSelected = calendar.isDate(cell.date, inSameDayAs: activeDay)
                Button {
                    selectedDay = calendar.startOfDay(for: cell.date)
                    displayedMonth = selectedDay
                    showingMonthGrid = false
                } label: {
                    VStack(spacing: 1) {
                        Text("\(calendar.component(.day, from: cell.date))")
                            .font(.system(size: 10.5, weight: (isToday || isSelected) ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isToday ? accent : (cell.inMonth ? Color.white : Color.white.opacity(0.32)))
                        Circle()
                            .fill(withEvents.contains(cell.date) ? accent : Color.clear)
                            .frame(width: 2.5, height: 2.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                            .fill(isSelected ? N.capsule : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Nine-day strip (40 pt): interactive day selection; today accent; selected pilled; event dot under.

    @ViewBuilder private func strip(now: Date, activeDay: Date, calendar: Calendar) -> some View {
        let days = GlanceRules.weekStrip(around: activeDay, calendar: calendar)
        let withEvents = GlanceRules.daysWithEvents(model.calendarEvents, strip: days, calendar: calendar)
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { d in
                let isToday = calendar.isDate(d, inSameDayAs: now)
                let isSelected = calendar.isDate(d, inSameDayAs: activeDay)
                Button {
                    selectedDay = calendar.startOfDay(for: d)
                } label: {
                    VStack(spacing: 2) {
                        Text(d.formatted(.dateTime.weekday(.narrow).locale(locale)))
                            .font(.system(size: 9))
                            .opacity(0.5)
                        Text("\(calendar.component(.day, from: d))")
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(isToday ? accent : .primary)
                        Circle()
                            .fill(withEvents.contains(d) ? accent : Color.clear)
                            .frame(width: 3, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                            .fill(isSelected ? N.capsule : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale)))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - List (62 pt): up-next line (for today) or selected-day agenda, scrollable.

    @ViewBuilder private func list(now: Date, activeDay: Date, calendar: Calendar) -> some View {
        let hour = calendar.component(.hour, from: now)
        let isToday = calendar.isDate(activeDay, inSameDayAs: now)
        let dayItems = GlanceRules.dayEvents(model.calendarEvents, on: activeDay, hideAllDay: model.calendarHidesAllDay, calendar: calendar)
        VStack(alignment: .leading, spacing: 3) {
            if isToday {
                upNextLine(now: now, hour: hour)
            } else if dayItems.isEmpty {
                Text(L10n.t("Không có sự kiện trong ngày này."))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.65)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(dayItems) { e in eventRow(e, now: now) }
                }
            }
        }
    }

    @ViewBuilder private func upNextLine(now: Date, hour: Int) -> some View {
        if let next = GlanceRules.upNext(model.calendarEvents, now: now) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Text("\(L10n.t(GlanceRules.greetingKey(hour: hour))) \(L10n.t("Tiếp theo: "))\(next.title) · \(next.start.formatted(.dateTime.hour().minute().locale(locale)))")
                    .font(XFinderTokens.Font.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let c = GlanceRules.countdown(to: next.start, now: now) {
                    Text("\(L10n.t("trong "))\(c.number) \(L10n.t(c.unitKey))")
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.65)
                }
                if let u = GlanceRules.meetingURL(in: next) {
                    Button(L10n.t("Tham gia")) { NSWorkspace.shared.open(u) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                }
            }
        } else {
            Text("\(L10n.t(GlanceRules.greetingKey(hour: hour))) \(L10n.t("Hôm nay không còn gì nữa."))")
                .font(XFinderTokens.Font.caption)
                .opacity(0.75)
        }
    }

    @ViewBuilder private func eventRow(_ e: GlanceEvent, now: Date) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Text(e.isAllDay ? L10n.t("Cả ngày") : e.start.formatted(.dateTime.hour().minute().locale(locale)))
                .font(XFinderTokens.Font.caption)
                .monospacedDigit()
                .opacity(0.65)
                .frame(width: 44, alignment: .leading)
            Image(systemName: e.isReminder ? "checklist" : "circle.fill")
                .font(.system(size: 6))
                .opacity(0.65)
            Text(e.title)
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(e.end < now ? 0.45 : 1)
            Spacer(minLength: 0)
        }
    }
}
