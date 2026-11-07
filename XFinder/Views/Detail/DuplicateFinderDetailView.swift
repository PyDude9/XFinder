import SwiftUI
import AppKit

struct DuplicateFinderDetailView: View {
    @State private var model = DuplicateFinderModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Tìm tệp trùng"))
                SettingsSection {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        InlineNote(text: L10n.t("Quét trên máy; tệp chỉ thay đổi khi bạn xác nhận chuyển vào Thùng rác."))
                        InlineNote(text: L10n.t("Liên kết, gói ứng dụng và tệp chưa tải về được bỏ qua; các đường dẫn tới cùng một tệp chỉ được tính một lần."))
                        HStack {
                            Button(L10n.t("Chọn thư mục…")) { model.choose() }.disabled(model.busy)
                            Button(L10n.t("Quét")) { model.scan() }.disabled(model.root == nil || model.busy)
                            if model.busy { Button(L10n.t("Huỷ"), role: .cancel) { model.cancel() } }
                        }
                        if let root = model.root { Text(root.path).font(XFinderTokens.Font.caption).textSelection(.enabled) }
                        if model.busy {
                            ProgressView(L10n.t(model.phaseKey)).controlSize(.small)
                            if model.phaseKey != "Đang kiểm tra lại các bản đã chọn…" && model.phaseKey != "Đang chuyển vào Thùng rác…" {
                                Text(String(format: L10n.t("Đã xử lý %d tệp; bỏ qua %d mục."), model.processed, model.skipped))
                                    .font(XFinderTokens.Font.caption)
                            }
                        }
                        if !model.message.isEmpty { InlineNote(text: model.message) }
                        if !model.details.isEmpty {
                            LazyVStack(alignment: .leading) {
                                ForEach(model.details, id: \.self) { Text($0).font(XFinderTokens.Font.caption).textSelection(.enabled) }
                            }
                        }
                        if let result = model.result {
                            Text(String(format: L10n.t("%d nhóm trùng; đã quét %d tệp; bỏ qua %d mục."), result.groups.count, result.scanned, result.skipped))
                            Text(L10n.t(model.statusKey)).font(XFinderTokens.Font.caption).foregroundStyle(.secondary)
                            Text(L10n.t("Dung lượng logic đã chọn: ") + ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))
                                .font(XFinderTokens.Font.caption)
                            Button(L10n.t("Chuyển các bản đã chọn vào Thùng rác…")) { model.prepare() }
                                .disabled(model.busy || model.plan == nil)
                            if !model.writeAllowed { InlineNote(text: L10n.t("Không có quyền ghi vào thư mục. Bạn vẫn có thể xem kết quả và hiện tệp trong Finder.")) }
                            if model.plan == nil { InlineNote(text: L10n.t("Chọn bản cần bỏ và giữ ít nhất một bản trong mỗi nhóm. Chỉ kết quả quét đầy đủ mới cho phép chuyển vào Thùng rác.")) }
                            if result.groups.isEmpty && result.status == .complete && !model.busy { Text(L10n.t("Không tìm thấy tệp trùng y hệt.")) }
                        }
                    }.settingsRow()
                }
                if let result = model.result {
                    LazyVStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        ForEach(result.groups) { group in
                            SettingsSection {
                                LazyVStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                                    ForEach(group.files) { file in
                                        HStack(alignment: .top) {
                                            Toggle(isOn: Binding(get: { model.selection.contains(file.id) }, set: { value in
                                                if value { model.selection.insert(file.id) } else { model.selection.remove(file.id) }
                                            })) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(file.name).fileNameRowSafe()
                                                    Text(file.relativePath).font(XFinderTokens.Font.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                                    Text(ByteCountFormatter.string(fromByteCount: file.fingerprint.size, countStyle: .file) + L10n.t(" · ") +
                                                         Date(timeIntervalSince1970: Double(file.fingerprint.modifiedSeconds)).formatted())
                                                        .font(XFinderTokens.Font.caption)
                                                    if file.id == group.files.first?.id { Text(L10n.t("Gợi ý giữ lại")).font(XFinderTokens.Font.caption).foregroundStyle(.secondary) }
                                                }
                                            }.toggleStyle(.checkbox).disabled(model.busy)
                                            Spacer()
                                            Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                                        }
                                    }
                                }.settingsRow()
                            }
                        }
                    }
                }
            }.padding(.bottom, XFinderTokens.Space.section).pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onDisappear { model.cancel() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in model.cancel() }
        .alert(L10n.t("Chuyển vào Thùng rác?"), isPresented: $model.showConfirmation) {
            Button(L10n.t("Huỷ"), role: .cancel) { model.pending = [] }.keyboardShortcut(.defaultAction)
            Button(L10n.t("Chuyển vào Thùng rác"), role: .destructive) { model.confirm() }
        } message: {
            Text(String(format: L10n.t("Chỉ chuyển %d bản đã chọn trong thư mục này vào Thùng rác. Mỗi tệp và bản giữ lại sẽ được kiểm tra lại ngay trước khi chuyển."), model.pending.count) + "\n" + (model.root?.path ?? ""))
        }
    }
}

@MainActor @Observable
private final class DuplicateFinderModel {
    // Retain actual move outcomes across page navigation; no operation is resumed automatically.
    static let shared = DuplicateFinderModel()
    private init() {}
    var root: URL?
    var result: DuplicateResult?
    var selection = Set<String>()
    var pending: [DuplicateMove] = []
    var showConfirmation = false
    var writeAllowed = false
    var busy = false
    var phaseKey = "Đang nhóm theo kích thước…"
    var processed = 0
    var skipped = 0
    var message = ""
    var details: [String] = []
    private var task: Task<Void, Never>?
    private var run = UUID()
    private var lastProgress = 0.0
    var plan: [DuplicateMove]? {
        guard let result, writeAllowed else { return nil }
        return DuplicateRules.plan(groups: result.groups, selected: selection, complete: result.status == .complete)
    }
    var selectedBytes: Int64 {
        guard let result, !selection.isEmpty else { return 0 }
        var total: Int64 = 0
        for group in result.groups {
            for file in group.files where selection.contains(file.id) {
                let (sum, overflow) = total.addingReportingOverflow(file.fingerprint.size)
                total = overflow ? Int64.max : sum
            }
        }
        return total
    }
    var statusKey: String {
        switch result?.status {
        case .complete: return "Đã quét đầy đủ. Kích thước là byte logic, không phải dung lượng vật lý chắc chắn giải phóng."
        case .incomplete: return "Kết quả chưa đầy đủ hoặc đã chạm giới hạn 500.000 tệp. Hãy chọn phạm vi nhỏ hơn và quét lại."
        case .cancelled: return "Đã huỷ quét; không thể chuyển tệp từ kết quả này vào Thùng rác."
        default: return "Không đọc được thư mục. Hãy chọn lại thư mục và kiểm tra quyền truy cập."
        }
    }
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeAllowed = FileManager.default.isWritableFile(atPath: url.path)
        root = url; result = nil; selection = []; pending = []; message = ""; details = []
    }
    func scan() {
        guard let root, !busy else { return }
        let token = UUID(); run = token
        busy = true; result = nil; selection = []; pending = []; message = ""; details = []; processed = 0; skipped = 0
        phaseKey = "Đang nhóm theo kích thước…"
        task = Task { [weak self] in
            let result = await DuplicateScanEngine.scan(root: root) { [weak self] progress in
                Task { @MainActor [weak self] in self?.receive(progress, token: token) }
            }
            guard let self, self.run == token else { return }
            self.result = Task.isCancelled ? .init(groups: [], status: .cancelled, scanned: result.scanned, skipped: result.skipped) : result
            self.writeAllowed = FileManager.default.isWritableFile(atPath: root.path)
            self.busy = false
        }
    }
    private func receive(_ progress: DuplicateProgress, token: UUID) {
        guard token == run, busy else { return }
        let key: String
        switch progress.phase {
        case .grouping: key = "Đang nhóm theo kích thước…"
        case .hashing: key = "Đang tính checksum…"
        case .comparing: key = "Đang so sánh nội dung…"
        case .verifying: key = "Đang kiểm tra lại các bản đã chọn…"
        case .moving: key = "Đang chuyển vào Thùng rác…"
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard key != phaseKey || now - lastProgress >= 0.2 else { return }
        lastProgress = now; phaseKey = key; processed = progress.processed; skipped = progress.skipped
    }
    func prepare() {
        guard let plan, !busy else { return }
        run = UUID() // Drop any scan progress still queued on MainActor before entering verification.
        busy = true; phaseKey = "Đang kiểm tra lại các bản đã chọn…"; message = ""
        task = Task { [weak self] in
            let checked = await DuplicateTrash.prepare(plan)
            guard let self else { return }
            self.busy = false
            self.details = checked.rejectedPaths.map { L10n.t("Nhóm thay đổi hoặc không đọc được: ") + $0 }
            if !checked.cancelled && !Task.isCancelled {
                self.pending = checked.moves; self.showConfirmation = !checked.moves.isEmpty
            }
            self.message = (checked.cancelled || Task.isCancelled) ? L10n.t("Đã huỷ kiểm tra.") :
                String(format: L10n.t("Đã kiểm tra: %d bản hợp lệ; loại %d bản do nhóm thay đổi hoặc không đọc được."), checked.moves.count, checked.rejected)
        }
    }
    func confirm() {
        let moves = pending; pending = []
        guard !moves.isEmpty, !busy else { return }
        let chosen = selection
        run = UUID()
        busy = true; phaseKey = "Đang chuyển vào Thùng rác…"
        task = Task { [weak self] in
            let outcome = await DuplicateTrash.run(moves, selected: chosen)
            guard let self else { return }
            self.busy = false; self.selection = []; self.result = nil
            self.details = outcome.failed.map { L10n.t("Không thể chuyển: ") + $0 } + outcome.skipped.map { L10n.t("Bỏ qua: ") + $0 }
            self.message = String(format: L10n.t("Đã chuyển %d tệp; lỗi %d; bỏ qua %d. Hãy quét lại để cập nhật kết quả."), outcome.moved.count, outcome.failed.count, outcome.skipped.count)
            if outcome.cancelled { self.message += L10n.t(" Đã dừng các lần chuyển tiếp theo; các tệp đã chuyển vẫn ở Thùng rác.") }
        }
    }
    func cancel() { task?.cancel(); pending = []; showConfirmation = false }
}
