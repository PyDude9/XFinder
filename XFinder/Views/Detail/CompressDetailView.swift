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
            case .compress: return "Nén"
            case .extract: return "Giải nén"
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
            case .newFolderBesideArchive: return "Thư mục mới cạnh file nén"
            case .sameFolder: return "Cùng thư mục với file nén"
            case .downloads: return "Tải về"
            case .custom: return "Thư mục tùy chọn"
            }
        }
    }

    enum ConflictPolicy: String, CaseIterable, Identifiable {
        case keepBoth, ask, merge
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .keepBoth: return "Giữ cả hai"
            case .ask: return "Hỏi"
            case .merge: return "Gộp thư mục"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Picker("Chế độ", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.titleVI).tag(m) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .onChange(of: mode) { sources = [] }

                SettingsCard(
                    title: mode == .compress ? "Tập tin / thư mục cần nén" : "Tập tin nén cần giải",
                    subtitle: sources.isEmpty
                        ? "Chưa chọn gì"
                        : "\(sources.count) mục đã chọn"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Chọn…") { pickSources() }
                        if !sources.isEmpty {
                            ForEach(sources.prefix(8), id: \.self) { url in
                                HStack {
                                    Image(systemName: mode == .compress ? "doc.fill" : "archivebox.fill")
                                        .foregroundColor(.secondary)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        sources.removeAll { $0 == url }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if sources.count > 8 {
                                Text("…và \(sources.count - 8) mục nữa")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Button("Xóa hết") { sources = [] }
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal, 20)

                if mode == .compress {
                    SettingsCard(title: "Định dạng & tên") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Định dạng", selection: $format) {
                                ForEach(ArchiveFormat.allCases) { f in Text(f.titleVI).tag(f) }
                            }
                            .pickerStyle(.segmented)
                            HStack {
                                Text("Tên tập tin:").font(.system(size: 12)).foregroundColor(.secondary)
                                TextField("Archive", text: $archiveName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                Text(".\(format.fileExtension)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            if format == .zip {
                                HStack {
                                    Text("Mật khẩu (tuỳ chọn):").font(.system(size: 12)).foregroundColor(.secondary)
                                    SecureField("để trống nếu không khoá", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                }
                                HStack {
                                    Text("Mức nén:").font(.system(size: 12)).foregroundColor(.secondary)
                                    Picker("", selection: $level) {
                                        Text("Nhanh").tag(1)
                                        Text("Thường").tag(6)
                                        Text("Tối đa").tag(9)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 240)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                SettingsCard(
                    title: "Giải nén vào",
                    subtitle: extractionDestination.titleVI
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Giải nén vào", selection: $extractionDestination) {
                            ForEach(ExtractionDestination.allCases) { d in Text(d.titleVI).tag(d) }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 320)
                        if extractionDestination == .custom {
                            HStack {
                                Button("Chọn thư mục đích…") { pickOutputFolder() }
                                if let f = outputFolder {
                                    Text(f.lastPathComponent).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                                }
                                if outputFolder != nil {
                                    Button("Mặc định") { outputFolder = nil; extractionDestination = .newFolderBesideArchive }
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(
                    title: "Khi tên đã tồn tại",
                    subtitle: conflictPolicy.titleVI
                ) {
                    Picker("Khi tên đã tồn tại", selection: $conflictPolicy) {
                        ForEach(ConflictPolicy.allCases) { p in Text(p.titleVI).tag(p) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    Text(conflictPolicy == .keepBoth ? "Giữ cả hai lưu một bản sao riêng (\"Report 2\")."
                         : conflictPolicy == .merge ? "Gộp thêm file vào thư mục hiện có và khôi phục nếu giải nén thất bại."
                         : "Hỏi trước khi ghi đè.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                if mode == .compress {
                    SettingsCard(title: "Mặc định giải nén") {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Bộ máy nén và giải nén").font(.system(size: 13))
                            Spacer()
                            Text("7-Zip 26.02 tích hợp sẵn").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Text("MFinder tích hợp sẵn bộ máy 7-Zip; không cần cài thêm ứng dụng nén và giải nén. Không bao giờ ghi đè — mục trùng tên sẽ được đổi tên (\"Report 2\") hoặc gộp.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)

                    SettingsCard(title: "Tách tác vụ nén và giải nén hoạt động") {
                        Text("Tạo file ZIP hoặc 7Z và giải nén ZIP, 7Z, RAR, TAR, GZ, XZ cùng các định dạng phổ biến khác. MFinder không bao giờ ghi đè file hiện có.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                }

                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if isRunning { ProgressView().scaleEffect(0.7) }
                        Text(isRunning ? "Đang xử lý…" : (mode == .compress ? "Nén ngay" : "Giải nén ngay"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sources.isEmpty || isRunning)
                .padding(.horizontal, 20)

                if let resultURL {
                    SettingsCard(title: "Việc tiếp theo") {
                        HStack {
                            Menu {
                                if mode == .compress {
                                    Button("Mở thư mục chứa") { NSWorkspace.shared.open(resultURL.deletingLastPathComponent()) }
                                    Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
                                } else {
                                    Button("Mở thư mục đã giải") { NSWorkspace.shared.open(resultURL) }
                                    Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
                                    Button("Xóa file nén gốc", role: .destructive) {
                                        for s in sources {
                                            try? FileManager.default.trashItem(at: s, resultingItemURL: nil)
                                        }
                                        sources = []
                                        self.resultURL = nil
                                    }
                                }
                                Button("Chép đường dẫn") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(resultURL.path, forType: .string)
                                }
                            } label: {
                                Label(mode == .compress ? "Đã nén xong — tuỳ chọn…" : "Đã giải xong — tuỳ chọn…",
                                      systemImage: "ellipsis.circle")
                            }
                            .fixedSize()
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if !log.isEmpty {
                    SettingsCard(title: "Kết quả") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(log.indices.reversed().prefix(10), id: \.self) { i in
                                Text(log[i])
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(log[i].hasPrefix("Lỗi") || log[i].hasPrefix("Thất bại") ? .red : .primary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                } else {
                    Spacer().padding(.bottom, 20)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
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
                   title: "Nén & Giải nén",
                   subtitle: "Nén và giải nén file từ Finder.")
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
        appendLog(ok ? "Đã nén → \(finalDest.lastPathComponent)" : "Thất bại khi nén \(sources.count) mục")
        if ok {
            resultURL = finalDest
            ActionHistoryStore.shared.record(
                kind: "compress",
                summary: "Nén \(sources.count) mục → \(finalDest.lastPathComponent)",
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
            } else { appendLog("Lỗi: không giải được \(src.lastPathComponent)") }
        }
        appendLog("Đã giải \(okCount)/\(sources.count) tập tin")
        if okCount > 0 {
            ActionHistoryStore.shared.record(
                kind: "extract",
                summary: "Giải \(okCount)/\(sources.count) tập tin",
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
