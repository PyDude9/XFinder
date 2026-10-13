import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// F1 — Dọn rác thư mục. The user comes here to clear known system metadata out of ONE folder before zipping it,
/// copying it to a USB stick or sending it to someone on Windows. The list is the preview; the button moves only what
/// is still ticked, and only to the Trash (`JunkCleanup.moveToTrash` re-checks each item first).
struct JunkCleanupDetailView: View {
    @State private var folder: URL?
    @State private var report: JunkCleanup.Report?
    @State private var scanHandle: Task<JunkCleanup.Report, Never>?
    @State private var excluded: Set<JunkCleanup.Kind> = []
    @State private var working = false
    @State private var outcome: String?
    @State private var outcomeIsError = false
    @State private var dropTargeted = false

    private var scanning: Bool { scanHandle != nil }
    private var chosen: [JunkCleanup.Item] { (report?.items ?? []).filter { !excluded.contains($0.kind) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "bubbles.and.sparkles",
                           title: L10n.t("Dọn rác thư mục"),
                           subtitle: L10n.t("Gỡ .DS_Store, ._tên, __MACOSX, Thumbs.db… khỏi một thư mục trước khi nén, chép sang USB hay gửi cho máy Windows. Xem trước, chỉ vào Thùng rác."))
                folderSection
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                resultSection
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                InlineNote(text: L10n.t("Chỉ chọn siêu dữ liệu đã biết của Finder, AppleDouble, file nén và Windows — không bao giờ chọn \"file tạm\" chung chung. Không đi theo bí danh hay liên kết, không vào bên trong gói ứng dụng, không sang ổ khác, bỏ qua file iCloud chưa tải. Finder có thể tạo lại .DS_Store khi bạn mở thư mục."))
                    .padding(.horizontal, XFinderTokens.Space.page)
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .onDisappear { scanHandle?.cancel() }
    }

    // MARK: Folder

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "folder", title: L10n.t("Thư mục cần dọn"),
                          subtitle: folder.map { $0.path } ?? L10n.t("Chưa chọn thư mục"))
            HStack(spacing: XFinderTokens.Space.tight) {
                Button(L10n.t("Chọn thư mục…")) { pickFolder() }
                Button(L10n.t("Dùng thư mục đang chọn trong Finder")) { useFinderSelection() }
                if folder != nil && !scanning {
                    Button(L10n.t("Quét lại")) { startScan() }
                }
            }
            .disabled(working)
            .padding(.horizontal, XFinderTokens.Space.page)
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundColor(dropTargeted ? .accentColor : Color.primary.opacity(0.2))
                .frame(height: 52)
                .overlay(Text(L10n.t("Hoặc thả một thư mục vào đây"))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary))
                .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                    guard let p = providers.first else { return false }
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in choose(url) }
                    }
                    return true
                }
                .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    // MARK: Result

    @ViewBuilder private var resultSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "list.bullet", title: L10n.t("Sẽ chuyển vào Thùng rác"),
                          subtitle: L10n.t("Bỏ chọn nhóm nào bạn muốn giữ lại."))
            Group {
                if scanning {
                    HStack(spacing: XFinderTokens.Space.tight) {
                        ProgressView().controlSize(.small)
                        Text(L10n.t("Đang quét…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        Button(L10n.t("Hủy")) { scanHandle?.cancel() }.controlSize(.small)
                    }
                } else if let report {
                    reportView(report)
                } else {
                    Text(L10n.t("Chọn một thư mục để xem có gì cần dọn."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                if let outcome {
                    InlineNote(kind: outcomeIsError ? .warning : .success, text: outcome)
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    @ViewBuilder private func reportView(_ r: JunkCleanup.Report) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            if r.cancelled {
                InlineNote(kind: .warning, text: L10n.t("Đã huỷ quét — danh sách dưới đây chưa đủ."))
            }
            if r.truncated {
                InlineNote(kind: .warning, text: "\(L10n.t("Thư mục quá lớn: chỉ xem "))\(JunkCleanup.maxEntries.formatted())\(L10n.t(" mục đầu. Hãy chọn một thư mục nhỏ hơn."))")
            }
            if r.items.isEmpty && !r.cancelled {
                InlineNote(kind: .success, text: L10n.t("Thư mục này đã sạch — không có rác metadata nào."))
            }
            ForEach(JunkCleanup.groups(r.items), id: \.kind) { g in
                groupRow(g, items: r.items.filter { $0.kind == g.kind })
            }
            Text(summaryLine(r)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            if !r.items.isEmpty {
                HStack {
                    Button("\(L10n.t("Chuyển "))\(chosen.count)\(L10n.t(" mục vào Thùng rác"))") { moveToTrash() }
                        .buttonStyle(.borderedProminent)
                        .disabled(chosen.isEmpty || working)
                    if working { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    private func groupRow(_ g: JunkCleanup.Group, items: [JunkCleanup.Item]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { !excluded.contains(g.kind) },
                                 set: { on in if on { excluded.remove(g.kind) } else { excluded.insert(g.kind) } })) {
                HStack {
                    Text(L10n.t(g.kind.titleKey)).font(XFinderTokens.Font.row)
                    Spacer()
                    Text("\(g.count)\(L10n.t(" mục")) · \(ByteCountFormatter.string(fromByteCount: g.bytes, countStyle: .file))")
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            Text(L10n.t(g.kind.explanationKey))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .padding(.leading, 20)
            DisclosureGroup(L10n.t("Xem đường dẫn")) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items.prefix(100), id: \.url) { item in
                        Text(folder.map { JunkCleanup.relativePath(item.url, root: $0) } ?? item.url.path)
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    if items.count > 100 {
                        Text("\(L10n.t("… và "))\(items.count - 100)\(L10n.t(" mục nữa"))")
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                }
            }
            .font(XFinderTokens.Font.caption)
            .padding(.leading, 20)
        }
    }

    private func summaryLine(_ r: JunkCleanup.Report) -> String {
        var s = "\(L10n.t("Đã xem "))\(r.scannedEntries.formatted())\(L10n.t(" mục"))"
        if r.skippedPackages > 0 { s += " · \(r.skippedPackages)\(L10n.t(" gói ứng dụng không mở vào"))" }
        if r.skippedCloud > 0 { s += " · \(r.skippedCloud)\(L10n.t(" mục iCloud chưa tải bị bỏ qua"))" }
        return s
    }

    // MARK: Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("Chọn")
        if panel.runModal() == .OK, let url = panel.url { choose(url) }
    }

    private func useFinderSelection() {
        Task { @MainActor in
            switch await FinderSelection.read() {
            case .success(let urls):
                if let dir = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }) {
                    choose(dir)
                } else {
                    outcome = L10n.t("Hãy chọn một thư mục trong Finder rồi bấm lại.")
                    outcomeIsError = true
                }
            case .failure(let message):
                outcome = message
                outcomeIsError = true
            }
        }
    }

    private func choose(_ url: URL) {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        guard isDir else {
            outcome = L10n.t("Đó không phải thư mục.")
            outcomeIsError = true
            return
        }
        folder = url
        startScan()
    }

    private func startScan() {
        guard let root = folder else { return }
        scanHandle?.cancel()
        report = nil
        outcome = nil
        excluded = []
        let handle = Task.detached(priority: .userInitiated) {
            JunkCleanup.scan(root, isCancelled: { Task.isCancelled })
        }
        scanHandle = handle
        Task { @MainActor in
            let r = await handle.value
            guard scanHandle == handle else { return }   // a newer scan replaced this one
            report = r
            scanHandle = nil
        }
    }

    private func moveToTrash() {
        let items = chosen
        guard !items.isEmpty else { return }
        working = true
        Task { @MainActor in
            let out = await Task.detached(priority: .userInitiated) { JunkCleanup.moveToTrash(items) }.value
            working = false
            ActionHistoryStore.shared.recordTrash(urls: out.trashed)
            var msg = "\(L10n.t("Đã chuyển "))\(out.trashed.count)\(L10n.t(" mục vào Thùng rác — mở Thùng rác để khôi phục nếu cần."))"
            if out.changed > 0 { msg += " \(out.changed)\(L10n.t(" mục đã đổi sau khi quét nên được giữ nguyên.")) " }
            if !out.failed.isEmpty { msg += " \(out.failed.count)\(L10n.t(" mục không chuyển được: "))\(out.failed.prefix(3).joined(separator: "; "))" }
            startScan()
            outcome = msg
            outcomeIsError = !out.failed.isEmpty
        }
    }
}
