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
    /// XF-T37 L4 — FileOctopus 1.0.10's forms: `<7d` (changed within the last 7 days, counted from now), `>2w` (more
    /// than 2 weeks ago), an exact day `2026-10-01`, and an inclusive span `2026-10-01..2026-10-10`.
    case within(Int, DateUnit), olderThan(Int, DateUnit), day(CalendarDay), span(CalendarDay, CalendarDay)
}

enum DateUnit: String, Codable, CaseIterable, Sendable {
    case day, week, month, year
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

/// A calendar day as typed (`2026-10-01`), resolved against the user's calendar only when the interval is built.
struct CalendarDay: Hashable, Codable, Sendable, Comparable {
    var year: Int
    var month: Int
    var day: Int
    static func < (a: CalendarDay, b: CalendarDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
    var text: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

/// XF-T37 L4 — why part of a search was not used as typed. FileOctopus 1.0.10 tells the user each of these (its parser
/// kinds: unknownOperator, invalidValue, inputTooLong, tooManyTerms, unterminatedQuote, emptyOperand); XFinder used to
/// fold them all into one key that no view showed.
struct SearchWarning: Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case unknownFilter, badDate, badSize, badKind, badExtension, emptyValue, unclosedQuote, tooLong, tooManyTerms
    }
    var kind: Kind
    /// The token, field name or limit the message is about (shown verbatim, never translated).
    var subject: String

    /// L10n key of the message. Kinds with a `subject` show it first, in curly quotes; the two limits show the number
    /// between `messageKey` and `trailingKey`.
    var messageKey: String {
        switch kind {
        case .unknownFilter: return "không phải bộ lọc, được tìm như chữ."
        case .badDate: return "không phải ngày. Dùng <7d, >2w, <3m, <1y, today, yesterday, 2026-10-01 hoặc 2026-10-01..2026-10-10."
        case .badSize: return "không phải cỡ tệp. Dùng dạng >5MB, <=200KB hoặc =0."
        case .badKind: return "không phải loại đã biết. Thử pdf, image, video, audio, archive, document, code hoặc folder."
        case .badExtension: return "không phải đuôi tệp."
        case .emptyValue: return "cần một giá trị."
        case .unclosedQuote: return "Thiếu dấu ngoặc kép đóng; phần còn lại được tìm như một cụm."
        case .tooLong: return "Ô tìm dài quá — chỉ dùng "
        case .tooManyTerms: return "Quá nhiều từ — chỉ dùng "
        }
    }
    var trailingKey: String? {
        switch kind {
        case .tooLong: return " ký tự đầu."
        case .tooManyTerms: return " từ đầu."
        default: return nil
        }
    }
    /// Whether `subject` is quoted in front of the message (vs. a sentence of its own or a number inside it).
    var quotesSubject: Bool { kind != .unclosedQuote && kind != .tooLong && kind != .tooManyTerms }
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
    /// What was not used as typed (shown under the search field; the view composes the sentence from the keys).
    var warnings: [SearchWarning]
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
        case .within(let n, let unit): return "within:\(n):\(unit.rawValue)"
        case .olderThan(let n, let unit): return "olderThan:\(n):\(unit.rawValue)"
        case .day(let d): return "day:\(d.text)"
        case .span(let a, let b): return "span:\(a.text):\(b.text)"
        }
    }

    // MARK: - parse

    /// XF-T37 L4 / Q-T37-2 (owner: "the number statistics show is safe and fast, for quick-find habits"). Statistics:
    /// personal/desktop search queries average 1.6 words (Dumais, Stuff I've Seen), and ~90 % of web queries have ≤ 4
    /// words (MSN log, Bendersky & Croft) — 16 terms is 10× the desktop mean and 4× the web 90th percentile. Measured on
    /// this Mac (2026-11-08, `mdfind -onlyin ~`, one wildcard name clause per term): past ~8 terms every extra clause
    /// costs ~75 ms (16 terms 2.1 s, 32 terms 3.6 s, 64 terms 6.0 s), while parsing stays in microseconds (16 terms
    /// 74 µs). 16 terms of ~16 characters ⇒ 256 characters. FileOctopus caps both too; its numbers were not readable.
    static let maxQueryLength: Int = 256
    static let maxTerms: Int = 16

    /// Field names `field:value` understands (anything else is "not a search filter, searched as text").
    static let knownFields: Set<String> = ["kind", "ext", "tag", "tags", "from", "source", "content", "in", "trong",
                                           "size", "modified", "edited", "created"]

    static func parse(_ text: String, now: Date, calendar: Calendar) -> ParsedSearch {
        var chips: [SearchChip] = []
        var terms: [String] = []
        var phrases: [String] = []
        var excluded: [String] = []
        var warnings: [SearchWarning] = []

        var input = text
        if input.count > maxQueryLength {
            input = String(input.prefix(maxQueryLength))
            warnings.append(SearchWarning(kind: .tooLong, subject: String(maxQueryLength)))
        }
        var (tokens, unclosedQuote) = tokenize(input)
        if unclosedQuote { warnings.append(SearchWarning(kind: .unclosedQuote, subject: "")) }
        if tokens.count > maxTerms {
            tokens = Array(tokens.prefix(maxTerms))
            warnings.append(SearchWarning(kind: .tooManyTerms, subject: String(maxTerms)))
        }

        for rawToken in tokens {
            switch rawToken {
            case .phrase(let p):
                phrases.append(p)

            case .excluded(let w):
                excluded.append(w)

            case .emptyField(let field):
                // `kind:` with nothing after it: a known filter with no value is dropped (searching for the literal
                // "kind:" finds nothing useful); an unknown one is just a word that ends in a colon ("Re:").
                if knownFields.contains(field.lowercased()) {
                    warnings.append(SearchWarning(kind: .emptyValue, subject: field))
                } else {
                    terms.append(field + ":")
                }

            case .fieldValue(let field, let value):
                switch parseFieldValue(field: field, value: value, now: now, calendar: calendar) {
                case .chip(let chip):
                    chips.append(chip)
                case .invalid(let kind):
                    // A known filter with a value it cannot read: kept as a filename word (contract: "Toán tử lạ ⇒
                    // giữ là từ + warning"), and the warning now says which form was expected.
                    terms.append("\(field):\(value)")
                    warnings.append(SearchWarning(kind: kind, subject: value))
                case .unknownField:
                    terms.append("\(field):\(value)")
                    warnings.append(SearchWarning(kind: .unknownFilter, subject: field))
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
        case emptyField(String)
    }

    /// Splits on whitespace while keeping `"quoted phrases"` together and recognizing `field:value` (value may
    /// itself be quoted, e.g. `tag:"work in progress"`).
    private static func tokenize(_ text: String) -> (tokens: [RawToken], unclosedQuote: Bool) {
        var tokens: [RawToken] = []
        var unclosedQuote = false
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
                if i < chars.count { i += 1 } else { unclosedQuote = true } // closing quote
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

            if let colon = word.firstIndex(of: ":"), colon != word.startIndex, colon == word.index(before: word.endIndex),
               word.firstIndex(of: ":") == colon {
                tokens.append(.emptyField(String(word[word.startIndex..<colon])))
            } else if let colon = word.firstIndex(of: ":"), colon != word.startIndex, colon != word.index(before: word.endIndex) {
                let field = String(word[word.startIndex..<colon])
                var value = String(word[word.index(after: colon)...])
                // `tag:"work in progress"` — the colon token ends right at the opening quote; absorb the quoted run.
                if value.hasPrefix("\"") {
                    value.removeFirst()
                    var s = value
                    while i < chars.count, chars[i] != "\"" { s.append(chars[i]); i += 1 }
                    if i < chars.count { i += 1 } else { unclosedQuote = true }
                    value = s
                }
                tokens.append(.fieldValue(field: field.lowercased(), value: value))
            } else {
                tokens.append(.word(word))
            }
        }
        return (tokens, unclosedQuote)
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

    private enum FieldResult {
        case chip(SearchChip)
        case invalid(SearchWarning.Kind)
        case unknownField
    }

    private static func parseFieldValue(field: String, value: String, now: Date, calendar: Calendar) -> FieldResult {
        switch field {
        case "kind":
            guard let kind = kindTokenAliases[value.lowercased()] else { return .invalid(.badKind) }
            return .chip(SearchChip(field: .kind, value: .kind(kind), uncertain: false))

        case "ext":
            let cleaned = value.hasPrefix(".") ? String(value.dropFirst()) : value
            // An extension is one name part: no separator, no space, no wildcard, not empty after the dot.
            guard !cleaned.isEmpty, !cleaned.contains(where: { $0 == "/" || $0 == ":" || $0 == "*" || $0.isWhitespace })
            else { return .invalid(.badExtension) }
            return .chip(SearchChip(field: .ext, value: .text(cleaned.lowercased()), uncertain: false))

        case "tag", "tags":
            guard !value.isEmpty else { return .invalid(.emptyValue) }
            return .chip(SearchChip(field: .tag, value: .text(value), uncertain: false))

        case "from", "source":
            guard !value.isEmpty else { return .invalid(.emptyValue) }
            return .chip(SearchChip(field: .source, value: .text(value), uncertain: false))

        case "content":
            guard !value.isEmpty else { return .invalid(.emptyValue) }
            return .chip(SearchChip(field: .content, value: .text(value), uncertain: false))

        case "in", "trong":
            // `in:<folder>` / Vietnamese `trong:<thư mục>` — a path-prefix constraint INSIDE whatever scope is
            // already in effect. Contract (XF-T30 W5a §1, FileOctopus): "in: chỉ thu hẹp trong phạm vi, không bao
            // giờ mở rộng" — this file only records the folder name as text; the actual narrowing-not-widening
            // guarantee lives in `SearchCoordinator.rootsInScope`/`chipsAllow`, which intersect this chip's path
            // with the caller's scope rather than ever searching outside it.
            guard !value.isEmpty else { return .invalid(.emptyValue) }
            return .chip(SearchChip(field: .folder, value: .text(value), uncertain: false))

        case "size":
            guard let chip = parseSizeToken(value, defaultField: .size) else { return .invalid(.badSize) }
            return .chip(chip)

        case "modified", "edited":
            // Contract vocabulary: "created/edited/modified" chọn field created/modified — "edited" is a synonym
            // for "modified", not a third field.
            guard let chip = parseDateToken(value, field: .modified, now: now, calendar: calendar) else { return .invalid(.badDate) }
            return .chip(chip)

        case "created":
            guard let chip = parseDateToken(value, field: .created, now: now, calendar: calendar) else { return .invalid(.badDate) }
            return .chip(chip)

        default:
            return .unknownField
        }
    }

    /// `size:>1GB`, `size:>=500KB`, `size:<10MB`, `size:=0`, `size:1GB` (bare = equal); contract: "`size:` không đơn vị
    /// = byte". FileOctopus 1.0.10's own examples: `>5MB`, `<=200KB`, `=0`.
    private static func parseSizeToken(_ raw: String, defaultField: SearchChip.Field) -> SearchChip? {
        var s = raw
        var op: SizeOp = .equal
        if s.hasPrefix(">=") { op = .greaterOrEqual; s.removeFirst(2) }
        else if s.hasPrefix("<=") { op = .lessOrEqual; s.removeFirst(2) }
        else if s.hasPrefix("==") { op = .equal; s.removeFirst(2) }
        else if s.hasPrefix(">") { op = .greater; s.removeFirst(1) }
        else if s.hasPrefix("<") { op = .less; s.removeFirst(1) }
        else if s.hasPrefix("=") { op = .equal; s.removeFirst(1) }

        guard let bytes = parseByteCount(raw: s) else { return nil }
        return SearchChip(field: defaultField, value: .size(op, bytes), uncertain: false)
    }

    /// The relative keywords (same words as the plain-sentence parser) plus FileOctopus 1.0.10's forms: `<7d` / `>2w` /
    /// `<3m` / `<1y` (d, w, m, y; `<=`/`>=` read the same), an exact day `2026-10-01`, and `2026-10-01..2026-10-10`.
    private static func parseDateToken(_ raw: String, field: SearchChip.Field, now: Date, calendar: Calendar) -> SearchChip? {
        let lower = raw.lowercased()
        func chip(_ range: DateRange) -> SearchChip { SearchChip(field: field, value: .date(range), uncertain: false) }
        switch lower {
        case "today": return chip(.today)
        case "yesterday": return chip(.yesterday)
        case "thisweek": return chip(.thisWeek)
        case "lastweek": return chip(.lastWeek)
        case "thismonth": return chip(.thisMonth)
        case "lastmonth": return chip(.lastMonth)
        case "thisyear": return chip(.thisYear)
        case "lastyear": return chip(.lastYear)
        default: break
        }
        if let first = lower.first, first == "<" || first == ">" {
            var body = Substring(lower.dropFirst())
            if body.hasPrefix("=") { body = body.dropFirst() }
            guard let unitChar = body.last, let count = Int(body.dropLast()), (1...9999).contains(count) else { return nil }
            let unit: DateUnit
            switch unitChar {
            case "d": unit = .day
            case "w": unit = .week
            case "m": unit = .month
            case "y": unit = .year
            default: return nil
            }
            return chip(first == "<" ? .within(count, unit) : .olderThan(count, unit))
        }
        let parts = lower.components(separatedBy: "..")
        if parts.count == 2 {
            guard let a = calendarDay(parts[0], calendar: calendar), let b = calendarDay(parts[1], calendar: calendar) else { return nil }
            return chip(.span(min(a, b), max(a, b)))
        }
        if parts.count == 1, let day = calendarDay(lower, calendar: calendar) { return chip(.day(day)) }
        return nil
    }

    /// `YYYY-MM-DD` that exists on the calendar ("2026-02-30" does not: building it would roll over to March 2).
    static func calendarDay(_ text: String, calendar: Calendar) -> CalendarDay? {
        let fields = text.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0].count == 4, fields[1].count == 2, fields[2].count == 2,
              fields.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]),
              year >= 1, (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = calendar.date(from: comps) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return CalendarDay(year: year, month: month, day: day)
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
        func dayDate(_ d: CalendarDay) -> Date? {
            var comps = DateComponents()
            comps.year = d.year
            comps.month = d.month
            comps.day = d.day
            return calendar.date(from: comps)
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
        case .within(let n, let unit):
            // "<7d": changed less than 7 days ago, counted from this moment (not from midnight) — open-ended at the top.
            return (calendar.date(byAdding: unit.component, value: -n, to: now), nil)
        case .olderThan(let n, let unit):
            return (nil, calendar.date(byAdding: unit.component, value: -n, to: now))
        case .day(let d):
            let s = startOfDay(dayDate(d) ?? now)
            return (s, addDays(1, to: s))
        case .span(let a, let b):
            // Inclusive of the last day: 2026-10-01..2026-10-10 ends at the start of 2026-10-11.
            let s = startOfDay(dayDate(a) ?? now)
            let e = addDays(1, to: startOfDay(dayDate(b) ?? now))
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
                let alternatives = sourcePatterns(for: value).map { "kMDItemWhereFroms == \"*\(escapeForMDQuery($0))*\"cd" }
                return alternatives.count == 1 ? alternatives[0] : "(" + alternatives.joined(separator: " || ") + ")"
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
                // Two clauses ORed: `*/folder/*` for anything nested inside it, `*/folder` for the folder entry
                // itself (no trailing slash after the last path component) — without the second, searching
                // `in:Reports` would never surface the "Reports" folder, only its contents (edge case found in
                // review; see SearchCoordinator.chipsAllow for the matching index-side check).
                let escaped = escapeForMDQuery(value)
                return "(kMDItemPath == \"*/\(escaped)/*\"cd || kMDItemPath == \"*/\(escaped)\"cd)"
            case .kind, .modified, .created, .size:
                // Not reachable given how chips are constructed above, but keeps this switch exhaustive and safe.
                return "kMDItemFSName == \"*\(escapeForMDQuery(value))*\"cd"
            }
        }
    }

    /// XF-T37 L4 — `from:gmail` must find a Gmail attachment, whose "where from" is a Google host that does not contain
    /// the word "gmail". FileOctopus 1.0.10 carries the attachment hosts below (read from its binary); the site hosts
    /// next to them are the services' own. The typed value always stays one of the alternatives.
    static let sourceAliases: [String: [String]] = [
        "gmail": ["mail.google.com", "mail-attachment.googleusercontent.com"],
        "github": ["github.com", "githubusercontent.com"],
        "dropbox": ["dropbox.com", "dropboxusercontent.com"],
        "drive": ["drive.google.com", "drive.usercontent.google.com"],
        "googledrive": ["drive.google.com", "drive.usercontent.google.com"],
        "onedrive": ["onedrive.live.com", "1drv.ms"],
        "outlook": ["outlook.office.com", "outlook.office365.com", "outlook.live.com", "attachments.office.net"],
        "notion": ["notion.so", "notion-static.com"],
        "chatgpt": ["chatgpt.com", "oaiusercontent.com"],
        "openai": ["openai.com", "oaiusercontent.com"],
    ]

    /// Substrings any of which may appear in a file's "where from" list for `from:<value>` to match.
    static func sourcePatterns(for value: String) -> [String] {
        let key = value.lowercased()
        return [value] + (sourceAliases[key] ?? []).filter { !$0.localizedCaseInsensitiveContains(key) }
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
