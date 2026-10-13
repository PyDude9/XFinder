import SwiftUI
import Combine

struct PinDetailView: View {
    @Environment(SystemMonitorManager.self) var monitor
    @ObservedObject private var batteryStore = BatteryStore.shared
    @AppStorage("battery.showDisconnected") private var showDisconnected = false
    @State private var info: BatteryInfo = PowerManager.read()
    @State private var hasBattery: Bool = PowerManager.hasBattery()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "battery.100", title: L10n.t("Pin"))

                if !hasBattery {
                    VStack(spacing: XFinderTokens.Space.inline) {
                        Image(systemName: "battery.0").font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
                        Text(L10n.t("Không có pin")).font(XFinderTokens.Font.sectionTitle)
                        Text(L10n.t("Thiết bị này không có pin tích hợp.")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, XFinderTokens.Space.inline)
                    .padding(.horizontal, XFinderTokens.Space.page)
                } else {
                    let m = monitor.currentMetrics
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "bolt.fill", title: L10n.t("Trạng thái"))
                        VStack(spacing: XFinderTokens.Space.inline) {
                            HStack(alignment: .firstTextBaseline, spacing: XFinderTokens.Space.inline) {
                                MetricBigNumber(value: String(format: "%.0f", m.batteryLevel), unit: "%", label: m.isCharging ? L10n.t("Đang sạc") : L10n.t("Đang xả"), tint: m.batteryLevel < 20 ? .red : .green)
                                Spacer()
                                Text(m.batteryTimeString).font(XFinderTokens.Font.row).foregroundColor(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(XFinderTokens.Fill.inset)
                                    Capsule().fill(m.batteryLevel < 20 ? Color.red : Color.green)
                                        .frame(width: max(0, CGFloat(m.batteryLevel / 100.0) * geo.size.width))
                                }
                            }
                            .frame(height: 10)
                            HStack {
                                Label(m.isCharging ? L10n.t("Đang sạc") : L10n.t("Đang xả"), systemImage: m.isCharging ? "bolt.fill" : "bolt.slash")
                                Spacer()
                                Text(m.batteryTimeString).foregroundColor(.secondary)
                            }
                            .font(XFinderTokens.Font.rowValue)
                        }
                        .padding(.horizontal, XFinderTokens.Space.page)
                    }

                    Divider().padding(.horizontal, XFinderTokens.Space.page)

                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "heart.fill", title: L10n.t("Sức khỏe pin"))
                        VStack(spacing: XFinderTokens.Space.tight) {
                            // Health = NominalChargeCapacity / DesignCapacity.
                            // It used to divide MaxCapacity (a 0-100 PERCENT on
                            // Apple Silicon) by mAh, which is what rendered 1%.
                            row(label: L10n.t("Sức khỏe"),
                                value: info.healthPercent.map { String(format: "%.0f%%", $0) } ?? "—")

                            if let c = info.cycleCount {
                                row(label: L10n.t("Số chu kỳ"),
                                    value: info.designCycleCount.map { "\(c) / \($0)" } ?? "\(c)")
                            } else {
                                row(label: L10n.t("Số chu kỳ"), value: "—")
                            }

                            if let n = info.nominalCapacity, let d = info.designCapacity {
                                row(label: L10n.t("Dung lượng"), value: "\(n) / \(d) mAh")
                            }

                            row(label: L10n.t("Công suất"),
                                value: info.watts.map { String(format: "%.1f W", $0) } ?? "—")

                            if let v = info.voltage {
                                row(label: L10n.t("Điện áp"), value: String(format: "%.2f V", v))
                            }
                            if let a = info.amperage {
                                row(label: L10n.t("Dòng điện"), value: "\(a) mA")
                            }

                            Divider().opacity(0.5)

                            // Battery temperature IS available after all — it
                            // lives in AppleSmartBatteryPack/BatteryData, not
                            // AppleSmartBattery, and is centi-Celsius
                            // (3469 -> 34.7 °C). Twice reported here as "no
                            // public API" because only the latter was checked.
                            if let t = info.temperatureC {
                                row(label: L10n.t("Nhiệt độ pin"), value: String(format: "%.1f °C", t))
                                if let mx = info.lifetimeMaxTempC, let mn = info.lifetimeMinTempC {
                                    row(label: L10n.t("Nhiệt độ đã ghi nhận"),
                                        value: String(format: "%.0f – %.0f °C", mn, mx))
                                }
                            } else {
                                row(label: L10n.t("Nhiệt độ pin"), value: "—")
                            }

                            if let s = info.serial {
                                row(label: L10n.t("Số sê-ri"), value: s)
                            }
                        }
                        .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }

                let externalDevices = batteryStore.allDevices.filter { $0.kind != .mac }
                if !externalDevices.isEmpty {
                    Divider().padding(.horizontal, XFinderTokens.Space.page)

                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "externaldrive.connected.to.line.below", title: L10n.t("Thiết bị đã kết nối"))
                        VStack(spacing: XFinderTokens.Space.inline) {
                            ToggleRow(title: L10n.t("Hiện thiết bị đã ngắt kết nối"), isOn: $showDisconnected)

                            let displayDevices = externalDevices.filter { showDisconnected || $0.isConnected }
                            if displayDevices.isEmpty {
                                Text(L10n.t("Không có thiết bị kết nối"))
                                    .font(XFinderTokens.Font.rowValue)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, XFinderTokens.Space.inline)
                            } else {
                                VStack(spacing: XFinderTokens.Space.inline) {
                                    ForEach(displayDevices) { dev in
                                        LargeBatteryCardView(device: dev)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        // Only sample metrics while a page that shows them is on screen.
        .onAppear {
            SystemMonitorManager.shared.retain()
            batteryStore.retain()
        }
        .onDisappear {
            SystemMonitorManager.shared.release()
            batteryStore.release()
        }
        .onAppear {
            info = PowerManager.read()
            hasBattery = PowerManager.hasBattery()
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            Spacer()
            Text(value).font(XFinderTokens.Font.mono).foregroundColor(.primary)
        }
    }
}
