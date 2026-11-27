import Foundation
import Observation

/// Engine "Tìm nhanh" của trang Tìm kiếm — kiểu TinyCast: một ô nhập gộp
/// bốn nguồn trong cùng một danh sách:
///   1. Liên kết nhanh (từ khóa → URL, khớp chính xác xếp trước)
///   2. Ứng dụng (fuzzy match trên danh sách app đã quét)
///   3. Phép tính (SafeArithmetic — không bao giờ ném exception; nút Mở sao chép kết quả vào clipboard)
///   4. Tập tin (mdfind/Spotlight)
/// Debounce 0.2s; quét app + mdfind chạy background task, phần còn lại instant.
@MainActor @Observable
final class QuickSearchEngine {
    static let shared = QuickSearchEngine()

    private(set) var results: [QuickSearchResult] = []
    private(set) var isSearching = false

    private var searchTask: Task<Void, Never>?

    private init() {}

    func search(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()

        // Dưới 2 ký tự chưa đủ ý nghĩa — và tránh mdfind chạy bão mỗi phím gõ.
        guard q.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            // Debounce: task bị hủy nếu người dùng gõ tiếp trong 0.2s.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            let links = Quicklinks.shared.search(query: q)
            let snippets = TextSnippetStore.shared.quickSearchResults(query: q)
            let settingsPages = Self.searchSettingsPages(query: q)
            let calc = Calculator.shared.evaluate(query: q).map { [$0] } ?? []

            async let apps = Task.detached(priority: .userInitiated) {
                AppLauncher.shared.search(query: q)
            }.value
            async let files = FileSearch.shared.search(query: q)

            let (appResults, fileResults) = await (apps, files)
            guard !Task.isCancelled else { return }

            self?.results = links + snippets + settingsPages + appResults + calc + fileResults
            self?.isSearching = false
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
        isSearching = false
    }

    private static func searchSettingsPages(query: String) -> [QuickSearchResult] {
        var matched: [QuickSearchResult] = []
        for dest in SidebarDestination.allCases {
            let texts = [dest.titleKey, L10n.english(dest.titleKey), dest.rawValue]
                + dest.searchAlsoKeys.flatMap { [$0, L10n.english($0)] }
                + SettingsSearchIndex.keywords(for: dest)
            guard SidebarSearch.matches(query: query, texts: texts) else { continue }
            let hint = SettingsSearchIndex.firstMatchedKeyword(for: dest, query: query)
            matched.append(QuickSearchResult(
                type: .settingsPage,
                title: dest.titleVI,
                subtitle: hint ?? L10n.t("Cài đặt XFinder"),
                icon: nil,
                action: {
                    Task { @MainActor in
                        AppState.shared.navigate(to: dest)
                    }
                }
            ))
            if matched.count >= 5 { break }
        }
        return matched
    }
}