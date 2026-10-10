import Foundation

/// The pure half of "export / import my settings". Job: *"set up a second Mac the way my first one
/// is, or restore after a reinstall."*
///
/// Two rules shape everything here, and both are about what must NOT travel:
///
/// * **Only settings.** XFinder's defaults domain also holds user DATA (clipboard pinboards, notes,
///   action history, speed-test history), window frames, status-item positions and migration flags.
///   Data has its own exporters, frames and positions are per-machine, and a migration flag copied
///   to a fresh Mac would make it skip a migration it needs.
/// * **An import file is untrusted input.** It is a plain JSON file anyone can hand you, so the
///   import side applies the SAME allow-rules as export instead of trusting that a file produced
///   by XFinder only contains exportable keys. A crafted file must not be able to set `startPage`,
///   an `NS…` system key or a migration flag.
///
/// API keys are not in UserDefaults (they live in the Keychain), so they are never exported.
enum SettingsTransfer {

    static let format = "xfinder-settings"
    static let version = 1
    /// A real export is a few KB; refusing megabytes stops a pasted-wrong-file from being parsed.
    static let maxFileBytes = 1_000_000

    // MARK: Values

    enum Value: Equatable {
        case bool(Bool), int(Int), double(Double), string(String), data(Data)
    }

    /// A UserDefaults value as one of the supported kinds. nil for arrays, dictionaries, dates.
    static func value(from any: Any) -> Value? {
        switch any {
        case let d as Data: return .data(d)
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return CFNumberIsFloatType(n) ? .double(n.doubleValue) : .int(n.intValue)
        default: return nil
        }
    }

    // MARK: What may travel

    private static let excludedPrefixes = [
        "NS", "Apple", "com.apple", "XFinder.",            // system keys, window geometry, USER DATA
        "onboarding.", "startPage",                         // per-install state / a debug launch hook
        "general.automationVerified", "menubar.guidanceShown",
        "mouseGestures.lastTapState", "mouseGestures.migrated", "mouseGestures.triggerMigrated",
        "AppleLanguages",
    ]
    /// Binary values that ARE configuration (everything else binary is data or per-machine state).
    private static let configBlobKeys: Set<String> = [
        "mouseGestures.configuration.v1", "quickSearch.quicklinks", "quicklinks.data",
    ]

    enum Verdict: Equatable { case transfer, notASetting, machineSpecific }

    static func verdict(key: String, value: Value) -> Verdict {
        if excludedPrefixes.contains(where: { key.hasPrefix($0) }) { return .notASetting }
        switch value {
        case .data: return configBlobKeys.contains(key) ? .transfer : .notASetting
        // An absolute path (a sync source, a save folder) names a place on THIS Mac.
        case .string(let s): return (s.hasPrefix("/") || s.hasPrefix("~")) ? .machineSpecific : .transfer
        default: return .transfer
        }
    }

    // MARK: Export

    struct ExportResult {
        var data: Data
        var exported: Int
        var skippedMachineSpecific: Int
    }

    private struct Entry: Codable { var t: String; var v: String }
    private struct Envelope: Codable {
        var format: String
        var version: Int
        var app: String
        var exportedAt: String
        var settings: [String: Entry]
    }

    private static func encode(_ v: Value) -> Entry {
        switch v {
        case .bool(let b): return Entry(t: "bool", v: b ? "true" : "false")
        case .int(let i): return Entry(t: "int", v: String(i))
        case .double(let d): return Entry(t: "double", v: String(d))
        case .string(let s): return Entry(t: "string", v: s)
        case .data(let d): return Entry(t: "data", v: d.base64EncodedString())
        }
    }

    private static func decode(_ e: Entry) -> Value? {
        switch e.t {
        case "bool": return e.v == "true" ? .bool(true) : (e.v == "false" ? .bool(false) : nil)
        case "int": return Int(e.v).map(Value.int)
        case "double": return Double(e.v).flatMap { $0.isFinite ? Value.double($0) : nil }
        case "string": return .string(e.v)
        case "data": return Data(base64Encoded: e.v).map(Value.data)
        default: return nil
        }
    }

    static func export(defaults: [String: Any], appVersion: String, date: Date) throws -> ExportResult {
        var settings: [String: Entry] = [:]
        var skipped = 0
        for (key, any) in defaults {
            guard let v = value(from: any) else { continue }
            switch verdict(key: key, value: v) {
            case .transfer: settings[key] = encode(v)
            case .machineSpecific: skipped += 1
            case .notASetting: break
            }
        }
        let env = Envelope(format: format, version: version, app: appVersion,
                           exportedAt: ISO8601DateFormatter().string(from: date), settings: settings)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]   // stable, diff-friendly
        return ExportResult(data: try enc.encode(env), exported: settings.count, skippedMachineSpecific: skipped)
    }

    // MARK: Import

    enum ImportError: Error, Equatable {
        case tooLarge
        case notASettingsFile
        case newerThanThisApp(Int)
        case empty
    }

    struct ImportPlan: Equatable {
        var settings: [String: Value]
        var appVersion: String
        /// Keys in the file that were refused (not settings, machine-specific, malformed value).
        var rejected: [String]
    }

    static func parse(_ data: Data) -> Result<ImportPlan, ImportError> {
        guard data.count <= maxFileBytes else { return .failure(.tooLarge) }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data), env.format == format else {
            return .failure(.notASettingsFile)
        }
        guard env.version <= version else { return .failure(.newerThanThisApp(env.version)) }
        var accepted: [String: Value] = [:]
        var rejected: [String] = []
        for (key, entry) in env.settings {
            guard let v = decode(entry), verdict(key: key, value: v) == .transfer else { rejected.append(key); continue }
            accepted[key] = v
        }
        guard !accepted.isEmpty else { return .failure(.empty) }
        return .success(ImportPlan(settings: accepted, appVersion: env.app, rejected: rejected.sorted()))
    }

    @discardableResult
    static func apply(_ plan: ImportPlan, to defaults: UserDefaults) -> Int {
        for (key, v) in plan.settings {
            switch v {
            case .bool(let b): defaults.set(b, forKey: key)
            case .int(let i): defaults.set(i, forKey: key)
            case .double(let d): defaults.set(d, forKey: key)
            case .string(let s): defaults.set(s, forKey: key)
            case .data(let d): defaults.set(d, forKey: key)
            }
        }
        return plan.settings.count
    }
}
