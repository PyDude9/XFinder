import Foundation

/// XF-T23 Crew v2b (2026-10-18) — the few git calls a crew needs: one worktree and branch per builder, one shared
/// integration worktree for the judges. Process-based and synchronous: callers run it off the main thread.
///
/// Rules every call keeps (each one a measured or documented trap):
/// * `core.hooksPath=/dev/null` — a repository's own hooks never run because XFinder created a worktree; the members' own
///   `git commit` still runs them, and that command asks the person first.
/// * `--no-optional-locks` — a status read must not take the index lock a member's commit may need.
/// * The working directory is set with `currentDirectoryURL`, never `-C <path>`: `Process` decomposes a non-ASCII ARGUMENT to
///   NFD (measured, P6), a directory URL it does not.
/// * stdout and stderr go to temp files, not pipes — two full pipes cannot deadlock a child that fills one of them.
/// * Nothing here deletes work: a worktree with uncommitted files is MOVED aside, never `--force`-removed (see `retire`).
enum CrewGit {
    struct Result: Sendable, Equatable {
        let status: Int32
        let out: String
        let err: String
        var ok: Bool { status == 0 }
    }

    static let gitPath = "/usr/bin/git"

    static func run(_ args: [String], in dir: String, timeout: TimeInterval = 60) -> Result {
        let fm = FileManager.default
        let stem = fm.temporaryDirectory.appendingPathComponent("xf-git-\(UUID().uuidString)")
        let outURL = stem.appendingPathExtension("out"), errURL = stem.appendingPathExtension("err")
        guard fm.createFile(atPath: outURL.path, contents: nil), fm.createFile(atPath: errURL.path, contents: nil),
              let outH = try? FileHandle(forWritingTo: outURL), let errH = try? FileHandle(forWritingTo: errURL) else {
            return Result(status: -1, out: "", err: "no temp file")
        }
        defer { try? outH.close(); try? errH.close(); try? fm.removeItem(at: outURL); try? fm.removeItem(at: errURL) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = ["-c", "core.hooksPath=/dev/null", "--no-optional-locks"] + args
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LC_ALL"] = "en_US.UTF-8"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = outH
        p.standardError = errH
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return Result(status: -1, out: "", err: "\(error)") }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 3)
            return Result(status: -2, out: "", err: "timed out")
        }
        let out = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let err = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        return Result(status: p.terminationStatus, out: out, err: err)
    }

    /// POSIX `realpath`: `/var/x` → `/private/var/x`, the form git prints. Foundation's `resolvingSymlinksInPath` does the
    /// opposite for `/private/var` (it strips the prefix back, measured 2026-10-18), so a prefix comparison against a git path
    /// would silently fail for any folder under /var, /tmp or /etc.
    static func realPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard let r = realpath(path, &buffer) else { return path }
        return String(cString: r)
    }

    // MARK: - Reading

    /// The repository's top folder (symlinks resolved, like `rev-parse` prints it), or nil outside a repository.
    static func repoRoot(of dir: String) -> String? {
        let r = run(["rev-parse", "--show-toplevel"], in: dir)
        let t = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok && !t.isEmpty ? t : nil
    }

    /// The commit worktrees start from; nil for a repository with no commit yet.
    static func headSHA(in repo: String) -> String? {
        let r = run(["rev-parse", "--verify", "--quiet", "HEAD"], in: repo)
        let t = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok && !t.isEmpty ? t : nil
    }

    static func branchExists(_ name: String, in repo: String) -> Bool {
        run(["show-ref", "--verify", "--quiet", "refs/heads/\(name)"], in: repo).ok
    }

    /// True when the worktree has uncommitted or untracked files (or git could not say — treated as dirty: never delete on doubt).
    static func isDirty(_ path: String) -> Bool {
        let r = run(["status", "--porcelain"], in: path)
        return !r.ok || !r.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `dir` relative to `root` ("" when equal or outside) — a crew started in `repo/app` runs in `<worktree>/app`.
    static func relativePath(of dir: String, inside root: String) -> String {
        let d = (dir as NSString).standardizingPath, r = (root as NSString).standardizingPath
        guard d != r, d.hasPrefix(r + "/") else { return "" }
        return String(d.dropFirst(r.count + 1))
    }

    // MARK: - Writing

    /// `git worktree add -b <branch> <path> <base>` — the branch is new; a name that exists is the caller's problem
    /// (`CrewV2.assignBranches` already picked a free family).
    static func addWorktree(repo: String, path: String, branch: String, base: String) -> Result {
        run(["worktree", "add", "-q", "-b", branch, path, base], in: repo)
    }

    /// Without `--force`: git refuses a worktree with uncommitted or untracked files, which is exactly the case that must survive.
    static func removeWorktree(repo: String, path: String) -> Result {
        run(["worktree", "remove", path], in: repo)
    }

    static func moveWorktree(repo: String, from: String, to: String) -> Result {
        run(["worktree", "move", from, to], in: repo)
    }

    static func pruneWorktrees(repo: String) {
        _ = run(["worktree", "prune"], in: repo)
    }

    /// Only for a branch this very start just created and nothing committed to (a start that failed half-way).
    static func deleteBranch(_ name: String, repo: String) -> Result {
        run(["branch", "-D", name], in: repo)
    }

    enum Retired: Equatable, Sendable {
        case removed
        /// There was uncommitted work: the worktree now lives at this path and the branch is untouched.
        case keptAside(String)
        case failed(String)
    }

    /// End of a crew: remove the builder's worktree if it holds nothing but commits; otherwise move it to `keptRoot`.
    /// The BRANCH is never deleted — committed work stays reachable either way.
    static func retire(worktree path: String, repo: String, keptRoot: String, keptName: String) -> Retired {
        guard FileManager.default.fileExists(atPath: path) else { pruneWorktrees(repo: repo); return .removed }
        if !isDirty(path), removeWorktree(repo: repo, path: path).ok { return .removed }
        try? FileManager.default.createDirectory(atPath: keptRoot, withIntermediateDirectories: true)
        var target = (keptRoot as NSString).appendingPathComponent(keptName)
        var n = 2
        while FileManager.default.fileExists(atPath: target) { target = (keptRoot as NSString).appendingPathComponent("\(keptName)-\(n)"); n += 1 }
        let moved = moveWorktree(repo: repo, from: path, to: target)
        return moved.ok ? .keptAside(target) : .failed(moved.err.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
