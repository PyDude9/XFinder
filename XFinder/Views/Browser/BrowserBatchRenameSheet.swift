import SwiftUI

/// XF-T37 L2 — the browser's batch rename: Finder's three modes (Replace Text / Add Text / Format) plus FileOctopus's
/// "Include extension", a preview row per item (old name → new name → status), and ONE error blocks the whole batch.
/// Disk facts are read once (on appear and after a run), never in `body`; the rename runs in two phases off the main
/// thread (`BatchRenameRules.execute`) and lands as one ⌘Z step in the browser's undo journal.
struct BrowserBatchRenameSheet: View {
    let sources: [String]
    let model: BrowserWindowModel

    @State private var options = BatchRenameRules.Options()
    @State private var items: [BatchRenameRules.Item] = []
    @State private var siblings: [String: Set<String>] = [:]
    @State private var isLoading = true
    @State private var isRunning = false
    @State private var outcome: String?
    @Environment(\.dismiss) private var dismiss

    private var plan: BatchRenameRules.Plan {
        BatchRenameRules.plan(items: items, options: options, siblings: { siblings[$0] }, calendar: .current,
                              dateConnector: L10n.t(" lúc "))
    }

    var body: some View {
        let plan = plan
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            Text("\(L10n.t("Đổi tên "))\(sources.count)\(L10n.t(" mục"))")
                .font(XFinderTokens.Font.sectionTitle)

            modeControls

            previewTable(plan)

            Text(summary(plan))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(plan.errorCount > 0 ? .red : .secondary)

            if let outcome {
                Text(outcome)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button(L10n.t("Huỷ")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t("Đổi tên")) { apply(plan) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!plan.canRename || isRunning || isLoading)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 620, height: 520)
        .onAppear {
            if options.customName == BatchRenameRules.Options().customName { options.customName = L10n.t("Tệp ") }
            loadFacts()
        }
    }

    // MARK: - Controls

    private var modeControls: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Picker(L10n.t("Kiểu"), selection: $options.mode) {
                Text(L10n.t("Thay chữ")).tag(BatchRenameRules.Mode.replaceText)
                Text(L10n.t("Thêm chữ")).tag(BatchRenameRules.Mode.addText)
                Text(L10n.t("Định dạng")).tag(BatchRenameRules.Mode.format)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            switch options.mode {
            case .replaceText:
                HStack {
                    TextField(L10n.t("Tìm"), text: $options.find).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                    TextField(L10n.t("Thay bằng"), text: $options.replaceWith).textFieldStyle(.roundedBorder)
                }
            case .addText:
                HStack {
                    TextField(L10n.t("Chữ thêm vào"), text: $options.addText).textFieldStyle(.roundedBorder)
                    positionPicker($options.addPosition)
                }
            case .format:
                HStack {
                    Picker(L10n.t("Kiểu tên"), selection: $options.formatStyle) {
                        Text(L10n.t("Tên và chỉ số")).tag(BatchRenameRules.FormatStyle.nameAndIndex)
                        Text(L10n.t("Tên và bộ đếm")).tag(BatchRenameRules.FormatStyle.nameAndCounter)
                        Text(L10n.t("Tên và ngày")).tag(BatchRenameRules.FormatStyle.nameAndDate)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    positionPicker($options.formatPosition)
                }
                HStack {
                    TextField(L10n.t("Tên tuỳ chỉnh"), text: $options.customName).textFieldStyle(.roundedBorder)
                    if options.formatStyle != .nameAndDate {
                        Stepper("\(L10n.t("Bắt đầu từ "))\(options.startNumber)", value: $options.startNumber, in: 0...99_999)
                            .fixedSize()
                    }
                }
            }

            if options.mode != .format {
                Toggle(L10n.t("Gồm cả đuôi tệp"), isOn: $options.includeExtension)
            }
        }
        .font(XFinderTokens.Font.rowValue)
    }

    private func positionPicker(_ selection: Binding<BatchRenameRules.Position>) -> some View {
        Picker(L10n.t("Đặt ở"), selection: selection) {
            Text(L10n.t("Sau tên")).tag(BatchRenameRules.Position.after)
            Text(L10n.t("Trước tên")).tag(BatchRenameRules.Position.before)
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    // MARK: - Preview

    private func previewTable(_ plan: BatchRenameRules.Plan) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(plan.rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.oldName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundColor(.secondary)
                        Text(row.newName)
                            .foregroundColor(row.issues.isEmpty ? .primary : .red)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Text(status(row))
                            .foregroundColor(row.issues.isEmpty ? .secondary : .red)
                            .lineLimit(2)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    .font(XFinderTokens.Font.caption)
                    .padding(.vertical, 4)
                    SettingsDivider()
                }
            }
        }
        .frame(maxHeight: .infinity)
        .overlay {
            if isLoading { ProgressView().controlSize(.small) }
        }
    }

    private func status(_ row: BatchRenameRules.Row) -> String {
        if !row.issues.isEmpty { return row.issues.map { L10n.t($0.key) }.joined(separator: " ") }
        if row.isUnchanged { return L10n.t("Không đổi") }
        if row.notes.isEmpty { return L10n.t("Sẵn sàng") }
        return row.notes.map { note in
            note.detail.isEmpty ? L10n.t(note.key) : "\(L10n.t(note.key)) \(note.detail)"
        }.joined(separator: " ")
    }

    private func summary(_ plan: BatchRenameRules.Plan) -> String {
        var text = "\(plan.renameCount)\(L10n.t(" mục sẽ được đổi tên."))"
        if plan.errorCount > 0 {
            text += " \(plan.errorCount)\(L10n.t(" mục có lỗi — sửa hết mới đổi được."))"
        }
        return text
    }

    // MARK: - Disk

    /// Reads every fact the plan needs, once, off the main thread: existence, folder-vs-file (a package counts as a
    /// file — "MyApp.app" has an extension), modification date, the user-immutable flag, whether the parent is
    /// writable, and each parent's names straight from `readdir`.
    private func loadFacts() {
        isLoading = true
        let paths = sources
        Task { @MainActor in
            let facts = await Task.detached(priority: .userInitiated) { Self.readFacts(paths) }.value
            items = facts.items
            siblings = facts.siblings
            isLoading = false
        }
    }

    nonisolated private static func readFacts(_ paths: [String]) -> (items: [BatchRenameRules.Item], siblings: [String: Set<String>]) {
        var loaded: [BatchRenameRules.Item] = []
        var names: [String: Set<String>] = [:]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey,
                                                           .isUserImmutableKey])
            var info = stat()
            let exists = lstat(path, &info) == 0
            let parent = (path as NSString).deletingLastPathComponent
            if names[parent] == nil { names[parent] = BatchRenameRules.directoryNames(parent) ?? [] }
            loaded.append(BatchRenameRules.Item(
                path: path,
                isFolder: (values?.isDirectory ?? false) && !(values?.isPackage ?? false),
                modified: values?.contentModificationDate ?? Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)),
                exists: exists,
                isLocked: values?.isUserImmutable ?? false,
                parentWritable: access(parent, W_OK) == 0
            ))
        }
        return (loaded, names)
    }

    private func apply(_ plan: BatchRenameRules.Plan) {
        guard plan.canRename else { return }
        let pairs = plan.pairs
        isRunning = true
        outcome = nil
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { BatchRenameRules.execute(pairs) }.value
            finish(result, pairs: pairs)
        }
    }

    private func finish(_ result: BatchRenameRules.Outcome, pairs: [(from: String, to: String)]) {
        isRunning = false
        guard result.succeeded else {
            let failedName = result.failedPath.map { ($0 as NSString).lastPathComponent } ?? ""
            let reason = result.failedErrno.map { String(cString: strerror($0)) } ?? ""
            var text = "\(L10n.t("Không đổi tên được: "))\(failedName) (\(reason))."
            if result.stranded.isEmpty {
                text += " \(L10n.t("Mọi mục đã trở về tên cũ."))"
            } else {
                let names = result.stranded.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                text += " \(result.stranded.count)\(L10n.t(" mục chưa trả về được tên cũ: "))\(names)"
            }
            outcome = text
            loadFacts()
            return
        }
        FileOperationQueue.shared.recordRenames(pairs)
        ActionHistoryStore.shared.recordRenames(pairs: pairs.map { (old: URL(fileURLWithPath: $0.from), new: URL(fileURLWithPath: $0.to)) })
        model.active.selection = Set(pairs.map { $0.to })
        model.active.reload()
        dismiss()
    }
}
