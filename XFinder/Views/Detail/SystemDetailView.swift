import SwiftUI

/// Hệ thống — layout mirrors the reference screenshot: two temperature
/// readouts across the top, CPU and GPU meters, a flat memory table, uptime.
///
/// Honesty Rule: the temperature slots show the SoC die sensors read through the HID thermal
/// interface (`ThermalSensors`, measured on macOS 27 without root). They are labelled SoC, not
/// CPU, and render "Không khả dụng" — never a number — when no sensor is readable. GPU *load* is
/// read from `IOAccelerator/PerformanceStatistics` (see `GPUUtilization`).
struct SystemDetailView: View {
    @Environment(SystemMonitorManager.self) var monitor
    @AppStorage("menubar.updateInterval") private var updateInterval = 2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "cpu",
                           title: L10n.t("Hệ thống"),
                           subtitle: L10n.t("Xem nhanh CPU, đồ họa, bộ nhớ và nhiệt độ."))

                temperatureRow
                Divider().padding(.horizontal, 20)

                MeterRow(label: "CPU",
                         percent: monitor.currentMetrics.cpuUsage,
                         tint: .blue)
                if !monitor.metricsHistory.isEmpty {
                    SparklineView(values: monitor.metricsHistory.map(\.cpuUsage),
                                  yMax: 100, tint: .blue, height: 26)
                        .padding(.horizontal, 20)
                }

                // GPU load: `IOAccelerator/PerformanceStatistics/Device Utilization %`, a
                // public IORegistry read that was measured to track real load (idle 0–22 %,
                // Metal burn 99–100 %). nil only when the hardware does not publish it.
                MeterRow(label: "GPU",
                         percent: monitor.currentMetrics.gpuUsage,
                         tint: .teal)
                if monitor.metricsHistory.contains(where: { $0.gpuUsage != nil }) {
                    SparklineView(values: monitor.metricsHistory.map { $0.gpuUsage ?? 0 },
                                  yMax: 100, tint: .teal, height: 26)
                        .padding(.horizontal, 20)
                }

                Divider().padding(.horizontal, 20)

                LabeledLine(label: L10n.t("Bộ nhớ"),
                            value: "\(monitor.currentMetrics.memoryUsedString) / \(monitor.currentMetrics.memoryTotalString)")
                LabeledLine(label: L10n.t("Áp lực bộ nhớ"),
                            value: monitor.currentMetrics.thermalState.label)
                LabeledLine(label: L10n.t("Đã nén"),
                            value: fmt(monitor.currentMetrics.memoryCompressed))
                LabeledLine(label: L10n.t("Tệp trong bộ nhớ đệm"),
                            value: fmt(monitor.currentMetrics.memoryCached))
                LabeledLine(label: L10n.t("Swap đã dùng"),
                            value: fmt(monitor.currentMetrics.swapUsed))

                if !monitor.metricsHistory.isEmpty {
                    SparklineView(values: monitor.metricsHistory.map(\.memoryPercentage),
                                  yMax: 100, tint: .purple, height: 26)
                        .padding(.horizontal, 20)
                }

                Divider().padding(.horizontal, 20)

                LabeledLine(label: L10n.t("Thời gian hoạt động"),
                            value: monitor.currentMetrics.uptimeString)

                Divider().padding(.horizontal, 20)

                HStack {
                    Text(L10n.t("Tần suất cập nhật"))
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $updateInterval) {
                        Text("1s").tag(1)
                        Text("2s").tag(2)
                        Text("5s").tag(5)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .onChange(of: updateInterval) { _ in
                        SystemMonitorManager.shared.applyUpdateInterval()
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        // Only sample metrics while a page that shows them is on screen.
        .onAppear { SystemMonitorManager.shared.retain() }
        .onDisappear { SystemMonitorManager.shared.release() }
    }

    // No per-process CPU list here by design. Activity Monitor already does
    // that job far better (sortable, killable, per-thread), and sampling it
    // cost a `top -l 2` subprocess every few seconds. This page answers
    // "how is the machine doing", not "which app is misbehaving".

    private var temperatureRow: some View {
        HStack(spacing: 0) {
            tempCell(title: L10n.t("Nhiệt độ SoC"), value: monitor.currentMetrics.socTempAverage)
            Divider().frame(height: 50)
            tempCell(title: L10n.t("Nóng nhất"), value: monitor.currentMetrics.socTempMax)
        }
        .padding(.horizontal, 20)
    }

    /// SoC die temperature from the HID thermal sensors (see `ThermalSensors`): the mean and the
    /// hottest die sensor. Labelled SoC, not CPU — no key says which sensors belong to CPU cores.
    /// nil (no readable sensor) renders "Không khả dụng", never 0 °C.
    private func tempCell(title: String, value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            if let value {
                Text(String(format: "%.0f °C", value))
                    .font(.system(size: 15, weight: .medium)).monospacedDigit()
            } else {
                Text(L10n.t("Không khả dụng"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .memory
        return f.string(fromByteCount: b)
    }
}

/// Label + right-aligned percent with a full-width bar underneath. `percent`
/// of nil renders the honest "Không khả dụng" state with an empty track.
