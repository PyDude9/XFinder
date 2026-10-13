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
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: "Quick Look",
                           subtitle: L10n.t("Xem trước Markdown và file nén mà không cần mở."))

                SettingsSection(title: L10n.t("Tiện ích xem trước")) {
                    extensionRow(title: L10n.t("Xem trước chính — Markdown & file nén"),
                                 registered: mainRegistered)
                    SettingsDivider()
                    extensionRow(title: L10n.t("Xem trước cho lập trình viên — dữ liệu, mã nguồn & font"),
                                 registered: devRegistered)
                }

                SettingsSection(
                    title: "Video — QuickLookVideo",
                    footer: L10n.t("Xem trước & thumbnail video (AV1, VP9, DivX, WMV…, macOS 26+)")
                ) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        Text(L10n.t("QuickLookVideo v3 cài Media Extensions vào AVFoundation để Quick Look hiện thumbnail và phát được mọi định dạng video — chính là tính năng video còn thiếu của XFinder."))
                            .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(L10n.t("Tải QuickLookVideo (DMG)")) {
                                NSWorkspace.shared.open(URL(string: "https://github.com/Marginal/QuickLookVideo/releases/download/rel-311/QLVideo_311.dmg")!)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            Button(L10n.t("Trang phát hành")) {
                                NSWorkspace.shared.open(URL(string: "https://github.com/Marginal/QuickLookVideo/releases/tag/rel-311")!)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                        Text(L10n.t("Tải xong mở DMG và làm theo hướng dẫn bên trong; mở lại Finder nếu thumbnail video chưa mới."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    .settingsRow()
                }

                SettingsSection(title: L10n.t("Định dạng xem trước")) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                        line(L10n.t("Nhấn Space trên file .md, .mdx, .qmd hoặc .rmd trong Finder."))
                        // Only what `unzip -Z1` / `tar -tf` can actually list. No 7Z, no RAR:
                        // macOS ships no decoder for either and the previous copy promised both.
                        line(L10n.t("Nhấn Space trên file ZIP, TAR, TAR.GZ hoặc TAR.BZ2 để xem nội dung mà không cần giải nén."))
                        line(L10n.t("Render tiêu đề, bảng, danh sách công việc, khối mã, front matter và ảnh local."))
                        line(L10n.t("Mã MDX, Quarto và R được hiển thị nhưng không bao giờ được thực thi."))
                        line(L10n.t("Bản xem trước file nén chỉ đọc header và không bao giờ tạo file đã giải nén."))
                        line(L10n.t("Xem trước JSON, YAML, TOML, XML, CSV/TSV, log, mã nguồn, font và cơ sở dữ liệu SQLite chỉ đọc."))
                        line(L10n.t("HTML thô, JavaScript và tài nguyên mạng bị chặn để bảo đảm an toàn."))
                    }
                    .settingsRow()

                    SettingsDivider()
                    InlineNote(text: L10n.t("Nếu ứng dụng Quick Look khác cũng xử lý cùng định dạng, macOS sẽ chọn một trình cung cấp. Hãy tắt tiện ích xung đột trong Login Items & Extensions."))
                        .settingsRow()
                }

                SettingsSection(
                    title: L10n.t("Xem trước ngay trong XFinder"),
                    footer: L10n.t("Không cần cài tiện ích: mở trình xem trước tích hợp để đọc Markdown và liệt kê file nén.")
                ) {
                    Button(L10n.t("Mở trình xem trước…")) { showPreviewer = true }
                        .buttonStyle(.bordered).controlSize(.small)
                        .settingsRow()
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear(perform: refresh)
        .sheet(isPresented: $showPreviewer) {
            QuickLookPreviewerSheet(isPresented: $showPreviewer)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
    }

    private func extensionRow(title: String, registered: Bool) -> some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Image(systemName: registered ? "checkmark.circle.fill" : "circle")
                .foregroundColor(registered ? .green : .secondary)
                .frame(width: 20)
            Text(title).font(XFinderTokens.Font.row)
            Spacer(minLength: XFinderTokens.Space.inline)
            Text(registered ? L10n.t("Đã đăng ký") : L10n.t("Chưa cài đặt"))
                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            Button(L10n.t("Tiện ích…")) { openExtensionsPane() }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .settingsRow()
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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
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
                Text(L10n.t("Trình xem trước")).font(XFinderTokens.Font.sectionTitle)
                Spacer()
                Button(L10n.t("Chọn tập tin…")) { pickFiles() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(L10n.t("Xong")) { isPresented = false }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if files.isEmpty {
                        Text(L10n.t("Chưa chọn tập tin nào"))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .padding(12)
                    } else {
                        List(selection: $selected) {
                            ForEach(files, id: \.self) { url in
                                Label(url.lastPathComponent, systemImage: iconFor(url))
                                    .font(XFinderTokens.Font.rowValue)
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
                            Text(entry).font(XFinderTokens.Font.mono)
                        }
                    } else if let url = selected {
                        VStack(spacing: 10) {
                            Image(systemName: "eye").font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
                            Text(url.lastPathComponent).font(XFinderTokens.Font.row)
                            Button(L10n.t("Mở Quick Look hệ thống")) { presentSystemQuickLook(url) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
                            Text(L10n.t("Chọn một tập tin để xem trước"))
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
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
            Task {
                let entries = await Task.detached {
                    ArchiveReader.listEntries(url: url)
                }.value
                if self.selected == url {
                    self.archiveListing = entries
                }
            }
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
        // `7z` deliberately absent: Info-ZIP `unzip` cannot read it, so listing one
        // returned [] and looked like a bug rather than an unsupported format.
        return ["zip", "tar", "gz", "tgz", "bz2"].contains(ext)
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
        if ext == "zip" {
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
                Text("\(entries.count)\(L10n.t(" mục"))").font(.caption).foregroundColor(.secondary)
                    .padding([.top, .leading], 12)
                ForEach(entries, id: \.self) { e in
                    HStack {
                        Image(systemName: e.hasSuffix("/") ? "folder.fill" : "doc.fill")
                            .font(.caption).foregroundColor(.secondary)
                        Text(e).font(XFinderTokens.Font.mono).lineLimit(1)
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
