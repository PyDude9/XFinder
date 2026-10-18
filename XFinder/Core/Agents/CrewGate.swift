import Foundation
import CryptoKit

/// XF-T23 Crew v2, phase v2a (2026-10-18): the pure rules behind the owner's "Lead Architect" brief — a signed message
/// envelope with TASK / CRITERIA / BRANCH, the Approved→merge gate, and the classifier that decides which shell commands
/// must always ask on the notch. Nothing here touches a process, a file or git; `CrewManager` (v2b) will drive it.
/// v1's `CrewRules` stays as it is until v2b replaces the relay's payload.
///
/// Facts this leans on (docs/specs/XF-T23-crew-v2.md §2): Claude Code's own `Bash(git push *)` rules do not catch
/// `git -C . push` (permissions.md "bash-rule-limits"), so `StateChanging.classify` tokenises instead of prefix-matching —
/// still "a safety net for the commands Claude usually produces", never a security boundary. The MAC covers EVERY field
/// (the P7b review: a `branch` outside the MAC is a forgeable branch).
enum CrewV2 {

    // MARK: - Roles

    /// What a role is FOR. Only `security` and `reviewer` may issue verdicts; only `lead` may ask to merge.
    enum Domain: String, CaseIterable, Sendable {
        case lead, frontend, backend, security, reviewer, custom

        var editsCode: Bool { self == .frontend || self == .backend || self == .custom }
        var mayJudge: Bool { self == .security || self == .reviewer }
    }

    /// `crew/<goal-slug>-<role>`: lower-case letters, digits and dashes only, like the role names.
    static func slug(_ goal: String) -> String {
        var out = ""
        var dash = false
        for ch in goal.lowercased().unicodeScalars {
            if ("a"..."z").contains(Character(ch)) || ("0"..."9").contains(Character(ch)) { out.append(Character(ch)); dash = false }
            else if !dash, !out.isEmpty { out.append("-"); dash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(32))
    }

    static func branchName(goalSlug: String, role: String) -> String { "crew/\(goalSlug)-\(role)" }

    static func isValidBranch(_ s: String) -> Bool {
        guard s.hasPrefix("crew/"), s.count <= 80 else { return false }
        let rest = s.dropFirst(5)
        guard let f = rest.first, f != "-", !rest.hasSuffix("-") else { return false }
        return rest.unicodeScalars.allSatisfy { ("a"..."z").contains(Character($0)) || ("0"..."9").contains(Character($0)) || $0 == "-" }
    }

    // MARK: - Envelope (the owner's schema)

    enum Kind: String, CaseIterable, Sendable { case task, status, done, question, verdict, conflict }
    enum Verdict: String, CaseIterable, Sendable { case approved, rejected }

    struct Envelope: Equatable, Sendable {
        var from: String
        var to: String                 // a role, or "all"
        var kind: Kind
        var text: String               // the free note (may be empty for task/verdict)
        var task: String?
        var criteria: String?
        var branch: String?
        var verdict: Verdict?
        var tests: String?             // `done`: what the builder ran, in its words
        var at: Date
    }

    static let maxField = 8_000
    /// A fresh formatter per call: `ISO8601DateFormatter` is not Sendable, so Swift 6 refuses it as a static let
    /// (build error 2026-10-18). Cheap enough for a message a few times a minute.
    private static func isoString(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.string(from: d)
    }

    /// One canonical line per field, in a fixed order, so the signature covers every field — adding a field means
    /// adding it HERE, or it is unsigned. Field values are length-prefixed so a value cannot smuggle a separator.
    static func canonical(_ e: Envelope, name: String) -> String {
        func f(_ tag: String, _ v: String?) -> String { let s = v ?? ""; return "\(tag):\(s.utf8.count):\(s)" }
        return [f("name", name), f("from", e.from), f("to", e.to), f("kind", e.kind.rawValue), f("text", e.text),
                f("task", e.task), f("criteria", e.criteria), f("branch", e.branch), f("verdict", e.verdict?.rawValue),
                f("tests", e.tests), f("at", isoString(e.at))].joined(separator: "\n")
    }

    /// SHA-256(canonical ⏎ token) — token LAST (no length extension of a secret prefix), never written to the shared inbox.
    static func signature(_ e: Envelope, name: String, token: String) -> String {
        SHA256.hash(data: Data((canonical(e, name: name) + "\n" + token).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    enum Refusal: Equatable, Sendable {
        case unknownSender, unknownTarget, selfTarget, missingTask, missingCriteria, missingBranch, badBranch,
             verdictNotAllowed, verdictWithoutBranch, rejectedWithoutFileLine, tooLong
    }

    /// Spec §3.3: a task must carry TASK and CRITERIA; a verdict only from a judging role, on a branch, and a rejection
    /// must point at `file:line`; `done`/`conflict` name their branch. nil = accepted.
    static func validate(_ e: Envelope, senderDomain: Domain?, roles: [String]) -> Refusal? {
        guard senderDomain != nil, roles.contains(e.from) else { return .unknownSender }
        guard e.to == "all" || roles.contains(e.to) else { return .unknownTarget }
        guard e.to != e.from else { return .selfTarget }
        for v in [e.text, e.task, e.criteria, e.tests] where (v?.count ?? 0) > maxField { return .tooLong }
        if let b = e.branch, !isValidBranch(b) { return .badBranch }
        switch e.kind {
        case .task:
            guard let t = e.task, !t.trimmingCharacters(in: .whitespaces).isEmpty else { return .missingTask }
            guard let c = e.criteria, !c.trimmingCharacters(in: .whitespaces).isEmpty else { return .missingCriteria }
        case .done, .conflict:
            guard e.branch != nil else { return .missingBranch }
        case .verdict:
            guard senderDomain?.mayJudge == true else { return .verdictNotAllowed }
            guard e.branch != nil else { return .verdictWithoutBranch }
            if e.verdict == .rejected, !mentionsFileLine(e.text) { return .rejectedWithoutFileLine }
            if e.verdict == nil { return .verdictNotAllowed }
        case .status, .question:
            break
        }
        return nil
    }

    /// "Path.swift:42" somewhere in the note — a rejection has to point at the code (Notch Crew's reviewers do the same;
    /// the rule here is XFinder's own).
    static func mentionsFileLine(_ s: String) -> Bool {
        s.range(of: #"[\w./-]+\.\w+:\d+"#, options: .regularExpression) != nil
    }

    /// Exactly the owner's wire format — what the recipient reads and what the board shows:
    /// `[TIMESTAMP] [FROM: role] -> [TO: role]` then `TASK: … | CRITERIA: … | BRANCH: …` (other kinds name themselves).
    static func render(_ e: Envelope, timeZone: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = timeZone
        let head = "[\(f.string(from: e.at))] [FROM: \(e.from)] -> [TO: \(e.to)]"
        var parts: [String] = []
        switch e.kind {
        case .task:
            parts.append("TASK: \(e.task ?? "")"); parts.append("CRITERIA: \(e.criteria ?? "")")
        case .done:
            parts.append("DONE: \(e.tests ?? e.text)")
        case .verdict:
            parts.append("VERDICT: \(e.verdict?.rawValue ?? "")")
        case .conflict:
            parts.append("CONFLICT: \(e.text)")
        case .status:
            parts.append("STATUS: \(e.text)")
        case .question:
            parts.append("QUESTION: \(e.text)")
        }
        if let b = e.branch { parts.append("BRANCH: \(b)") }
        if e.kind != .status, e.kind != .question, e.kind != .conflict, !e.text.isEmpty, e.kind != .done || e.tests != nil {
            parts.append("NOTE: \(e.text)")
        }
        return head + "\n" + parts.joined(separator: " | ")
    }

    // MARK: - The Approved → merge gate (spec §3.5)

    enum BranchState: Equatable, Sendable {
        case building
        /// `done` received; verdicts collected so far.
        case awaitingVerdicts(security: Verdict?, reviewer: Verdict?)
        case mergeable
        case rejected(by: String, note: String)
        case merged
    }

    enum GateEvent: Equatable, Sendable {
        case nowAwaiting(String), nowMergeable(String), nowRejected(String, by: String), nowMerged(String), ignored(String)
    }

    struct Gate: Equatable, Sendable {
        private(set) var branches: [String: BranchState] = [:]

        func state(of branch: String) -> BranchState { branches[branch] ?? .building }
        func isMergeable(_ branch: String) -> Bool { state(of: branch) == .mergeable }

        /// Feed an ACCEPTED envelope (after `validate`). Only `done` and `verdict` move a branch.
        mutating func apply(_ e: Envelope, senderDomain: Domain) -> GateEvent? {
            guard let b = e.branch else { return nil }
            switch e.kind {
            case .done:
                guard senderDomain.editsCode else { return .ignored(b) }
                if case .merged = state(of: b) { return .ignored(b) }
                // A new `done` means the code moved: every earlier verdict is void (spec §3.5).
                branches[b] = .awaitingVerdicts(security: nil, reviewer: nil)
                return .nowAwaiting(b)
            case .verdict:
                guard let v = e.verdict, senderDomain.mayJudge else { return .ignored(b) }
                guard case .awaitingVerdicts(var sec, var rev) = state(of: b) else { return .ignored(b) }  // before `done`, or already decided
                if v == .rejected {
                    branches[b] = .rejected(by: e.from, note: e.text)
                    return .nowRejected(b, by: e.from)
                }
                if senderDomain == .security { sec = .approved } else { rev = .approved }
                if sec == .approved, rev == .approved {
                    branches[b] = .mergeable
                    return .nowMergeable(b)
                }
                branches[b] = .awaitingVerdicts(security: sec, reviewer: rev)
                return nil
            default:
                return nil
            }
        }

        /// The lead asks to merge: allowed only from `.mergeable`. The merge itself is a git command the lead runs — it
        /// still goes through the permission hook, so the person sees the card.
        mutating func requestMerge(_ branch: String, senderDomain: Domain) -> Bool {
            guard senderDomain == .lead, isMergeable(branch) else { return false }
            branches[branch] = .merged
            return true
        }

        /// A rejected branch goes back to building when the builder starts again (any `status` from it, or the next `done`).
        mutating func builderResumed(_ branch: String) {
            if case .rejected = state(of: branch) { branches[branch] = .building }
        }
    }

    // MARK: - Commands that must always ask (spec §3.4)

    enum StateChanging {
        enum Class: Equatable, Sendable {
            case stateChanging(String)      // the matched command, e.g. "git push"
            case ordinary
        }

        /// Git subcommands that rewrite history or the shared tree.
        static let gitSubcommands: Set<String> = ["commit", "push", "merge", "rebase", "cherry-pick", "revert", "am", "apply"]
        /// `git <sub> <flag>` pairs that destroy work.
        static let gitDestructive: [(String, String)] = [("reset", "--hard"), ("checkout", "--"), ("clean", "-f"), ("clean", "-fd"),
                                                         ("clean", "-fdx"), ("branch", "-D"), ("worktree", "remove"), ("stash", "drop"),
                                                         ("push", "--force"), ("push", "-f")]
        static let gitWholeSubcommands: Set<String> = ["restore", "switch"]
        /// Package managers: installs/adds/publishes.
        static let packageManagers: [String: Set<String>] = [
            "npm": ["install", "i", "add", "ci", "publish", "uninstall", "update", "link"],
            "pnpm": ["install", "i", "add", "publish", "remove", "update"],
            "yarn": ["install", "add", "publish", "remove", "upgrade"],
            "bun": ["install", "i", "add", "publish", "remove"],
            "pip": ["install", "uninstall"], "pip3": ["install", "uninstall"],
            "brew": ["install", "uninstall", "upgrade", "reinstall"],
            "gem": ["install"], "cargo": ["install", "publish"], "swift": ["package"],
        ]
        /// Whole commands that change the machine or the repo however they are spelled.
        static let alwaysAsk: Set<String> = ["sudo", "launchctl", "chmod", "chown", "rm", "mv", "defaults", "killall", "pkill",
                                             "kill", "xcodebuild", "make", "deploy", "systemctl", "diskutil", "tccutil"]

        /// Split a shell line into simple commands: `&&`, `||`, `;`, `|`, newlines and `$(`…`)` / backticks all start a new
        /// one. Quoting is honoured well enough for the commands Claude writes; this is not a shell parser.
        static func simpleCommands(_ line: String) -> [String] {
            var out: [String] = [], cur = ""
            var quote: Character? = nil
            let chars = Array(line)
            var i = 0
            func flush() { let t = cur.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { out.append(t) }; cur = "" }
            while i < chars.count {
                let c = chars[i]
                if let q = quote {
                    if c == q { quote = nil } else { cur.append(c) }
                } else if c == "\"" || c == "'" {
                    quote = c
                } else if c == "`" || c == "\n" || c == ";" {
                    flush()
                } else if c == "&" && i + 1 < chars.count && chars[i + 1] == "&" { flush(); i += 1 }
                else if c == "|" { flush(); if i + 1 < chars.count && chars[i + 1] == "|" { i += 1 } }
                else if c == "$" && i + 1 < chars.count && chars[i + 1] == "(" { flush(); i += 1 }
                else if c == ")" { flush() }
                else { cur.append(c) }
                i += 1
            }
            flush()
            return out
        }

        /// Words of one simple command with leading `VAR=value` assignments and a leading `sudo`/`env`/`nohup`/`time`
        /// dropped (sudo itself is reported before that).
        static func words(_ cmd: String) -> [String] {
            var w = cmd.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            while let f = w.first, f.contains("="), !f.hasPrefix("-"), f.first?.isLetter == true { w.removeFirst() }
            if let f = w.first, let slash = f.lastIndex(of: "/"), !f.hasPrefix("./") { w[0] = String(f[f.index(after: slash)...]) }
            return w
        }

        /// The verdict for one shell line: the FIRST simple command that changes state, or `.ordinary`.
        static func classify(command: String) -> Class {
            for simple in simpleCommands(command) {
                var w = words(simple)
                // `env NODE_ENV=test npm i`: wrappers and VAR=value assignments alternate — strip both until a command is left.
                while let f = w.first, ["env", "nohup", "time", "command", "exec"].contains(f)
                        || (f.contains("=") && !f.hasPrefix("-") && f.first?.isLetter == true) { w.removeFirst() }
                guard let head = w.first else { continue }
                if alwaysAsk.contains(head) || head.hasSuffix("deploy.sh") || head.contains("deploy") { return .stateChanging(head) }
                if head == "git" {
                    // skip `-C <dir>`, `-c k=v`, `--git-dir=…`, `--work-tree=…`, `--no-pager`
                    var i = 1
                    while i < w.count, w[i].hasPrefix("-") {
                        if w[i] == "-C" || w[i] == "-c" { i += 2 } else { i += 1 }
                    }
                    guard i < w.count else { continue }
                    let sub = w[i]
                    if gitSubcommands.contains(sub) || gitWholeSubcommands.contains(sub) { return .stateChanging("git \(sub)") }
                    let rest = Set(w.dropFirst(i + 1))
                    for (s, flag) in gitDestructive where s == sub && rest.contains(flag) { return .stateChanging("git \(sub) \(flag)") }
                    continue
                }
                if let subs = packageManagers[head], w.count > 1, subs.contains(w[1]) { return .stateChanging("\(head) \(w[1])") }
            }
            return .ordinary
        }

        /// Edit/Write fence: is `file` inside `root`? Both are resolved lexically (`..` collapsed); a symlink escape needs
        /// the live check the controller does with `realpath`.
        static func pathInside(root: String, file: String) -> Bool {
            func norm(_ p: String) -> [String] {
                var out: [String] = []
                for part in p.split(separator: "/", omittingEmptySubsequences: true) {
                    if part == "." { continue }
                    if part == ".." { _ = out.popLast(); continue }
                    out.append(String(part))
                }
                return out
            }
            guard file.hasPrefix("/"), root.hasPrefix("/") else { return false }
            let r = norm(root), f = norm(file)
            return f.count >= r.count && Array(f.prefix(r.count)) == r
        }
    }
}
