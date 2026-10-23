import Foundation

/// Spotlight-backed file search via the system `mdfind` tool (Foundation
/// Process, no deps). macOS 12-safe. The AI page reuses this engine: it
/// translates a natural-language query into an mdfind query string and runs it
/// here — no cloud, no fabricated results.
enum FileSearchEngine {

    struct ResultItem: Identifiable, Equatable {
        var id: String { path }
        var path: String
        var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    /// What one search found: at most `limit` paths, and whether Spotlight had more.
    struct Found: Equatable {
        var items: [ResultItem] = []
        var truncated = false
    }

    /// Raw mdfind runner. `query` is an mdfind expression, `scopes` are folders (empty = whole machine). Reads the
    /// output in chunks and stops `mdfind` once `limit` paths (and proof of one more) are in — before 2026-10-23 every
    /// path was read first (up to 134 MB / 35 s for a broad query, measured) and all but 100 thrown away.
    static func runMdfind(query: String, scopes: [URL] = [], limit: Int = 100) -> Found {
        var args = ["-0"]
        for s in scopes { args += ["-onlyin", s.path] }
        args += [query]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return Found() }
        var records = NulRecords(limit: limit)
        let reader = pipe.fileHandleForReading
        while true {
            let chunk = autoreleasepool { reader.availableData }
            if chunk.isEmpty { break }                     // end of output
            records.append(chunk)
            if records.truncated { break }                  // a record beyond the limit: enough
        }
        if p.isRunning { p.terminate() }
        try? reader.close()
        p.waitUntilExit()
        records.finish()
        return Found(items: records.records.map { ResultItem(path: $0) }, truncated: records.truncated)
    }

    // MARK: - Basic structured search (Tìm kiếm page)

    struct Criteria {
        var nameContains: String = ""
        var kind: KindFilter = .any
        var modifiedWithinDays: Int? = nil

        enum KindFilter: String, CaseIterable, Identifiable {
            case any, images, documents, audio, video, archives, folders
            var id: String { rawValue }
            var titleVI: String {
                switch self {
                case .any: return L10n.t("Mọi loại")
                case .images: return L10n.t("Hình ảnh")
                case .documents: return L10n.t("Tài liệu")
                case .audio: return L10n.t("Âm thanh")
                case .video: return "Video"
                case .archives: return L10n.t("File nén")
                case .folders: return L10n.t("Thư mục")
                }
            }
            /// Spotlight kMDItemContentTypeTree fragment, nil = no constraint.
            var mdFragment: String? {
                switch self {
                case .any: return nil
                case .images: return "kMDItemContentTypeTree == 'public.image'"
                case .documents: return "kMDItemContentTypeTree == 'public.content'"
                case .audio: return "kMDItemContentTypeTree == 'public.audio'"
                case .video: return "kMDItemContentTypeTree == 'public.movie'"
                case .archives: return "kMDItemContentTypeTree == 'public.archive'"
                case .folders: return "kMDItemContentTypeTree == 'public.folder'"
                }
            }
        }

        func mdfindQuery() -> String {
            var parts: [String] = []
            let t = nameContains.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                let escaped = t.replacingOccurrences(of: "'", with: "\\'")
                parts.append("kMDItemDisplayName == '*\(escaped)*'wc")
            }
            if let frag = kind.mdFragment { parts.append(frag) }
            if let days = modifiedWithinDays {
                // mdfind time: $time.today(-Nd)
                parts.append("kMDItemFSContentChangeDate >= $time.today(-\(days))")
            }
            return parts.isEmpty ? "kMDItemDisplayName == '*'wc" : parts.joined(separator: " && ")
        }
    }

    static func search(criteria: Criteria, scopes: [URL] = []) -> Found {
        runMdfind(query: criteria.mdfindQuery(), scopes: scopes)
    }

    // MARK: - Natural-language → mdfind (Tìm kiếm AI page, 100% on-device)

    /// Rule-based parser for Vietnamese/English queries. Returns the mdfind
    /// query plus a human-readable explanation of what was understood. Unknown
    /// phrasing falls back to a plain name search on the whole query — never
    /// a fake "AI" answer.
    static func parseNaturalLanguage(_ text: String) -> (query: String, explanation: String) {
        let lower = text.lowercased()
        var parts: [String] = []
        var notes: [String] = []

        func has(_ words: String...) -> Bool { words.contains { lower.contains($0) } }

        // Kind
        if has("ảnh", "hình", "image", "photo", "picture", "png", "jpg") {
            parts.append("kMDItemContentTypeTree == 'public.image'"); notes.append(L10n.t("loại: hình ảnh"))
        } else if has("video", "phim", "movie", "mp4") {
            parts.append("kMDItemContentTypeTree == 'public.movie'"); notes.append(L10n.t("loại: video"))
        } else if has("nhạc", "âm thanh", "audio", "music", "mp3") {
            parts.append("kMDItemContentTypeTree == 'public.audio'"); notes.append(L10n.t("loại: âm thanh"))
        } else if has("pdf") {
            parts.append("kMDItemContentTypeTree == 'com.adobe.pdf'"); notes.append(L10n.t("loại: PDF"))
        } else if has("nén", "zip", "archive") {
            parts.append("kMDItemContentTypeTree == 'public.archive'"); notes.append(L10n.t("loại: file nén"))
        } else if has("thư mục", "folder", "directory") {
            parts.append("kMDItemContentTypeTree == 'public.folder'"); notes.append(L10n.t("loại: thư mục"))
        } else if has("tài liệu", "document", "doc", "word", "excel") {
            parts.append("kMDItemContentTypeTree == 'public.content'"); notes.append(L10n.t("loại: tài liệu"))
        }

        // Recency
        if has("hôm nay", "today") {
            parts.append("kMDItemFSContentChangeDate >= $time.today(-1)"); notes.append(L10n.t("sửa: hôm nay"))
        } else if has("hôm qua", "yesterday") {
            parts.append("kMDItemFSContentChangeDate >= $time.today(-2)"); notes.append(L10n.t("sửa: 2 ngày qua"))
        } else if has("tuần này", "tuần qua", "this week", "last week") {
            parts.append("kMDItemFSContentChangeDate >= $time.today(-7)"); notes.append(L10n.t("sửa: 7 ngày qua"))
        } else if has("tháng này", "tháng qua", "this month") {
            parts.append("kMDItemFSContentChangeDate >= $time.today(-30)"); notes.append(L10n.t("sửa: 30 ngày qua"))
        }

        // Quoted "name" or remainder words as name filter.
        var nameTerms: [String] = []
        if let open = text.firstIndex(of: "\""), let close = text[open...].dropFirst().firstIndex(of: "\"") {
            nameTerms.append(String(text[text.index(after: open)..<close]))
        } else {
            // Strip recognised keywords, keep the rest as a name hint.
            let stopwords: Set<String> = ["tìm", "kiếm", "tìm kiếm", "cho", "tôi", "các", "những", "file",
                "tập tin", "mới", "gần đây", "sửa", "đổi", "trong", "của", "là", "có", "từ", "này",
                "nay", "qua", "find", "search", "files", "recent", "modified", "the", "a", "an", "me", "my",
                "ảnh", "hình", "video", "phim", "nhạc", "pdf", "nén", "thư mục", "tài liệu",
                "hôm", "tuần", "tháng", "today", "week", "month", "yesterday", "image", "movie", "audio", "folder", "document"]
            let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init).filter { !stopwords.contains($0) && $0.count > 1 }
            nameTerms.append(contentsOf: words)
        }
        let meaningful = nameTerms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !meaningful.isEmpty {
            let escaped = meaningful.joined(separator: " ").replacingOccurrences(of: "'", with: "\\'")
            parts.append("kMDItemDisplayName == '*\(escaped)*'wc")
            notes.append(L10n.t("tên chứa: ") + "\"\(meaningful.joined(separator: " "))\"")
        }

        if parts.isEmpty {
            let escaped = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "'", with: "\\'")
            return ("kMDItemDisplayName == '*\(escaped)*'wc",
                    L10n.t("Không nhận ra cấu trúc — tìm tên chứa toàn bộ câu."))
        }
        return (parts.joined(separator: " && "), L10n.t("Hiểu: ") + notes.joined(separator: " · "))
    }
}
