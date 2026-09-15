import SwiftUI
import Combine

struct PinDetailView: View {
    @Environment(SystemMonitorManager.self) var monitor
    @State private var info: BatteryInfo = PowerManager.read()
    @State private var hasBattery: Bool = PowerManager.hasBattery()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pin")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                if !hasBattery {
                    SettingsCard {
                        VStack(spacing: 8) {
                            Image(systemName: "battery.0").font(.system(size: 28)).foregroundColor(.secondary)
                            Text("Không có pin").font(.system(size: 14, weight: .semibold))
                            Text("Thiết bị này không có pin tích hợp.").font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .padding(.horizontal, 20)
                } else {
                    let m = monitor.currentMetrics
                    SettingsCard {
                        VStack(spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                MetricBigNumber(value: String(format: "%.0f", m.batteryLevel), unit: "%", label: m.isCharging ? "Đang sạc" : "Đang xả", tint: m.batteryLevel < 20 ? .red : .green)
                                Spacer()
                                Text(m.batteryTimeString).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.12))
                                    Capsule().fill(m.batteryLevel < 20 ? Color.red : Color.green)
                                        .frame(width: max(0, CGFloat(m.batteryLevel / 100.0) * geo.size.width))
                                }
                            }
                            .frame(height: 10)
                            HStack {
                                Label(m.isCharging ? "Đang sạc" : "Đang xả", systemImage: m.isCharging ? "bolt.fill" : "bolt.slash")
                                Spacer()
                                Text(m.batteryTimeString).foregroundColor(.secondary)
                            }
                            .font(.system(size: 12))
                        }
                    }
                    .padding(.horizontal, 20)

                    SettingsCard(title: "Sức khỏe pin") {
                        VStack(spacing: 10) {
                            row(label: "Sức khỏe", value: info.healthPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                            row(label: "Số chu kỳ", value: info.cycleCount.map(String.init) ?? "—")
                            row(label: "Công suất", value: info.watts.map { String(format: "%.1f W", $0) } ?? "—")
                            if let d = info.designCapacity, let mx = info.maxCapacity {
                                row(label: "Dung lượng", value: "\(mx) / \(d) mAh")
                            }
                            Divider().opacity(0.5)
                            HStack {
                                Text("Nhiệt độ pin").font(.system(size: 11)).foregroundColor(.secondary)
                                Spacer()
                                Text("Đang thu thập…").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                            }
                            Text("Cảm biến nhiệt độ pin yêu cầu SMC riêng — không có API công khai.")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        // Only sample metrics while a page that shows them is on screen.
        .onAppear { SystemMonitorManager.shared.retain() }
        .onDisappear { SystemMonitorManager.shared.release() }
        .onAppear {
            info = PowerManager.read()
            hasBattery = PowerManager.hasBattery()
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(.primary)
        }
    }
}
