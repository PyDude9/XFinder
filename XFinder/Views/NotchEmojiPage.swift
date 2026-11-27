import SwiftUI
import AppKit

/// Observable state for the Dynamic Island emoji page.
/// Owned by `NotchSurfaceModel` (e.g. `let emoji = NotchEmojiModel()`) so `NotchSurfaceController`
/// can coordinate panel key focus (`searchFocused`, `focusSearchRequest`, `isComposing`) across opens and key events.
@MainActor
@Observable
final class NotchEmojiModel {
    var query: String {
        didSet { session.query = query }
    }
    var selectedCategory: NotchEmojiCategory {
        didSet { session.selectedCategory = selectedCategory }
    }
    private(set) var recents: [String]
    var lastCopiedGlyph: String?
    /// Mirrors the SwiftUI `@FocusState` of the search field so the controller knows typing is active.
    var searchFocused: Bool = false
    /// Bumped by ⌘F or clear-search to restore keyboard focus into the search field.
    var focusSearchRequest: Int = 0

    /// True while the user is typing or holding a query — feeds `NotchSurfaceMachine.Settings.composing`
    /// so pointer drift off the notch does not collapse the surface mid-search.
    var isComposing: Bool { searchFocused || !query.isEmpty }

    private var session: NotchEmojiPickerSession

    init(
        recentsStore: NotchEmojiRecentsStore = NotchEmojiRecentsStore(),
        copyHandler: ((String) -> Bool)? = nil
    ) {
        let handler: (String) -> Bool = copyHandler ?? { glyph in
            let pb = NSPasteboard.general
            pb.clearContents()
            let ok = pb.setString(glyph, forType: .string)
            if ok { ClipboardSounds.playCopy() }
            return ok
        }
        let s = NotchEmojiPickerSession(store: recentsStore, copyHandler: handler)
        self.session = s
        self.query = s.query
        self.selectedCategory = s.selectedCategory
        self.recents = s.recents
    }

    var isSearching: Bool { session.isSearching }
    var displayedItems: [NotchEmojiItem] { session.displayedItems }

    /// Reloads persisted recents when the page appears or reopens.
    func reloadRecents() {
        session.reloadRecents()
        recents = session.recents
    }

    /// Resets transient feedback and refreshes recents on a fresh open.
    func beginSession() {
        lastCopiedGlyph = nil
        reloadRecents()
        focusSearchRequest += 1
    }

    func selectCategory(_ category: NotchEmojiCategory) {
        session.selectCategory(category)
        selectedCategory = session.selectedCategory
        query = session.query
    }

    /// Copies the selected emoji and updates recents without dropping search focus.
    @discardableResult
    func selectEmoji(_ item: NotchEmojiItem) -> Bool {
        let ok = session.copy(item)
        if ok {
            recents = session.recents
            lastCopiedGlyph = session.lastCopiedGlyph
        }
        return ok
    }

    func clearSearch() {
        query = ""
        focusSearchRequest += 1
    }
}

/// Dynamic Island emoji browser: local categorized emoji grid, VI/EN keyword search,
/// 24-item deduplicated recents, one-click copy, and persistent typing focus.
struct NotchEmojiPage: View {
    var model: NotchEmojiModel
    var onSearchFocusChanged: (Bool) -> Void = { _ in }
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch
    private static let gridColumns = [GridItem(.adaptive(minimum: 30, maximum: 34), spacing: 4)]

    var body: some View {
        let items = model.displayedItems
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            searchBar
            categoryStrip
            if items.isEmpty {
                emptyState
            } else {
                emojiGrid(items)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.beginSession()
            searchFieldFocused = true
            onSearchFocusChanged(true)
        }
        .onChange(of: searchFieldFocused) { _, focused in
            model.searchFocused = focused
            onSearchFocusChanged(focused)
        }
        .onDisappear {
            model.searchFocused = false
            model.query = ""
            onSearchFocusChanged(false)
        }
        .onChange(of: model.focusSearchRequest) { _, _ in
            searchFieldFocused = true
        }
    }

    // MARK: - Search Bar (always mounted so typing never loses focus)

    private var searchBar: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(searchFieldFocused ? .white.opacity(0.8) : N.toolbarIcon)
                    .accessibilityHidden(true)

                TextField("", text: Bindable(model).query)
                    .textFieldStyle(.plain)
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.white)
                    .focused($searchFieldFocused)
                    .accessibilityLabel(L10n.t("Tìm kiếm emoji"))
                    .overlay(alignment: .leading) {
                        if model.query.isEmpty {
                            Text(L10n.t("Tìm emoji (VI/EN)…"))
                                .font(XFinderTokens.Font.rowValue)
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                                .allowsHitTesting(false)
                        }
                    }

                if !model.query.isEmpty {
                    Button {
                        model.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Xoá tìm kiếm"))
                    .accessibilityLabel(L10n.t("Xoá tìm kiếm"))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: N.searchDiameter)
            .background(Capsule().fill(N.capsule))
            .overlay(Capsule().strokeBorder(searchFieldFocused ? accent.opacity(0.8) : N.cardStroke, lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture { searchFieldFocused = true }

            if let copied = model.lastCopiedGlyph {
                HStack(spacing: 4) {
                    Text(copied)
                        .font(.system(size: 12))
                    Text(L10n.t("Đã sao chép"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: N.searchDiameter)
                .background(Capsule().fill(accent.opacity(0.28)))
                .overlay(Capsule().strokeBorder(accent.opacity(0.55), lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(L10n.t("Đã sao chép")) \(copied)")
            }
        }
    }

    // MARK: - Category Strip

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(NotchEmojiCategory.allCases) { category in
                    let isSelected = !model.isSearching && model.selectedCategory == category
                    let title = categoryTitle(category)
                    Button {
                        model.selectCategory(category)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.symbolName)
                                .font(.system(size: 10, weight: .semibold))
                            if isSelected || category == .recent {
                                Text(title)
                                    .font(XFinderTokens.Font.caption)
                                    .lineLimit(1)
                            }
                        }
                        .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(isSelected ? accent.opacity(0.35) : N.capsule)
                        )
                        .overlay(
                            Capsule().strokeBorder(isSelected ? accent.opacity(0.8) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(title)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(height: 22)
    }

    // MARK: - Emoji Grid

    private func emojiGrid(_ items: [NotchEmojiItem]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: Self.gridColumns, spacing: 4) {
                ForEach(items) { item in
                    let wasCopied = model.lastCopiedGlyph == item.glyph
                    Button {
                        model.selectEmoji(item)
                    } label: {
                        Text(item.glyph)
                            .font(.system(size: 18))
                            .frame(width: 30, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                                    .fill(wasCopied ? accent.opacity(0.30) : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                                    .strokeBorder(wasCopied ? accent.opacity(0.75) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("\(item.nameVI) · \(item.nameEN)")
                    .accessibilityLabel("\(item.nameVI), \(item.nameEN)")
                    .accessibilityHint(L10n.t("Nhấn để sao chép emoji"))
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 4) {
            if model.isSearching {
                Text(L10n.t("Không tìm thấy emoji phù hợp"))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.white.opacity(0.75))
                    .accessibilityLabel(L10n.t("Không tìm thấy emoji phù hợp"))
                Button {
                    model.clearSearch()
                } label: {
                    Text(L10n.t("Xoá tìm kiếm"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(N.capsule))
                        .overlay(Capsule().strokeBorder(N.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Xoá tìm kiếm"))
            } else {
                Text(L10n.t("Chưa có emoji dùng gần đây"))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.white.opacity(0.75))
                    .accessibilityLabel(L10n.t("Chưa có emoji dùng gần đây"))
                Text(L10n.t("Chọn emoji để sao chép và lưu vào mục gần đây"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(L10n.t("Chọn emoji để sao chép và lưu vào mục gần đây"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Explicit literal `L10n.t("...")` calls so every L10n static audit script sees all category keys.
    private func categoryTitle(_ category: NotchEmojiCategory) -> String {
        switch category {
        case .recent: return L10n.t("Gần đây")
        case .smileys: return L10n.t("Cảm xúc")
        case .gestures: return L10n.t("Cử chỉ")
        case .hearts: return L10n.t("Trái tim")
        case .nature: return L10n.t("Thiên nhiên")
        case .food: return L10n.t("Đồ ăn")
        case .activities: return L10n.t("Hoạt động")
        case .travel: return L10n.t("Du lịch")
        case .objects: return L10n.t("Đồ vật")
        case .symbols: return L10n.t("Ký hiệu")
        case .flags: return L10n.t("Cờ")
        }
    }
}
