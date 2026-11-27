import SwiftUI

/// Live hardware rows share a single grid so values align even on compact displays.
struct NotchSystemPage: View {
    @State private var monitor = SystemMonitorManager.shared
    @State private var caffeine = CaffeineController.shared
    @State private var hasBattery = PowerManager.hasBattery()
    @State private var batteryInfo: BatteryInfo?
    @Environment(\.notchAccent) private var accent

    var body: some View {
        let metrics = monitor.currentMetrics
        VStack(spacing: 5) {
            VStack(spacing: 4) {
                metric("CPU", icon: "cpu", fraction: metrics.cpuUsage / 100,
                       value: metrics.cpuUsage.formatted(.number.precision(.fractionLength(0))) + "%",
                       detail: "GPU: \(metrics.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "—") · SoC: \(MenubarPanelRules.formatTemp(metrics.socTempAverage) ?? "—")")
                metric("RAM", icon: "memorychip", fraction: metrics.memoryPercentage / 100,
                       value: "\(metrics.memoryUsedString) / \(metrics.memoryTotalString)",
                       detail: metrics.thermalState.label)
                metric(L10n.t("Ổ đĩa"), icon: "internaldrive", fraction: metrics.diskPercentage / 100,
                       value: L10n.t("Còn trống: ") + MenubarPanelRules.formatBytes(max(0, metrics.diskTotal - metrics.diskUsed)))
                networkRow(metrics)
                if hasBattery {
                    metric(L10n.t("Pin"), icon: metrics.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                           fraction: metrics.batteryLevel / 100,
                           value: metrics.batteryLevel.formatted(.number.precision(.fractionLength(0))) + "%",
                           detail: (batteryInfo?.healthPercent).map { L10n.t("Sức khỏe") + " " + String(format: "%.0f%%", $0) })
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 6) {
                caffeineControls
                Spacer(minLength: 2)
                Button {
                    NotchSurfaceController.shared.dismiss()
                    AppState.shared.navigate(to: .system)
                } label: {
                    Image(systemName: "arrow.up.right").frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Mở bảng Hệ thống"))
                .accessibilityLabel(L10n.t("Mở bảng Hệ thống"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            monitor.retain()
            hasBattery = PowerManager.hasBattery()
            batteryInfo = hasBattery ? PowerManager.read() : nil
            caffeine.refreshPowerState()
        }
        .onDisappear { monitor.release() }
    }

    private var caffeineControls: some View {
        HStack(spacing: 5) {
            Menu {
                ForEach(MenubarPanelRules.unsleepPresets) { preset in
                    Button(L10n.t(preset.labelKey)) {
                        caffeine.activate(duration: preset.minutes == 0 ? .indefinite : .minutes(preset.minutes))
                    }
                }
            } label: {
                Label("Caffeine", systemImage: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
            }
            .controlSize(.small)
            .fixedSize()
            .layoutPriority(2)
            .foregroundStyle(caffeine.isActive ? accent : .primary)

            if caffeine.isActive {
                Text(MenubarPanelRules.formatRemaining(seconds: caffeine.remainingSeconds) ?? "∞")
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityLabel(caffeine.remainingSeconds == nil ? L10n.t("Vô hạn") : (MenubarPanelRules.formatRemaining(seconds: caffeine.remainingSeconds) ?? ""))
                Button(L10n.t("Dừng")) { caffeine.deactivate() }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(accent)
            }
            if hasBattery {
                Toggle(isOn: Binding(get: { caffeine.requestLidWake }, set: { caffeine.setLidWakeRequested($0) })) {
                    Label(L10n.t("Đóng nắp"), systemImage: lidWakeSymbol)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(lidWakeLabelColor)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .help(lidWakeHelpText)
                .accessibilityLabel(L10n.t("Yêu cầu giữ máy thức khi đóng nắp"))
                .accessibilityValue(lidWakeAccessibilityValue)
            }
        }
        .font(.caption)
    }

    private var lidWakeSymbol: String {
        switch caffeine.lidWakeState {
        case .active: return "laptopcomputer.and.arrow.down"
        case .waitingForACPower: return "bolt.slash"
        case .waitingForCaffeine, .unavailable, .off: return "laptopcomputer"
        }
    }

    private var lidWakeLabelColor: Color {
        switch caffeine.lidWakeState {
        case .active: return accent
        case .waitingForCaffeine, .waitingForACPower, .unavailable: return .orange
        case .off: return .secondary
        }
    }

    private var lidWakeHelpText: String {
        switch caffeine.lidWakeState {
        case .active:
            return L10n.t("Đang giữ thức khi đóng nắp (đang cắm nguồn). macOS vẫn có thể cho máy ngủ nếu không có màn hình ngoài.")
        case .waitingForCaffeine:
            return L10n.t("Đã bật yêu cầu đóng nắp — chưa hoạt động vì Chống ngủ đang tắt. Cần cắm nguồn.")
        case .waitingForACPower:
            return L10n.t("Đã bật yêu cầu đóng nắp — đang tạm dừng vì dùng pin (cần cắm nguồn).")
        case .unavailable:
            return L10n.t("Không tạo được yêu cầu giữ thức khi đóng nắp từ macOS.")
        case .off:
            return L10n.t("Cần bật Chống ngủ và cắm nguồn. macOS vẫn có thể cho máy ngủ khi đóng nắp.")
        }
    }

    private var lidWakeAccessibilityValue: String {
        switch caffeine.lidWakeState {
        case .active: return L10n.t("Đang hoạt động")
        case .waitingForCaffeine: return L10n.t("Đang chờ bật Chống ngủ")
        case .waitingForACPower: return L10n.t("Đang chờ cắm nguồn")
        case .unavailable: return L10n.t("Không khả dụng")
        case .off: return L10n.t("Đang tắt")
        }
    }

    private func metric(_ label: String, icon: String, fraction: Double, value: String, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            metricLabel(label, icon: icon)
            GeometryReader { geometry in
                Capsule()
                    .fill(.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent.opacity(0.8)).frame(width: geometry.size.width * min(max(fraction, 0), 1))
                    }
            }
            .frame(height: 4)
            metricValue(value)
        }
        .frame(height: 16)
        .help(detail ?? value)
        .accessibilityElement(children: .combine)
    }

    private func networkRow(_ metrics: SystemMetrics) -> some View {
        HStack(spacing: 8) {
            metricLabel(L10n.t("Mạng"), icon: "network")
            HStack(spacing: 3) {
                networkTrend(monitor.metricsHistory.map(\.networkDownload), tint: .cyan)
                Spacer(minLength: 2)
                networkTrend(monitor.metricsHistory.map(\.networkUpload), tint: .mint)
            }
            metricValue("↓ \(MenubarPanelRules.formatRateKBs(metrics.networkDownload))  ↑ \(MenubarPanelRules.formatRateKBs(metrics.networkUpload))")
        }
        .frame(height: 16)
        .accessibilityElement(children: .combine)
    }

    private func networkTrend(_ points: [Double], tint: Color) -> some View {
        SparklineView(values: points, yMax: max(1, points.max() ?? 0), tint: tint, height: 13)
            .accessibilityHidden(true)
    }

    private func metricLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 73, alignment: .leading)
            .lineLimit(1)
    }

    private func metricValue(_ value: String) -> some View {
        Text(value).font(.caption.monospacedDigit())
            .frame(width: 117, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}
