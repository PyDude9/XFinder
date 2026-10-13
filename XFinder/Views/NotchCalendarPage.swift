import SwiftUI
import AppKit

/// P2 — Calendar tool, restyled in OneNotch's grammar for the NARROW notch body (content 354 × 140, per
/// `CONTRACT.md`/P2). Job sentence unchanged from the page this restyles: *"What's on my calendar today, what's
/// next, and can I join it without opening the Calendar app."* All data and interactions are the existing,
/// already-tested `GlanceRules` + `CalendarGlanceMonitor` — this file only re-lays the same content inside the
/// fixed row budget (`NotchSurfaceLayout.Metrics.standard.calendarHeaderHeight/HeaderGap/StripHeight/StripGap/
/// ListHeight`). Meeting-alert Join/Snooze buttons stay the transient `LiveActivity.Item` banner and are
/// deliberately NOT duplicated here (Part 0 §4 — one control, one job).
struct NotchCalendarPage: View {
    var model: NotchSurfaceModel
    @Environment(\.notchAccent) private var accent

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
        VStack(alignment: .leading, spacing: 0) {
            header(now: now)
                .frame(height: Self.m.calendarHeaderHeight, alignment: .top)
            Spacer(minLength: 0).frame(height: Self.m.calendarHeaderGap)
            strip(now: now, calendar: cal)
                .frame(height: Self.m.calendarStripHeight, alignment: .top)
            Spacer(minLength: 0).frame(height: Self.m.calendarStripGap)
            list(now: now, calendar: cal)
                .frame(height: Self.m.calendarListHeight, alignment: .top)
        }
    }

    // MARK: - Header (28 pt): weekday large bold left; day+month / year+lunar two-line right; open-Calendar button.

    @ViewBuilder private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: XFinderTokens.Space.tight) {
            Text(now.formatted(.dateTime.weekday(.wide).locale(locale)))
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: XFinderTokens.Space.tight)

            VStack(alignment: .trailing, spacing: 1) {
                Text(now.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.85)
                HStack(spacing: 2) {
                    Text(now.formatted(.dateTime.year().locale(locale)))
                    Text("\(GlanceRules.lunarLabel(for: now)) \(L10n.t("ÂL"))")
                }
                .font(XFinderTokens.Font.caption)
                .opacity(0.6)
            }
            .lineLimit(1)

            Button {
                NotchSurfaceController.shared.openCalendar(on: now)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .opacity(0.65)
            .help(L10n.t("Mở Lịch"))
            .accessibilityLabel(L10n.t("Mở Lịch"))
        }
    }

    // MARK: - Nine-day strip (40 pt): weekday caps over day number; today pilled; event dot under.

    @ViewBuilder private func strip(now: Date, calendar: Calendar) -> some View {
        let days = GlanceRules.weekStrip(around: now, calendar: calendar)
        let withEvents = GlanceRules.daysWithEvents(model.calendarEvents, strip: days, calendar: calendar)
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { d in
                let isToday = calendar.isDate(d, inSameDayAs: now)
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
                        .fill(isToday ? N.capsule : Color.clear)
                )
            }
        }
    }

    // MARK: - List (62 pt): up-next line, then today's events/reminders, scrollable.

    @ViewBuilder private func list(now: Date, calendar: Calendar) -> some View {
        let hour = calendar.component(.hour, from: now)
        let today = GlanceRules.dayEvents(model.calendarEvents, on: now, hideAllDay: model.calendarHidesAllDay, calendar: calendar)
        VStack(alignment: .leading, spacing: 3) {
            upNextLine(now: now, hour: hour)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(today) { e in eventRow(e, now: now) }
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
