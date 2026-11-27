import SwiftUI
import AppKit

/// Observable state for the Dynamic Island Quicklinks page (`XF-ISLAND-LINKS`).
/// Owned by `NotchSurfaceModel` (e.g. `let links = NotchLinksModel()`) so `NotchSurfaceController`
/// can coordinate panel key focus (`searchFocused`, `focusSearchRequest`, `isComposing`) and key events.
///
/// Does not maintain its own link store (reads `Quicklinks.shared.links` directly) and never reads the Clipboard.
@MainActor
@Observable
final class NotchLinksModel {
    enum Notice: Equatable {
        case copied
        case invalidURL
        case openFailed
    }

    var query: String = ""
    /// Mirrors the SwiftUI `@FocusState` of the search field so the controller knows typing is active.
    var searchFocused: Bool = false
    /// Bumped by ⌘F or clear-search to restore keyboard focus into the search field.
    var focusSearchRequest: Int = 0
    /// ID of the most recently copied Quicklink for brief inline button feedback.
    var lastCopiedID: UUID?
    /// Transient inline status message (copied confirmation, invalid URL, or default-app open failure).
    var notice: Notice?

    /// True while typing or holding a filter query — feeds `NotchSurfaceMachine.Settings.composing`
    /// so pointer drift off the notch does not collapse the surface mid-search.
    var isComposing: Bool { searchFocused || !query.isEmpty }

    private let openHandler: (URL) -> Bool
    private let copyHandler: (String) -> Bool

    init(
        openHandler: ((URL) -> Bool)? = nil,
        copyHandler: ((String) -> Bool)? = nil
    ) {
        self.openHandler = openHandler ?? { url in
            NSWorkspace.shared.open(url)
        }
        self.copyHandler = copyHandler ?? { address in
            let pb = NSPasteboard.general
            pb.clearContents()
            let ok = pb.setString(address, forType: .string)
            if ok { ClipboardSounds.playCopy() }
            return ok
        }
    }

    func beginSession() {
        notice = nil
        lastCopiedID = nil
        focusSearchRequest += 1
    }

    func clearSearch() {
        query = ""
        notice = nil
        focusSearchRequest += 1
    }

    /// Opens `entry` in the user's default app ONLY if it passes strict HTTP/HTTPS validation.
    @discardableResult
    func open(_ entry: NotchLinkEntry) -> NotchLinksRules.OpenResult {
        let result = NotchLinksRules.open(entry, using: openHandler)
        switch result {
        case .opened:
            notice = nil
        case .invalidURL:
            notice = .invalidURL
        case .launchFailed:
            notice = .openFailed
        }
        return result
    }

    /// Copies the Quicklink's URL to the pasteboard (write-only; never reads the clipboard).
    @discardableResult
    func copy(_ entry: NotchLinkEntry) -> Bool {
        let ok = NotchLinksRules.copyAddress(entry, using: copyHandler)
        if ok {
            lastCopiedID = entry.id
            notice = .copied
        }
        return ok
    }
}

/// Dynamic Island Quicklinks page (`XF-ISLAND-LINKS`):
/// Lists existing XFinder Quicklinks (`Quicklinks.shared`), filters by title/keyword/URL,
/// opens valid HTTP/HTTPS URLs on explicit user click, copies URLs, and links to Quicklinks settings.
struct NotchLinksPage: View {
    var model: NotchLinksModel
    /// Optional navigation callback supplied by the integrator (e.g. `NotchSurfaceController.shared.openQuicklinksSettings()`).
    /// Falls back to navigating directly to `.finderSearch` and raising the main window.
    var onOpenSettings: (() -> Void)? = nil
    var onSearchFocusChanged: (Bool) -> Void = { _ in }

    @State private var quicklinks = Quicklinks.shared
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch

    private var entries: [NotchLinkEntry] {
        quicklinks.links.map { link in
            NotchLinkEntry(id: link.id, keyword: link.keyword, title: link.title, url: link.url)
        }
    }

    var body: some View {
        let displayState = NotchLinksRules.displayState(links: entries, query: model.query)
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            topBar
            if let notice = model.notice {
                noticeBanner(notice)
            }
            switch displayState {
            case .emptyCatalog:
                emptyCatalogView
            case .noMatches:
                noMatchesView
            case .results(let matched):
                resultsList(matched)
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

    // MARK: - Top Bar (always-mounted search field + Quicklinks settings button)

    private var topBar: some View {
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
                    .accessibilityLabel(L10n.t("Tìm kiếm liên kết"))
                    .overlay(alignment: .leading) {
                        if model.query.isEmpty {
                            Text(L10n.t("Tìm liên kết, từ khóa hoặc URL…"))
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

            Button {
                openQuicklinksSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: N.searchDiameter, height: N.searchDiameter)
                    .background(Circle().fill(N.capsule))
                    .overlay(Circle().strokeBorder(N.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Quản lý Quicklinks"))
            .accessibilityLabel(L10n.t("Quản lý Quicklinks"))
        }
    }

    // MARK: - Inline Notice

    private func noticeBanner(_ notice: NotchLinksModel.Notice) -> some View {
        let isError = notice != .copied
        let icon = isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        let tint: Color = isError ? .orange : accent
        let message = noticeText(notice)

        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                .fill(tint.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private func noticeText(_ notice: NotchLinksModel.Notice) -> String {
        switch notice {
        case .copied:
            return L10n.t("Đã sao chép địa chỉ")
        case .invalidURL:
            return L10n.t("URL không hợp lệ (chỉ hỗ trợ HTTP/HTTPS)")
        case .openFailed:
            return L10n.t("Không thể mở liên kết trong ứng dụng mặc định")
        }
    }

    // MARK: - Results List

    private func resultsList(_ items: [NotchLinkEntry]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(items) { entry in
                    linkRow(entry)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func linkRow(_ entry: NotchLinkEntry) -> some View {
        let validURL = NotchLinksRules.validatedWebURL(entry.url) != nil
        let title = NotchLinksRules.displayTitle(entry.title, fallbackURL: entry.url)
        let shownURL = NotchLinksRules.displayURL(entry.url)
        let isCopied = model.lastCopiedID == entry.id

        return HStack(spacing: XFinderTokens.Space.tight) {
            Button {
                model.open(entry)
            } label: {
                HStack(spacing: XFinderTokens.Space.tight) {
                    Image(systemName: validURL ? "link.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(validURL ? accent : .orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(title)
                                .font(XFinderTokens.Font.rowValue)
                                .foregroundColor(validURL ? .white : .white.opacity(0.65))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)

                            if !entry.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(entry.keyword)
                                    .font(XFinderTokens.Font.caption)
                                    .foregroundColor(.white.opacity(0.75))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.white.opacity(0.10)))
                            }
                        }

                        Text(validURL ? shownURL : L10n.t("URL không hợp lệ"))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(validURL ? .white.opacity(0.55) : .orange.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(validURL ? "\(title) — \(entry.url)" : L10n.t("URL không hợp lệ (chỉ hỗ trợ HTTP/HTTPS)"))
            .accessibilityLabel("\(L10n.t("Mở liên kết")): \(title)")

            Button {
                model.copy(entry)
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isCopied ? accent : .white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Sao chép địa chỉ"))
            .accessibilityLabel("\(L10n.t("Sao chép địa chỉ")): \(title)")

            Button {
                model.open(entry)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(validURL ? .white.opacity(0.75) : .white.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(L10n.t("Mở liên kết"))
            .accessibilityLabel("\(L10n.t("Mở liên kết")): \(title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(N.cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Empty States

    private var emptyCatalogView: some View {
        VStack(spacing: 6) {
            Text(L10n.t("Chưa có liên kết nhanh nào"))
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.white.opacity(0.75))
                .accessibilityLabel(L10n.t("Chưa có liên kết nhanh nào"))
            Button {
                openQuicklinksSettings()
            } label: {
                Text(L10n.t("Mở cài đặt Quicklinks"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(accent.opacity(0.75), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Mở cài đặt Quicklinks"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var noMatchesView: some View {
        VStack(spacing: 6) {
            Text(L10n.t("Không tìm thấy liên kết phù hợp"))
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.white.opacity(0.75))
                .accessibilityLabel(L10n.t("Không tìm thấy liên kết phù hợp"))
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func openQuicklinksSettings() {
        if let onOpenSettings {
            onOpenSettings()
        } else {
            AppState.shared.navigate(to: .finderSearch)
            AppState.shared.bringMainWindowFront()
        }
    }
}
