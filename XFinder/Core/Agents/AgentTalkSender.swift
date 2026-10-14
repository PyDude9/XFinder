import AppKit
import Foundation

/// P6 — the live half of "Nhắn phiên" (rules and measurements: `AgentTalk`). Sends one reply the person typed on the
/// notch to the agent session it belongs to, along the route `AgentTalk.route(for:)` picked:
/// * kitty / tmux: the target is checked first (window still runs the agent / pane still has the agent's tty), then the
///   cleaned text is typed and Enter pressed as a SEPARATE keystroke 0.1 s later (a TUI may read text+CR in one chunk as a
///   paste and not submit it);
/// * OpenCode: its own prompt API, `delivery: queue` while the session works;
/// * anything else: the text goes on the clipboard and the terminal app is brought forward.
/// A message for a session that is working waits HERE (one per session — a newer one replaces it) and goes out when the
/// session next waits for the person with no dialog or question on screen; a session that ends drops it and says so.
/// Nothing polls: the outbox is re-checked when the session list changes.
@MainActor
final class AgentTalkSender {
    static let shared = AgentTalkSender()

    /// What the page shows under a session after an attempt. Store keys only (the view wraps them), plus an optional
    /// verbatim detail — a CLI's own error line.
    struct Status: Equatable {
        var key: String
        var detail: String? = nil
        var isError = false
    }

    private(set) var outbox: [String: String] = [:]          // listID → cleaned text waiting for the session
    private(set) var status: [String: Status] = [:]          // listID → last outcome
    private var inFlight: Set<String> = []
    var onChange: (() -> Void)?

    // MARK: - Send

    /// The person pressed send. Returns immediately; the outcome lands in `status`.
    func send(_ raw: String, to session: AgentSession) {
        guard let text = AgentTalk.clean(raw) else { return }
        let route = AgentTalk.route(for: session)
        switch AgentTalk.decision(for: session, route: route) {
        case .blocked(let key):
            setStatus(session, Status(key: key, isError: true))
        case .copyInstead:
            copyAndActivate(text, bundleID: session.terminal.bundleID, session: session, afterDialog: true)
        case .queue:
            let replaced = outbox[session.listID] != nil
            outbox[session.listID] = text
            setStatus(session, Status(key: replaced ? "Đã thay tin đang chờ — sẽ gửi khi phiên rảnh." : "Sẽ gửi khi phiên rảnh."))
        case .sendNow:
            deliver(text, to: session, route: route)
        }
    }

    /// Drop the held message for a session (the person cancelled it).
    func cancelQueued(for session: AgentSession) {
        guard outbox.removeValue(forKey: session.listID) != nil else { return }
        setStatus(session, Status(key: "Đã huỷ tin đang chờ."))
    }

    /// The session list changed: deliver held messages whose session now waits for the person; drop the ones whose session
    /// ended. Called by `AgentSessionMonitor` after every rebuild.
    func sessionsChanged(_ sessions: [AgentSession]) {
        guard !outbox.isEmpty else { return }
        let byID = Dictionary(sessions.map { ($0.listID, $0) }, uniquingKeysWith: { a, _ in a })
        for (listID, text) in outbox {
            guard let s = byID[listID] else {
                // Gone from the list (ended and aged out): nothing to deliver to.
                outbox.removeValue(forKey: listID)
                status[listID] = Status(key: "Phiên đã kết thúc — tin đang chờ chưa được gửi.", isError: true)
                continue
            }
            let route = AgentTalk.route(for: s)
            switch AgentTalk.shouldDeliverQueued(to: s, route: route) {
            case true?:
                outbox.removeValue(forKey: listID)
                deliver(text, to: s, route: route)
            case false?:
                outbox.removeValue(forKey: listID)
                status[listID] = Status(key: "Phiên đã kết thúc — tin đang chờ chưa được gửi.", isError: true)
            case nil:
                continue
            }
        }
        onChange?()
    }

    private func setStatus(_ s: AgentSession, _ st: Status) {
        status[s.listID] = st
        onChange?()
    }

    // MARK: - Delivery

    private func deliver(_ text: String, to session: AgentSession, route: AgentTalk.Route) {
        let listID = session.listID
        guard !inFlight.contains(listID) else { return }
        switch route {
        case .copyAndActivate(let bid):
            copyAndActivate(text, bundleID: bid, session: session, afterDialog: false)
            return
        case .windowless(let id):
            // XFinder owns the process: the write is a pipe write, no command to run. A crew delivery may have taken the
            // turn a moment ago (one gate, P7b): then the reply waits here for the next free moment instead of being lost.
            switch WindowlessSessionManager.shared.deliver(text, to: id) {
            case .sent: setStatus(session, Status(key: "Đã gửi tin."))
            case .busy:
                outbox[session.listID] = text
                setStatus(session, Status(key: "Sẽ gửi khi phiên rảnh."))
            case .gone: setStatus(session, Status(key: "Phiên không cửa sổ đã dừng — tin chưa được gửi.", isError: true))
            }
            return
        case .kitty, .tmux, .opencode:
            break
        }
        inFlight.insert(listID)
        setStatus(session, Status(key: "Đang gửi…"))
        let recordedTTY = session.terminal.tty
        let agentPID = session.agentPID
        let running: Bool = { if case .running = session.status { return true }; return false }()
        let openCodeBinary = OpenCodeMonitor.shared.binaryPath ?? OpenCodeMonitor.findBinary()
        Task.detached(priority: .userInitiated) {
            let result = Self.perform(route: route, text: text, recordedTTY: recordedTTY, agentPID: agentPID,
                                      queueOnServer: running, openCodeBinary: openCodeBinary)
            await MainActor.run {
                let me = AgentTalkSender.shared
                me.inFlight.remove(listID)
                me.status[listID] = result
                me.onChange?()
            }
        }
    }

    private func copyAndActivate(_ text: String, bundleID: String?, session: AgentSession, afterDialog: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        var opened = false
        if let bundleID {
            opened = AgentSessionMonitor.bringForward(bundleID: bundleID)
        }
        if afterDialog {
            setStatus(session, Status(key: "Đã chép — trả lời hộp thoại ở terminal trước, rồi dán (⌘V) và bấm Enter."))
        } else {
            setStatus(session, Status(key: opened ? "Đã chép — dán (⌘V) vào terminal rồi bấm Enter."
                                                  : "Đã chép — mở terminal của phiên, dán (⌘V) rồi bấm Enter."))
        }
    }

    /// Off the main thread. Every command is an argument array — no shell.
    nonisolated static func perform(route: AgentTalk.Route, text: String, recordedTTY: String?, agentPID: Int32?,
                                    queueOnServer: Bool, openCodeBinary: String?) -> Status {
        switch route {
        case .tmux(let socket, let pane):
            guard let tmux = firstExecutable(tmuxCandidates) else {
                return Status(key: "Không tìm thấy lệnh tmux.", isError: true)
            }
            let check = OpenCodeMonitor.run(tmux, AgentTalk.tmuxCheckArguments(socket: socket, pane: pane))
            guard check.status == 0,
                  AgentTalk.tmuxTargetMatches(paneTTY: String(decoding: check.out, as: UTF8.self), recordedTTY: recordedTTY) else {
                return Status(key: "Ô tmux của phiên không còn — không gõ vào đâu cả.", isError: true)
            }
            let buffer = AgentTalk.tmuxBufferName(UUID())
            let loaded = run(tmux, AgentTalk.tmuxLoadArguments(socket: socket, buffer: buffer), stdin: Data(text.utf8))
            guard loaded.status == 0 else { return Status(key: "tmux không nhận chữ.", detail: errorLine(loaded), isError: true) }
            let typed = OpenCodeMonitor.run(tmux, AgentTalk.tmuxPasteArguments(socket: socket, pane: pane, buffer: buffer))
            guard typed.status == 0 else { return Status(key: "tmux không nhận chữ.", detail: errorLine(typed), isError: true) }
            Thread.sleep(forTimeInterval: 0.1)
            // Re-check before Enter (review): if the agent left the pane in the last 0.1 s, a blind Enter would run the
            // typed text as a shell command. The text may be left in the input line — the status says so.
            let recheck = OpenCodeMonitor.run(tmux, AgentTalk.tmuxCheckArguments(socket: socket, pane: pane))
            guard recheck.status == 0,
                  AgentTalk.tmuxTargetMatches(paneTTY: String(decoding: recheck.out, as: UTF8.self), recordedTTY: recordedTTY) else {
                return Status(key: "Ô tmux đã đổi trước khi bấm Enter — chữ có thể còn ở dòng nhập, chưa gửi.", isError: true)
            }
            let enter = OpenCodeMonitor.run(tmux, AgentTalk.tmuxEnterArguments(socket: socket, pane: pane))
            return enter.status == 0 ? Status(key: "Đã gửi vào tmux.")
                                     : Status(key: "tmux không nhận phím Enter.", detail: errorLine(enter), isError: true)
        case .kitty(let socket, let windowID):
            guard let kitty = firstExecutable(kittyCandidates) else {
                return Status(key: "Không tìm thấy lệnh kitty.", isError: true)
            }
            let ls = OpenCodeMonitor.run(kitty, AgentTalk.kittyCheckArguments(socket: socket, windowID: windowID))
            guard ls.status == 0 else {
                return Status(key: "kitty không cho điều khiển từ xa (cần allow_remote_control và listen_on trong kitty.conf).",
                              detail: errorLine(ls), isError: true)
            }
            guard AgentTalk.kittyTargetMatches(lsJSON: ls.out, windowID: windowID, agentPID: agentPID) else {
                return Status(key: "Cửa sổ kitty của phiên không còn chạy agent — không gõ vào đâu cả.", isError: true)
            }
            let typed = run(kitty, AgentTalk.kittyTypeArguments(socket: socket, windowID: windowID), stdin: Data(text.utf8))
            guard typed.status == 0 else { return Status(key: "kitty không nhận chữ.", detail: errorLine(typed), isError: true) }
            Thread.sleep(forTimeInterval: 0.1)
            let recheck = OpenCodeMonitor.run(kitty, AgentTalk.kittyCheckArguments(socket: socket, windowID: windowID))
            guard recheck.status == 0, AgentTalk.kittyTargetMatches(lsJSON: recheck.out, windowID: windowID, agentPID: agentPID) else {
                return Status(key: "Cửa sổ kitty thôi chạy agent trước khi bấm Enter — chữ có thể còn ở dòng nhập, chưa gửi.", isError: true)
            }
            let enter = run(kitty, AgentTalk.kittyEnterArguments(socket: socket, windowID: windowID),
                            stdin: Data(AgentTalk.kittyEnterBytes.utf8))
            return enter.status == 0 ? Status(key: "Đã gửi vào kitty.")
                                     : Status(key: "kitty không nhận phím Enter.", detail: errorLine(enter), isError: true)
        case .opencode(let sessionID):
            guard let bin = openCodeBinary,
                  let args = AgentTalk.opencodePromptArguments(sessionID: sessionID, text: text, queue: queueOnServer) else {
                return Status(key: "Không tìm thấy lệnh opencode.", isError: true)
            }
            let r = OpenCodeMonitor.run(bin, args)
            guard r.status == 0 else { return Status(key: "OpenCode không nhận tin.", detail: errorLine(r), isError: true) }
            return Status(key: queueOnServer ? "OpenCode đã xếp tin vào hàng đợi của phiên." : "Đã gửi qua OpenCode.")
        case .copyAndActivate, .windowless:
            return Status(key: "Đang gửi…")      // handled on the main actor before reaching here
        }
    }

    // MARK: - Process helpers

    nonisolated static let tmuxCandidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
    nonisolated static var kittyCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications/kitty.app/Contents/MacOS/kitty", "\(home)/Applications/kitty.app/Contents/MacOS/kitty",
                "/opt/homebrew/bin/kitty", "/usr/local/bin/kitty"]
    }

    nonisolated static func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func errorLine(_ r: OpenCodeMonitor.RunResult) -> String? {
        let text = String(decoding: r.err.isEmpty ? r.out : r.err, as: UTF8.self)
        return text.split(separator: "\n").first.map { String($0.prefix(160)) }
    }

    /// Like `OpenCodeMonitor.run`, with bytes written to the child's stdin (kitty `send-text --stdin`).
    nonisolated static func run(_ path: String, _ args: [String], stdin input: Data) -> OpenCodeMonitor.RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let inPipe = Pipe(), out = Pipe(), err = Pipe()
        p.standardInput = inPipe
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return .init(status: -1, out: Data(), err: Data("\(error)".utf8)) }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: killer)
        // F_SETNOSIGPIPE: a CLI that exits before reading its stdin must not take XFinder down with SIGPIPE (measured: the
        // unguarded write kills the writer with exit 141; guarded, it throws).
        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? inPipe.fileHandleForWriting.write(contentsOf: input)
        try? inPipe.fileHandleForWriting.close()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return .init(status: p.terminationStatus, out: outData, err: errData)
    }
}
