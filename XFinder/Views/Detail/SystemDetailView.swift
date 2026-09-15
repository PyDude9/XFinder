import SwiftUI

/// Hệ thống — layout mirrors the reference screenshot: two temperature
/// readouts across the top, CPU and GPU meters, a flat memory table, uptime.
///
/// Honesty Rule: CPU/GPU temperature and GPU load have no public macOS API
/// (SMC and IOAccelerator are private and unreliable on Apple Silicon), so
/// those slots render "Đang thu thập…" / "Không khả dụng" — never a number.
struct SystemDetailView: View {
    @Environment(SystemMonitorManager.self) var monitor

    @State private var topProcesses: [ProcessSampler.Row] = []
    @State private var sampleTask: Task<Void, Never>?
    /// Distinguishes "still sampling" from "genuinely nothing to show".
    @State private var loadedOnce = false

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

                Divider().padding(.horizontal, 20)

                topProcessesSection
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        // Only sample metrics while a page that shows them is on screen.
        .onAppear {
            SystemMonitorManager.shared.retain()
            startSampling()
        }
        .onDisappear {
            SystemMonitorManager.shared.release()
            sampleTask?.cancel()
            sampleTask = nil
        }
    }

    // MARK: - Top CPU processes
    //
    // Replaces the old per-core bar list. Knowing core 7 is at 40% is not
    // actionable; knowing *which app* is burning the CPU is.

    /// Polls in a loop while the page is visible, cancelled on disappear so the
    /// app's idle CPU stays at zero when nobody is looking.
    private func startSampling() {
        guard sampleTask == nil else { return }
        sampleTask = Task {
            while !Task.isCancelled {
                let rows = await ProcessSampler.topCPU(limit: 10)
                if Task.isCancelled { return }
                topProcesses = rows
                loadedOnce = true
                // `top -l 2` already blocks ~2 s, so this is a ~4 s cadence.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var topProcessesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "list.bullet.rectangle",
                          title: "Ứng dụng dùng nhiều CPU",
                          subtitle: "Top 10, lấy mẫu theo thời gian thực mỗi vài giây.")

            if !loadedOnce {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Đang lấy mẫu…")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            } else if topProcesses.isEmpty {
                Text("Không có tiến trình nào đang dùng CPU đáng kể.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 6) {
                    ForEach(topProcesses) { row in
                        processRow(row)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func processRow(_ row: ProcessSampler.Row) -> some View {
        HStack(spacing: 9) {
            Group {
                if let url = row.bundleURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                } else {
                    // A pid with no bundle is a daemon or helper — a generic
                    // gear is honest, an app icon would be a guess.
                    Image(systemName: "gearshape.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.secondary)
                        .padding(2)
                }
            }
            .frame(width: 16, height: 16)

            Text(row.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                // Without this a long process name pushes the whole window
                // wider — the sidebar-resize bug in CLAUDE.md.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", row.cpuPercent))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(row.cpuPercent >= 50 ? .orange : .secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

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
