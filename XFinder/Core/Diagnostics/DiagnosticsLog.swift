import Foundation

/// The local technical log: one JSON line per failure XFinder notices in itself, kept on this Mac only
/// (`~/Library/Application Support/XFinder/Diagnostics/events.jsonl`, newest 300 lines).
///
/// `record` may be called from any thread — event-tap callbacks, helper readers, background tasks: it validates
/// on the caller and does the file work on one serial utility queue, so a caller never waits on the disk.
/// Nothing in this file talks to the network.
enum DiagnosticsLog {
    private static let queue = DispatchQueue(label: "com.xfinder.diagnostics.log", qos: .utility)

    /// The ONE reader of `diagnostics.localLog` (default on: codes only, never content, never leaves the Mac).
    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "diagnostics.localLog") as? Bool ?? true
    }

    nonisolated static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("XFinder/Diagnostics", isDirectory: true)
    }

    nonisolated static var fileURL: URL { folder.appendingPathComponent("events.jsonl") }

    /// Records one event when the log is on. `area`/`code` must be safe words (`DiagnosticsRules.isSafeWord`);
    /// anything else is dropped rather than stored. `detail` is redacted before it is written.
    /// `waitUntilWritten` is for the quit marker: an async write queued in `applicationWillTerminate` would be lost
    /// when the process exits, and every next launch would then report an unclean exit.
    nonisolated static func record(_ area: String, _ code: String, detail: String? = nil, waitUntilWritten: Bool = false) {
        guard isEnabled,
              let event = DiagnosticsRules.event(area: area, code: code, detail: detail, at: Date(), home: NSHomeDirectory()),
              let line = DiagnosticsRules.encodeLine(event) else { return }
        if waitUntilWritten { queue.sync { append(line) } } else { queue.async { append(line) } }
    }

    /// Every stored event, oldest first. Waits for writes already queued, so a report includes them.
    nonisolated static func events() -> [DiagnosticsRules.Event] {
        queue.sync {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
            return DiagnosticsRules.decodeLines(text)
        }
    }

    nonisolated static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Called on `queue` only.
    private static func append(_ line: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = fileURL
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
        // Trim lazily: only once the file is twice the ring, rewrite the newest `maxEvents` atomically.
        if let size = try? handle.offset(), size > 64_000,
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let kept = DiagnosticsRules.trimmed(DiagnosticsRules.decodeLines(text))
            let body = kept.compactMap(DiagnosticsRules.encodeLine).joined(separator: "\n") + "\n"
            try? Data(body.utf8).write(to: url, options: .atomic)
        }
    }
}
