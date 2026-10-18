import XCTest
@testable import XFinderLogicTests

/// XF-T23 v2a — the owner's Lead Architect rules as pure logic. Each test names the failure it pins.
final class CrewGateTests: XCTestCase {
    typealias C = CrewV2
    let roles = ["lead", "frontend", "backend", "security", "reviewer"]
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func env(_ from: String, _ to: String, _ kind: C.Kind, text: String = "", task: String? = nil, criteria: String? = nil,
             branch: String? = nil, verdict: C.Verdict? = nil, tests: String? = nil) -> C.Envelope {
        C.Envelope(from: from, to: to, kind: kind, text: text, task: task, criteria: criteria, branch: branch, verdict: verdict, tests: tests, at: t0)
    }

    // MARK: Names

    func testSlugAndBranchNamesAreGitSafe() {
        XCTAssertEqual(C.slug("Add share links to notes, with tests!"), "add-share-links-to-notes-with-te")
        XCTAssertEqual(C.slug("  Thêm   link  "), "them-link", "v2b: diacritics fold to ASCII (v2a pinned th-m-link, which read as noise in a branch name)")
        XCTAssertEqual(C.branchName(goalSlug: "notes", role: "frontend"), "crew/notes-frontend")
        XCTAssertTrue(C.isValidBranch("crew/notes-frontend"))
        XCTAssertFalse(C.isValidBranch("main")); XCTAssertFalse(C.isValidBranch("crew/-x")); XCTAssertFalse(C.isValidBranch("crew/Notes"))
    }

    // MARK: Signature covers every field

    func testSignatureChangesWhenAnyFieldChanges() {
        let base = env("lead", "frontend", .task, text: "n", task: "t", criteria: "c", branch: "crew/notes-frontend", tests: "x")
        let sig = C.signature(base, name: "001.json", token: "tok")
        var variants = [base, base, base, base, base, base, base, base]
        variants[0].from = "backend"; variants[1].to = "backend"; variants[2].kind = .status; variants[3].text = "m"
        variants[4].task = "t2"; variants[5].criteria = "c2"; variants[6].branch = "crew/notes-backend"; variants[7].tests = "y"
        for (i, v) in variants.enumerated() {
            XCTAssertNotEqual(C.signature(v, name: "001.json", token: "tok"), sig, "field \(i) is not covered by the MAC")
        }
        var verdict = base; verdict.kind = .verdict; verdict.verdict = .approved
        var verdict2 = verdict; verdict2.verdict = .rejected
        XCTAssertNotEqual(C.signature(verdict, name: "001.json", token: "tok"), C.signature(verdict2, name: "001.json", token: "tok"))
        XCTAssertNotEqual(C.signature(base, name: "002.json", token: "tok"), sig, "file name is covered")
        XCTAssertNotEqual(C.signature(base, name: "001.json", token: "other"), sig, "token is covered")
        // Length-prefixed fields: moving a separator between two fields cannot collide.
        var a = base; a.task = "x\ncriteria:1:y"; a.criteria = ""
        var b = base; b.task = "x"; b.criteria = "y"
        XCTAssertNotEqual(C.canonical(a, name: "n"), C.canonical(b, name: "n"))
    }

    // MARK: Validation = the brief's schema

    func testATaskNeedsTaskAndCriteriaAndAVerdictNeedsAJudge() {
        XCTAssertEqual(C.validate(env("lead", "frontend", .task, criteria: "c"), senderDomain: .lead, roles: roles), .missingTask)
        XCTAssertEqual(C.validate(env("lead", "frontend", .task, task: "t"), senderDomain: .lead, roles: roles), .missingCriteria)
        XCTAssertNil(C.validate(env("lead", "frontend", .task, task: "t", criteria: "c", branch: "crew/n-frontend"), senderDomain: .lead, roles: roles))
        XCTAssertEqual(C.validate(env("frontend", "lead", .verdict, branch: "crew/n-frontend", verdict: .approved), senderDomain: .frontend, roles: roles), .verdictNotAllowed, "a builder cannot approve")
        XCTAssertEqual(C.validate(env("security", "lead", .verdict, verdict: .approved), senderDomain: .security, roles: roles), .verdictWithoutBranch)
        XCTAssertEqual(C.validate(env("security", "lead", .verdict, text: "weak token", branch: "crew/n-backend", verdict: .rejected), senderDomain: .security, roles: roles), .rejectedWithoutFileLine)
        XCTAssertNil(C.validate(env("security", "lead", .verdict, text: "api/token.ts:12 uses Math.random", branch: "crew/n-backend", verdict: .rejected), senderDomain: .security, roles: roles))
        XCTAssertEqual(C.validate(env("backend", "lead", .done, tests: "npm test: 9 passed"), senderDomain: .backend, roles: roles), .missingBranch)
        XCTAssertEqual(C.validate(env("ghost", "lead", .status), senderDomain: nil, roles: roles), .unknownSender)
        XCTAssertEqual(C.validate(env("lead", "nobody", .status), senderDomain: .lead, roles: roles), .unknownTarget)
        XCTAssertEqual(C.validate(env("lead", "lead", .status), senderDomain: .lead, roles: roles), .selfTarget)
        XCTAssertEqual(C.validate(env("lead", "all", .task, task: "t", criteria: "c", branch: "Main"), senderDomain: .lead, roles: roles), .badBranch)
        XCTAssertEqual(C.validate(env("lead", "all", .status, text: String(repeating: "x", count: C.maxField + 1)), senderDomain: .lead, roles: roles), .tooLong)
    }

    func testRenderIsTheOwnersWireFormat() {
        let e = env("lead", "frontend", .task, text: "ask before touching schema", task: "Share button, copy link",
                    criteria: "npm test green", branch: "crew/notes-frontend")
        let s = C.render(e, timeZone: TimeZone(secondsFromGMT: 7 * 3600)!)
        // 1_800_000_000 s = 2027-01-15 08:00:00 UTC → 15:00 at +07:00 (the first draft of this line said 15:20 — wrong arithmetic).
        XCTAssertEqual(s, "[2027-01-15T15:00:00+07:00] [FROM: lead] -> [TO: frontend]\nTASK: Share button, copy link | CRITERIA: npm test green | BRANCH: crew/notes-frontend | NOTE: ask before touching schema")
        let v = env("reviewer", "lead", .verdict, text: "all three branches pass npm test", branch: "crew/notes-backend", verdict: .approved)
        XCTAssertTrue(C.render(v, timeZone: .init(secondsFromGMT: 0)!).hasSuffix("VERDICT: approved | BRANCH: crew/notes-backend | NOTE: all three branches pass npm test"))
        let d = env("backend", "lead", .done, branch: "crew/notes-backend", tests: "npm test: 9 passed")
        XCTAssertTrue(C.render(d, timeZone: .init(secondsFromGMT: 0)!).contains("DONE: npm test: 9 passed | BRANCH: crew/notes-backend"))
    }

    // MARK: The gate

    func testMergeableOnlyAfterDoneAndBothApprovals() {
        var g = C.Gate()
        let b = "crew/notes-backend"
        XCTAssertEqual(g.apply(env("security", "lead", .verdict, branch: b, verdict: .approved), senderDomain: .security), .ignored(b), "a verdict before `done` means nothing")
        XCTAssertEqual(g.apply(env("backend", "lead", .done, branch: b, tests: "ok"), senderDomain: .backend), .nowAwaiting(b))
        XCTAssertNil(g.apply(env("security", "lead", .verdict, branch: b, verdict: .approved), senderDomain: .security))
        XCTAssertFalse(g.isMergeable(b), "one approval is not two")
        XCTAssertFalse(g.requestMerge(b, senderDomain: .lead))
        XCTAssertEqual(g.apply(env("reviewer", "lead", .verdict, branch: b, verdict: .approved), senderDomain: .reviewer), .nowMergeable(b))
        XCTAssertTrue(g.isMergeable(b))
        XCTAssertFalse(g.requestMerge(b, senderDomain: .frontend), "only the lead merges")
        XCTAssertTrue(g.requestMerge(b, senderDomain: .lead))
        XCTAssertEqual(g.state(of: b), .merged)
        XCTAssertEqual(g.apply(env("backend", "lead", .done, branch: b), senderDomain: .backend), .ignored(b), "a merged branch is closed")
    }

    func testANewDoneVoidsEarlierVerdictsAndARejectionSendsItBack() {
        var g = C.Gate()
        let b = "crew/notes-frontend"
        _ = g.apply(env("frontend", "lead", .done, branch: b), senderDomain: .frontend)
        _ = g.apply(env("security", "lead", .verdict, branch: b, verdict: .approved), senderDomain: .security)
        _ = g.apply(env("frontend", "lead", .done, branch: b), senderDomain: .frontend)   // code moved
        _ = g.apply(env("reviewer", "lead", .verdict, branch: b, verdict: .approved), senderDomain: .reviewer)
        XCTAssertFalse(g.isMergeable(b), "security's approval was for the OLD code")
        XCTAssertEqual(g.apply(env("security", "lead", .verdict, text: "x.ts:1", branch: b, verdict: .rejected), senderDomain: .security), .nowRejected(b, by: "security"))
        XCTAssertEqual(g.state(of: b), .rejected(by: "security", note: "x.ts:1"))
        XCTAssertNil(g.apply(env("reviewer", "lead", .verdict, branch: b, verdict: .approved), senderDomain: .reviewer).flatMap { $0 == .ignored(b) ? nil : $0 }, "verdicts on a rejected branch are ignored")
        g.builderResumed(b)
        XCTAssertEqual(g.state(of: b), .building)
    }

    /// Every sequence of up to 6 events: `mergeable` is reachable ONLY through done → (approve security, approve reviewer)
    /// with no `done` or `rejected` in between — a reference model says what "should" hold.
    func testExhaustiveWalkNeverReachesMergeableWithoutBothApprovalsAfterTheLastDone() {
        enum Ev: CaseIterable { case done, appSec, appRev, rejSec, rejRev, status }
        let b = "crew/x-backend"
        var walked = 0
        func run(_ seq: [Ev]) {
            var g = C.Gate()
            var doneSeen = false, sec = false, rev = false, rejected = false
            for ev in seq {
                switch ev {
                case .done:
                    _ = g.apply(env("backend", "lead", .done, branch: b), senderDomain: .backend)
                    doneSeen = true; sec = false; rev = false; rejected = false
                case .appSec:
                    _ = g.apply(env("security", "lead", .verdict, branch: b, verdict: .approved), senderDomain: .security)
                    if doneSeen, !rejected { sec = true }
                case .appRev:
                    _ = g.apply(env("reviewer", "lead", .verdict, branch: b, verdict: .approved), senderDomain: .reviewer)
                    if doneSeen, !rejected { rev = true }
                case .rejSec, .rejRev:
                    _ = g.apply(env(ev == .rejSec ? "security" : "reviewer", "lead", .verdict, text: "f.ts:1", branch: b, verdict: .rejected), senderDomain: ev == .rejSec ? .security : .reviewer)
                    if doneSeen, !(sec && rev) { rejected = true }
                case .status:
                    _ = g.apply(env("backend", "lead", .status, text: "working", branch: b), senderDomain: .backend)
                }
                let expected = doneSeen && sec && rev && !rejected
                XCTAssertEqual(g.isMergeable(b), expected, "sequence \(seq) after \(ev)")
            }
            walked += 1
        }
        func walk(_ prefix: [Ev], _ depth: Int) {
            run(prefix)
            guard depth < 6 else { return }
            for e in Ev.allCases { walk(prefix + [e], depth + 1) }
        }
        walk([], 0)
        XCTAssertGreaterThan(walked, 50_000, "the walk must actually walk")
    }

    // MARK: Commands that always ask

    func testStateChangingCommandsAreCaughtHoweverGitIsSpelled() {
        typealias S = C.StateChanging
        let asks = ["git commit -m 'x'", "git push origin main", "git -C . push origin main", "git -c push.default=current push",
                    "git 'push' origin main", "npm test && git push origin main", "cd /tmp; git merge crew/x-frontend",
                    "echo hi | tee log; git rebase main", "npm install left-pad", "pnpm add -D vitest", "yarn add x", "bun install",
                    "pip install requests", "brew install jq", "./scripts/deploy.sh staging", "sudo rm -rf /tmp/x", "rm -rf build",
                    "git reset --hard HEAD~1", "git checkout -- src/a.ts", "git push --force", "git clean -fd", "FOO=1 npm install",
                    "env NODE_ENV=test npm i", "$(git commit -m x)", "defaults write com.x y -bool true", "/usr/bin/git push"]
        for c in asks {
            if case .ordinary = S.classify(command: c) { XCTFail("not caught: \(c)") }
        }
        let fine = ["git status", "git diff", "git log --oneline -5", "git -C . status", "npm test", "npm run test:e2e", "ls -la",
                    "cat package.json", "grep -rn foo src", "git branch --show-current", "echo 'git push' > notes.txt",
                    "npm run build", "swift test", "git fetch origin", "git stash list", "git worktree list"]
        for c in fine {
            XCTAssertEqual(S.classify(command: c), .ordinary, "false alarm: \(c)")
        }
        XCTAssertEqual(S.classify(command: "git -C . push origin main"), .stateChanging("git push"))
        XCTAssertEqual(S.classify(command: "npm ci && npm test"), .stateChanging("npm ci"))
    }

    func testEditFenceIsLexicalAndClosed() {
        typealias S = C.StateChanging
        XCTAssertTrue(S.pathInside(root: "/Users/a/crew/wt/frontend", file: "/Users/a/crew/wt/frontend/src/App.tsx"))
        XCTAssertTrue(S.pathInside(root: "/Users/a/crew/wt/frontend/", file: "/Users/a/crew/wt/frontend/./src/../src/App.tsx"))
        XCTAssertFalse(S.pathInside(root: "/Users/a/crew/wt/frontend", file: "/Users/a/crew/wt/frontend/../backend/x.ts"))
        XCTAssertFalse(S.pathInside(root: "/Users/a/crew/wt/frontend", file: "/Users/a/crew/wt/frontend-2/x.ts"), "a sibling with the same prefix is outside")
        XCTAssertFalse(S.pathInside(root: "/Users/a/crew/wt/frontend", file: "src/App.tsx"), "relative paths are not judged here")
    }
}
