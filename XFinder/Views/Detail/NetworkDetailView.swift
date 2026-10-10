import SwiftUI

/// Mạng — deliberately compact (see the reference screenshot): two live rate
/// readouts, the physical interface, which apps are using the network, the
/// session total, and a speed test. No per-interface table, no sparkline wall.
struct NetworkDetailView: View {
    @Environment(SystemMonitorManager.self) var monitor
    @State private var speed = SpeedTest.shared
    @State private var appRows: [NettopSampler.Row] = []
    @State private var sampling = false
    @State private var sampleTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "globe",
                           title: L10n.t("Mạng"),
                           subtitle: L10n.t("Lưu lượng, ứng dụng dùng mạng và tốc độ kết nối."))

                rateRow
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                LabeledLine(label: L10n.t("Giao diện vật lý"), value: primaryInterface)
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                appsSection
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                LabeledLine(label: L10n.t("Phiên này"),
                            value: "↓\(fmtBytes(monitor.sessionBytesRX))  ↑\(fmtBytes(monitor.sessionBytesTX))")
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                speedSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Fill.window)
        // Only sample metrics while a page that shows them is on screen.
        .onAppear { SystemMonitorManager.shared.retain() }
        .onDisappear { SystemMonitorManager.shared.release() }
        .onAppear { startSampling() }
        .onDisappear {
            sampleTask?.cancel()
            sampleTask = nil
        }
    }

    // MARK: Rates

    private var rateRow: some View {
        HStack(spacing: 0) {
            rateCell(icon: "arrow.down", tint: .blue,
                     value: monitor.currentMetrics.networkDownload,
                     label: L10n.t("Tải xuống"))
            Divider().frame(height: 42)
            rateCell(icon: "arrow.up", tint: .green,
                     value: monitor.currentMetrics.networkUpload,
                     label: L10n.t("Tải lên"))
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    private func rateCell(icon: String, tint: Color, value: Double, label: String) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Image(systemName: icon).foregroundColor(tint).font(XFinderTokens.Font.sectionTitle)
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.metricsHistory.isEmpty ? L10n.t("Đang đo…") : rateString(value))
                    .font(XFinderTokens.Font.sectionTitle)
                Text(label).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// KB/s below 1 MB/s, MB/s above — a fixed KB/s unit reads as noise on fast links.
    private func rateString(_ kbs: Double) -> String {
        kbs >= 1024
            ? String(format: "%.1f MB/s", kbs / 1024)
            : String(format: "%.0f KB/s", kbs)
    }

    private var primaryInterface: String {
        // Highest-traffic non-loopback interface is the one actually in use.
        let candidates = monitor.perInterfaceRates.filter { $0.key != "lo0" }
        guard let best = candidates.max(by: { ($0.value.down + $0.value.up) < ($1.value.down + $1.value.up) })
        else { return monitor.perInterfaceRates.isEmpty ? L10n.t("Đang thu thập…") : "—" }
        return best.key
    }

    // MARK: Apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                Text(L10n.t("Ứng dụng dùng mạng")).font(XFinderTokens.Font.row)
                Spacer()
                if sampling && appRows.isEmpty {
                    Text(L10n.t("Đang chờ dữ liệu…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
            }

            if appRows.isEmpty {
                Text(sampling
                     ? L10n.t("Đang lấy mẫu qua nettop (≈, cập nhật mỗi 2 giây).")
                     : L10n.t("Chưa có dữ liệu."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            } else {
                ForEach(appRows) { row in
                    HStack {
                        Text(row.name).font(XFinderTokens.Font.rowValue).lineLimit(1)
                        Spacer()
                        Text(String(format: "↓ %@  ↑ %@", rateString(row.downKBs), rateString(row.upKBs)))
                            .font(XFinderTokens.Font.mono)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                Text(L10n.t("Số liệu xấp xỉ từ nettop — không có API công khai cho lưu lượng theo tiến trình."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    /// Repeating 2s sample while the page is visible; cancelled on disappear so
    /// no `nettop` process survives the page (idle CPU stays 0%).
    private func startSampling() {
        guard sampleTask == nil else { return }
        sampling = true
        sampleTask = Task {
            while !Task.isCancelled {
                let rows = await NettopSampler.sample(duration: 2)
                if Task.isCancelled { break }
                appRows = rows
            }
            sampling = false
        }
    }

    // MARK: Speed test

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            switch speed.state {
            case .idle:
                Button { speed.start() } label: {
                    Label(L10n.t("Đo tốc độ"), systemImage: "speedometer")
                }
                .buttonStyle(.bordered).controlSize(.small)
            case .running:
                HStack(spacing: XFinderTokens.Space.row) {
                    ProgressView().scaleEffect(0.6)
                    Text(L10n.t("Đang đo…")).font(XFinderTokens.Font.rowValue)
                    Button(L10n.t("Hủy")) { speed.cancel() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            case .done(let mbps, let seconds):
                HStack(spacing: XFinderTokens.Space.row) {
                    Text(String(format: "%.1f Mbps", mbps))
                        .font(XFinderTokens.Font.sectionTitle)
                    Text(String(format: L10n.t("25 MB trong %.1f giây"), seconds))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    Button(L10n.t("Đo lại")) { speed.start() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            case .failed(let msg):
                HStack(spacing: XFinderTokens.Space.row) {
                    Text(msg).font(XFinderTokens.Font.rowValue).foregroundColor(.red)
                    Button(L10n.t("Thử lại")) { speed.start() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }

            Text(L10n.t("Phép đo dùng dữ liệu Internet. Đóng tất cả màn hình theo dõi mạng để hủy."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    private func fmtBytes(_ b: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .binary
        return f.string(fromByteCount: Int64(b))
    }
}
