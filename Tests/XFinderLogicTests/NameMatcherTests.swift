import XCTest

/// XF-T30 W5a — tier order (exact < prefix < wordPrefix < substring < fuzzy), word boundaries, Vietnamese
/// diacritic-insensitive folding in both NFC and NFD, fuzzy ordering, the budget/`tierEnded` flag, and stable ranking.
final class NameMatcherTests: XCTestCase {

    private func f(_ s: String) -> [UInt8] { NameMatcher.fold(s) }

    func testTierOrderIsExactLessThanPrefixLessThanWordPrefixLessThanSubstringLessThanFuzzy() {
        XCTAssertLessThan(MatchTier.exact, .prefix)
        XCTAssertLessThan(MatchTier.prefix, .wordPrefix)
        XCTAssertLessThan(MatchTier.wordPrefix, .substring)
        XCTAssertLessThan(MatchTier.substring, .fuzzy)
    }

    func testEmptyQueryNeverMatches() {
        XCTAssertNil(NameMatcher.match(query: [], name: f("report.pdf")))
        XCTAssertNil(NameMatcher.match(query: [], name: []))
    }

    func testExactMatch() {
        let m = NameMatcher.match(query: f("report.pdf"), name: f("report.pdf"))
        XCTAssertEqual(m?.tier, .exact)
    }

    func testPrefixMatch() {
        let m = NameMatcher.match(query: f("rep"), name: f("report.pdf"))
        XCTAssertEqual(m?.tier, .prefix)
    }

    // Word boundaries: space, '-', '_', '.', and a letter/digit transition (contract §2).
    func testWordPrefixAfterSpace() {
        XCTAssertEqual(NameMatcher.match(query: f("cao"), name: f("bao cao.pdf"))?.tier, .wordPrefix)
    }

    func testWordPrefixAfterHyphen() {
        XCTAssertEqual(NameMatcher.match(query: f("final"), name: f("draft-final.docx"))?.tier, .wordPrefix)
    }

    func testWordPrefixAfterUnderscore() {
        XCTAssertEqual(NameMatcher.match(query: f("v2"), name: f("report_v2.pdf"))?.tier, .wordPrefix)
    }

    func testWordPrefixAfterDot() {
        XCTAssertEqual(NameMatcher.match(query: f("pdf"), name: f("report.pdf"))?.tier, .wordPrefix)
    }

    func testWordPrefixAtLetterToDigitBoundary() {
        // "file2" — "2" starts a new word right after the letter "e".
        XCTAssertEqual(NameMatcher.match(query: f("2"), name: f("file2.txt"))?.tier, .wordPrefix)
    }

    func testWordPrefixAtDigitToLetterBoundary() {
        // "2nd" — "nd" starts a new word right after the digit "2".
        XCTAssertEqual(NameMatcher.match(query: f("nd"), name: f("2nd place.txt"))?.tier, .wordPrefix)
    }

    func testWordPrefixPrefersTheEarliestMatchingWordStart() {
        // "foo" starts a word at both index 2 and index 6 of same-length names; the earlier one must score higher
        // (same name length in both fixtures, so the only thing that can move the score is the word-start index).
        let earlier = NameMatcher.match(query: f("foo"), name: f("a-foo-xxx"))
        let later = NameMatcher.match(query: f("foo"), name: f("a-xxx-foo"))
        XCTAssertEqual(earlier?.tier, .wordPrefix)
        XCTAssertEqual(later?.tier, .wordPrefix)
        XCTAssertGreaterThan(earlier!.score, later!.score, "an earlier word start must score higher")
        // Direct check on a name with the word repeated: the match must report the score of the FIRST occurrence,
        // i.e. the same score as "a-foo-xxx" above (word start at index 2 in both).
        let repeated = NameMatcher.match(query: f("foo"), name: f("a-foo-foo"))
        XCTAssertEqual(repeated, earlier, "the score must come from the earliest occurrence of the two")
    }

    func testSubstringAnywhereNotAtAWordStart() {
        // "ort" is inside "report" but does not start a word.
        XCTAssertEqual(NameMatcher.match(query: f("ort"), name: f("report.pdf"))?.tier, .substring)
    }

    func testFuzzySubsequenceInOrder() {
        // "rpt" as an in-order subsequence of "report.pdf", not contiguous anywhere.
        XCTAssertEqual(NameMatcher.match(query: f("rpt"), name: f("report.pdf"))?.tier, .fuzzy)
    }

    func testFuzzyFailsWhenBytesAreOutOfOrder() {
        // No byte of "xyz" appears anywhere in "report.pdf" at all — too weak a case on its own, since a mutant that
        // checks "does this byte occur anywhere in the query" (set membership) instead of "is this the NEXT query
        // byte in order" would also correctly return nil here.
        XCTAssertNil(NameMatcher.match(query: f("xyz"), name: f("report.pdf")))
    }

    func testFuzzyRequiresBytesInOrderNotJustSetMembership() {
        // Both bytes of "ba" occur in "ab", but not in that order — a subsequence match must fail. (A mutant that
        // tests "is this byte anywhere in the query" instead of "is this the next expected query byte" would wrongly
        // accept this: probe confirmed query="ba" name="ab" gives true under byte-membership, false under subsequence.)
        XCTAssertNil(NameMatcher.match(query: f("ba"), name: f("ab")))
        // Positive control: the same two bytes in the matching order DO fuzzy-match.
        XCTAssertEqual(NameMatcher.match(query: f("ba"), name: f("ba"))?.tier, .exact)
        XCTAssertEqual(NameMatcher.match(query: f("ab"), name: f("xaxbx"))?.tier, .fuzzy)
    }

    // Vietnamese diacritics: a query typed without diacritics must find a name with them, and it must not matter
    // whether the name's String value is NFC-composed ("á" = U+00E1) or NFD-decomposed ("á" = "a" + U+0301).
    func testVietnameseWithoutDiacriticsMatchesNFCName() {
        let nfc = "Báo cáo tháng" // precomposed, the normal way Swift string literals come in
        // `String ==` is Unicode canonical-equivalence, so it cannot tell NFC from NFD apart — compare the raw
        // scalar sequences instead to confirm this fixture really is precomposed ("á" = one scalar, U+00E1).
        XCTAssertEqual(Array(nfc.unicodeScalars).map(\.value), [0x42, 0xE1, 0x6F, 0x20, 0x63, 0xE1, 0x6F, 0x20, 0x74, 0x68, 0xE1, 0x6E, 0x67],
                       "test fixture must actually be NFC")
        XCTAssertEqual(NameMatcher.match(query: f("bao cao"), name: f(nfc))?.tier, .prefix)
    }

    func testVietnameseWithoutDiacriticsMatchesNFDName() {
        let nfc = "Báo cáo tháng"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(nfd.unicodeScalars), Array(nfc.unicodeScalars), "test fixture must actually be NFD")
        XCTAssertEqual(NameMatcher.match(query: f("bao cao"), name: f(nfd))?.tier, .prefix)
    }

    func testNFCAndNFDNamesFoldToTheSameBytes() {
        let nfc = "đường dẫn"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        XCTAssertEqual(f(nfc), f(nfd))
    }

    func testPositiveControlPlainAsciiStillFolds() {
        // Positive control: an ASCII name with no diacritics at all still case-folds normally.
        XCTAssertEqual(f("REPORT"), f("report"))
    }

    // Fuzzy ordering: a tighter / more word-aligned fuzzy match scores higher than a loose one.
    func testFuzzyOrderingPrefersWordAlignedAndContiguousMatches() {
        let candidates: [(id: Int, name: [UInt8])] = [
            (0, f("xaxbxcx")),       // scattered, no word alignment
            (1, f("abc report")),    // contiguous "abc" right at the start (word-aligned)
        ]
        let (results, tierEnded) = NameMatcher.rank(candidates, query: f("abc"), limit: 10, fuzzyBudget: 10)
        XCTAssertFalse(tierEnded)
        XCTAssertEqual(results.first?.id, 1, "the contiguous, word-aligned fuzzy match should rank first")
    }

    func testRankOrdersByTierThenScoreThenName() {
        let candidates: [(id: String, name: [UInt8])] = [
            ("b-substring", f("xreportx")),
            ("a-exact", f("report")),
            ("c-prefix", f("reportxyz")),
        ]
        let (results, tierEnded) = NameMatcher.rank(candidates, query: f("report"), limit: 10, fuzzyBudget: 10)
        XCTAssertFalse(tierEnded)
        XCTAssertEqual(results.map(\.id), ["a-exact", "c-prefix", "b-substring"])
    }

    func testRankRespectsLimit() {
        let candidates: [(id: Int, name: [UInt8])] = (0..<5).map { ($0, f("report\($0)")) }
        let (results, _) = NameMatcher.rank(candidates, query: f("report"), limit: 2, fuzzyBudget: 10)
        XCTAssertEqual(results.count, 2)
    }

    func testRankStableOrderForTiedCandidatesUsesNaturalNameOrder() {
        // Two candidates land on the exact same tier and score (both are an identical prefix match at the start);
        // the tie-break must be deterministic (natural name order), not insertion order.
        let candidates: [(id: String, name: [UInt8])] = [
            ("file10", f("file10.txt")),
            ("file2", f("file2.txt")),
        ]
        let (results, _) = NameMatcher.rank(candidates, query: f("file"), limit: 10, fuzzyBudget: 10)
        XCTAssertEqual(results.map(\.id), ["file2", "file10"], "natural compare: File 2 before File 10")
    }

    // Budget: the fuzzy tier only tries `fuzzyBudget` candidates that failed every cheaper tier; past the budget,
    // `tierEnded` is true and those candidates are simply not tried (not force-included, not force-excluded by error).
    func testFuzzyBudgetStopsTryingAndReportsTierEnded() {
        // Query "yz" never appears contiguously in any candidate (every name has an "x" wedged between "y" and "z"),
        // so none of these can match any tier cheaper than fuzzy — but all of them DO match fuzzy ("y" then later "z").
        let candidates: [(id: Int, name: [UInt8])] = (0..<10).map { ($0, f("ayx\($0)xz")) }
        for (_, name) in candidates {
            XCTAssertEqual(NameMatcher.match(query: f("yz"), name: name)?.tier, .fuzzy, "fixture must only match fuzzy")
        }
        let (resultsFullBudget, tierEndedFullBudget) = NameMatcher.rank(candidates, query: f("yz"), limit: 100, fuzzyBudget: 100)
        XCTAssertFalse(tierEndedFullBudget)
        XCTAssertEqual(resultsFullBudget.count, 10)

        let (resultsSmallBudget, tierEndedSmallBudget) = NameMatcher.rank(candidates, query: f("yz"), limit: 100, fuzzyBudget: 3)
        XCTAssertTrue(tierEndedSmallBudget)
        XCTAssertEqual(resultsSmallBudget.count, 3, "only the first 3 candidates got a fuzzy try")
    }

    func testCheapTierMatchesNeverCountAgainstTheFuzzyBudget() {
        // One candidate matches a cheap tier (prefix); it must not consume any of the fuzzy budget, so the one
        // genuinely-fuzzy candidate still gets its try even with a budget of 1.
        let candidates: [(id: String, name: [UInt8])] = [
            ("prefix-match", f("report final")),
            ("fuzzy-match", f("xrxexpxoxrxtx")), // "report" as a scattered subsequence only
        ]
        let (results, tierEnded) = NameMatcher.rank(candidates, query: f("report"), limit: 10, fuzzyBudget: 1)
        XCTAssertFalse(tierEnded)
        XCTAssertEqual(Set(results.map(\.id)), ["prefix-match", "fuzzy-match"])
    }
}
