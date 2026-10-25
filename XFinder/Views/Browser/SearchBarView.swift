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
    @FocusState private var filterFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            if pane.search != nil {
                searchRow
                if let search = pane.search, !search.parsed.chips.isEmpty {
                    chipsRow(search.parsed)
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
                    pane.runSearch(searchText, scope: pane.search?.scope ?? .folder)
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

    private var scopePicker: some View {
        Picker("", selection: Binding(
            get: { pane.search?.scope ?? .folder },
            set: { pane.runSearch(searchText, scope: $0) }
        )) {
            Text(L10n.t("Thư mục này")).tag(PaneSearchState.Scope.folder)
            Text(L10n.t("Máy này")).tag(PaneSearchState.Scope.mac)
            Text(L10n.t("Các ngăn")).tag(PaneSearchState.Scope.panes)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 120)
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
