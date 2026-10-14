import Foundation

/// What XFinder may keep about its own failures, and what a bug report may contain.
///
/// Job: *"something went wrong — give the developer enough to fix it, and nothing about me."* Nothing here
/// sends anything: the log stays on this Mac, and a report leaves only when the person copies, saves, or pastes
/// it themselves after reading it. The rules below are therefore about CONTENT: an event is a short machine code
/// (never a file name, a clip, a window title or an app id), free text is redacted, and a crash report is reduced
/// to an allowlist of fields — anything Apple's report carries that identifies the machine, the person or the
/// session (`crashReporterKey`, `sleepWakeUUID`, `userID`, process paths, the `asi` free text…) never reaches the
/// summary, because the summary is built field by field rather than filtered.
enum DiagnosticsRules {

    // MARK: - Events

    struct Event: Codable, Equatable, Sendable {
        let time: Date
        /// The subsystem: `app`, `snap`, `archive`, `capture`, `nowPlaying`, `eventTap`…
        let area: String
        /// A short machine word: `uncleanExit`, `helperGaveUp`, `timeout.snap`…
        let code: String
        /// Optional, already redacted and trimmed to `maxDetail`.
        let detail: String?
    }

    /// The ring's size. 300 lines of ~100 bytes is ~30 KB — no reason to keep more on disk.
    static let maxEvents = 300
    static let maxDetail = 200

    /// A word that is safe to store as an area or a code: ASCII letters, digits, `.`, `_`, `-`, 1…48 long.
    /// Anything else (a path, a sentence, a name) is refused rather than stored.
    static func isSafeWord(_ s: String) -> Bool {
        guard (1...48).contains(s.count) else { return false }
        return s.unicodeScalars.allSatisfy { c in
            (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "." || c == "_" || c == "-"
        }
    }

    /// A storable event, or nil when the area or the code is not a safe word.
    static func event(area: String, code: String, detail: String?, at time: Date, home: String) -> Event? {
        guard isSafeWord(area), isSafeWord(code) else { return nil }
        let cleaned = detail.map { String(redact($0, home: home).prefix(maxDetail)) }
        return Event(time: time, area: area, code: code, detail: cleaned?.isEmpty == true ? nil : cleaned)
    }

    /// The newest `maxEvents`, oldest first.
    static func trimmed(_ events: [Event]) -> [Event] {
        events.count > maxEvents ? Array(events.suffix(maxEvents)) : events
    }

    static func encodeLine(_ e: Event) -> String? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(e), let line = String(data: data, encoding: .utf8) else { return nil }
        return line
    }

    /// Every well-formed line, in file order. A torn last line (the app died mid-write) is skipped, never fatal.
    static func decodeLines(_ text: String) -> [Event] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? dec.decode(Event.self, from: Data(line.utf8))
        }
    }

    /// The launch before this one ended without the app's own quit marker: it crashed, was killed, or the Mac
    /// lost power. Looked at once per launch, BEFORE this launch writes its own marker.
    static func previousRunEndedUncleanly(_ events: [Event]) -> Bool {
        guard let lastLaunch = events.lastIndex(where: { $0.area == "app" && $0.code == "launch" }) else { return false }
        return !events[lastLaunch...].contains { $0.area == "app" && $0.code == "quit" }
    }

    // MARK: - Redaction

    /// Removes what can identify the person from free text: their home folder (`~`), any other `/Users/<name>`,
    /// e-mail addresses and UUIDs (clip, session and device ids all look like one).
    static func redact(_ text: String, home: String) -> String {
        var s = text
        if home.count > 1 { s = s.replacingOccurrences(of: home, with: "~") }
        s = replace(#"/Users/[^/\s"'<>:]+"#, in: s, with: "/Users/…")
        s = replace(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, in: s, with: "<email>")
        s = replace(#"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#, in: s, with: "<uuid>")
        return s
    }

    private static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let escaped = NSRegularExpression.escapedTemplate(for: template)
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: escaped)
    }

    // MARK: - Crash summaries

    struct CrashSummary: Codable, Equatable, Sendable {
        /// `report` — a macOS crash report (.ips); `metrickit` — delivered by MetricKit.
        var source: String
        /// `crash`, `hang`, `cpu`, `diskWrite`.
        var kind: String
        var time: Date?
        var appVersion: String?
        var build: String?
        var osVersion: String?
        var model: String?
        var cpu: String?
        var exceptionType: String?
        var signal: String?
        var termination: String?
        var hangSeconds: Double?
        /// The faulting thread, top first: `image  symbol + offset` or `image  +0xoffset`.
        var frames: [String]
    }

    static let maxFrames = 12
    /// How many crash summaries a report carries.
    static let maxCrashes = 5

    /// A summary of one macOS crash report (`.ips`: a one-line JSON header, then a JSON body), or nil when the
    /// text is not a report of `processName`. Built from named fields only — see the type's doc comment.
    static func crashSummary(ipsText: String, processName: String, home: String) -> CrashSummary? {
        let parts = ipsText.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let header = json(parts[0]),
              let body = json(parts[1]) else { return nil }
        let name = (header["name"] as? String) ?? (header["app_name"] as? String) ?? (body["procName"] as? String)
        guard name == processName else { return nil }

        func clean(_ v: Any?) -> String? {
            guard let s = v as? String, !s.isEmpty else { return nil }
            return String(redact(s, home: home).prefix(120))
        }
        let bundle = body["bundleInfo"] as? [String: Any]
        let exception = body["exception"] as? [String: Any]
        let termination = body["termination"] as? [String: Any]
        let terminationText: String? = {
            let parts = [termination?["namespace"], termination?["indicator"]].compactMap { clean($0) }
            return parts.isEmpty ? nil : parts.joined(separator: " — ")
        }()
        let osText: String? = clean(header["os_version"]) ?? {
            let os = body["osVersion"] as? [String: Any]
            return [clean(os?["train"]), clean(os?["build"])].compactMap { $0 }.joined(separator: " ").nilIfEmpty
        }()
        let bugType = (header["bug_type"] as? String) ?? (body["bug_type"] as? String)

        return CrashSummary(
            source: "report",
            kind: bugType == "309" ? "crash" : "other",          // 309 = a crash report; anything else is not decoded further
            time: reportDate(clean(header["timestamp"]) ?? clean(body["captureTime"])),
            appVersion: clean(header["app_version"]) ?? clean(bundle?["CFBundleShortVersionString"]),
            build: clean(header["build_version"]) ?? clean(bundle?["CFBundleVersion"]),
            osVersion: osText,
            model: clean(body["modelCode"]),
            cpu: clean(body["cpuType"]),
            exceptionType: clean(exception?["type"]),
            signal: clean(exception?["signal"]),
            termination: terminationText,
            hangSeconds: nil,
            frames: faultingFrames(body: body, home: home))
    }

    private static func json(_ s: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
    }

    /// The faulting thread's top frames: image NAME (never its path), symbol and offset; a source location keeps
    /// only the file's last path component and line.
    private static func faultingFrames(body: [String: Any], home: String) -> [String] {
        guard let threads = body["threads"] as? [[String: Any]], !threads.isEmpty else { return [] }
        let images = body["usedImages"] as? [[String: Any]] ?? []
        let index = (body["faultingThread"] as? Int) ?? threads.firstIndex { ($0["triggered"] as? Bool) == true } ?? 0
        guard threads.indices.contains(index), let frames = threads[index]["frames"] as? [[String: Any]] else { return [] }
        return frames.prefix(maxFrames).map { f in
            let imageIndex = f["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(imageIndex) ? (images[imageIndex]["name"] as? String ?? "?") : "?"
            var line = image
            if let symbol = f["symbol"] as? String, !symbol.isEmpty {
                line += "  " + symbol
                if let loc = f["symbolLocation"] as? Int { line += " + \(loc)" }
            } else if let offset = f["imageOffset"] as? Int {
                line += "  +0x" + String(offset, radix: 16)
            }
            if let file = f["sourceFile"] as? String, !file.isEmpty {
                line += "  (" + (file as NSString).lastPathComponent
                if let n = f["sourceLine"] as? Int { line += ":\(n)" }
                line += ")"
            }
            return String(redact(line, home: home).prefix(240))
        }
    }

    /// `2026-10-13 05:52:12.00 +0700` (header) or `2026-10-13 05:52:12.5321 +0700` (body).
    static func reportDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss.SSSS Z", "yyyy-MM-dd HH:mm:ss Z"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    // MARK: - Report

    struct SystemInfo: Equatable, Sendable {
        var appVersion: String
        var build: String
        var osVersion: String
        var model: String
        var arch: String
        var language: String
        /// `accessibility: granted` … — names from `AppPermission.rawValue`, never a display string.
        var permissions: [String]
        /// `FeatureID.rawValue`s of the features switched on.
        var featuresOn: [String]
    }

    /// The text the person reads before it goes anywhere. English on purpose: it is a technical log for the
    /// developer, like a crash report, and it reads the same whatever the UI language.
    static func report(system: SystemInfo, events: [Event], crashes: [CrashSummary], now: Date, home: String) -> String {
        var out: [String] = []
        out.append("## XFinder diagnostic report")
        out.append("Generated: \(iso(now))")
        out.append("")
        out.append(contentsOf: systemLines(system))
        out.append("")
        let shownCrashes = Array(crashes.sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }.prefix(maxCrashes))
        out.append("### Crashes and hangs (\(shownCrashes.count))")
        if shownCrashes.isEmpty { out.append("None found.") }
        for c in shownCrashes {
            var head = "- \(c.kind) · \(c.source)"
            if let t = c.time { head += " · \(iso(t))" }
            if let v = c.appVersion { head += " · v\(v)" }
            if let b = c.build { head += " (\(b))" }
            out.append(head)
            let reason = [c.exceptionType, c.signal, c.termination].compactMap { $0 }.joined(separator: " · ")
            if !reason.isEmpty { out.append("  reason: \(reason)") }
            if let h = c.hangSeconds { out.append("  hang: \(String(format: "%.1f", h)) s") }
            for f in c.frames { out.append("    \(f)") }
        }
        out.append("")
        let recent = events.suffix(60)
        out.append("### Recent events (\(recent.count) of \(events.count))")
        if recent.isEmpty { out.append("None recorded.") }
        for e in recent {
            var line = "- \(iso(e.time))  \(e.area)/\(e.code)"
            if let d = e.detail { line += "  \(d)" }
            out.append(line)
        }
        out.append("")
        out.append("No file names, clipboard content, window titles or account data are included.")
        return redact(out.joined(separator: "\n"), home: home)
    }

    static func systemLines(_ s: SystemInfo) -> [String] {
        [
            "- App: XFinder \(s.appVersion) (\(s.build))",
            "- macOS: \(s.osVersion)",
            "- Mac: \(s.model) · \(s.arch)",
            "- UI language: \(s.language)",
            "- Permissions: \(s.permissions.isEmpty ? "—" : s.permissions.joined(separator: ", "))",
            "- Features on: \(s.featuresOn.isEmpty ? "—" : s.featuresOn.joined(separator: ", "))",
        ]
    }

    /// A new-issue link that carries only the versions and a template; the report itself travels by clipboard,
    /// so the URL stays short and never holds anything but version numbers.
    static func issueURL(repo: String, system: SystemInfo) -> URL? {
        let body = """
        **What happened**


        **Steps to reproduce**
        1.

        **System**
        \(systemLines(SystemInfo(appVersion: system.appVersion, build: system.build, osVersion: system.osVersion,
                                 model: system.model, arch: system.arch, language: system.language,
                                 permissions: [], featuresOn: [])).prefix(3).joined(separator: "\n"))

        **Diagnostic report**
        (XFinder copied it to your clipboard — paste it here, after reading it.)
        """
        var c = URLComponents(string: "https://github.com/\(repo)/issues/new")
        c?.queryItems = [URLQueryItem(name: "title", value: "[Bug] "), URLQueryItem(name: "body", value: body)]
        guard let url = c?.url, url.absoluteString.count <= 6_000 else { return nil }
        return url
    }

    private static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
