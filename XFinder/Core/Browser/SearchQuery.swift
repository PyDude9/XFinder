import Foundation

/// XF-T28 — plain-sentence + advanced-syntax search parsing, and the `mdfind` expression it compiles to.
///
/// Why plain sentences: the reference app (FileOctopus, measured from its docs — see contract) lets people type
/// "pdfs from last week" and get an editable chip instead of forcing `kind:pdf modified:>=2026-10-17` up front.
/// Plural/`kind:` is the file's TYPE ("pdfs", "images", "ảnh", "tệp pdf"); the singular "pdf" is just a filename
/// word — that distinction is the single most load-bearing rule here (checklist: "Tìm \"pdf\" số ít").
///
/// This file only turns text into structure (`ParsedSearch`) and structure into an `mdfind` predicate string; it
/// never runs a process (that is `DirectoryReader`'s job, not pure). All user-facing strings are returned as L10n
/// KEYS — the Vietnamese sentence itself — per the repo-wide convention (see `L10n.swift`); the view calls `L10n.t()`.
enum KindFilter: String, Codable, CaseIterable, Sendable {
    case pdfs, images, videos, audio, documents, spreadsheets, presentations, archives, folders, applications, screenshots, code, text
}

enum DateRange: Hashable, Codable, Sendable {
    case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, lastYear
    case pastDays(Int), olderThanDays(Int), month(year: Int, month: Int)
}

enum SizeOp: String, Codable, Sendable { case greater, less, greaterOrEqual, lessOrEqual, equal }

struct SearchChip: Hashable, Codable, Sendable, Identifiable {
    enum Field: String, Codable, Sendable { case kind, modified, created, size, source, ext, tag, content, folder }
    enum Value: Hashable, Codable, Sendable { case kind(KindFilter); case date(DateRange); case size(SizeOp, Int64); case text(String) }
    var field: Field
    var value: Value
    /// A bare month name with no year ("tháng 3", "March") resolves to the most recent occurrence — the chip
    /// shows a "?" because that guess may be wrong (contract: "tháng không có năm ⇒ chip đánh dấu \"?\"").
    var uncertain: Bool

    /// Stable across re-parses of the same intent so the UI can match a chip back to its edit, independent of
    /// array position. Built from the field plus a normalized rendering of the value (not the raw user text).
    var id: String {
        switch value {
        case .kind(let k): return "kind:\(k.rawValue)"
        case .date(let d): return "\(field.rawValue):\(SearchQuery.normalizedKey(for: d))"
        case .size(let op, let bytes): return "\(field.rawValue):\(op.rawValue):\(bytes)"
        case .text(let t): return "\(field.rawValue):\(SearchQuery.foldedKey(t))"
        }
    }
}

struct ParsedSearch: Equatable, Sendable {
    var chips: [SearchChip]
    /// Bare filename words (AND together) — the "pdf" in "pdf report", kept as text, not promoted to a kind chip.
    var terms: [String]
    /// "cụm trong ngoặc" — matched verbatim (as a substring) in the filename.
    var phrases: [String]
    /// -word or !word — filename words that must NOT appear.
    var excluded: [String]
    /// L10n keys, e.g. an unrecognized operator kept as plain text.
    var warnings: [String]
    var isEmpty: Bool { chips.isEmpty && terms.isEmpty && phrases.isEmpty && excluded.isEmpty }
}

/// Plain-sentence and `field:value` search parsing (English + Vietnamese), and the `mdfind` predicate it compiles to.
enum SearchQuery {

    // MARK: - Vocabulary

    private static let kindWordsEnglish: [String: KindFilter] = [
        "pdfs": .pdfs,
        "images": .images, "pictures": .images, "photos": .images,
        "videos": .videos, "movies": .videos,
        "audio": .audio, "music": .audio, "songs": .audio,
        "documents": .documents, "docs": .documents,
        "spreadsheets": .spreadsheets,
        "presentations": .presentations, "slides": .presentations,
        "archives": .archives, "zips": .archives,
        "folders": .folders, "directories": .folders,
        "applications": .applications, "apps": .applications,
        "screenshots": .screenshots,
        "code": .code,
        "text": .text,
    ]

    /// Vietnamese kind words, already fold-keyed (no diacritics, lowercase) so matching is accent-insensitive —
    /// the user may type "anh" for "ảnh" and still get the image kind, mirroring `EntryRules.foldKey`.
    private static let kindWordsVietnamese: [String: KindFilter] = [
        foldedKey("ảnh"): .images, foldedKey("hình"): .images,
        foldedKey("video"): .videos, foldedKey("phim"): .videos,
        foldedKey("nhạc"): .audio, foldedKey("âm thanh"): .audio,
        foldedKey("tài liệu"): .documents,
        foldedKey("bảng tính"): .spreadsheets,
        foldedKey("bản trình chiếu"): .presentations,
        foldedKey("tệp nén"): .archives,
        foldedKey("thư mục"): .folders,
        foldedKey("ứng dụng"): .applications,
        foldedKey("ảnh chụp màn hình"): .screenshots,
        foldedKey("mã nguồn"): .code,
        foldedKey("tệp pdf"): .pdfs,
    ]

    /// `kind:` value tokens — both the enum raw value and a few common aliases.
    private static let kindTokenAliases: [String: KindFilter] = [
        "pdf": .pdfs, "pdfs": .pdfs,
        "image": .images, "images": .images,
        "video": .videos, "videos": .videos,
        "audio": .audio,
        "document": .documents, "documents": .documents,
        "spreadsheet": .spreadsheets, "spreadsheets": .spreadsheets,
        "presentation": .presentations, "presentations": .presentations,
        "archive": .archives, "archives": .archives,
        "folder": .folders, "folders": .folders,
        "application": .applications, "applications": .applications, "app": .applications,
        "screenshot": .screenshots, "screenshots": .screenshots,
        "code": .code,
        "text": .text,
    ]

    private static let monthNamesEnglish: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
        "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
    ]

    /// UTC-second resolution matches the `$time.iso` format the contract specifies for `mdfindExpression`;
    /// anything finer would be false precision no reader of a date chip could act on.
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Folding (shared normalization for matching, independent of EntryRules to keep this file standalone)

    /// Lowercases and strips diacritics so "Ảnh" / "anh" / "ẢNH" all compare equal — same normalization family as
    /// `EntryRules.foldKey`, duplicated here because this file must stay a standalone leaf (no cross-file Core
    /// dependency beyond its own contract).
    static func foldedKey(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    fileprivate static func normalizedKey(for range: DateRange) -> String {
        switch range {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .thisWeek: return "thisWeek"
        case .lastWeek: return "lastWeek"
        case .thisMonth: return "thisMonth"
        case .lastMonth: return "lastMonth"
        case .thisYear: return "thisYear"
        case .lastYear: return "lastYear"
        case .pastDays(let n): return "pastDays:\(n)"
        case .olderThanDays(let n): return "olderThanDays:\(n)"
        case .month(let y, let m): return "month:\(y):\(m)"
        }
    }

    // MARK: - parse

    static func parse(_ text: String, now: Date, calendar: Calendar) -> ParsedSearch {
        var chips: [SearchChip] = []
        var terms: [String] = []
        var phrases: [String] = []
        var excluded: [String] = []
        var warnings: [String] = []

        for rawToken in tokenize(text) {
            switch rawToken {
            case .phrase(let p):
                phrases.append(p)

            case .excluded(let w):
                excluded.append(w)

            case .fieldValue(let field, let value):
                if let chip = parseFieldValue(field: field, value: value, now: now, calendar: calendar) {
                    chips.append(chip)
                } else {
                    // Unknown field or unparsable value stays as a plain filename word, with a warning (contract:
                    // "Toán tử lạ ⇒ giữ là từ + warning").
                    terms.append("\(field):\(value)")
                    warnings.append("Toán tử không rõ: giữ là chữ")
                }

            case .word(let w):
                terms.append(w)
            }
        }

        // Multi-word phrasal rules ("from last week", "last week", "past 7 days", "older than 30 days",
        // "7 ngày qua", "cũ hơn 30 ngày", "lớn hơn 1 GB", "nhỏ hơn 10 MB", "tải từ github", month names without
        // a year) need lookahead across tokens, so they run as a second pass over the plain words collected above
        // rather than the single-token switch — a plain word is only "spent" (removed from `terms`) once a phrase
        // actually matches, so unmatched runs stay as ordinary filename words.
        let (phraseChips, remainingTerms) = extractPhrasalChips(from: terms, now: now, calendar: calendar)
        chips.append(contentsOf: phraseChips)

        return ParsedSearch(chips: chips, terms: remainingTerms, phrases: phrases, excluded: excluded, warnings: warnings)
    }

    // MARK: - Tokenizing

    private enum RawToken {
        case word(String)
        case phrase(String)
        case excluded(String)
        case fieldValue(field: String, value: String)
    }

    /// Splits on whitespace while keeping `"quoted phrases"` together and recognizing `field:value` (value may
    /// itself be quoted, e.g. `tag:"work in progress"`).
    private static func tokenize(_ text: String) -> [RawToken] {
        var tokens: [RawToken] = []
        let chars = Array(text)
        var i = 0
        func isSpace(_ c: Character) -> Bool { c == " " || c == "\t" || c == "\n" }

        while i < chars.count {
            while i < chars.count, isSpace(chars[i]) { i += 1 }
            guard i < chars.count else { break }

            if chars[i] == "\"" {
                i += 1
                var s = ""
                while i < chars.count, chars[i] != "\"" { s.append(chars[i]); i += 1 }
                if i < chars.count { i += 1 } // closing quote
                if !s.isEmpty { tokens.append(.phrase(s)) }
                continue
            }

            if chars[i] == "-" || chars[i] == "!" {
                let marker = chars[i]
                i += 1
                var s = ""
                while i < chars.count, !isSpace(chars[i]) { s.append(chars[i]); i += 1 }
                if s.isEmpty {
                    // Bare "-" or "!" with nothing after it: not a real exclusion, drop silently rather than
                    // emit an empty excluded term that would never match anything.
                    _ = marker
                } else {
                    tokens.append(.excluded(s))
                }
                continue
            }

            var word = ""
            while i < chars.count, !isSpace(chars[i]) { word.append(chars[i]); i += 1 }

            if let colon = word.firstIndex(of: ":"), colon != word.startIndex, colon != word.index(before: word.endIndex) {
                let field = String(word[word.startIndex..<colon])
                var value = String(word[word.index(after: colon)...])
                // `tag:"work in progress"` — the colon token ends right at the opening quote; absorb the quoted run.
                if value.hasPrefix("\"") {
                    value.removeFirst()
                    var s = value
                    while i < chars.count, chars[i] != "\"" { s.append(chars[i]); i += 1 }
                    if i < chars.count { i += 1 }
                    value = s
                }
                tokens.append(.fieldValue(field: field.lowercased(), value: value))
            } else {
                tokens.append(.word(word))
            }
        }
        return tokens
    }

    /// Longest-match-first over the whole Vietnamese kind-word table, so a 3-word phrase like "ảnh chụp màn hình"
    /// is recognized before its shorter prefix "ảnh" would otherwise win — tried at every position before the
    /// single-word tables (contract vocabulary mixes 1-4 word Vietnamese phrases with single English words).
    private static let maxVietnameseKindPhraseWords = 4

    /// Matches the folded (accent/case-insensitive) words `folded[i...]` against `kindWordsVietnamese`, trying the
    /// longest phrase first. Returns the matched kind and how many words it consumed, or nil.
    private static func matchVietnameseKindPhrase(_ folded: [String], at i: Int) -> (KindFilter, Int)? {
        let maxLen = min(maxVietnameseKindPhraseWords, folded.count - i)
        guard maxLen > 0 else { return nil }
        for len in stride(from: maxLen, through: 1, by: -1) {
            let candidate = folded[i..<(i + len)].joined(separator: " ")
            if let kind = kindWordsVietnamese[candidate] { return (kind, len) }
        }
        return nil
    }

    /// Multi-word phrases ("last week", "this month", "past 7 days", "older than 30 days", Vietnamese equivalents,
    /// bare month names, "size over/under N unit", multi-word Vietnamese kind words) scanned over the already-
    /// tokenized bare words, plus the single-word kind/today/yesterday recognition. Greedy, longest match first at
    /// each position; a word only leaves `terms` when it is consumed by a real match.
    private static func extractPhrasalChips(from words: [String], now: Date, calendar: Calendar) -> (chips: [SearchChip], remaining: [String]) {
        var chips: [SearchChip] = []
        var remaining: [String] = []
        var i = 0
        let lower = words.map { $0.lowercased() }
        let folded = words.map { foldedKey($0) }

        func consume(_ n: Int) { i += n }

        while i < words.count {
            // Multi-word (and single-word) Vietnamese kind phrases, longest first.
            if let (kind, len) = matchVietnameseKindPhrase(folded, at: i) {
                chips.append(SearchChip(field: .kind, value: .kind(kind), uncertain: false))
                consume(len); continue
            }
            // Single-word English kind words.
            if let kind = kindWordsEnglish[lower[i]] {
                chips.append(SearchChip(field: .kind, value: .kind(kind), uncertain: false))
                consume(1); continue
            }
            // "today" / "hôm nay"
            if lower[i] == "today" {
                chips.append(SearchChip(field: .modified, value: .date(.today), uncertain: false))
                consume(1); continue
            }
            if folded[i] == foldedKey("hôm"), i + 1 < words.count, folded[i + 1] == foldedKey("nay") {
                chips.append(SearchChip(field: .modified, value: .date(.today), uncertain: false))
                consume(2); continue
            }
            // "yesterday" / "hôm qua"
            if lower[i] == "yesterday" {
                chips.append(SearchChip(field: .modified, value: .date(.yesterday), uncertain: false))
                consume(1); continue
            }
            if folded[i] == foldedKey("hôm"), i + 1 < words.count, folded[i + 1] == foldedKey("qua") {
                chips.append(SearchChip(field: .modified, value: .date(.yesterday), uncertain: false))
                consume(2); continue
            }
            // "this/last week|month|year" (EN)
            if i + 1 < words.count, lower[i] == "this" || lower[i] == "last" {
                let isLast = lower[i] == "last"
                switch lower[i + 1] {
                case "week":
                    chips.append(SearchChip(field: .modified, value: .date(isLast ? .lastWeek : .thisWeek), uncertain: false))
                    consume(2); continue
                case "month":
                    chips.append(SearchChip(field: .modified, value: .date(isLast ? .lastMonth : .thisMonth), uncertain: false))
                    consume(2); continue
                case "year":
                    chips.append(SearchChip(field: .modified, value: .date(isLast ? .lastYear : .thisYear), uncertain: false))
                    consume(2); continue
                default: break
                }
            }
            // "tuần/tháng/năm này|trước|ngoái" (VI) — Vietnamese postposits the qualifier.
            if i + 1 < words.count {
                let unit = folded[i]
                let qual = folded[i + 1]
                if unit == foldedKey("tuần") {
                    if qual == foldedKey("này") { chips.append(SearchChip(field: .modified, value: .date(.thisWeek), uncertain: false)); consume(2); continue }
                    if qual == foldedKey("trước") { chips.append(SearchChip(field: .modified, value: .date(.lastWeek), uncertain: false)); consume(2); continue }
                }
                if unit == foldedKey("tháng") {
                    if qual == foldedKey("này") { chips.append(SearchChip(field: .modified, value: .date(.thisMonth), uncertain: false)); consume(2); continue }
                    if qual == foldedKey("trước") { chips.append(SearchChip(field: .modified, value: .date(.lastMonth), uncertain: false)); consume(2); continue }
                }
                if unit == foldedKey("năm") {
                    if qual == foldedKey("nay") { chips.append(SearchChip(field: .modified, value: .date(.thisYear), uncertain: false)); consume(2); continue }
                    if qual == foldedKey("ngoái") { chips.append(SearchChip(field: .modified, value: .date(.lastYear), uncertain: false)); consume(2); continue }
                }
            }
            // "from last week" (EN) — "from" is noise before a date phrase; handled by letting "last week" match
            // on the next iteration once "from" itself falls through to `remaining` (it carries no meaning alone).
            if lower[i] == "from", i + 1 < words.count, lower[i + 1] == "last", i + 2 < words.count, lower[i + 2] == "week" {
                chips.append(SearchChip(field: .modified, value: .date(.lastWeek), uncertain: false))
                consume(3); continue
            }
            // "past N days" / "N days ago" family, and "N ngày qua" (VI)
            if lower[i] == "past", i + 2 < words.count, let n = Int(words[i + 1]), lower[i + 2] == "days" {
                chips.append(SearchChip(field: .modified, value: .date(.pastDays(n)), uncertain: false))
                consume(3); continue
            }
            if i + 2 < words.count, let n = Int(words[i]), folded[i + 1] == foldedKey("ngày"), folded[i + 2] == foldedKey("qua") {
                chips.append(SearchChip(field: .modified, value: .date(.pastDays(n)), uncertain: false))
                consume(3); continue
            }
            // "older than N days" (EN) / "cũ hơn N ngày" (VI)
            if lower[i] == "older", i + 3 < words.count, lower[i + 1] == "than", let n = Int(words[i + 2]), lower[i + 3] == "days" {
                chips.append(SearchChip(field: .modified, value: .date(.olderThanDays(n)), uncertain: false))
                consume(4); continue
            }
            if folded[i] == foldedKey("cũ"), i + 3 < words.count, folded[i + 1] == foldedKey("hơn"), let n = Int(words[i + 2]), folded[i + 3] == foldedKey("ngày") {
                chips.append(SearchChip(field: .modified, value: .date(.olderThanDays(n)), uncertain: false))
                consume(4); continue
            }
            // "larger/greater than N UNIT" and "smaller/less than N UNIT" (EN) / "lớn hơn N ĐƠN VỊ", "nhỏ hơn N ĐƠN VỊ" (VI)
            if i + 3 < words.count, (lower[i] == "larger" || lower[i] == "greater" || lower[i] == "bigger"), lower[i + 1] == "than",
               let bytes = parseByteCount(number: words[i + 2], unit: words[i + 3]) {
                chips.append(SearchChip(field: .size, value: .size(.greater, bytes), uncertain: false))
                consume(4); continue
            }
            if i + 3 < words.count, (lower[i] == "smaller" || lower[i] == "less"), lower[i + 1] == "than",
               let bytes = parseByteCount(number: words[i + 2], unit: words[i + 3]) {
                chips.append(SearchChip(field: .size, value: .size(.less, bytes), uncertain: false))
                consume(4); continue
            }
            if i + 3 < words.count, folded[i] == foldedKey("lớn"), folded[i + 1] == foldedKey("hơn"),
               let bytes = parseByteCount(number: words[i + 2], unit: words[i + 3]) {
                chips.append(SearchChip(field: .size, value: .size(.greater, bytes), uncertain: false))
                consume(4); continue
            }
            if i + 3 < words.count, folded[i] == foldedKey("nhỏ"), folded[i + 1] == foldedKey("hơn"),
               let bytes = parseByteCount(number: words[i + 2], unit: words[i + 3]) {
                chips.append(SearchChip(field: .size, value: .size(.less, bytes), uncertain: false))
                consume(4); continue
            }
            // "downloaded from X" (EN) / "tải từ X" (VI)
            if i + 2 < words.count, lower[i] == "downloaded", lower[i + 1] == "from" {
                chips.append(SearchChip(field: .source, value: .text(words[i + 2]), uncertain: false))
                consume(3); continue
            }
            if i + 2 < words.count, folded[i] == foldedKey("tải"), folded[i + 1] == foldedKey("từ") {
                chips.append(SearchChip(field: .source, value: .text(words[i + 2]), uncertain: false))
                consume(3); continue
            }
            // Bare month name, no year ⇒ most recent occurrence, marked uncertain.
            if let month = monthNamesEnglish[lower[i]] {
                chips.append(uncertainMonthChip(month: month, now: now, calendar: calendar))
                consume(1); continue
            }
            if folded[i] == foldedKey("tháng"), i + 1 < words.count, let month = Int(words[i + 1]), (1...12).contains(month) {
                chips.append(uncertainMonthChip(month: month, now: now, calendar: calendar))
                consume(2); continue
            }

            remaining.append(words[i])
            consume(1)
        }
        return (chips, remaining)
    }

    /// A bare "March" / "tháng 3" with no year means the most recent March (this year if it has not passed the
    /// end of that month yet, otherwise last year) — a guess the UI must flag, per contract.
    private static func uncertainMonthChip(month: Int, now: Date, calendar: Calendar) -> SearchChip {
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        let year = month <= currentMonth ? currentYear : currentYear - 1
        return SearchChip(field: .modified, value: .date(.month(year: year, month: month)), uncertain: true)
    }

    // MARK: - field:value chip parsing

    private static func parseFieldValue(field: String, value: String, now: Date, calendar: Calendar) -> SearchChip? {
        switch field {
        case "kind":
            guard let kind = kindTokenAliases[value.lowercased()] else { return nil }
            return SearchChip(field: .kind, value: .kind(kind), uncertain: false)

        case "ext":
            guard !value.isEmpty else { return nil }
            let cleaned = value.hasPrefix(".") ? String(value.dropFirst()) : value
            return SearchChip(field: .ext, value: .text(cleaned.lowercased()), uncertain: false)

        case "tag":
            guard !value.isEmpty else { return nil }
            return SearchChip(field: .tag, value: .text(value), uncertain: false)

        case "from", "source":
            guard !value.isEmpty else { return nil }
            return SearchChip(field: .source, value: .text(value), uncertain: false)

        case "content":
            guard !value.isEmpty else { return nil }
            return SearchChip(field: .content, value: .text(value), uncertain: false)

        case "in", "trong":
            // `in:<folder>` / Vietnamese `trong:<thư mục>` — a path-prefix constraint INSIDE whatever scope is
            // already in effect. Contract (XF-T30 W5a §1, FileOctopus): "in: chỉ thu hẹp trong phạm vi, không bao
            // giờ mở rộng" — this file only records the folder name as text; the actual narrowing-not-widening
            // guarantee lives in `SearchCoordinator.rootsInScope`/`chipsAllow`, which intersect this chip's path
            // with the caller's scope rather than ever searching outside it.
            guard !value.isEmpty else { return nil }
            return SearchChip(field: .folder, value: .text(value), uncertain: false)

        case "size":
            return parseSizeToken(value, defaultField: .size)

        case "modified", "edited":
            // Contract vocabulary: "created/edited/modified" chọn field created/modified — "edited" is a synonym
            // for "modified", not a third field.
            return parseDateToken(value, field: .modified, now: now, calendar: calendar)

        case "created":
            return parseDateToken(value, field: .created, now: now, calendar: calendar)

        default:
            return nil
        }
    }

    /// `size:>1GB`, `size:>=500KB`, `size:<10MB`, `size:1GB` (bare = equal); contract: "`size:` không đơn vị = byte".
    private static func parseSizeToken(_ raw: String, defaultField: SearchChip.Field) -> SearchChip? {
        var s = raw
        var op: SizeOp = .equal
        if s.hasPrefix(">=") { op = .greaterOrEqual; s.removeFirst(2) }
        else if s.hasPrefix("<=") { op = .lessOrEqual; s.removeFirst(2) }
        else if s.hasPrefix(">") { op = .greater; s.removeFirst(1) }
        else if s.hasPrefix("<") { op = .less; s.removeFirst(1) }

        guard let bytes = parseByteCount(raw: s) else { return nil }
        return SearchChip(field: defaultField, value: .size(op, bytes), uncertain: false)
    }

    /// `modified:2026-03-01..2026-03-31` style is out of scope for Wave 1 chips (not in the contract's vocabulary
    /// list); only the relative-keyword vocabulary is recognized here, same words as the plain-sentence parser.
    private static func parseDateToken(_ raw: String, field: SearchChip.Field, now: Date, calendar: Calendar) -> SearchChip? {
        switch raw.lowercased() {
        case "today": return SearchChip(field: field, value: .date(.today), uncertain: false)
        case "yesterday": return SearchChip(field: field, value: .date(.yesterday), uncertain: false)
        case "thisweek": return SearchChip(field: field, value: .date(.thisWeek), uncertain: false)
        case "lastweek": return SearchChip(field: field, value: .date(.lastWeek), uncertain: false)
        case "thismonth": return SearchChip(field: field, value: .date(.thisMonth), uncertain: false)
        case "lastmonth": return SearchChip(field: field, value: .date(.lastMonth), uncertain: false)
        case "thisyear": return SearchChip(field: field, value: .date(.thisYear), uncertain: false)
        case "lastyear": return SearchChip(field: field, value: .date(.lastYear), uncertain: false)
        default: return nil
        }
    }

    /// "1", "GB" -> bytes. Decimal values allowed ("1.5GB"). KiB/MiB/GiB/TiB treated the same as their decimal
    /// counterparts per contract ("KiB… coi như nhau"); no unit suffix on a standalone number is not a size at all
    /// (contract checklist: "\"over 5\" không đơn vị ⇒ không thành chip cỡ, giữ là từ").
    private static func parseByteCount(number: String, unit: String) -> Int64? {
        parseByteCount(raw: number + unit)
    }

    private static func parseByteCount(raw: String) -> Int64? {
        var digits = ""
        var unit = ""
        for c in raw {
            if c.isNumber || c == "." { digits.append(c) } else { unit.append(c) }
        }
        guard let value = Double(digits), !digits.isEmpty else { return nil }
        let multiplier: Double
        switch unit.lowercased() {
        case "b", "": multiplier = 1 // bare "size:" is bytes; a bare number with no unit elsewhere is rejected by the caller
        case "kb", "kib": multiplier = 1024
        case "mb", "mib": multiplier = 1024 * 1024
        case "gb", "gib": multiplier = 1024 * 1024 * 1024
        case "tb", "tib": multiplier = 1024 * 1024 * 1024 * 1024
        default: return nil
        }
        // `Int64(Double)` traps on overflow (measured: "size:99999999999999999999" crashes the app on a plain
        // search keystroke, no force-unwrap needed to trigger it) — clamp into range instead of converting a
        // user-typed number straight into a crash.
        let bytes = value * multiplier
        guard bytes.isFinite else { return Int64.max }
        if bytes >= Double(Int64.max) { return Int64.max }
        if bytes <= Double(Int64.min) { return Int64.min }
        return Int64(bytes)
    }

    // MARK: - Chip editing

    static func removing(chip id: String, from search: ParsedSearch) -> ParsedSearch {
        var result = search
        result.chips.removeAll { $0.id == id }
        return result
    }

    static func replacing(id oldID: String, with chip: SearchChip, in search: ParsedSearch) -> ParsedSearch {
        var result = search
        if let index = result.chips.firstIndex(where: { $0.id == oldID }) {
            result.chips[index] = chip
        } else {
            result.chips.append(chip)
        }
        return result
    }

    // MARK: - Date interval resolution

    static func interval(of range: DateRange, now: Date, calendar: Calendar) -> (start: Date?, end: Date?) {
        func startOfDay(_ d: Date) -> Date { calendar.startOfDay(for: d) }
        func addDays(_ n: Int, to d: Date) -> Date { calendar.date(byAdding: .day, value: n, to: d) ?? d }
        func startOfWeek(_ d: Date) -> Date {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
            return calendar.date(from: comps) ?? startOfDay(d)
        }
        func startOfMonth(_ d: Date) -> Date {
            let comps = calendar.dateComponents([.year, .month], from: d)
            return calendar.date(from: comps) ?? startOfDay(d)
        }
        func startOfYear(_ d: Date) -> Date {
            let comps = calendar.dateComponents([.year], from: d)
            return calendar.date(from: comps) ?? startOfDay(d)
        }

        switch range {
        case .today:
            let s = startOfDay(now)
            return (s, addDays(1, to: s))
        case .yesterday:
            let s = addDays(-1, to: startOfDay(now))
            return (s, addDays(1, to: s))
        case .thisWeek:
            let s = startOfWeek(now)
            return (s, calendar.date(byAdding: .day, value: 7, to: s) ?? s)
        case .lastWeek:
            let s = startOfWeek(now)
            let prevStart = calendar.date(byAdding: .day, value: -7, to: s) ?? s
            return (prevStart, s)
        case .thisMonth:
            let s = startOfMonth(now)
            let e = calendar.date(byAdding: .month, value: 1, to: s) ?? s
            return (s, e)
        case .lastMonth:
            let s = startOfMonth(now)
            let prevStart = calendar.date(byAdding: .month, value: -1, to: s) ?? s
            return (prevStart, s)
        case .thisYear:
            let s = startOfYear(now)
            let e = calendar.date(byAdding: .year, value: 1, to: s) ?? s
            return (s, e)
        case .lastYear:
            let s = startOfYear(now)
            let prevStart = calendar.date(byAdding: .year, value: -1, to: s) ?? s
            return (prevStart, s)
        case .pastDays(let n):
            let s = addDays(-n, to: startOfDay(now))
            return (s, addDays(1, to: startOfDay(now)))
        case .olderThanDays(let n):
            let e = addDays(-n, to: startOfDay(now))
            return (nil, e)
        case .month(let year, let month):
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            let s = calendar.date(from: comps) ?? startOfDay(now)
            let e = calendar.date(byAdding: .month, value: 1, to: s) ?? s
            return (s, e)
        }
    }

    // MARK: - mdfind expression

    /// Builds the AND-joined `mdfind` predicate for the whole parsed search. Dates are resolved to absolute
    /// instants against `now`/`calendar` (not left as relative text — `mdfind` cannot evaluate "last week" itself)
    /// and emitted as `$time.iso(...)` in UTC, per contract. An empty search still needs *some* valid predicate
    /// for `mdfind` to run against (it does not accept an empty string), hence the "match everything" fallback.
    static func mdfindExpression(_ search: ParsedSearch, now: Date, calendar: Calendar) -> String {
        var clauses: [String] = []

        for term in search.terms {
            clauses.append("kMDItemFSName == \"*\(escapeForMDQuery(term))*\"cd")
        }
        for phrase in search.phrases {
            clauses.append("kMDItemFSName == \"*\(escapeForMDQuery(phrase))*\"c")
        }
        for word in search.excluded {
            clauses.append("!(kMDItemFSName == \"*\(escapeForMDQuery(word))*\"cd)")
        }
        for chip in search.chips {
            clauses.append(clause(for: chip, now: now, calendar: calendar))
        }

        guard !clauses.isEmpty else { return "kMDItemFSName == \"*\"" }
        return clauses.joined(separator: " && ")
    }

    private static func clause(for chip: SearchChip, now: Date, calendar: Calendar) -> String {
        switch chip.value {
        case .kind(.screenshots):
            // Measured (2026-10-24, this machine): "public.png" matches every PNG on disk (34 625), while
            // `kMDItemIsScreenCapture` matches only the 147 files Spotlight actually flagged as screen captures —
            // a plain UTI compare here would silently turn "screenshots" into "any PNG".
            return "kMDItemIsScreenCapture = 1"

        case .kind(let kind):
            return "kMDItemContentTypeTree == \"\(contentType(for: kind))\"cd"

        case .date(let range):
            let (start, end) = interval(of: range, now: now, calendar: calendar)
            let key = chip.field == .created ? "kMDItemFSCreationDate" : "kMDItemFSContentChangeDate"
            var parts: [String] = []
            if let start { parts.append("\(key) >= \(isoLiteral(start))") }
            if let end { parts.append("\(key) < \(isoLiteral(end))") }
            if parts.isEmpty { return "kMDItemFSName == \"*\"" }
            return parts.count == 1 ? parts[0] : "(" + parts.joined(separator: " && ") + ")"

        case .size(let op, let bytes):
            let symbol: String
            switch op {
            case .greater: symbol = ">"
            case .less: symbol = "<"
            case .greaterOrEqual: symbol = ">="
            case .lessOrEqual: symbol = "<="
            case .equal: symbol = "=="
            }
            return "kMDItemFSSize \(symbol) \(bytes)"

        case .text(let value):
            switch chip.field {
            case .source:
                return "kMDItemWhereFroms == \"*\(escapeForMDQuery(value))*\"cd"
            case .content:
                return "kMDItemTextContent == \"*\(escapeForMDQuery(value))*\"cd"
            case .tag:
                return "kMDItemUserTags == \"\(escapeForMDQuery(value))\"cd"
            case .ext:
                return "kMDItemFSName == \"*.\(escapeForMDQuery(value))\"c"
            case .folder:
                // `in:<folder>` narrows to paths whose directory chain contains a component named `folder` —
                // `kMDItemPath` is the only Spotlight key with the full path, so this is a substring compare on
                // it, not an exact segment compare (`mdfind` has no path-segment operator); never widens because
                // the caller's own `scopes:`/`-onlyin` argument to `mdfind` already limits the search root — this
                // clause only adds an extra AND, it can only remove matches, never add ones outside that scope.
                return "kMDItemPath == \"*/\(escapeForMDQuery(value))/*\"cd"
            case .kind, .modified, .created, .size:
                // Not reachable given how chips are constructed above, but keeps this switch exhaustive and safe.
                return "kMDItemFSName == \"*\(escapeForMDQuery(value))*\"cd"
            }
        }
    }

    private static func contentType(for kind: KindFilter) -> String {
        switch kind {
        case .pdfs: return "com.adobe.pdf"
        case .images: return "public.image"
        case .videos: return "public.movie"
        case .audio: return "public.audio"
        case .documents: return "public.content"
        case .spreadsheets: return "public.spreadsheet"
        case .presentations: return "public.presentation"
        case .archives: return "public.archive"
        case .folders: return "public.folder"
        case .applications: return "com.apple.application-bundle"
        // `.screenshots` is handled by a dedicated `kMDItemIsScreenCapture` clause in `clause(for:)` above, not by
        // a content-type compare; this arm only exists so the switch stays exhaustive if that ever changes.
        case .screenshots: return "public.png"
        case .code: return "public.source-code"
        case .text: return "public.text"
        }
    }

    private static func isoLiteral(_ date: Date) -> String {
        "$time.iso(\(isoFormatter.string(from: date)))"
    }

    /// Escapes `"` and `\` for a value embedded inside a double-quoted `mdfind` literal.
    private static func escapeForMDQuery(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            if c == "\\" || c == "\"" { out.append("\\") }
            out.append(c)
        }
        return out
    }
}
