import Foundation

/// XF-T30 W5a — filename matching in tiers, the mechanism measured in FileOctopus (`NameMatcher`, `MatchTier`,
/// `fuzzyBudget`, `tierEndCause`): cheap tiers answer first, the fuzzy tier runs on a budget. Pure, symlinked into the
/// test package. Contract docs/specs/XF-T30-w5a-contract.md §2.
enum MatchTier: Int, Comparable, Codable, Sendable {
    case exact = 0, prefix, wordPrefix, substring, fuzzy
    static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
}

struct NameMatch: Equatable, Sendable {
    let tier: MatchTier
    /// Higher is better, only meaningful inside one tier.
    let score: Int
}

enum NameMatcher {
    /// ASCII digits 0-9.
    private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    /// ASCII letters a-z (bytes are already lowercased by `foldBytes`, but non-ASCII folded bytes can still contain
    /// uppercase-looking UTF-8 continuation bytes, so this only ever sees the ASCII range it is asked about).
    private static func isLower(_ b: UInt8) -> Bool { b >= 0x61 && b <= 0x7A }

    /// Separator bytes that start a new "word" inside a name: space, `-`, `_`, `.`.
    private static func isSeparator(_ b: UInt8) -> Bool { b == 0x20 || b == 0x2D || b == 0x5F || b == 0x2E }

    /// The folded bytes of `s`, exactly as `EntryRules.foldBytes` folds names (lowercase, no diacritics, đ → d), so
    /// "bao cao" finds "Báo cáo" whether `s` arrives NFC ("á" = U+00E1) or NFD ("á" = "a" + U+0301 combining acute):
    /// `EntryRules.foldBytes`'s table only covers precomposed scalars, so NFD input is precomposed first (probe:
    /// `"a\u{0301}".precomposedStringWithCanonicalMapping` → U+00E1, confirmed against the live Vietnamese case
    /// "Báo cáo".decomposedStringWithCanonicalMapping round-tripping back to the original NFC string).
    /// W5a builder (pure): implement (delegate to `EntryRules.foldBytes`).
    static func fold(_ s: String) -> [UInt8] {
        EntryRules.foldBytes(s.precomposedStringWithCanonicalMapping)
    }

    /// Indices (into `name`) that start a "word": index 0; right after a separator byte; and any letter→digit or
    /// digit→letter boundary ("file2" has a word start at "2", "2nd" has one at "nd").
    private static func wordStarts(_ name: [UInt8]) -> Set<Int> {
        guard !name.isEmpty else { return [] }
        var starts: Set<Int> = [0]
        for i in 1..<name.count {
            let prev = name[i - 1], cur = name[i]
            if isSeparator(prev) {
                if !isSeparator(cur) { starts.insert(i) }
                continue
            }
            let prevDigit = isDigit(prev), curDigit = isDigit(cur)
            let prevLetter = isLower(prev), curLetter = isLower(cur)
            if (prevDigit && curLetter) || (prevLetter && curDigit) { starts.insert(i) }
        }
        return starts
    }

    /// The best tier `query` reaches against `name` (both folded), or nil. exact: equal; prefix: name starts with query;
    /// wordPrefix: query starts a word inside name (after space, -, _, ., or a lowercase→digit / letter↔digit boundary);
    /// substring: anywhere; fuzzy: every query byte appears in order. Empty query ⇒ nil. W5a builder (pure): implement.
    static func match(query: [UInt8], name: [UInt8]) -> NameMatch? {
        if let cheap = cheapMatch(query: query, name: name) { return cheap }
        guard !query.isEmpty else { return nil }
        // fuzzy: every query byte appears in order (subsequence), with bonuses for matching at a word start and for
        // consecutive matched bytes (a tighter, more "word-like" match scores higher).
        if let fuzzyScore = fuzzyScore(query: query, name: name) {
            return NameMatch(tier: .fuzzy, score: fuzzyScore)
        }
        return nil
    }

    /// `match` restricted to the tiers cheaper than fuzzy (exact/prefix/wordPrefix/substring), nil if none of them
    /// hit — used directly by `rank` so a candidate that needs the (budgeted) fuzzy pass only runs `fuzzyScore` once,
    /// not once here (and discarded) plus once more in `rank`'s own budgeted fuzzy attempt.
    private static func cheapMatch(query: [UInt8], name: [UInt8]) -> NameMatch? {
        guard !query.isEmpty else { return nil }
        if query == name { return NameMatch(tier: .exact, score: 0) }
        if name.count >= query.count && Array(name[0..<query.count]) == query {
            // Shorter names are a tighter prefix match; score by how much shorter the name is than some reference ceiling.
            return NameMatch(tier: .prefix, score: -(name.count - query.count))
        }
        // wordPrefix: query matches starting at some word-start index other than 0 (0 was already tried as `prefix`).
        if name.count >= query.count {
            let starts = wordStarts(name).sorted()
            for start in starts where start > 0 && start + query.count <= name.count {
                if Array(name[start..<(start + query.count)]) == query {
                    // Earlier word starts and tighter overall length both score better.
                    return NameMatch(tier: .wordPrefix, score: -(start * 1000 + (name.count - query.count)))
                }
            }
        }
        // substring: anywhere, prefer the earliest occurrence.
        if let at = firstIndex(of: query, in: name) {
            return NameMatch(tier: .substring, score: -at)
        }
        return nil
    }

    /// Naive substring search (names are short; no need for a smarter algorithm here).
    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let limit = haystack.count - needle.count
        outer: for start in 0...limit {
            for i in 0..<needle.count where haystack[start + i] != needle[i] { continue outer }
            return start
        }
        return nil
    }

    /// Greedy left-to-right subsequence match: `query` bytes must all appear in `name`, in order. Score rewards
    /// matches that land on a word start (+3) and matches immediately following the previous match (+2, "liền
    /// mạch"), and penalizes the gap before the first match (closer to the front of the name is better).
    private static func fuzzyScore(query: [UInt8], name: [UInt8]) -> Int? {
        let starts = wordStarts(name)
        var qi = 0
        var lastMatched = -2
        var score = 0
        var firstMatch = -1
        for (ni, b) in name.enumerated() {
            guard qi < query.count else { break }
            if b == query[qi] {
                if firstMatch < 0 { firstMatch = ni }
                if starts.contains(ni) { score += 3 }
                if ni == lastMatched + 1 { score += 2 }
                lastMatched = ni
                qi += 1
            }
        }
        guard qi == query.count else { return nil }
        score -= firstMatch
        return score
    }

    struct Ranked<ID: Hashable & Sendable>: Sendable {
        let id: ID
        let match: NameMatch
    }

    /// Ranks `candidates` (id + folded name) by tier then score then name order; at most `limit`. The fuzzy tier tries
    /// at most `fuzzyBudget` candidates that failed every cheaper tier; `tierEnded` is true when the budget ran out.
    /// W5a builder (pure): implement.
    static func rank<ID: Hashable & Sendable>(_ candidates: [(id: ID, name: [UInt8])], query: [UInt8], limit: Int,
                                               fuzzyBudget: Int) -> (results: [Ranked<ID>], tierEnded: Bool) {
        guard !query.isEmpty, limit > 0 else { return ([], false) }
        var scored: [(ranked: Ranked<ID>, name: [UInt8])] = []
        scored.reserveCapacity(min(candidates.count, limit))
        var fuzzyTried = 0
        var tierEnded = false
        for (id, name) in candidates {
            if let cheap = cheapMatch(query: query, name: name) {
                scored.append((Ranked(id: id, match: cheap), name))
                continue
            }
            guard fuzzyTried < fuzzyBudget else { tierEnded = true; continue }
            fuzzyTried += 1
            if let fuzzyScore = fuzzyScore(query: query, name: name) {
                scored.append((Ranked(id: id, match: NameMatch(tier: .fuzzy, score: fuzzyScore)), name))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.ranked.match.tier != rhs.ranked.match.tier { return lhs.ranked.match.tier < rhs.ranked.match.tier }
            if lhs.ranked.match.score != rhs.ranked.match.score { return lhs.ranked.match.score > rhs.ranked.match.score }
            return EntryRules.naturalCompare(lhs.name, rhs.name) < 0
        }
        if scored.count > limit { scored = Array(scored.prefix(limit)) }
        return (scored.map(\.ranked), tierEnded)
    }
}
