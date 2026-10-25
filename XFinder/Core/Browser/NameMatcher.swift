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
    /// The folded bytes of `s`, exactly as `EntryRules.foldBytes` folds names (lowercase, no diacritics, đ → d), so
    /// "bao cao" finds "Báo cáo". W5a builder (pure): implement (delegate to `EntryRules.foldBytes`).
    static func fold(_ s: String) -> [UInt8] { EntryRules.foldBytes(s) }

    /// The best tier `query` reaches against `name` (both folded), or nil. exact: equal; prefix: name starts with query;
    /// wordPrefix: query starts a word inside name (after space, -, _, ., or a lowercase→digit / letter↔digit boundary);
    /// substring: anywhere; fuzzy: every query byte appears in order. Empty query ⇒ nil. W5a builder (pure): implement.
    static func match(query: [UInt8], name: [UInt8]) -> NameMatch? { nil }

    struct Ranked<ID: Hashable & Sendable>: Sendable {
        let id: ID
        let match: NameMatch
    }

    /// Ranks `candidates` (id + folded name) by tier then score then name order; at most `limit`. The fuzzy tier tries
    /// at most `fuzzyBudget` candidates that failed every cheaper tier; `tierEnded` is true when the budget ran out.
    /// W5a builder (pure): implement.
    static func rank<ID: Hashable & Sendable>(_ candidates: [(id: ID, name: [UInt8])], query: [UInt8], limit: Int,
                                               fuzzyBudget: Int) -> (results: [Ranked<ID>], tierEnded: Bool) {
        ([], false)
    }
}
