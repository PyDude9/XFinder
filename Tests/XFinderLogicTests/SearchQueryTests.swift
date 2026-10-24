import XCTest

final class SearchQueryTests: XCTestCase {

    // A fixed, deterministic "now": Wednesday 2026-10-21 12:00:00 UTC, Gregorian calendar, UTC timezone, so
    // "today"/"this week"/month-without-year resolve the same on every machine running this suite.
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 1
        return cal
    }()

    private var now: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 21; comps.hour = 12
        comps.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: comps)!
    }

    private func parse(_ text: String) -> ParsedSearch {
        SearchQuery.parse(text, now: now, calendar: calendar)
    }

    private func expr(_ text: String) -> String {
        SearchQuery.mdfindExpression(parse(text), now: now, calendar: calendar)
    }

    // MARK: - singular vs plural kind (the single most load-bearing rule)

    func test_singularPdfIsFilenameTerm() {
        let p = parse("pdf")
        XCTAssertEqual(p.terms, ["pdf"])
        XCTAssertTrue(p.chips.isEmpty)
    }

    func test_pluralPdfsIsKindChip() {
        let p = parse("pdfs")
        XCTAssertEqual(p.chips, [SearchChip(field: .kind, value: .kind(.pdfs), uncertain: false)])
        XCTAssertTrue(p.terms.isEmpty)
    }

    func test_kindSyntaxIsKindChip() {
        let p = parse("kind:pdf")
        XCTAssertEqual(p.chips, [SearchChip(field: .kind, value: .kind(.pdfs), uncertain: false)])
    }

    func test_vietnameseKindWordAnh() {
        let p = parse("ảnh")
        XCTAssertEqual(p.chips, [SearchChip(field: .kind, value: .kind(.images), uncertain: false)])
    }

    func test_vietnameseKindWordAccentInsensitive() {
        // "anh" (no diacritics) should still fold to "ảnh" per EntryRules-style accent folding.
        let p = parse("anh")
        XCTAssertEqual(p.chips, [SearchChip(field: .kind, value: .kind(.images), uncertain: false)])
    }

    func test_vietnameseKindWordCaseInsensitive() {
        // Folding must also ignore case, independent of accents (uppercase ASCII, no diacritics at all).
        let p = parse("ANH")
        XCTAssertEqual(p.chips, [SearchChip(field: .kind, value: .kind(.images), uncertain: false)])
    }

    func test_vietnameseTepPdf() {
        let p = parse("tệp pdf")
        XCTAssertEqual(p.chips, [SearchChip(field: .kind, value: .kind(.pdfs), uncertain: false)])
        XCTAssertTrue(p.terms.isEmpty)
    }

    func test_allEnglishKindWords() {
        let cases: [(String, KindFilter)] = [
            ("images", .images), ("videos", .videos), ("audio", .audio), ("documents", .documents),
            ("spreadsheets", .spreadsheets), ("presentations", .presentations), ("archives", .archives),
            ("folders", .folders), ("applications", .applications), ("screenshots", .screenshots),
            ("code", .code), ("text", .text),
        ]
        for (word, kind) in cases {
            let p = parse(word)
            XCTAssertEqual(p.chips.first?.value, .kind(kind), "word: \(word)")
        }
    }

    func test_allVietnameseKindWords() {
        let cases: [(String, KindFilter)] = [
            ("ảnh", .images), ("video", .videos), ("nhạc", .audio), ("tài liệu", .documents),
            ("bảng tính", .spreadsheets), ("bản trình chiếu", .presentations), ("tệp nén", .archives),
            ("thư mục", .folders), ("ứng dụng", .applications), ("ảnh chụp màn hình", .screenshots),
            ("mã nguồn", .code),
        ]
        for (phrase, kind) in cases {
            let p = parse(phrase)
            XCTAssertTrue(p.chips.contains { $0.value == .kind(kind) }, "phrase: \(phrase)")
        }
    }

    // MARK: - phrases, exclusions

    func test_quotedPhraseIsPhraseNotTerm() {
        let p = parse("\"quarterly report\"")
        XCTAssertEqual(p.phrases, ["quarterly report"])
        XCTAssertTrue(p.terms.isEmpty)
    }

    func test_dashExcludesWord() {
        let p = parse("report -draft")
        XCTAssertEqual(p.terms, ["report"])
        XCTAssertEqual(p.excluded, ["draft"])
    }

    func test_bangExcludesWord() {
        let p = parse("report !draft")
        XCTAssertEqual(p.excluded, ["draft"])
    }

    func test_bareDashIsDropped() {
        let p = parse("report - draft")
        XCTAssertEqual(p.terms, ["report", "draft"])
        XCTAssertTrue(p.excluded.isEmpty)
    }

    // MARK: - dates: English relative phrases

    func test_today() {
        let p = parse("today")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.today), uncertain: false)])
    }

    func test_yesterday() {
        let p = parse("yesterday")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.yesterday), uncertain: false)])
    }

    func test_thisWeek() {
        let p = parse("this week")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.thisWeek), uncertain: false)])
    }

    func test_lastWeek() {
        let p = parse("last week")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.lastWeek), uncertain: false)])
    }

    func test_fromLastWeek() {
        let p = parse("pdfs from last week")
        XCTAssertTrue(p.chips.contains(SearchChip(field: .kind, value: .kind(.pdfs), uncertain: false)))
        XCTAssertTrue(p.chips.contains(SearchChip(field: .modified, value: .date(.lastWeek), uncertain: false)))
        XCTAssertTrue(p.terms.isEmpty, "'from' should be consumed by the phrase, not left as a term")
    }

    func test_thisMonthLastMonth() {
        XCTAssertEqual(parse("this month").chips, [SearchChip(field: .modified, value: .date(.thisMonth), uncertain: false)])
        XCTAssertEqual(parse("last month").chips, [SearchChip(field: .modified, value: .date(.lastMonth), uncertain: false)])
    }

    func test_thisYearLastYear() {
        XCTAssertEqual(parse("this year").chips, [SearchChip(field: .modified, value: .date(.thisYear), uncertain: false)])
        XCTAssertEqual(parse("last year").chips, [SearchChip(field: .modified, value: .date(.lastYear), uncertain: false)])
    }

    func test_pastNDays() {
        let p = parse("past 7 days")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.pastDays(7)), uncertain: false)])
    }

    func test_olderThanNDays() {
        let p = parse("older than 30 days")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.olderThanDays(30)), uncertain: false)])
    }

    // MARK: - dates: Vietnamese relative phrases

    func test_homNayHomQua() {
        XCTAssertEqual(parse("hôm nay").chips, [SearchChip(field: .modified, value: .date(.today), uncertain: false)])
        XCTAssertEqual(parse("hôm qua").chips, [SearchChip(field: .modified, value: .date(.yesterday), uncertain: false)])
    }

    func test_tuanNayTuanTruoc() {
        XCTAssertEqual(parse("tuần này").chips, [SearchChip(field: .modified, value: .date(.thisWeek), uncertain: false)])
        XCTAssertEqual(parse("tuần trước").chips, [SearchChip(field: .modified, value: .date(.lastWeek), uncertain: false)])
    }

    func test_thangNayThangTruoc() {
        XCTAssertEqual(parse("tháng này").chips, [SearchChip(field: .modified, value: .date(.thisMonth), uncertain: false)])
        XCTAssertEqual(parse("tháng trước").chips, [SearchChip(field: .modified, value: .date(.lastMonth), uncertain: false)])
    }

    func test_namNayNamNgoai() {
        XCTAssertEqual(parse("năm nay").chips, [SearchChip(field: .modified, value: .date(.thisYear), uncertain: false)])
        XCTAssertEqual(parse("năm ngoái").chips, [SearchChip(field: .modified, value: .date(.lastYear), uncertain: false)])
    }

    func test_nNgayQua() {
        let p = parse("7 ngày qua")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.pastDays(7)), uncertain: false)])
    }

    func test_cuHonNNgay() {
        let p = parse("cũ hơn 30 ngày")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.olderThanDays(30)), uncertain: false)])
    }

    func test_anhHomNay() {
        let p = parse("ảnh hôm nay")
        XCTAssertTrue(p.chips.contains(SearchChip(field: .kind, value: .kind(.images), uncertain: false)))
        XCTAssertTrue(p.chips.contains(SearchChip(field: .modified, value: .date(.today), uncertain: false)))
    }

    // MARK: - bare month name without year => uncertain, most-recent-occurrence

    func test_bareMonthNameEnglishPastThisYear() {
        // now = Oct 21 2026; "March" has already passed this year => March 2026.
        let p = parse("march")
        XCTAssertEqual(p.chips.count, 1)
        guard case .date(.month(let year, let month)) = p.chips[0].value else { return XCTFail("expected month chip") }
        XCTAssertEqual(year, 2026)
        XCTAssertEqual(month, 3)
        XCTAssertTrue(p.chips[0].uncertain)
    }

    func test_bareMonthNameEnglishFutureRollsToLastYear() {
        // now = Oct 21 2026; "December" has not happened yet this year => December 2025.
        let p = parse("december")
        guard case .date(.month(let year, let month)) = p.chips[0].value else { return XCTFail("expected month chip") }
        XCTAssertEqual(year, 2025)
        XCTAssertEqual(month, 12)
        XCTAssertTrue(p.chips[0].uncertain)
    }

    func test_bareMonthNameCurrentMonthIsThisYear() {
        // now is October => "october" resolves to this October, not last year's.
        let p = parse("october")
        guard case .date(.month(let year, let month)) = p.chips[0].value else { return XCTFail("expected month chip") }
        XCTAssertEqual(year, 2026)
        XCTAssertEqual(month, 10)
    }

    func test_thangBaVietnamese() {
        let p = parse("tháng 3")
        guard case .date(.month(let year, let month)) = p.chips[0].value else { return XCTFail("expected month chip") }
        XCTAssertEqual(year, 2026)
        XCTAssertEqual(month, 3)
        XCTAssertTrue(p.chips[0].uncertain)
    }

    func test_nonUncertainChipsAreNotMarkedUncertain() {
        XCTAssertFalse(parse("today").chips[0].uncertain)
        XCTAssertFalse(parse("pdfs").chips[0].uncertain)
    }

    // MARK: - created vs modified

    func test_modifiedKeywordSelectsModifiedField() {
        let p = parse("modified:today")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.today), uncertain: false)])
    }

    func test_createdKeywordSelectsCreatedField() {
        let p = parse("created:today")
        XCTAssertEqual(p.chips, [SearchChip(field: .created, value: .date(.today), uncertain: false)])
    }

    func test_defaultDateFieldIsModified() {
        // Plain-sentence dates with no "created"/"modified" qualifier default to modified (contract).
        let p = parse("today")
        XCTAssertEqual(p.chips[0].field, .modified)
    }

    // MARK: - size

    func test_sizeOverUnit() {
        let p = parse("larger than 1 GB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.greater, 1_073_741_824), uncertain: false)])
    }

    func test_sizeSmallerUnit() {
        let p = parse("smaller than 10 MB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.less, 10 * 1024 * 1024), uncertain: false)])
    }

    func test_lonHonVietnamese() {
        let p = parse("lớn hơn 1 GB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.greater, 1_073_741_824), uncertain: false)])
    }

    func test_nhoHonVietnamese() {
        let p = parse("nhỏ hơn 10 MB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.less, 10 * 1024 * 1024), uncertain: false)])
    }

    func test_sizeOverWithoutUnitIsNotAChip() {
        // Checklist: "over 5" without a unit stays plain words, not a size chip.
        let p = parse("over 5")
        XCTAssertTrue(p.chips.isEmpty)
    }

    func test_sizeSyntaxGreater() {
        let p = parse("size:>1GB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.greater, 1_073_741_824), uncertain: false)])
    }

    func test_sizeSyntaxGreaterOrEqual() {
        let p = parse("size:>=500KB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.greaterOrEqual, 500 * 1024), uncertain: false)])
    }

    func test_sizeSyntaxLess() {
        let p = parse("size:<10MB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.less, 10 * 1024 * 1024), uncertain: false)])
    }

    func test_sizeSyntaxLessOrEqual() {
        let p = parse("size:<=2GB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.lessOrEqual, 2 * 1024 * 1024 * 1024), uncertain: false)])
    }

    func test_sizeSyntaxBareEqualsNoUnitIsBytes() {
        // Contract: "`size:` không đơn vị = byte" (unqualified `size:` syntax, unlike bare-word "over 5").
        let p = parse("size:1024")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.equal, 1024), uncertain: false)])
    }

    func test_sizeKiBEqualsKB() {
        let kib = parse("size:1KiB").chips[0]
        let kb = parse("size:1KB").chips[0]
        XCTAssertEqual(kib.value, kb.value)
    }

    func test_sizeDecimalValue() {
        let p = parse("size:1.5GB")
        guard case .size(_, let bytes) = p.chips[0].value else { return XCTFail() }
        XCTAssertEqual(bytes, Int64(1.5 * 1024 * 1024 * 1024))
    }

    // MARK: - source (downloaded from)

    func test_downloadedFromGithub() {
        let p = parse("downloaded from github")
        XCTAssertEqual(p.chips, [SearchChip(field: .source, value: .text("github"), uncertain: false)])
    }

    func test_taiTuGithubVietnamese() {
        let p = parse("tải từ github")
        XCTAssertEqual(p.chips, [SearchChip(field: .source, value: .text("github"), uncertain: false)])
    }

    func test_fromSyntax() {
        let p = parse("from:github.com")
        XCTAssertEqual(p.chips, [SearchChip(field: .source, value: .text("github.com"), uncertain: false)])
    }

    // MARK: - ext / tag / content syntax

    func test_extSyntax() {
        let p = parse("ext:pdf")
        XCTAssertEqual(p.chips, [SearchChip(field: .ext, value: .text("pdf"), uncertain: false)])
    }

    func test_extSyntaxStripsLeadingDot() {
        let p = parse("ext:.pdf")
        XCTAssertEqual(p.chips, [SearchChip(field: .ext, value: .text("pdf"), uncertain: false)])
    }

    func test_tagSyntax() {
        let p = parse("tag:important")
        XCTAssertEqual(p.chips, [SearchChip(field: .tag, value: .text("important"), uncertain: false)])
    }

    func test_tagSyntaxQuotedMultiWord() {
        let p = parse("tag:\"work in progress\"")
        XCTAssertEqual(p.chips, [SearchChip(field: .tag, value: .text("work in progress"), uncertain: false)])
    }

    func test_contentSyntax() {
        let p = parse("content:invoice")
        XCTAssertEqual(p.chips, [SearchChip(field: .content, value: .text("invoice"), uncertain: false)])
    }

    // MARK: - unknown operator => plain word + warning

    func test_unknownFieldSyntaxBecomesTermWithWarning() {
        let p = parse("bogus:value")
        XCTAssertEqual(p.terms, ["bogus:value"])
        XCTAssertEqual(p.warnings, ["Toán tử không rõ: giữ là chữ"])
    }

    func test_unknownKindTokenBecomesTermWithWarning() {
        let p = parse("kind:nonsense")
        XCTAssertEqual(p.terms, ["kind:nonsense"])
        XCTAssertFalse(p.warnings.isEmpty)
    }

    // MARK: - combined / mixed sentence

    func test_mixedTermsAndChips() {
        let p = parse("report pdfs from last week -draft")
        XCTAssertEqual(p.terms, ["report"])
        XCTAssertEqual(p.excluded, ["draft"])
        XCTAssertTrue(p.chips.contains(SearchChip(field: .kind, value: .kind(.pdfs), uncertain: false)))
        XCTAssertTrue(p.chips.contains(SearchChip(field: .modified, value: .date(.lastWeek), uncertain: false)))
    }

    // MARK: - isEmpty

    func test_isEmptyTrueForBlankInput() {
        XCTAssertTrue(parse("").isEmpty)
        XCTAssertTrue(parse("   ").isEmpty)
    }

    func test_isEmptyFalseWithOnlyAWarningTerm() {
        // A single bare word is a term, not empty.
        XCTAssertFalse(parse("report").isEmpty)
    }

    // MARK: - chip id stability

    func test_chipIdStableAcrossReparseSameIntent() {
        let a = parse("pdfs").chips[0]
        let b = parse("kind:pdf").chips[0]
        XCTAssertEqual(a.id, b.id)
    }

    func test_chipIdDiffersByField() {
        let modified = SearchChip(field: .modified, value: .date(.today), uncertain: false)
        let created = SearchChip(field: .created, value: .date(.today), uncertain: false)
        XCTAssertNotEqual(modified.id, created.id)
    }

    // MARK: - removing / replacing chips

    func test_removingChipById() {
        let search = parse("pdfs today")
        let kindID = search.chips.first { if case .kind = $0.value { return true }; return false }!.id
        let result = SearchQuery.removing(chip: kindID, from: search)
        XCTAssertEqual(result.chips.count, 1)
        XCTAssertFalse(result.chips.contains { $0.id == kindID })
    }

    func test_removingUnknownIdIsNoOp() {
        let search = parse("pdfs")
        let result = SearchQuery.removing(chip: "nonexistent", from: search)
        XCTAssertEqual(result, search)
    }

    func test_replacingExistingChipKeepsPosition() {
        let search = parse("pdfs today")
        let dateChip = search.chips.first { if case .date = $0.value { return true }; return false }!
        let newChip = SearchChip(field: .modified, value: .date(.yesterday), uncertain: false)
        let result = SearchQuery.replacing(id: dateChip.id, with: newChip, in: search)
        XCTAssertEqual(result.chips.count, 2)
        let idx = result.chips.firstIndex { if case .date(.yesterday) = $0.value { return true }; return false }
        XCTAssertEqual(idx, search.chips.firstIndex(of: dateChip))
    }

    func test_replacingMissingIdAppends() {
        let search = parse("pdfs")
        let newChip = SearchChip(field: .modified, value: .date(.today), uncertain: false)
        let result = SearchQuery.replacing(id: "missing-id", with: newChip, in: search)
        XCTAssertEqual(result.chips.count, 2)
        XCTAssertEqual(result.chips.last, newChip)
    }

    // MARK: - interval(of:)

    func test_intervalToday() {
        let (start, end) = SearchQuery.interval(of: .today, now: now, calendar: calendar)
        XCTAssertEqual(start, calendar.startOfDay(for: now))
        XCTAssertEqual(end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
    }

    func test_intervalOlderThanDaysHasNilStart() {
        let (start, end) = SearchQuery.interval(of: .olderThanDays(30), now: now, calendar: calendar)
        XCTAssertNil(start)
        XCTAssertNotNil(end)
    }

    func test_intervalPastDaysHasBothBounds() {
        let (start, end) = SearchQuery.interval(of: .pastDays(7), now: now, calendar: calendar)
        XCTAssertNotNil(start)
        XCTAssertNotNil(end)
        XCTAssertTrue(start! < end!)
    }

    func test_intervalThisWeekVsLastWeekAdjacent() {
        let (thisStart, _) = SearchQuery.interval(of: .thisWeek, now: now, calendar: calendar)
        let (_, lastEnd) = SearchQuery.interval(of: .lastWeek, now: now, calendar: calendar)
        XCTAssertEqual(thisStart, lastEnd)
    }

    func test_intervalMonthYearMonth() {
        let (start, end) = SearchQuery.interval(of: .month(year: 2026, month: 3), now: now, calendar: calendar)
        var startComps = DateComponents(); startComps.year = 2026; startComps.month = 3; startComps.day = 1
        XCTAssertEqual(start, calendar.date(from: startComps))
        var endComps = DateComponents(); endComps.year = 2026; endComps.month = 4; endComps.day = 1
        XCTAssertEqual(end, calendar.date(from: endComps))
    }

    // MARK: - mdfindExpression: empty / fallback

    func test_emptySearchFallsBackToMatchAll() {
        XCTAssertEqual(expr(""), "kMDItemFSName == \"*\"")
    }

    // MARK: - mdfindExpression: structure

    func test_expressionJoinsClausesWithAnd() {
        let e = expr("pdfs today")
        XCTAssertTrue(e.contains(" && "))
        XCTAssertFalse(e.contains(" || "), "clauses must be ANDed, not ORed, together")
        XCTAssertTrue(e.contains("kMDItemContentTypeTree"))
        XCTAssertTrue(e.contains("kMDItemFSContentChangeDate"))
    }

    func test_expressionTwoTermsAreAnded() {
        // Two plain filename terms must both be required (AND), matching Spotlight's implicit term semantics —
        // an OR join would silently widen every multi-word filename search.
        let e = expr("report draft")
        XCTAssertEqual(e, "kMDItemFSName == \"*report*\"cd && kMDItemFSName == \"*draft*\"cd")
    }

    func test_expressionTermUsesFSName() {
        let e = expr("report")
        XCTAssertEqual(e, "kMDItemFSName == \"*report*\"cd")
    }

    func test_expressionPhraseUsesCaseSensitiveFlag() {
        let e = expr("\"Quarterly Report\"")
        XCTAssertEqual(e, "kMDItemFSName == \"*Quarterly Report*\"c")
    }

    func test_expressionExcludedWrapsInNegation() {
        let e = expr("-draft")
        XCTAssertEqual(e, "!(kMDItemFSName == \"*draft*\"cd)")
    }

    func test_expressionKindUsesContentTypeTree() {
        let e = expr("pdfs")
        XCTAssertEqual(e, "kMDItemContentTypeTree == \"com.adobe.pdf\"cd")
    }

    func test_expressionSourceUsesWhereFroms() {
        let e = expr("from:github")
        XCTAssertEqual(e, "kMDItemWhereFroms == \"*github*\"cd")
    }

    func test_expressionContentUsesTextContent() {
        let e = expr("content:invoice")
        XCTAssertEqual(e, "kMDItemTextContent == \"*invoice*\"cd")
    }

    func test_expressionTagUsesUserTags() {
        let e = expr("tag:important")
        XCTAssertEqual(e, "kMDItemUserTags == \"important\"cd")
    }

    func test_expressionExtUsesFSNameSuffix() {
        let e = expr("ext:pdf")
        XCTAssertEqual(e, "kMDItemFSName == \"*.pdf\"c")
    }

    func test_expressionSizeUsesFSSize() {
        let e = expr("size:>1024")
        XCTAssertEqual(e, "kMDItemFSSize > 1024")
    }

    func test_expressionDateUsesISOTimeLiteralUTC() {
        let e = expr("modified:today")
        XCTAssertTrue(e.contains("$time.iso("))
        XCTAssertTrue(e.contains("Z)"))
    }

    func test_expressionCreatedUsesCreationDateKey() {
        let e = expr("created:today")
        XCTAssertTrue(e.contains("kMDItemFSCreationDate"))
        XCTAssertFalse(e.contains("kMDItemFSContentChangeDate"))
    }

    func test_expressionOlderThanOnlyHasUpperBound() {
        let e = expr("older than 30 days")
        XCTAssertTrue(e.contains("kMDItemFSContentChangeDate <"))
        XCTAssertFalse(e.contains(">="))
    }

    // MARK: - mdfindExpression: quote/backslash escaping

    func test_expressionEscapesQuoteInTerm() {
        let p = ParsedSearch(chips: [], terms: ["weird\"name"], phrases: [], excluded: [], warnings: [])
        let e = SearchQuery.mdfindExpression(p, now: now, calendar: calendar)
        XCTAssertEqual(e, "kMDItemFSName == \"*weird\\\"name*\"cd")
    }

    func test_expressionEscapesBackslashInTerm() {
        let p = ParsedSearch(chips: [], terms: ["a\\b"], phrases: [], excluded: [], warnings: [])
        let e = SearchQuery.mdfindExpression(p, now: now, calendar: calendar)
        XCTAssertEqual(e, "kMDItemFSName == \"*a\\\\b*\"cd")
    }

    // MARK: - full sentence end to end

    func test_pdfsFromLastWeekExpression() {
        let e = expr("pdfs from last week")
        XCTAssertTrue(e.contains("kMDItemContentTypeTree == \"com.adobe.pdf\"cd"))
        XCTAssertTrue(e.contains("kMDItemFSContentChangeDate >="))
        XCTAssertTrue(e.contains("kMDItemFSContentChangeDate <"))
    }

    // MARK: - verify pass: "screenshots" must use the measured screen-capture flag, not a PNG content-type compare

    // Measured on this machine (2026-10-24): `kMDItemContentTypeTree == "public.png"cd` matches every PNG file on
    // disk (34 625, `mdfind -count`), while `kMDItemIsScreenCapture = 1` matches only the 147 files Spotlight
    // actually flagged as screen captures. Mapping "screenshots" to a bare PNG compare silently turns a screenshot
    // search into an "any PNG" search — a real behavior defect, not a style choice.
    func test_expressionScreenshotsUsesIsScreenCaptureNotPNGContentType() {
        let e = expr("screenshots")
        XCTAssertEqual(e, "kMDItemIsScreenCapture = 1")
        XCTAssertFalse(e.contains("public.png"))
        XCTAssertFalse(e.contains("kMDItemContentTypeTree"))
    }

    func test_expressionVietnameseScreenshotPhraseUsesIsScreenCapture() {
        let e = expr("ảnh chụp màn hình")
        XCTAssertEqual(e, "kMDItemIsScreenCapture = 1")
    }

    func test_expressionKindSyntaxScreenshotUsesIsScreenCapture() {
        let e = expr("kind:screenshot")
        XCTAssertEqual(e, "kMDItemIsScreenCapture = 1")
    }

    // MARK: - verify pass: "edited:" is a documented synonym for "modified:" (contract: "created/edited/modified")

    func test_editedFieldSyntaxSelectsModifiedField() {
        let p = parse("edited:today")
        XCTAssertEqual(p.chips, [SearchChip(field: .modified, value: .date(.today), uncertain: false)])
    }

    func test_editedFieldSyntaxChipIdMatchesModifiedFieldSyntax() {
        // Same underlying field+value ⇒ same stable chip id, so the UI can't end up with two different-looking
        // chips for what the contract says is the same field.
        let viaEdited = parse("edited:today").chips[0]
        let viaModified = parse("modified:today").chips[0]
        XCTAssertEqual(viaEdited.id, viaModified.id)
        XCTAssertEqual(viaEdited.field, .modified)
    }

    func test_editedFieldSyntaxExpressionUsesContentChangeDate() {
        let e = expr("edited:today")
        XCTAssertTrue(e.contains("kMDItemFSContentChangeDate"))
        XCTAssertFalse(e.contains("kMDItemFSCreationDate"))
    }

    // MARK: - verify pass: a size value that overflows Int64 must not crash the app

    // `Int64(Double)` traps when the result does not fit — a plain search keystroke like
    // "size:99999999999999999999" reaches `parseByteCount` with no guard in front of it, so an unclamped
    // conversion is a crash reachable straight from user-typed text, not just a theoretical edge case.
    func test_sizeSyntaxHugeDigitStringDoesNotCrashAndClampsToInt64Max() {
        let p = parse("size:99999999999999999999999999999999")
        guard case .size(.equal, let bytes) = p.chips[0].value else { return XCTFail("expected a size chip") }
        XCTAssertEqual(bytes, Int64.max)
    }

    func test_sizeSyntaxHugeValueWithUnitDoesNotCrashAndClampsToInt64Max() {
        let p = parse("size:>99999999999999999999GB")
        guard case .size(.greater, let bytes) = p.chips[0].value else { return XCTFail("expected a size chip") }
        XCTAssertEqual(bytes, Int64.max)
    }

    func test_plainSentenceHugeSizeDoesNotCrashAndClampsToInt64Max() {
        let p = parse("larger than 99999999999999999999999 GB")
        guard case .size(.greater, let bytes) = p.chips[0].value else { return XCTFail("expected a size chip") }
        XCTAssertEqual(bytes, Int64.max)
    }

    func test_sizeSyntaxOrdinaryValueUnaffectedByOverflowClamp() {
        // The overflow guard must not perturb the normal, already-covered path.
        let p = parse("size:1GB")
        XCTAssertEqual(p.chips, [SearchChip(field: .size, value: .size(.equal, 1_073_741_824), uncertain: false)])
    }
}
