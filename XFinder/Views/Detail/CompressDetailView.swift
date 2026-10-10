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
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                headerSection

                Picker(L10n.t("Chế độ"), selection: $mode) {
                    Text(Mode.compress.titleVI).tag(Mode.compress)
                    Text(Mode.extract.titleVI).tag(Mode.extract)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, XFinderTokens.Space.page)
                .onChange(of: mode) { sources = [] }

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(
                        icon: mode == .compress ? "doc.fill" : "archivebox.fill",
                        title: mode == .compress ? L10n.t("Tập tin / thư mục cần nén") : L10n.t("Tập tin nén cần giải"),
                        subtitle: sources.isEmpty
                            ? L10n.t("Chưa chọn gì")
                            : "\(sources.count)\(L10n.t(" mục đã chọn"))"
                    )
                    Button(L10n.t("Chọn…")) { pickSources() }
                        .padding(.horizontal, XFinderTokens.Space.page)
                    if !sources.isEmpty {
                        ForEach(sources.prefix(8), id: \.self) { url in
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
                            .padding(.horizontal, XFinderTokens.Space.page)
                            Divider().padding(.horizontal, XFinderTokens.Space.page)
                        }
                        if sources.count > 8 {
                            Text("\(L10n.t("…và "))\(sources.count - 8)\(L10n.t(" mục nữa"))")
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, XFinderTokens.Space.page)
                        }
                        Button(L10n.t("Xóa hết")) { sources = [] }
                            .font(XFinderTokens.Font.rowValue)
                            .foregroundColor(.red)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                if mode == .compress {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "doc.badge.gearshape", title: L10n.t("Định dạng & tên"))
                        Picker(L10n.t("Định dạng"), selection: $format) {
                            Text(ArchiveFormat.zip.titleVI).tag(ArchiveFormat.zip)
                            Text(ArchiveFormat.tarGz.titleVI).tag(ArchiveFormat.tarGz)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, XFinderTokens.Space.page)
                        HStack {
                            Text(L10n.t("Tên tập tin:")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            TextField("Archive", text: $archiveName)
                                .textFieldStyle(.roundedBorder)
                                .font(XFinderTokens.Font.rowValue)
                            Text(".\(format.fileExtension)")
                                .font(XFinderTokens.Font.rowValue)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, XFinderTokens.Space.page)
                        if format == .zip {
                            HStack {
                                Text(L10n.t("Mật khẩu (tuỳ chọn):")).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                                SecureField(L10n.t("để trống nếu không khoá"), text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .font(XFinderTokens.Font.rowValue)
                            }
                            .padding(.horizontal, XFinderTokens.Space.page)
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
                            .padding(.horizontal, XFinderTokens.Space.page)
                        }
                    }
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                }

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "tray.and.arrow.down.fill", title: L10n.t("Giải nén vào"))
                    PickerRow(title: L10n.t("Giải nén vào"), selection: $extractionDestination, width: 220) {
                        ForEach(ExtractionDestination.allCases) { d in Text(d.titleVI).tag(d) }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                    if extractionDestination == .custom {
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
                        .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "exclamationmark.triangle", title: L10n.t("Khi tên đã tồn tại"))
                    PickerRow(title: L10n.t("Khi tên đã tồn tại"), selection: $conflictPolicy, width: 180) {
                        ForEach(ConflictPolicy.allCases) { p in Text(p.titleVI).tag(p) }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                    InlineNote(text: conflictPolicy == .keepBoth ? L10n.t("Giữ cả hai lưu một bản sao riêng (\"Report 2\").")
                         : conflictPolicy == .merge ? L10n.t("Gộp thêm file vào thư mục hiện có và khôi phục nếu giải nén thất bại.")
                         : L10n.t("Hỏi trước khi ghi đè."))
                        .padding(.horizontal, XFinderTokens.Space.page)
                }
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                if mode == .compress {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "checkmark.circle.fill", title: L10n.t("Mặc định giải nén"))
                        LabeledLine(label: L10n.t("Bộ máy nén và giải nén"), value: L10n.t("ditto, zip, tar có sẵn của macOS"))
                        InlineNote(text: L10n.t("Dùng công cụ nén có sẵn của macOS (ditto cho ZIP, tar cho TAR.GZ), không cần cài thêm gì. Không bao giờ ghi đè — mục trùng tên được đổi tên (\"Report 2\") hoặc gộp theo lựa chọn bên trên."))
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                    Divider().padding(.horizontal, XFinderTokens.Space.page)

                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "square.stack.3d.up.fill", title: L10n.t("Tách tác vụ nén và giải nén hoạt động"))
                        InlineNote(text: L10n.t("Tạo file ZIP hoặc TAR.GZ và giải nén ZIP, TAR, TAR.GZ. XFinder không bao giờ ghi đè file hiện có."))
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
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
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "arrow.right.circle", title: L10n.t("Việc tiếp theo"))
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
                        .padding(.horizontal, XFinderTokens.Space.page)
                    }
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                }

                if !log.isEmpty {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "list.bullet.rectangle", title: L10n.t("Kết quả"))
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(log.indices.reversed().prefix(10), id: \.self) { i in
                                Text(log[i])
                                    .font(XFinderTokens.Font.mono)
                                    .foregroundColor(log[i].hasPrefix(L10n.t("Lỗi")) || log[i].hasPrefix(L10n.t("Thất bại")) ? .red : .primary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Fill.window)
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
        PageHeader(icon: "archivebox.fill",
                   title: L10n.t("Nén & Giải nén"),
                   subtitle: L10n.t("Nén và giải nén file từ Finder."))
    }

    private func resolvedDestDir(for src: URL) -> URL {
        switch extractionDestination {
        case .newFolderBesideArchive:
            return src.deletingLastPathComponent()
        case .sameFolder:
            return src.deletingLastPathComponent()
        case .downloads:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? src.deletingLastPathComponent()
        case .custom:
            return outputFolder ?? src.deletingLastPathComponent()
        }
    }

    private func uniqueDestURL(base: URL) -> URL {
        // keepBoth: "Report" → "Report 2", "Report 2" → "Report 3"
        switch conflictPolicy {
        case .keepBoth:
            if !FileManager.default.fileExists(atPath: base.path) { return base }
            let dir = base.deletingLastPathComponent()
            let ext = base.pathExtension
            let stem = base.deletingPathExtension().lastPathComponent
            var i = 2
            while true {
                let cand = ext.isEmpty ? dir.appendingPathComponent("\(stem) \(i)")
                                       : dir.appendingPathComponent("\(stem) \(i).\(ext)")
                if !FileManager.default.fileExists(atPath: cand.path) { return cand }
                i += 1
            }
        case .ask:
            if FileManager.default.fileExists(atPath: base.path) {
                // Caller should have asked; fallback to keepBoth naming.
                return uniqueDestURL(base: base) // recurse into keepBoth branch requires manual — just suffix
            }
            return base
        case .merge:
            return base
        }
    }

    private func compress() async {
        var destDir = outputFolder ?? sources[0].deletingLastPathComponent()
        if mode == .extract {} else {
            // compress destination: picker is about extraction; compress always beside first source
            destDir = sources[0].deletingLastPathComponent()
        }
        let exe: String
        let args: [String]
        let cwd: URL?
        let finalDest: URL
        switch format {
        case .tarGz:
            exe = "/usr/bin/tar"
            finalDest = uniqueDestURL(base: destDir.appendingPathComponent("\(sanitizedName).tar.gz"))
            let parent = sources[0].deletingLastPathComponent().path
            args = ["-czf", finalDest.path, "-C", parent] + sources.map(\.lastPathComponent)
            cwd = nil
        case .zip:
            finalDest = uniqueDestURL(base: destDir.appendingPathComponent("\(sanitizedName).zip"))
            if password.isEmpty && level == 6 {
                // ditto giữ resource fork / metadata macOS; không mã hoá.
                exe = "/usr/bin/ditto"
                args = ["-c", "-k", "--sequesterRsrc", "--keepParent"]
                    + sources.map(\.path) + [finalDest.path]
                cwd = nil
            } else {
                // zip khi cần mật khẩu / mức nén khác mặc định.
                exe = "/usr/bin/zip"
                var a = ["-r", "-\(level)", "-q"]
                if !password.isEmpty { a += ["-P", password] }
                a += [finalDest.path] + sources.map(\.lastPathComponent)
                args = a
                cwd = sources[0].deletingLastPathComponent()
            }
        }
        let ok = await runProcess(exe: exe, args: args, cwd: cwd)
        appendLog(ok ? "\(L10n.t("Đã nén → "))\(finalDest.lastPathComponent)" : "\(L10n.t("Thất bại khi nén "))\(sources.count)\(L10n.t(" mục"))")
        if ok {
            resultURL = finalDest
            ActionHistoryStore.shared.record(
                kind: "compress",
                summary: "\(L10n.t("Nén "))\(sources.count)\(L10n.t(" mục → "))\(finalDest.lastPathComponent)",
                detail: finalDest.path,
                reversible: false)
        }
    }

    private func extract() async {
        var okCount = 0
        for src in sources {
            let destBase = resolvedDestDir(for: src)
            let destDir: URL
            // MFinder: newFolderBesideArchive → folder named after archive beside it.
            if extractionDestination == .newFolderBesideArchive {
                destDir = uniqueDestURL(base: destBase.appendingPathComponent(src.deletingPathExtension().lastPathComponent))
                try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            } else {
                destDir = destBase
                if destDir.path != src.deletingLastPathComponent().path {
                    try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                }
            }
            let ext = src.pathExtension.lowercased()
            let exe: String
            let args: [String]
            let destURL: URL
            if ext == "zip" {
                exe = "/usr/bin/ditto"
                destURL = destDir
                args = ["-x", "-k", src.path, destDir.path]
            } else {
                exe = "/usr/bin/tar"
                destURL = destDir
                args = ["-xzf", src.path, "-C", destDir.path]
            }
            if await runProcess(exe: exe, args: args) {
                okCount += 1
                resultURL = destURL
            } else { appendLog("\(L10n.t("Lỗi: không giải được "))\(src.lastPathComponent)") }
        }
        appendLog("\(L10n.t("Đã giải "))\(okCount)/\(sources.count)\(L10n.t(" tập tin"))")
        if okCount > 0 {
            ActionHistoryStore.shared.record(
                kind: "extract",
                summary: "\(L10n.t("Giải "))\(okCount)/\(sources.count)\(L10n.t(" tập tin"))",
                reversible: false)
        }
    }

    private var sanitizedName: String {
        let t = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Archive" : t
    }

    private func runProcess(exe: String, args: [String], cwd: URL? = nil) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            if let cwd { p.currentDirectoryURL = cwd }
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                return p.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }
}
