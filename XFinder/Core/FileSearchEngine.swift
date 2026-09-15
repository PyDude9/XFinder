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

    /// Raw mdfind runner. `query` is an mdfind expression, `scopes` are folders
    /// (empty = whole machine). Returns up to `limit` paths, empty on error.
    static func runMdfind(query: String, scopes: [URL] = [], limit: Int = 100) -> [ResultItem] {
        var args = ["-0"]
        for s in scopes { args += ["-onlyin", s.path] }
        args += [query]
        let out = runProcess(exe: "/usr/bin/mdfind", args: args)
        guard !out.isEmpty else { return [] }
        let paths = out.split(separator: "\0").map(String.init).prefix(limit)
        return paths.map { ResultItem(path: $0) }
    }

    private static func runProcess(exe: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
        } catch { return "" }
        // Drain before waiting — a >64KB result would otherwise deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
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
                case .any: return "Mọi loại"
                case .images: return "Hình ảnh"
                case .documents: return "Tài liệu"
                case .audio: return "Âm thanh"
                case .video: return "Video"
                case .archives: return "File nén"
                case .folders: return "Thư mục"
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

    static func search(criteria: Criteria, scopes: [URL] = []) -> [ResultItem] {
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
            parts.append("kMDItemContentTypeTree == 'public.image'"); notes.append("loại: hình ảnh")
        } else if has("video", "phim", "movie", "mp4") {
            parts.append("kMDItemContentTypeTree == 'public.movie'"); notes.append("loại: video")
        } else if has("nhạc", "âm thanh", "audio", "music", "mp3") {
            parts.append("kMDItemContentTypeTree == 'public.audio'"); notes.append("loại: âm thanh")
        } else if has("pdf") {
            parts.append("kMDItemContentTypeTree == 'com.adobe.pdf'"); notes.append("loại: PDF")
        } else if has("nén", "zip", "archive") {
            parts.append("kMDItemContentTypeTree == 'public.archive'"); notes.append("loại: file nén")
        } else if has("thư mục", "folder", "directory") {
            parts.append("kMDItemContentTypeTree == 'public.folder'"); notes.append("loại: thư mục")
        } else if has("tài liệu", "document", "doc", "word", "excel") {
            parts.append("kMDItemContentTypeTree == 'public.content'"); notes.append("loại: tài liệu")
        }

        // Recency
        if has("hôm nay", "today") {
            parts.append("kMDItemFSContentChangeDate >= $time.today(-1)"); notes.append("sửa: hôm nay")
        } else if has("hôm qua", "yesterday") {
            parts.append("kMDItemFSContentChangeDate >= $time.today(-2)"); notes.append("sửa: 2 ngày qua")
        } else if has("tuần này", "tuần qua", "this week", "last week") {
            parts.append("kMDItemFSContentChangeDate >= $time.today(-7)"); notes.append("sửa: 7 ngày qua")
        } else if has("tháng này", "tháng qua", "this month") {
            parts.append("kMDItemFSContentChangeDate >= $time.today(-30)"); notes.append("sửa: 30 ngày qua")
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
            notes.append("tên chứa: “\(meaningful.joined(separator: " "))”")
        }

        if parts.isEmpty {
            let escaped = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "'", with: "\\'")
            return ("kMDItemDisplayName == '*\(escaped)*'wc",
                    "Không nhận ra cấu trúc — tìm tên chứa toàn bộ câu.")
        }
        return (parts.joined(separator: " && "), "Hiểu: " + notes.joined(separator: " · "))
    }
}
