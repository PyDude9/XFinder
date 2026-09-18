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
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(item.path).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(L10n.t("Mở")) { NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) }
                .buttonStyle(.link).font(.system(size: 11))
            Button(L10n.t("Hiện trong Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
            .buttonStyle(.link).font(.system(size: 11))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
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
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("Tìm kiếm"))
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 16)

                if quickSearchEnabled {
                    quickSearchCard
                        .padding(.horizontal, 20)
                }

                paletteCard
                    .padding(.horizontal, 20)

                quicklinksCard
                    .padding(.horizontal, 20)

                Text(L10n.t("Tìm nâng cao"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)

                SettingsCard(title: L10n.t("Tên tập tin")) {
                    TextField(L10n.t("Ví dụ: báo cáo"), text: $criteria.nameContains)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        .onSubmit { run() }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: L10n.t("Loại & thời gian")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(L10n.t("Loại"), selection: $criteria.kind) {
                            ForEach(FileSearchEngine.Criteria.KindFilter.allCases) { k in
                                Text(k.titleVI).tag(k)
                            }
                        }
                        .pickerStyle(.menu).frame(maxWidth: 220)
                        Picker(L10n.t("Sửa đổi"), selection: Binding(
                            get: { criteria.modifiedWithinDays ?? 0 },
                            set: { criteria.modifiedWithinDays = $0 == 0 ? nil : $0 })) {
                                Text(L10n.t("Mọi lúc")).tag(0)
                                Text(L10n.t("Hôm nay")).tag(1)
                                Text(L10n.t("7 ngày qua")).tag(7)
                                Text(L10n.t("30 ngày qua")).tag(30)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: L10n.t("Phạm vi"),
                             subtitle: scopes.isEmpty ? L10n.t("Toàn máy") : "\(scopes.count)\(L10n.t(" thư mục"))") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(L10n.t("Thêm thư mục…")) {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = true
                                if panel.runModal() == .OK { scopes = panel.urls }
                            }
                            if !scopes.isEmpty {
                                Button(L10n.t("Toàn máy")) { scopes = [] }.font(.system(size: 12))
                            }
                        }
                        ForEach(scopes, id: \.self) { url in
                            HStack {
                                Text(url.path).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                                Spacer()
                                Button { scopes.removeAll { $0 == url } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

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
                .padding(.horizontal, 20)

                SettingsCard(title: searched
                             ? (results.isEmpty ? L10n.t("Không tìm thấy gì") : "\(results.count)\(L10n.t(" kết quả"))")
                             : L10n.t("Kết quả")) {
                    VStack(spacing: 6) {
                        ForEach(results.prefix(50)) { item in
                            FileResultRow(item: item)
                        }
                        if results.count > 50 {
                            Text("\(L10n.t("…và "))\(results.count - 50)\(L10n.t(" kết quả nữa — hãy thu hẹp điều kiện."))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showQuicklinkSheet) {
            QuicklinkEditorSheet(isPresented: $showQuicklinkSheet, link: editingQuicklink)
        }
    }

    // MARK: - Tìm nhanh (kiểu TinyCast)

    private var quickSearchCard: some View {
        SettingsCard(
            title: L10n.t("Tìm nhanh"),
            subtitle: L10n.t("Ứng dụng · Liên kết nhanh · Phép tính · Tập tin — gõ là ra")
        ) {
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
                .background(Color(.controlBackgroundColor).opacity(0.7))
                .cornerRadius(6)

                if !quickSearch.results.isEmpty {
                    quickResultsSection
                } else if !quickQuery.isEmpty && !quickSearch.isSearching {
                    Text("\(L10n.t("Không có gì khớp “"))\(quickQuery)”.")
                        .font(.caption).foregroundColor(.secondary)
                }

                Text(L10n.t("Ứng dụng: tên khớp mờ (saf → Safari) · Liên kết: gõ từ khóa · Phép tính: nút Mở sao chép kết quả · Tập tin: qua Spotlight. Nhấn ↵ để mở kết quả đầu tiên."))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var quickResultsSection: some View {
        let grouped = Dictionary(grouping: quickSearch.results, by: \.type)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach([QuickSearchResult.ResultType.quicklink, .app, .calculator, .file], id: \.self) { type in
                if let items = grouped[type], !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.titleVI)
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                        ForEach(items.prefix(5)) { result in
                            QuickSearchResultRow(result: result)
                        }
                    }
                }
            }
        }
    }

    /// Phím tắt toàn cục — công tắc bật/tắt Quick Search + ô ghi hotkey.
    private var paletteCard: some View {
        SettingsCard(title: L10n.t("Phím tắt toàn cục"),
                     subtitle: "\(palette.hotkeyLabel)\(L10n.t(" mở bảng lệnh nổi kiểu Spotlight / Raycast / TinyCast"))") {
            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(title: L10n.t("Bật Tìm nhanh (Quick Search)"),
                          subtitle: L10n.t("Bảng lệnh toàn cục + ô tìm nhanh trong trang này"),
                          isOn: $quickSearchEnabled)
                    .onChange(of: quickSearchEnabled) {
                        QuickSearchPanelController.shared.applySettings()
                    }

                if quickSearchEnabled {
                    // Ô phím tắt: hiển thị tổ hợp hiện tại + nút ghi tổ hợp mới.
                    HStack(spacing: 10) {
                        Text(L10n.t("Phím tắt"))
                            .font(.system(size: 12))
                        Text(palette.hotkeyLabel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.08)))
                        Button {
                            if palette.isRecording {
                                palette.cancelRecording()
                            } else {
                                palette.beginRecording()
                            }
                        } label: {
                            Text(palette.isRecording ? L10n.t("Hủy ghi") : L10n.t("Đổi phím…"))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if palette.isRecording {
                        Text(L10n.t("Đang ghi — nhấn tổ hợp phím mới (phải có ⌘/⌥/⌃, ví dụ ⌘Space). Esc để hủy."))
                            .font(.system(size: 11)).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L10n.t("Chọn phím theo thói quen — ví dụ ⌘Space hoặc ⌥Space. Nếu chọn ⌘Space, hãy tắt ⌘Space của Spotlight trong Cài đặt → Bàn phím → Phím tắt để tránh mở cả hai cùng lúc."))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var quicklinksCard: some View {
        SettingsCard(title: L10n.t("Liên kết nhanh"), subtitle: "\(quicklinks.links.count)\(L10n.t(" từ khóa"))") {
            VStack(alignment: .leading, spacing: 8) {
                if quicklinks.links.isEmpty {
                    Text(L10n.t("Chưa có liên kết nào."))
                        .font(.caption).foregroundColor(.secondary)
                }
                ForEach(quicklinks.links) { link in
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundColor(.purple)
                        Text(link.keyword)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title).font(.system(size: 12, weight: .medium))
                            Text(link.url).font(.system(size: 10))
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
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                }
                Button(L10n.t("Thêm liên kết")) {
                    editingQuicklink = nil
                    showQuicklinkSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
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
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("Tìm kiếm AI"))
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 16)

                SettingsCard(title: L10n.t("Hỏi bằng câu tự nhiên"),
                             subtitle: L10n.t("100% trên máy — ví dụ: “ảnh sửa tuần này”")) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(L10n.t("Ví dụ: video mới tháng này, pdf báo cáo…"), text: $queryText)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                            .onSubmit { run() }
                        Text(L10n.t("Gợi ý: loại (ảnh, video, pdf, thư mục…) + thời gian (hôm nay, tuần này…) + tên trong “ngoặc kép”."))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)

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
                .padding(.horizontal, 20)

                if let expl = explanation {
                    SettingsCard(title: L10n.t("AI hiểu")) {
                        Text(expl).font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                }

                SettingsCard(title: searched
                             ? (results.isEmpty ? L10n.t("Không tìm thấy gì") : "\(results.count)\(L10n.t(" kết quả"))")
                             : L10n.t("Kết quả")) {
                    VStack(spacing: 6) {
                        ForEach(results.prefix(50)) { item in
                            FileResultRow(item: item)
                        }
                        if results.count > 50 {
                            Text("\(L10n.t("…và "))\(results.count - 50)\(L10n.t(" kết quả nữa."))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
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
                Text(result.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(result.type == .calculator ? L10n.t("Sao chép") : L10n.t("Mở")) { result.action() }
                .buttonStyle(.link).font(.system(size: 11))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
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
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Tiêu đề")).font(.system(size: 12, weight: .medium))
                TextField("Google", text: $title).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL").font(.system(size: 12, weight: .medium))
                TextField("https://google.com", text: $url).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Từ khóa")).font(.system(size: 12, weight: .medium))
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
