import SwiftUI

/// Hệ thống — layout mirrors the reference screenshot: two temperature
/// readouts across the top, CPU and GPU meters, a flat memory table, uptime.
///
/// Honesty Rule: CPU/GPU temperature and GPU load have no public macOS API
/// (SMC and IOAccelerator are private and unreliable on Apple Silicon), so
/// those slots render "Đang thu thập…" / "Không khả dụng" — never a number.
struct SystemDetailView: View {
    @Environment(SystemMonitorManager.self) var monitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "cpu",
                           title: "Hệ thống",
                           subtitle: "Xem nhanh CPU, đồ họa, bộ nhớ và nhiệt độ.")

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

                // GPU load: IOAccelerator is not public → no meter, no number.
                MeterRow(label: "GPU", percent: nil, tint: .teal)

                Divider().padding(.horizontal, 20)

                LabeledLine(label: "Bộ nhớ",
                            value: "\(monitor.currentMetrics.memoryUsedString) / \(monitor.currentMetrics.memoryTotalString)")
                LabeledLine(label: "Áp lực bộ nhớ",
                            value: monitor.currentMetrics.thermalState.label)
                LabeledLine(label: "Đã nén",
                            value: fmt(monitor.currentMetrics.memoryCompressed))
                LabeledLine(label: "Tệp trong bộ nhớ đệm",
                            value: fmt(monitor.currentMetrics.memoryCached))
                LabeledLine(label: "Swap đã dùng",
                            value: fmt(monitor.currentMetrics.swapUsed))

                if !monitor.metricsHistory.isEmpty {
                    SparklineView(values: monitor.metricsHistory.map(\.memoryPercentage),
                                  yMax: 100, tint: .purple, height: 26)
                        .padding(.horizontal, 20)
                }

                Divider().padding(.horizontal, 20)

                LabeledLine(label: "Thời gian hoạt động",
                            value: monitor.currentMetrics.uptimeString)
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
            tempCell(title: "CPU")
            Divider().frame(height: 50)
            tempCell(title: "GPU")
        }
        .padding(.horizontal, 20)
    }

    /// No public API exposes die temperature — show the honest placeholder.
    private func tempCell(title: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text("Đang thu thập…")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
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
struct MeterRow: View {
    let label: String
    let percent: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 13))
                Spacer()
                Text(percent.map { String(format: "%.0f%%", $0) } ?? "Không khả dụng")
                    .font(.system(size: 13, weight: percent == nil ? .regular : .semibold))
                    .foregroundColor(percent == nil ? .secondary : .primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    if let percent {
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * min(max(percent / 100, 0), 1))
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
    }
}
