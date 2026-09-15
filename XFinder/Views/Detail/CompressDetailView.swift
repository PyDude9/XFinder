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
    @State private var format: ArchiveFormat = .zip
    @State private var archiveName: String = "Archive"
    @State private var isRunning = false
    @State private var log: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nén & Giải nén")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

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
                        }
                    }
                    .padding(.horizontal, 20)
                }

                SettingsCard(
                    title: "Thư mục đích",
                    subtitle: outputFolder?.path ?? "Mặc định: cùng thư mục với tập tin đầu tiên"
                ) {
                    HStack {
                        Button("Chọn thư mục đích…") { pickOutputFolder() }
                        if outputFolder != nil {
                            Button("Mặc định") { outputFolder = nil }
                                .font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 20)

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

    private func compress() async {
        let destDir = outputFolder ?? sources[0].deletingLastPathComponent()
        let dest = destDir
            .appendingPathComponent(sanitizedName)
            .appendingPathExtension(format == .zip ? "zip" : "gz")
        // tar.gz needs the full double extension; appendingPathExtension("gz")
        // on "Archive.tar" — build it explicitly.
        let finalDest: URL = format == .zip
            ? dest
            : destDir.appendingPathComponent("\(sanitizedName).tar.gz")
        var args: [String]
        var exe: String
        switch format {
        case .zip:
            exe = "/usr/bin/ditto"
            args = ["-c", "-k", "--sequesterRsrc", "--keepParent"]
                + sources.map(\.path) + [finalDest.path]
        case .tarGz:
            exe = "/usr/bin/tar"
            let parent = sources[0].deletingLastPathComponent().path
            args = ["-czf", finalDest.path, "-C", parent]
                + sources.map(\.lastPathComponent)
        }
        let ok = await runProcess(exe: exe, args: args)
        appendLog(ok ? "Đã nén → \(finalDest.lastPathComponent)" : "Thất bại khi nén \(sources.count) mục")
        if ok {
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
            let destDir = outputFolder ?? src.deletingLastPathComponent()
            let ext = src.pathExtension.lowercased()
            let name = src.deletingPathExtension().lastPathComponent
            let exe: String
            let args: [String]
            if ext == "zip" {
                exe = "/usr/bin/ditto"
                args = ["-x", "-k", src.path, destDir.appendingPathComponent(name).path]
            } else {
                exe = "/usr/bin/tar"
                args = ["-xzf", src.path, "-C", destDir.path]
            }
            if await runProcess(exe: exe, args: args) { okCount += 1 }
            else { appendLog("Lỗi: không giải được \(src.lastPathComponent)") }
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

    private func runProcess(exe: String, args: [String]) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
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
