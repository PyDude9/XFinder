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
    @AppStorage("notch.activity.brightness") private var actBrightness = true
    @AppStorage("notch.activity.hideSystemHUD") private var hideSystemHUD = false
    /// Accessibility decides whether XFinder can take the brightness/volume keys over at all.
    @State private var trusted = WindowManager.isTrusted

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Hoạt động trực tiếp"),
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
                systemHUDSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear { trusted = WindowManager.isTrusted }
        // Granting Accessibility happens in System Settings; coming back must refresh the note.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = WindowManager.isTrusted
        }
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
                      subtitle: L10n.t("Mức âm lượng thật từ CoreAudio, hiện trên notch."),
                      isOn: $actVolume)
                .onChange(of: actVolume) { LiveActivityMonitor.shared.applySettings() }
                .disabled(!activities)
                .settingsRow()
            SettingsDivider()
            // Nothing observes brightness: the notch shows it only for a key XFinder took itself, i.e.
            // while "Chỉ dùng notch…" below is on. Without that the switch would promise a readout that
            // never appears (Part 0 §6), so it is disabled and says why.
            ToggleRow(title: L10n.t("Độ sáng"),
                      subtitle: L10n.t("Mức độ sáng thật của màn hình trong, hiện trên notch khi bạn bấm phím độ sáng. Chỉ có khi bật “Chỉ dùng notch cho độ sáng và âm lượng” bên dưới."),
                      isOn: $actBrightness)
                .disabled(!activities || !hideSystemHUD)
                .settingsRow()
        }
    }

    /// The owner's HUD request (2026-10-15): while XFinder draws brightness/volume on the notch, macOS must
    /// not draw its own square as well. Measured (probe, 2026-10-15): swallowing the key at `.cghidEventTap`
    /// and applying the change ourselves hides the native OSD for volume *and* brightness.
    private var systemHUDSection: some View {
        SettingsSection(title: L10n.t("Hộp điều chỉnh của macOS"),
                        footer: L10n.t("Khi tắt, macOS vẫn hiện hộp vuông của nó như trước. Phím bấm kèm ⌥, ⇧, ⌃ hoặc ⌘, và loa không cho chỉnh âm lượng, vẫn để macOS xử lý.")) {
            ToggleRow(title: L10n.t("Chỉ dùng notch cho độ sáng và âm lượng"),
                      subtitle: L10n.t("XFinder tự nhận phím độ sáng và âm lượng rồi đặt giá trị, nên macOS không hiện hộp vuông riêng nữa."),
                      isOn: $hideSystemHUD)
                .disabled(!activities)
                .onChange(of: hideSystemHUD) { SystemKeyInterceptor.shared.applySettings() }
                .settingsRow()
            if !trusted {
                SettingsDivider()
                InlineNote(kind: .warning,
                           text: L10n.t("Cần quyền Trợ năng để XFinder nhận được phím độ sáng và âm lượng."),
                           buttonTitle: L10n.t("Cấp quyền Trợ năng"),
                           action: {
                               if !WindowManager.requestAccessibilityTrust() {
                                   WindowManager.openAccessibilityPane()
                               }
                           })
                    .settingsRow()
            }
        }
    }
}
