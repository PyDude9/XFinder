import SwiftUI
import AppKit

/// Nén & Giải nén — real implementation backed by the system `ditto` (ZIP)
/// and `tar` (TAR.GZ) tools via Foundation Process. No third-party deps.
struct CompressDetailView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case compress, extract
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .compress: return L10n.t("Nén")
            case .extract: return L10n.t("Giải nén")
            }
        }
    }

    enum ArchiveFormat: String, CaseIterable, Identifiable {
        case zip, tarGz
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .zip: return "ZIP (.zip)"
            case .tarGz: return "TAR.GZ (.tar.gz)"
            }
        }
        var fileExtension: String {
            switch self {
            case .zip: return "zip"
            case .tarGz: return "tar.gz"
            }
        }
    }

    enum CompressionLevel: Int, CaseIterable, Identifiable {
        case fast = 1, normal = 6, max = 9
        var id: Int { rawValue }
        var titleVI: String {
            switch self {
            case .fast: return L10n.t("Nhanh")
            case .normal: return L10n.t("Thường")
            case .max: return L10n.t("Tối đa")
            }
        }
    }

    @State private var mode: Mode = .compress
    @State private var sources: [URL] = []
    @State private var outputFolder: URL? = nil
    @State private var extractionDestination: ExtractionDestination = .newFolderBesideArchive
    @State private var conflictPolicy: ConflictPolicy = .keepBoth
    @State private var format: ArchiveFormat = .zip
    @State private var archiveName: String = "Archive"
    @State private var password = ""
    @State private var level = 6
    @State private var resultURL: URL?
    @State private var isRunning = false
    @State private var log: [String] = []

    enum ExtractionDestination: String, CaseIterable, Identifiable {
        case newFolderBesideArchive, sameFolder, downloads, custom
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .newFolderBesideArchive: return L10n.t("Thư mục mới cạnh file nén")
            case .sameFolder: return L10n.t("Cùng thư mục với file nén")
            case .downloads: return L10n.t("Tải về")
            case .custom: return L10n.t("Thư mục tùy chọn")
            }
        }
    }

    enum ConflictPolicy: String, CaseIterable, Identifiable {
        case keepBoth, ask, merge
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .keepBoth: return L10n.t("Giữ cả hai")
            case .ask: return L10n.t("Hỏi")
            case .merge: return L10n.t("Gộp thư mục")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                headerSection

                Picker(L10n.t("Chế độ"), selection: $mode) {
                    Text(Mode.compress.titleVI).tag(Mode.compress)
                    Text(Mode.extract.titleVI).tag(Mode.extract)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, XFinderTokens.Space.page)
                .onChange(of: mode) { sources = [] }

                SettingsSection(
                    title: mode == .compress ? L10n.t("Tập tin / thư mục cần nén") : L10n.t("Tập tin nén cần giải"),
                    footer: sources.isEmpty
                        ? L10n.t("Chưa chọn gì")
                        : "\(sources.count)\(L10n.t(" mục đã chọn"))"
                ) {
                    Button(L10n.t("Chọn…")) { pickSources() }
                        .settingsRow()
                    if !sources.isEmpty {
                        ForEach(sources.prefix(8), id: \.self) { url in
                            SettingsDivider()
                            HStack {
                                Image(systemName: mode == .compress ? "doc.fill" : "archivebox.fill")
                                    .foregroundColor(.secondary)
                                Text(url.lastPathComponent)
                                    .font(XFinderTokens.Font.rowValue)
                                    .fileNameRowSafe()
                                Spacer()
                                Button {
                                    sources.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .settingsRow()
                        }
                        if sources.count > 8 {
                            SettingsDivider()
                            Text("\(L10n.t("…và "))\(sources.count - 8)\(L10n.t(" mục nữa"))")
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                                .settingsRow()
                        }
                        SettingsDivider()
                        Button(L10n.t("Xóa hết")) { sources = [] }
                            .font(XFinderTokens.Font.rowValue)
                            .foregroundColor(.red)
                            .settingsRow()
                    }
                }

                if mode == .compress {
                    SettingsSection(title: L10n.t("Định dạng & tên")) {
                        Picker(L10n.t("Định dạng"), selection: $format) {
                            Text(ArchiveFormat.zip.titleVI).tag(ArchiveFormat.zip)
                            Text(ArchiveFormat.tarGz.titleVI).tag(ArchiveFormat.tarGz)
                        }
                        .pickerStyle(.segmented)
                        .settingsRow()
                        SettingsDivider()
                        HStack {
                            Text(L10n.t("Tên tập tin:")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            TextField("Archive", text: $archiveName)
                                .textFieldStyle(.roundedBorder)
                                .font(XFinderTokens.Font.rowValue)
                            Text(".\(format.fileExtension)")
                                .font(XFinderTokens.Font.rowValue)
                                .foregroundColor(.secondary)
                        }
                        .settingsRow()
                        if format == .zip {
                            SettingsDivider()
                            HStack {
                                Text(L10n.t("Mật khẩu (tuỳ chọn):")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                                SecureField(L10n.t("để trống nếu không khoá"), text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .font(XFinderTokens.Font.rowValue)
                            }
                            .settingsRow()
                            if !password.isEmpty {
                                SettingsDivider()
                                InlineNote(text: L10n.t("Mật khẩu dùng mã hoá ZIP truyền thống (ZipCrypto): đủ chặn người xem tình cờ, không phải mã hoá mạnh. Mật khẩu không nằm trong dòng lệnh và XFinder không lưu nó."))
                                    .settingsRow()
                            }
                            SettingsDivider()
                            HStack {
                                Text(L10n.t("Mức nén:")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                                Picker("", selection: $level) {
                                    Text(CompressionLevel.fast.titleVI).tag(CompressionLevel.fast.rawValue)
                                    Text(CompressionLevel.normal.titleVI).tag(CompressionLevel.normal.rawValue)
                                    Text(CompressionLevel.max.titleVI).tag(CompressionLevel.max.rawValue)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 240)
                            }
                            .settingsRow()
                        }
                    }
                }

                SettingsSection(title: L10n.t("Giải nén vào")) {
                    PickerRow(title: L10n.t("Giải nén vào"), selection: $extractionDestination, width: 220) {
                        ForEach(ExtractionDestination.allCases) { d in Text(d.titleVI).tag(d) }
                    }
                    .settingsRow()
                    if extractionDestination == .custom {
                        SettingsDivider()
                        HStack {
                            Button(L10n.t("Chọn thư mục đích…")) { pickOutputFolder() }
                            if let f = outputFolder {
                                Text(f.lastPathComponent)
                                    .font(XFinderTokens.Font.caption)
                                    .foregroundColor(.secondary)
                                    .fileNameRowSafe()
                            }
                            if outputFolder != nil {
                                Button(L10n.t("Mặc định")) { outputFolder = nil; extractionDestination = .newFolderBesideArchive }
                                    .font(XFinderTokens.Font.rowValue)
                            }
                        }
                        .settingsRow()
                    }
                }

                SettingsSection(title: L10n.t("Khi tên đã tồn tại")) {
                    PickerRow(title: L10n.t("Khi tên đã tồn tại"), selection: $conflictPolicy, width: 180) {
                        ForEach(ConflictPolicy.allCases) { p in Text(p.titleVI).tag(p) }
                    }
                    .settingsRow()
                    SettingsDivider()
                    InlineNote(text: conflictPolicy == .keepBoth ? L10n.t("Giữ cả hai lưu một bản sao riêng (\"Report 2\").")
                         : conflictPolicy == .merge ? L10n.t("Khi giải nén: gộp vào thư mục có sẵn, thay file trùng tên. Nếu giải nén lỗi, thư mục đích không bị đụng tới. Khi nén: tệp nén cũ không bao giờ bị ghi thêm, bản mới được giữ cả hai.")
                         : L10n.t("Hiện hộp thoại trước khi ghi đè: giữ cả hai, thay thế hoặc huỷ. Thay thế đưa bản cũ vào Thùng rác."))
                        .settingsRow()
                }

                if mode == .compress {
                    SettingsSection(title: L10n.t("Mặc định giải nén")) {
                        LabeledLine(label: L10n.t("Bộ máy nén và giải nén"), value: L10n.t("ditto, zip, tar có sẵn của macOS"))
                            .settingsRow()
                        SettingsDivider()
                        InlineNote(text: L10n.t("Dùng công cụ có sẵn của macOS: ditto cho ZIP một mục (giữ metadata của Mac), zip cho nhiều mục hoặc có mật khẩu, tar cho TAR.GZ. Không cần cài thêm gì. Chỉ ghi đè khi bạn chọn Gộp hoặc Thay thế."))
                            .settingsRow()
                    }

                    SettingsSection(title: L10n.t("Tách tác vụ nén và giải nén hoạt động")) {
                        InlineNote(text: L10n.t("Tạo ZIP hoặc TAR.GZ từ nhiều mục ở nhiều thư mục khác nhau; giải nén ZIP, TAR, TAR.GZ, TAR.BZ2. Tệp nén được đọc lại sau khi tạo để chắc không thiếu mục nào."))
                            .settingsRow()
                    }
                }

                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if isRunning { ProgressView().scaleEffect(0.7) }
                        Text(isRunning ? L10n.t("Đang xử lý…") : (mode == .compress ? L10n.t("Nén ngay") : L10n.t("Giải nén ngay")))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sources.isEmpty || isRunning)
                .padding(.horizontal, XFinderTokens.Space.page)

                if let resultURL {
                    SettingsSection(title: L10n.t("Việc tiếp theo")) {
                        HStack {
                            Menu {
                                if mode == .compress {
                                    Button(L10n.t("Mở thư mục chứa")) { NSWorkspace.shared.open(resultURL.deletingLastPathComponent()) }
                                    Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
                                } else {
                                    Button(L10n.t("Mở thư mục đã giải")) { NSWorkspace.shared.open(resultURL) }
                                    Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
                                    Button(L10n.t("Xóa file nén gốc"), role: .destructive) {
                                        for s in sources {
                                            try? FileManager.default.trashItem(at: s, resultingItemURL: nil)
                                        }
                                        sources = []
                                        self.resultURL = nil
                                    }
                                }
                                Button(L10n.t("Chép đường dẫn")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(resultURL.path, forType: .string)
                                }
                            } label: {
                                Label(mode == .compress ? L10n.t("Đã nén xong — tuỳ chọn…") : L10n.t("Đã giải xong — tuỳ chọn…"),
                                      systemImage: "ellipsis.circle")
                            }
                            .fixedSize()
                        }
                        .settingsRow()
                    }
                }

                if !log.isEmpty {
                    SettingsSection(title: L10n.t("Kết quả")) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(log.indices.reversed().prefix(10), id: \.self) { i in
                                Text(log[i])
                                    .font(XFinderTokens.Font.mono)
                                    .foregroundColor(log[i].hasPrefix(L10n.t("Lỗi")) || log[i].hasPrefix(L10n.t("Thất bại")) ? .red : .primary)
                                    .lineLimit(3)
                            }
                        }
                        .settingsRow()
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    // MARK: - Pickers

    private func pickSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = mode == .compress
        panel.allowsMultipleSelection = true
        if mode == .extract {
            panel.allowedFileTypes = ["zip", "gz", "bz2", "tar"]
        }
        if panel.runModal() == .OK { sources = panel.urls }
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { outputFolder = panel.url }
    }

    // MARK: - Run

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        if mode == .compress {
            await compress()
        } else {
            await extract()
        }
    }

    private var headerSection: some View {
        PageHeader(title: L10n.t("Nén & Giải nén"),
                   subtitle: L10n.t("Nén và giải nén file từ Finder."))
    }

    private func resolvedDestDir(for src: URL) -> URL {
        switch extractionDestination {
        case .newFolderBesideArchive, .sameFolder:
            return src.deletingLastPathComponent()
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? src.deletingLastPathComponent()
        case .custom:
            return outputFolder ?? src.deletingLastPathComponent()
        }
    }

    private var enginePolicy: ArchiveEngine.ConflictPolicy {
        switch conflictPolicy {
        case .keepBoth: return .keepBoth
        case .ask: return .ask
        case .merge: return .merge
        }
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private enum ConflictChoice { case keepBoth, replace, cancel }

    /// The real "Hỏi" (Ask). The old branch recursed into itself forever the moment a name existed.
    private func askConflict(names: [String], replaceTitle: String) -> ConflictChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(names.count)\(L10n.t(" mục đã tồn tại ở nơi đích."))"
        alert.informativeText = names.prefix(6).joined(separator: "\n") + (names.count > 6 ? "\n…" : "")
        alert.addButton(withTitle: L10n.t("Giữ cả hai"))
        alert.addButton(withTitle: replaceTitle)
        alert.addButton(withTitle: L10n.t("Hủy"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        default: return .cancel
        }
    }

    private func failureLine(_ f: ArchiveRunner.Failure) -> String {
        if let d = f.detail, !d.isEmpty { return "\(L10n.t(f.messageKey)) \(d)" }
        return L10n.t(f.messageKey)
    }

    private var engineFormat: ArchiveEngine.Format { format == .zip ? .zip : .tarGz }

    private func compress() async {
        guard let first = sources.first else { return }
        let base = first.deletingLastPathComponent()
            .appendingPathComponent("\(ArchiveEngine.archiveName(archiveName)).\(engineFormat.fileExtension)")
        // "Gộp" only means something for extraction; an existing archive is never appended to.
        let policy: ArchiveEngine.ConflictPolicy = enginePolicy == .merge ? .keepBoth : enginePolicy
        var output: URL
        switch ArchiveEngine.destination(base: base, policy: policy, exists: Self.exists) {
        case .write(let url): output = url
        case .needsDecision(let existing):
            switch askConflict(names: [existing.lastPathComponent], replaceTitle: L10n.t("Thay thế")) {
            case .cancel: appendLog(L10n.t("Đã hủy.")); return
            case .replace:
                // Replace = the old archive goes to the Trash first. Never a hard delete.
                do { try FileManager.default.trashItem(at: existing, resultingItemURL: nil) }
                catch { appendLog(L10n.t("Không đưa được tệp cũ vào Thùng rác.")); return }
                output = existing
            case .keepBoth:
                guard case .write(let url) = ArchiveEngine.destination(base: base, policy: .keepBoth, exists: Self.exists) else { return }
                output = url
            }
        }
        let result = await ArchiveRunner.compress(sources: sources, format: engineFormat, level: level,
                                                  password: password.isEmpty ? nil : password, output: output)
        switch result {
        case .success(let url):
            appendLog("\(L10n.t("Đã nén → "))\(url.lastPathComponent)")
            resultURL = url
            ActionHistoryStore.shared.record(
                kind: "compress",
                summary: "\(L10n.t("Nén "))\(sources.count)\(L10n.t(" mục → "))\(url.lastPathComponent)",
                detail: url.path,
                reversible: false)
        case .failure(let f):
            DiagnosticsLog.record("archive", "compress." + f.diagnosticCode)
            appendLog("\(L10n.t("Thất bại khi nén "))\(sources.count)\(L10n.t(" mục"))")
            appendLog(failureLine(f))
        }
    }

    private func extract() async {
        var okCount = 0
        for src in sources {
            var dest = resolvedDestDir(for: src)
            var policy = enginePolicy
            if extractionDestination == .newFolderBesideArchive {
                let folder = dest.appendingPathComponent(ArchiveEngine.folderName(forArchive: src))
                switch ArchiveEngine.destination(base: folder, policy: policy, exists: Self.exists) {
                case .write(let url): dest = url
                case .needsDecision(let existing):
                    switch askConflict(names: [existing.lastPathComponent], replaceTitle: L10n.t("Gộp")) {
                    case .cancel: appendLog("\(L10n.t("Bỏ qua "))\(src.lastPathComponent)"); continue
                    case .replace: dest = existing; policy = .merge
                    case .keepBoth:
                        guard case .write(let url) = ArchiveEngine.destination(base: folder, policy: .keepBoth, exists: Self.exists) else { continue }
                        dest = url; policy = .keepBoth
                    }
                }
            }
            // Extract into a private staging folder first: ditto and tar overwrite silently.
            let staged = await ArchiveRunner.extractToStaging(archive: src, near: dest)
            guard case .success(let batch) = staged else {
                if case .failure(let f) = staged { DiagnosticsLog.record("archive", "extract." + f.diagnosticCode); appendLog("\(L10n.t("Lỗi: không giải được "))\(src.lastPathComponent)"); appendLog(failureLine(f)) }
                continue
            }
            let clashes = ArchiveRunner.conflicts(batch, in: dest)
            if policy == .ask {
                if clashes.isEmpty { policy = .keepBoth }
                else {
                    switch askConflict(names: clashes, replaceTitle: L10n.t("Gộp")) {
                    case .cancel: ArchiveRunner.discard(batch); appendLog("\(L10n.t("Bỏ qua "))\(src.lastPathComponent)"); continue
                    case .replace: policy = .merge
                    case .keepBoth: policy = .keepBoth
                    }
                }
            }
            switch await ArchiveRunner.place(batch, into: dest, policy: policy) {
            case .success(let placed):
                okCount += 1
                resultURL = placed.count == 1 ? placed[0] : dest
            case .failure(let f):
                appendLog("\(L10n.t("Lỗi: không giải được "))\(src.lastPathComponent)")
                appendLog(failureLine(f))
            }
        }
        appendLog("\(L10n.t("Đã giải "))\(okCount)/\(sources.count)\(L10n.t(" tập tin"))")
        if okCount > 0 {
            ActionHistoryStore.shared.record(
                kind: "extract",
                summary: "\(L10n.t("Giải "))\(okCount)/\(sources.count)\(L10n.t(" tập tin"))",
                reversible: false)
        }
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }
}
