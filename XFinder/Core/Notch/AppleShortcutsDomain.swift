import Foundation
import Observation

/// Pure domain types, CLI argument builders, output parser, and `@MainActor` session store
/// for running the user's macOS Apple Shortcuts from the Dynamic Island (Notch).
///
/// Foundation + Observation only (no AppKit/SwiftUI), so the entire state machine and async
/// lifecycle can be unit-tested in `Tests/XFinderLogicTests` with a fake `AppleShortcutsRunning`
/// runner — never executing a real Apple Shortcut in tests.
///
/// Lifecycle contract (for the Coordinator / `NotchSurfaceView`):
/// - `onOpen()`: marks the page active and loads the user's shortcuts (`shortcuts list --show-identifiers`).
///   Never auto-runs any shortcut.
/// - `refresh()`: cancels any in-flight list request and loads a fresh list while the page is active.
/// - `run(_:)`: runs ONLY on explicit user click while the page is active and no shortcut is already running.
///   Consecutive clicks while running are ignored (single-flight).
/// - `cancelRun()`: cancels the in-flight CLI task and invalidates its generation token immediately.
///   Limitation: killing `/usr/bin/shortcuts` stops waiting and tears down the CLI client, but macOS
///   delegates shortcut execution over XPC to `Shortcuts` / `BackgroundShortcutRunner`; already-dispatched
///   actions inside that daemon cannot be guaranteed to roll back or halt mid-step.
/// - `onCloseOrTabSwitch()`: marks the page inactive, bumps generation tokens, cancels in-flight tasks,
///   and guarantees any late/stale reply arriving after a tab switch or close is silently discarded.

// MARK: - Models

struct AppleShortcut: Identifiable, Hashable, Sendable {
    /// Stable UI identity (UUID identifier when reported by `shortcuts list --show-identifiers`,
    /// otherwise the display name, disambiguated if duplicate names appear without identifiers).
    let id: String
    /// Exact user-visible name from Apple Shortcuts (spaces, quotes, shell metacharacters, Unicode preserved).
    let name: String
    /// UUID reported by `shortcuts list --show-identifiers`, when present.
    let identifier: String?

    /// Argument passed to `shortcuts run`. Preferring the UUID keeps the target valid even if the
    /// user renames the shortcut in Shortcuts.app between `list` and `run`.
    var runTarget: String { identifier ?? name }
}

struct AppleShortcutsProcessOutput: Equatable, Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
    let stdoutTruncated: Bool
    let stderrTruncated: Bool

    init(
        exitCode: Int32,
        stdout: Data = Data(),
        stderr: Data = Data(),
        stdoutTruncated: Bool = false,
        stderrTruncated: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
    }
}

enum AppleShortcutsRunnerError: Error, Equatable, Sendable {
    case cliUnavailable(path: String)
    case timedOut(seconds: TimeInterval)
    case cancelled
    case launchFailed(detail: String)
}

protocol AppleShortcutsRunning: Sendable {
    func execute(
        arguments: [String],
        timeout: TimeInterval,
        maxOutputBytes: Int
    ) async -> Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError>
}

// MARK: - CLI Command Builder

enum AppleShortcutsCommand {
    static let defaultExecutablePath = "/usr/bin/shortcuts"

    /// Separate argv array — never interpolated into a shell command string.
    static func listArguments() -> [String] {
        ["list", "--show-identifiers"]
    }

    /// Separate argv array with `--` option terminator so names starting with `-`, spaces,
    /// quotes, or shell metacharacters are passed verbatim to `/usr/bin/shortcuts`.
    static func runArguments(for shortcut: AppleShortcut) -> [String] {
        ["run", "--", shortcut.runTarget]
    }
}

// MARK: - Output & Error Parser

enum AppleShortcutsParser {
    /// Parses stdout from `shortcuts list --show-identifiers`.
    ///
    /// Format emitted by macOS `/usr/bin/shortcuts list --show-identifiers`:
    /// `<Shortcut Name> (<UUID>)` — one entry per line.
    ///
    /// Rules:
    /// - Parses the UUID suffix from the rightmost ` (` ... `)` so parentheses inside the shortcut name
    ///   (e.g. `Backup (Daily) (F8DC56A7-...)`) are preserved intact.
    /// - Preserves internal spaces, quotes, shell metacharacters, and Unicode.
    /// - When `truncated` is true and stdout did not end on a newline boundary, drops the final
    ///   partial line so a sliced name or UUID is never surfaced.
    /// - Deduplicates identical UUIDs; disambiguates duplicate names without UUIDs so SwiftUI IDs stay unique.
    static func parseListOutput(_ data: Data, truncated: Bool) -> [AppleShortcut] {
        guard !data.isEmpty else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
        }

        if truncated, !text.hasSuffix("\n"), !rawLines.isEmpty {
            rawLines.removeLast()
        }

        var result: [AppleShortcut] = []
        var seenIdentifiers: Set<String> = []
        var nameCounts: [String: Int] = [:]

        for line in rawLines {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let (name, identifier) = splitNameAndUUID(line)

            if let identifier {
                let normalizedID = identifier.uppercased()
                guard seenIdentifiers.insert(normalizedID).inserted else { continue }
                result.append(AppleShortcut(id: normalizedID, name: name, identifier: identifier))
            } else {
                let count = nameCounts[name, default: 0] + 1
                nameCounts[name] = count
                let uniqueID = count == 1 ? name : "\(name)#\(count)"
                result.append(AppleShortcut(id: uniqueID, name: name, identifier: nil))
            }
        }

        return result
    }

    /// Splits `"<name> (<36-char-UUID>)"` from the rightmost UUID group.
    static func splitNameAndUUID(_ line: String) -> (name: String, identifier: String?) {
        guard line.hasSuffix(")"), line.count >= 40 else {
            return (line, nil)
        }
        // Suffix length is `" ("` (2) + UUID (36) + `")"` (1) = 39 chars.
        let suffixStart = line.index(line.endIndex, offsetBy: -39)
        let suffix = line[suffixStart...]
        guard suffix.hasPrefix(" ("), suffix.hasSuffix(")") else {
            return (line, nil)
        }
        let uuidStart = line.index(suffixStart, offsetBy: 2)
        let uuidEnd = line.index(before: line.endIndex)
        let candidate = String(line[uuidStart..<uuidEnd])
        guard isCanonicalUUID(candidate) else {
            return (line, nil)
        }
        let name = String(line[..<suffixStart])
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (line, nil)
        }
        return (name, candidate)
    }

    /// Validates canonical 8-4-4-4-12 hexadecimal UUID format.
    static func isCanonicalUUID(_ value: String) -> Bool {
        guard value.count == 36 else { return false }
        let bytes = Array(value.utf8)
        let hyphenIndices: Set<Int> = [8, 13, 18, 23]
        for (idx, byte) in bytes.enumerated() {
            if hyphenIndices.contains(idx) {
                if byte != 45 { return false } // '-'
            } else {
                let isDigit = (48...57).contains(byte)      // 0-9
                let isUpperHex = (65...70).contains(byte)   // A-F
                let isLowerHex = (97...102).contains(byte)  // a-f
                if !(isDigit || isUpperHex || isLowerHex) { return false }
            }
        }
        return true
    }

    /// Detects macOS `shortcuts` CLI "shortcut not found" stderr messages (e.g. after rename/delete).
    static func isNotFoundError(stderr: String) -> Bool {
        let lower = stderr.lowercased()
        let markers = [
            "couldn't find shortcut",
            "could not find shortcut",
            "couldn’t find shortcut",
            "could not be found",
            "no shortcut named",
            "doesn't exist",
            "does not exist"
        ]
        return markers.contains { lower.contains($0) }
    }

    /// Trims, flattens newlines, and caps stderr detail so large process output never floods the Notch UI.
    static func sanitizeErrorDetail(_ data: Data, maxCharacters: Int = 180) -> String? {
        guard !data.isEmpty else { return nil }
        let raw = String(decoding: data, as: UTF8.self)
        let compact = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        guard !compact.isEmpty else { return nil }
        guard compact.count > maxCharacters else { return compact }
        let cutoff = compact.index(compact.startIndex, offsetBy: max(1, maxCharacters - 1))
        return String(compact[..<cutoff]) + "…"
    }
}

// MARK: - Domain State & Errors

enum AppleShortcutsError: Error, Equatable, Sendable {
    case cliUnavailable
    case timedOut
    case shortcutNotFound(name: String)
    case commandFailed(exitCode: Int32, detail: String?)
    case launchFailed(detail: String?)
}

enum AppleShortcutsLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(truncated: Bool)
    case failed(AppleShortcutsError)
}

enum AppleShortcutsRunState: Equatable, Sendable {
    case idle
    case running(AppleShortcut)
    case succeeded(AppleShortcut)
    case cancelled(AppleShortcut)
    case failed(AppleShortcut, AppleShortcutsError)
}

// MARK: - MainActor Store (Lifecycle & Single-Flight Orchestration)

@MainActor
@Observable
final class AppleShortcutsStore {
    nonisolated static let defaultListTimeout: TimeInterval = 10
    nonisolated static let defaultRunTimeout: TimeInterval = 30
    nonisolated static let defaultMaxListOutputBytes: Int = 512 * 1024
    nonisolated static let defaultMaxRunOutputBytes: Int = 64 * 1024

    private(set) var shortcuts: [AppleShortcut] = []
    private(set) var loadState: AppleShortcutsLoadState = .idle
    private(set) var runState: AppleShortcutsRunState = .idle
    private(set) var isPageActive: Bool = false

    private let runner: any AppleShortcutsRunning
    private let listTimeout: TimeInterval
    private let runTimeout: TimeInterval
    private let maxListOutputBytes: Int
    private let maxRunOutputBytes: Int

    private var pageGeneration: UInt64 = 0
    private var listGeneration: UInt64 = 0
    private var runGeneration: UInt64 = 0
    private var lastLoadedTruncated: Bool = false

    private var listTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?

    init(
        runner: any AppleShortcutsRunning,
        listTimeout: TimeInterval = AppleShortcutsStore.defaultListTimeout,
        runTimeout: TimeInterval = AppleShortcutsStore.defaultRunTimeout,
        maxListOutputBytes: Int = AppleShortcutsStore.defaultMaxListOutputBytes,
        maxRunOutputBytes: Int = AppleShortcutsStore.defaultMaxRunOutputBytes
    ) {
        self.runner = runner
        self.listTimeout = listTimeout
        self.runTimeout = runTimeout
        self.maxListOutputBytes = maxListOutputBytes
        self.maxRunOutputBytes = maxRunOutputBytes
    }

    var isLoading: Bool {
        loadState == .loading
    }

    var isRunning: Bool {
        if case .running = runState { return true }
        return false
    }

    var runningShortcutID: String? {
        if case .running(let shortcut) = runState { return shortcut.id }
        return nil
    }

    // MARK: Lifecycle

    /// Called when the Shortcuts page opens in the Dynamic Island.
    /// Loads the user's shortcuts (coalescing if already loading in this active session).
    /// Never runs any shortcut automatically.
    func onOpen() {
        let wasActive = isPageActive
        isPageActive = true
        if wasActive && isLoading {
            return
        }
        startListLoad()
    }

    /// Called when the user switches away to another Notch tab or closes/collapses the Dynamic Island.
    /// Invalidates all in-flight generations and cancels pending CLI tasks so late replies are dropped.
    func onCloseOrTabSwitch() {
        isPageActive = false
        pageGeneration &+= 1
        listGeneration &+= 1
        runGeneration &+= 1

        listTask?.cancel()
        listTask = nil
        runTask?.cancel()
        runTask = nil

        if loadState == .loading {
            loadState = shortcuts.isEmpty ? .idle : .loaded(truncated: lastLoadedTruncated)
        }
        if case .running = runState {
            runState = .idle
        }
    }

    /// Explicit user refresh. Cancels any in-flight list fetch and starts a fresh one.
    func refresh() {
        guard isPageActive else { return }
        startListLoad()
    }

    /// Runs the selected shortcut. Only called from an explicit user tap.
    /// Ignores consecutive clicks while a shortcut is already running (single-flight).
    func run(_ shortcut: AppleShortcut) {
        guard isPageActive else { return }
        guard !isRunning else { return }

        runGeneration &+= 1
        let capturedPageGen = pageGeneration
        let capturedRunGen = runGeneration
        let arguments = AppleShortcutsCommand.runArguments(for: shortcut)

        runState = .running(shortcut)
        runTask?.cancel()

        runTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.runner.execute(
                arguments: arguments,
                timeout: self.runTimeout,
                maxOutputBytes: self.maxRunOutputBytes
            )
            self.applyRunResult(
                result,
                for: shortcut,
                pageGen: capturedPageGen,
                runGen: capturedRunGen
            )
        }
    }

    /// Cancels the currently running shortcut CLI process and marks the run as cancelled immediately.
    func cancelRun() {
        guard case .running(let shortcut) = runState else { return }
        runGeneration &+= 1
        runTask?.cancel()
        runTask = nil
        runState = .cancelled(shortcut)
    }

    /// Dismisses non-running run status banners (succeeded / cancelled / failed).
    func clearRunFeedback() {
        guard !isRunning else { return }
        runState = .idle
    }

    // MARK: Internal Execution

    private func startListLoad() {
        listTask?.cancel()
        listGeneration &+= 1
        let capturedPageGen = pageGeneration
        let capturedListGen = listGeneration
        let arguments = AppleShortcutsCommand.listArguments()

        loadState = .loading

        listTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.runner.execute(
                arguments: arguments,
                timeout: self.listTimeout,
                maxOutputBytes: self.maxListOutputBytes
            )
            self.applyListResult(
                result,
                pageGen: capturedPageGen,
                listGen: capturedListGen
            )
        }
    }

    private func applyListResult(
        _ result: Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError>,
        pageGen: UInt64,
        listGen: UInt64
    ) {
        guard isPageActive, pageGen == pageGeneration, listGen == listGeneration else {
            return
        }
        listTask = nil

        switch result {
        case .success(let output):
            if output.exitCode == 0 {
                let parsed = AppleShortcutsParser.parseListOutput(
                    output.stdout,
                    truncated: output.stdoutTruncated
                )
                shortcuts = parsed
                lastLoadedTruncated = output.stdoutTruncated
                loadState = .loaded(truncated: output.stdoutTruncated)
            } else {
                let detail = AppleShortcutsParser.sanitizeErrorDetail(output.stderr)
                loadState = .failed(.commandFailed(exitCode: output.exitCode, detail: detail))
            }
        case .failure(let error):
            switch error {
            case .cliUnavailable:
                loadState = .failed(.cliUnavailable)
            case .timedOut:
                loadState = .failed(.timedOut)
            case .cancelled:
                loadState = shortcuts.isEmpty ? .idle : .loaded(truncated: lastLoadedTruncated)
            case .launchFailed(let detail):
                loadState = .failed(.launchFailed(detail: detail.isEmpty ? nil : detail))
            }
        }
    }

    private func applyRunResult(
        _ result: Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError>,
        for shortcut: AppleShortcut,
        pageGen: UInt64,
        runGen: UInt64
    ) {
        guard isPageActive, pageGen == pageGeneration, runGen == runGeneration else {
            return
        }
        runTask = nil

        switch result {
        case .success(let output):
            if output.exitCode == 0 {
                runState = .succeeded(shortcut)
            } else {
                let stderrText = String(decoding: output.stderr, as: UTF8.self)
                if AppleShortcutsParser.isNotFoundError(stderr: stderrText) {
                    runState = .failed(shortcut, .shortcutNotFound(name: shortcut.name))
                } else {
                    let detail = AppleShortcutsParser.sanitizeErrorDetail(output.stderr)
                    runState = .failed(shortcut, .commandFailed(exitCode: output.exitCode, detail: detail))
                }
            }
        case .failure(let error):
            switch error {
            case .cliUnavailable:
                runState = .failed(shortcut, .cliUnavailable)
            case .timedOut:
                runState = .failed(shortcut, .timedOut)
            case .cancelled:
                runState = .cancelled(shortcut)
            case .launchFailed(let detail):
                runState = .failed(shortcut, .launchFailed(detail: detail.isEmpty ? nil : detail))
            }
        }
    }
}
