import XCTest

final class VocabularyLibraryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000.125)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func card(_ term: String, language: String = "en", book: UUID = VocabularyLibrary.defaultWordbookID) -> VocabularyCard {
        VocabularyCard(term: term, language: language, wordbookID: book, createdAt: now)
    }

    private func alteredPayload(_ library: VocabularyLibrary, change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: library.encoded()) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testDefaultLibraryHasStableSavedBookAndNoInventedLinguisticFields() throws {
        let library = VocabularyLibrary()
        XCTAssertEqual(library.wordbooks, [VocabularyWordbook(id: VocabularyLibrary.defaultWordbookID, name: "Từ đã lưu")])
        XCTAssertEqual(library, VocabularyLibrary())
        XCTAssertTrue(library.cards.isEmpty)
        let word = card("unknown")
        XCTAssertNil(word.syllables)
        XCTAssertNil(word.phoneticUS)
        XCTAssertNil(word.phoneticUK)
        XCTAssertNil(word.cefr)
        XCTAssertNil(word.etymology)
        XCTAssertNil(word.provenance)
        XCTAssertTrue(word.definitions.isEmpty)
        XCTAssertTrue(word.synonyms.isEmpty)
        XCTAssertEqual(word.review.easeFactor, 2.5)
        XCTAssertEqual(word.review.nextReviewAt, word.createdAt)
        try library.validate()
    }

    func testCompleteJSONRoundTripPreservesUnicodeLinguisticsReviewAndBlueprints() throws {
        var library = VocabularyLibrary()
        var word = card("điện thoại / 日本語 / 한국어")
        word.meaning = "Nghĩa đã được người dùng xác nhận"
        word.context = "A\tcontext with \"quotes\"\nand another line"
        word.syllables = "điện · thoại"
        word.phoneticUS = "/test/"
        word.phoneticUK = "/tɛst/"
        word.definitions = [.init(pos: "noun", meaningVi: "nghĩa", meaningEn: "meaning", exampleEn: "An example.", exampleVi: "Ví dụ.")]
        word.synonyms = ["tương đương", "類義語"]
        word.etymology = "User-supplied history"
        word.cefr = "B2"
        word.provenance = "AI openai user-model"
        word.review = VocabularyReviewState(repetition: 2, intervalDays: 6, easeFactor: 2.36,
                                             nextReviewAt: now.addingTimeInterval(6 * 86_400), lastReviewedAt: now)
        library.cards = [word]
        library.blueprints = ["definition": "Describe {{term}} without invented IPA.", "grammar": "日本語\nTiếng Việt"]
        let encoded = try library.encoded()
        XCTAssertEqual(try VocabularyLibrary.decode(encoded), library)
        XCTAssertEqual(try VocabularyLibrary.decode(encoded).cards.first?.createdAt, now)
    }

    func testMissingOptionalLinguisticsAndBlueprintsRemainAbsent() throws {
        var library = VocabularyLibrary()
        library.cards = [card("hello")]
        let data = try alteredPayload(library) { object in
            object.removeValue(forKey: "blueprints")
            var words = object["cards"] as? [[String: Any]] ?? []
            for key in ["syllables", "phoneticUS", "phoneticUK", "definitions", "synonyms", "etymology", "cefr", "provenance"] {
                words[0].removeValue(forKey: key)
            }
            object["cards"] = words
        }
        let decoded = try VocabularyLibrary.decode(data)
        XCTAssertEqual(decoded.cards, library.cards)
        XCTAssertTrue(decoded.blueprints.isEmpty)
    }

    func testUpsertDeduplicatesNormalizedIdentityAndPreservesReviewOnAnalysisUpdates() throws {
        var library = VocabularyLibrary()
        var existing = card("điện thoại", language: "VI")
        existing.review = VocabularyReviewState(repetition: 3, intervalDays: 15, easeFactor: 2.5,
                                                nextReviewAt: now.addingTimeInterval(86_400), lastReviewedAt: now)
        let saved = try library.upsert(existing, now: now)
        var analysis = card("  ĐIỆN  THOẠI  ".decomposedStringWithCanonicalMapping, language: "vi")
        analysis.meaning = "Refined analysis"
        let updated = try library.upsert(analysis, now: now.addingTimeInterval(30))
        XCTAssertEqual(library.cards.count, 1)
        XCTAssertEqual(updated.id, saved.id)
        XCTAssertEqual(updated.createdAt, saved.createdAt)
        XCTAssertEqual(updated.review, saved.review)
        XCTAssertEqual(updated.meaning, "Refined analysis")
        XCTAssertEqual(updated.updatedAt, now.addingTimeInterval(30))
    }

    func testDedupKeepsAccentsLanguagesAndBooksDistinct() throws {
        var library = VocabularyLibrary()
        let second = try library.addWordbook(name: "研究")
        _ = try library.upsert(card("ma"), now: now)
        _ = try library.upsert(card("má"), now: now)
        _ = try library.upsert(card("ma", language: "vi"), now: now)
        _ = try library.upsert(card("ma", book: second.id), now: now)
        _ = try library.upsert(card("日本語", language: "ja"), now: now)
        _ = try library.upsert(card("日本語", language: "JA"), now: now)
        XCTAssertEqual(library.cards.count, 5)
        XCTAssertEqual(try library.addWordbook(name: "  研究  ").id, second.id)
        var cafe = card("Café")
        cafe = try library.upsert(cafe, now: now)
        let composed = try library.upsert(card("CAFÉ".decomposedStringWithCanonicalMapping), now: now)
        XCTAssertEqual(cafe.id, composed.id)
    }

    func testEditByIDPreservesHistoryAndRejectsCollidingIdentitiesWithoutMutation() throws {
        var library = VocabularyLibrary()
        let first = try library.upsert(card("one"), now: now)
        let second = try library.upsert(card("two"), now: now)
        var edited = first
        edited.term = "renamed"
        let updated = try library.upsert(edited, now: now.addingTimeInterval(5))
        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.review, first.review)
        let before = library
        edited.term = second.term
        XCTAssertThrowsError(try library.upsert(edited, now: now)) { error in
            XCTAssertEqual(error as? VocabularyLibrary.ValidationError, .duplicateIdentity)
        }
        XCTAssertEqual(library, before)
    }

    func testMergeMapsSameNameBooksAndNeverOverwritesExistingCardsReviewOrPrompts() throws {
        var current = VocabularyLibrary()
        let book = try current.addWordbook(name: "日本語")
        var existing = card("猫", language: "ja", book: book.id)
        existing.meaning = "Existing meaning"
        existing.review = VocabularyReviewState(repetition: 1, intervalDays: 1, easeFactor: 2.5,
                                                nextReviewAt: now.addingTimeInterval(86_400), lastReviewedAt: now)
        _ = try current.upsert(existing, now: now)
        current.blueprints = ["definition": "My existing prompt"]
        var incoming = VocabularyLibrary()
        let importedBook = try incoming.addWordbook(name: " 日本語 ")
        var duplicate = card("猫", language: "JA", book: importedBook.id)
        duplicate.meaning = "Must not overwrite"
        incoming.cards = [duplicate, card("犬", language: "ja", book: importedBook.id)]
        incoming.blueprints = ["definition": "Imported replacement", "grammar": "New module"]
        let report = try current.merge(incoming)
        XCTAssertEqual(report.addedWordbooks, 0)
        XCTAssertEqual(report.addedCards, 1)
        XCTAssertEqual(report.duplicateCards, 1)
        XCTAssertEqual(report.addedBlueprints, 1)
        XCTAssertEqual(current.cards.first, existing)
        XCTAssertEqual(current.cards.last?.wordbookID, book.id)
        XCTAssertEqual(current.blueprints["definition"], "My existing prompt")
        XCTAssertEqual(current.blueprints["grammar"], "New module")
        let before = current
        let repeated = try current.merge(incoming)
        XCTAssertEqual(repeated.addedCards, 0)
        XCTAssertEqual(repeated.duplicateCards, 2)
        XCTAssertEqual(current, before)
    }

    func testInvalidImportMergeIsTransactionalAndUnknownBooksAreRejected() throws {
        var library = VocabularyLibrary()
        _ = try library.upsert(card("keep"), now: now)
        let before = library
        var incoming = VocabularyLibrary()
        incoming.cards = [card("new")]
        incoming.blueprints = ["bad": "Invalid\0prompt"]
        XCTAssertThrowsError(try library.merge(incoming))
        XCTAssertEqual(library, before)
        var orphan = card("orphan")
        orphan.wordbookID = UUID()
        XCTAssertThrowsError(try library.upsert(orphan, now: now)) { error in
            XCTAssertEqual(error as? VocabularyLibrary.ValidationError, .unknownWordbook)
        }
        XCTAssertEqual(library, before)
    }

    func testStrictDecodeRejectsMalformedOversizedAndFuturePayloads() throws {
        for malformed in [Data(), Data("not JSON".utf8), Data("[]".utf8), Data("{\"schemaVersion\":true}".utf8)] {
            XCTAssertThrowsError(try VocabularyLibrary.decode(malformed))
        }
        let oversized = Data(repeating: 32, count: VocabularyLibrary.maximumImportBytes + 1)
        XCTAssertThrowsError(try VocabularyLibrary.decode(oversized)) { error in
            XCTAssertEqual(error as? VocabularyLibrary.ValidationError, .oversizedPayload)
        }
        let future = Data("{\"schemaVersion\":2}".utf8)
        XCTAssertThrowsError(try VocabularyLibrary.decode(future)) { error in
            XCTAssertEqual(error as? VocabularyLibrary.ValidationError, .unsupportedVersion(2))
        }
        var library = VocabularyLibrary()
        library.cards = [card("good")]
        let bad = try alteredPayload(library) { object in
            var cards = object["cards"] as? [[String: Any]] ?? []
            cards[0]["wordbookID"] = UUID().uuidString
            object["cards"] = cards
        }
        XCTAssertThrowsError(try VocabularyLibrary.decode(bad)) { error in
            XCTAssertEqual(error as? VocabularyLibrary.ValidationError, .unknownWordbook)
        }
    }

    func testValidationRejectsInvalidReviewNumbersDatesAndDuplicatePayloadCards() throws {
        let invalidStates = [
            VocabularyReviewState(repetition: -1, nextReviewAt: now),
            VocabularyReviewState(intervalDays: -1, nextReviewAt: now),
            VocabularyReviewState(easeFactor: .nan, nextReviewAt: now),
            VocabularyReviewState(easeFactor: 1.2, nextReviewAt: now),
            VocabularyReviewState(easeFactor: .infinity, nextReviewAt: now),
            VocabularyReviewState(repetition: 1, intervalDays: 0, nextReviewAt: now),
            VocabularyReviewState(nextReviewAt: .distantFuture),
            VocabularyReviewState(nextReviewAt: now, lastReviewedAt: now.addingTimeInterval(1)),
        ]
        for review in invalidStates {
            var library = VocabularyLibrary()
            var word = card("invalid")
            word.review = review
            library.cards = [word]
            XCTAssertThrowsError(try library.validate())
        }
        var library = VocabularyLibrary()
        library.cards = [card("duplicate"), card("DUPLICATE")]
        XCTAssertThrowsError(try library.encoded()) { error in
            XCTAssertEqual(error as? VocabularyLibrary.ValidationError, .duplicateIdentity)
        }
        library.cards = [card(String(repeating: "字", count: 5_001))]
        XCTAssertThrowsError(try library.validate())
        library.cards = [card("term")]
        library.cards[0].updatedAt = now.addingTimeInterval(-1)
        XCTAssertThrowsError(try library.validate())
    }

    func testLanguageTagsPreserveUndAndUnknownValidSyntaxWithoutClaimingSupport() throws {
        for tag in ["en", "vi", "zh-Hant-TW", "ja", "ko", "und", "zz-ZZ", "x-user", "en-US-u-ca-gregory", "i-klingon"] {
            XCTAssertTrue(VocabularyLibrary.isValidLanguageTag(tag), tag)
        }
        for tag in ["", "e", "hello world", "vi--VN", "en-a", "en-x", "en-u-ca-u-nu", "https://example.test", "日本語"] {
            XCTAssertFalse(VocabularyLibrary.isValidLanguageTag(tag), tag)
        }
        var library = VocabularyLibrary()
        let unknown = try library.upsert(card("unidentified", language: "und"), now: now)
        XCTAssertEqual(unknown.language, "und")
        let privateLanguage = try library.upsert(card("unknown", language: "x-user"), now: now)
        XCTAssertEqual(privateLanguage.language, "x-user")
    }

    func testProvenanceIsOptionalPlainLabelAndCannotContainRequestURLs() throws {
        var library = VocabularyLibrary()
        var word = card("test")
        word.provenance = "AI ollama local-model"
        _ = try library.upsert(word, now: now)
        for bad in ["https://example.test?key=secret", "provider\nvalue", "provider\tvalue", ""] {
            word.provenance = bad
            XCTAssertThrowsError(try library.upsert(word, now: now))
        }
        XCTAssertEqual(library.cards.first?.provenance, "AI ollama local-model")
    }

    func testTSVPreservesThreeFieldsUnicodeQuotesTabsAndMultilineText() throws {
        var library = VocabularyLibrary()
        var word = card("#語\t\"term\"")
        word.meaning = "nghĩa\nsecond \"line\""
        word.context = "<b>plain text</b>\t日本語\r\n끝"
        library.cards = [word]
        let expected = "#separator:tab\n#html:false\n\"#語\t\"\"term\"\"\"\t\"nghĩa\nsecond \"\"line\"\"\"\t\"<b>plain text</b>\t日本語\r\n끝\"\n"
        let exported = library.ankiTSV()
        XCTAssertEqual(exported, expected)
        XCTAssertEqual(String(data: Data(exported.utf8), encoding: .utf8), expected)
        XCTAssertFalse(exported.contains("easeFactor"))
        XCTAssertFalse(exported.contains("nextReviewAt"))
        XCTAssertEqual(VocabularyLibrary().ankiTSV(), "#separator:tab\n#html:false\n")
    }

    func testTSVUsesUserDefinitionsWhenSummaryMeaningIsAbsent() {
        var library = VocabularyLibrary()
        var word = card("cat")
        word.definitions = [.init(meaningVi: "mèo", meaningEn: "a small animal")]
        library.cards = [word]
        XCTAssertEqual(library.ankiTSV(), "#separator:tab\n#html:false\n\"cat\"\t\"mèo\na small animal\"\t\"\"\n")
    }

    func testSM2GoodIntervalsAndEaseFollowExactFirstSecondAndLaterSteps() {
        var state = VocabularyReviewState(nextReviewAt: now)
        state = VocabularyReviewRules.reviewed(state, rating: .good, now: now, calendar: utc)
        XCTAssertEqual(state.repetition, 1)
        XCTAssertEqual(state.intervalDays, 1)
        XCTAssertEqual(state.easeFactor, 2.5, accuracy: 0.000_000_1)
        XCTAssertEqual(state.nextReviewAt, now.addingTimeInterval(86_400))
        state = VocabularyReviewRules.reviewed(state, rating: .good, now: state.nextReviewAt, calendar: utc)
        XCTAssertEqual(state.repetition, 2)
        XCTAssertEqual(state.intervalDays, 6)
        state = VocabularyReviewRules.reviewed(state, rating: .good, now: state.nextReviewAt, calendar: utc)
        XCTAssertEqual(state.repetition, 3)
        XCTAssertEqual(state.intervalDays, 15)
    }

    func testSM2UsesOldEaseForIntervalAndCeilsFractionalDays() {
        let old = VocabularyReviewState(repetition: 2, intervalDays: 6, easeFactor: 2.5, nextReviewAt: now)
        let easy = VocabularyReviewRules.reviewed(old, rating: .easy, now: now, calendar: utc)
        XCTAssertEqual(easy.intervalDays, 15, "new EF2.6 would incorrectly schedule16days")
        XCTAssertEqual(easy.easeFactor, 2.6, accuracy: 0.000_000_1)
        let fraction = VocabularyReviewState(repetition: 3, intervalDays: 7, easeFactor: 2.36, nextReviewAt: now)
        XCTAssertEqual(VocabularyReviewRules.reviewed(fraction, rating: .good, now: now, calendar: utc).intervalDays, 17)
        let hard = VocabularyReviewRules.reviewed(old, rating: .hard, now: now, calendar: utc)
        XCTAssertEqual(hard.intervalDays, 15)
        XCTAssertEqual(hard.easeFactor, 2.36, accuracy: 0.000_000_1)
    }

    func testAgainIsExplicitTenMinuteRetryResetsRepetitionsAndRetainsAdjustedEase() {
        let old = VocabularyReviewState(repetition: 10, intervalDays: 80, easeFactor: 2.5, nextReviewAt: now)
        let again = VocabularyReviewRules.reviewed(old, rating: .again, now: now, calendar: utc)
        XCTAssertEqual(again.repetition, 0)
        XCTAssertEqual(again.intervalDays, 0)
        XCTAssertEqual(again.easeFactor, 1.7, accuracy: 0.000_000_1)
        XCTAssertEqual(again.nextReviewAt, now.addingTimeInterval(600))
        XCTAssertEqual(again.lastReviewedAt, now)
        let restarted = VocabularyReviewRules.reviewed(again, rating: .good, now: again.nextReviewAt, calendar: utc)
        XCTAssertEqual(restarted.repetition, 1)
        XCTAssertEqual(restarted.intervalDays, 1)
        var floor = again
        for _ in 0..<20 { floor = VocabularyReviewRules.reviewed(floor, rating: .again, now: now, calendar: utc) }
        XCTAssertEqual(floor.easeFactor, 1.3, accuracy: 0.000_000_1)
    }

    func testSchedulingAddsCalendarDaysAcrossDSTRatherThanFixedSeconds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        let reviewed = VocabularyReviewRules.reviewed(.init(nextReviewAt: start), rating: .good, now: start, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: reviewed.nextReviewAt), 12)
        XCTAssertEqual(reviewed.nextReviewAt.timeIntervalSince(start), 23 * 3_600)
    }

    func testExtremeSchedulerInputCannotOverflowOrEmitInvalidState() {
        let extreme = VocabularyReviewState(repetition: .max, intervalDays: .max, easeFactor: .nan, nextReviewAt: .distantFuture)
        let reviewed = VocabularyReviewRules.reviewed(extreme, rating: .easy, now: now, calendar: utc)
        XCTAssertTrue(VocabularyReviewRules.isValid(reviewed))
        XCTAssertEqual(reviewed.intervalDays, VocabularyReviewRules.maximumIntervalDays)
        XCTAssertEqual(reviewed.repetition, VocabularyReviewRules.maximumRepetitions)
        let invalidClock = VocabularyReviewRules.reviewed(extreme, rating: .again,
                                                          now: Date(timeIntervalSince1970: .infinity), calendar: utc)
        XCTAssertTrue(VocabularyReviewRules.isValid(invalidClock))
    }

    func testDueListUsesActualReviewStateWithoutInferringMastery() {
        var library = VocabularyLibrary()
        var due = card("due"), future = card("future")
        due.review.nextReviewAt = now
        future.review.nextReviewAt = now.addingTimeInterval(1)
        future.review.repetition = 50
        future.review.intervalDays = 20_000
        library.cards = [future, due]
        XCTAssertEqual(library.dueCards(at: now).map(\.id), [due.id])
        XCTAssertEqual(library.dueCards(at: now.addingTimeInterval(-1)).count, 0)
        XCTAssertEqual(library.dueCards(at: now.addingTimeInterval(1)).count, 2)
    }
}
