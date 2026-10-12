import Foundation
import SQLite3

/// D (2026-10-12) — `XFinder --mcp`: the app binary as a stdio MCP server. No new target: a second
/// executable would need its own hand-authored pbxproj target and signing, and an MCP client only needs
/// a command to run. The GUI never starts in this mode — `XFinderApp.init` calls `run()` before SwiftUI
/// builds a scene, and `run()` exits on stdin EOF. Nothing here touches AppKit, Accessibility or any
/// TCC-gated service, so launching the binary from a terminal is safe (the Part 3c warning is about the
/// GUI path, whose first AX/Bluetooth request TCC attributes to the terminal).
///
/// Data: the same SQLite file the app writes, opened READ-ONLY (`SQLITE_OPEN_READONLY`), re-read on
/// every call so an agent sees what was just copied. Payload text comes from the payload files.
enum MCPServer {
    /// The ONE reader of `clipboard.mcpEnabled`. Default OFF: an agent reading your clipboard is opt-in.
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "clipboard.mcpEnabled") as? Bool ?? false }

    static func run() -> Never {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let dbPath = databasePath()
        let context = MCP.Context(enabled: isEnabled,
                                  appVersion: version,
                                  records: { readRecords(dbPath: dbPath) },
                                  fullText: { r in ClipboardText.fullText(snippet: r.textSnippet, payloadPath: r.type == .file ? nil : r.payloadPath) })
        // Unbuffered writes: the client waits for each reply line, so nothing may sit in a stdio buffer.
        // (`setvbuf(stdout, …)` is off the table — `stdout` is a C global and Swift 6 rejects the reference.)
        let out = FileHandle.standardOutput
        while let line = readLine(strippingNewline: true) {
            if let reply = MCP.handle(line: line, context: context), let data = (reply + "\n").data(using: .utf8) {
                out.write(data)
            }
        }
        exit(0)
    }

    /// Same location `DatabaseService` uses.
    static func databasePath() -> String {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("XFinder", isDirectory: true).appendingPathComponent("xfinder.db").path
    }

    /// Newest 1 000 rows, read-only, fresh per call. A missing or locked database is an empty history.
    static func readRecords(dbPath: String, limit: Int = 1000) -> [ClipboardRecord] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }
        let query = """
        SELECT id, type, timestamp, sourceBundleID, sourceAppName, textSnippet,
               thumbnailPath, payloadPath, ocrText, pinboardID, metadata
        FROM clipboard_records ORDER BY timestamp DESC LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var out: [ClipboardRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            func col(_ i: Int32) -> String? {
                guard let p = sqlite3_column_text(statement, i) else { return nil }
                return String(cString: p)
            }
            var meta: [String: String] = [:]
            if let m = col(10), let d = m.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: String] { meta = j }
            out.append(ClipboardRecord(
                id: UUID(uuidString: col(0) ?? "") ?? UUID(),
                type: ContentType(rawValue: col(1) ?? "") ?? .text,
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                sourceBundleID: col(3), sourceAppName: col(4),
                textSnippet: col(5), thumbnailPath: col(6), payloadPath: col(7), ocrText: col(8),
                pinboardID: col(9).flatMap(UUID.init(uuidString:)), metadata: meta))
        }
        return out
    }
}
