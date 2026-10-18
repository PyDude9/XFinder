import SwiftUI
import AppKit

/// Thao tác Finder — run XFinder's file tools on the files currently selected
/// in Finder, and reach the system panes that install them as Quick Actions.
///
/// The selection is read via a one-line AppleScript against Finder (needs
/// Automation for Finder the first time — the page says so and offers the
/// pane). Copy/Move/Trash/Compress then run on that selection through the same
/// engines the tool pages use, so behaviour is identical everywhere.
///
/// Honesty note: macOS has **no** public API to add items to Finder's own
/// context menu from a plain app — that requires a Finder Sync Extension
/// target. The page links to the Extensions pane instead of faking it.
struct FinderActionsDetailView: View {
    // 13 nhóm — MFinder screenshot; mỗi toggle là một @AppStorage bool, default true.

    @State private var selection: [URL] = []
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Thao tác Finder"),
                           subtitle: L10n.t("Thao tác trên các mục đang chọn trong Finder — từ trang này hoặc từ hai mục XFinder trong menu chuột phải."))

                selectionSection

                quickActionsSection

                if !imageSelection.isEmpty {
                    imageSection
                }

                contextMenuSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    // MARK: - Menu config

    // MARK: - Finder selection

    private var selectionSection: some View {
        SettingsSection(title: L10n.t("Tệp đang chọn trong Finder"),
                        footer: selection.isEmpty
                            ? L10n.t("Chọn vài tệp trong Finder rồi bấm Đọc lựa chọn.")
                            : "\(selection.count)\(L10n.t(" mục"))") {
            HStack(spacing: 8) {
                Button(L10n.t("Đọc lựa chọn")) { readSelection() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(busy)
                if !selection.isEmpty {
                    Button(L10n.t("Bỏ chọn")) { selection = []; status = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .settingsRow()

            if !selection.isEmpty {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(selection.prefix(8), id: \.self) { url in
                        Text(url.lastPathComponent)
                            .font(XFinderTokens.Font.rowValue)
                            .fileNameRowSafe()
                    }
                    if selection.count > 8 {
                        Text("\(L10n.t("… và "))\(selection.count - 8)\(L10n.t(" mục nữa"))")
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                }
                .settingsRow()
            }
        }
    }

    // MARK: - Quick actions

    private var quickActionsSection: some View {
        SettingsSection(title: L10n.t("Thao tác nhanh"),
                        footer: L10n.t("Áp dụng cho các mục vừa đọc ở trên.")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 8)], spacing: 8) {
                actionButton(L10n.t("Sao chép đường dẫn"), "doc.on.doc") { copyPaths() }
                actionButton(L10n.t("Nén thành ZIP"), "archivebox") { compress() }
                actionButton(L10n.t("Đổi tên hàng loạt…"), "textformat.abc") {
                    AppState.shared.navigate(to: .batchRename)
                }
                actionButton(L10n.t("Thêm vào Khay thả"), "tray.and.arrow.down") { addToTray() }
                actionButton(L10n.t("Chuyển vào Thùng rác"), "trash", destructive: true) { trash() }
                actionButton(L10n.t("Hiện trong Finder"), "folder") { reveal() }
            }
            .settingsRow()

            if let status {
                SettingsDivider()
                Text(status)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .settingsRow()
            }
        }
    }

    // MARK: - Context menu

    private var contextMenuSection: some View {
        SettingsSection(title: L10n.t("Menu chuột phải trong Finder"),
                        footer: L10n.t("Thêm mục vào menu ngữ cảnh của Finder.")) {
            InlineNote(text: L10n.t("macOS không có API công khai cho phép một ứng dụng thường thêm mục vào menu chuột phải của Finder. XFinder đi đường Apple hỗ trợ: một Finder Sync Extension với hai mục — Thêm vào Khay thả và Hiện trong Finder. Muốn thêm thao tác khác, dùng Quick Action (Shortcuts/Automator)."))
                .settingsRow()
            SettingsDivider()
            HStack(spacing: 8) {
                Button(L10n.t("Mở Tiện ích mở rộng…")) { openExtensionsPane() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(L10n.t("Mở Automator")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Automator.app"))
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .settingsRow()
        }
    }

    // MARK: Images (B2c) — ImageRunner on the image files in the selection

    private var imageSelection: [URL] { selection.filter(ImageEngine.isImage) }

    /// Only formats this Mac can encode (measured: no WebP encoder on macOS 27).
    private var imageTargets: [ImageEngine.Target] { ImageEngine.availableTargets(encodable: ImageRunner.encodableTypes) }

    private var imageSection: some View {
        SettingsSection(title: L10n.t("Ảnh"),
                        footer: "\(imageSelection.count)\(L10n.t(" ảnh trong các mục đã chọn. Kết quả nằm cạnh ảnh gốc; ảnh gốc không bị đổi."))") {
            HStack(spacing: XFinderTokens.Space.inline) {
                Menu(L10n.t("Chuyển định dạng")) {
                    ForEach(imageTargets, id: \.self) { t in
                        Button(t.label) { runImages(.convert(t)) }
                    }
                }
                .fixedSize()
                Menu(L10n.t("Giảm kích thước")) {
                    ForEach(ImageEngine.resizePresets, id: \.self) { px in
                        Button("\(px) px") { runImages(.resize(maxPixels: px)) }
                    }
                }
                .fixedSize()
                Button(L10n.t("Tách nền")) { runImages(.removeBackground) }
                    .help(L10n.t("Dùng Vision trên máy, không gửi ảnh đi đâu. Lần đầu mất vài giây để nạp mô hình."))
            }
            .disabled(busy)
            .settingsRow()
        }
    }

    private func runImages(_ op: ImageEngine.Operation) {
        let files = imageSelection.filter { url in
            if case .convert(let t) = op { return !ImageEngine.isSameFormat(url, t) }
            return true
        }
        guard !files.isEmpty else { status = L10n.t("Các ảnh đã ở định dạng này."); return }
        busy = true
        status = L10n.t("Đang xử lý…")
        Task {
            let results: [Result<URL, ImageRunner.Failure>] = await Task.detached(priority: .userInitiated) {
                files.map { url in
                    switch op {
                    case .convert(let t): return ImageRunner.convert(url, to: t)
                    case .resize(let px): return ImageRunner.resize(url, maxPixels: px)
                    case .removeBackground: return ImageRunner.removeBackground(url)
                    }
                }
            }.value
            busy = false
            let made = results.compactMap { if case .success(let u) = $0 { return u } else { return nil } }
            let firstFailure = results.lazy.compactMap { r -> ImageRunner.Failure? in if case .failure(let f) = r { return f } else { return nil } }.first
            var line = "\(L10n.t("Đã tạo "))\(made.count)/\(files.count)\(L10n.t(" ảnh."))"
            if let f = firstFailure { line += " \(L10n.t(f.messageKey))\(f.detail)" }
            status = line
            if !made.isEmpty {
                ActionHistoryStore.shared.record(kind: "image", summary: line, detail: made.map(\.path).joined(separator: "\n"))
                NSWorkspace.shared.activateFileViewerSelecting(made)
            }
        }
    }

    private func actionButton(_ title: String, _ icon: String,
                              destructive: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(XFinderTokens.Font.rowValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(destructive ? .red : nil)
        .disabled(selection.isEmpty || busy)
    }

    // MARK: Finder selection

    private func readSelection() {
        busy = true
        status = nil
        Task {
            let result = await FinderSelection.read()
            busy = false
            switch result {
            case .success(let urls):
                selection = urls
                status = urls.isEmpty ? L10n.t("Finder không có mục nào đang chọn.") : nil
            case .failure(let message):
                status = message
            }
        }
    }

    // MARK: Actions

    private func copyPaths() {
        let text = selection.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "\(L10n.t("Đã sao chép "))\(selection.count)\(L10n.t(" đường dẫn."))"
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(selection)
    }

    private func trash() {
        var moved = 0
        for url in selection {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                moved += 1
            } catch {
                status = "\(L10n.t("Không xóa được "))\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if moved > 0 {
            ActionHistoryStore.shared.recordTrash(urls: selection)
            status = "\(L10n.t("Đã chuyển "))\(moved)\(L10n.t(" mục vào Thùng rác."))"
            selection = []
        }
    }

    private func compress() {
        guard let first = selection.first else { return }
        busy = true
        let items = selection
        let base = first.deletingLastPathComponent()
            .appendingPathComponent("XFinder-\(Int(Date().timeIntervalSince1970)).zip")
        guard case .write(let output) = ArchiveEngine.destination(
            base: base, policy: .keepBoth, exists: { FileManager.default.fileExists(atPath: $0.path) }) else { busy = false; return }
        Task {
            // The shared runner: `ditto` alone refuses more than one source, which made this button
            // fail for every multi-item selection.
            let result = await ArchiveRunner.compress(sources: items, format: .zip, output: output)
            busy = false
            switch result {
            case .success(let url):
                status = "\(L10n.t("Đã nén thành "))\(url.lastPathComponent)."
                ActionHistoryStore.shared.record(
                    kind: "compress",
                    summary: "\(L10n.t("Nén "))\(items.count)\(L10n.t(" mục → "))\(url.lastPathComponent)")
            case .failure(let f):
                status = "\(L10n.t("Nén thất bại.")) \(L10n.t(f.messageKey)) \(f.detail ?? "")"
            }
        }
    }

    private func addToTray() {
        DropTrayStore.shared.add(urls: selection)
        status = "\(L10n.t("Đã thêm "))\(selection.count)\(L10n.t(" mục vào Khay thả."))"
    }

    private func openExtensionsPane() {
        WindowManager.openFinderExtensionsPane()
    }
}
