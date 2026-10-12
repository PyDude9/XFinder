import Foundation

/// D (2026-10-12) — the Clipboard MCP server's protocol half: pure, so every message shape and every
/// rule about what leaves the machine is tested without a process or a pipe. `MCPServer` (the other
/// half) owns stdin/stdout and SQLite and calls `handle(line:context:)` per line.
///
/// Scope, stated honestly: the server runs only when an agent starts `XFinder --mcp`; it reads the
/// clipboard database read-only; it returns TEXT (snippets or full text), never image/file bytes; it
/// never returns a record from a password manager (those are also never recorded — this is the
/// second fence); and when `clipboard.mcpEnabled` is off every tool call answers with an error.
enum MCP {
    static let protocolVersion = "2024-11-05"
    static let serverName = "xfinder-clipboard"
    static let maxLimit = 100
    static let defaultLimit = 20

    /// Bundle-id fragments of password managers (mirrors the capture filter's list in ClipboardManager).
    static let excludedBundleFragments = ["1password", "bitwarden", "lastpass", "keepass", "dashlane", "keychainaccess", "nordpass", "enpass"]

    /// What the server needs from the outside, injected so tests run with fixtures.
    struct Context {
        var enabled: Bool
        var appVersion: String
        var records: () -> [ClipboardRecord]
        /// Full text of a record (payload file first, snippet second); nil when there is none.
        var fullText: (ClipboardRecord) -> String?
    }

    // MARK: - Dispatch

    /// One JSON-RPC line in, one line out (nil for notifications and for lines that need no answer).
    static func handle(line: String, context: Context) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return encode(error(id: NSNull(), code: -32700, message: "Parse error"))
        }
        let id = obj["id"] ?? NSNull()
        guard let method = obj["method"] as? String else {
            return encode(error(id: id, code: -32600, message: "Invalid Request: missing method"))
        }
        let params = obj["params"] as? [String: Any] ?? [:]
        let isNotification = obj["id"] == nil
        switch method {
        case "initialize":
            return encode(result(id: id, [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": serverName, "version": context.appVersion],
            ]))
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return isNotification ? nil : encode(result(id: id, [String: Any]()))
        case "tools/list":
            return encode(result(id: id, ["tools": toolDescriptors()]))
        case "tools/call":
            guard context.enabled else {
                return encode(error(id: id, code: -32000, message: "Clipboard MCP is turned off in XFinder ▸ Cài đặt Clipboard"))
            }
            return encode(callTool(id: id, params: params, context: context))
        default:
            return isNotification ? nil : encode(error(id: id, code: -32601, message: "Method not found: \(method)"))
        }
    }

    // MARK: - Tools

    static func toolDescriptors() -> [[String: Any]] {
        let typeProp: [String: Any] = ["type": "string", "description": "text | code | markdown | link | color | file | image | merged",
                                       "enum": ContentType.allCases.map(\.rawValue)]
        return [
            ["name": "clipboard_list_recent",
             "description": "Most recent clipboard items (text only; images and files are listed by name, their bytes are never returned).",
             "inputSchema": ["type": "object", "properties": [
                "limit": ["type": "integer", "minimum": 1, "maximum": maxLimit, "default": defaultLimit],
                "type": typeProp]]],
            ["name": "clipboard_search",
             "description": "Search the clipboard history by text (snippet, OCR text, title, source app). Newest first.",
             "inputSchema": ["type": "object", "required": ["query"], "properties": [
                "query": ["type": "string"],
                "type": typeProp,
                "limit": ["type": "integer", "minimum": 1, "maximum": maxLimit, "default": defaultLimit]]]],
            ["name": "clipboard_get",
             "description": "Full text of one clipboard item by id (from list/search).",
             "inputSchema": ["type": "object", "required": ["id"], "properties": ["id": ["type": "string"]]]],
        ]
    }

    private static func callTool(id: Any, params: [String: Any], context: Context) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return error(id: id, code: -32602, message: "Invalid params: missing tool name")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]
        let all = visible(context.records())
        switch name {
        case "clipboard_list_recent":
            let type = (args["type"] as? String).flatMap(ContentType.init(rawValue:))
            let items = recent(all, type: type, limit: clampLimit(args["limit"]))
            return result(id: id, toolText(items.map(summaryLine).joined(separator: "\n"), isError: false))
        case "clipboard_search":
            guard let query = args["query"] as? String, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                return error(id: id, code: -32602, message: "Invalid params: query is required")
            }
            let type = (args["type"] as? String).flatMap(ContentType.init(rawValue:))
            let items = search(all, query: query, type: type, limit: clampLimit(args["limit"]))
            return result(id: id, toolText(items.isEmpty ? "No clipboard items match \"\(query)\"." : items.map(summaryLine).joined(separator: "\n"), isError: false))
        case "clipboard_get":
            guard let s = args["id"] as? String, let uuid = UUID(uuidString: s) else {
                return error(id: id, code: -32602, message: "Invalid params: id must be a UUID")
            }
            guard let r = all.first(where: { $0.id == uuid }) else {
                return result(id: id, toolText("No clipboard item with id \(s).", isError: true))
            }
            let text = context.fullText(r) ?? r.textSnippet ?? ""
            return result(id: id, toolText(text, isError: false))
        default:
            return error(id: id, code: -32602, message: "Unknown tool: \(name)")
        }
    }

    // MARK: - Pure rules

    /// Records a password manager produced never leave the machine, whatever the capture filter did.
    static func visible(_ records: [ClipboardRecord]) -> [ClipboardRecord] {
        records.filter { r in
            let bid = (r.sourceBundleID ?? "").lowercased()
            return !excludedBundleFragments.contains { bid.contains($0) }
        }
    }

    static func recent(_ records: [ClipboardRecord], type: ContentType?, limit: Int) -> [ClipboardRecord] {
        var list = records
        if let type { list = list.filter { $0.type == type } }
        return Array(list.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// Case-insensitive substring over snippet, OCR text, custom title and source-app name; newest first.
    static func search(_ records: [ClipboardRecord], query: String, type: ContentType?, limit: Int) -> [ClipboardRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var list = records.filter { r in
            (r.textSnippet?.localizedCaseInsensitiveContains(q) ?? false)
                || (r.ocrText?.localizedCaseInsensitiveContains(q) ?? false)
                || (r.customTitle?.localizedCaseInsensitiveContains(q) ?? false)
                || (r.sourceAppName?.localizedCaseInsensitiveContains(q) ?? false)
        }
        if let type { list = list.filter { $0.type == type } }
        return Array(list.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// `limit` from the arguments, clamped to 1…`maxLimit`; absent or garbage ⇒ the default.
    static func clampLimit(_ raw: Any?) -> Int {
        let n: Int
        if let i = raw as? Int { n = i } else if let d = raw as? Double { n = Int(d) } else if let s = raw as? String, let i = Int(s) { n = i } else { return defaultLimit }
        return min(max(n, 1), maxLimit)
    }

    /// One line per item: id · type · age-free ISO timestamp · app · the snippet on one line (≤ 200 chars).
    static func summaryLine(_ r: ClipboardRecord) -> String {
        let f = ISO8601DateFormatter()
        let snippet = (r.textSnippet ?? "").replacingOccurrences(of: "\n", with: " ⏎ ")
        let short = snippet.count > 200 ? String(snippet.prefix(200)) + "…" : snippet
        let app = r.sourceAppName ?? r.sourceBundleID ?? "?"
        return "\(r.id.uuidString) · \(r.type.rawValue) · \(f.string(from: r.timestamp)) · \(app) · \(short)"
    }

    // MARK: - JSON-RPC envelopes

    static func result(id: Any, _ value: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static func toolText(_ text: String, isError: Bool) -> [String: Any] {
        var r: [String: Any] = ["content": [["type": "text", "text": text]]]
        if isError { r["isError"] = true }
        return r
    }

    /// One line, no pretty-printing (the transport is newline-delimited), keys sorted for stable tests.
    static func encode(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error: could not encode"}}"#
        }
        return s
    }
}
