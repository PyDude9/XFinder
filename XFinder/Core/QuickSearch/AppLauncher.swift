import Foundation
import AppKit

/// Tìm kiếm và mở ứng dụng với fuzzy search
/// `@unchecked Sendable`: bộ đếm `cachedApps` chỉ ghi một lần trong init và
/// được khóa bằng lock; search chỉ đọc.
final class AppLauncher: @unchecked Sendable {
    static let shared = AppLauncher()

    private var cachedApps: [AppInfo] = []
    private let cacheLock = NSLock()
    private let workspace = NSWorkspace.shared

    struct AppInfo {
        let name: String
        let path: String
        let icon: NSImage?
    }

    private init() {
        refreshApps()
    }

    func refreshApps() {
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "\(NSHomeDirectory())/Applications"
        ]

        var apps: [AppInfo] = []
        let fm = FileManager.default

        for dir in appDirs {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let fullPath = "\(dir)/\(item)"
                let name = (item as NSString).deletingPathExtension
                let icon = workspace.icon(forFile: fullPath)
                apps.append(AppInfo(name: name, path: fullPath, icon: icon))
            }
        }

        cacheLock.lock()
        cachedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cacheLock.unlock()
    }

    func search(query: String) -> [QuickSearchResult] {
        guard !query.isEmpty else { return [] }

        // Snapshot dưới lock — search có thể chạy trên background task.
        cacheLock.lock()
        let apps = cachedApps
        cacheLock.unlock()

        let scored = apps.compactMap { app -> SearchScore? in
            guard let score = fuzzyMatch(query: query.lowercased(), target: app.name.lowercased()) else {
                return nil
            }
            let result = QuickSearchResult(
                type: .app,
                title: app.name,
                subtitle: app.path,
                icon: app.icon,
                action: { [weak self] in
                    self?.launch(path: app.path)
                }
            )
            return SearchScore(score: score, result: result)
        }

        return scored
            .sorted { $0.score < $1.score }
            .prefix(8)
            .map(\.result)
    }

    private func launch(path: String) {
        let url = URL(fileURLWithPath: path)
        workspace.open(url)
    }

    /// Fuzzy match: trả về score (càng nhỏ càng tốt), nil nếu không khớp
    /// "saf" khớp "Safari" → score 0 (exact prefix)
    /// "sfr" khớp "Safari" → score 2 (skipped 'a', 'i')
    private func fuzzyMatch(query: String, target: String) -> Int? {
        var queryIdx = query.startIndex
        var targetIdx = target.startIndex
        var score = 0
        var lastMatch = target.startIndex

        while queryIdx < query.endIndex && targetIdx < target.endIndex {
            if query[queryIdx] == target[targetIdx] {
                // Khớp liên tiếp → điểm thấp hơn
                if targetIdx == target.index(after: lastMatch) || lastMatch == target.startIndex {
                    score += 0
                } else {
                    score += 1
                }
                lastMatch = targetIdx
                query.formIndex(after: &queryIdx)
            } else {
                score += 1
            }
            target.formIndex(after: &targetIdx)
        }

        // Chưa match hết query → fail
        guard queryIdx == query.endIndex else { return nil }

        return score
    }
}
