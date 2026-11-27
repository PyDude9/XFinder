import SwiftUI

// audit-ui-tokens: embedded-panel — a card inside MouseGesturesDetailView, not a page of its own.
/// XF-T25 — the "Cuộn chuột mượt" card on the Chuột & cử chỉ page. Its own keys (`smoothScroll.*`), not the gesture blob:
/// smoothing has its own engine and catalog row. Defaults equal `SmoothScrollController`'s readers (FeatureKeyDefaultsTests).
struct SmoothScrollSection: View {
    @AppStorage("smoothScroll.enabled") private var enabled = false
    @AppStorage("smoothScroll.speed") private var speed = 100
    @AppStorage("smoothScroll.smoothness") private var smoothness = 220
    @AppStorage("smoothScroll.reverse") private var reverse = false
    @AppStorage("smoothScroll.linear") private var linear = false
    @AppStorage("mouse.disableAcceleration") private var disablePointerAccel = false
    @State private var controller = SmoothScrollController.shared

    var body: some View {
        SettingsSection(title: L10n.t("Cuộn chuột mượt"),
                        footer: L10n.t("Chỉ bánh xe chuột được làm mượt. Trackpad và Magic Mouse giữ nguyên cách cuộn của macOS.")) {
            ToggleRow(title: L10n.t("Làm mượt bánh xe chuột"),
                      subtitle: L10n.t("Bánh xe trôi như trackpad thay vì nhảy từng nấc."),
                      isOn: $enabled)
                .onChange(of: enabled) { controller.applySettings() }
                .settingsRow()
            SettingsDivider()
            sliderRow(title: L10n.t("Tốc độ"), caption: L10n.t("Quãng cuộn của mỗi nấc bánh xe."),
                      value: $speed, range: SmoothScrollRules.speedRange, step: 10, unit: "%")
            SettingsDivider()
            sliderRow(title: L10n.t("Độ mượt"), caption: L10n.t("Thời gian dàn một nấc ra thành chuyển động — cao hơn là trôi lâu hơn."),
                      value: $smoothness, range: SmoothScrollRules.smoothnessRange, step: 20, unit: "ms")
            SettingsDivider()
            ToggleRow(title: L10n.t("Đảo chiều bánh xe"),
                      subtitle: L10n.t("Chỉ áp cho chuột. Trackpad giữ cài đặt Cuộn tự nhiên của macOS."),
                      isOn: $reverse)
                .onChange(of: reverse) { controller.applySettings() }
                .disabled(!enabled)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Cuộn tuyến tính (không tăng tốc bánh xe)"),
                      subtitle: L10n.t("Mỗi nấc bánh xe cuộn một khoảng cố định dù bạn quay nhanh hay chậm."),
                      isOn: $linear)
                .onChange(of: linear) { controller.applySettings() }
                .disabled(!enabled)
                .settingsRow()
            SettingsDivider()
            ToggleRow(title: L10n.t("Tắt tăng tốc con trỏ chuột"),
                      subtitle: L10n.t("Giữ tốc độ con trỏ chuột ngoài ổn định (tắt sẽ khôi phục mức trước đó; có thể cần cắm lại chuột để áp dụng ngay)."),
                      isOn: $disablePointerAccel)
                .onChange(of: disablePointerAccel) { PointerAccelerationController.setDisableAcceleration(disablePointerAccel) }
                .settingsRow()
            SettingsDivider()
            HStack(spacing: XFinderTokens.Space.inline) {
                Image(systemName: statusSymbol).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText).font(XFinderTokens.Font.row)
                    if let kindText {
                        Text(kindText).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(L10n.t("Khôi phục mặc định")) {
                    speed = SmoothScrollRules.defaultSpeed
                    smoothness = SmoothScrollRules.defaultSmoothness
                    reverse = false
                    linear = false
                    controller.applySettings()
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(speed == SmoothScrollRules.defaultSpeed && smoothness == SmoothScrollRules.defaultSmoothness && !reverse && !linear)
            }
            .settingsRow()
        }
        .onAppear { controller.applySettings() }
    }

    private func sliderRow(title: String, caption: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(XFinderTokens.Font.row)
                Text(caption).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0); controller.applySettings() }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                .frame(width: 160)
            Text("\(value.wrappedValue) \(unit)").font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .disabled(!enabled)
        .settingsRow()
    }

    private var statusText: String {
        switch controller.state {
        case .off: return L10n.t("Đang tắt — bánh xe cuộn như macOS gốc.")
        case .running: return L10n.t("Đang làm mượt bánh xe chuột.")
        case .needsAccessibility: return L10n.t("Cần quyền Trợ năng để đọc bánh xe chuột.")
        case .pausedFor(let app): return L10n.t("Đang tạm dừng: ") + app + L10n.t(" cũng làm mượt cuộn — tắt một trong hai.")
        case .pausedForCapture: return L10n.t("Đang tạm dừng trong lúc chụp cuộn.")
        }
    }

    private var statusSymbol: String {
        switch controller.state {
        case .running: return "computermouse.fill"
        case .needsAccessibility: return "exclamationmark.triangle"
        case .pausedFor, .pausedForCapture: return "pause.circle"
        case .off: return "computermouse"
        }
    }

    /// Lets the owner check the device split on his own mouse (spec §2.1).
    private var kindText: String? {
        guard controller.state == .running, let kind = controller.lastKind else { return nil }
        switch kind {
        case .wheel: return L10n.t("Lần cuộn vừa rồi: bánh xe chuột — đã làm mượt.")
        case .gesture: return L10n.t("Lần cuộn vừa rồi: trackpad hoặc Magic Mouse — giữ nguyên.")
        }
    }
}
