import AppKit
import Foundation
import os

/// P9 — the live half of a handoff: read the old session (its transcript file, or OpenCode's own CLI) and the folder's
/// git state off the main thread, then start the chosen agent with the message the person has read and maybe edited.
/// The rules and the message text are `AgentHandoff` (pure, tested).
@MainActor
final class AgentHandoffRunner {
    static let shared = AgentHandoffRunner()
    private init() {}
    private let log = Logger(subsystem: "com.xfinder.app", category: "Handoff")

    struct Draft: Equatable {
        var source: AgentKind
        var target: AgentKind
        var folder: String?
        var text: String
        var turnCount: Int
    }

    enum Outcome: Equatable {
        case started            // a windowless Claude Code session / a new OpenCode session took the message
        case copiedCommand      // Codex: the command is on the clipboard
        case failed(String)     // a store key
    }

    /// Read the session and build the message. Never sends anything.
    func prepare(_ session: AgentSession, target: AgentKind) async -> Draft {
        let source = session.agent
        let folder = session.cwd
        let transcript = session.transcriptPath
        let sessionID = session.id
        let openCodeBinary = source == .opencode ? OpenCodeMonitor.findBinary() : nil
        let state = AgentHandoff.sourceState(of: session)
        let transcriptPath = session.transcriptPath
        let english = L10n.isEnglish
        return await Task.detached(priority: .userInitiated) {
            var turns: [AgentHandoff.Turn] = []
            var files: [String] = []
            switch source {
            case .claude, .codex:
                if let path = transcript, let text = Self.readTail(path, maxBytes: 8 << 20) {
                    turns = source == .claude ? AgentHandoff.claudeTurns(jsonl: text) : AgentHandoff.codexTurns(jsonl: text)
                    if source == .claude { files = AgentHandoff.claudeFilesTouched(jsonl: text) }
                }
            case .opencode:
                if let bin = openCodeBinary, OpenCodeRules.isSessionID(sessionID),
                   let data = Self.run(bin, ["api", "session.message.list", "--param", "sessionID=\(sessionID)", "--param", "limit=100"], cwd: nil) {
                    turns = AgentHandoff.openCodeTurns(json: data)
                }
            }
            var git: AgentHandoff.GitState?
            if let folder, FileManager.default.fileExists(atPath: folder),
               let status = Self.run("/usr/bin/git", AgentHandoff.gitStatusArguments(), cwd: folder).flatMap({ String(data: $0, encoding: .utf8) }) {
                let parsed = AgentHandoff.parseGitStatus(status)
                let commits = Self.run("/usr/bin/git", AgentHandoff.gitLogArguments(), cwd: folder)
                    .flatMap { String(data: $0, encoding: .utf8) }?
                    .split(separator: "\n").map(String.init) ?? []
                git = AgentHandoff.GitState(branch: parsed.branch, changed: parsed.changed, commits: commits)
            }
            let text = AgentHandoff.compose(source: source, folder: folder, turns: turns, files: files, git: git,
                                            state: state, transcriptPath: transcriptPath, english: english)
            return Draft(source: source, target: target, folder: folder, text: text, turnCount: turns.count)
        }.value
    }

    /// Start the target with the (possibly edited) message. Spends one model turn on the target agent.
    ///
    /// XF-T29: handoff (to any target) is its own Pro gate — a session already talking keeps talking, only a NEW
    /// handoff send is blocked.
    func send(_ draft: Draft) async -> Outcome {
        guard LicenseManager.shared.allows(.agentHandoff) else { return .failed("Cần XFinder Pro") }
        guard let message = WindowlessRules.cleanMessage(draft.text) else { return .failed("Tin chuyển giao đang trống.") }
        switch draft.target {
        case .claude:
            guard let folder = draft.folder, !folder.isEmpty else { return .failed("Phiên gốc không ghi thư mục.") }
            do {
                _ = try await WindowlessSessionManager.shared.startClaude(folder: URL(fileURLWithPath: folder, isDirectory: true),
                                                                        firstMessage: message, gated: false)
                log.info("handoff \(draft.source.rawValue, privacy: .public) -> claude started")
                return .started
            } catch let e as WindowlessSessionManager.StartError {
                return .failed(e.key)
            } catch {
                return .failed("Không chạy được claude.")
            }
        case .opencode:
            guard let folder = draft.folder, !folder.isEmpty else { return .failed("Phiên gốc không ghi thư mục.") }
            guard let bin = OpenCodeMonitor.findBinary() else { return .failed("Đã bật OpenCode nhưng không tìm thấy lệnh opencode.") }
            let title = "Handoff from \(draft.source.displayName)"
            let created: String? = await Task.detached {
                guard let data = Self.run(bin, ["api", "session.create", "-d", AgentHandoff.openCodeCreateBody(folder: folder, title: title)], cwd: nil),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let info = root["data"] as? [String: Any], let id = info["id"] as? String else { return nil }
                return id
            }.value
            guard let id = created, let args = AgentTalk.opencodePromptArguments(sessionID: id, text: message, queue: false) else {
                return .failed("OpenCode không tạo được phiên mới.")
            }
            let ok = await Task.detached { Self.run(bin, args, cwd: nil) != nil }.value
            log.info("handoff \(draft.source.rawValue, privacy: .public) -> opencode \(ok ? "sent" : "failed", privacy: .public)")
            return ok ? .started : .failed("OpenCode không nhận tin chuyển giao.")
        case .codex:
            // P11: a windowless Codex session (codex app-server) — was a command on the clipboard before.
            guard let folder = draft.folder, !folder.isEmpty else { return .failed("Phiên gốc không ghi thư mục.") }
            do {
                _ = try await WindowlessSessionManager.shared.startCodex(folder: URL(fileURLWithPath: folder, isDirectory: true),
                                                                       firstMessage: message, gated: false)
                log.info("handoff \(draft.source.rawValue, privacy: .public) -> codex started")
                return .started
            } catch let e as WindowlessSessionManager.StartError {
                return .failed(e.key)
            } catch {
                return .failed("Không tìm thấy lệnh codex.")
            }
        }
    }

    // MARK: - Off-main helpers

    /// The last `maxBytes` of a file (a transcript can be hundreds of MB; the end is what a handoff needs). A cut first
    /// line is dropped so the JSONL readers only see whole lines.
    nonisolated static func readTail(_ path: String, maxBytes: Int) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd(), var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        if start > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
        return text
    }

    /// Run a command with no stdin; stdout is read BEFORE waiting (a full pipe would block the child), 10 s cap.
    /// nil on a non-zero exit (`opencode api` exits 1 on HTTP errors — measured in P6).
    nonisolated static func run(_ executable: String, _ args: [String], cwd: String?) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true) }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return p.terminationStatus == 0 ? data : nil
    }
}
