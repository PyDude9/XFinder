import SwiftUI

/// Hoạt động trực tiếp — the user comes here to choose which short notices the notch may show. Split off
/// "Notch & Khay thả" (P3). A master switch gates six notice kinds; turning it off disables (not hides)
/// the six so the page still explains what each one is.
struct LiveActivitiesDetailView: View {
    // B4 live activities. Reader: LiveActivityMonitor (defaults must match — FeatureKeyDefaultsTests).
    @AppStorage("dropTray.notchEnabled") private var notchEnabled = true
    @AppStorage("notch.activities") private var activities = true
    @AppStorage("notch.activity.power") private var actPower = true
    @AppStorage("notch.activity.network") private var actNetwork = true
    @AppStorage("notch.activity.capsLock") private var actCapsLock = true
    @AppStorage("notch.activity.bluetooth") private var actBluetooth = true
    @AppStorage("notch.activity.alerts") private var actAlerts = true
    @AppStorage("notch.activity.volume") private var actVolume = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(
                    icon: "dot.radiowaves.left.and.right",
                    title: L10n.t("Hoạt động trực tiếp"),
                    subtitle: L10n.t("Thông báo ngắn hiện dưới notch vài giây rồi tự tắt; không bao giờ chen vào khi bạn đang mở khay.")
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

                activitiesSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    private var activitiesSection: some View {
        SettingsSection(title: L10n.t("Thông báo trên notch")) {
            ToggleRow(title: L10n.t("Hiện thông báo trên notch"), isOn: $activities)
                .onChange(of: activities) { LiveActivityMonitor.shared.applySettings() }
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Sạc và pin"),
                      subtitle: L10n.t("Cắm, rút sạc, pin đầy, pin yếu (20%) và rất yếu (10%)."),
                      isOn: $actPower)
                .onChange(of: actPower) { LiveActivityMonitor.shared.applySettings() }
                .disabled(!activities)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Mất và có lại mạng"), isOn: $actNetwork)
                .onChange(of: actNetwork) { LiveActivityMonitor.shared.applySettings() }
                .disabled(!activities)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Caps Lock"),
                      subtitle: L10n.t("Cần quyền Trợ năng khi XFinder không ở phía trước."),
                      isOn: $actCapsLock)
                .onChange(of: actCapsLock) { LiveActivityMonitor.shared.applySettings() }
                .disabled(!activities)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Thiết bị Bluetooth kết nối, ngắt kết nối"),
                      subtitle: L10n.t("Cần quyền Bluetooth."),
                      isOn: $actBluetooth)
                .onChange(of: actBluetooth) { LiveActivityMonitor.shared.applySettings() }
                .disabled(!activities)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Cảnh báo hệ thống"),
                      subtitle: L10n.t("Cảnh báo từ trang Cảnh báo hiện ở notch thay vì góc trên bên phải."),
                      isOn: $actAlerts)
                .disabled(!activities)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Âm lượng"),
                      subtitle: L10n.t("Mức âm lượng thật từ CoreAudio, hiện song song HUD của macOS. Không có HUD độ sáng: trên máy này giá trị độ sáng đọc được bị kẹt nên sẽ phải bịa số."),
                      isOn: $actVolume)
                .onChange(of: actVolume) { LiveActivityMonitor.shared.applySettings() }
                .disabled(!activities)
                .settingsRow()
        }
    }
}
