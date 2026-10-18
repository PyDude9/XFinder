import Foundation
import AppKit

/// Đồng bộ thư mục — one-way folder mirroring (source → destination).
///
/// Uses `rsync -a` with `--delete` optional, so it is incremental: only
/// changed files move. One-way by design — two-way sync needs conflict
/// resolution and a change journal, and a half-built version of that loses
/// data. The UI says "một chiều" rather than implying more than it does.
///
/// Triggers: manual, on-change (an `FSEventStream`-backed `DispatchSource`
/// watch with debounce), and daily at a chosen hour.
@MainActor
@Observable
final class FolderSyncController {
    static let shared = FolderSyncController()

    struct Pair: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var sourcePath: String
        var destPath: String
        /// Mirror deletions too. Off by default — deleting is irreversible.
        var deleteExtras: Bool = false
        var onChange: Bool = true
        var daily: Bool = false
        var dailyHour: Int = 22
        var lastRun: Date?
        var lastResult: String?

        var sourceName: String { URL(fileURLWithPath: sourcePath).lastPathComponent }
        var destName: String { URL(fileURLWithPath: destPath).lastPathComponent }
    }

    private(set) var pairs: [Pair] = []
    private(set) var runningIDs: Set<UUID> = []
    var lastError: String?

    private let key = "XFinder.FolderSyncPairs"
    private var watchers: [UUID: DispatchSourceFileSystemObject] = [:]
    private var debounce: [UUID: Task<Void, Never>] = [:]
    private var dailyTimer: Timer?

    private init() { load() }

    private var autoEnabled: Bool {
        UserDefaults.standard.object(forKey: "sync.autoEnabled") as? Bool ?? false
    }

    // MARK: Lifecycle

    func applySettings() {
        stopWatching()
        guard autoEnabled else { return }
        for pair in pairs where pair.onChange { startWatching(pair) }
        // The 60 s check only exists when some pair is on a daily schedule (audit 2026-10-18, P-4); on-change pairs are
        // served by their DispatchSource watchers alone.
        if pairs.contains(where: { $0.daily }) { startDailyTimer() }
    }

    private func stopWatching() {
        for (_, w) in watchers { w.cancel() }
        watchers.removeAll()
        dailyTimer?.invalidate()
        dailyTimer = nil
    }

    /// Watches the source directory; a change schedules a debounced sync so a
    /// burst of edits produces one run, not hundreds.
    private func startWatching(_ pair: Pair) {
        let fd = open(pair.sourcePath, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleDebounced(pair.id) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers[pair.id] = src
    }

    private func scheduleDebounced(_ id: UUID) {
        debounce[id]?.cancel()
        debounce[id] = Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                if let pair = self.pairs.first(where: { $0.id == id }) {
                    Task { await self.run(pair) }
                }
            }
        }
    }

    /// Checks once a minute whether a daily pair is due this hour.
    private func startDailyTimer() {
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDaily() }
        }
        RunLoop.main.add(t, forMode: .common)
        dailyTimer = t
    }

    private func checkDaily() {
        let cal = Calendar.current
        let now = Date()
        for pair in pairs where pair.daily {
            guard cal.component(.hour, from: now) == pair.dailyHour else { continue }
            // Once per day: skip if the last run was already today.
            if let last = pair.lastRun, cal.isDate(last, inSameDayAs: now) { continue }
            Task { await run(pair) }
        }
    }

    // MARK: CRUD

    func add(source: URL, dest: URL) {
        guard source.path != dest.path else {
            lastError = L10n.t("Nguồn và đích không được trùng nhau.")
            return
        }
        // A destination inside the source would recurse forever.
        if dest.path.hasPrefix(source.path + "/") {
            lastError = L10n.t("Thư mục đích nằm trong thư mục nguồn — sẽ lặp vô hạn.")
            return
        }
        lastError = nil
        pairs.append(Pair(sourcePath: source.path, destPath: dest.path))
        persist()
        applySettings()
    }

    func remove(_ pair: Pair) {
        watchers[pair.id]?.cancel()
        watchers[pair.id] = nil
        pairs.removeAll { $0.id == pair.id }
        persist()
    }

    func update(_ pair: Pair) {
        guard let idx = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[idx] = pair
        persist()
        applySettings()
    }

    // MARK: Run

    @discardableResult
    func run(_ pair: Pair) async -> Bool {
        guard !runningIDs.contains(pair.id) else { return false }
        runningIDs.insert(pair.id)
        defer { runningIDs.remove(pair.id) }

        let fm = FileManager.default
        guard fm.fileExists(atPath: pair.sourcePath) else {
            record(pair, L10n.t("Nguồn không tồn tại."))
            return false
        }
        if !fm.fileExists(atPath: pair.destPath) {
            try? fm.createDirectory(atPath: pair.destPath, withIntermediateDirectories: true)
        }

        // Trailing slash on the source copies its *contents*, matching the
        // "mirror this folder into that one" mental model.
        var args = ["-a", "--human-readable"]
        if pair.deleteExtras { args.append("--delete") }
        args.append(pair.sourcePath.hasSuffix("/") ? pair.sourcePath : pair.sourcePath + "/")
        args.append(pair.destPath)

        let result = await Self.runProcess(["/usr/bin/rsync"] + args)
        let summary = result.ok
            ? L10n.t("Đồng bộ xong lúc ") + Self.timeString(Date())
            : L10n.t("Lỗi: ") + result.output.split(separator: "\n").last.map(String.init).orEmpty
        record(pair, summary)
        if result.ok {
            ActionHistoryStore.shared.record(
                kind: "sync",
                summary: "\(L10n.t("Đồng bộ "))\(pair.sourceName) → \(pair.destName)")
        }
        return result.ok
    }

    private func record(_ pair: Pair, _ message: String) {
        guard let idx = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[idx].lastRun = Date()
        pairs[idx].lastResult = message
        persist()
    }

    private nonisolated static func runProcess(_ cmd: [String]) async -> (ok: Bool, output: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cmd[0])
            p.arguments = Array(cmd.dropFirst())
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            guard (try? p.run()) != nil else { return (false, L10n.t("không chạy được rsync")) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
        }.value
    }

    private nonisolated static func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: d)
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Pair].self, from: data) else { return }
        pairs = decoded
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(pairs) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
