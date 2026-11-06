import SwiftUI
import AppKit

struct StorageDetailView: View {
    @State private var disk = DiskManager.shared
    @State private var selectedMount: String = "/"
    /// Raw `diskutil` SMART string for the selected volume, e.g. "Verified".
    @State private var smartRaw: String? = nil
    /// Distinguishes "still querying" from "queried and got nothing".
    @State private var smartChecked = false
    @State private var storageScan = StorageScanController()

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

                storageScanSection

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
        .onDisappear {
            disk.stop()
            storageScan.cancel()
        }
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

    private var storageScanSection: some View {
        SettingsSection(title: L10n.t("Phân tích thư mục")) {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                InlineNote(text: L10n.t("Quét một thư mục bạn chọn và hiển thị dung lượng logic của các tệp. XFinder không thay đổi tệp."))

                HStack(spacing: XFinderTokens.Space.inline) {
                    Button {
                        storageScan.chooseFolder()
                    } label: {
                        Label(L10n.t("Chọn thư mục để phân tích"), systemImage: "folder.badge.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(storageScan.isScanning)

                    if storageScan.isScanning {
                        Button(L10n.t("Huỷ quét"), role: .cancel) { storageScan.cancel() }
                            .buttonStyle(.bordered)
                    }
                }

                if let rootName = storageScan.rootName {
                    Text(rootName)
                        .font(XFinderTokens.Font.row)
                        .fileNameRowSafe()
                }

                if storageScan.isScanning, let progress = storageScan.progress {
                    ProgressView(L10n.t("Đang quét…"))
                        .controlSize(.small)
                    Text("\(L10n.t("Đã quét "))\(progress.visitedEntries)\(L10n.t(" mục"))\(L10n.t(" · "))\(progress.fileCount)\(L10n.t(" tệp"))")
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                    if !progress.currentRelativePath.isEmpty {
                        Text(progress.currentRelativePath)
                            .font(XFinderTokens.Font.mono)
                            .foregroundColor(.secondary)
                            .fileNameRowSafe()
                    }
                }

                if let failure = storageScan.result?.failure {
                    InlineNote(kind: .warning, text: L10n.t(failure.localizationKey))
                }

                if let result = storageScan.result, result.failure == nil {
                    scanSummary(result)
                }
            }
            .settingsRow()
        }
    }

    @ViewBuilder
    private func scanSummary(_ result: StorageScanResult) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack {
                Text(L10n.t(result.status.localizationKey))
                    .font(XFinderTokens.Font.row)
                Spacer()
                if result.status == .partial {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .accessibilityLabel(L10n.t("Kết quả chưa đầy đủ"))
                } else if result.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .accessibilityLabel(L10n.t("Hoàn tất"))
                }
            }

            Text("\(L10n.t("Tổng dung lượng logic: "))\(fmt(result.logicalBytes))")
                .font(XFinderTokens.Font.rowValue)
            Text("\(L10n.t("Đã quét "))\(result.visitedEntries)\(L10n.t(" mục"))\(L10n.t(" · "))\(result.fileCount)\(L10n.t(" tệp"))")
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)

            if result.skippedCount > 0 {
                Text("\(L10n.t("Đã bỏ qua "))\(result.skippedCount)\(L10n.t(" mục; kết quả có thể chưa đầy đủ."))")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.orange)
            }
            if result.status == .cancelled {
                InlineNote(text: L10n.t("Đã huỷ. Đây là kết quả một phần."))
            }
            if result.didOverflow {
                InlineNote(kind: .warning, text: L10n.t("Tổng dung lượng vượt giới hạn tính toán an toàn."))
            }

            if result.largestFiles.isEmpty {
                Text(L10n.t("Không có tệp nào để hiển thị"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            } else {
                SettingsDivider()
                Text(L10n.t("Tệp lớn nhất"))
                    .font(XFinderTokens.Font.row)
                ForEach(Array(result.largestFiles.enumerated()), id: \.element.id) { index, file in
                    if index > 0 { SettingsDivider() }
                    HStack(alignment: .top, spacing: XFinderTokens.Space.inline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(XFinderTokens.Font.rowValue)
                                .fileNameRowSafe()
                            Text(file.relativePath)
                                .font(XFinderTokens.Font.mono)
                                .foregroundColor(.secondary)
                                .fileNameRowSafe()
                        }
                        Spacer(minLength: XFinderTokens.Space.inline)
                        Text(fmt(file.logicalSize))
                            .font(XFinderTokens.Font.mono)
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.top, XFinderTokens.Space.tight)
    }
}

@MainActor
@Observable
private final class StorageScanController {
    private(set) var phase: Phase = .idle
    private(set) var rootName: String?
    private(set) var progress: StorageScanProgress?
    private(set) var result: StorageScanResult?

    private var currentRun = UUID()
    private var task: Task<Void, Never>?

    var isScanning: Bool { phase == .scanning }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.t("Chọn thư mục")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start(url)
    }

    func start(_ rootURL: URL) {
        task?.cancel()
        let run = UUID()
        currentRun = run
        rootName = rootURL.lastPathComponent
        progress = StorageScanProgress(visitedEntries: 0, fileCount: 0, skippedCount: 0, currentRelativePath: "")
        result = nil
        phase = .scanning

        task = Task { [weak self] in
            let outcome = await StorageScanEngine.scan(rootURL: rootURL) { [weak self] nextProgress in
                Task { @MainActor [weak self] in
                    self?.receive(nextProgress, run: run)
                }
            }
            guard let self, self.currentRun == run else { return }
            self.result = outcome
            self.progress = StorageScanProgress(
                visitedEntries: outcome.visitedEntries,
                fileCount: outcome.fileCount,
                skippedCount: outcome.skippedCount,
                currentRelativePath: self.progress?.currentRelativePath ?? ""
            )
            switch outcome.status {
            case .completed: self.phase = .completed
            case .partial: self.phase = .partial
            case .cancelled: self.phase = .cancelled
            case .failed: self.phase = .failed
            }
            self.task = nil
        }
    }

    func cancel() {
        guard isScanning else { return }
        task?.cancel()
    }

    private func receive(_ newProgress: StorageScanProgress, run: UUID) {
        guard currentRun == run, isScanning else { return }
        progress = newProgress
    }

    enum Phase: Equatable {
        case idle, scanning, completed, partial, cancelled, failed
    }
}

private extension StorageScanStatus {
    var localizationKey: String {
        switch self {
        case .completed: return "Quét hoàn tất"
        case .partial: return "Kết quả chưa đầy đủ"
        case .cancelled: return "Đã huỷ quét"
        case .failed: return "Không thể quét thư mục"
        }
    }
}

private extension StorageScanFailure {
    var localizationKey: String {
        switch self {
        case .unavailableRoot: return "Không thể truy cập thư mục đã chọn."
        case .rootIsNotDirectory: return "Mục đã chọn không phải là thư mục."
        case .rootNotReadable: return "Không có quyền đọc thư mục đã chọn."
        case .rootCloudOnly: return "Thư mục chỉ có trên đám mây. Hãy tải về trước khi quét."
        }
    }
}
