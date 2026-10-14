import Foundation

/// P11 (2026-10-14) — a windowless Codex session: XFinder runs `codex app-server` as its child and speaks its JSON-RPC
/// over stdin/stdout (one JSON object per line). Pure (symlinked into the test package): the messages XFinder sends and
/// the reading of what comes back. The live half is `WindowlessSessionManager` (`startCodex`).
///
/// Measured on codex-cli 0.155.0 (schema from `codex app-server generate-json-schema`, plus a probe that ran only the
/// handshake — no turn, no model call): `initialize` answers in 0.16 s; `thread/start {cwd, approvalPolicy: "on-request",
/// sandbox: "workspace-write"}` returns `thread.id` (== `thread.sessionId`) with the cwd and policy echoed; closing stdin
/// ends the process with status 0. Messages carry `id`/`method`/`params` and no `"jsonrpc"` field.
///
/// Approval comes back on the same pipe as a server REQUEST (`item/commandExecution/requestApproval`,
/// `item/fileChange/requestApproval`; v1 `execCommandApproval` / `applyPatchApproval`), so XFinder answers it directly —
/// no hook needed. Any other server request is answered with a JSON-RPC error rather than left hanging: the server would
/// otherwise wait on it forever.
enum CodexAppServer {

    // MARK: - Requests XFinder sends

    static let initializeID = 1
    static let threadStartID = 2

    static func initialize(id: Int = initializeID, version: String) -> String {
        line(["id": id, "method": "initialize",
              "params": ["clientInfo": ["name": "xfinder", "title": "XFinder", "version": version]]])
    }

    static let initialized = line(["method": "initialized"])

    /// A new thread in `cwd`. `on-request` + `workspace-write`: Codex asks before anything outside the folder or the
    /// network — the windowless counterpart of Claude Code's ask-first mode (P7a / P7b).
    static func threadStart(id: Int = threadStartID, cwd: String) -> String {
        line(["id": id, "method": "thread/start",
              "params": ["cwd": cwd, "approvalPolicy": "on-request", "sandbox": "workspace-write"]])
    }

    static func turnStart(id: Int, threadID: String, text: String) -> String {
        line(["id": id, "method": "turn/start",
              "params": ["threadId": threadID, "input": [["type": "text", "text": text]]]])
    }

    static func turnInterrupt(id: Int, threadID: String, turnID: String) -> String {
        line(["id": id, "method": "turn/interrupt", "params": ["threadId": threadID, "turnId": turnID]])
    }

    /// The answer to an approval request. `rawID` is the request's `id` exactly as it arrived (a number or a string), so
    /// the reply matches it whatever its JSON type. v2 says accept/decline; v1 approved/denied.
    static func approvalReply(rawID: String, allow: Bool, legacy: Bool) -> String {
        let decision = legacy ? (allow ? "approved" : "denied") : (allow ? "accept" : "decline")
        return "{\"id\":\(rawID),\"result\":{\"decision\":\"\(decision)\"}}\n"
    }

    /// Any server request XFinder does not handle: an error, so the server does not wait on it.
    static func unsupportedReply(rawID: String) -> String {
        "{\"id\":\(rawID),\"error\":{\"code\":-32601,\"message\":\"Not supported by XFinder\"}}\n"
    }

    private static func line(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "" }
        return s + "\n"
    }

    // MARK: - What comes back

    enum ApprovalKind: Equatable, Sendable { case command, fileChange }

    enum Event: Equatable, Sendable {
        case initializeOK
        case threadStarted(threadID: String, model: String?)
        /// A reply to one of XFinder's requests that failed (e.g. thread/start without a login).
        case requestFailed(id: Int, message: String)
        case turnStarted(turnID: String)
        case tool(String)                       // a command started (shown as the session's current tool)
        case agentMessage(String)
        case turnCompleted(status: String, error: String?)
        case approval(rawID: String, kind: ApprovalKind, summary: String?, legacy: Bool)
        case otherRequest(rawID: String)        // a server request XFinder answers with an error
        case error(String)
        case ignored
    }

    static func parse(line: String) -> Event {
        guard let data = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .ignored }
        let method = o["method"] as? String
        let params = o["params"] as? [String: Any] ?? [:]
        // A server REQUEST has both an id and a method.
        if let method, o["id"] != nil {
            let raw = rawID(o["id"])
            switch method {
            case "item/commandExecution/requestApproval":
                return .approval(rawID: raw, kind: .command, summary: params["command"] as? String ?? params["reason"] as? String, legacy: false)
            case "item/fileChange/requestApproval":
                return .approval(rawID: raw, kind: .fileChange, summary: params["reason"] as? String ?? params["grantRoot"] as? String, legacy: false)
            case "execCommandApproval":
                let cmd = (params["command"] as? [String])?.joined(separator: " ") ?? params["command"] as? String
                return .approval(rawID: raw, kind: .command, summary: cmd, legacy: true)
            case "applyPatchApproval":
                return .approval(rawID: raw, kind: .fileChange, summary: params["reason"] as? String, legacy: true)
            default:
                return .otherRequest(rawID: raw)
            }
        }
        // A reply to one of XFinder's requests.
        if method == nil, let id = o["id"] as? Int {
            if let err = o["error"] as? [String: Any] {
                return .requestFailed(id: id, message: err["message"] as? String ?? "error")
            }
            let result = o["result"] as? [String: Any] ?? [:]
            if id == initializeID { return .initializeOK }
            if let thread = result["thread"] as? [String: Any], let tid = thread["id"] as? String {
                return .threadStarted(threadID: tid, model: result["model"] as? String)
            }
            return .ignored
        }
        switch method {
        case "turn/started":
            return ((params["turn"] as? [String: Any])?["id"] as? String).map { .turnStarted(turnID: $0) } ?? .ignored
        case "item/started":
            guard let item = params["item"] as? [String: Any] else { return .ignored }
            switch item["type"] as? String {
            case "commandExecution": return .tool("Bash")
            case "fileChange": return .tool("Edit")
            case "mcpToolCall": return .tool((item["tool"] as? String) ?? "MCP")
            case "webSearch": return .tool("WebSearch")
            default: return .ignored
            }
        case "item/completed":
            guard let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage",
                  let text = item["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .ignored }
            return .agentMessage(text)
        case "turn/completed":
            let turn = params["turn"] as? [String: Any] ?? [:]
            let err = (turn["error"] as? [String: Any])?["message"] as? String
            return .turnCompleted(status: turn["status"] as? String ?? "completed", error: err)
        case "error":
            let msg = (params["error"] as? [String: Any])?["message"] as? String ?? params["message"] as? String ?? "error"
            return .error(msg)
        default:
            return .ignored
        }
    }

    /// The `id` re-serialised as JSON (so a numeric id stays a number and a string id stays a string in the reply).
    static func rawID(_ v: Any?) -> String {
        if let i = v as? Int { return String(i) }
        if let s = v as? String, let d = try? JSONSerialization.data(withJSONObject: [s]), let txt = String(data: d, encoding: .utf8) {
            return String(txt.dropFirst().dropLast())
        }
        return "null"
    }

    /// Where `codex` usually lives (its standalone installer links ~/.local/bin/codex — measured on this Mac).
    static func candidates(path: String?, home: String) -> [String] {
        var out = (path ?? "").split(separator: ":").map { String($0) + "/codex" }
        out += [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        var seen = Set<String>()
        return out.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }
}
