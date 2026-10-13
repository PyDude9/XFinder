import SwiftUI
import AppKit
import PDFKit

/// Công cụ PDF — real implementation on built-in PDFKit:
/// merge multiple PDFs, extract a page range, rotate pages.
struct PdfToolsDetailView: View {
    enum Tool: String, CaseIterable, Identifiable {
        case merge, extract, rotate
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .merge: return L10n.t("Gộp PDF")
            case .extract: return L10n.t("Tách trang")
            case .rotate: return L10n.t("Xoay trang")
            }
        }
    }

    @State private var tool: Tool = .merge
    @State private var sources: [URL] = []
    @State private var outputFolder: URL? = nil
    // Extract / rotate options
    @State private var pageRangeText: String = "1-3"
    @State private var angle: Int = 90
    @State private var isRunning = false
    @State private var resultMessage: String? = nil
    @State private var isError = false

    private var inspectedPageCount: Int {
        guard let first = sources.first,
              let doc = PDFDocument(url: first) else { return 0 }
        return doc.pageCount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "doc.richtext.fill",
                           title: L10n.t("Công cụ PDF"))

                Picker(L10n.t("Công cụ"), selection: $tool) {
                    ForEach(Tool.allCases) { t in Text(t.titleVI).tag(t) }
                }
                .pickerStyle(.segmented)   // segmented-ok: 3 cases
                .padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(
                        icon: "doc.on.doc",
                        title: tool == .merge ? L10n.t("Các tập tin PDF cần gộp (theo thứ tự)") : L10n.t("Tập tin PDF nguồn"),
                        subtitle: sources.isEmpty ? L10n.t("Chưa chọn gì") : "\(sources.count)\(L10n.t(" tập tin"))"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Button(L10n.t("Chọn PDF…")) { pickSources() }
                        ForEach(sources, id: \.self) { url in
                            HStack {
                                Image(systemName: "doc.richtext.fill").foregroundColor(.red.opacity(0.8))
                                Text(url.lastPathComponent)
                                    .font(XFinderTokens.Font.rowValue)
                                    .fileNameRowSafe()
                                Spacer()
                                if tool == .merge, sources.count > 1 {
                                    Button {
                                        moveUp(url)
                                    } label: { Image(systemName: "chevron.up") }
                                    .buttonStyle(.plain)
                                    .disabled(sources.first == url)
                                    Button {
                                        moveDown(url)
                                    } label: { Image(systemName: "chevron.down") }
                                    .buttonStyle(.plain)
                                    .disabled(sources.last == url)
                                }
                                Button {
                                    sources.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !sources.isEmpty, tool != .merge, inspectedPageCount > 0 {
                            Text("\(L10n.t("Tài liệu có "))\(inspectedPageCount)\(L10n.t(" trang"))")
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                if tool == .extract {
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "scissors", title: L10n.t("Trang cần tách"), subtitle: L10n.t("Ví dụ: 1-3 hoặc 2,5,7"))
                        TextField("1-3", text: $pageRangeText)
                            .textFieldStyle(.roundedBorder)
                            .font(XFinderTokens.Font.mono)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }

                if tool == .rotate {
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "rotate.right", title: L10n.t("Góc xoay & trang"))
                        VStack(alignment: .leading, spacing: 10) {
                            Picker(L10n.t("Góc"), selection: $angle) {
                                Text("90°").tag(90)
                                Text("180°").tag(180)
                                Text("270°").tag(270)
                            }
                            .pickerStyle(.segmented)
                            TextField(L10n.t("Trang (1-3 hoặc 2,5,7 — để trống = tất cả)"), text: $pageRangeText)
                                .textFieldStyle(.roundedBorder)
                                .font(XFinderTokens.Font.mono)
                        }
                        .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(
                        icon: "folder",
                        title: L10n.t("Thư mục đích"),
                        subtitle: outputFolder?.path ?? L10n.t("Mặc định: cùng thư mục với tập tin đầu tiên")
                    )
                    HStack {
                        Button(L10n.t("Chọn thư mục đích…")) {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK { outputFolder = panel.url }
                        }
                        if outputFolder != nil {
                            Button(L10n.t("Mặc định")) { outputFolder = nil }.font(XFinderTokens.Font.rowValue)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        if isRunning { ProgressView().scaleEffect(0.7) }
                        Text(isRunning ? L10n.t("Đang xử lý…") : L10n.t("Thực hiện"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRun || isRunning)
                .padding(.horizontal, XFinderTokens.Space.page)

                if let msg = resultMessage {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: isError ? "exclamationmark.triangle.fill" : "checkmark.circle",
                                      title: isError ? L10n.t("Lỗi") : L10n.t("Kết quả"))
                        Text(msg)
                            .font(XFinderTokens.Font.rowValue)
                            .foregroundColor(isError ? .red : .primary)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    private var canRun: Bool {
        switch tool {
        case .merge: return sources.count >= 2
        case .extract, .rotate: return sources.count == 1
        }
    }

    // MARK: - Pickers & ordering

    private func pickSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = tool == .merge
        panel.allowedFileTypes = ["pdf"]
        if panel.runModal() == .OK { sources = panel.urls }
    }

    private func moveUp(_ url: URL) {
        guard let i = sources.firstIndex(of: url), i > 0 else { return }
        sources.swapAt(i, i - 1)
    }

    private func moveDown(_ url: URL) {
        guard let i = sources.firstIndex(of: url), i < sources.count - 1 else { return }
        sources.swapAt(i, i + 1)
    }

    // MARK: - Run — PdfRunner does the work off the main thread; output names never replace a file

    private func run() async {
        await MainActor.run { isRunning = true; resultMessage = nil }
        let tool = self.tool, sources = self.sources, range = pageRangeText, angle = self.angle
        let folder = outputFolder ?? sources.first?.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory
        let outcome: Result<PdfRunner.Output, PdfRunner.Failure> = await Task.detached(priority: .userInitiated) {
            switch tool {
            case .merge: return PdfRunner.merge(sources, into: folder)
            case .extract: return PdfRunner.extract(sources[0], range: range, into: folder)
            case .rotate: return PdfRunner.rotate(sources[0], range: range, degrees: angle, into: folder)
            }
        }.value
        await MainActor.run {
            isRunning = false
            switch outcome {
            case .failure(let f):
                finish(error: "\(L10n.t(f.messageKey))\(f.detail)")
            case .success(let o):
                let name = o.url.lastPathComponent
                switch tool {
                case .merge:
                    finish(error: nil, message: "\(L10n.t("Đã gộp "))\(sources.count)\(L10n.t(" tập tin ("))\(o.pages)\(L10n.t(" trang) → "))\(name)")
                case .extract:
                    finish(error: nil, message: "\(L10n.t("Đã tách "))\(o.pages)\(L10n.t(" trang → "))\(name)")
                case .rotate:
                    finish(error: nil, message: "\(L10n.t("Đã xoay "))\(o.pages)\(L10n.t(" trang "))\(angle)° → \(name)")
                }
            }
        }
    }

    @MainActor
    private func finish(error: String?, message: String? = nil) {
        isError = error != nil
        resultMessage = error ?? message
        if let message {
            ActionHistoryStore.shared.record(kind: "pdf", summary: message, reversible: false)
        }
    }
}
