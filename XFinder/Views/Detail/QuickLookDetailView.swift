import SwiftUI
import AppKit
import QuickLookUI
import WebKit

/// Quick Look — status page for XFinder's preview extensions, mirroring the
/// reference screenshot: which generators are registered, what formats they
/// cover, and the conflict note. The live previewer moved into a sheet so the
/// page itself stays a settings screen.
///
/// Honesty note: a real Quick Look generator requires a separate
/// `.appex` extension target. Until that target exists the rows report the
/// **actual** registration state from `pluginkit`, never a hardcoded ✓.
struct QuickLookDetailView: View {
    @State private var mainRegistered = false
    @State private var devRegistered = false
    @State private var showPreviewer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "eye",
                           title: "Quick Look",
                           subtitle: "Xem trước Markdown và file nén mà không cần mở.")

                VStack(spacing: 0) {
                    extensionRow(title: "Xem trước chính — Markdown & file nén",
                                 registered: mainRegistered)
                    Divider().padding(.leading, 34)
                    extensionRow(title: "Xem trước cho lập trình viên — dữ liệu, mã nguồn & font",
                                 registered: devRegistered)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
                .padding(.horizontal, 20)

                SettingsCard(title: "Video — QuickLookVideo",
                             subtitle: "Xem trước & thumbnail video (AV1, VP9, DivX, WMV…, macOS 26+)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("QuickLookVideo v3 cài Media Extensions vào AVFoundation để Quick Look hiện thumbnail và phát được mọi định dạng video — chính là tính năng video còn thiếu của XFinder.")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Tải QuickLookVideo (DMG)") {
                                NSWorkspace.shared.open(URL(string: "https://github.com/Marginal/QuickLookVideo/releases/download/rel-311/QLVideo_311.dmg")!)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            Button("Trang phát hành") {
                                NSWorkspace.shared.open(URL(string: "https://github.com/Marginal/QuickLookVideo/releases/tag/rel-311")!)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                        Text("Tải xong mở DMG và làm theo hướng dẫn bên trong; mở lại Finder nếu thumbnail video chưa mới.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Định dạng xem trước").font(.system(size: 15, weight: .semibold))
                    line("Nhấn Space trên file .md, .mdx, .qmd hoặc .rmd trong Finder.")
                    line("Nhấn Space trên file ZIP, 7Z, RAR, GZ hoặc TAR.GZ để xem nội dung mà không cần giải nén.")
                    line("Render tiêu đề, bảng, danh sách công việc, khối mã, front matter và ảnh local.")
                    line("Mã MDX, Quarto và R được hiển thị nhưng không bao giờ được thực thi.")
                    line("Bản xem trước file nén chỉ đọc header và không bao giờ tạo file đã giải nén.")
                    line("Xem trước JSON, YAML, TOML, XML, CSV/TSV, log, mã nguồn, font và cơ sở dữ liệu SQLite chỉ đọc.")
                    line("HTML thô, JavaScript và tài nguyên mạng bị chặn để bảo đảm an toàn.")
                }
                .padding(.horizontal, 20)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundColor(.blue)
                    Text("Nếu ứng dụng Quick Look khác cũng xử lý cùng định dạng, macOS sẽ chọn một trình cung cấp. Hãy tắt tiện ích xung đột trong Login Items & Extensions.")
                        .font(.system(size: 12))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.08)))
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Xem trước ngay trong XFinder")
                        .font(.system(size: 13, weight: .medium))
                    Text("Không cần cài tiện ích: mở trình xem trước tích hợp để đọc Markdown và liệt kê file nén.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Button("Mở trình xem trước…") { showPreviewer = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear(perform: refresh)
        .sheet(isPresented: $showPreviewer) {
            QuickLookPreviewerSheet(isPresented: $showPreviewer)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundColor(.secondary)
    }

    private func extensionRow(title: String, registered: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: registered ? "checkmark.circle.fill" : "circle")
                .foregroundColor(registered ? .green : .secondary)
                .frame(width: 20)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 10)
            Text(registered ? "Đã đăng ký" : "Chưa cài đặt")
                .font(.system(size: 12)).foregroundColor(.secondary)
            Button("Tiện ích…") { openExtensionsPane() }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    /// Real registration state via `pluginkit -m`, so the row cannot claim an
    /// extension is installed when it is not.
    private func refresh() {
        Task.detached {
            let listed = Self.registeredExtensions()
            let main = listed.contains { $0.contains("QuickLook") && $0.contains("xfinder") }
            let dev = listed.contains { $0.contains("Developer") && $0.contains("xfinder") }
            await MainActor.run {
                mainRegistered = main
                devRegistered = dev
            }
        }
    }

    private nonisolated static func registeredExtensions() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        p.arguments = ["-m", "-p", "com.apple.quicklook.preview"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.components(separatedBy: .newlines)
    }

    private func openExtensionsPane() {
        WindowManager.openFinderExtensionsPane()
    }
}

/// The previous file-browsing previewer, now presented as a sheet.
struct QuickLookPreviewerSheet: View {
    @Binding var isPresented: Bool
    @State private var files: [URL] = []
    @State private var selected: URL? = nil
    @State private var renderedHTML: String? = nil
    @State private var archiveListing: [String]? = nil
    @State private var qlController: QuickLookController? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Trình xem trước").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Chọn tập tin…") { pickFiles() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Xong") { isPresented = false }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if files.isEmpty {
                        Text("Chưa chọn tập tin nào")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(12)
                    } else {
                        List(selection: $selected) {
                            ForEach(files, id: \.self) { url in
                                Label(url.lastPathComponent, systemImage: iconFor(url))
                                    .font(.system(size: 12))
                                    .tag(url)
                            }
                        }
                    }
                    Spacer()
                }
                .frame(width: 240)

                Divider()

                Group {
                    if let html = renderedHTML {
                        MarkdownWebView(html: html)
                    } else if let listing = archiveListing {
                        List(listing, id: \.self) { entry in
                            Text(entry).font(.system(size: 11, design: .monospaced))
                        }
                    } else if let url = selected {
                        VStack(spacing: 10) {
                            Image(systemName: "eye").font(.system(size: 34)).foregroundColor(.secondary)
                            Text(url.lastPathComponent).font(.system(size: 13, weight: .medium))
                            Button("Mở Quick Look hệ thống") { presentSystemQuickLook(url) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 34)).foregroundColor(.secondary)
                            Text("Chọn một tập tin để xem trước")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(width: 860, height: 560)
        .onChange(of: selected) { load() }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            files = panel.urls
            selected = panel.urls.first
        }
    }

    private func load() {
        renderedHTML = nil
        archiveListing = nil
        guard let url = selected else { return }
        let ext = url.pathExtension.lowercased()
        if ["md", "mdx", "qmd", "rmd", "markdown"].contains(ext) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                renderedHTML = MarkdownRenderer.toHTML(text)
            }
            return
        }
        if url.isArchiveURL {
            archiveListing = ArchiveReader.listEntries(url: url)
        }
    }

    private func presentSystemQuickLook(_ url: URL) {
        if qlController == nil { qlController = QuickLookController() }
        qlController?.present(url: url)
    }

    private func iconFor(_ url: URL) -> String {
        if url.pathExtension.lowercased() == "md" { return "doc.richtext.fill" }
        if url.isArchiveURL { return "archivebox.fill" }
        return "doc.fill"
    }
}

// MARK: - URL helpers

private extension URL {
    var isArchiveURL: Bool {
        let ext = pathExtension.lowercased()
        return ["zip", "tar", "gz", "tgz", "bz2", "7z"].contains(ext)
    }
}

// MARK: - Markdown renderer (tiny, no deps)

enum MarkdownRenderer {
    static func toHTML(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var html = "<!doctype html><meta charset='utf-8'><style>"
            + "body{font:14px -apple-system;margin:18px;line-height:1.6}"
            + "code{background:#8882;padding:1px 4px;border-radius:4px;font-family:monospace}"
            + "h1{font-size:22px}h2{font-size:18px}h3{font-size:15px}"
            + "ul{padding-left:20px}</style>"
        var inList = false
        for raw in lines {
            var line = raw
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { html += "<ul>"; inList = true }
                html += "<li>\(inline(String(line.dropFirst(2))))</li>"
                continue
            } else if inList { html += "</ul>"; inList = false }
            var headingLevel = 0
            for c in line where c == "#" { headingLevel += 1 }
            if headingLevel > 0, headingLevel <= 6 { line = String(line.dropFirst(headingLevel)).trimmingCharacters(in: .whitespaces) }
            if headingLevel > 0 {
                html += "<h\(headingLevel)>\(inline(line))</h\(headingLevel)>"
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                html += "<br>"
            } else {
                html += "<p>\(inline(line))</p>"
            }
        }
        if inList { html += "</ul>" }
        return html
    }

    private static func inline(_ s: String) -> String {
        var out = s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        out = regexReplace(out, pattern: "\\*\\*(.+?)\\*\\*") { "<b>\($0)</b>" }
        out = regexReplace(out, pattern: "`(.+?)`") { "<code>\($0)</code>" }
        return out
    }

    private static func regexReplace(_ s: String, pattern: String, _ transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        var result = s
        for m in re.matches(in: s, range: range).reversed() {
            guard let outer = Range(m.range, in: result) else { continue }
            let inner = re.replacementString(for: m, in: s, offset: 0, template: "$1")
            let replacement = transform(inner)
            result.replaceSubrange(outer, with: replacement)
        }
        return result
    }
}

// MARK: - WebView wrapper (WKWebView hosted in SwiftUI)

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    func makeNSView(context: Context) -> WKWebView { WKWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Archive listing

enum ArchiveReader {
    static func listEntries(url: URL) -> [String] {
        let ext = url.pathExtension.lowercased()
        let p = Process()
        if ext == "zip" || ext == "7z" {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-Z1", url.path]
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            p.arguments = ["-tf", url.path]
        }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
        } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").map(String.init).prefix(300).map { $0 }
    }
}

struct ArchiveListView: View {
    let entries: [String]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entries.count) mục").font(.caption).foregroundColor(.secondary)
                    .padding([.top, .leading], 12)
                ForEach(entries, id: \.self) { e in
                    HStack {
                        Image(systemName: e.hasSuffix("/") ? "folder.fill" : "doc.fill")
                            .font(.caption).foregroundColor(.secondary)
                        Text(e).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 3)
                }
            }
        }
    }
}

// MARK: - Native QLPreviewPanel controller (AppKit, main thread only)

final class QuickLookController: NSObject, QLPreviewPanelDataSource {
    private var url: URL?

    func present(url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return url as QLPreviewItem?
    }
}
