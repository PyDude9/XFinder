import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    /// The chip row's scope: history / pinned / saved / suggestions / one custom board (⌘1–9).
    var scope: NotchClipboardRules.Scope = .history
    /// The chip row's type filter. A typed `@type` token filters too; the chips highlight whichever applies.
    var typeFilter: ContentType?
    /// Newest first by default; the sort menu at the end of the chip row changes it (the shelf had this).
    var sort: ClipboardSortOrder = .newest
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

    /// Rendered cap. Four cards show; the rest scroll sideways. The shelf rendered everything; 60 is
    /// plenty for a glance-and-grab surface and keeps the LazyHStack cheap.
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

    /// The chips are exclusive, as in the reference: a scope chip clears the type, a type chip returns
    /// the scope to history. "Tất cả" also drops any `@type` token in the query, or the chip would lie.
    func choose(scope s: NotchClipboardRules.Scope) {
        scope = s; typeFilter = nil; selectedID = nil
        query = query.split(separator: " ").filter { ClipboardFilterToken.parse(String($0)).type == nil }.joined(separator: " ")
    }

    func choose(type t: ContentType) {
        typeFilter = t; scope = .history; selectedID = nil
    }

    /// Scope + app + text filters + sort, NO type filter — what the type-chip counts could be computed
    /// over. (The chip row shows counts over the whole loaded history so the numbers do not jump as you
    /// click; this list is what the deck draws from.)
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
        switch sort {
        case .newest: return list.sorted { $0.timestamp > $1.timestamp }
        case .oldest: return list.sorted { $0.timestamp < $1.timestamp }
        case .mostUsed: return list.sorted { $0.usageCount != $1.usageCount ? $0.usageCount > $1.usageCount : $0.timestamp > $1.timestamp }
        }
    }

    /// The deck: the type filter applied, capped.
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

    /// One horizontal row: ←/→ walk it and stop at the ends; ↑/↓ have no row to go to and stay put
    /// (`columns` = the whole row, so the rule's "no row there" branch applies).
    func move(_ d: NotchClipboardRules.Direction, in items: [ClipboardRecord]) {
        let i = items.firstIndex { $0.id == selectedID } ?? (selectedID == nil && !items.isEmpty ? 0 : nil)
        if let next = NotchClipboardRules.move(d, from: i, count: items.count, columns: max(1, items.count)) { selectedID = items[next].id }
    }
}

/// The search field — drawn in the notch band's LEFT wing, beside the page dots, by `NotchSurfaceView.band`, so it
/// is its own view. P1 (OneNotch): a 24-pt circle that opens into a field while it is in use — focused or holding a
/// query. The field is always in the hierarchy (zero-width while closed) so a click on the circle, ⌘F, or the page
/// focusing it on open can give it focus; ⌘⇧V therefore still lands typing in it at once.
/// Own placeholder at white 50 %: the system one measured 1.1:1 on this black field.
struct NotchClipboardSearchField: View {
    var model: NotchClipboardModel
    @FocusState private var searchFocused: Bool
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch
    private var locked: Bool { ClipboardShelfController.shared.touchIDLockEnabled && !model.unlocked }
    private var open: Bool { searchFocused || !model.query.isEmpty }

    var body: some View {
        HStack(spacing: open ? 6 : 0) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                .foregroundColor(open ? .white.opacity(0.65) : N.toolbarIcon)
            TextField("", text: Bindable(model).query)
                .textFieldStyle(.plain)
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.white)
                .focused($searchFocused)
                .overlay(alignment: .leading) {
                    if model.query.isEmpty, open {
                        Text(L10n.t("Tìm kiếm (⌘F)…"))
                            .font(XFinderTokens.Font.rowValue).foregroundColor(.white.opacity(0.5))
                            .lineLimit(1).allowsHitTesting(false)
                    }
                }
                .frame(width: open ? nil : 0)
                .opacity(open ? 1 : 0)
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.65)) }
                    .buttonStyle(.plain)
                    .help(L10n.t("Xoá tìm kiếm"))
            }
        }
        .padding(.horizontal, open ? 9 : 0)
        .frame(width: open ? nil : N.searchDiameter, height: N.searchDiameter)
        .frame(maxWidth: open ? .infinity : nil, alignment: .leading)
        .background(Capsule().fill(N.capsule))
        .overlay(Capsule().strokeBorder(searchFocused ? accent.opacity(0.8) : Color.clear, lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { if !locked { searchFocused = true } }
        .help(L10n.t("Tìm, hoặc @ảnh @link @tênapp…"))
        .accessibilityLabel(L10n.t("Tìm kiếm (⌘F)…"))
        .disabled(locked).opacity(locked ? 0.35 : 1)
        .animation(.easeOut(duration: 0.18), value: open)
        .onAppear { searchFocused = !locked }
        .onChange(of: searchFocused) { _, f in model.searchFocused = f }
        .onChange(of: model.focusSearchRequest) { searchFocused = true }
        .onChange(of: model.unlocked) { _, u in if u { searchFocused = true } }
    }
}

/// The clipboard page inside the notch hub (P1, OneNotch grammar): a chip row — Tất cả · Đã ghim · Đã lưu ·
/// Gợi ý · one chip per content type with its count · custom boards · "+" — with the status pill, the Library
/// button and the sort menu at its right end, then ONE horizontal row of `NotchClipCardView`s (three and a half
/// show, the rest scroll). The old footer line is gone: what it said lives in the status pill (Paste Stack, a
/// notice, paused, no Accessibility) or, for the key hints, in that pill's tooltip.
/// Click pastes into the app the user came from; ⌘-click queues the Paste Stack; right-click has every
/// action the shelf had. Keys live in `NotchSurfaceController`'s monitor; the search field is in the band.
struct NotchClipboardView: View {
    var model: NotchClipboardModel
    @State private var manager = ClipboardManager.shared
    @State private var now = Date()
    /// The card at the leading edge of the deck while it scrolls — each change taps the trackpad (ClipboardSounds.cardTick).
    @State private var leadingCard: UUID?
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch
    private var items: [ClipboardRecord] { model.items(from: manager) }
    private var locked: Bool { ClipboardShelfController.shared.touchIDLockEnabled && !model.unlocked }
    /// P1: the card and chip-row sizes are the page budget in `NotchSurfaceLayout.Metrics` (a test proves they fill the
    /// wide body exactly).
    private static let m = NotchSurfaceLayout.Metrics.standard
    static let cardWidth: CGFloat = m.clipCardWidth
    static let cardHeight: CGFloat = m.clipCardHeight
    static let cardGap: CGFloat = m.clipCardGap

    var body: some View {
        let list = items          // once per render — filter + sort of the loaded history, not once per use
        return VStack(alignment: .leading, spacing: Self.m.chipToDeckGap) {
            chipRow
            if locked { lockView }
            else if list.isEmpty { emptyView }
            else { deck(list) }
        }
        .environment(manager)
        .onAppear { now = Date() }
    }

    // MARK: Chip row — scopes, types with counts, boards, "+", and the sort menu

    private var customBoards: [Pinboard] { manager.pinboards.filter { !$0.isBuiltIn } }

    private var chipRow: some View {
        let history = manager.history
        let typeCounts = NotchClipboardRules.typeCounts(history.map(\.type))
        let typeChips = NotchClipboardRules.chips(from: typeCounts)
        let pinned = history.filter(\.isPinned).count
        let saved = history.filter(\.isSavedSnippet).count
        let type = model.effectiveType
        return HStack(spacing: XFinderTokens.Space.tight) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    chip(label: L10n.t("Tất cả"), icon: "clock", count: history.count,
                         on: model.scope == .history && type == nil, help: "\(L10n.t("Lịch sử Clipboard")) · ⌘1") { model.choose(scope: .history) }
                    chip(label: L10n.t("Đã ghim"), icon: "pin.fill", count: pinned, tint: .orange,
                         on: model.scope == .pinned, help: "⌘2") { model.choose(scope: .pinned) }
                        .onDrop(of: [.plainText], isTargeted: nil) { providers in
                            Self.dropRecordID(providers) { id in
                                if let r = ClipboardManager.shared.history.first(where: { $0.id == id }), !r.isPinned { ClipboardManager.shared.togglePin(id) }
                            }
                        }
                    if saved > 0 {
                        chip(label: L10n.t("Đã lưu"), icon: "bookmark.fill", count: saved,
                             on: model.scope == .saved, help: "⌘3") { model.choose(scope: .saved) }
                    }
                    if ClipboardIntelligenceEngine.shared.isEnabled {
                        chip(label: L10n.t("Gợi ý"), icon: "sparkles", count: nil, tint: .purple,
                             on: model.scope == .suggestions,
                             help: "\(L10n.t("Gợi ý cho "))\(ClipboardIntelligenceEngine.shared.targetAppName(forTargetPID: model.targetPID ?? manager.lastExternalPID))") {
                            model.choose(scope: .suggestions)
                        }
                    }
                    ForEach(typeChips, id: \.type) { c in
                        chip(label: nil, icon: c.type.icon, count: c.count, on: type == c.type, help: c.type.titleVI) {
                            model.choose(type: c.type)
                        }
                    }
                    ForEach(Array(customBoards.enumerated()), id: \.element.id) { i, b in
                        chip(label: b.name, icon: b.icon, count: b.itemIDs.count, tint: b.color.color,
                             on: model.scope == .board(b.id), help: i + 4 <= 9 ? "⌘\(i + 4)" : "") {
                            model.choose(scope: .board(b.id))
                        }
                        .onDrop(of: [.plainText], isTargeted: nil) { providers in
                            Self.dropRecordID(providers) { id in ClipboardManager.shared.addItemToPinboard(id, pinboardID: b.id) }
                        }
                    }
                    // "+" — boards are made on the Cài đặt Clipboard page, not in an overlay inside the hub.
                    Button { NotchSurfaceController.shared.openClipboardSettings() } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                            .foregroundColor(N.toolbarIcon)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(N.capsule))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Tạo bảng ghim mới"))
                    .accessibilityLabel(L10n.t("Tạo bảng ghim mới"))
                }
            }
            .disabled(locked).opacity(locked ? 0.35 : 1)
            Spacer(minLength: 0)
            statusPill
            if !locked {
                roundButton("rectangle.stack", help: L10n.t("Mở Thư viện Clipboard")) { NotchSurfaceController.shared.openLibrary() }
                sortMenu
            }
        }
        .frame(height: Self.m.chipRowHeight)
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundColor(N.toolbarIcon)
                .frame(width: 22, height: 22)
                .background(Circle().fill(N.capsule))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// D1 #3 — a card dragged onto a chip carries its record id as plain text; the chip's action runs on the main actor.
    private static func dropRecordID(_ providers: [NSItemProvider], _ action: @escaping @MainActor @Sendable (UUID) -> Void) -> Bool {
        guard let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, let id = UUID(uuidString: s) else { return }
            Task { @MainActor in action(id) }
        }
        return true
    }

    private func chip(label: String?, icon: String?, count: Int?, tint: Color? = nil, on: Bool, help: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                        .foregroundColor(on ? .black : (tint ?? .white.opacity(0.65)))
                }
                if let label { Text(label).font(.system(size: 11, weight: .semibold)) }
                if let count { Text(count.formatted()).font(.system(size: 10.5, weight: .medium)).monospacedDigit().opacity(on ? 0.6 : 0.8) }
            }
            .foregroundColor(on ? .black : .white.opacity(0.65))
            .padding(.horizontal, label == nil ? 7 : 9)
            .frame(height: 22)
            .background(Capsule().fill(on ? Color.white : N.capsule))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label ?? help)        // icon-only type chips: VoiceOver gets the type name, not just a count
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ClipboardSortOrder.allCases) { o in
                Button { model.sort = o; model.selectedID = nil } label: {
                    if model.sort == o { Label(o.titleVI, systemImage: "checkmark") } else { Text(o.titleVI) }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                .foregroundColor(N.toolbarIcon)
                .frame(width: 22, height: 22)
                .background(Circle().fill(N.capsule))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(L10n.t("Sắp xếp")) · \(model.sort.titleVI)")
        .accessibilityLabel("\(L10n.t("Sắp xếp")) · \(model.sort.titleVI)")
    }

    // MARK: The deck, the lock, the empty state

    private func deck(_ list: [ClipboardRecord]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Self.cardGap) {
                    ForEach(list) { record in
                        card(record, selected: model.isSelected(record, in: list)).id(record.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $leadingCard)
            .onChange(of: leadingCard) { old, new in
                ClipboardSounds.tickIfCardChanged(from: old, to: new, in: list.map(\.id))
            }
            .frame(height: Self.cardHeight)
            .onChange(of: model.selectedID) { _, id in
                if let id { withAnimation(.easeOut(duration: XFinderTokens.Motion.overlayIn)) { proxy.scrollTo(id) } }
            }
        }
    }

    private func card(_ record: ClipboardRecord, selected: Bool) -> some View {
        let stackIndex = manager.pasteStack.items.firstIndex(of: record).map { $0 + 1 }
        return NotchClipCardView(record: record, selected: selected, stackIndex: stackIndex, now: now,
                                 width: Self.cardWidth, height: Self.cardHeight)
            .frame(width: Self.cardWidth)
            .onDrag { NSItemProvider(object: record.id.uuidString as NSString) }   // D1 #3: drop on a board chip
            .onTapGesture { select(record) }
            .contextMenu { contextMenu(record) }
            .help("\(record.type.titleVI) · \(record.sourceAppName ?? "") · \(NotchClipCardView.ageLabel(record.timestamp, now: now))")
    }

    /// Plain click pastes; ⌘-click toggles the Paste Stack membership. A LOCKED record never pastes —
    /// the notch cannot prompt Touch ID and show a decrypted preview in a 174×122 tile, so selecting it
    /// dismisses the surface and opens the Library at the board that holds it instead.
    private func select(_ record: ClipboardRecord) {
        if record.isLocked {
            NotchSurfaceController.shared.openLibraryForLocked(record)
            return
        }
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
                .frame(maxWidth: 360)
            Button(L10n.t("Mở khóa Clipboard")) { NotchSurfaceController.shared.unlockClipboard() }
                .buttonStyle(NotchPillButtonStyle(primary: true))
        }
        .frame(maxWidth: .infinity).frame(height: Self.cardHeight)
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
        .frame(maxWidth: .infinity).frame(height: Self.cardHeight)
    }

    // MARK: Status pill — what the old footer line said, at the right end of the chip row

    /// `NotchClipboardRules.footer` still decides WHAT is shown and in which order (Paste Stack › notice › paused ›
    /// no Accessibility › hints); P1 only moves it from a line under the deck into one pill, so the deck keeps the
    /// height the measured 182-pt hub has. The full sentence is the pill's tooltip wherever the pill is shortened.
    @ViewBuilder private var statusPill: some View {
        let decision = NotchClipboardRules.footer(pasteStackActive: manager.pasteStack.active,
                                                  remaining: manager.pasteStack.remaining,
                                                  interceptsCommandV: NotchSurfaceController.shared.pasteStackInterceptsCommandV,
                                                  notice: model.notice,
                                                  paused: manager.isPaused,
                                                  autoPaste: ClipboardShelfController.shared.autoPasteAfterSelection,
                                                  accessibilityTrusted: WindowManager.isTrusted)
        switch decision {
        case .hints:
            if !locked {
                Image(systemName: "keyboard").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(N.toolbarIcon)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(N.capsule))
                    .help(L10n.t("↩ dán · ⇧↩ thuần · Space xem · ⌘P ghim · ⌘⌫ xoá · ⌘1–9 bảng"))
                    .accessibilityLabel(L10n.t("↩ dán · ⇧↩ thuần · Space xem · ⌘P ghim · ⌘⌫ xoá · ⌘1–9 bảng"))
            }
        case .pasteStack(let remaining, let intercepts):
            // HOW the stack pastes (⌘V or Dán tiếp) decides what the user does next, so it is text, not a tooltip; it
            // truncates first and the whole line stays the tooltip (P1 review).
            let how = intercepts ? L10n.t("Mỗi ⌘V dán mục kế tiếp.") : L10n.t("Bấm Dán tiếp để dán từng mục.")
            pill {
                Image(systemName: "square.stack.3d.up.fill").foregroundColor(accent)
                Text("Paste Stack · \(remaining)\(L10n.t(" mục"))").monospacedDigit().fixedSize()
                Text(how).lineLimit(1).truncationMode(.tail).opacity(0.75)
                Button(L10n.t("Dán tiếp")) { NotchSurfaceController.shared.pasteNextFromStack() }.buttonStyle(NotchPillButtonStyle(primary: true))
                    .fixedSize()
                Button { manager.stopPasteStack() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).help(L10n.t("Hủy")).accessibilityLabel(L10n.t("Hủy"))
            }
            .frame(maxWidth: 380)
            .layoutPriority(1)
            .help("Paste Stack · \(remaining)\(L10n.t(" mục")) · \(how)")
        case .notice(let key):
            pill { Text(L10n.t(key)).lineLimit(1).truncationMode(.tail) }
                .frame(maxWidth: 260)
                .help(L10n.t(key))
        case .paused:
            Button { NotchSurfaceController.shared.openClipboardSettings() } label: {
                pill {
                    Image(systemName: "pause.circle.fill").foregroundColor(.orange)
                    Text(L10n.t("Đang tạm dừng ghi clipboard.")).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .help(L10n.t("Mở Cài đặt"))
        case .accessibilityMissing:
            // D0's footer rule: the user must learn that ↩ only COPIES before the first click, not after — so the
            // sentence is visible text, with the grant button beside it (P1 review).
            pill {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(L10n.t("Chưa có Trợ năng: ↩ chỉ sao chép, dán bằng ⌘V.")).lineLimit(1).truncationMode(.tail)
                Button(L10n.t("Cấp quyền")) { _ = WindowManager.requestAccessibilityTrust() }
                    .buttonStyle(NotchPillButtonStyle(primary: true)).fixedSize()
            }
            .frame(maxWidth: 380)
            .layoutPriority(1)
            .help(L10n.t("Chưa có Trợ năng: ↩ chỉ sao chép, dán bằng ⌘V."))
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) { content() }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(N.capsule))
    }

    // MARK: Context menu — every shelf action that has no button of its own

    @ViewBuilder private func contextMenu(_ record: ClipboardRecord) -> some View {
        if record.isLocked {
            // D4: no paste / preview / speak / edit of a sealed clip from the notch — the Library prompts
            // Touch ID and shows it; deleting the ciphertext row is still allowed here.
            Button(L10n.t("Mở trong Thư viện")) { NotchSurfaceController.shared.openLibraryForLocked(record) }
            Divider()
            Button(L10n.t("Xoá"), role: .destructive) { NotchSurfaceController.shared.deleteFromClipboardPage(record) }
        } else {
        Button(L10n.t("Dán (Return)")) { NotchSurfaceController.shared.pasteFromClipboardPage(record) }
        Button(L10n.t("Dán dạng text thuần (⇧Return)")) { NotchSurfaceController.shared.pasteFromClipboardPage(record, plainText: true) }
        Button(L10n.t("Xem nhanh (Space)")) { NotchSurfaceController.shared.quickLook(record) }
        if record.type != .image, record.type != .file, record.type != .color {
            Button(L10n.t("Sửa văn bản…")) { NotchSurfaceController.shared.editText(record) }
            if NotchSurfaceController.shared.isSpeaking {
                Button(L10n.t("Dừng phát âm")) { NotchSurfaceController.shared.speak(record) }
            } else {
                Button(L10n.t("Phát âm")) { NotchSurfaceController.shared.speak(record) }
            }
        }
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
        let boards = customBoards
        if !boards.isEmpty {
            Menu(L10n.t("Bảng ghim")) {
                ForEach(boards) { b in
                    if b.itemIDs.contains(record.id) {
                        Button { manager.removeItemFromPinboard(record.id, pinboardID: b.id) } label: { Label(b.name, systemImage: "checkmark") }
                    } else {
                        Button(b.name) { manager.addItemToPinboard(record.id, pinboardID: b.id) }
                    }
                }
            }
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
