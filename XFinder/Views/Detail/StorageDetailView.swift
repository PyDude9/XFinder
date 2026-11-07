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

            if let tree = result.tree, tree.nodes[0].bytes > 0, result.status != .cancelled {
                StorageTreeChartView(tree: tree).id(storageScan.rootName)
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

private struct StorageTreeChartView: View {
    let tree: StorageTree
    @AppStorage("storage.chartStyle") private var style = "treemap"
    @AppStorage("storage.chartFraction") private var fraction = 0.6
    @State private var root = 0
    @State private var selected: Int?

    private var children: [StorageTreeNode] { tree.nodes[root].children.map { tree.nodes[$0] } }
    private func title(_ node: StorageTreeNode) -> String {
        node.isAggregate ? String(format: L10n.t("%d tệp khác"), node.fileCount) : node.name
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    private struct Region {
        let id: Int
        let depth: Int
        let path: Path
        let label: CGRect?
    }

    /// Draw at most four visible levels and 1,500 regions; deeper nodes remain reachable through the inspector.
    private func chartRegions(_ size: CGSize) -> [Region] {
        var result: [Region] = []
        var queue: [(Int, CGRect, Double, Double, Int)] = [(root, CGRect(origin: .zero, size: size), 0, 1, 0)]
        while let (parent, rect, start, span, depth) = queue.popLast(), result.count < 1500 {
            guard depth < 4 else { continue }
            let ids = tree.nodes[parent].children
            let total = ids.reduce(0.0) { $0 + Double(tree.nodes[$1].bytes) }
            guard total > 0 else { continue }
            var offset = 0.0
            for id in ids where result.count < 1500 {
                let node = tree.nodes[id]
                let share = Double(node.bytes) / total
                guard share > 0 else { continue }
                let childRect: CGRect
                if depth.isMultiple(of: 2) {
                    childRect = CGRect(x: rect.minX + offset * rect.width, y: rect.minY,
                                       width: share * rect.width, height: rect.height)
                } else {
                    childRect = CGRect(x: rect.minX, y: rect.minY + offset * rect.height,
                                       width: rect.width, height: share * rect.height)
                }
                let a = start + span * offset
                let arc = span * share
                var path = Path()
                var label: CGRect?
                if style == "sunburst" {
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let ring = min(size.width, size.height) / 10
                    let inner = ring * Double(depth + 1)
                    let outer = inner + ring - 1
                    path.addArc(center: center, radius: outer, startAngle: .degrees(a * 360 - 90), endAngle: .degrees((a + arc) * 360 - 90), clockwise: false)
                    path.addArc(center: center, radius: inner, startAngle: .degrees((a + arc) * 360 - 90), endAngle: .degrees(a * 360 - 90), clockwise: true)
                    path.closeSubpath()
                } else {
                    path = Path(childRect.insetBy(dx: 1, dy: 1))
                    if childRect.width >= 60 && childRect.height >= 30 {
                        label = CGRect(x: childRect.minX + 4, y: childRect.minY + 3, width: childRect.width - 8, height: 20)
                    }
                }
                result.append(.init(id: id, depth: depth, path: path, label: label))
                if node.isDirectory {
                    let interior = CGRect(x: childRect.minX + 2, y: childRect.minY + 25,
                                          width: max(0, childRect.width - 4), height: max(0, childRect.height - 27))
                    if style == "sunburst" || (interior.width > 4 && interior.height > 4) {
                        queue.append((id, interior, a, arc, depth + 1))
                    }
                }
                offset += share
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading) {
            Picker(L10n.t("Kiểu biểu đồ"), selection: $style) {
                Text(L10n.t("Bản đồ cây")).tag("treemap")
                Text(L10n.t("Biểu đồ vòng")).tag("sunburst")
            }.pickerStyle(.segmented)
            HStack {
                Text(L10n.t("Tỷ lệ vùng biểu đồ"))
                Slider(value: $fraction, in: 0.3...0.7, step: 0.05)
                    .accessibilityLabel(L10n.t("Tỷ lệ vùng biểu đồ"))
            }
            if tree.simplified { InlineNote(text: L10n.t("Biểu đồ đã được giản lược; tổng dung lượng vẫn được giữ.")) }
            if root != 0 {
                Button(L10n.t("Về thư mục gốc")) { root = 0; selected = nil }
            }
            Text(tree.nodes[root].name).font(XFinderTokens.Font.row)
            if let selected, tree.nodes.indices.contains(selected) {
                let node = tree.nodes[selected]
                Text(title(node) + L10n.t(" · ") + size(node.bytes)).font(XFinderTokens.Font.rowValue)
                if !node.isAggregate { Text(node.path).font(XFinderTokens.Font.caption).textSelection(.enabled) }
                if node.isDirectory {
                    Button(L10n.t("Mở trong biểu đồ")) { root = node.id; self.selected = nil }
                }
            }
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 12) {
                    let chartSize = CGSize(width: max(1, (geo.size.width - 12) * fraction), height: 240)
                    let regions = chartRegions(chartSize)
                    Canvas { context, _ in
                        for region in regions {
                            let color = Color(hue: Double(region.id % 10) / 10, saturation: 0.55,
                                              brightness: selected == region.id ? 1 : 0.7 + Double(region.depth) * 0.04)
                            context.fill(region.path, with: .color(color))
                            if let label = region.label {
                                context.draw(Text(title(tree.nodes[region.id])).font(.caption).foregroundColor(.white), in: label)
                            }
                        }
                    }
                    .frame(width: chartSize.width)
                    .accessibilityLabel(L10n.t("Dung lượng logic theo thư mục"))
                    .onTapGesture { point in
                        selected = regions.last(where: { $0.path.contains(point) })?.id
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(children) { node in
                                Button { selected = node.id } label: {
                                    VStack(alignment: .leading) {
                                        Text(title(node)).lineLimit(2)
                                        Text(size(node.bytes)).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.borderless)
                                .background(selected == node.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                if selected == node.id, node.isDirectory {
                                    Button(L10n.t("Mở trong biểu đồ")) { root = node.id; selected = nil }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 240)
        }
        .onAppear {
            style = StorageChartPreferences.style(style)
            fraction = StorageChartPreferences.fraction(fraction)
        }
    }
}
