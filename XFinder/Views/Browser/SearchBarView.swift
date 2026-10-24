import SwiftUI

/// XF-T28 cluster E — the strip under the location bar: the in-memory filter field (⌘F, `pane.filterText`) and the
/// natural-language search field (⌥⌘F, `pane.runSearch`) with its chips and scope picker. Only shown while one of
/// the two is active (filtering/searching) — contract: "PaneView: … SearchBarView (only when filtering/searching)".
struct SearchBarView: View {
    let pane: PaneState
    let model: BrowserWindowModel

    @State private var searchText: String = ""
    @State private var editingChip: SearchChip?

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
            } else if !pane.filterText.isEmpty {
                filterRow
            }
        }
        .onChange(of: pane.search?.text) { _, newValue in
            if let newValue { searchText = newValue }
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
                pane.runSearch(buildQueryText(removing: chip, from: search.parsed), scope: search.scope)
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
                pane.runSearch(SearchBarView.rebuildText(replaced), scope: search.scope)
                editingChip = nil
            }
        }
    }

    /// Chips are edited through `SearchQuery.replacing`/`removing` on the PARSED structure, but `pane.runSearch`
    /// takes raw text (contract: `PaneState.runSearch(_:scope:)`); re-running the ORIGINAL typed text keeps the
    /// pane's source of truth as the one text field. Removing a chip narrows what's shown by asking the engine to
    /// drop that one piece of structure and re-derive text-free of it is Cluster C's job once it stops stubbing
    /// `runSearch`; here we pass the already-edited parse forward via the chip's own vocabulary words so a plain
    /// re-run still reflects the removal for the common "field:value" phrasing.
    private func buildQueryText(removing chip: SearchChip, from search: ParsedSearch) -> String {
        let remaining = SearchQuery.removing(chip: chip.id, from: search)
        return SearchBarView.rebuildText(remaining)
    }

    /// Best-effort reconstruction of a plain query string from a `ParsedSearch` with one chip taken out — terms,
    /// phrases and exclusions already ARE text, so only chips (which the user typed as natural language) need a
    /// readable re-encoding to keep the field showing something sensible after a chip is removed.
    private static func rebuildText(_ parsed: ParsedSearch) -> String {
        var parts: [String] = parsed.terms
        parts.append(contentsOf: parsed.phrases.map { "\"\($0)\"" })
        parts.append(contentsOf: parsed.excluded.map { "-\($0)" })
        for chip in parsed.chips {
            switch chip.value {
            case .kind(let k): parts.append("kind:\(k.rawValue)")
            case .date(let range):
                if let token = dateQueryToken(range) {
                    parts.append("\(chip.field.rawValue):\(token)")
                }
                // A range with no `field:value` round trip (pastDays/olderThanDays/month) is dropped from the
                // rebuilt text rather than emitting a token `SearchQuery.parse` cannot read back — the edit that
                // removed a DIFFERENT chip must not silently reintroduce stale, unparsable text for this one.
            case .size(let op, let bytes): parts.append("size:\(sizeOpGlyph(op))\(bytes)")
            case .text(let t): parts.append("\(chip.field.rawValue):\(t)")
            }
        }
        return parts.joined(separator: " ")
    }

    /// Only the relative-keyword vocabulary `SearchQuery.parse`'s `field:value` syntax understands (same list as
    /// its private `parseDateToken`); other `DateRange` cases have no single-token spelling and are omitted above.
    private static func dateQueryToken(_ range: DateRange) -> String? {
        switch range {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .thisWeek: return "thisweek"
        case .lastWeek: return "lastweek"
        case .thisMonth: return "thismonth"
        case .lastMonth: return "lastmonth"
        case .thisYear: return "thisyear"
        case .lastYear: return "lastyear"
        case .pastDays, .olderThanDays, .month: return nil
        }
    }

    private static func sizeOpGlyph(_ op: SizeOp) -> String {
        switch op {
        case .greater: return ">"
        case .less: return "<"
        case .greaterOrEqual: return ">="
        case .lessOrEqual: return "<="
        case .equal: return ""
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
