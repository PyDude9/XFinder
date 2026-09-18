import SwiftUI

struct StorageDetailView: View {
    @State private var disk = DiskManager.shared
    @State private var selectedMount: String = "/"
    /// Raw `diskutil` SMART string for the selected volume, e.g. "Verified".
    @State private var smartRaw: String? = nil
    /// Distinguishes "still querying" from "queried and got nothing".
    @State private var smartChecked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("Ổ đĩa"))
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                if !disk.volumes.isEmpty {
                    Picker(L10n.t("Ổ đĩa"), selection: $selectedMount) {
                        ForEach(disk.volumes) { v in Text("\(v.volumeName) (\(v.mount))").tag(v.mount) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                }

                if let vol = disk.volumes.first(where: { $0.mount == selectedMount }) ?? disk.volumes.first {
                    SettingsCard {
                        VStack(spacing: 10) {
                            HStack {
                                Text(vol.volumeName).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(String(format: L10n.t("%.0f%% đã dùng"), vol.percentUsed))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(vol.percentUsed > 90 ? .red : .primary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.12))
                                    Capsule().fill(vol.percentUsed > 90 ? Color.red : Color.purple)
                                        .frame(width: max(0, CGFloat(vol.percentUsed / 100.0) * geo.size.width))
                                }
                            }
                            .frame(height: 8)
                            HStack {
                                Text(fmt(vol.used) + L10n.t(" đã dùng")).font(.system(size: 11)).foregroundColor(.secondary)
                                Spacer()
                                Text(fmt(vol.total) + L10n.t(" tổng")).font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            Text("\(L10n.t("Còn trống "))\(fmt(vol.free))").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if disk.volumes.count > 1 {
                    SettingsCard(title: L10n.t("Tất cả phân vùng")) {
                        VStack(spacing: 8) {
                            ForEach(disk.volumes) { v in
                                HStack {
                                    Text(v.volumeName).font(.system(size: 12, weight: .medium))
                                    Text(v.mount).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.0f%%", v.percentUsed)).font(.system(size: 11, design: .monospaced))
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                SettingsCard(title: L10n.t("Tốc độ I/O (KB/s)")) {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            MetricBigNumber(value: String(format: "%.1f", disk.readKBs), unit: "KB/s", label: L10n.t("Đọc"), tint: .blue)
                            MetricBigNumber(value: String(format: "%.1f", disk.writeKBs), unit: "KB/s", label: "Ghi", tint: .orange)
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.t("Đọc")).font(.system(size: 11)).foregroundColor(.secondary)
                                SparklineView(values: disk.historyRead, tint: .blue, height: 28)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ghi").font(.system(size: 11)).foregroundColor(.secondary)
                                SparklineView(values: disk.historyWrite, tint: .orange, height: 28)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: L10n.t("SMART / Tình trạng ổ đĩa")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if let raw = smartRaw {
                                let label = DiskManager.smartLabel(raw)
                                Image(systemName: label.healthy == true ? "checkmark.circle.fill"
                                      : (label.healthy == false ? "exclamationmark.triangle.fill"
                                         : "minus.circle"))
                                    .foregroundColor(label.healthy == true ? .green
                                        : (label.healthy == false ? .red : .secondary))
                                Text(label.text)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(label.healthy == false ? .red : .primary)
                            } else if smartChecked {
                                Image(systemName: "minus.circle").foregroundColor(.secondary)
                                Text(L10n.t("Không đọc được trạng thái SMART của ổ này"))
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            } else {
                                ProgressView().controlSize(.small)
                                Text(L10n.t("Đang kiểm tra…"))
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        Text(L10n.t("Lấy từ `diskutil` (API công khai). macOS không cung cấp bảng thuộc tính SMART chi tiết (số sector hỏng, độ mòn, nhiệt độ ổ) nên XFinder chỉ hiển thị trạng thái tổng thể thay vì đoán thêm."))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .task(id: selectedMount) {
                    smartChecked = false
                    smartRaw = await DiskManager.smartStatus(forMount: selectedMount)
                    smartChecked = true
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
        .onAppear { disk.start() }
        .onDisappear { disk.stop() }
        .onChange(of: disk.volumes) { _, new in
            if !new.contains(where: { $0.mount == selectedMount }), let first = new.first {
                selectedMount = first.mount
            }
        }
    }

    private func fmt(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.allowedUnits = [.useGB, .useTB]; f.countStyle = .file
        return f.string(fromByteCount: b)
    }
}
