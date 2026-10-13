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
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Ổ đĩa"))

                if !disk.volumes.isEmpty {
                    SettingsSection {
                        PickerRow(title: L10n.t("Ổ đĩa"), selection: $selectedMount, width: 220) {
                            ForEach(disk.volumes) { v in Text("\(v.volumeName) (\(v.mount))").tag(v.mount) }
                        }
                        .settingsRow()
                    }
                }

                if let vol = disk.volumes.first(where: { $0.mount == selectedMount }) ?? disk.volumes.first {
                    SettingsSection(title: L10n.t("Dung lượng")) {
                        VStack(spacing: XFinderTokens.Space.tight) {
                            HStack {
                                Text(vol.volumeName)
                                    .font(XFinderTokens.Font.row)
                                    .fileNameRowSafe()
                                Spacer()
                                Text(String(format: L10n.t("%.0f%% đã dùng"), vol.percentUsed))
                                    .font(XFinderTokens.Font.mono)
                                    .foregroundColor(vol.percentUsed > 90 ? .red : .primary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(XFinderTokens.Fill.inset)
                                    Capsule().fill(vol.percentUsed > 90 ? Color.red : Color.purple)
                                        .frame(width: max(0, CGFloat(vol.percentUsed / 100.0) * geo.size.width))
                                }
                            }
                            .frame(height: 8)
                            HStack {
                                Text(fmt(vol.used) + L10n.t(" đã dùng")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                Spacer()
                                Text(fmt(vol.total) + L10n.t(" tổng")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            }
                            Text("\(L10n.t("Còn trống "))\(fmt(vol.free))").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        }
                        .settingsRow()
                    }
                }

                if disk.volumes.count > 1 {
                    SettingsSection(title: L10n.t("Tất cả phân vùng")) {
                        ForEach(Array(disk.volumes.enumerated()), id: \.element.id) { index, v in
                            if index > 0 { SettingsDivider() }
                            HStack {
                                Text(v.volumeName)
                                    .font(XFinderTokens.Font.row)
                                    .fileNameRowSafe()
                                Text(v.mount)
                                    .font(XFinderTokens.Font.mono)
                                    .foregroundColor(.secondary)
                                    .fileNameRowSafe()
                                Spacer()
                                Text(String(format: "%.0f%%", v.percentUsed)).font(XFinderTokens.Font.mono)
                            }
                            .settingsRow()
                        }
                    }
                }

                SettingsSection(title: L10n.t("Tốc độ I/O (KB/s)")) {
                    VStack(spacing: XFinderTokens.Space.row) {
                        HStack(spacing: XFinderTokens.Space.inline) {
                            MetricBigNumber(value: String(format: "%.1f", disk.readKBs), unit: "KB/s", label: L10n.t("Đọc"), tint: .blue)
                            MetricBigNumber(value: String(format: "%.1f", disk.writeKBs), unit: "KB/s", label: L10n.t("Ghi"), tint: .orange)
                        }
                        HStack(spacing: XFinderTokens.Space.inline) {
                            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                                Text(L10n.t("Đọc")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                SparklineView(values: disk.historyRead, tint: .blue, height: 28)
                            }
                            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                                Text(L10n.t("Ghi")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                                SparklineView(values: disk.historyWrite, tint: .orange, height: 28)
                            }
                        }
                    }
                    .settingsRow()
                }

                SettingsSection(title: L10n.t("SMART / Tình trạng ổ đĩa")) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        HStack(spacing: XFinderTokens.Space.inline) {
                            if let raw = smartRaw {
                                // `label.key` is a store key (a model must not return display text);
                                // an unknown raw value falls through L10n.t unchanged, which is the
                                // OS's own wording — honest, not invented.
                                let label = SMARTStatus.label(forRaw: raw)
                                Image(systemName: label.healthy == true ? "checkmark.circle.fill"
                                      : (label.healthy == false ? "exclamationmark.triangle.fill"
                                         : "minus.circle"))
                                    .foregroundColor(label.healthy == true ? .green
                                        : (label.healthy == false ? .red : .secondary))
                                Text(L10n.t(label.key))
                                    .font(XFinderTokens.Font.row)
                                    .foregroundColor(label.healthy == false ? .red : .primary)
                            } else if smartChecked {
                                Image(systemName: "minus.circle").foregroundColor(.secondary)
                                Text(L10n.t("Không đọc được trạng thái SMART của ổ này"))
                                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            } else {
                                ProgressView().controlSize(.small)
                                Text(L10n.t("Đang kiểm tra…"))
                                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        InlineNote(text: L10n.t("Lấy từ `diskutil` (API công khai). macOS không cung cấp bảng thuộc tính SMART chi tiết (số sector hỏng, độ mòn, nhiệt độ ổ) nên XFinder chỉ hiển thị trạng thái tổng thể thay vì đoán thêm."))
                    }
                    .task(id: selectedMount) {
                        // Clear before refetching: switching volumes must show "Đang kiểm tra…",
                        // not the previous volume's status while diskutil runs (same ordering bug
                        // the flyout had — `if let raw` is checked before `smartChecked`).
                        smartRaw = nil
                        smartChecked = false
                        smartRaw = await DiskManager.smartStatus(forMount: selectedMount)
                        smartChecked = true
                    }
                    .settingsRow()
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
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
