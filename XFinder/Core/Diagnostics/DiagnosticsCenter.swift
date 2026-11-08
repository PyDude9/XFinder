import AppKit
import MetricKit

/// Gathers what a bug report may contain and hands it to the person — never to a server.
///
/// Sources, all on this Mac: the local event log (`DiagnosticsLog`), crash/hang diagnostics MetricKit delivers to
/// the app itself, and macOS's own crash reports for XFinder in `~/Library/Logs/DiagnosticReports`, each reduced
/// to `DiagnosticsRules.CrashSummary`. The report is shown before it goes anywhere; the only ways out are
/// Copy, Save and "open GitHub Issues" (which copies the report and opens a short, version-only link).
@MainActor
final class DiagnosticsCenter {
    static let shared = DiagnosticsCenter()
    static let issuesRepo = "PyDude9/XFinder"

    private let sink = MetricKitSink()
    private var started = false

    private init() {}

    /// Once per launch, from `applicationDidFinishLaunching`.
    func start() {
        guard !started else { return }
        started = true
        if DiagnosticsLog.isEnabled {
            // Read the previous run's end BEFORE writing this run's launch marker.
            if DiagnosticsRules.previousRunEndedUncleanly(DiagnosticsLog.events()) {
                DiagnosticsLog.record("app", "uncleanExit")
            }
            DiagnosticsLog.record("app", "launch", detail: "v\(appVersion) (\(appBuild))")
        }
        MXMetricManager.shared.add(sink)
        sink.ingest(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    /// The quit marker that lets the next launch tell a clean exit from a crash.
    func markQuit() {
        DiagnosticsLog.record("app", "quit", waitUntilWritten: true)
    }

    // MARK: Report

    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var appBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }

    func systemInfo() -> DiagnosticsRules.SystemInfo {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let granted = FeatureHub.shared.granted()
        let permissions = AppPermission.allCases.map { "\($0.rawValue): \(granted[$0] == true ? "granted" : "not granted")" }
        let featuresOn = FeatureHub.shared.enabledSet.map(\.rawValue).sorted()
        return DiagnosticsRules.SystemInfo(
            appVersion: appVersion, build: appBuild,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (\(Self.sysctl("kern.osversion") ?? "?"))",
            model: Self.sysctl("hw.model") ?? "?",
            arch: Self.architecture,
            language: L10n.isEnglish ? "en" : "vi",
            permissions: permissions, featuresOn: featuresOn)
    }

    /// Everything the report shows, built fresh. Disk reads are small (a 30 KB log, ≤ 3 crash reports).
    func buildReport() -> String {
        let home = NSHomeDirectory()
        let crashes = Self.storedMetricKitSummaries() + Self.recentCrashReports(home: home)
        return DiagnosticsRules.report(system: systemInfo(), events: DiagnosticsLog.events(),
                                       crashes: crashes, now: Date(), home: home)
    }

    func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func copySystemInfo() {
        copy((["XFinder system info"] + DiagnosticsRules.systemLines(systemInfo())).joined(separator: "\n"))
    }

    /// Returns false when the person cancelled or the write failed.
    @discardableResult
    func save(_ text: String) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "XFinder-diagnostics-\(appVersion).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Copies the report, then opens a new-issue page whose link carries only version numbers.
    func openIssue(with report: String) {
        copy(report)
        if let url = DiagnosticsRules.issueURL(repo: Self.issuesRepo, system: systemInfo()) {
            NSWorkspace.shared.open(url)
        }
    }

    func clearLog() {
        DiagnosticsLog.clear()
        try? FileManager.default.removeItem(at: Self.metricKitFile)
    }

    // MARK: Sources

    /// macOS's crash reports for XFinder, newest three from the last 30 days.
    nonisolated static func recentCrashReports(home: String) -> [DiagnosticsRules.CrashSummary] {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: home).appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let candidates: [(URL, Date)] = names
            .filter { $0.hasPrefix("XFinder") && $0.hasSuffix(".ips") }
            .compactMap { name in
                let url = dir.appendingPathComponent(name)
                guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      date >= cutoff else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
        return candidates.prefix(3).compactMap { url, _ in
            // A crash report is a few hundred KB at most; refuse anything absurd rather than read it.
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 4_000_000,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return DiagnosticsRules.crashSummary(ipsText: text, processName: "XFinder", home: home)
        }
    }

    nonisolated static var metricKitFile: URL { DiagnosticsLog.folder.appendingPathComponent("metrickit.json") }

    nonisolated static func storedMetricKitSummaries() -> [DiagnosticsRules.CrashSummary] {
        guard let data = try? Data(contentsOf: metricKitFile) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([DiagnosticsRules.CrashSummary].self, from: data)) ?? []
    }

    /// Keeps the newest ten. Only while the local log is on — the switch covers every stored diagnostic.
    nonisolated static func storeMetricKitSummaries(_ new: [DiagnosticsRules.CrashSummary]) {
        guard DiagnosticsLog.isEnabled, !new.isEmpty else { return }
        var all = storedMetricKitSummaries()
        for s in new where !all.contains(s) { all.append(s) }
        all.sort { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
        let kept = Array(all.suffix(10))
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(kept) else { return }
        try? FileManager.default.createDirectory(at: DiagnosticsLog.folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: metricKitFile, options: .atomic)
        DiagnosticsLog.record("metrickit", "received", detail: "\(new.count)")
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}

extension ArchiveRunner.Failure {
    /// The failure's kind as a log code — never the file names or the tool's stderr the case carries.
    var diagnosticCode: String {
        switch self {
        case .nothingToDo: return "nothingToDo"
        case .cancelled: return "cancelled"
        case .missingSource: return "missingSource"
        case .staging: return "staging"
        case .tool(let status, _): return "tool.\(status)"
        case .missingData: return "missingData"
        case .placement: return "placement"
        case .unsafeLinks: return "unsafeLinks"
        case .unsafeArchive: return "unsafeArchive"
        case .outOfSpace: return "outOfSpace"
        case .archiveChanged: return "archiveChanged"
        case .readerUnavailable: return "readerUnavailable"
        }
    }
}

/// MetricKit calls back on its own queue; this object holds no state, converts each payload to plain summaries
/// on that queue and writes them through the nonisolated store. Nothing non-Sendable crosses a boundary.
final class MetricKitSink: NSObject, MXMetricManagerSubscriber, Sendable {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        ingest(payloads)
    }

    func ingest(_ payloads: [MXDiagnosticPayload]) {
        let home = NSHomeDirectory()
        let summaries = payloads.flatMap { Self.summaries(of: $0, home: home) }
        DiagnosticsCenter.storeMetricKitSummaries(summaries)
    }

    private static func summaries(of payload: MXDiagnosticPayload, home: String) -> [DiagnosticsRules.CrashSummary] {
        var out: [DiagnosticsRules.CrashSummary] = []
        for d in payload.crashDiagnostics ?? [] {
            var s = base(d, kind: "crash", time: payload.timeStampEnd, home: home)
            s.exceptionType = d.exceptionType.map { "EXC \($0)" }
            s.signal = d.signal.map { "signal \($0)" }
            s.termination = d.terminationReason.map { String(DiagnosticsRules.redact($0, home: home).prefix(120)) }
            out.append(s)
        }
        for d in payload.hangDiagnostics ?? [] {
            var s = base(d, kind: "hang", time: payload.timeStampEnd, home: home)
            s.hangSeconds = d.hangDuration.converted(to: .seconds).value
            out.append(s)
        }
        for d in payload.cpuExceptionDiagnostics ?? [] {
            out.append(base(d, kind: "cpu", time: payload.timeStampEnd, home: home))
        }
        for d in payload.diskWriteExceptionDiagnostics ?? [] {
            out.append(base(d, kind: "diskWrite", time: payload.timeStampEnd, home: home))
        }
        return out
    }

    private static func base(_ d: MXDiagnostic, kind: String, time: Date, home: String) -> DiagnosticsRules.CrashSummary {
        let meta = d.metaData
        return DiagnosticsRules.CrashSummary(
            source: "metrickit", kind: kind, time: time,
            appVersion: d.applicationVersion, build: meta.applicationBuildVersion,
            osVersion: meta.osVersion, model: meta.deviceType, cpu: meta.platformArchitecture,
            exceptionType: nil, signal: nil, termination: nil, hangSeconds: nil,
            frames: frames(of: d, home: home))
    }

    /// MetricKit's call stacks are unsymbolicated: binary name + offset is what there is, and all a developer needs.
    private static func frames(of d: MXDiagnostic, home: String) -> [String] {
        let tree: MXCallStackTree?
        switch d {
        case let c as MXCrashDiagnostic: tree = c.callStackTree
        case let h as MXHangDiagnostic: tree = h.callStackTree
        case let c as MXCPUExceptionDiagnostic: tree = c.callStackTree
        case let w as MXDiskWriteExceptionDiagnostic: tree = w.callStackTree
        default: tree = nil
        }
        guard let data = tree?.jsonRepresentation(),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]] else { return [] }
        let chosen = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        var lines: [String] = []
        var level = (chosen?["callStackRootFrames"] as? [[String: Any]])?.first
        while let frame = level, lines.count < DiagnosticsRules.maxFrames {
            let binary = frame["binaryName"] as? String ?? "?"
            let offset = frame["offsetIntoBinaryTextSegment"] as? Int ?? 0
            lines.append(String(DiagnosticsRules.redact("\(binary)  +0x\(String(offset, radix: 16))", home: home).prefix(240)))
            level = (frame["subFrames"] as? [[String: Any]])?.first
        }
        return lines
    }
}
