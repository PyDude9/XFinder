import Foundation

/// A local vocabulary snapshot. JSON is the full backup format; TSV contains notes only.
struct VocabularyLibrary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let defaultWordbookID = UUID(uuid: (0x58, 0x46, 0x57, 0x42, 0x00, 0x00, 0x40, 0x00,
                                             0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))
    static let defaultWordbookNameKey = "Từ đã lưu"
    static let maximumImportBytes = 20 * 1024 * 1024
    static let maximumCards = 50_000
    static let maximumWordbooks = 1_000

    var schemaVersion: Int = VocabularyLibrary.currentSchemaVersion
    var wordbooks: [VocabularyWordbook] = [.init(id: VocabularyLibrary.defaultWordbookID, name: VocabularyLibrary.defaultWordbookNameKey)]
    var cards: [VocabularyCard] = []
    var blueprints: [String: String] = [:]

    enum ValidationError: Error, Equatable {
        case oversizedPayload
        case invalidPayload
        case unsupportedVersion(Int)
        case invalidWordbook
        case invalidCard
        case invalidReviewState
        case invalidBlueprint
        case duplicateIdentity
        case unknownWordbook
        case capacityExceeded
    }

    struct MergeReport: Equatable, Sendable {
        var addedWordbooks = 0
        var addedCards = 0
        var duplicateCards = 0
        var addedBlueprints = 0
    }

    mutating func addWordbook(name: String) throws -> VocabularyWordbook {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validText(trimmed, maximum: 200, allowsEmpty: false) else { throw ValidationError.invalidWordbook }
        if let existing = wordbooks.first(where: { Self.normalizedIdentity($0.name) == Self.normalizedIdentity(trimmed) }) {
            return existing
        }
        guard wordbooks.count < Self.maximumWordbooks else { throw ValidationError.capacityExceeded }
        let book = VocabularyWordbook(name: trimmed)
        wordbooks.append(book)
        return book
    }

    /// Analysis updates preserve the card's scheduling history and creation identity.
    @discardableResult
    mutating func upsert(_ card: VocabularyCard, now: Date = Date()) throws -> VocabularyCard {
        var candidate = card
        candidate.term = candidate.term.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.language = Self.normalizedLanguage(candidate.language)
        candidate.targetLanguage = Self.normalizedLanguage(candidate.targetLanguage)
        guard wordbooks.contains(where: { $0.id == candidate.wordbookID }) else { throw ValidationError.unknownWordbook }
        let key = Self.cardIdentity(candidate)
        let matchingKey = cards.firstIndex { Self.cardIdentity($0) == key }
        let matchingID = cards.firstIndex { $0.id == candidate.id }
        if let matchingKey, let matchingID, matchingKey != matchingID { throw ValidationError.duplicateIdentity }
        if let index = matchingKey ?? matchingID {
            let existing = cards[index]
            candidate.id = existing.id
            candidate.createdAt = existing.createdAt
            candidate.review = existing.review
            candidate.updatedAt = max(now, max(existing.updatedAt, existing.createdAt))
            try Self.validateCard(candidate)
            cards[index] = candidate
        } else {
            guard cards.count < Self.maximumCards else { throw ValidationError.capacityExceeded }
            candidate.updatedAt = max(now, max(candidate.createdAt, candidate.updatedAt))
            try Self.validateCard(candidate)
            cards.append(candidate)
        }
        return candidate
    }

    @discardableResult
    mutating func removeCard(_ id: UUID) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return false }
        cards.remove(at: index)
        return true
    }

    /// Import is staged and non-destructive: existing cards, schedules and prompt edits win collisions.
    @discardableResult
    mutating func merge(_ incoming: VocabularyLibrary) throws -> MergeReport {
        try validate()
        try incoming.validate()
        var merged = self
        var report = MergeReport()
        var bookIDs: [UUID: UUID] = [:]
        for book in incoming.wordbooks {
            if let existing = merged.wordbooks.first(where: { $0.id == book.id }) {
                bookIDs[book.id] = existing.id
            } else if let existing = merged.wordbooks.first(where: { Self.normalizedIdentity($0.name) == Self.normalizedIdentity(book.name) }) {
                bookIDs[book.id] = existing.id
            } else {
                merged.wordbooks.append(book)
                bookIDs[book.id] = book.id
                report.addedWordbooks += 1
            }
        }
        var knownIDs = Set(merged.cards.map(\.id))
        var knownKeys = Set(merged.cards.map(Self.cardIdentity))
        for source in incoming.cards {
            var card = source
            guard let mappedBook = bookIDs[card.wordbookID] else { throw ValidationError.unknownWordbook }
            card.wordbookID = mappedBook
            if knownIDs.contains(card.id) || knownKeys.contains(Self.cardIdentity(card)) {
                report.duplicateCards += 1
                continue
            }
            merged.cards.append(card)
            knownIDs.insert(card.id)
            knownKeys.insert(Self.cardIdentity(card))
            report.addedCards += 1
        }
        for (key, value) in incoming.blueprints where merged.blueprints[key] == nil {
            merged.blueprints[key] = value
            report.addedBlueprints += 1
        }
        try merged.validate()
        self = merged
        return report
    }

    func dueCards(at now: Date) -> [VocabularyCard] {
        cards.filter { $0.review.nextReviewAt <= now }.sorted {
            if $0.review.nextReviewAt != $1.review.nextReviewAt { return $0.review.nextReviewAt < $1.review.nextReviewAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw ValidationError.unsupportedVersion(schemaVersion) }
        guard !wordbooks.isEmpty else { throw ValidationError.invalidWordbook }
        guard wordbooks.count <= Self.maximumWordbooks, cards.count <= Self.maximumCards,
              blueprints.count <= 50 else { throw ValidationError.capacityExceeded }
        var bookIDs: Set<UUID> = []
        for book in wordbooks {
            guard Self.validText(book.name.trimmingCharacters(in: .whitespacesAndNewlines), maximum: 200, allowsEmpty: false)
            else { throw ValidationError.invalidWordbook }
            guard bookIDs.insert(book.id).inserted else { throw ValidationError.duplicateIdentity }
        }
        var cardIDs: Set<UUID> = [], cardKeys: Set<String> = []
        for card in cards {
            guard bookIDs.contains(card.wordbookID) else { throw ValidationError.unknownWordbook }
            try Self.validateCard(card)
            guard cardIDs.insert(card.id).inserted, cardKeys.insert(Self.cardIdentity(card)).inserted
            else { throw ValidationError.duplicateIdentity }
        }
        for (key, value) in blueprints {
            guard Self.validText(key, maximum: 100, allowsEmpty: false),
                  Self.validText(value, maximum: 50_000, allowsEmpty: true) else { throw ValidationError.invalidBlueprint }
        }
    }

    static func decode(_ data: Data) throws -> VocabularyLibrary {
        guard data.count <= maximumImportBytes else { throw ValidationError.oversizedPayload }
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let version: Int
        do { version = try decoder.decode(Header.self, from: data).schemaVersion }
        catch { throw ValidationError.invalidPayload }
        guard version == currentSchemaVersion else { throw ValidationError.unsupportedVersion(version) }
        let library: VocabularyLibrary
        do { library = try decoder.decode(VocabularyLibrary.self, from: data) }
        catch { throw ValidationError.invalidPayload }
        try library.validate()
        return library
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumImportBytes else { throw ValidationError.oversizedPayload }
        return data
    }

    /// Three UTF-8 note fields. Scheduling, deck mapping and linguistic metadata remain in the full JSON backup.
    func ankiTSV() -> String {
        let rows = cards.map { card in
            let back = card.meaning.isEmpty
                ? card.definitions.map { [$0.meaningVi, $0.meaningEn].filter { !$0.isEmpty }.joined(separator: "\n") }.joined(separator: "\n\n")
                : card.meaning
            return [card.term, back, card.context].map(Self.quotedTSVField).joined(separator: "\t")
        }
        return "#separator:tab\n#html:false\n" + rows.joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
    }

    static func normalizedLanguage(_ language: String) -> String {
        language.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-").lowercased()
    }

    /// Syntax validation preserves unknown language tags without claiming the language is supported.
    static func isValidLanguageTag(_ value: String) -> Bool {
        let normalized = normalizedLanguage(value)
        guard normalized.count <= 64 else { return false }
        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        func letters(_ part: String) -> Bool { !part.isEmpty && part.utf8.allSatisfy { (97...122).contains($0) } }
        func digits(_ part: String) -> Bool { !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } }
        func alphanumeric(_ part: String) -> Bool { !part.isEmpty && part.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) } }
        let grandfathered: Set<String> = ["en-gb-oed", "i-ami", "i-bnn", "i-default", "i-enochian", "i-hak", "i-klingon",
            "i-lux", "i-mingo", "i-navajo", "i-pwn", "i-tao", "i-tay", "i-tsu", "sgn-be-fr", "sgn-be-nl", "sgn-ch-de",
            "art-lojban", "cel-gaulish", "no-bok", "no-nyn", "zh-guoyu", "zh-hakka", "zh-min", "zh-min-nan", "zh-xiang"]
        if grandfathered.contains(normalized) { return true }
        guard let first = parts.first else { return false }
        if first == "x" { return parts.count > 1 && parts.dropFirst().allSatisfy { (1...8).contains($0.count) && alphanumeric($0) } }
        guard (2...8).contains(first.count), letters(first) else { return false }
        var index = 1
        if first.count <= 3 {
            var extensions = 0
            while index < parts.count, parts[index].count == 3, letters(parts[index]), extensions < 3 {
                index += 1; extensions += 1
            }
        }
        if index < parts.count, parts[index].count == 4, letters(parts[index]) { index += 1 }
        if index < parts.count, (parts[index].count == 2 && letters(parts[index])) || (parts[index].count == 3 && digits(parts[index])) { index += 1 }
        var variants: Set<String> = []
        while index < parts.count {
            let part = parts[index]
            let variant = (5...8).contains(part.count) && alphanumeric(part)
                || (part.count == 4 && part.utf8.first.map { (48...57).contains($0) } == true && alphanumeric(part))
            guard variant else { break }
            guard variants.insert(part).inserted else { return false }
            index += 1
        }
        var extensions: Set<String> = []
        while index < parts.count, parts[index].count == 1, parts[index] != "x", alphanumeric(parts[index]) {
            guard extensions.insert(parts[index]).inserted else { return false }
            index += 1
            let start = index
            while index < parts.count, (2...8).contains(parts[index].count), alphanumeric(parts[index]) { index += 1 }
            guard index > start else { return false }
        }
        if index < parts.count, parts[index] == "x" {
            index += 1
            guard index < parts.count else { return false }
            return parts[index...].allSatisfy { (1...8).contains($0.count) && alphanumeric($0) }
        }
        return index == parts.count
    }

    /// NFC and case folding retain accents: Vietnamese `ma` and `má` are different terms.
    static func normalizedIdentity(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func cardIdentity(_ card: VocabularyCard) -> String {
        card.wordbookID.uuidString + "\0" + normalizedLanguage(card.language) + "\0" + normalizedIdentity(card.term)
    }

    private static func quotedTSVField(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func validText(_ text: String, maximum: Int, allowsEmpty: Bool) -> Bool {
        text.count <= maximum && !text.contains("\0") && (allowsEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func validateCard(_ card: VocabularyCard) throws {
        guard validText(card.term, maximum: 5_000, allowsEmpty: false),
              isValidLanguageTag(card.language),
              isValidLanguageTag(card.targetLanguage),
              validText(card.meaning, maximum: 50_000, allowsEmpty: true),
              validText(card.context, maximum: 50_000, allowsEmpty: true),
              card.definitions.count <= 100, card.synonyms.count <= 200,
              [card.syllables, card.phoneticUS, card.phoneticUK, card.etymology, card.cefr].compactMap({ $0 })
                .allSatisfy({ validText($0, maximum: 10_000, allowsEmpty: true) }),
              card.synonyms.allSatisfy({ validText($0, maximum: 1_000, allowsEmpty: false) }),
              card.definitions.allSatisfy({ definition in
                  [definition.pos, definition.meaningVi, definition.meaningEn, definition.exampleEn, definition.exampleVi]
                    .allSatisfy { validText($0, maximum: 10_000, allowsEmpty: true) }
              }),
              VocabularyReviewRules.validDate(card.createdAt), VocabularyReviewRules.validDate(card.updatedAt),
              card.updatedAt >= card.createdAt,
              card.provenance.map({ validText($0, maximum: 200, allowsEmpty: false)
                  && !$0.contains("://") && !$0.contains("\n") && !$0.contains("\r") && !$0.contains("\t") }) ?? true
        else { throw ValidationError.invalidCard }
        guard VocabularyReviewRules.isValid(card.review), card.review.nextReviewAt >= card.createdAt,
              card.review.lastReviewedAt.map({ $0 >= card.createdAt }) ?? true
        else { throw ValidationError.invalidReviewState }
    }
}

struct VocabularyWordbook: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
}

struct VocabularyDefinition: Codable, Equatable, Sendable {
    var pos: String = ""
    var meaningVi: String = ""
    var meaningEn: String = ""
    var exampleEn: String = ""
    var exampleVi: String = ""
}

struct VocabularyCard: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var term: String
    var language: String
    var targetLanguage: String
    var meaning: String
    var context: String
    var syllables: String?
    var phoneticUS: String?
    var phoneticUK: String?
    var definitions: [VocabularyDefinition]
    var synonyms: [String]
    var etymology: String?
    var cefr: String?
    var provenance: String?
    var wordbookID: UUID
    var createdAt: Date
    var updatedAt: Date
    var review: VocabularyReviewState

    init(id: UUID = UUID(), term: String, language: String = "en", targetLanguage: String = "vi",
         meaning: String = "", context: String = "", syllables: String? = nil,
         phoneticUS: String? = nil, phoneticUK: String? = nil, definitions: [VocabularyDefinition] = [],
         synonyms: [String] = [], etymology: String? = nil, cefr: String? = nil, provenance: String? = nil,
         wordbookID: UUID = VocabularyLibrary.defaultWordbookID,
         createdAt: Date = Date(), updatedAt: Date? = nil, review: VocabularyReviewState? = nil) {
        self.id = id; self.term = term; self.language = language; self.targetLanguage = targetLanguage
        self.meaning = meaning; self.context = context; self.syllables = syllables
        self.phoneticUS = phoneticUS; self.phoneticUK = phoneticUK
        self.definitions = definitions; self.synonyms = synonyms; self.etymology = etymology; self.cefr = cefr
        self.provenance = provenance
        self.wordbookID = wordbookID; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.review = review ?? VocabularyReviewState(nextReviewAt: createdAt)
    }
}

struct VocabularyReviewState: Codable, Equatable, Sendable {
    var repetition: Int = 0
    var intervalDays: Int = 0
    var easeFactor: Double = 2.5
    var nextReviewAt: Date = Date()
    var lastReviewedAt: Date? = nil
}

enum VocabularyRating: Int, Codable, CaseIterable, Identifiable, Sendable {
    case again = 0, hard = 3, good = 4, easy = 5
    var id: Int { rawValue }
}

/// SM-2 intervals and ease update, with an explicit ten-minute learning retry for Again.
/// Safety bounds prevent imported or repeatedly growing numbers from overflowing native date/Int operations.
enum VocabularyReviewRules {
    static let maximumIntervalDays = 36_500
    static let maximumEaseFactor = 1_000.0
    static let maximumRepetitions = 100_000
    static let earliestDate = Date(timeIntervalSince1970: 0)
    static let latestDate = Date(timeIntervalSince1970: 32_503_680_000)

    static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && date >= earliestDate && date <= latestDate
    }

    static func isValid(_ state: VocabularyReviewState) -> Bool {
        (0...maximumRepetitions).contains(state.repetition) && (0...maximumIntervalDays).contains(state.intervalDays)
            && state.easeFactor.isFinite && (1.3...maximumEaseFactor).contains(state.easeFactor)
            && ((state.repetition == 0 && state.intervalDays == 0) || (state.repetition > 0 && state.intervalDays > 0))
            && validDate(state.nextReviewAt) && (state.lastReviewedAt.map(validDate) ?? true)
            && (state.lastReviewedAt.map({ $0 <= state.nextReviewAt }) ?? true)
    }

    static func reviewed(_ state: VocabularyReviewState, rating: VocabularyRating, now: Date,
                         calendar: Calendar = .current) -> VocabularyReviewState {
        let safeNow = validDate(now) ? now : earliestDate
        let oldEase = state.easeFactor.isFinite ? min(maximumEaseFactor, max(1.3, state.easeFactor)) : 2.5
        let quality = Double(rating.rawValue)
        let updatedEase = min(maximumEaseFactor, max(1.3, oldEase + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))
        if rating == .again {
            return VocabularyReviewState(repetition: 0, intervalDays: 0, easeFactor: updatedEase,
                                         nextReviewAt: min(latestDate, safeNow.addingTimeInterval(600)), lastReviewedAt: safeNow)
        }
        let repetitions = min(maximumRepetitions, max(0, state.repetition))
        let interval: Int
        if repetitions == 0 { interval = 1 }
        else if repetitions == 1 { interval = 6 }
        else {
            let previous = min(maximumIntervalDays, max(0, state.intervalDays))
            interval = max(1, Int(min(Double(maximumIntervalDays), ceil(Double(previous) * oldEase))))
        }
        let due = calendar.date(byAdding: .day, value: interval, to: safeNow) ?? latestDate
        return VocabularyReviewState(repetition: min(maximumRepetitions, repetitions + 1), intervalDays: interval,
                                     easeFactor: updatedEase, nextReviewAt: min(latestDate, due), lastReviewedAt: safeNow)
    }
}

// Optional linguistic fields may be absent in older version-one backups. Scheduling/dates remain required.
extension VocabularyCard {
    private enum CodingKeys: String, CodingKey {
        case id, term, language, targetLanguage, meaning, context, syllables, phoneticUS, phoneticUK
        case definitions, synonyms, etymology, cefr, provenance, wordbookID, createdAt, updatedAt, review
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        term = try values.decode(String.self, forKey: .term)
        language = try values.decode(String.self, forKey: .language)
        targetLanguage = try values.decode(String.self, forKey: .targetLanguage)
        meaning = try values.decode(String.self, forKey: .meaning)
        context = try values.decodeIfPresent(String.self, forKey: .context) ?? ""
        syllables = try values.decodeIfPresent(String.self, forKey: .syllables)
        phoneticUS = try values.decodeIfPresent(String.self, forKey: .phoneticUS)
        phoneticUK = try values.decodeIfPresent(String.self, forKey: .phoneticUK)
        definitions = try values.decodeIfPresent([VocabularyDefinition].self, forKey: .definitions) ?? []
        synonyms = try values.decodeIfPresent([String].self, forKey: .synonyms) ?? []
        etymology = try values.decodeIfPresent(String.self, forKey: .etymology)
        cefr = try values.decodeIfPresent(String.self, forKey: .cefr)
        provenance = try values.decodeIfPresent(String.self, forKey: .provenance)
        wordbookID = try values.decode(UUID.self, forKey: .wordbookID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        review = try values.decode(VocabularyReviewState.self, forKey: .review)
    }
}

extension VocabularyLibrary {
    private enum CodingKeys: String, CodingKey { case schemaVersion, wordbooks, cards, blueprints }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        wordbooks = try values.decode([VocabularyWordbook].self, forKey: .wordbooks)
        cards = try values.decode([VocabularyCard].self, forKey: .cards)
        blueprints = try values.decodeIfPresent([String: String].self, forKey: .blueprints) ?? [:]
    }
}
