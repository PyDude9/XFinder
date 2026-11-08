import SwiftUI

/// XF-T28 cluster E / XF-T30 W1 — the strip under the location bar: the in-memory filter field (⌘F,
/// `pane.filterText`) and the natural-language search field (⌥⌘F, `pane.runSearch`) with its chips and scope
/// picker. Shown while filtering/searching, OR while `model.filterFocusRequest == pane.id` (⌘F fired on an empty
/// filter — the strip must appear so there is a field to focus, then the request is cleared once focus lands).
struct SearchBarView: View {
    let pane: PaneState
    let model: BrowserWindowModel

    @State private var searchText: String = ""
    @State private var editingChip: SearchChip?
    @State private var indexing = false
    @State private var showSaveSearch = false
    @FocusState private var filterFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            if pane.search != nil {
                searchRow
                if let search = pane.search, !search.parsed.chips.isEmpty {
                    chipsRow(search.parsed)
                }
                if let search = pane.search, !search.parsed.warnings.isEmpty {
                    warningsRow(search.parsed.warnings)
                }
                if indexing {
                    Text(L10n.t("Đang cập nhật chỉ mục…"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                if let search = pane.search, isContentOnlyZeroResults(search) {
                    Text(L10n.t("Spotlight có thể chưa lập chỉ mục nội dung ở đây"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
            } else if !pane.filterText.isEmpty || model.filterFocusRequest == pane.id {
                filterRow
            }
        }
        .onChange(of: pane.search?.text) { _, newValue in
            if let newValue { searchText = newValue }
        }
        .onChange(of: model.filterFocusRequest) { _, newValue in
            guard newValue == pane.id else { return }
            filterFieldFocused = true
            model.filterFocusRequest = nil
        }
        .onChange(of: pane.search?.scope) { _, _ in refreshIndexingState() }
        .onChange(of: pane.search == nil) { _, _ in refreshIndexingState() }
        .task(id: indexingRefreshKey) { await refreshIndexingStateAsync() }
    }

    /// Re-evaluated whenever the search's scope, running state, or whether a search exists at all changes — the
    /// `.task(id:)` above restarts its lookup each time this key changes, same pattern `FileListView`'s own async
    /// lookups use for "don't poll continuously, just re-check on the events that could change the answer".
    private var indexingRefreshKey: String {
        guard let search = pane.search else { return "none" }
        return "\(search.scope.rawValue)|\(search.running)"
    }

    private func refreshIndexingState() {
        Task { await refreshIndexingStateAsync() }
    }

    private func refreshIndexingStateAsync() async {
        guard let search = pane.search else {
            indexing = false
            return
        }
        let paneFolders = search.scope == .panes ? model.tree.panes.compactMap { model.panes[$0]?.path } : []
        let folders = pane.searchScopeFolderPaths(for: search.scope, paneFolders: paneFolders)
        indexing = await BrowserWindowModel.scopeIsIndexing(folders: folders)
    }

    // MARK: - Filter (⌘F)

    private var filterRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundColor(.secondary)
                .font(XFinderTokens.Font.caption)
            TextField(L10n.t("Lọc trong thư mục này"), text: Binding(
                get: { pane.filterText },
                set: { pane.filterText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(XFinderTokens.Font.rowValue)
            .focused($filterFieldFocused)
            Button {
                pane.filterText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, XFinderTokens.Space.tight)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).fill(XFinderTokens.Fill.inset))
    }

    // MARK: - Search (⌥⌘F)

    private var searchRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(XFinderTokens.Font.caption)
            TextField(L10n.t("Tìm kiếm…"), text: $searchText)
                .textFieldStyle(.plain)
                .font(XFinderTokens.Font.rowValue)
                .onSubmit {
                    model.runSearch(searchText, scope: pane.search?.scope ?? BrowserWindowModel.resolvedDefaultSearchScope())
                }
            if let search = pane.search, search.running {
                ProgressView().controlSize(.small)
            }
            if let search = pane.search, !search.results.isEmpty {
                Text(resultCountLabel(search))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            scopePicker
            saveSearchButton
            Button {
                pane.endSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, XFinderTokens.Space.tight)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).fill(XFinderTokens.Fill.inset))
    }

    /// FileOctopus: "Open Panes" only ever appears once there is more than one pane to span (contract §1, 3 scopes
    /// "This Mac / Current Folder / Open Panes") — a lone-pane window never offers a scope choice that cannot
    /// differ from "Current Folder".
    private var scopePicker: some View {
        Picker("", selection: Binding(
            get: { pane.search?.scope ?? BrowserWindowModel.resolvedDefaultSearchScope() },
            set: { model.runSearch(searchText, scope: $0) }
        )) {
            Text(L10n.t("Thư mục hiện tại")).tag(PaneSearchState.Scope.folder)
            Text(L10n.t("Máy này")).tag(PaneSearchState.Scope.mac)
            if model.tree.panes.count > 1 {
                Text(L10n.t("Các ngăn đang mở")).tag(PaneSearchState.Scope.panes)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 150)
    }

    private var saveSearchButton: some View {
        Button {
            showSaveSearch = true
        } label: {
            Image(systemName: "bookmark")
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .disabled(pane.search == nil || (pane.search?.text.isEmpty ?? true))
        .popover(isPresented: $showSaveSearch) {
            SaveSearchPopover(pane: pane, model: model) { showSaveSearch = false }
        }
    }

    private func resultCountLabel(_ search: PaneSearchState) -> String {
        let n = search.results.count
        return search.truncated ? "\(n)+" : "\(n)"
    }

    /// Contract: a `content:`-only search (no other chip/term/phrase) with zero results gets a one-line note instead
    /// of looking exactly like "không có gì ở đây" — Spotlight's content index can simply be missing.
    private func isContentOnlyZeroResults(_ search: PaneSearchState) -> Bool {
        guard !search.running, search.results.isEmpty else { return false }
        let parsed = search.parsed
        guard parsed.terms.isEmpty, parsed.phrases.isEmpty, parsed.excluded.isEmpty else { return false }
        guard parsed.chips.count == 1, parsed.chips[0].field == .content else { return false }
        return true
    }

    // MARK: - Warnings (XF-T37 L4)

    /// One line per thing that was not used as typed — FileOctopus 1.0.10 says each of these; before XF-T37 XFinder
    /// computed one generic key and showed nothing, so a typo looked exactly like "no results".
    private func warningsRow(_ warnings: [SearchWarning]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Label(warningText(warning), systemImage: "exclamationmark.triangle")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func warningText(_ warning: SearchWarning) -> String {
        if let trailing = warning.trailingKey {
            return "\(L10n.t(warning.messageKey))\(warning.subject)\(L10n.t(trailing))"
        }
        if warning.quotesSubject {
            let subject = warning.kind == .unknownFilter || warning.kind == .emptyValue ? warning.subject + ":" : warning.subject
            return "“\(subject)” \(L10n.t(warning.messageKey))"
        }
        return L10n.t(warning.messageKey)
    }

    // MARK: - Chips

    private func chipsRow(_ parsed: ParsedSearch) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: XFinderTokens.Space.tight) {
                ForEach(parsed.chips) { chip in
                    chipView(chip)
                }
            }
        }
    }

    private func chipView(_ chip: SearchChip) -> some View {
        HStack(spacing: 4) {
            Text(label(for: chip))
                .font(XFinderTokens.Font.caption)
            Button {
                guard let search = pane.search else { return }
                let remaining = SearchQuery.removing(chip: chip.id, from: search.parsed)
                pane.runSearch(parsed: remaining, scope: search.scope)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, XFinderTokens.Space.tight)
        .padding(.vertical, 2)
        .background(Capsule().fill(XFinderTokens.Fill.inset))
        .onTapGesture {
            editingChip = chip
        }
        .popover(item: Binding(
            get: { editingChip?.id == chip.id ? editingChip : nil },
            set: { editingChip = $0 }
        )) { editing in
            ChipEditorPopover(chip: editing) { updated in
                guard let search = pane.search else { return }
                let replaced = SearchQuery.replacing(id: chip.id, with: updated, in: search.parsed)
                pane.runSearch(parsed: replaced, scope: search.scope)
                editingChip = nil
            }
        }
    }

    /// Vietnamese label for one chip, per field/value (contract: "label per field/value in Vietnamese via L10n.t;
    /// uncertain ⇒ '?' suffix").
    private func label(for chip: SearchChip) -> String {
        var base: String
        switch chip.value {
        case .kind(let kind):
            base = kindLabel(kind)
        case .date(let range):
            base = dateLabel(range)
        case .size(let op, let bytes):
            base = "\(sizeOpLabel(op)) \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        case .text(let text):
            base = "\(fieldLabel(chip.field)): \(text)"
        }
        return chip.uncertain ? base + " ?" : base
    }

    private func kindLabel(_ kind: KindFilter) -> String {
        switch kind {
        case .pdfs: return L10n.t("PDF")
        case .images: return L10n.t("Ảnh")
        case .videos: return L10n.t("Video")
        case .audio: return L10n.t("Âm thanh")
        case .documents: return L10n.t("Tài liệu")
        case .spreadsheets: return L10n.t("Bảng tính")
        case .presentations: return L10n.t("Bản trình chiếu")
        case .archives: return L10n.t("Tệp nén")
        case .folders: return L10n.t("Thư mục")
        case .applications: return L10n.t("Ứng dụng")
        case .screenshots: return L10n.t("Ảnh chụp màn hình")
        case .code: return L10n.t("Mã nguồn")
        case .text: return L10n.t("Văn bản")
        }
    }

    private func dateLabel(_ range: DateRange) -> String {
        switch range {
        case .today: return L10n.t("Hôm nay")
        case .yesterday: return L10n.t("Hôm qua")
        case .thisWeek: return L10n.t("Tuần này")
        case .lastWeek: return L10n.t("Tuần trước")
        case .thisMonth: return L10n.t("Tháng này")
        case .lastMonth: return L10n.t("Tháng trước")
        case .thisYear: return L10n.t("Năm nay")
        case .lastYear: return L10n.t("Năm ngoái")
        case .pastDays(let n): return "\(n)\(L10n.t(" ngày qua"))"
        case .olderThanDays(let n): return "\(L10n.t("Cũ hơn "))\(n)\(L10n.t(" ngày"))"
        case .month(let year, let month): return "\(month)/\(year)"
        case .within(let n, let unit): return "\(L10n.t("Trong "))\(n)\(withinUnit(unit))"
        case .olderThan(let n, let unit): return "\(L10n.t("Cũ hơn "))\(n)\(plainUnit(unit))"
        case .day(let d): return d.text
        case .span(let a, let b): return "\(a.text) – \(b.text)"
        }
    }

    /// " ngày qua" … — "Trong 7 ngày qua" / "In the last 7 days".
    private func withinUnit(_ unit: DateUnit) -> String {
        switch unit {
        case .day: return L10n.t(" ngày qua")
        case .week: return L10n.t(" tuần qua")
        case .month: return L10n.t(" tháng qua")
        case .year: return L10n.t(" năm qua")
        }
    }

    /// " ngày" … — "Cũ hơn 2 tuần" / "Older than 2 weeks".
    private func plainUnit(_ unit: DateUnit) -> String {
        switch unit {
        case .day: return L10n.t(" ngày")
        case .week: return L10n.t(" tuần")
        case .month: return L10n.t(" tháng")
        case .year: return L10n.t(" năm")
        }
    }

    private func fieldLabel(_ field: SearchChip.Field) -> String {
        switch field {
        case .kind: return L10n.t("Loại")
        case .modified: return L10n.t("Sửa đổi")
        case .created: return L10n.t("Tạo lúc")
        case .size: return L10n.t("Cỡ")
        case .source: return L10n.t("Nguồn")
        case .ext: return L10n.t("Đuôi")
        case .tag: return L10n.t("Thẻ")
        case .content: return L10n.t("Nội dung")
        case .folder: return L10n.t("Trong")
        }
    }

    private func sizeOpLabel(_ op: SizeOp) -> String {
        switch op {
        case .greater: return L10n.t("Lớn hơn")
        case .less: return L10n.t("Nhỏ hơn")
        case .greaterOrEqual: return L10n.t("Từ")
        case .lessOrEqual: return L10n.t("Tối đa")
        case .equal: return L10n.t("Bằng")
        }
    }
}

/// A chip's popover editor: date presets for a `.date` chip, size op + value + unit for a `.size` chip. Other
/// chip kinds (kind/text) have nothing to tune beyond removing them, so the popover just confirms/cancels.
private struct ChipEditorPopover: View {
    let chip: SearchChip
    let onReplace: (SearchChip) -> Void

    @State private var sizeOp: SizeOp
    @State private var sizeValue: String
    @State private var sizeUnit: String

    init(chip: SearchChip, onReplace: @escaping (SearchChip) -> Void) {
        self.chip = chip
        self.onReplace = onReplace
        if case .size(let op, let bytes) = chip.value {
            _sizeOp = State(initialValue: op)
            let mb = Double(bytes) / (1024 * 1024)
            _sizeValue = State(initialValue: String(format: "%.0f", mb))
            _sizeUnit = State(initialValue: "MB")
        } else {
            _sizeOp = State(initialValue: .equal)
            _sizeValue = State(initialValue: "")
            _sizeUnit = State(initialValue: "MB")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            switch chip.value {
            case .date:
                datePresets
            case .size:
                sizeEditor
            default:
                Text(L10n.t("Không có tuỳ chọn khác"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(XFinderTokens.Space.row)
        .frame(minWidth: 200)
    }

    private var datePresets: some View {
        let presets: [(String, DateRange)] = [
            (L10n.t("Hôm nay"), .today), (L10n.t("Hôm qua"), .yesterday),
            (L10n.t("Tuần này"), .thisWeek), (L10n.t("Tuần trước"), .lastWeek),
            (L10n.t("Tháng này"), .thisMonth), (L10n.t("Tháng trước"), .lastMonth),
            (L10n.t("Năm nay"), .thisYear), (L10n.t("Năm ngoái"), .lastYear),
        ]
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                Button(preset.0) {
                    onReplace(SearchChip(field: chip.field, value: .date(preset.1), uncertain: false))
                }
                .buttonStyle(.plain)
                .font(XFinderTokens.Font.rowValue)
            }
        }
    }

    private var sizeEditor: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Picker(L10n.t("So sánh"), selection: $sizeOp) {
                Text(L10n.t("Lớn hơn")).tag(SizeOp.greater)
                Text(L10n.t("Nhỏ hơn")).tag(SizeOp.less)
                Text(L10n.t("Từ")).tag(SizeOp.greaterOrEqual)
                Text(L10n.t("Tối đa")).tag(SizeOp.lessOrEqual)
                Text(L10n.t("Bằng")).tag(SizeOp.equal)
            }
            .pickerStyle(.menu)
            HStack {
                TextField(L10n.t("Giá trị"), text: $sizeValue)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $sizeUnit) {
                    Text("KB").tag("KB")
                    Text("MB").tag("MB")
                    Text("GB").tag("GB")
                    Text("TB").tag("TB")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 70)
            }
            Button(L10n.t("Áp dụng")) {
                guard let value = Double(sizeValue) else { return }
                let multiplier: Double
                switch sizeUnit {
                case "KB": multiplier = 1024
                case "MB": multiplier = 1024 * 1024
                case "GB": multiplier = 1024 * 1024 * 1024
                case "TB": multiplier = 1024 * 1024 * 1024 * 1024
                default: multiplier = 1
                }
                let bytes = Int64(value * multiplier)
                onReplace(SearchChip(field: chip.field, value: .size(sizeOp, bytes), uncertain: false))
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// XF-T30 W5b — "Lưu tìm kiếm…": name + "Thêm vào sidebar" (contract §"Tìm đã lưu"). `BrowserSidebarView` (a
/// different builder's file) is the thing that actually renders a saved search's sidebar row; this popover only
/// writes the entry into `BrowserSettings.savedSearches` via `BrowserWindowModel.saveCurrentSearch`.
private struct SaveSearchPopover: View {
    let pane: PaneState
    let model: BrowserWindowModel
    let onDone: () -> Void

    @State private var name = ""
    @State private var addToSidebar = true

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Lưu tìm kiếm…"))
                .font(XFinderTokens.Font.row)
            TextField(L10n.t("Tên"), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
            Toggle(L10n.t("Thêm vào sidebar"), isOn: $addToSidebar)
            HStack {
                Spacer()
                Button(L10n.t("Huỷ")) { onDone() }
                Button(L10n.t("Lưu")) {
                    pane.saveCurrentSearch(name: name, addToSidebar: addToSidebar)
                    onDone()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(XFinderTokens.Space.row)
        .onAppear {
            if name.isEmpty { name = pane.search?.text ?? "" }
        }
    }
}
