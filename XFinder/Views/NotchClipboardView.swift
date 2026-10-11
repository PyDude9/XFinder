import SwiftUI
import AppKit

/// State of the notch's clipboard page. Owned by `NotchSurfaceController` so the keyboard handler and
/// the view share one selection. D0: this page IS the ⌘⇧V clipboard — the floating shelf's job
/// ("one clip from deep history: search, boards, keyboard, paste into the window I was in") moved here;
/// the rules it follows are `NotchClipboardRules`.
@MainActor
@Observable
final class NotchClipboardModel {
    /// Free text plus `@type` / `@app` tokens (`ClipboardFilterToken`).
    var query = ""
    var selectedID: UUID?
    /// The board menu: history / pinned / saved / suggestions / one custom board (⌘1–9).
    var scope: NotchClipboardRules.Scope = .history
    /// The chip row. A typed `@type` token filters too; the chips highlight whichever applies.
    var typeFilter: ContentType?
    /// One-line result of the last action (a store key), e.g. a transform that changed nothing.
    var notice: String?
    /// Touch ID lock (`clipboard.touchIDLock`): false until authenticated for THIS opening of the page.
    var unlocked = true
    /// The app ⌘⇧V was pressed in — pastes go back there. nil ⇒ `ClipboardManager.lastExternalPID`.
    var targetPID: pid_t?
    /// Mirrors the view's focus so the key monitor knows whether Space belongs to the field.
    var searchFocused = false
    /// Bumped by ⌘F; the view focuses the field when it changes.
    var focusSearchRequest = 0

    static let columns = 3
    /// Rendered cap. Two rows show; the rest scroll. The shelf rendered everything; 60 is plenty for a
    /// glance-and-grab surface and keeps the LazyVGrid cheap.
    static let cap = 60

    /// ⌘⇧V: a fresh session — filters reset, lock re-armed when the setting is on, paste target noted.
    func beginSession(lockOn: Bool, targetPID pid: pid_t?) {
        query = ""; typeFilter = nil; scope = .history; selectedID = nil; notice = nil
        targetPID = pid
        armLock(lockOn)
    }

    /// Opening the page any other way (tab, hover) also re-arms the lock: a lock that stays open
    /// after the page closed is no lock.
    func armLock(_ lockOn: Bool) { unlocked = !lockOn }

    func resetFilters() { query = ""; typeFilter = nil; scope = .history; selectedID = nil }

    var effectiveType: ContentType? { typeFilter ?? ClipboardFilterToken.parse(query).type }

    /// "Tất cả": drop the chip AND any `@type` token in the query, or the chip would lie.
    func clearTypeFilter() {
        typeFilter = nil
        query = query.split(separator: " ").filter { ClipboardFilterToken.parse(String($0)).type == nil }.joined(separator: " ")
    }

    /// Scope + app + text filters, NO type filter — what the chip counts are computed over.
    func scopedItems(from manager: ClipboardManager) -> [ClipboardRecord] {
        let parsed = ClipboardFilterToken.parse(query)
        var boardIDs: Set<UUID>?
        if case .board(let id) = scope, let b = manager.pinboards.first(where: { $0.id == id }) { boardIDs = Set(b.itemIDs) }
        var list = NotchClipboardRules.apply(scope: scope, boardItemIDs: boardIDs, to: manager.history)
        if parsed.app != nil {
            list = list.filter { ClipboardFilterToken.appMatches(token: parsed.app, appName: $0.sourceAppName, bundleID: $0.sourceBundleID) }
        }
        if !parsed.text.isEmpty {
            let q = parsed.text
            list = list.filter { r in
                (r.textSnippet?.localizedCaseInsensitiveContains(q) ?? false)
                    || (r.ocrText?.localizedCaseInsensitiveContains(q) ?? false)
                    || (r.customTitle?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        if scope == .suggestions {
            return ClipboardIntelligenceEngine.shared.rankSuggestions(from: list, forTargetPID: targetPID ?? manager.lastExternalPID, limit: Self.cap)
        }
        return list.sorted { $0.timestamp > $1.timestamp }
    }

    /// The deck: newest first, the type filter applied, capped.
    func items(from manager: ClipboardManager) -> [ClipboardRecord] {
        var list = scopedItems(from: manager)
        if let t = effectiveType { list = list.filter { $0.type == t } }
        return Array(list.prefix(Self.cap))
    }

    /// The selected record, or the first one — Return with nothing picked pastes the newest, as the shelf did.
    func selected(in items: [ClipboardRecord]) -> ClipboardRecord? {
        if let id = selectedID, let r = items.first(where: { $0.id == id }) { return r }
        return items.first
    }

    func isSelected(_ r: ClipboardRecord, in items: [ClipboardRecord]) -> Bool { selected(in: items)?.id == r.id }

    func move(_ d: NotchClipboardRules.Direction, in items: [ClipboardRecord]) {
        let i = items.firstIndex { $0.id == selectedID } ?? (selectedID == nil && !items.isEmpty ? 0 : nil)
        if let next = NotchClipboardRules.move(d, from: i, count: items.count, columns: Self.columns) { selectedID = items[next].id }
    }
}

/// The clipboard page inside the notch hub (wireframe B, 2026-10-11): search with `@filter` and the
/// board menu · a chip per content type with its count · a 3-column grid of `NotchClipCardView` ·
/// one footer line. Click pastes into the app the user came from; ⌘-click queues the Paste Stack;
/// right-click has every action the shelf had. Keys live in `NotchSurfaceController`'s monitor.
struct NotchClipboardView: View {
    var model: NotchClipboardModel
    @State private var manager = ClipboardManager.shared
    @FocusState private var searchFocused: Bool
    @State private var now = Date()

    private var scoped: [ClipboardRecord] { model.scopedItems(from: manager) }
    private var items: [ClipboardRecord] { model.items(from: manager) }
    private var locked: Bool { ClipboardShelfController.shared.touchIDLockEnabled && !model.unlocked }
    private static let gridHeight: CGFloat = 192

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            searchRow.disabled(locked).opacity(locked ? 0.35 : 1)
            chipRow.disabled(locked).opacity(locked ? 0.35 : 1)
            if locked { lockView }
            else if items.isEmpty { emptyView }
            else { grid }
            footer
        }
        .environment(manager)
        .onAppear { searchFocused = !locked; now = Date() }
        .onChange(of: searchFocused) { _, f in model.searchFocused = f }
        .onChange(of: model.focusSearchRequest) { searchFocused = true }
        .onChange(of: model.unlocked) { _, u in if u { searchFocused = true } }
    }

    // MARK: Row 2 — search + board menu

    private var searchRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(.white.opacity(0.65))
                TextField("", text: Bindable(model).query)
                    .textFieldStyle(.plain)
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.white)
                    .focused($searchFocused)
                    // Our own placeholder: the system one measured 1.1:1 on this black field (review row 1).
                    .overlay(alignment: .leading) {
                        if model.query.isEmpty {
                            Text(L10n.t("Tìm, hoặc @ảnh @link @tênapp…"))
                                .font(XFinderTokens.Font.rowValue).foregroundColor(.white.opacity(0.5))
                                .lineLimit(1).allowsHitTesting(false)
                        }
                    }
                if model.query.isEmpty {
                    keycap("⌘F")
                } else {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.65)) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.white.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control)
                .strokeBorder(searchFocused ? Color.accentColor : Color.clear, lineWidth: 1))

            boardMenu
        }
    }

    private func keycap(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
    }

    private var customBoards: [Pinboard] { manager.pinboards.filter { !$0.isBuiltIn } }

    private var scopeTitle: String {
        switch model.scope {
        case .history: return L10n.t("Lịch sử")
        case .pinned: return L10n.t("Đã ghim")
        case .saved: return L10n.t("Đã lưu")
        case .suggestions: return L10n.t("Gợi ý")
        case .board(let id): return manager.pinboards.first { $0.id == id }?.name ?? L10n.t("Bảng ghim")
        }
    }

    private var scopeDot: Color {
        switch model.scope {
        case .history: return .accentColor
        case .pinned: return .orange
        case .saved: return .white.opacity(0.65)
        case .suggestions: return .purple
        case .board(let id): return manager.pinboards.first { $0.id == id }?.color.color ?? .white
        }
    }

    private func menuTitle(_ title: String, count: Int, key: String?) -> String {
        key.map { "\(title) · \(count.formatted())   \($0)" } ?? "\(title) · \(count.formatted())"
    }

    private var boardMenu: some View {
        Menu {
            if ClipboardIntelligenceEngine.shared.isEnabled {
                Button { model.scope = .suggestions; model.selectedID = nil } label: {
                    Label("\(L10n.t("Gợi ý cho "))\(ClipboardIntelligenceEngine.shared.targetAppName(forTargetPID: model.targetPID ?? manager.lastExternalPID))",
                          systemImage: "sparkles")
                }
                Divider()
            }
            Button { model.scope = .history; model.selectedID = nil } label: {
                Label(menuTitle(L10n.t("Lịch sử Clipboard"), count: manager.history.count, key: "⌘1"), systemImage: "clock")
            }
            Button { model.scope = .pinned; model.selectedID = nil } label: {
                Label(menuTitle(L10n.t("Đã ghim"), count: manager.history.filter(\.isPinned).count, key: "⌘2"), systemImage: "pin")
            }
            Button { model.scope = .saved; model.selectedID = nil } label: {
                Label(menuTitle(L10n.t("Đã lưu"), count: manager.history.filter(\.isSavedSnippet).count, key: "⌘3"), systemImage: "bookmark")
            }
            let boards = customBoards
            if !boards.isEmpty {
                Divider()
                ForEach(Array(boards.enumerated()), id: \.element.id) { i, b in
                    Button { model.scope = .board(b.id); model.selectedID = nil } label: {
                        Label(menuTitle(b.name, count: b.itemIDs.count, key: i + 4 <= 9 ? "⌘\(i + 4)" : nil), systemImage: b.icon)
                    }
                }
            }
            Divider()
            Button { NotchSurfaceController.shared.openClipboardSettings() } label: {
                Label(L10n.t("Tạo bảng ghim mới"), systemImage: "plus")
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(scopeDot).frame(width: 8, height: 8)
                Text(scopeTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.65)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.white.opacity(0.10)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(L10n.t("Bảng ghim")) · ⌘1–9")
    }

    // MARK: Row 3 — type chips

    private var chipRow: some View {
        let list = scoped
        let chips = NotchClipboardRules.chips(from: NotchClipboardRules.typeCounts(list.map(\.type)))
        let effective = model.effectiveType
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                chip(label: L10n.t("Tất cả"), icon: nil, count: list.count, on: effective == nil, help: "") { model.clearTypeFilter() }
                ForEach(chips, id: \.type) { c in
                    chip(label: nil, icon: c.type.icon, count: c.count, on: effective == c.type, help: c.type.titleVI) {
                        model.typeFilter = c.type; model.selectedID = nil
                    }
                }
            }
        }
        .frame(height: 22)
    }

    private func chip(label: String?, icon: String?, count: Int, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                if let label { Text(label).font(.system(size: 11, weight: .semibold)) }
                Text(count.formatted()).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
            }
            .foregroundColor(on ? .black : .white.opacity(0.65))
            .padding(.horizontal, label == nil ? 5 : 7)
            .frame(height: 22)
            .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Row 4 — the grid, the lock, the empty state

    private var grid: some View {
        let list = items
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: NotchClipboardModel.columns), spacing: 8) {
                    ForEach(list) { record in
                        card(record, selected: model.isSelected(record, in: list)).id(record.id)
                    }
                }
            }
            .frame(height: Self.gridHeight)
            .onChange(of: model.selectedID) { _, id in
                if let id { withAnimation(.easeOut(duration: XFinderTokens.Motion.overlayIn)) { proxy.scrollTo(id) } }
            }
        }
    }

    private func card(_ record: ClipboardRecord, selected: Bool) -> some View {
        let stackIndex = manager.pasteStack.items.firstIndex(of: record).map { $0 + 1 }
        return NotchClipCardView(record: record, selected: selected, stackIndex: stackIndex, now: now)
            .onTapGesture { select(record) }
            .contextMenu { contextMenu(record) }
            .help("\(record.type.titleVI) · \(record.sourceAppName ?? "") · \(NotchClipCardView.ageLabel(record.timestamp, now: now))")
    }

    /// Plain click pastes; ⌘-click toggles the Paste Stack membership.
    private func select(_ record: ClipboardRecord) {
        model.selectedID = record.id
        if NSEvent.modifierFlags.contains(.command) {
            manager.togglePasteStackItem(record)
        } else {
            NotchSurfaceController.shared.pasteFromClipboardPage(record)
        }
    }

    private var lockView: some View {
        VStack(spacing: XFinderTokens.Space.tight + 2) {
            Image(systemName: "lock.fill").font(.system(size: 22)).opacity(0.65)
            Text(L10n.t("Xác thực bằng Touch ID hoặc mật khẩu để xem lịch sử clipboard"))
                .font(XFinderTokens.Font.rowValue).multilineTextAlignment(.center).opacity(0.65)
                .frame(maxWidth: 300)
            Button(L10n.t("Mở khóa Clipboard")) { NotchSurfaceController.shared.unlockClipboard() }
                .buttonStyle(NotchPillButtonStyle(primary: true))
        }
        .frame(maxWidth: .infinity).frame(height: Self.gridHeight)
    }

    private var emptyView: some View {
        VStack(spacing: XFinderTokens.Space.tight + 2) {
            if manager.history.isEmpty {
                Text(L10n.t("Chưa có gì trong clipboard.")).font(XFinderTokens.Font.rowValue).opacity(0.65)
            } else {
                Text(L10n.t("Không có mục nào khớp.")).font(XFinderTokens.Font.rowValue).opacity(0.65)
                Button(L10n.t("Đặt lại bộ lọc")) { model.resetFilters() }.buttonStyle(NotchPillButtonStyle(primary: false))
            }
        }
        .frame(maxWidth: .infinity).frame(height: Self.gridHeight)
    }

    // MARK: Row 5 — footer

    @ViewBuilder private var footer: some View {
        let decision = NotchClipboardRules.footer(pasteStackActive: manager.pasteStack.active,
                                                  remaining: manager.pasteStack.remaining,
                                                  interceptsCommandV: NotchSurfaceController.shared.pasteStackInterceptsCommandV,
                                                  notice: model.notice,
                                                  autoPaste: ClipboardShelfController.shared.autoPasteAfterSelection,
                                                  accessibilityTrusted: WindowManager.isTrusted)
        HStack(spacing: XFinderTokens.Space.tight) {
            switch decision {
            case .hints:
                if !locked {
                    Text(L10n.t("↩ dán · ⇧↩ thuần · Space xem · ⌘P ghim · ⌘⌫ xoá · ⌘1–9 bảng"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                }
            case .pasteStack(let remaining, let intercepts):
                Image(systemName: "square.stack.3d.up.fill").font(XFinderTokens.Font.caption).foregroundColor(.accentColor)
                let how = intercepts ? L10n.t("Mỗi ⌘V dán mục kế tiếp.") : L10n.t("Bấm Dán tiếp để dán từng mục.")
                Text("Paste Stack · \(remaining)\(L10n.t(" mục")) · \(how)")
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                Spacer(minLength: 4)
                Button(L10n.t("Dán tiếp")) { NotchSurfaceController.shared.pasteNextFromStack() }.buttonStyle(NotchPillButtonStyle(primary: true))
                Button(L10n.t("Hủy")) { manager.stopPasteStack() }.buttonStyle(NotchPillButtonStyle(primary: false))
            case .notice(let key):
                Text(L10n.t(key)).font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65)).lineLimit(1)
            case .accessibilityMissing:
                Image(systemName: "exclamationmark.triangle.fill").font(XFinderTokens.Font.caption).foregroundColor(.orange)
                Text(L10n.t("Chưa có Trợ năng: ↩ chỉ sao chép, dán bằng ⌘V."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                Spacer(minLength: 4)
                Button(L10n.t("Cấp quyền")) { _ = WindowManager.requestAccessibilityTrust() }.buttonStyle(NotchPillButtonStyle(primary: true))
            }
        }
        .frame(height: 20)
    }

    // MARK: Context menu — every shelf action that has no button of its own

    @ViewBuilder private func contextMenu(_ record: ClipboardRecord) -> some View {
        Button(L10n.t("Dán (Return)")) { NotchSurfaceController.shared.pasteFromClipboardPage(record) }
        Button(L10n.t("Dán dạng text thuần (⇧Return)")) { NotchSurfaceController.shared.pasteFromClipboardPage(record, plainText: true) }
        Button(L10n.t("Xem nhanh (Space)")) { NotchSurfaceController.shared.quickLook(record) }
        Divider()
        if record.isPinned {
            Button(L10n.t("Bỏ ghim")) { manager.togglePin(record.id) }
        } else {
            Button(L10n.t("Ghim")) { manager.togglePin(record.id) }
        }
        if manager.pasteStack.items.contains(record) {
            Button(L10n.t("Bỏ khỏi Paste Stack")) { manager.togglePasteStackItem(record) }
        } else {
            Button(L10n.t("Thêm vào Paste Stack")) { manager.togglePasteStackItem(record) }
        }
        if record.isSavedSnippet {
            Button(L10n.t("Bỏ lưu Snippet")) { manager.removeSnippet(record.id) }
        } else {
            Button(L10n.t("Lưu Snippet")) { manager.saveSnippet(record.id) }
        }
        Divider()
        if let text = record.textSnippet, !text.isEmpty, record.type != .image, record.type != .file {
            Menu(L10n.t("Biến đổi")) {
                ForEach(Array(ClipboardTransform.groups.enumerated()), id: \.offset) { i, group in
                    ForEach(group) { t in
                        Button(L10n.t(t.labelKey)) { NotchSurfaceController.shared.applyTransform(t, to: record) }
                    }
                    if i < ClipboardTransform.groups.count - 1 { Divider() }
                }
                Divider()
                let s = ClipboardTransform.stats(text)
                Text("\(s.words)\(L10n.t(" từ · "))\(s.characters)\(L10n.t(" ký tự · "))\(s.lines)\(L10n.t(" dòng"))")
            }
        }
        // "Đi tới nguồn" — one row per thing that is actually known about this record.
        let bid = record.sourceBundleID.flatMap { $0.isEmpty ? nil : $0 }
        let page = sourcePage(record)
        let filePath = revealablePath(record)
        if bid != nil || page != nil || filePath != nil {
            Menu(L10n.t("Đi tới nguồn")) {
                if let bid {
                    Button("\(L10n.t("Mở "))\(record.sourceAppName ?? bid)") { NotchSurfaceController.shared.openSourceApp(bundleID: bid) }
                }
                if let page { Button(L10n.t("Mở trang nguồn")) { NSWorkspace.shared.open(page) } }
                if let filePath { Button(L10n.t("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)]) } }
            }
        }
        Divider()
        if let ocr = record.ocrText, !ocr.isEmpty {
            Button(L10n.t("Sao chép chữ OCR trong ảnh")) { NotchSurfaceController.shared.copyText(ocr) }
        }
        if let bid {
            Button(L10n.t("Bỏ qua ứng dụng này (không lưu vào Clipboard)")) { manager.excludeApp(bundleID: bid, appName: record.sourceAppName) }
        }
        Button(L10n.t("Xóa (⌘⌫)"), role: .destructive) { NotchSurfaceController.shared.deleteFromClipboardPage(record) }
    }

    /// The page a clip came from: the link itself for a copied URL, or the browser-reported source
    /// (Chromium's `org.chromium.source-url`, captured at copy time). Nothing is guessed.
    private func sourcePage(_ r: ClipboardRecord) -> URL? {
        for key in ["sourceURL", "url"] {
            if let s = r.metadata[key], !s.isEmpty, let u = URL(string: s), ["http", "https"].contains(u.scheme ?? "") { return u }
        }
        return nil
    }

    private func revealablePath(_ r: ClipboardRecord) -> String? {
        guard let path = r.payloadPath ?? r.metadata["path"], r.type == .file || r.type == .image,
              FileManager.default.fileExists(atPath: path), !path.contains("/XFinder/") else { return nil }
        return path
    }
}

/// Pill buttons on the black surface: the primary one is white with black text (the Dynamic Island
/// convention — white text on the accent blue measured 3.7:1, below 4.5), the secondary a 10 % fill.
struct NotchPillButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(primary ? .black : .white)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.10)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
