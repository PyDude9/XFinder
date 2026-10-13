import SwiftUI
import AppKit

/// Shared result-row UI for the Tìm kiếm / Tìm kiếm AI pages.
struct FileResultRow: View {
    let item: FileSearchEngine.ResultItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: NSWorkspace.shared.icon(forFile: item.path).isTemplate ? "doc.fill" : "doc.fill")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(XFinderTokens.Font.row).lineLimit(1).fileNameRowSafe()
                Text(item.path).font(XFinderTokens.Font.mono)
                    .foregroundColor(.secondary).fileNameRowSafe()
            }
            Spacer()
            Button(L10n.t("Mở")) { NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) }
                .buttonStyle(.link).font(XFinderTokens.Font.caption)
            Button(L10n.t("Hiện trong Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
            .buttonStyle(.link).font(XFinderTokens.Font.caption)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(XFinderTokens.Fill.inset)
        .cornerRadius(XFinderTokens.Radius.control)
    }
}

/// Tìm kiếm — structured Spotlight search (name + kind + recency), optionally
/// scoped to chosen folders. Runs `mdfind` on a background task.
struct FinderSearchDetailView: View {
    @State private var criteria = FileSearchEngine.Criteria()
    @State private var scopes: [URL] = []
    @State private var results: [FileSearchEngine.ResultItem] = []
    @State private var isSearching = false
    @State private var searched = false
    // Tìm nhanh (kiểu TinyCast) — engine gộp app/link/phép tính/file.
    @State private var quickQuery = ""
    @State private var quickSearch = QuickSearchEngine.shared
    @State private var quicklinks = Quicklinks.shared
    @State private var palette = QuickSearchPanelController.shared
    @State private var showQuicklinkSheet = false
    @State private var editingQuicklink: Quicklinks.Quicklink? = nil
    /// Bật/tắt Quick Search — controller đọc cùng key này (quickSearch.enabled).
    @AppStorage("quickSearch.enabled") private var quickSearchEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(
                    icon: "magnifyingglass",
                    title: L10n.t("Tìm kiếm"),
                    subtitle: L10n.t("Tìm nhanh ứng dụng, liên kết và tập tin, hoặc lọc theo tên/loại/thời gian")
                )

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    if quickSearchEnabled {
                        quickSearchSection
                    }
                    paletteSection
                    quicklinksSection
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "line.3.horizontal.decrease.circle", title: L10n.t("Tìm nâng cao"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("Tên tập tin")).font(XFinderTokens.Font.row)
                        TextField(L10n.t("Ví dụ: báo cáo"), text: $criteria.nameContains)
                            .textFieldStyle(.roundedBorder)
                            .font(XFinderTokens.Font.rowValue)
                            .onSubmit { run() }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)

                    PickerRow(title: L10n.t("Loại"), selection: $criteria.kind, width: 180) {
                        ForEach(FileSearchEngine.Criteria.KindFilter.allCases) { k in
                            Text(k.titleVI).tag(k)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)

                    PickerRow(
                        title: L10n.t("Sửa đổi"),
                        selection: Binding(
                            get: { criteria.modifiedWithinDays ?? 0 },
                            set: { criteria.modifiedWithinDays = $0 == 0 ? nil : $0 }),
                        width: 140
                    ) {
                        Text(L10n.t("Mọi lúc")).tag(0)
                        Text(L10n.t("Hôm nay")).tag(1)
                        Text(L10n.t("7 ngày qua")).tag(7)
                        Text(L10n.t("30 ngày qua")).tag(30)
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)

                    scopeSection

                    Button {
                        run()
                    } label: {
                        HStack {
                            if isSearching { ProgressView().scaleEffect(0.7) }
                            Text(isSearching ? L10n.t("Đang tìm…") : L10n.t("Tìm kiếm"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSearching)
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(
                        icon: "list.bullet",
                        title: searched
                            ? (results.isEmpty ? L10n.t("Không tìm thấy gì") : "\(results.count)\(L10n.t(" kết quả"))")
                            : L10n.t("Kết quả")
                    )
                    VStack(spacing: 6) {
                        ForEach(results.prefix(50)) { item in
                            FileResultRow(item: item)
                        }
                        if results.count > 50 {
                            Text("\(L10n.t("…và "))\(results.count - 50)\(L10n.t(" kết quả nữa — hãy thu hẹp điều kiện."))")
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .sheet(isPresented: $showQuicklinkSheet) {
            QuicklinkEditorSheet(isPresented: $showQuicklinkSheet, link: editingQuicklink)
        }
    }

    // MARK: - Tìm nhanh (kiểu TinyCast)

    private var quickSearchSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(
                icon: "bolt.fill",
                title: L10n.t("Tìm nhanh"),
                subtitle: L10n.t("Ứng dụng · Liên kết nhanh · Phép tính · Tập tin — gõ là ra")
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(L10n.t("Ví dụ: saf, gh, 12*(3+4), báo cáo…"), text: $quickQuery)
                        .textFieldStyle(.plain)
                        .onSubmit { openTopQuickResult() }
                    if quickSearch.isSearching {
                        ProgressView().scaleEffect(0.6).controlSize(.small)
                    }
                    if !quickQuery.isEmpty {
                        Button {
                            quickQuery = ""
                            quickSearch.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(XFinderTokens.Fill.inset)
                .cornerRadius(XFinderTokens.Radius.control)

                if !quickSearch.results.isEmpty {
                    quickResultsSection
                } else if !quickQuery.isEmpty && !quickSearch.isSearching {
                    Text("\(L10n.t("Không có gì khớp “"))\(quickQuery)”.")
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }

                Text(L10n.t("Ứng dụng: tên khớp mờ (saf → Safari) · Liên kết: gõ từ khóa · Phép tính: nút Mở sao chép kết quả · Tập tin: qua Spotlight. Nhấn ↵ để mở kết quả đầu tiên."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private var quickResultsSection: some View {
        let grouped = Dictionary(grouping: quickSearch.results, by: \.type)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach([QuickSearchResult.ResultType.quicklink, .app, .calculator, .file], id: \.self) { type in
                if let items = grouped[type], !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.titleVI)
                            .font(XFinderTokens.Font.caption).fontWeight(.semibold).foregroundColor(.secondary)
                        ForEach(items.prefix(5)) { result in
                            QuickSearchResultRow(result: result)
                        }
                    }
                }
            }
        }
    }

    /// Phím tắt toàn cục — công tắc bật/tắt Quick Search; đổi tổ hợp phím ở trang Phím tắt.
    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(
                icon: "command",
                title: L10n.t("Phím tắt toàn cục"),
                subtitle: "\(palette.hotkeyLabel)\(L10n.t(" mở bảng lệnh nổi kiểu Spotlight / Raycast / TinyCast"))"
            )

            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(title: L10n.t("Bật Tìm nhanh (Quick Search)"),
                          subtitle: L10n.t("Bảng lệnh toàn cục + ô tìm nhanh trong trang này"),
                          isOn: $quickSearchEnabled)
                    .onChange(of: quickSearchEnabled) {
                        QuickSearchPanelController.shared.applySettings()
                    }

                if quickSearchEnabled {
                    SettingsLinkRow(title: L10n.t("Đổi phím tắt trong Phím tắt"), destination: .shortcuts) {
                        ShortcutChip(label: palette.hotkeyLabel)
                    }
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private var quicklinksSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(
                icon: "link",
                title: L10n.t("Liên kết nhanh"),
                subtitle: "\(quicklinks.links.count)\(L10n.t(" từ khóa"))"
            )

            VStack(alignment: .leading, spacing: 8) {
                if quicklinks.links.isEmpty {
                    Text(L10n.t("Chưa có liên kết nào."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                ForEach(quicklinks.links) { link in
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundColor(.purple)
                        Text(link.keyword)
                            .font(XFinderTokens.Font.mono)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(XFinderTokens.Fill.surface)
                            .cornerRadius(XFinderTokens.Radius.badge)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title).font(XFinderTokens.Font.row)
                            Text(link.url).font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            editingQuicklink = link
                            showQuicklinkSheet = true
                        } label: {
                            Image(systemName: "pencil").font(.caption)
                        }
                        .buttonStyle(.plain)
                        Button {
                            quicklinks.delete(link)
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(XFinderTokens.Fill.inset)
                    .cornerRadius(XFinderTokens.Radius.control)
                }
                Button(L10n.t("Thêm liên kết")) {
                    editingQuicklink = nil
                    showQuicklinkSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("Phạm vi")).font(XFinderTokens.Font.row)
                Spacer()
                Text(scopes.isEmpty ? L10n.t("Toàn máy") : "\(scopes.count)\(L10n.t(" thư mục"))")
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            }
            HStack {
                Button(L10n.t("Thêm thư mục…")) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK { scopes = panel.urls }
                }
                .controlSize(.small)
                if !scopes.isEmpty {
                    Button(L10n.t("Toàn máy")) { scopes = [] }
                        .font(XFinderTokens.Font.rowValue)
                        .controlSize(.small)
                }
            }
            ForEach(scopes, id: \.self) { url in
                HStack {
                    Text(url.path).font(XFinderTokens.Font.mono).fileNameRowSafe()
                    Spacer()
                    Button { scopes.removeAll { $0 == url } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    private func openTopQuickResult() {
        guard let top = quickSearch.results.first else { return }
        top.action()
        quickQuery = ""
        quickSearch.clear()
    }

    private func run() {
        let crit = criteria
        let sc = scopes
        isSearching = true
        Task.detached(priority: .userInitiated) {
            let found = FileSearchEngine.search(criteria: crit, scopes: sc)
            await MainActor.run {
                results = found
                searched = true
                isSearching = false
            }
        }
    }
}

/// Tìm kiếm AI — type a natural sentence (Vietnamese or English); the on-device
/// rule parser turns it into a Spotlight query and explains what it understood.
/// No network, no model download, no fabricated answers.
struct AiSearchDetailView: View {
    @State private var queryText = ""
    @State private var explanation: String? = nil
    @State private var results: [FileSearchEngine.ResultItem] = []
    @State private var isSearching = false
    @State private var searched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(
                    icon: "wand.and.stars",
                    title: L10n.t("Tìm kiếm AI"),
                    subtitle: L10n.t("Hiểu câu tự nhiên và tự tạo câu truy vấn Spotlight — 100% trên máy")
                )

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(
                        icon: "text.bubble",
                        title: L10n.t("Hỏi bằng câu tự nhiên"),
                        subtitle: L10n.t("100% trên máy — ví dụ: “ảnh sửa tuần này”")
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        TextField(L10n.t("Ví dụ: video mới tháng này, pdf báo cáo…"), text: $queryText)
                            .textFieldStyle(.roundedBorder)
                            .font(XFinderTokens.Font.rowValue)
                            .onSubmit { run() }
                        Text(L10n.t("Gợi ý: loại (ảnh, video, pdf, thư mục…) + thời gian (hôm nay, tuần này…) + tên trong “ngoặc kép”."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)

                    Button {
                        run()
                    } label: {
                        HStack {
                            if isSearching { ProgressView().scaleEffect(0.7) }
                            Text(isSearching ? L10n.t("Đang tìm…") : L10n.t("Tìm bằng AI"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    .padding(.horizontal, XFinderTokens.Space.page)
                }

                if let expl = explanation {
                    Divider().padding(.horizontal, XFinderTokens.Space.page)
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        SectionHeader(icon: "sparkles", title: L10n.t("AI hiểu"))
                        Text(expl).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(
                        icon: "list.bullet",
                        title: searched
                            ? (results.isEmpty ? L10n.t("Không tìm thấy gì") : "\(results.count)\(L10n.t(" kết quả"))")
                            : L10n.t("Kết quả")
                    )
                    VStack(spacing: 6) {
                        ForEach(results.prefix(50)) { item in
                            FileResultRow(item: item)
                        }
                        if results.count > 50 {
                            Text("\(L10n.t("…và "))\(results.count - 50)\(L10n.t(" kết quả nữa."))")
                                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    private func run() {
        let text = queryText
        isSearching = true
        Task.detached(priority: .userInitiated) {
            let (query, expl) = FileSearchEngine.parseNaturalLanguage(text)
            let found = FileSearchEngine.runMdfind(query: query)
            await MainActor.run {
                explanation = expl
                results = found
                searched = true
                isSearching = false
            }
        }
    }
}

/// Một dòng kết quả của Tìm nhanh: icon + tên + mô tả + nút hành động.
/// Bấm hàng hoặc nút Mở/Sao chép đều thực thi action.
struct QuickSearchResultRow: View {
    let result: QuickSearchResult

    var body: some View {
        HStack(spacing: 8) {
            if let icon = result.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: result.type.symbolName)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title).font(XFinderTokens.Font.row).lineLimit(1).fileNameRowSafe()
                Text(result.subtitle)
                    .font(XFinderTokens.Font.mono)
                    .foregroundColor(.secondary).fileNameRowSafe()
            }
            Spacer()
            Button(result.type == .calculator ? L10n.t("Sao chép") : L10n.t("Mở")) { result.action() }
                .buttonStyle(.link).font(XFinderTokens.Font.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(XFinderTokens.Fill.inset)
        .cornerRadius(XFinderTokens.Radius.control)
        .contentShape(Rectangle())
        .onTapGesture { result.action() }
    }
}

/// Sheet thêm/sửa liên kết nhanh (từ khóa → URL), lưu qua Quicklinks.
private struct QuicklinkEditorSheet: View {
    @Binding var isPresented: Bool
    let link: Quicklinks.Quicklink?
    @State private var title = ""
    @State private var url = ""
    @State private var keyword = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(link == nil ? L10n.t("Thêm liên kết nhanh") : L10n.t("Sửa liên kết nhanh"))
                .font(XFinderTokens.Font.sectionTitle)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Tiêu đề")).font(XFinderTokens.Font.row)
                TextField("Google", text: $title).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL").font(XFinderTokens.Font.row)
                TextField("https://google.com", text: $url).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Từ khóa")).font(XFinderTokens.Font.row)
                TextField("gg", text: $keyword).textFieldStyle(.roundedBorder)
            }

            HStack {
                Button(L10n.t("Hủy")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(link == nil ? L10n.t("Thêm") : L10n.t("Lưu")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                              || url.trimmingCharacters(in: .whitespaces).isEmpty
                              || keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let link = link {
                title = link.title
                url = link.url
                keyword = link.keyword
            }
        }
    }

    private func save() {
        if let link = link {
            Quicklinks.shared.update(link, keyword: keyword, title: title, url: url)
        } else {
            Quicklinks.shared.add(keyword: keyword, title: title, url: url)
        }
        isPresented = false
    }
}
