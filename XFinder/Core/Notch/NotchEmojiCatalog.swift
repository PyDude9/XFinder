import Foundation

/// Categories for the Dynamic Island emoji browser.
/// Pure `Foundation` so `XFinderLogicTests` tests browsing, VI/EN search, recents, and copy state without AppKit.
enum NotchEmojiCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case recent
    case smileys
    case gestures
    case hearts
    case nature
    case food
    case activities
    case travel
    case objects
    case symbols
    case flags

    var id: String { rawValue }

    /// SF Symbol used in the category strip (system glyph, monochrome-safe on black notch).
    var symbolName: String {
        switch self {
        case .recent: return "clock"
        case .smileys: return "face.smiling"
        case .gestures: return "hand.wave"
        case .hearts: return "heart"
        case .nature: return "leaf"
        case .food: return "fork.knife"
        case .activities: return "flame"
        case .travel: return "airplane"
        case .objects: return "laptopcomputer"
        case .symbols: return "sparkles"
        case .flags: return "flag"
        }
    }

    /// Vietnamese localization key matching `L10n.strings.json`.
    var titleKey: String {
        switch self {
        case .recent: return "Gần đây"
        case .smileys: return "Cảm xúc"
        case .gestures: return "Cử chỉ"
        case .hearts: return "Trái tim"
        case .nature: return "Thiên nhiên"
        case .food: return "Đồ ăn"
        case .activities: return "Hoạt động"
        case .travel: return "Du lịch"
        case .objects: return "Đồ vật"
        case .symbols: return "Ký hiệu"
        case .flags: return "Cờ"
        }
    }

    /// Content categories (all categories excluding `.recent`).
    static var browseable: [NotchEmojiCategory] {
        allCases.filter { $0 != .recent }
    }
}

/// One emoji entry in the local Dynamic Island catalog.
///
/// Data provenance: self-authored curated Vietnamese/English keyword dataset using standard Unicode system emoji glyphs
/// (Unicode Emoji 15.1 sequences rendered by Apple Color Emoji on macOS). No third-party external JSON or network fetch.
struct NotchEmojiItem: Identifiable, Equatable, Hashable, Sendable {
    var id: String { glyph }

    /// The exact Unicode grapheme cluster (may contain multiple scalars: ZWJ, VS16, skin tone, keycap, or flag pairs).
    let glyph: String
    let category: NotchEmojiCategory
    let nameVI: String
    let nameEN: String
    let keywordsVI: [String]
    let keywordsEN: [String]

    /// Pre-normalized searchable fields for fast local filtering.
    fileprivate var normalizedNameVI: String { NotchEmojiCatalog.normalizeQuery(nameVI) }
    fileprivate var normalizedNameEN: String { NotchEmojiCatalog.normalizeQuery(nameEN) }
    fileprivate var normalizedTerms: [String] {
        var terms: [String] = [normalizedNameVI, normalizedNameEN]
        terms.append(contentsOf: keywordsVI.map(NotchEmojiCatalog.normalizeQuery))
        terms.append(contentsOf: keywordsEN.map(NotchEmojiCatalog.normalizeQuery))
        return terms.filter { !$0.isEmpty }
    }
}

/// Pure local emoji catalog, VI/EN diacritic-insensitive search engine, and recents rules.
enum NotchEmojiCatalog {
    /// Maximum number of recently used emojis retained.
    static let recentsLimit = 24
    /// `UserDefaults` key for persisting recent emoji glyphs.
    static let recentsDefaultsKey = "notch.emoji.recents"

    // MARK: - Search Normalization

    /// Normalizes a query or keyword for Vietnamese + English matching:
    /// - Lowercases
    /// - Explicitly folds Vietnamese `đ`/`Đ` to `d` (which `folding(.diacriticInsensitive)` does NOT fold)
    /// - Strips combining diacritics
    /// - Collapses whitespace
    static func normalizeQuery(_ raw: String) -> String {
        let lower = raw.lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "ð", with: "d")
        let folded = lower.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let parts = folded.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    static func searchTokens(_ raw: String) -> [String] {
        let normalized = normalizeQuery(raw)
        guard !normalized.isEmpty else { return [] }
        return normalized.split(separator: " ").map(String.init)
    }

    // MARK: - Browsing & Searching

    /// Returns items for a category. For `.recent`, preserves recents order (up to `recentsLimit`),
    /// resolving catalog metadata when available and synthesizing a fallback item for valid custom/multi-scalar graphemes.
    static func items(in category: NotchEmojiCategory, recents: [String]) -> [NotchEmojiItem] {
        if category == .recent {
            let clean = sanitizeRecents(recents)
            return clean.map { glyph in
                if let known = byGlyph[glyph] {
                    return known
                }
                return NotchEmojiItem(
                    glyph: glyph,
                    category: .recent,
                    nameVI: glyph,
                    nameEN: glyph,
                    keywordsVI: [],
                    keywordsEN: []
                )
            }
        }
        return all.filter { $0.category == category }
    }

    /// Searches across `items` (default: full local catalog) using VI/EN keywords, names, and exact glyph matching.
    /// Every whitespace-separated token must match (AND semantics).
    static func search(_ query: String, in items: [NotchEmojiItem] = all) -> [NotchEmojiItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let tokens = searchTokens(trimmed)

        var scored: [(rank: Int, index: Int, item: NotchEmojiItem)] = []
        for (index, item) in items.enumerated() {
            if item.glyph == trimmed {
                scored.append((0, index, item))
                continue
            }
            guard !tokens.isEmpty else { continue }

            let terms = item.normalizedTerms
            let joined = terms.joined(separator: " ")

            // Every query token must appear in the item's searchable text (or match its glyph).
            let allMatch = tokens.allSatisfy { token in
                joined.contains(token) || item.glyph.contains(token)
            }
            guard allMatch else { continue }

            let fullNorm = tokens.joined(separator: " ")
            let rank: Int
            if item.normalizedNameVI == fullNorm || item.normalizedNameEN == fullNorm {
                rank = 1
            } else if terms.contains(where: { $0 == fullNorm }) {
                rank = 2
            } else if item.normalizedNameVI.hasPrefix(fullNorm) || item.normalizedNameEN.hasPrefix(fullNorm) {
                rank = 3
            } else if terms.contains(where: { $0.hasPrefix(fullNorm) }) {
                rank = 4
            } else {
                rank = 5
            }
            scored.append((rank, index, item))
        }

        return scored
            .sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.index < b.index
            }
            .map(\.item)
    }

    // MARK: - Recents Rules (Cap 24 + Deduplication)

    /// Cleans a raw recents array: drops empty/whitespace-only entries, preserves exact multi-scalar Unicode graphemes,
    /// deduplicates keeping the first occurrence, and enforces `limit` (default 24).
    static func sanitizeRecents(_ glyphs: [String], limit: Int = recentsLimit) -> [String] {
        guard limit > 0 else { return [] }
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(min(glyphs.count, limit))

        for glyph in glyphs {
            guard !glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard seen.insert(glyph).inserted else { continue }
            result.append(glyph)
            if result.count >= limit { break }
        }
        return result
    }

    /// Inserts `glyph` at the front of `existing`, removing any prior duplicate and capping at `limit` (default 24).
    static func recordRecent(_ glyph: String, into existing: [String], limit: Int = recentsLimit) -> [String] {
        guard !glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return sanitizeRecents(existing, limit: limit)
        }
        return sanitizeRecents([glyph] + existing, limit: limit)
    }

    // MARK: - Curated Local Catalog

    static let byGlyph: [String: NotchEmojiItem] = {
        var map: [String: NotchEmojiItem] = [:]
        map.reserveCapacity(all.count)
        for item in all where map[item.glyph] == nil {
            map[item.glyph] = item
        }
        return map
    }()

    static let all: [NotchEmojiItem] = [
        // MARK: Smileys (Cảm xúc)
        NotchEmojiItem(glyph: "😀", category: .smileys, nameVI: "Mặt cười tươi", nameEN: "Grinning face", keywordsVI: ["cười", "vui", "hạnh phúc", "tươi"], keywordsEN: ["smile", "happy", "grin", "joy"]),
        NotchEmojiItem(glyph: "😂", category: .smileys, nameVI: "Cười ra nước mắt", nameEN: "Face with tears of joy", keywordsVI: ["cười", "hài", "haha", "vui", "nước mắt"], keywordsEN: ["laugh", "lol", "haha", "funny", "tears"]),
        NotchEmojiItem(glyph: "🥹", category: .smileys, nameVI: "Rưng rưng xúc động", nameEN: "Face holding back tears", keywordsVI: ["xúc động", "cảm động", "rưng rưng", "dễ thương"], keywordsEN: ["touched", "emotional", "cute", "teary"]),
        NotchEmojiItem(glyph: "😊", category: .smileys, nameVI: "Cười mỉm má hồng", nameEN: "Smiling face with smiling eyes", keywordsVI: ["cười", "mỉm cười", "ngại", "hiền", "vui"], keywordsEN: ["blush", "smile", "warm", "happy"]),
        NotchEmojiItem(glyph: "😍", category: .smileys, nameVI: "Mắt trái tim", nameEN: "Smiling face with heart-eyes", keywordsVI: ["yêu", "thích", "mê", "trái tim"], keywordsEN: ["love", "crush", "adore", "heart"]),
        NotchEmojiItem(glyph: "🥰", category: .smileys, nameVI: "Cười ngập tràn yêu thương", nameEN: "Smiling face with hearts", keywordsVI: ["yêu thương", "ấm áp", "hạnh phúc"], keywordsEN: ["love", "affection", "hearts", "warm"]),
        NotchEmojiItem(glyph: "😘", category: .smileys, nameVI: "Gửi nụ hôn", nameEN: "Face blowing a kiss", keywordsVI: ["hôn", "yêu", "thơm"], keywordsEN: ["kiss", "love", "flirt"]),
        NotchEmojiItem(glyph: "😎", category: .smileys, nameVI: "Đeo kính râm ngầu", nameEN: "Smiling face with sunglasses", keywordsVI: ["ngầu", "chất", "kính râm", "tự tin"], keywordsEN: ["cool", "sunglasses", "chill", "awesome"]),
        NotchEmojiItem(glyph: "🤩", category: .smileys, nameVI: "Mắt ngôi sao", nameEN: "Star-struck", keywordsVI: ["ngưỡng mộ", "tuyệt vời", "ngôi sao", "hào hứng"], keywordsEN: ["star", "excited", "amazing", "wow"]),
        NotchEmojiItem(glyph: "🥳", category: .smileys, nameVI: "Ăn mừng tiệc tùng", nameEN: "Partying face", keywordsVI: ["tiệc", "chúc mừng", "sinh nhật", "ăn mừng"], keywordsEN: ["party", "celebrate", "birthday", "congrats"]),
        NotchEmojiItem(glyph: "🤔", category: .smileys, nameVI: "Đang suy nghĩ", nameEN: "Thinking face", keywordsVI: ["suy nghĩ", "nghĩ", "thắc mắc", "nghi ngờ"], keywordsEN: ["think", "hmm", "wonder", "question"]),
        NotchEmojiItem(glyph: "🫡", category: .smileys, nameVI: "Chào nghiêm", nameEN: "Saluting face", keywordsVI: ["chào", "nhận lệnh", "tôn trọng", "rõ"], keywordsEN: ["salute", "respect", "yes sir", "roger"]),
        NotchEmojiItem(glyph: "😮", category: .smileys, nameVI: "Ngạc nhiên", nameEN: "Face with open mouth", keywordsVI: ["ngạc nhiên", "bất ngờ", "ồ"], keywordsEN: ["surprised", "wow", "shocked", "oh"]),
        NotchEmojiItem(glyph: "🤯", category: .smileys, nameVI: "Nổ não", nameEN: "Exploding head", keywordsVI: ["nổ não", "sốc", "quá đỉnh", "bất ngờ"], keywordsEN: ["mind blown", "shocked", "boom", "amazed"]),
        NotchEmojiItem(glyph: "😴", category: .smileys, nameVI: "Đang ngủ", nameEN: "Sleeping face", keywordsVI: ["ngủ", "buồn ngủ", "mệt", "nghỉ"], keywordsEN: ["sleep", "tired", "zzz", "nap"]),
        NotchEmojiItem(glyph: "😢", category: .smileys, nameVI: "Khóc buồn", nameEN: "Crying face", keywordsVI: ["khóc", "buồn", "nước mắt"], keywordsEN: ["cry", "sad", "tear"]),
        NotchEmojiItem(glyph: "😭", category: .smileys, nameVI: "Khóc lớn", nameEN: "Loudly crying face", keywordsVI: ["khóc", "hu hu", "buồn quá", "khóc lóc"], keywordsEN: ["sob", "cry", "sad", "tears"]),
        NotchEmojiItem(glyph: "😡", category: .smileys, nameVI: "Tức giận", nameEN: "Pouting face", keywordsVI: ["giận", "tức", "bực", "cáu"], keywordsEN: ["angry", "mad", "rage", "furious"]),
        NotchEmojiItem(glyph: "😱", category: .smileys, nameVI: "Hoảng sợ", nameEN: "Face screaming in fear", keywordsVI: ["sợ", "hoảng", "hốt hoảng", "kinh ngạc"], keywordsEN: ["scream", "fear", "scared", "omg"]),
        NotchEmojiItem(glyph: "😅", category: .smileys, nameVI: "Cười đổ mồ hôi", nameEN: "Grinning face with sweat", keywordsVI: ["mồ hôi", "ngại", "hú hồn", "cười gượng"], keywordsEN: ["sweat", "phew", "nervous", "awkward"]),
        NotchEmojiItem(glyph: "🫠", category: .smileys, nameVI: "Tan chảy", nameEN: "Melting face", keywordsVI: ["tan chảy", "nóng", "ngượng", "bất lực"], keywordsEN: ["melt", "awkward", "hot", "sarcasm"]),
        NotchEmojiItem(glyph: "🙃", category: .smileys, nameVI: "Mặt lộn ngược", nameEN: "Upside-down face", keywordsVI: ["lộn ngược", "châm biếm", "đùa"], keywordsEN: ["upside down", "silly", "sarcasm"]),

        // MARK: Gestures & People (Cử chỉ)
        NotchEmojiItem(glyph: "👍", category: .gestures, nameVI: "Thích đồng ý", nameEN: "Thumbs up", keywordsVI: ["thích", "đồng ý", "tốt", "ok", "duyệt"], keywordsEN: ["thumbs up", "like", "ok", "yes", "approve"]),
        NotchEmojiItem(glyph: "👍🏽", category: .gestures, nameVI: "Thích tông da trung bình", nameEN: "Thumbs up medium skin tone", keywordsVI: ["thích", "đồng ý", "ok", "tông da"], keywordsEN: ["thumbs up", "like", "ok", "skin tone"]),
        NotchEmojiItem(glyph: "👎", category: .gestures, nameVI: "Không thích", nameEN: "Thumbs down", keywordsVI: ["không thích", "từ chối", "tệ", "không"], keywordsEN: ["thumbs down", "dislike", "no", "bad"]),
        NotchEmojiItem(glyph: "👏", category: .gestures, nameVI: "Vỗ tay", nameEN: "Clapping hands", keywordsVI: ["vỗ tay", "chúc mừng", "hoan hô", "giỏi"], keywordsEN: ["clap", "applause", "bravo", "congrats"]),
        NotchEmojiItem(glyph: "🙌", category: .gestures, nameVI: "Giơ tay ăn mừng", nameEN: "Raising hands", keywordsVI: ["hoan hô", "ăn mừng", "tuyệt", "giơ tay"], keywordsEN: ["hooray", "celebrate", "praise", "hands"]),
        NotchEmojiItem(glyph: "🙏", category: .gestures, nameVI: "Cảm ơn chắp tay", nameEN: "Folded hands", keywordsVI: ["cảm ơn", "xin lỗi", "cầu nguyện", "chắp tay"], keywordsEN: ["thanks", "please", "pray", "grateful"]),
        NotchEmojiItem(glyph: "🤝", category: .gestures, nameVI: "Bắt tay hợp tác", nameEN: "Handshake", keywordsVI: ["bắt tay", "hợp tác", "đồng ý", "thỏa thuận"], keywordsEN: ["handshake", "deal", "agree", "partner"]),
        NotchEmojiItem(glyph: "👋", category: .gestures, nameVI: "Vẫy tay chào", nameEN: "Waving hand", keywordsVI: ["chào", "tạm biệt", "vẫy tay", "xin chào"], keywordsEN: ["wave", "hello", "hi", "bye"]),
        NotchEmojiItem(glyph: "👌", category: .gestures, nameVI: "Bàn tay OK", nameEN: "OK hand", keywordsVI: ["ok", "ổn", "chuẩn", "tuyệt"], keywordsEN: ["ok", "perfect", "good", "fine"]),
        NotchEmojiItem(glyph: "✌️", category: .gestures, nameVI: "Chiến thắng hòa bình", nameEN: "Victory hand", keywordsVI: ["chiến thắng", "hòa bình", "hai ngón"], keywordsEN: ["peace", "victory", "two"]),
        NotchEmojiItem(glyph: "🤞", category: .gestures, nameVI: "Chúc may mắn", nameEN: "Crossed fingers", keywordsVI: ["may mắn", "hy vọng", "cầu may"], keywordsEN: ["luck", "hope", "fingers crossed"]),
        NotchEmojiItem(glyph: "💪", category: .gestures, nameVI: "Cơ bắp cố lên", nameEN: "Flexed biceps", keywordsVI: ["mạnh mẽ", "cố lên", "sức mạnh", "tập gym"], keywordsEN: ["strong", "muscle", "power", "workout"]),
        NotchEmojiItem(glyph: "🫶", category: .gestures, nameVI: "Bàn tay thả tim", nameEN: "Heart hands", keywordsVI: ["thả tim", "yêu", "cảm ơn"], keywordsEN: ["heart hands", "love", "appreciate"]),
        NotchEmojiItem(glyph: "👨‍💻", category: .gestures, nameVI: "Lập trình viên", nameEN: "Man technologist", keywordsVI: ["lập trình", "code", "dev", "máy tính", "công nghệ"], keywordsEN: ["developer", "coder", "programmer", "tech", "laptop"]),
        NotchEmojiItem(glyph: "👩‍🚀", category: .gestures, nameVI: "Nữ phi hành gia", nameEN: "Woman astronaut", keywordsVI: ["phi hành gia", "vũ trụ", "không gian"], keywordsEN: ["astronaut", "space", "rocket", "launch"]),
        NotchEmojiItem(glyph: "👨‍👩‍👧‍👦", category: .gestures, nameVI: "Gia đình", nameEN: "Family", keywordsVI: ["gia đình", "nhà", "người thân"], keywordsEN: ["family", "parents", "kids", "home"]),
        NotchEmojiItem(glyph: "🧑‍🎨", category: .gestures, nameVI: "Nghệ sĩ thiết kế", nameEN: "Artist", keywordsVI: ["nghệ sĩ", "thiết kế", "vẽ", "sáng tạo"], keywordsEN: ["artist", "designer", "paint", "creative"]),

        // MARK: Hearts (Trái tim)
        NotchEmojiItem(glyph: "❤️", category: .hearts, nameVI: "Trái tim đỏ", nameEN: "Red heart", keywordsVI: ["trái tim", "tim", "yêu", "đỏ", "thương"], keywordsEN: ["heart", "love", "red", "like"]),
        NotchEmojiItem(glyph: "❤️‍🔥", category: .hearts, nameVI: "Trái tim bốc cháy", nameEN: "Heart on fire", keywordsVI: ["trái tim", "cháy", "đam mê", "nhiệt huyết"], keywordsEN: ["heart on fire", "passion", "love", "burn"]),
        NotchEmojiItem(glyph: "🧡", category: .hearts, nameVI: "Trái tim cam", nameEN: "Orange heart", keywordsVI: ["trái tim", "tim", "cam"], keywordsEN: ["orange heart", "love", "warm"]),
        NotchEmojiItem(glyph: "💛", category: .hearts, nameVI: "Trái tim vàng", nameEN: "Yellow heart", keywordsVI: ["trái tim", "tim", "vàng", "bạn bè"], keywordsEN: ["yellow heart", "friendship", "gold"]),
        NotchEmojiItem(glyph: "💚", category: .hearts, nameVI: "Trái tim xanh lá", nameEN: "Green heart", keywordsVI: ["trái tim", "tim", "xanh lá"], keywordsEN: ["green heart", "nature", "love"]),
        NotchEmojiItem(glyph: "💙", category: .hearts, nameVI: "Trái tim xanh dương", nameEN: "Blue heart", keywordsVI: ["trái tim", "tim", "xanh dương", "tin tưởng"], keywordsEN: ["blue heart", "trust", "love"]),
        NotchEmojiItem(glyph: "💜", category: .hearts, nameVI: "Trái tim tím", nameEN: "Purple heart", keywordsVI: ["trái tim", "tim", "tím"], keywordsEN: ["purple heart", "love"]),
        NotchEmojiItem(glyph: "🖤", category: .hearts, nameVI: "Trái tim đen", nameEN: "Black heart", keywordsVI: ["trái tim", "tim", "đen"], keywordsEN: ["black heart", "dark"]),
        NotchEmojiItem(glyph: "🤍", category: .hearts, nameVI: "Trái tim trắng", nameEN: "White heart", keywordsVI: ["trái tim", "tim", "trắng", "thuần khiết"], keywordsEN: ["white heart", "pure"]),
        NotchEmojiItem(glyph: "💔", category: .hearts, nameVI: "Trái tim tan vỡ", nameEN: "Broken heart", keywordsVI: ["tan vỡ", "thất tình", "buồn", "trái tim"], keywordsEN: ["broken heart", "sad", "heartbreak"]),
        NotchEmojiItem(glyph: "💖", category: .hearts, nameVI: "Trái tim lấp lánh", nameEN: "Sparkling heart", keywordsVI: ["trái tim", "lấp lánh", "yêu"], keywordsEN: ["sparkling heart", "love", "shine"]),
        NotchEmojiItem(glyph: "💯", category: .hearts, nameVI: "Một trăm điểm", nameEN: "Hundred points", keywordsVI: ["trăm điểm", "hoàn hảo", "chuẩn", "100"], keywordsEN: ["100", "perfect", "score", "keep it real"]),

        // MARK: Nature (Thiên nhiên)
        NotchEmojiItem(glyph: "☀️", category: .nature, nameVI: "Mặt trời nắng", nameEN: "Sun", keywordsVI: ["mặt trời", "nắng", "sáng", "thời tiết"], keywordsEN: ["sun", "sunny", "weather", "bright"]),
        NotchEmojiItem(glyph: "🌙", category: .nature, nameVI: "Mặt trăng khuyết", nameEN: "Crescent moon", keywordsVI: ["mặt trăng", "đêm", "tối", "trăng"], keywordsEN: ["moon", "night", "sleep", "dark"]),
        NotchEmojiItem(glyph: "⭐", category: .nature, nameVI: "Ngôi sao", nameEN: "Star", keywordsVI: ["ngôi sao", "sao", "nổi bật", "đánh giá"], keywordsEN: ["star", "favorite", "rating"]),
        NotchEmojiItem(glyph: "🌈", category: .nature, nameVI: "Cầu vồng", nameEN: "Rainbow", keywordsVI: ["cầu vồng", "màu sắc", "thời tiết"], keywordsEN: ["rainbow", "color", "pride", "weather"]),
        NotchEmojiItem(glyph: "🌧️", category: .nature, nameVI: "Đám mây mưa", nameEN: "Cloud with rain", keywordsVI: ["mưa", "mây", "thời tiết"], keywordsEN: ["rain", "cloud", "weather"]),
        NotchEmojiItem(glyph: "❄️", category: .nature, nameVI: "Bông tuyết", nameEN: "Snowflake", keywordsVI: ["tuyết", "lạnh", "mùa đông"], keywordsEN: ["snow", "cold", "winter", "freeze"]),
        NotchEmojiItem(glyph: "🌸", category: .nature, nameVI: "Hoa anh đào", nameEN: "Cherry blossom", keywordsVI: ["hoa", "anh đào", "mùa xuân", "hồng"], keywordsEN: ["flower", "blossom", "sakura", "spring"]),
        NotchEmojiItem(glyph: "🌿", category: .nature, nameVI: "Nhánh lá xanh", nameEN: "Herb", keywordsVI: ["lá", "cây", "xanh", "thiên nhiên"], keywordsEN: ["leaf", "plant", "herb", "green", "nature"]),
        NotchEmojiItem(glyph: "🍀", category: .nature, nameVI: "Cỏ bốn lá", nameEN: "Four leaf clover", keywordsVI: ["may mắn", "cỏ bốn lá", "lá"], keywordsEN: ["clover", "lucky", "green"]),
        NotchEmojiItem(glyph: "🐱", category: .nature, nameVI: "Mặt mèo", nameEN: "Cat face", keywordsVI: ["mèo", "thú cưng", "động vật"], keywordsEN: ["cat", "kitty", "pet", "animal"]),
        NotchEmojiItem(glyph: "🐶", category: .nature, nameVI: "Mặt chó", nameEN: "Dog face", keywordsVI: ["chó", "cún", "thú cưng", "động vật"], keywordsEN: ["dog", "puppy", "pet", "animal"]),
        NotchEmojiItem(glyph: "🦋", category: .nature, nameVI: "Con bướm", nameEN: "Butterfly", keywordsVI: ["bướm", "côn trùng", "đẹp"], keywordsEN: ["butterfly", "insect", "pretty"]),

        // MARK: Food & Drink (Đồ ăn)
        NotchEmojiItem(glyph: "☕", category: .food, nameVI: "Cà phê nóng", nameEN: "Hot beverage", keywordsVI: ["cà phê", "cafe", "trà", "nóng", "uống", "sáng"], keywordsEN: ["coffee", "cafe", "tea", "hot", "drink", "morning"]),
        NotchEmojiItem(glyph: "🧋", category: .food, nameVI: "Trà sữa trân châu", nameEN: "Bubble tea", keywordsVI: ["trà sữa", "trân châu", "uống"], keywordsEN: ["boba", "bubble tea", "milk tea", "drink"]),
        NotchEmojiItem(glyph: "🍜", category: .food, nameVI: "Tô phở mì nóng", nameEN: "Steaming bowl", keywordsVI: ["phở", "mì", "bún", "đồ ăn", "nóng"], keywordsEN: ["noodles", "ramen", "pho", "soup", "food"]),
        NotchEmojiItem(glyph: "🍕", category: .food, nameVI: "Bánh pizza", nameEN: "Pizza", keywordsVI: ["pizza", "bánh", "đồ ăn", "tiệc"], keywordsEN: ["pizza", "slice", "food", "party"]),
        NotchEmojiItem(glyph: "🍔", category: .food, nameVI: "Bánh burger", nameEN: "Hamburger", keywordsVI: ["burger", "bánh mì kẹp", "đồ ăn nhanh"], keywordsEN: ["burger", "hamburger", "fast food"]),
        NotchEmojiItem(glyph: "🍣", category: .food, nameVI: "Sushi", nameEN: "Sushi", keywordsVI: ["sushi", "nhật bản", "cá", "đồ ăn"], keywordsEN: ["sushi", "japanese", "food"]),
        NotchEmojiItem(glyph: "🍰", category: .food, nameVI: "Bánh kem", nameEN: "Shortcake", keywordsVI: ["bánh kem", "bánh ngọt", "sinh nhật", "tráng miệng"], keywordsEN: ["cake", "dessert", "sweet", "birthday"]),
        NotchEmojiItem(glyph: "🍎", category: .food, nameVI: "Quả táo đỏ", nameEN: "Red apple", keywordsVI: ["táo", "trái cây", "hoa quả"], keywordsEN: ["apple", "fruit", "red"]),
        NotchEmojiItem(glyph: "🥑", category: .food, nameVI: "Quả bơ", nameEN: "Avocado", keywordsVI: ["bơ", "trái cây", "xanh"], keywordsEN: ["avocado", "fruit", "healthy"]),
        NotchEmojiItem(glyph: "🍺", category: .food, nameVI: "Cốc bia", nameEN: "Beer mug", keywordsVI: ["bia", "uống", "nhậu", "tiệc"], keywordsEN: ["beer", "drink", "cheers", "pub"]),
        NotchEmojiItem(glyph: "🥂", category: .food, nameVI: "Cụng ly chúc mừng", nameEN: "Clinking glasses", keywordsVI: ["cụng ly", "chúc mừng", "rượu", "tiệc"], keywordsEN: ["cheers", "toast", "champagne", "celebrate"]),

        // MARK: Activities (Hoạt động)
        NotchEmojiItem(glyph: "🔥", category: .activities, nameVI: "Ngọn lửa cháy", nameEN: "Fire", keywordsVI: ["lửa", "cháy", "nóng", "đỉnh", "hot"], keywordsEN: ["fire", "flame", "lit", "hot", "burn"]),
        NotchEmojiItem(glyph: "🎉", category: .activities, nameVI: "Pháo giấy chúc mừng", nameEN: "Party popper", keywordsVI: ["chúc mừng", "tiệc", "pháo giấy", "ăn mừng"], keywordsEN: ["party", "tada", "celebrate", "congrats"]),
        NotchEmojiItem(glyph: "🏆", category: .activities, nameVI: "Cúp vô địch", nameEN: "Trophy", keywordsVI: ["cúp", "vô địch", "chiến thắng", "giải thưởng"], keywordsEN: ["trophy", "winner", "award", "champion"]),
        NotchEmojiItem(glyph: "🎯", category: .activities, nameVI: "Bia ngắm mục tiêu", nameEN: "Bullseye", keywordsVI: ["mục tiêu", "chính xác", "trúng đích"], keywordsEN: ["target", "goal", "bullseye", "focus"]),
        NotchEmojiItem(glyph: "🎮", category: .activities, nameVI: "Tay cầm chơi game", nameEN: "Video game", keywordsVI: ["game", "trò chơi", "tay cầm", "giải trí"], keywordsEN: ["game", "gaming", "controller", "play"]),
        NotchEmojiItem(glyph: "🎵", category: .activities, nameVI: "Nốt nhạc", nameEN: "Musical note", keywordsVI: ["nhạc", "âm nhạc", "nốt nhạc", "bài hát"], keywordsEN: ["music", "note", "song", "audio"]),
        NotchEmojiItem(glyph: "🎬", category: .activities, nameVI: "Bảng quay phim", nameEN: "Clapper board", keywordsVI: ["phim", "video", "quay phim", "điện ảnh"], keywordsEN: ["movie", "film", "video", "action"]),
        NotchEmojiItem(glyph: "⚽", category: .activities, nameVI: "Bóng đá", nameEN: "Soccer ball", keywordsVI: ["bóng đá", "thể thao", "đá banh"], keywordsEN: ["soccer", "football", "sport"]),
        NotchEmojiItem(glyph: "🏃", category: .activities, nameVI: "Chạy bộ", nameEN: "Person running", keywordsVI: ["chạy", "thể thao", "nhanh", "vận động"], keywordsEN: ["run", "running", "sprint", "fast"]),
        NotchEmojiItem(glyph: "🎨", category: .activities, nameVI: "Bảng màu vẽ", nameEN: "Artist palette", keywordsVI: ["vẽ", "màu sắc", "thiết kế", "nghệ thuật"], keywordsEN: ["art", "design", "palette", "color"]),

        // MARK: Travel & Places (Du lịch)
        NotchEmojiItem(glyph: "🚀", category: .travel, nameVI: "Tên lửa phóng", nameEN: "Rocket", keywordsVI: ["tên lửa", "ra mắt", "nhanh", "bay", "khởi chạy"], keywordsEN: ["rocket", "launch", "ship", "fast", "space"]),
        NotchEmojiItem(glyph: "✈️", category: .travel, nameVI: "Máy bay", nameEN: "Airplane", keywordsVI: ["máy bay", "du lịch", "bay", "chuyến bay"], keywordsEN: ["airplane", "plane", "flight", "travel"]),
        NotchEmojiItem(glyph: "🚗", category: .travel, nameVI: "Ô tô xe hơi", nameEN: "Automobile", keywordsVI: ["ô tô", "xe hơi", "xe", "lái xe"], keywordsEN: ["car", "drive", "auto", "vehicle"]),
        NotchEmojiItem(glyph: "🏠", category: .travel, nameVI: "Ngôi nhà", nameEN: "House", keywordsVI: ["nhà", "ngôi nhà", "trang chủ"], keywordsEN: ["house", "home"]),
        NotchEmojiItem(glyph: "🌍", category: .travel, nameVI: "Trái đất toàn cầu", nameEN: "Globe", keywordsVI: ["trái đất", "thế giới", "toàn cầu", "mạng"], keywordsEN: ["earth", "world", "globe", "global"]),
        NotchEmojiItem(glyph: "🏖️", category: .travel, nameVI: "Bãi biển nghỉ mát", nameEN: "Beach with umbrella", keywordsVI: ["biển", "bãi biển", "nghỉ mát", "du lịch"], keywordsEN: ["beach", "vacation", "summer", "holiday"]),
        NotchEmojiItem(glyph: "⛰️", category: .travel, nameVI: "Ngọn núi", nameEN: "Mountain", keywordsVI: ["núi", "leo núi", "thiên nhiên"], keywordsEN: ["mountain", "hike", "nature"]),
        NotchEmojiItem(glyph: "⏰", category: .travel, nameVI: "Đồng hồ báo thức", nameEN: "Alarm clock", keywordsVI: ["đồng hồ", "báo thức", "thời gian", "hẹn giờ"], keywordsEN: ["alarm", "clock", "time", "timer"]),
        NotchEmojiItem(glyph: "⏳", category: .travel, nameVI: "Đồng hồ cát", nameEN: "Hourglass", keywordsVI: ["đồng hồ cát", "chờ", "thời gian", "đang tải"], keywordsEN: ["hourglass", "wait", "loading", "time"]),

        // MARK: Objects (Đồ vật)
        NotchEmojiItem(glyph: "💻", category: .objects, nameVI: "Máy tính xách tay", nameEN: "Laptop", keywordsVI: ["máy tính", "laptop", "làm việc", "code"], keywordsEN: ["laptop", "computer", "mac", "work", "code"]),
        NotchEmojiItem(glyph: "📱", category: .objects, nameVI: "Điện thoại di động", nameEN: "Mobile phone", keywordsVI: ["điện thoại", "di động", "iphone"], keywordsEN: ["phone", "mobile", "iphone", "smartphone"]),
        NotchEmojiItem(glyph: "⌨️", category: .objects, nameVI: "Bàn phím", nameEN: "Keyboard", keywordsVI: ["bàn phím", "gõ", "phím"], keywordsEN: ["keyboard", "type", "input"]),
        NotchEmojiItem(glyph: "🎧", category: .objects, nameVI: "Tai nghe", nameEN: "Headphone", keywordsVI: ["tai nghe", "nhạc", "âm thanh"], keywordsEN: ["headphones", "audio", "music", "listen"]),
        NotchEmojiItem(glyph: "📷", category: .objects, nameVI: "Máy ảnh", nameEN: "Camera", keywordsVI: ["máy ảnh", "chụp ảnh", "ảnh"], keywordsEN: ["camera", "photo", "picture"]),
        NotchEmojiItem(glyph: "💡", category: .objects, nameVI: "Bóng đèn ý tưởng", nameEN: "Light bulb", keywordsVI: ["ý tưởng", "bóng đèn", "sáng tạo", "gợi ý"], keywordsEN: ["idea", "bulb", "light", "tip"]),
        NotchEmojiItem(glyph: "📝", category: .objects, nameVI: "Ghi chú tài liệu", nameEN: "Memo", keywordsVI: ["ghi chú", "viết", "tài liệu", "nháp"], keywordsEN: ["note", "memo", "write", "doc"]),
        NotchEmojiItem(glyph: "📁", category: .objects, nameVI: "Thư mục", nameEN: "File folder", keywordsVI: ["thư mục", "tệp", "tài liệu", "folder"], keywordsEN: ["folder", "file", "directory"]),
        NotchEmojiItem(glyph: "🔒", category: .objects, nameVI: "Ổ khóa bảo mật", nameEN: "Locked", keywordsVI: ["khóa", "bảo mật", "riêng tư"], keywordsEN: ["lock", "secure", "private", "security"]),
        NotchEmojiItem(glyph: "🔑", category: .objects, nameVI: "Chìa khóa", nameEN: "Key", keywordsVI: ["chìa khóa", "mật khẩu", "quyền"], keywordsEN: ["key", "password", "access"]),
        NotchEmojiItem(glyph: "🔧", category: .objects, nameVI: "Cờ lê sửa chữa", nameEN: "Wrench", keywordsVI: ["sửa", "công cụ", "cài đặt", "kỹ thuật"], keywordsEN: ["wrench", "fix", "tool", "settings"]),
        NotchEmojiItem(glyph: "📦", category: .objects, nameVI: "Hộp gói hàng", nameEN: "Package", keywordsVI: ["gói", "hộp", "đóng gói", "phát hành"], keywordsEN: ["package", "box", "ship", "release"]),
        NotchEmojiItem(glyph: "🔍", category: .objects, nameVI: "Kính lúp tìm kiếm", nameEN: "Magnifying glass", keywordsVI: ["tìm kiếm", "kính lúp", "tra cứu"], keywordsEN: ["search", "find", "zoom", "inspect"]),
        NotchEmojiItem(glyph: "📎", category: .objects, nameVI: "Kẹp giấy đính kèm", nameEN: "Paperclip", keywordsVI: ["đính kèm", "kẹp giấy", "tệp"], keywordsEN: ["paperclip", "attach", "attachment"]),
        NotchEmojiItem(glyph: "📅", category: .objects, nameVI: "Lịch ngày", nameEN: "Calendar", keywordsVI: ["lịch", "ngày", "sự kiện", "lịch trình"], keywordsEN: ["calendar", "date", "schedule", "event"]),
        NotchEmojiItem(glyph: "🎁", category: .objects, nameVI: "Hộp quà", nameEN: "Wrapped gift", keywordsVI: ["quà", "tặng", "sinh nhật"], keywordsEN: ["gift", "present", "birthday"]),

        // MARK: Symbols (Ký hiệu)
        NotchEmojiItem(glyph: "✨", category: .symbols, nameVI: "Lấp lánh tinh tú", nameEN: "Sparkles", keywordsVI: ["lấp lánh", "mới", "đẹp", "ai", "ma thuật"], keywordsEN: ["sparkles", "magic", "new", "ai", "clean"]),
        NotchEmojiItem(glyph: "✅", category: .symbols, nameVI: "Dấu tích hoàn thành", nameEN: "Check mark button", keywordsVI: ["xong", "hoàn thành", "đúng", "tích xanh", "ok"], keywordsEN: ["check", "done", "complete", "yes", "pass"]),
        NotchEmojiItem(glyph: "❌", category: .symbols, nameVI: "Dấu nhân lỗi", nameEN: "Cross mark", keywordsVI: ["lỗi", "sai", "hủy", "xóa", "không"], keywordsEN: ["cross", "error", "no", "fail", "cancel"]),
        NotchEmojiItem(glyph: "⚠️", category: .symbols, nameVI: "Cảnh báo", nameEN: "Warning", keywordsVI: ["cảnh báo", "chú ý", "nguy hiểm", "lưu ý"], keywordsEN: ["warning", "alert", "caution", "danger"]),
        NotchEmojiItem(glyph: "ℹ️", category: .symbols, nameVI: "Thông tin", nameEN: "Information", keywordsVI: ["thông tin", "chi tiết", "hướng dẫn"], keywordsEN: ["info", "information", "details"]),
        NotchEmojiItem(glyph: "❓", category: .symbols, nameVI: "Dấu hỏi", nameEN: "Question mark", keywordsVI: ["hỏi", "thắc mắc", "câu hỏi"], keywordsEN: ["question", "help", "what"]),
        NotchEmojiItem(glyph: "⚡", category: .symbols, nameVI: "Tia chớp nhanh", nameEN: "High voltage", keywordsVI: ["tia chớp", "nhanh", "điện", "năng lượng"], keywordsEN: ["lightning", "fast", "bolt", "power", "zap"]),
        NotchEmojiItem(glyph: "🔔", category: .symbols, nameVI: "Chuông thông báo", nameEN: "Bell", keywordsVI: ["chuông", "thông báo", "nhắc nhở"], keywordsEN: ["bell", "notification", "alert", "remind"]),
        NotchEmojiItem(glyph: "📌", category: .symbols, nameVI: "Ghim", nameEN: "Pushpin", keywordsVI: ["ghim", "đánh dấu", "quan trọng"], keywordsEN: ["pin", "pushpin", "bookmark"]),
        NotchEmojiItem(glyph: "🔗", category: .symbols, nameVI: "Liên kết", nameEN: "Link", keywordsVI: ["liên kết", "link", "đường dẫn", "url"], keywordsEN: ["link", "url", "chain"]),
        NotchEmojiItem(glyph: "➡️", category: .symbols, nameVI: "Mũi tên phải", nameEN: "Right arrow", keywordsVI: ["mũi tên", "tiếp", "phải"], keywordsEN: ["arrow", "right", "next"]),
        NotchEmojiItem(glyph: "1️⃣", category: .symbols, nameVI: "Phím số một", nameEN: "Keycap digit one", keywordsVI: ["số một", "một", "thứ nhất", "1"], keywordsEN: ["one", "1", "first", "keycap"]),
        NotchEmojiItem(glyph: "2️⃣", category: .symbols, nameVI: "Phím số hai", nameEN: "Keycap digit two", keywordsVI: ["số hai", "hai", "thứ hai", "2"], keywordsEN: ["two", "2", "second", "keycap"]),
        NotchEmojiItem(glyph: "#️⃣", category: .symbols, nameVI: "Phím dấu thăng", nameEN: "Keycap number sign", keywordsVI: ["dấu thăng", "hashtag", "số"], keywordsEN: ["hash", "hashtag", "number", "keycap"]),

        // MARK: Flags (Cờ)
        NotchEmojiItem(glyph: "🇻🇳", category: .flags, nameVI: "Cờ Việt Nam", nameEN: "Flag Vietnam", keywordsVI: ["việt nam", "vn", "cờ", "quốc kỳ"], keywordsEN: ["vietnam", "vn", "flag"]),
        NotchEmojiItem(glyph: "🇺🇸", category: .flags, nameVI: "Cờ Hoa Kỳ", nameEN: "Flag United States", keywordsVI: ["mỹ", "hoa kỳ", "us", "usa", "cờ"], keywordsEN: ["usa", "us", "america", "united states", "flag"]),
        NotchEmojiItem(glyph: "🇯🇵", category: .flags, nameVI: "Cờ Nhật Bản", nameEN: "Flag Japan", keywordsVI: ["nhật bản", "nhật", "jp", "cờ"], keywordsEN: ["japan", "jp", "flag"]),
        NotchEmojiItem(glyph: "🇰🇷", category: .flags, nameVI: "Cờ Hàn Quốc", nameEN: "Flag South Korea", keywordsVI: ["hàn quốc", "hàn", "kr", "cờ"], keywordsEN: ["korea", "south korea", "kr", "flag"]),
        NotchEmojiItem(glyph: "🇬🇧", category: .flags, nameVI: "Cờ Vương quốc Anh", nameEN: "Flag United Kingdom", keywordsVI: ["anh", "vương quốc anh", "uk", "cờ"], keywordsEN: ["uk", "britain", "england", "united kingdom", "flag"]),
        NotchEmojiItem(glyph: "🇫🇷", category: .flags, nameVI: "Cờ Pháp", nameEN: "Flag France", keywordsVI: ["pháp", "fr", "cờ"], keywordsEN: ["france", "fr", "flag"]),
        NotchEmojiItem(glyph: "🇩🇪", category: .flags, nameVI: "Cờ Đức", nameEN: "Flag Germany", keywordsVI: ["đức", "de", "cờ"], keywordsEN: ["germany", "de", "flag"]),
        NotchEmojiItem(glyph: "🇸🇬", category: .flags, nameVI: "Cờ Singapore", nameEN: "Flag Singapore", keywordsVI: ["singapore", "sg", "cờ"], keywordsEN: ["singapore", "sg", "flag"]),
        NotchEmojiItem(glyph: "🏁", category: .flags, nameVI: "Cờ đích", nameEN: "Chequered flag", keywordsVI: ["đích", "hoàn thành", "đua", "cờ"], keywordsEN: ["finish", "race", "chequered", "flag"]),
    ]
}

/// Persists recently used emojis in `UserDefaults` with cap = 24 and deduplication.
/// Uses `UserDefaults` injection so reopen persistence is tested cleanly in `XFinderLogicTests`
/// without polluting the app's standard defaults.
struct NotchEmojiRecentsStore {
    private let defaults: UserDefaults
    let key: String
    let limit: Int

    init(
        defaults: UserDefaults = .standard,
        key: String = NotchEmojiCatalog.recentsDefaultsKey,
        limit: Int = NotchEmojiCatalog.recentsLimit
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    func load() -> [String] {
        let raw = defaults.stringArray(forKey: key) ?? []
        return NotchEmojiCatalog.sanitizeRecents(raw, limit: limit)
    }

    func save(_ recents: [String]) {
        let clean = NotchEmojiCatalog.sanitizeRecents(recents, limit: limit)
        defaults.set(clean, forKey: key)
    }

    @discardableResult
    func record(_ glyph: String) -> [String] {
        let updated = NotchEmojiCatalog.recordRecent(glyph, into: load(), limit: limit)
        defaults.set(updated, forKey: key)
        return updated
    }
}

/// Pure, UI-independent session controller for browsing, searching, copying, and reloading recents.
/// Tested directly in `XFinderLogicTests`; `NotchEmojiModel` delegates its state transitions to this logic.
struct NotchEmojiPickerSession {
    var query: String = ""
    var selectedCategory: NotchEmojiCategory = .smileys
    private(set) var recents: [String]
    private(set) var lastCopiedGlyph: String?
    private let store: NotchEmojiRecentsStore
    private let copyHandler: (String) -> Bool

    init(
        store: NotchEmojiRecentsStore = NotchEmojiRecentsStore(),
        copyHandler: @escaping (String) -> Bool
    ) {
        self.store = store
        self.copyHandler = copyHandler
        self.recents = store.load()
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayedItems: [NotchEmojiItem] {
        if isSearching {
            return NotchEmojiCatalog.search(query)
        }
        return NotchEmojiCatalog.items(in: selectedCategory, recents: recents)
    }

    mutating func reloadRecents() {
        recents = store.load()
    }

    mutating func selectCategory(_ category: NotchEmojiCategory) {
        selectedCategory = category
        if isSearching {
            query = ""
        }
    }

    /// Copies the emoji via `copyHandler` and records it in persisted recents when copy succeeds.
    @discardableResult
    mutating func copy(_ item: NotchEmojiItem) -> Bool {
        copy(glyph: item.glyph)
    }

    @discardableResult
    mutating func copy(glyph: String) -> Bool {
        guard !glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard copyHandler(glyph) else { return false }
        recents = store.record(glyph)
        lastCopiedGlyph = glyph
        return true
    }
}
