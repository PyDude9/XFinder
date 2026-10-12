import SwiftUI
import AppKit

/// D3 "Thư viện Clipboard" — the sidebar page for finding an OLD clip, beyond the 4 cards the notch
/// shows: filter by type / source app / board / time, inspect it, then paste / pin / delete.
/// Layout B (project owner's choice): a 180-pt filter rail on the left, a grid filling the rest,
/// and a 320-pt inspector that slides in from the right over the grid.
///
/// Piece C of a three-piece contract (A = `ClipboardLibrary` pure rules, B = `ClipboardLibraryStore`).
/// Written against the contract only — A and B were written in parallel and are not read here.
struct ClipboardLibraryView: View {
    @Environment(ClipboardManager.self) private var clipboardManager
    private var store: ClipboardLibraryStore { ClipboardLibraryStore.shared }

    @State private var appsExpanded = false
    @FocusState private var searchFocused: Bool
    @State private var gridColumns: Int = 1
    @State private var noticeVisible = false
    @State private var noticeWorkItem: DispatchWorkItem?
    /// D4 — "Khoá bảng này…" confirmation (the honest explanation from the brief, not a generic
    /// "are you sure?"). Identified by the board itself so re-tapping another board's lock row reuses
    /// the same alert state cleanly.
    @State private var pendingLockBoard: Pinboard?

    private let railWidth: CGFloat = 180
    private let inspectorWidth: CGFloat = 320
    private let cardMinWidth: CGFloat = 190
    private let cardHeight: CGFloat = 146

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                icon: "tray.full",
                title: L10n.t("Thư viện Clipboard"),
                subtitle: L10n.t("Tìm một mục cũ trong toàn bộ lịch sử, lọc theo loại, ứng dụng, bảng hoặc thời gian.")
            )

            HStack(spacing: 0) {
                FilterRail(store: store, appsExpanded: $appsExpanded, pendingLockBoard: $pendingLockBoard)
                    .frame(width: railWidth)
                    .padding(.leading, XFinderTokens.Space.page)

                Divider().padding(.vertical, XFinderTokens.Space.tight)

                ZStack(alignment: .trailing) {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        header
                        if store.isLockedBoard(store.query.scope) { lockedBoardBanner }
                        LibraryGrid(
                            store: store,
                            clipboardManager: clipboardManager,
                            columns: $gridColumns,
                            cardMinWidth: cardMinWidth,
                            cardHeight: cardHeight
                        )
                        footer
                    }
                    .padding(.horizontal, XFinderTokens.Space.inline)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    if store.inspectorOpen, let selected = store.selected {
                        LibraryInspector(store: store, rawRecord: selected, width: inspectorWidth)
                            .frame(width: inspectorWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .animation(XFinderTokens.Motion.surface, value: store.inspectorOpen)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

            if let notice = store.notice, noticeVisible {
                Text(L10n.t(notice))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, XFinderTokens.Space.page)
                    .padding(.bottom, XFinderTokens.Space.tight)
            }

            // Hidden Cmd-F focus trigger — the field itself lives in the header.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .pageWidthSafe()
        .background(XFinderTokens.Fill.window)
        .onAppear {
            store.unlockReason = L10n.t("Mở khoá clip trong bảng đã khoá")
            store.reload()
        }
        .onDisappear { store.relockAll() }
        .onChange(of: clipboardManager.history.first?.id) { _, _ in store.reload() }
        .onChange(of: store.notice) { _, newValue in
            noticeWorkItem?.cancel()
            guard newValue != nil else { noticeVisible = false; return }
            noticeVisible = true
            let work = DispatchWorkItem { noticeVisible = false; store.notice = nil }
            noticeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
        }
        .alert(item: $pendingLockBoard) { board in
            Alert(
                title: Text("\(L10n.t("Khoá bảng "))“\(board.name)”?"),   // the name is a proper noun; never inside a key
                message: Text(lockConfirmationMessage),
                primaryButton: .destructive(Text(L10n.t("Khoá bảng"))) { store.lockBoard(board) },
                secondaryButton: .cancel(Text(L10n.t("Hủy")))
            )
        }
    }

    /// The honest explanation (Part 0 §6 + the brief): what the lock protects against, what it does
    /// not, where the key lives, and that export skips locked clips. Every claim here must be true of
    /// `BoardLock`/`BoardLockKeys` — nothing here may promise more than the code does.
    private var lockConfirmationMessage: String {
        [
            L10n.t("Mỗi clip trong bảng sẽ được mã hoá bằng một khoá riêng của Mac này, lưu trong Secure Enclave."),
            L10n.t("Khoá này chống bị nhìn trộm, chống đọc được nếu ai đó sao chép tệp xfinder.db, và bị loại khỏi MCP cũng như khi xuất file."),
            L10n.t("Nó KHÔNG chống lại người đã có phiên đăng nhập của bạn VÀ vượt qua được Touch ID."),
            L10n.t("Khoá chỉ tồn tại trong Secure Enclave của Mac này — nếu Mac này hỏng, các clip đã khoá sẽ mất vĩnh viễn.")
        ].joined(separator: "\n\n")
    }

    // MARK: Header — search, sort, period

    private var header: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(L10n.t("Tìm… (⌘F, @ảnh @link …)"), text: Binding(
                    get: { store.query.text },
                    set: { store.query.text = $0 }
                ))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // Esc while typing (review): clear the query first, then close the inspector, then
                // leave the field — the grid's own Esc handler is not in the focus chain here.
                .onExitCommand {
                    if !store.query.text.isEmpty { store.query.text = "" }
                    else if store.inspectorOpen { store.closeInspector() }
                    else { searchFocused = false }
                }
                if !store.query.text.isEmpty {
                    Button { store.query.text = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, XFinderTokens.Space.inline)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(XFinderTokens.Fill.inset))
            .frame(minWidth: 0, maxWidth: .infinity)

            Picker("", selection: Binding(get: { store.query.sort }, set: { store.query.sort = $0 })) {
                Text(L10n.t("Mới nhất")).tag(ClipboardLibrary.Sort.newest)
                Text(L10n.t("Cũ nhất")).tag(ClipboardLibrary.Sort.oldest)
                Text(L10n.t("Theo ứng dụng")).tag(ClipboardLibrary.Sort.byApp)
                Text(L10n.t("Theo loại")).tag(ClipboardLibrary.Sort.byType)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)

            Picker("", selection: Binding(get: { store.query.period }, set: { store.query.period = $0 })) {
                Text(L10n.t("Mọi lúc")).tag(ClipboardLibrary.Period.any)
                Text(L10n.t("Hôm nay")).tag(ClipboardLibrary.Period.today)
                Text(L10n.t("7 ngày")).tag(ClipboardLibrary.Period.week)
                Text(L10n.t("30 ngày")).tag(ClipboardLibrary.Period.month)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 110)
        }
        .padding(.top, XFinderTokens.Space.tight)
    }

    // MARK: Locked-board banner (D4, wireframe B)

    private var lockedBoardBanner: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "lock.fill").foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("Bảng này đang khoá"))
                    .font(XFinderTokens.Font.row.weight(.semibold))
                Text(L10n.t("Mỗi thẻ sẽ hỏi Touch ID riêng; nội dung chỉ được giải mã trong bộ nhớ cho tới khi bạn rời trang này."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(XFinderTokens.Space.inline)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).fill(XFinderTokens.Fill.inset))
    }

    // MARK: Footer — count + load more

    @ViewBuilder private var footer: some View {
        let filteredCount = store.filtered.count
        let visibleCount = store.visible.count
        HStack(spacing: XFinderTokens.Space.inline) {
            if store.isLoading && store.records.isEmpty {
                Text(L10n.t("Đang nạp lịch sử…"))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            } else if filteredCount == 0 {
                Text(L10n.t("Không có mục nào khớp."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            } else {
                Text("\(L10n.t("Hiện "))1–\(visibleCount)\(L10n.t(" trong "))\(filteredCount)")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .monospacedDigit()
                if visibleCount < filteredCount {
                    Button(L10n.t("Tải thêm")) { store.loadMore() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, XFinderTokens.Space.tight)
    }
}

// MARK: - Filter rail

private struct FilterRail: View {
    var store: ClipboardLibraryStore
    @Binding var appsExpanded: Bool
    @Binding var pendingLockBoard: Pinboard?

    private var facets: ClipboardLibrary.Facets { store.facets }   // memoised in the store

    /// The tested contract for "is this title a store key or a user-authored name" (review: the rail
    /// had re-implemented it inline, leaving the pure functions and their tests dead).
    private func scopeTitle(_ scope: ClipboardLibrary.Scope) -> String {
        let key = ClipboardLibrary.scopeTitleKey(scope, boards: store.boards)
        return ClipboardLibrary.scopeTitleIsKey(scope) ? L10n.t(key) : key
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel(L10n.t("LỌC"))
                    railRow(title: scopeTitle(.all), count: facets.total, on: store.query.scope == .all) {
                        store.query.scope = .all
                    }
                    railRow(title: scopeTitle(.pinned), count: facets.pinned, on: store.query.scope == .pinned) {
                        store.query.scope = .pinned
                    }
                }

                if !facets.byType.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel(L10n.t("LOẠI"))
                        ForEach(ContentType.allCases.filter { (facets.byType[$0] ?? 0) > 0 }) { t in
                            railRow(title: scopeTitle(.type(t)), count: facets.byType[t] ?? 0,
                                    on: store.query.scope == .type(t)) {
                                store.query.scope = .type(t)
                            }
                        }
                    }
                }

                if !facets.apps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel(L10n.t("ỨNG DỤNG"))
                        let shown = appsExpanded ? facets.apps : Array(facets.apps.prefix(8))
                        ForEach(shown, id: \.bundleID) { app in
                            railRow(title: app.name.isEmpty ? L10n.t("Không rõ") : app.name, count: app.count,
                                    on: store.query.scope == .app(app.bundleID)) {
                                store.query.scope = .app(app.bundleID)
                            }
                        }
                        if facets.apps.count > 8 {
                            Button(appsExpanded ? L10n.t("Thu gọn") : L10n.t("Thêm…")) {
                                appsExpanded.toggle()
                            }
                            .buttonStyle(.plain)
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.accentColor)
                            .padding(.vertical, 3)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel(L10n.t("BẢNG"))
                    ForEach(store.boards) { b in
                        boardRow(b, count: facets.byBoard[b.id] ?? 0, on: store.query.scope == .board(b.id)) {
                            store.query.scope = .board(b.id)
                        }
                    }
                    Button(L10n.t("+ Bảng mới")) {
                        AppState.shared.navigate(to: .settingsClipboard)
                    }
                    .buttonStyle(.plain)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 3)
                }
            }
            .padding(.vertical, XFinderTokens.Space.tight)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(XFinderTokens.Font.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.vertical, 3)
    }

    private func railRow(title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(title)
                    .font(XFinderTokens.Font.row)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text(count.formatted())
                    .font(XFinderTokens.Font.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, XFinderTokens.Space.tight)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(on ? XFinderTokens.Fill.hover : .clear))
        }
        .buttonStyle(.plain)
    }

    /// D4 — a board row with a lock glyph when locked, and a context menu to lock / unlock it. Disabled
    /// with an explanation when the Secure Enclave is unavailable, so the menu item never promises a
    /// lock the hardware cannot actually create.
    private func boardRow(_ b: Pinboard, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: XFinderTokens.Space.tight) {
                if b.isLocked {
                    Image(systemName: "lock.fill").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                Text(scopeTitle(.board(b.id)))
                    .font(XFinderTokens.Font.row)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text(count.formatted())
                    .font(XFinderTokens.Font.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, XFinderTokens.Space.tight)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(on ? XFinderTokens.Fill.hover : .clear))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if b.isLocked {
                Button(L10n.t("Gỡ khoá (giải mã lại)")) { store.unlockBoardPermanently(b) }
            } else if BoardLockKeys.isAvailable {
                Button(L10n.t("Khoá bảng này…")) { pendingLockBoard = b }
            } else {
                Text(L10n.t("Không khoá được — máy này không có Secure Enclave."))
            }
        }
    }
}

// MARK: - Grid

private struct LibraryGrid: View {
    var store: ClipboardLibraryStore
    var clipboardManager: ClipboardManager
    @Binding var columns: Int
    let cardMinWidth: CGFloat
    let cardHeight: CGFloat
    /// The key handlers below only fire while this view has focus (review, split verdict: a card is an
    /// `.onTapGesture`, so nothing guaranteed the grid ever became first responder). Selecting a card
    /// and appearing both take focus explicitly.
    @FocusState private var gridFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = XFinderTokens.Space.row
            let computedColumns = max(1, Int((geo.size.width + spacing) / (cardMinWidth + spacing)))
            let items = store.visible
            ScrollView {
                if items.isEmpty {
                    emptyOrLoading
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: computedColumns),
                              spacing: spacing) {
                        ForEach(items) { record in
                            ClipboardCardView(
                                record: store.display(record),
                                selected: store.selectedID == record.id,
                                onSelect: {
                                    store.select(record.id)
                                    gridFocused = true
                                    // A still-locked card's tap is the unlock gesture (Touch ID), not a
                                    // selection-only click — the user is already asking to see it.
                                    if record.isLocked { store.unlock(record) }
                                },
                                onPreview: { store.quickLook(record) },
                                lockedHint: L10n.t("Bấm để mở khoá (Touch ID)")
                            )
                            .frame(height: cardHeight)
                        }
                    }
                    .padding(.bottom, XFinderTokens.Space.row)
                }
            }
            .focusable()
            .focused($gridFocused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { move(.left, columns: computedColumns); return .handled }
            .onKeyPress(.rightArrow) { move(.right, columns: computedColumns); return .handled }
            .onKeyPress(.upArrow) { move(.up, columns: computedColumns); return .handled }
            .onKeyPress(.downArrow) { move(.down, columns: computedColumns); return .handled }
            .onKeyPress(.return, phases: .down) { press in
                handleReturn(plainText: press.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(.space) {
                if let r = store.selected { store.quickLook(r) }
                return .handled
            }
            .onKeyPress(.escape) {
                guard store.inspectorOpen else { return .ignored }
                store.closeInspector()
                return .handled
            }
            .onKeyPress(.delete, phases: .down) { press in   // ⌘⌫ (standard Backspace key)
                guard press.modifiers.contains(.command), let r = store.selected else { return .ignored }
                store.delete(r)
                return .handled
            }
            .onKeyPress(.deleteForward, phases: .down) { press in   // Fn+Delete, same ⌘ combo on keyboards that have it
                guard press.modifiers.contains(.command), let r = store.selected else { return .ignored }
                store.delete(r)
                return .handled
            }
            .onChange(of: computedColumns) { _, newValue in columns = newValue }
            .onAppear { columns = computedColumns; gridFocused = true }
        }
    }

    @ViewBuilder private var emptyOrLoading: some View {
        if store.isLoading && store.records.isEmpty {
            VStack { Text(L10n.t("Đang nạp lịch sử…")).font(XFinderTokens.Font.row).foregroundColor(.secondary) }
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            VStack { Text(L10n.t("Không có mục nào khớp.")).font(XFinderTokens.Font.row).foregroundColor(.secondary) }
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func move(_ direction: ClipboardLibrary.MoveDirection, columns: Int) {
        store.move(direction, columns: columns)
    }

    private func handleReturn(plainText: Bool) {
        guard let r = store.selected else { return }
        store.pasteIntoPreviousApp(r, plainText: plainText)
    }
}

// MARK: - Inspector

private struct LibraryInspector: View {
    var store: ClipboardLibraryStore
    /// The row as stored — may still be locked. `record` below is the DISPLAY version.
    let rawRecord: ClipboardRecord
    let width: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var record: ClipboardRecord { store.display(rawRecord) }
    private var stillLocked: Bool { rawRecord.isLocked }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(record.type.titleVI)
                    .font(XFinderTokens.Font.sectionTitle)
                Spacer()
                Button { store.closeInspector() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(XFinderTokens.Space.inline)

            Divider()

            if stillLocked {
                lockedBody
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        preview
                        Divider()
                        metaRows
                        Divider()
                        actions
                    }
                    .padding(XFinderTokens.Space.inline)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(XFinderTokens.Fill.surface)
        .overlay(Rectangle().frame(width: 1).foregroundColor(XFinderTokens.Fill.hairline), alignment: .leading)
        .shadow(color: .black.opacity(0.12), radius: 12, x: -2, y: 0)
    }

    // MARK: Locked placeholder (D4)

    private var lockedBody: some View {
        VStack(spacing: XFinderTokens.Space.row) {
            Spacer(minLength: 0)
            Image(systemName: "lock.fill").font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
            Text(L10n.t("Đã khoá")).font(XFinderTokens.Font.row)
            Button(L10n.t("Mở khoá (Touch ID)")) { store.unlock(rawRecord) }
                .buttonStyle(.borderedProminent)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(XFinderTokens.Space.inline)
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        let height: CGFloat = 190
        switch record.type {
        case .image:
            // A row just unlocked in memory has no payload/thumbnail PATH (those live only on disk for
            // plain rows) — `store.unlockedImage` reads the decrypted bytes directly for that case.
            if let img = store.unlockedImage(rawRecord)
                ?? (record.payloadPath ?? record.thumbnailPath).flatMap(NSImage.init(contentsOfFile:)) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: height)
                    .background(XFinderTokens.Fill.inset)
                    .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile))
            } else {
                placeholderPreview(icon: "photo", height: height)
            }
        case .color:
            if let ns = ClipboardClassifier.color(from: record.displayPreview) {
                VStack(spacing: XFinderTokens.Space.tight) {
                    RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).fill(Color(ns))
                        .frame(maxWidth: .infinity, maxHeight: height - 30)
                    Text(record.displayPreview.uppercased())
                        .font(XFinderTokens.Font.mono.weight(.bold))
                }
            } else {
                placeholderPreview(icon: "paintpalette", height: height)
            }
        case .link:
            let urlStr = record.metadata["url"]?.isEmpty == false ? record.metadata["url"]! : record.displayPreview
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                if let title = record.customTitle, !title.isEmpty {
                    Text(title).font(XFinderTokens.Font.row)
                }
                Text(urlStr)
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.accentColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .padding(XFinderTokens.Space.inline)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).fill(XFinderTokens.Fill.inset))
        case .code:
            ScrollView {
                HighlightedCodeText(text: store.fullText(of: record) ?? record.displayPreview,
                                     font: .system(size: 12, design: .monospaced),
                                     dark: colorScheme == .dark, lineLimit: 400, maxLines: 400)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(XFinderTokens.Space.inline)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).fill(XFinderTokens.Fill.inset))
        case .file:
            placeholderPreview(icon: "doc.fill", height: height, caption: record.displayPreview)
        case .text, .markdown, .merged:
            ScrollView {
                Text(store.fullText(of: record) ?? record.displayPreview)
                    .font(XFinderTokens.Font.rowValue)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(XFinderTokens.Space.inline)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).fill(XFinderTokens.Fill.inset))
        }
    }

    private func placeholderPreview(icon: String, height: CGFloat, caption: String? = nil) -> some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: icon).font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary)
            if let caption {
                Text(caption).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).fill(XFinderTokens.Fill.inset))
    }

    // MARK: Meta rows

    @ViewBuilder private var metaRows: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            metaRow(L10n.t("Nguồn"), value: sourceValue)
            metaRow(L10n.t("Lúc"), value: record.timestamp.formatted(date: .abbreviated, time: .shortened))
            metaRow(L10n.t("Loại"), value: record.type.titleVI)
            if let size = sizeValue { metaRow(L10n.t("Kích thước"), value: size) }
            metaRow(L10n.t("Bảng"), value: boardsValue)
            metaRow(L10n.t("Đã dùng"), value: "\(record.usageCount)\(L10n.t(" lần"))")
        }
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: XFinderTokens.Space.inline) {
            Text(label)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(XFinderTokens.Font.rowValue)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var sourceValue: String {
        let name = record.sourceAppName ?? L10n.t("Không rõ")
        guard let bid = record.sourceBundleID, !bid.isEmpty else { return name }
        return "\(name) · \(bid)"
    }

    private var sizeValue: String? {
        switch record.type {
        case .text, .code, .markdown, .merged:
            guard let text = store.fullText(of: record) else { return nil }
            let lines = ClipboardLibrary.Facts.lines(in: text)
            let chars = ClipboardLibrary.Facts.characters(in: text)
            return "\(lines)\(L10n.t(" dòng · "))\(chars)\(L10n.t(" ký tự"))"
        case .image, .file:
            guard let path = store.fileURL(record)?.path,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let bytes = attrs[.size] as? Int64, bytes > 0 else { return nil }
            return ClipboardLibrary.Facts.sizeLabel(bytes: bytes)
        case .link, .color:
            return nil
        }
    }

    private var boardsValue: String {
        let names = store.boards.filter { ClipboardLibrary.isMember(record, of: $0) }.map(\.name)
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        VStack(spacing: XFinderTokens.Space.row) {
            Button {
                store.pasteIntoPreviousApp(record)
            } label: {
                Text("\(L10n.t("Dán vào app trước đó "))↩")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            let cols = [GridItem(.flexible(), spacing: XFinderTokens.Space.tight),
                        GridItem(.flexible(), spacing: XFinderTokens.Space.tight)]
            LazyVGrid(columns: cols, spacing: XFinderTokens.Space.tight) {
                Button(L10n.t("Sao chép")) { store.copy(record) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(record.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim")) { store.togglePin(record) }
                    .buttonStyle(.bordered).controlSize(.small)

                Menu(L10n.t("Bảng ▸")) {
                    ForEach(store.boards) { b in
                        let member = ClipboardLibrary.isMember(record, of: b)
                        Button {
                            store.toggleMembership(record, board: b)
                        } label: {
                            if member { Label(b.name, systemImage: "checkmark") } else { Text(b.name) }
                        }
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)

                transformMenu
            }

            Menu(L10n.t("Mở nguồn")) {
                if let bid = record.sourceBundleID, !bid.isEmpty {
                    Button("\(L10n.t("Mở "))\(record.sourceAppName ?? bid)") { store.openSourceApp(record) }
                }
                if store.sourcePageURL(record) != nil {
                    Button(L10n.t("Mở trang nguồn")) { store.openSourcePage(record) }
                }
                if store.fileURL(record) != nil {
                    Button(L10n.t("Hiện trong Finder")) { store.revealFile(record) }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(!hasAnySource)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: XFinderTokens.Space.tight) {
                Button("\(L10n.t("Xem nhanh "))(Space)") { store.quickLook(record) }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer(minLength: 0)
                Button(L10n.t("Xoá"), role: .destructive) { store.delete(record) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private var hasAnySource: Bool {
        (record.sourceBundleID?.isEmpty == false) || store.sourcePageURL(record) != nil || store.fileURL(record) != nil
    }

    @ViewBuilder private var transformMenu: some View {
        if let text = record.textSnippet, !text.isEmpty, record.type != .image, record.type != .file {
            Menu(L10n.t("Biến đổi ▸")) {
                ForEach(Array(ClipboardTransform.groups.enumerated()), id: \.offset) { i, group in
                    ForEach(group) { t in
                        Button(L10n.t(t.labelKey)) { store.applyTransform(t, to: record) }
                    }
                    if i < ClipboardTransform.groups.count - 1 { Divider() }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
        } else {
            Menu(L10n.t("Biến đổi ▸")) {}
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(true)
        }
    }
}
