import Foundation
import AppKit

/// Tìm file theo tên qua `NSMetadataQuery` — API native chạy thẳng trên index
/// Spotlight. Đây là thứ tương đương "Everything" của Windows trên macOS:
/// index tức thì theo tên, không spawn process `/usr/bin/mdfind` mỗi lần gõ
/// (nhanh hơn + bất đồng bộ + không còn hack `-limit`).
/// `Sendable`: không trạng thái dùng chung.
final class FileSearch: Sendable {
    static let shared = FileSearch()
    private init() {}

    func search(query: String) async -> [QuickSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let predicate = NSPredicate(format: "kMDItemFSName CONTAINS[c] %@", q)
        return await Self.metadataResults(predicate: predicate, limit: 10)
    }

    private static func metadataResults(predicate: NSPredicate, limit: Int) async -> [QuickSearchResult] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let query = NSMetadataQuery()
                query.predicate = predicate
                query.searchScopes = [NSHomeDirectory()]
                var token: NSObjectProtocol?
                var done = false

                let finish = {
                    guard !done else { return }
                    done = true
                    query.stop()
                    if let token { NotificationCenter.default.removeObserver(token) }
                    let items = query.results.prefix(limit).compactMap { item -> QuickSearchResult? in
                        guard let path = (item as? NSMetadataItem)?
                            .value(forAttribute: NSMetadataItemPathKey) as? String
                        else { return nil }
                        let url = URL(fileURLWithPath: path)
                        return QuickSearchResult(
                            type: .file,
                            title: url.lastPathComponent,
                            subtitle: path,
                            icon: NSWorkspace.shared.icon(forFile: path),
                            action: { NSWorkspace.shared.open(url) })
                    }
                    continuation.resume(returning: items)
                }

                token = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil
                ) { _ in finish() }

                query.start()
                // Deadline safety: nếu index chậm, trả kết quả đã gom sau 1.2s.
                let deadline = Date(timeIntervalSinceNow: 1.2)
                while !done && Date() < deadline {
                    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
                }
                finish()
            }
        }
    }
}
