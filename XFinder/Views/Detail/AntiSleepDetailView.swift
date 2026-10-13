import SwiftUI

struct AntiSleepDetailView: View {
    @State private var caffeine = CaffeineController.shared
    @State private var selectedMinutes: Int? = nil

    private let presets: [(label: String, minutes: Int?)] = [
        (L10n.t("Vô hạn"), nil), (L10n.t("15 phút"), 15), (L10n.t("1 giờ"), 60), (L10n.t("2 giờ"), 120),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Chống ngủ"))

                SettingsSection {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(caffeine.isActive ? L10n.t("Đang ngăn chế độ ngủ") : L10n.t("Cho phép ngủ bình thường"))
                                .font(XFinderTokens.Font.sectionTitle)
                            if let r = caffeine.remainingSeconds {
                                Text(String(format: L10n.t("Còn %02d:%02d"), r / 60, r % 60))
                                    .font(XFinderTokens.Font.metric)
                                    .foregroundColor(.orange)
                            } else if caffeine.isActive {
                                Text(L10n.t("∞ Vô hạn")).font(XFinderTokens.Font.metric).foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Button(caffeine.isActive ? L10n.t("Tắt") : L10n.t("Bật")) {
                            if caffeine.isActive { caffeine.deactivate() }
                            else {
                                if let m = selectedMinutes { caffeine.activate(duration: .minutes(m)) }
                                else { caffeine.activate(duration: .indefinite) }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(caffeine.isActive ? Color.red : Color.orange)
                        .controlSize(.large)
                    }
                    .settingsRow()
                    SettingsDivider()

                    Picker(L10n.t("Thời lượng"), selection: $selectedMinutes) {
                        Text(presets[0].label).tag(presets[0].minutes)
                        Text(presets[1].label).tag(presets[1].minutes)
                        Text(presets[2].label).tag(presets[2].minutes)
                        Text(presets[3].label).tag(presets[3].minutes)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(caffeine.isActive)
                    .settingsRow()
                }

                // P4 review: the note is the card's content — a footer under an EMPTY card drew a blank box.
                SettingsSection(title: L10n.t("Lưu ý")) {
                    Text(L10n.t("Khi bật, hệ thống sẽ không tự động ngủ hay tắt màn hình cho đến khi bạn tắt hoặc hết thời lượng đã chọn. Kiểm tra bằng `pmset -g assertions` trong Terminal."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .settingsRow()
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }
}
