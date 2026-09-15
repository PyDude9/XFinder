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
                            // Health = NominalChargeCapacity / DesignCapacity.
                            // It used to divide MaxCapacity (a 0-100 PERCENT on
                            // Apple Silicon) by mAh, which is what rendered 1%.
                            row(label: "Sức khỏe",
                                value: info.healthPercent.map { String(format: "%.0f%%", $0) } ?? "—")

                            if let c = info.cycleCount {
                                row(label: "Số chu kỳ",
                                    value: info.designCycleCount.map { "\(c) / \($0)" } ?? "\(c)")
                            } else {
                                row(label: "Số chu kỳ", value: "—")
                            }

                            if let n = info.nominalCapacity, let d = info.designCapacity {
                                row(label: "Dung lượng", value: "\(n) / \(d) mAh")
                            }

                            row(label: "Công suất",
                                value: info.watts.map { String(format: "%.1f W", $0) } ?? "—")

                            if let v = info.voltage {
                                row(label: "Điện áp", value: String(format: "%.2f V", v))
                            }
                            if let a = info.amperage {
                                row(label: "Dòng điện", value: "\(a) mA")
                            }

                            Divider().opacity(0.5)

                            // Battery temperature IS available after all — it
                            // lives in AppleSmartBatteryPack/BatteryData, not
                            // AppleSmartBattery, and is centi-Celsius
                            // (3469 -> 34.7 °C). Twice reported here as "no
                            // public API" because only the latter was checked.
                            if let t = info.temperatureC {
                                row(label: "Nhiệt độ pin", value: String(format: "%.1f °C", t))
                                if let mx = info.lifetimeMaxTempC, let mn = info.lifetimeMinTempC {
                                    row(label: "Nhiệt độ đã ghi nhận",
                                        value: String(format: "%.0f – %.0f °C", mn, mx))
                                }
                            } else {
                                row(label: "Nhiệt độ pin", value: "—")
                            }

                            if let s = info.serial {
                                row(label: "Số sê-ri", value: s)
                            }
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
