import Foundation

/// Anonymous product analytics: what one daily report may carry, and when XFinder may send it.
///
/// Job: *"tell the developer which features people use, which errors they hit and on which Macs the app runs — and
/// nothing about me."* Sending is on by default (the owner's choice); one switch refuses it. That default is only
/// defensible because a report is ANONYMOUS by construction, and the rules below are what keep it so:
/// - no identifier of any kind — every send is a separate record that cannot be linked to the previous one;
/// - no content — only version strings, machine codes, booleans and counts; a value that is not a safe token is
///   dropped, never sent;
/// - nothing leaves before the person has seen a one-time notice, and the first send waits a full day after it, so
///   the switch can be used before any data exists outside the Mac;
/// - at most one report per day.
/// Adding an identifier or any free text to `Report` would turn it into personal data and the opt-out default into a
/// legal problem (VN PDPL 91/2025 + Decree 356/2025, EU ePrivacy) — `AnalyticsRulesTests` fails on both.
enum AnalyticsRules {

    /// Bumped whenever `Report` gains a field. A higher schema shows the one-time notice again, so a person never has
    /// more sent about them than the notice they saw described.
    static let schemaVersion = 1
    static let minimumInterval: TimeInterval = 24 * 3600
    static let noticeGrace: TimeInterval = 24 * 3600
    /// After a failed send (offline, receiver down) the next try waits this long, so activating the app repeatedly
    /// never turns into a stream of requests.
    static let retryInterval: TimeInterval = 3600
    static let maxCrashes = 5
    static let maxFrames = 5
    static let maxErrorCodes = 40

    // MARK: - The report

    struct Crash: Codable, Equatable, Sendable {
        var kind: String
        var source: String
        var exceptionType: String?
        var signal: String?
        var termination: String?
        var frames: [String]
    }

    struct Report: Codable, Equatable, Sendable {
        var schema: Int
        var appVersion: String
        var build: String
        var osVersion: String
        var model: String
        var arch: String
        var language: String
        var featuresOn: [String]
        var permissionsGranted: [String]
        var launches: Int
        var uncleanExits: Int
        /// `area/code` → how many times since the last report.
        var errorCounts: [String: Int]
        var crashes: [Crash]
    }

    /// The inputs a report is built from. `osVersion` is `major.minor.patch` only — the build string is dropped.
    struct Inputs: Sendable {
        var appVersion: String
        var build: String
        var osVersion: String
        var model: String
        var arch: String
        var language: String
        var featuresOn: [String]
        var permissionsGranted: [String]
        var events: [DiagnosticsRules.Event]
        var crashes: [DiagnosticsRules.CrashSummary]
        /// The previous report's time; nil ⇒ the first report (only what is still in the local ring is counted).
        var since: Date?
    }

    /// A short machine token: letters, digits and `. _ - , : + ( ) space`, 1…80 characters. Anything else — a path (no
    /// `/`), an e-mail, a sentence in Vietnamese, a newline — is not a token and is never sent.
    static func isToken(_ s: String) -> Bool {
        guard (1...80).contains(s.count) else { return false }
        return s.unicodeScalars.allSatisfy { c in
            (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9")
                || ". _-,:+()".unicodeScalars.contains(c)
        }
    }

    /// `token` or nil — the only way a string reaches a report.
    static func clean(_ s: String?) -> String? {
        guard let s, isToken(s) else { return nil }
        return s
    }

    static func report(_ i: Inputs) -> Report {
        let fresh = i.events.filter { e in i.since.map { e.time > $0 } ?? true }
        var counts: [String: Int] = [:]
        var launches = 0, unclean = 0
        for e in fresh {
            switch (e.area, e.code) {
            case ("app", "launch"): launches += 1
            case ("app", "quit"): break
            case ("app", "uncleanExit"): unclean += 1
            default:
                // The key joins two words that are each checked on their own; `/` is never allowed inside a token.
                guard DiagnosticsRules.isSafeWord(e.area), DiagnosticsRules.isSafeWord(e.code) else { continue }
                counts["\(e.area)/\(e.code)", default: 0] += 1
            }
        }
        // Keep the most frequent codes if a broken machine logged hundreds of kinds.
        if counts.count > maxErrorCodes {
            let kept = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(maxErrorCodes)
            counts = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        let crashes = i.crashes
            .filter { c in i.since.map { (c.time ?? .distantPast) > $0 } ?? true }
            .sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
            .prefix(maxCrashes)
            .map { c in
                Crash(kind: clean(c.kind) ?? "other", source: clean(c.source) ?? "other",
                      exceptionType: clean(c.exceptionType), signal: clean(c.signal),
                      termination: clean(c.termination?.replacingOccurrences(of: " — ", with: " - ")),
                      frames: c.frames.compactMap(frameToken).prefix(maxFrames).map { $0 })
            }
        return Report(
            schema: schemaVersion,
            appVersion: clean(i.appVersion) ?? "?", build: clean(i.build) ?? "?",
            osVersion: clean(i.osVersion) ?? "?", model: clean(i.model) ?? "?", arch: clean(i.arch) ?? "?",
            language: i.language == "en" ? "en" : "vi",
            featuresOn: i.featuresOn.compactMap(clean).sorted(),
            permissionsGranted: i.permissionsGranted.compactMap(clean).sorted(),
            launches: launches, uncleanExits: unclean,
            errorCounts: counts, crashes: Array(crashes))
    }

    /// A crash frame as `image symbol`: the offset and the source location are dropped (they add nothing a symbol
    /// does not, and a source line can carry a file name). Symbols need `# < > [ ] $ & ? ! ' = *` ("closure #1 in …",
    /// generics), so frames get their own character set — but never `/`, `\`, `~` or `@`, the characters of a path or an
    /// e-mail. A frame that still does not fit is dropped.
    static func frameToken(_ frame: String) -> String? {
        var s = frame
        if let paren = s.range(of: "  (") { s = String(s[..<paren.lowerBound]) }      // "  (File.swift:42)"
        if let plus = s.range(of: " + ", options: .backwards) { s = String(s[..<plus.lowerBound]) }
        s = s.replacingOccurrences(of: "  ", with: " ").replacingOccurrences(of: "@objc ", with: "objc ")
        s = String(s.prefix(120))
        guard !s.isEmpty, s.unicodeScalars.allSatisfy({ c in
            (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9")
                || ". _-,:+()#<>[]$&?!'=*".unicodeScalars.contains(c)
        }) else { return nil }
        return s
    }

    /// The exact JSON the person can read in the app before anything is sent — sorted keys, pretty.
    static func previewJSON(_ r: Report) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(r), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    // MARK: - When to send

    struct State: Equatable, Sendable {
        var optedOut: Bool
        /// A receiver is configured in this build (Info.plist). Without one nothing is ever sent or announced.
        var configured: Bool
        var noticeShownAt: Date?
        var noticeSchema: Int?
        var lastSentAt: Date?
        /// The last attempt, successful or not.
        var lastAttemptAt: Date?
        /// First-run setup is on screen; the notice waits for it.
        var onboardingShowing: Bool
    }

    enum Wait: Equatable, Sendable { case optedOut, notConfigured, onboarding, grace, notDue }
    enum Action: Equatable, Sendable { case wait(Wait), showNotice, send }

    static func nextAction(_ s: State, now: Date) -> Action {
        if s.optedOut { return .wait(.optedOut) }
        if !s.configured { return .wait(.notConfigured) }
        guard let shown = s.noticeShownAt, (s.noticeSchema ?? 0) >= schemaVersion else {
            return s.onboardingShowing ? .wait(.onboarding) : .showNotice
        }
        // A clock set back must not freeze the grace or the interval forever: a "future" timestamp counts as elapsed.
        let sinceNotice = now.timeIntervalSince(shown)
        if sinceNotice >= 0, sinceNotice < noticeGrace { return .wait(.grace) }
        if let last = s.lastSentAt {
            let sinceSend = now.timeIntervalSince(last)
            if sinceSend >= 0, sinceSend < minimumInterval { return .wait(.notDue) }
        }
        if let attempt = s.lastAttemptAt {
            let sinceAttempt = now.timeIntervalSince(attempt)
            if sinceAttempt >= 0, sinceAttempt < retryInterval { return .wait(.notDue) }
        }
        return .send
    }

    /// The status line under the switch, as a store key.
    static func statusKey(_ action: Action) -> String {
        switch action {
        case .wait(.optedOut): return "Đã từ chối — XFinder không gửi gì."
        case .wait(.notConfigured): return "Bản này chưa có máy chủ nhận nên chưa gửi gì."
        case .wait(.onboarding), .showNotice: return "Chưa gửi gì — XFinder sẽ báo cho bạn trước lần gửi đầu."
        case .wait(.grace): return "Chưa gửi gì — lần gửi đầu chờ 24 giờ sau khi bạn thấy thông báo."
        case .wait(.notDue), .send: return "Đang bật — tối đa một bản mỗi ngày."
        }
    }

    // MARK: - TelemetryDeck (the receiver) — documented at telemetrydeck.com/docs/ingest/v2

    /// The receiver configured in Info.plist. Both values are public by design (they ship inside every app that uses
    /// TelemetryDeck); without both, nothing is ever sent or announced.
    struct Receiver: Equatable, Sendable {
        var appID: String
        var namespace: String
    }

    /// A receiver from the two Info.plist strings, or nil when either is missing or malformed. The namespace becomes a
    /// URL path component, so only `[a-z0-9-]` is accepted — never `/`, `..` or a space.
    static func receiver(appID: String?, namespace: String?) -> Receiver? {
        guard let id = appID?.trimmingCharacters(in: .whitespaces), !id.isEmpty, id.count <= 64,
              id.unicodeScalars.allSatisfy({ ($0 >= "A" && $0 <= "Z") || ($0 >= "a" && $0 <= "z")
                                                || ($0 >= "0" && $0 <= "9") || $0 == "-" }),
              let ns = namespace?.trimmingCharacters(in: .whitespaces), !ns.isEmpty, ns.count <= 64,
              ns.unicodeScalars.allSatisfy({ ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" })
        else { return nil }
        return Receiver(appID: id, namespace: ns)
    }

    static func endpoint(_ r: Receiver) -> URL? {
        URL(string: "https://nom.telemetrydeck.com/v2/namespace/\(r.namespace)/")
    }

    /// The POST body: one `Report.daily` signal plus one `Report.crash` per crash. `clientUser` is a fresh random
    /// value for THIS send only (the caller makes a new one every time), so two reports can never be linked;
    /// TelemetryDeck's user counts become meaningless for XFinder, which is the point. Payload values are flat
    /// strings (the receiver stores strings and leaves arrays undefined), keys scoped `XFinder.<Scope>.<key>`.
    static func telemetryDeckBody(_ r: Report, receiver: Receiver, clientUser: String, testMode: Bool) -> Data? {
        func signal(_ type: String, _ payload: [String: String]) -> [String: Any] {
            ["appID": receiver.appID, "clientUser": clientUser, "type": type, "isTestMode": testMode, "payload": payload]
        }
        let common: [String: String] = [
            "XFinder.Report.schema": String(r.schema),
            "XFinder.App.version": r.appVersion, "XFinder.App.build": r.build,
            "XFinder.System.osVersion": r.osVersion, "XFinder.System.model": r.model, "XFinder.System.arch": r.arch,
            "XFinder.UI.language": r.language,
        ]
        var daily = common
        daily["XFinder.Features.on"] = r.featuresOn.joined(separator: ",")
        daily["XFinder.Permissions.granted"] = r.permissionsGranted.joined(separator: ",")
        daily["XFinder.Usage.launches"] = String(r.launches)
        daily["XFinder.Usage.uncleanExits"] = String(r.uncleanExits)
        daily["XFinder.Errors.counts"] = r.errorCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            .joined(separator: ";")
        daily["XFinder.Crashes.count"] = String(r.crashes.count)
        var signals = [signal("Report.daily", daily)]
        for c in r.crashes {
            var p = common
            p["XFinder.Crash.kind"] = c.kind
            p["XFinder.Crash.source"] = c.source
            if let v = c.exceptionType { p["XFinder.Crash.exceptionType"] = v }
            if let v = c.signal { p["XFinder.Crash.signal"] = v }
            if let v = c.termination { p["XFinder.Crash.termination"] = v }
            p["XFinder.Crash.frames"] = c.frames.joined(separator: " | ")
            signals.append(signal("Report.crash", p))
        }
        return try? JSONSerialization.data(withJSONObject: signals, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static let statusKeys = [
        statusKey(.wait(.optedOut)), statusKey(.wait(.notConfigured)), statusKey(.showNotice),
        statusKey(.wait(.grace)), statusKey(.send),
    ]
}
