import Foundation
import os

/// P7b — the live half of "Crew" (rules, measurements and decisions: `CrewRules`). Starts one windowless Claude Code
/// session per role, watches the crew's inbox for `xfinder-crew` requests, and runs the relay: every delivery is one
/// write through `WindowlessSessionManager.deliver` (the single stdin gate), every turn end may carry a reply back.
/// Nothing polls: the inbox is a folder watch, turn ends come from the manager's stream.
///
/// XF-T23 v2b (2026-10-18): a crew whose template `usesV2` (Lead Architect) also gets
/// * a git worktree + branch per builder (`crew/<goal>-<role>`) and one shared integration worktree for the judges — the
///   members' working folders; edits outside a member's own worktree are denied by the PreToolUse guard (`CrewGuard`);
/// * signed envelopes with TASK / CRITERIA / BRANCH, `done`, `verdict`, `conflict`, `merge` — decided by `CrewV2.validate`
///   and the `Gate`: a branch is mergeable only after security AND reviewer approved it after the last `done`;
/// * a stop that never deletes work: branches stay, and a worktree with uncommitted files is moved aside, not removed.
///
/// Lifetime: in memory only. Members die with XFinder (P7a); the crew folder is removed on Stop, and any folder left by a
/// crash is removed at the next launch (`removeStaleFolders`, which retires leftover worktrees first). The board lives in
/// memory (≤ 200 entries); each member's own conversation stays in Claude Code.
@MainActor @Observable
final class CrewManager {
    static let shared = CrewManager()
    @ObservationIgnored private let log = Logger(subsystem: "com.xfinder.app", category: "Crew")

    struct Crew: Identifiable {
        let id: String
        let template: CrewRules.Template
        let folder: String
        let goal: String
        let createdAt: Date
        var relay: CrewRules.Relay
        /// role → session id (lower-case UUID)
        var members: [String: String]
        // v2b — empty for a v1 crew
        var gate = CrewV2.Gate()
        var repo: String?
        /// builder role → its branch
        var branches: [String: String] = [:]
        var integrationBranch: String?
        /// "integration" or a builder role → worktree path
        var worktrees: [String: String] = [:]
        /// Review 2026-10-18: a validly signed envelope copied back into the inbox verified again — remember what was consumed.
        var replay = CrewV2.ReplayGuard()
        var stopped: Bool { relay.stopped }
        var isV2: Bool { template.usesV2 }

        func domain(of role: String) -> CrewV2.Domain? { template.roles.first { $0.name == role }?.domain }

        /// One line per builder branch, in template order: Done · Security · Reviewer · Merged.
        var checklists: [(role: String, branch: String, list: CrewV2.Checklist)] {
            template.roles.compactMap { r in
                guard let b = branches[r.name] else { return nil }
                return (r.name, b, CrewV2.checklist(gate.state(of: b), domainOf: { domain(of: $0) }))
            }
        }
    }

    enum StartError: Error, Equatable {
        case badFolder, noScript, setupFailed, notGit, noCommit, noBranchName, git(String), member(WindowlessSessionManager.StartError)
        case proRequired
        var key: String {
            switch self {
            case .badFolder: return "Thư mục không còn."
            case .noScript, .setupFailed: return "Không tạo được crew."
            case .notGit: return "Mẫu này cần một thư mục là kho git."
            case .noCommit: return "Kho git chưa có commit nào — tạo commit đầu tiên rồi bắt đầu lại."
            case .noBranchName: return "Không đặt được tên nhánh cho crew."
            case .git: return "git không tạo được worktree cho crew."
            case .member(let e): return e.key
            case .proRequired: return "Cần XFinder Pro"
            }
        }
    }

    private(set) var crews: [Crew] = []
    var liveCrews: [Crew] { crews.filter { !$0.stopped } }

    @ObservationIgnored private var tokens: [String: [String: String]] = [:]     // crew id → token → role
    @ObservationIgnored private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var started = false
    /// The notch says "crew paused — waiting for you" (set by `NotchSurfaceController`; kept out of this file).
    @ObservationIgnored var onCapReached: ((String) -> Void)?
    /// Test seams for the e2e harness (no app bundle there). Never set by the app.
    @ObservationIgnored var scriptSourceOverride: URL?
    @ObservationIgnored var guardBinaryOverride: String?

    private init() {}

    // MARK: - Paths

    nonisolated static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/XFinder/Agents/crew", isDirectory: true)
    }
    nonisolated static var binDir: URL { root.appendingPathComponent("bin", isDirectory: true) }
    nonisolated static var keptRoot: URL { root.deletingLastPathComponent().appendingPathComponent("crew-kept", isDirectory: true) }
    nonisolated static func folder(for crewID: String) -> URL { root.appendingPathComponent(crewID, isDirectory: true) }

    /// Once per run: the crew relay listens to the windowless manager, and folders a crashed run left behind go.
    func startIfNeeded() {
        guard !started else { return }
        started = true
        WindowlessSessionManager.shared.crewObserver = { [weak self] signal in self?.handle(signal) }
        Self.removeStaleFolders()
    }

    /// Folders a crashed run left behind. A folder whose `owner.pid` names a process that is still alive belongs to ANOTHER
    /// running XFinder (a Debug build beside the installed one — review 2026-10-18) and is left alone.
    nonisolated static func removeStaleFolders() {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent != "bin" && UUID(uuidString: url.lastPathComponent) != nil {
            if let pid = ownerPID(of: url), pid != getpid(), kill(pid, 0) == 0 { continue }
            _ = removeFolder(url, crewID: url.lastPathComponent)
        }
    }

    nonisolated static func ownerPID(of dir: URL) -> pid_t? {
        guard let s = try? String(contentsOf: dir.appendingPathComponent("owner.pid"), encoding: .utf8) else { return nil }
        return pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Retire the worktrees under `dir/wt` (branches stay, uncommitted work is moved aside), then remove the folder — unless
    /// the repository is not where the crew recorded it or a worktree could not be moved: deleting the folder would delete
    /// that work, so it stays and the caller is told. The step itself lives in `CrewGit.retireCrewFolder` (tested with a moved
    /// repository and a dirty worktree); this reads what the crew recorded.
    nonisolated static func removeFolder(_ dir: URL, crewID: String) -> (kept: [String], failed: [String]) {
        let repo = (try? String(contentsOf: dir.appendingPathComponent("repo.txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let out = CrewGit.retireCrewFolder(dir, crewID: crewID, repo: repo, keptRoot: keptRoot.path)
        return (out.kept, out.failed)
    }

    // MARK: - Start

    /// What a Lead Architect start prepared on disk before any process runs.
    private struct V2Plan {
        var repo: String
        var base: String
        var branches: [String: String]
        var integration: String
        var worktrees: [String: String]          // builder role / "integration" → path
        /// role → the folder the member starts in (the worktree, plus the sub-folder the person chose inside the repo)
        var cwd: [String: URL]
        /// role → XFINDER_CREW_ROOT, the only place that member may edit
        var editRoot: [String: String]
    }

    /// git work for a v2 start. Off the main thread; rolls back whatever it created if one step fails.
    nonisolated private static func prepareWorktrees(template: CrewRules.Template, folder: URL, goal: String, dir: URL) throws -> V2Plan {
        let real = CrewGit.realPath(folder.path)
        guard let repo = CrewGit.repoRoot(of: real) else { throw StartError.notGit }
        guard let base = CrewGit.headSHA(in: repo) else { throw StartError.noCommit }
        let builders = template.roles.filter { $0.domain.editsCode }.map(\.name)
        guard let names = CrewV2.assignBranches(goal: goal, builders: builders, exists: { CrewGit.branchExists($0, in: repo) }) else {
            throw StartError.noBranchName
        }
        let sub = CrewGit.relativePath(of: real, inside: repo)
        var worktrees: [String: String] = [:]
        var createdBranches: [String] = []
        func rollback() {
            for (_, path) in worktrees { _ = CrewGit.removeWorktree(repo: repo, path: path) }
            for b in createdBranches where CrewGit.branchExists(b, in: repo)
                && CrewGit.run(["rev-parse", "--verify", "--quiet", "refs/heads/\(b)"], in: repo).out.trimmingCharacters(in: .whitespacesAndNewlines) == base {
                _ = CrewGit.deleteBranch(b, repo: repo)      // fresh and uncommitted: nothing to keep
            }
            CrewGit.pruneWorktrees(repo: repo)
        }
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("wt"), withIntermediateDirectories: true)
        var wanted: [(key: String, branch: String)] = builders.compactMap { r in names.branches[r].map { (r, $0) } }
        wanted.append(("integration", names.integration))
        for (key, branch) in wanted {
            let path = dir.appendingPathComponent("wt").appendingPathComponent(key).path
            // Measured (review 2026-10-18): `git worktree add -b` creates the branch ref BEFORE it can fail on the path, so the
            // name goes on the rollback list first — rollback deletes it only if it exists and still points at `base`.
            createdBranches.append(branch)
            let r = CrewGit.addWorktree(repo: repo, path: path, branch: branch, base: base)
            guard r.ok else { rollback(); throw StartError.git(r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
            worktrees[key] = path
        }
        var cwd: [String: URL] = [:], editRoot: [String: String] = [:]
        func inWorktree(_ path: String) -> URL {
            let full = sub.isEmpty ? path : (path as NSString).appendingPathComponent(sub)
            return URL(fileURLWithPath: FileManager.default.fileExists(atPath: full) ? full : path)
        }
        for role in template.roles {
            switch role.domain {
            case .lead:
                cwd[role.name] = folder; editRoot[role.name] = repo
            case .security, .reviewer:
                if let p = worktrees["integration"] { cwd[role.name] = inWorktree(p); editRoot[role.name] = p }
            default:
                if let p = worktrees[role.name] { cwd[role.name] = inWorktree(p); editRoot[role.name] = p }
            }
        }
        try? Data((repo + "\n").utf8).write(to: dir.appendingPathComponent("repo.txt"), options: .atomic)
        return V2Plan(repo: repo, base: base, branches: names.branches, integration: names.integration, worktrees: worktrees, cwd: cwd, editRoot: editRoot)
    }

    /// A crew from `template` in `folder`. The lead gets `goal` as its first message (one model turn); the others start
    /// with no message and spend nothing until a crewmate writes to them.
    @discardableResult
    func start(template: CrewRules.Template, folder: URL, goal: String) async throws -> String {
        startIfNeeded()
        // XF-T29: a crew (Lead Architect or not) is a Pro feature — a session already running keeps running, this only
        // gates a NEW start.
        guard LicenseManager.shared.allows(.agentCrews) else { throw StartError.proRequired }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { throw StartError.badFolder }
        guard let goalText = WindowlessRules.cleanMessage(goal) else { throw StartError.setupFailed }
        let crewID = UUID().uuidString.lowercased()
        let dir = Self.folder(for: crewID)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir.appendingPathComponent("inbox", isDirectory: true), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try Data("\(getpid())\n".utf8).write(to: dir.appendingPathComponent("owner.pid"), options: .atomic)
            try installScript()
        } catch is StartError {
            try? fm.removeItem(at: dir); throw StartError.noScript
        } catch {
            try? fm.removeItem(at: dir); throw StartError.setupFailed
        }

        // v2: worktrees first (git, off the main thread). v1 crews all work in `folder`.
        var plan: V2Plan?
        if template.usesV2 {
            do {
                plan = try await Task.detached(priority: .userInitiated) {
                    try Self.prepareWorktrees(template: template, folder: folder, goal: goalText, dir: dir)
                }.value
            } catch {
                try? fm.removeItem(at: dir)
                throw (error as? StartError) ?? StartError.setupFailed
            }
        }
        func undoStart(_ startedMembers: [String]) {
            for sid in startedMembers { WindowlessSessionManager.shared.stop(sid) }
            let pids = startedMembers.compactMap { WindowlessSessionManager.shared.records[$0]?.pid }
            if let plan {
                let repo = plan.repo, base = plan.base, branches = Array(plan.branches.values) + [plan.integration], paths = Array(plan.worktrees.values)
                Task.detached {
                    // Review 2026-10-18: let the members that did start exit before their worktrees go (≤ 1.5 s, like quit).
                    var live = pids
                    let deadline = Date().addingTimeInterval(1.5)
                    while !live.isEmpty, Date() < deadline { live.removeAll { kill($0, 0) != 0 }; if !live.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) } }
                    for p in paths { _ = CrewGit.removeWorktree(repo: repo, path: p) }
                    for b in branches where CrewGit.run(["rev-parse", b], in: repo).out.trimmingCharacters(in: .whitespacesAndNewlines) == base {
                        _ = CrewGit.deleteBranch(b, repo: repo)
                    }
                    CrewGit.pruneWorktrees(repo: repo)
                    try? FileManager.default.removeItem(at: dir)
                }
            } else {
                try? fm.removeItem(at: dir)
            }
        }

        do {
            func branchNote(_ r: CrewRules.Role) -> String {
                guard let plan else { return "" }
                switch r.domain {
                case .security, .reviewer: return " (branch: \(plan.integration))"
                case .lead: return ""
                default: return plan.branches[r.name].map { " (branch: \($0))" } ?? ""
                }
            }
            let roster = template.roles.map { "\($0.name) — \($0.purpose)\(branchNote($0))" }.joined(separator: "\n") + "\n"
            try Data(roster.utf8).write(to: dir.appendingPathComponent("roster.txt"), options: .atomic)
            if template.usesV2 { fm.createFile(atPath: dir.appendingPathComponent("v2").path, contents: Data()) }
        } catch {
            undoStart([]); throw StartError.setupFailed
        }

        // v2 members' --settings: `permissions.ask` for state-changing commands + the PreToolUse guard hook.
        var settingsPath: String?
        if template.usesV2 {
            let binary = guardBinaryOverride ?? Bundle.main.executablePath
            let data = CrewV2.settingsJSON(guardCommand: binary.map { CrewGuard.guardCommand(binary: $0) })
            let url = dir.appendingPathComponent("settings.json")
            do {
                try data.write(to: url, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                settingsPath = url.path
            } catch { undoStart([]); throw StartError.setupFailed }
        }

        var roleTokens: [String: String] = [:]
        var members: [String: String] = [:]
        let lead = template.lead.name
        for role in template.roles {
            let token = UUID().uuidString
            roleTokens[token] = role.name
            var env = ["XFINDER_CREW_DIR": dir.path, "XFINDER_CREW_TOKEN": token, "XFINDER_CREW_ROLE": role.name]
            var memberBranch: String?
            if let plan {
                if let root = plan.editRoot[role.name] { env["XFINDER_CREW_ROOT"] = root }
                memberBranch = role.domain.mayJudge ? plan.integration : plan.branches[role.name]
                if let b = memberBranch { env["XFINDER_CREW_BRANCH"] = b }
            }
            do {
                // Already gated above by `.agentCrews` — a crew member's own windowless session is not a second, separate
                // "Bắt đầu phiên" action.
                let sid = try await WindowlessSessionManager.shared.startClaude(
                    folder: plan?.cwd[role.name] ?? folder, firstMessage: nil,
                    extraArguments: CrewRules.launchArguments(for: role, in: template, settingsPath: settingsPath, branch: memberBranch),
                    extraEnvironment: env, pathPrepend: Self.binDir.path, gated: false)
                members[role.name] = sid
            } catch let e as WindowlessSessionManager.StartError {
                undoStart(Array(members.values))
                throw StartError.member(e)
            }
        }
        tokens[crewID] = roleTokens
        var crew = Crew(id: crewID, template: template, folder: folder.path, goal: goalText, createdAt: Date(),
                        relay: CrewRules.Relay(roles: template.roles.map(\.name), busy: [lead], cap: template.relayCap, capStep: template.relayCapStep), members: members)
        if let plan {
            crew.repo = plan.repo
            crew.branches = plan.branches
            crew.integrationBranch = plan.integration
            crew.worktrees = plan.worktrees
        }
        crews.insert(crew, at: 0)
        watchInbox(crewID)
        // P7b review: the goal goes to the lead only once the crew is registered and its inbox watched — a lead turn
        // that ended before that would have reached no relay and left the lead marked busy forever.
        guard let leadSID = members[lead],
              WindowlessSessionManager.shared.deliver(goalText, to: leadSID) == .sent else {
            stop(crewID)
            forget(crewID)
            throw StartError.setupFailed
        }
        log.info("crew started template=\(template.rawValue) members=\(members.count)")
        return crewID
    }

    /// The bundled CLI, copied next to the crews (0700) — a member's PATH starts with that folder. Rewritten when the
    /// bundled copy changed (an installed copy never followed the app, P6 lesson).
    private func installScript() throws {
        guard let src = scriptSourceOverride ?? Bundle.main.url(forResource: "xfinder-crew", withExtension: "zsh") else { throw StartError.noScript }
        let fm = FileManager.default
        try fm.createDirectory(at: Self.binDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let dest = Self.binDir.appendingPathComponent("xfinder-crew")
        let data = try Data(contentsOf: src)
        if (try? Data(contentsOf: dest)) != data { try data.write(to: dest, options: .atomic) }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dest.path)
    }

    // MARK: - Inbox

    private func watchInbox(_ crewID: String) {
        let inbox = Self.folder(for: crewID).appendingPathComponent("inbox", isDirectory: true)
        let fd = open(inbox.path, O_EVTONLY)
        guard fd >= 0 else { log.error("inbox watch failed"); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readInbox(crewID) } }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers[crewID] = src
        readInbox(crewID)
    }

    private func readInbox(_ crewID: String) {
        guard let i = crews.firstIndex(where: { $0.id == crewID }), let roleTokens = tokens[crewID] else { return }
        let inbox = Self.folder(for: crewID).appendingPathComponent("inbox", isDirectory: true)
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return }
        var effects: [CrewRules.Effect] = []
        for f in files {
            let data = (try? Data(contentsOf: f)) ?? Data()
            try? fm.removeItem(at: f)
            guard data.count <= 64 * 1024 else { log.info("crew inbox: an oversize request was refused"); continue }
            if crews[i].isV2 {
                guard let env = CrewV2.parseEnvelope(data, name: f.lastPathComponent, tokens: roleTokens) else {
                    log.info("crew inbox: a request was refused (signature or shape)")
                    continue
                }
                if let mac = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["mac"] as? String, !crews[i].replay.admit(mac) {
                    log.info("crew inbox: a replayed envelope was dropped")
                    continue
                }
                effects += receiveV2(env, crewIndex: i)
                continue
            }
            guard let req = CrewRules.parseRequest(data, name: f.lastPathComponent, tokens: roleTokens,
                                                    roles: crews[i].relay.roles) else {
                log.info("crew inbox: a request was refused")
                continue
            }
            effects += crews[i].relay.receive(req, at: Date())
        }
        run(effects, crewID: crewID)
    }

    // MARK: - v2: what a signed envelope does (spec §3.3, §3.5)

    /// The board line and the free text a v2 message carries.
    nonisolated static func boardText(_ e: CrewV2.Envelope) -> String {
        switch e.kind {
        case .task: return [e.task, e.criteria.map { "CRITERIA: \($0)" }].compactMap { $0 }.joined(separator: " | ")
        case .done: return [e.branch, e.tests].compactMap { $0 }.joined(separator: " — ")
        case .verdict: return [e.verdict?.rawValue, e.branch, e.text.isEmpty ? nil : e.text].compactMap { $0 }.joined(separator: " — ")
        case .merge: return e.branch ?? ""
        default: return e.text
        }
    }

    private func receiveV2(_ e: CrewV2.Envelope, crewIndex i: Int) -> [CrewRules.Effect] {
        let now = Date()
        let roles = crews[i].relay.roles
        let senderDomain = crews[i].domain(of: e.from)
        func refuse(_ r: CrewV2.Refusal) -> [CrewRules.Effect] {
            crews[i].relay.notify(e.from, text: CrewV2.refusalMessage(r), kind: .refused, at: now)
        }
        if let r = CrewV2.validate(e, senderDomain: senderDomain, roles: roles) { return refuse(r) }
        guard let sd = senderDomain else { return refuse(.unknownSender) }
        let targets = e.to == "all" ? roles.filter { $0 != e.from } : [e.to]
        // The lead hands a builder work with TASK + CRITERIA; a plain question or status to a builder is refused.
        for t in targets {
            if let td = crews[i].domain(of: t), CrewV2.requiresTask(from: sd, to: td, kind: e.kind) { return refuse(.missingTask) }
        }
        // Branch ownership — the manager owns the list, `validate` only checks the shape.
        let builderBranches = Set(crews[i].branches.values)
        if let b = e.branch {
            switch e.kind {
            case .done:
                if crews[i].branches[e.from] != b { return refuse(.notYourBranch) }
            case .verdict, .conflict, .merge:
                if !builderBranches.contains(b) { return refuse(.unknownBranch) }
            case .task:
                if targets.count == 1, let own = crews[i].branches[targets[0]], own != b { return refuse(.notYourBranch) }
            default: break
            }
        }
        var env = e
        if e.kind == .task, targets.count == 1, env.branch == nil { env.branch = crews[i].branches[targets[0]] }
        // Review 2026-10-18: a rejection stays on the board until the builder's NEXT `done` (Gate.apply resets it then);
        // a status line or question from the builder no longer wipes the rejected mark and its file:line.
        let rendered = CrewV2.render(env)
        let text = Self.boardText(env)
        var effects: [CrewRules.Effect] = []
        func send(_ from: String, _ to: [String], _ body: String, rendered r: String? = nil, kind: CrewRules.BoardEntry.Kind, reply: Bool) {
            effects += crews[i].relay.receive(CrewRules.Request(from: from, to: to, text: body), at: now, rendered: r, kind: kind, expectsReply: reply)
        }
        let lead = crews[i].template.lead.name
        switch e.kind {
        case .task:
            send(e.from, targets, text, rendered: rendered, kind: .message, reply: true)
        case .question:
            send(e.from, targets, text, rendered: rendered, kind: .message, reply: true)
        case .status:
            send(e.from, targets, text, rendered: rendered, kind: .message, reply: false)
        case .conflict:
            send(e.from, [lead], text, rendered: rendered, kind: .conflict, reply: false)
        case .done:
            let event = crews[i].gate.apply(env, senderDomain: sd)
            if case .ignored(let b)? = event {
                effects += crews[i].relay.notify(e.from, text: "IGNORED: branch \(b) is already merged; a done for it changes nothing. Start a new branch for new work.",
                                                 kind: .refused, at: now)
                break
            }
            send(e.from, [lead], text, rendered: rendered, kind: .done, reply: false)
            if case .nowAwaiting(let b, let round)? = event {
                let judges = crews[i].template.roles.filter { $0.domain.mayJudge }.map(\.name)
                let request = "JUDGE REQUEST for branch \(b), review round \(round) (builder: \(e.from)). Tests the builder ran: \(e.tests ?? "none stated"). "
                    + "Branches live in the shared repository, so git diff / log / show on that branch work from your worktree. "
                    + "Security: audit the diff for vulnerabilities by reading it. Reviewer: merge the branch into your integration worktree "
                    + "(git merge --no-ff \(b)), run the whole test suite, and read the diff for correctness. "
                    + "Answer only with: xfinder-crew verdict approved|rejected --branch \(b) --round \(round) --note \"file:line and why\". "
                    + "If a newer JUDGE REQUEST for this branch arrives before you answer, judge that one instead: the code moved."
                if !judges.isEmpty { send(e.from, judges, "judge \(b) round \(round)", rendered: request, kind: .message, reply: false) }
            }
        case .verdict:
            let event = crews[i].gate.apply(env, senderDomain: sd)
            send(e.from, [lead], text, rendered: rendered, kind: .verdict, reply: false)
            switch event {
            case .nowRejected(let b, _)?:
                if let owner = crews[i].branches.first(where: { $0.value == b })?.key {
                    send(e.from, [owner], text, rendered: rendered, kind: .verdict, reply: false)
                }
            case .nowMergeable(let b)?:
                effects += crews[i].relay.notify(lead, text: "Branch \(b) is approved by both security and reviewer. You may now run: xfinder-crew merge --branch \(b)",
                                                 kind: .merge, at: now)
            case .ignored(let b)?:
                effects += crews[i].relay.notify(e.from, text: "IGNORED: branch \(b) has no finished work waiting for a verdict (the builder must report done first, and a newer done voids earlier verdicts).",
                                                 kind: .refused, at: now)
            case .staleRound(let b, let judged, let current)?:
                effects += crews[i].relay.notify(e.from, text: "STALE: your verdict names round \(judged.map(String.init) ?? "none") but branch \(b) is on round \(current) — the builder reported done again after you looked. Review the current code and answer with --round \(current).",
                                                 kind: .refused, at: now)
            default: break
            }
        case .merge:
            let b = e.branch ?? ""
            if crews[i].gate.requestMerge(b, senderDomain: sd) {
                effects += crews[i].relay.notify(lead, text: "OK: branch \(b) may be merged. Run git merge --no-ff \(b) in your own folder; the person approves that command on the notch. After it, tell the builders what landed.",
                                                 kind: .merge, at: now)
            } else {
                effects += crews[i].relay.notify(lead, text: "REFUSED: branch \(b) is not mergeable yet. It needs a done report from its builder and approved verdicts from BOTH security and reviewer, all after the last done.",
                                                 kind: .refused, at: now)
            }
        }
        return effects
    }

    // MARK: - Signals from the windowless manager

    private func handle(_ signal: WindowlessSessionManager.Signal) {
        for i in crews.indices where !crews[i].stopped {
            let id: String
            switch signal {
            case .turnEnded(let sid, _), .processEnded(let sid): id = sid
            }
            guard let role = crews[i].members.first(where: { $0.value == id })?.key else { continue }
            let effects: [CrewRules.Effect]
            switch signal {
            case .turnEnded(_, let result): effects = crews[i].relay.turnEnded(role, result: result, at: Date())
            case .processEnded: effects = crews[i].relay.memberEnded(role, at: Date())
            }
            run(effects, crewID: crews[i].id)
        }
    }

    private func run(_ effects: [CrewRules.Effect], crewID: String) {
        var pending = effects
        while !pending.isEmpty {
            let e = pending.removeFirst()
            guard let i = crews.firstIndex(where: { $0.id == crewID }) else { return }
            switch e {
            case .deliver(let role, let text):
                guard let sid = crews[i].members[role] else { continue }
                switch WindowlessSessionManager.shared.deliver(text, to: sid) {
                case .sent: break
                case .busy: pending += crews[i].relay.deliveryFailed(role, gone: false, at: Date())
                case .gone: pending += crews[i].relay.deliveryFailed(role, gone: true, at: Date())
                }
            case .stopMember(let role):
                if let sid = crews[i].members[role] { WindowlessSessionManager.shared.stop(sid) }
            case .noticeCapReached:
                syncPausedMarker(crewID)
                onCapReached?(crewID)
            }
        }
        syncPausedMarker(crewID)
    }

    /// `paused` exists while the relay is paused, so `xfinder-crew send` can say so.
    private func syncPausedMarker(_ crewID: String) {
        guard let crew = crews.first(where: { $0.id == crewID }) else { return }
        let marker = Self.folder(for: crewID).appendingPathComponent("paused")
        if crew.relay.pause != nil && !crew.stopped {
            FileManager.default.createFile(atPath: marker.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    // MARK: - The person's controls

    func pause(_ crewID: String) {
        guard let i = crews.firstIndex(where: { $0.id == crewID }) else { return }
        crews[i].relay.pauseByPerson(at: Date())
        syncPausedMarker(crewID)
    }

    func resume(_ crewID: String) {
        guard let i = crews.firstIndex(where: { $0.id == crewID }) else { return }
        run(crews[i].relay.resume(at: Date()), crewID: crewID)
    }

    /// Stop the crew: every member's process, the relay, the inbox watch, then (v2) the worktrees — branches stay, uncommitted
    /// work is moved aside — and the crew folder.
    func stop(_ crewID: String) {
        guard let i = crews.firstIndex(where: { $0.id == crewID }) else { return }
        let crew = crews[i]
        run(crews[i].relay.stop(at: Date()), crewID: crewID)
        watchers.removeValue(forKey: crewID)?.cancel()
        tokens[crewID] = nil
        guard crew.isV2 else {
            try? FileManager.default.removeItem(at: Self.folder(for: crewID))
            return
        }
        Task { @MainActor [weak self] in
            // Let the members exit before their worktrees go (stop() is SIGINT, then SIGTERM after 3 s).
            for _ in 0..<30 {
                guard let self, let c = self.crews.first(where: { $0.id == crewID }) else { return }
                if c.relay.roles.allSatisfy({ c.relay.ended.contains($0) }) { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            let dir = Self.folder(for: crewID)
            let outcome = await Task.detached(priority: .utility) { Self.removeFolder(dir, crewID: crewID) }.value
            guard let self, let j = self.crews.firstIndex(where: { $0.id == crewID }) else { return }
            var note = ""
            let branches = (Array(crew.branches.values).sorted() + [crew.integrationBranch].compactMap { $0 })
            if !branches.isEmpty { note += L10n.t("Nhánh còn lại: ") + branches.joined(separator: ", ") }
            if !outcome.kept.isEmpty { note += L10n.t(" · Worktree còn thay đổi chưa commit, đã chuyển sang: ") + outcome.kept.joined(separator: ", ") }
            if !outcome.failed.isEmpty { note += L10n.t(" · Không dọn được: ") + outcome.failed.joined(separator: "; ") }
            self.crews[j].relay.annotate(note, at: Date())
        }
    }

    func forget(_ crewID: String) {
        guard let crew = crews.first(where: { $0.id == crewID }), crew.stopped else { return }
        crews.removeAll { $0.id == crewID }
    }

    /// XFinder is quitting: `WindowlessSessionManager.stopAll` has just signalled every member; wait up to 1.5 s for their
    /// processes to exit (a worktree must not be moved under a live member), then retire the folders. A member that is still
    /// alive after that keeps its folder — the next launch's stale sweep retires it once the process is gone.
    func stopAllForQuit() {
        let live = crews.filter { !$0.stopped }
        guard !live.isEmpty else { return }
        var pids: [pid_t] = live.flatMap { c in c.members.values.compactMap { WindowlessSessionManager.shared.records[$0]?.pid } }
        let deadline = Date().addingTimeInterval(1.5)
        while !pids.isEmpty, Date() < deadline {
            pids.removeAll { kill($0, 0) != 0 }
            if !pids.isEmpty { Thread.sleep(forTimeInterval: 0.05) }
        }
        for c in live {
            watchers.removeValue(forKey: c.id)?.cancel()
            let stillAlive = c.members.values.contains { sid in
                guard let pid = WindowlessSessionManager.shared.records[sid]?.pid else { return false }
                return kill(pid, 0) == 0
            }
            if stillAlive { log.info("crew \(c.id, privacy: .public): a member is still running at quit; folder left for the next launch") ; continue }
            _ = Self.removeFolder(Self.folder(for: c.id), crewID: c.id)
        }
    }

    // MARK: - Reading

    /// Which crew (and role) a hosted session belongs to.
    func membership(of sessionID: String) -> (crew: Crew, role: String)? {
        let sid = sessionID.lowercased()
        for c in crews { if let role = c.members.first(where: { $0.value == sid })?.key { return (c, role) } }
        return nil
    }

    /// Claude Code's own estimate summed over the members (not a bill).
    func costUSD(_ crew: Crew) -> Double? {
        let costs = crew.members.values.compactMap { WindowlessSessionManager.shared.records[$0]?.costUSD }
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }
}
