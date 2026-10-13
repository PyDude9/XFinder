import SwiftUI

/// Lịch & lời nhắc — the user comes here to put today's events on the notch and to decide how early a
/// meeting alert fires. Split off "Notch & Khay thả" (P3). The switches only read; the access sheet is
/// asked for from this page's own "Cấp quyền…" button (reusing `FeatureHub`/`AppPermission`), so a
/// toggle never pops a system dialog.
struct CalendarSettingsDetailView: View {
    // N4
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true
    @AppStorage("notch.calendar") private var calendarEnabled = false
    @AppStorage("notch.calendar.hideAllDay") private var calendarHideAllDay = false
    // §3b #33
    @AppStorage("notch.calendar.alerts") private var calendarAlerts = true
    @AppStorage("notch.calendar.alertLead") private var calendarAlertLead = 5
    @AppStorage("notch.calendar.alertSound") private var calendarAlertSound = true

    @State private var hub = FeatureHub.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(
                    icon: "calendar",
                    title: L10n.t("Lịch & lời nhắc"),
                    subtitle: L10n.t("Hôm nay có gì, việc kế tiếp lúc mấy giờ, link họp để bấm vào — ngay tại notch.")
                )

                // P3 review: the notch master switches this surface off with the rest of the notch — say so, here.
                if !notchEnabled {
                    SettingsSection {
                        SettingsLinkRow(
                            title: L10n.t("Notch đang tắt"),
                            subtitle: L10n.t("Mục này không hiện ở notch cho tới khi bạn bật lại notch ở Giao diện notch."),
                            destination: .notchInterface
                        )
                    }
                }

                onNotchSection
                alertsSection
                accessSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear { hub.retain() }
        .onDisappear { hub.release() }
    }

    private var onNotchSection: some View {
        SettingsSection(title: L10n.t("Trên notch")) {
            ToggleRow(title: L10n.t("Hiện trang Lịch ở notch"),
                      subtitle: L10n.t("Sự kiện và lời nhắc có giờ trong ±5 ngày, đọc từ Lịch của macOS (EventKit). Không mạng, không ghi gì vào lịch của bạn. Cần quyền Lịch — trang sẽ hỏi khi bạn mở."),
                      isOn: $calendarEnabled)
                .onChange(of: calendarEnabled) { NotchSurfaceController.shared.applySettings() }
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Ẩn sự kiện cả ngày"), isOn: $calendarHideAllDay)
                .onChange(of: calendarHideAllDay) { NotchSurfaceController.shared.applySettings() }
                .disabled(!calendarEnabled)
                .settingsRow()
        }
    }

    private var alertsSection: some View {
        SettingsSection(title: L10n.t("Báo trước cuộc họp")) {
            ToggleRow(title: L10n.t("Báo trước sự kiện ở notch"),
                      subtitle: L10n.t("Một dòng dưới notch trước sự kiện có giờ và lời nhắc có giờ, với nút Tham gia (khi có link họp) và Hoãn 5 phút. Không báo sự kiện cả ngày."),
                      isOn: $calendarAlerts)
                .onChange(of: calendarAlerts) { CalendarGlanceMonitor.shared.scheduleAlert() }
                .disabled(!calendarEnabled)
                .settingsRow()
            SettingsDivider()
            PickerRow(title: L10n.t("Báo trước"), selection: $calendarAlertLead, width: 170) {
                ForEach(MeetingAlertRules.leadChoices, id: \.self) { m in
                    Text("\(m)\(L10n.t(" phút trước sự kiện"))").tag(m)
                }
            }
            .onChange(of: calendarAlertLead) { CalendarGlanceMonitor.shared.scheduleAlert() }
            .disabled(!calendarEnabled || !calendarAlerts)
            .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Âm báo khi nhắc"), isOn: $calendarAlertSound)
                .disabled(!calendarEnabled || !calendarAlerts)
                .settingsRow()
        }
    }

    /// Compact rows reusing the existing `FeatureHub`/`AppPermission` mechanism — the same source of
    /// truth as the Features hub's Permissions tab. The toggle above never triggers this; only the
    /// button does.
    private var accessSection: some View {
        let granted = hub.granted()
        return SettingsSection(title: L10n.t("Quyền truy cập")) {
            accessRow(.calendars, granted: granted[.calendars] ?? false)
            SettingsDivider()
            accessRow(.reminders, granted: granted[.reminders] ?? false)
        }
    }

    private func accessRow(_ permission: AppPermission, granted: Bool) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L10n.t(permission.titleKey)).font(XFinderTokens.Font.row)
                    Circle().fill(granted ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(granted ? L10n.t("Đã cấp") : L10n.t("Chưa cấp"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                Text(L10n.t(permission.purposeKey))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: XFinderTokens.Space.inline)
            if !granted {
                Button(L10n.t("Cấp quyền…")) { hub.request(permission) }
                    .controlSize(.small)
            }
        }
        .settingsRow()
    }
}
