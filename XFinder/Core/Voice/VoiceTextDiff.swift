import Foundation

/// One run of words in a diff. Consecutive words with the same status are grouped so the
/// card can render a whole removed phrase as one strikethrough span.
public struct DiffRun: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case same, removed, added }
    public let status: Status
    public let text: String
    public init(status: Status, text: String) {
        self.status = status
        self.text = text
    }
}

/// A word-level diff between the raw transcription and the rewritten text.
///
/// This is what the "review before inserting" card shows. It is a plain longest-common-
/// subsequence over words — deliberately not a character diff, because the reader wants to
/// see *which words* changed, and not a semantic diff, because there is no honest way to
/// compute one offline.
///
/// The algorithm is O(n·m) in time and memory. Dictation is short (a paragraph), so the
/// table stays small; a guard caps the input so a pathological paste cannot allocate
/// unbounded memory.
public enum VoiceTextDiff {

    /// Above this many tokens on either side the diff is skipped and the two texts are
    /// returned as a single removed run followed by a single added run. Honest and cheap.
    public static let maxTokens = 1500

    public static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    public static func runs(from old: String, to new: String) -> [DiffRun] {
        let a = tokenize(old)
        let b = tokenize(new)

        if a == b { return a.isEmpty ? [] : [DiffRun(status: .same, text: a.joined(separator: " "))] }

        guard a.count <= maxTokens, b.count <= maxTokens else {
            var out: [DiffRun] = []
            if !a.isEmpty { out.append(DiffRun(status: .removed, text: a.joined(separator: " "))) }
            if !b.isEmpty { out.append(DiffRun(status: .added, text: b.joined(separator: " "))) }
            return out
        }

        // LCS length table.
        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty && !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j]
                        ? table[i + 1][j + 1] + 1
                        : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        // Walk the table, emitting runs.
        var out: [DiffRun] = []
        var pending: [String] = []
        var pendingStatus: DiffRun.Status?

        func flush() {
            guard let status = pendingStatus, !pending.isEmpty else { return }
            out.append(DiffRun(status: status, text: pending.joined(separator: " ")))
            pending = []
            pendingStatus = nil
        }
        func emit(_ word: String, _ status: DiffRun.Status) {
            if pendingStatus == status {
                pending.append(word)
            } else {
                flush()
                pendingStatus = status
                pending = [word]
            }
        }

        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                emit(a[i], .same)
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                emit(a[i], .removed)
                i += 1
            } else {
                emit(b[j], .added)
                j += 1
            }
        }
        while i < a.count { emit(a[i], .removed); i += 1 }
        while j < b.count { emit(b[j], .added); j += 1 }
        flush()

        return out
    }

    /// True when the rewrite changed nothing the user needs to review — the card is
    /// skipped in that case so a no-op rewrite does not interrupt the flow.
    public static func isIdentical(from old: String, to new: String) -> Bool {
        tokenize(old) == tokenize(new)
    }

    /// How many tokens differ, for a one-line summary on the card.
    public static func changedTokenCount(from old: String, to new: String) -> Int {
        runs(from: old, to: new).reduce(0) { total, run in
            run.status == .same ? total : total + tokenize(run.text).count
        }
    }
}
