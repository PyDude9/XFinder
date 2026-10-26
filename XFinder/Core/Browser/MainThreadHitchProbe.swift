import Foundation
import os

/// XF-T32 W0 (builder `hitch`): Debug-only main-thread hitch probe. Contract §C.
///
/// A background `Thread` pings `DispatchQueue.main` every `HitchRules.pingInterval` and waits for the answer.
/// If the answer is late by `HitchRules.threshold` the hitch is still in progress, so that is the moment a
/// `sample(1)` capture shows the stuck stack (rate limited by `HitchRules.shouldSample`). When main finally
/// answers, the latency is reported on main. Release builds: `start()` is a no-op.
@MainActor final class MainThreadHitchProbe {
    static let shared: MainThreadHitchProbe = MainThreadHitchProbe()
    private(set) var recent: [HitchRules.Hitch] = []
    var onHitch: ((HitchRules.Hitch) -> Void)?

    private let state: HitchProbeState = HitchProbeState()
    private let logger: Logger = Logger(subsystem: "com.xfinder.app", category: "hitch")

    func start() {
        #if DEBUG
        guard let generation: UInt64 = state.beginRun() else { return }
        let pinger: HitchPinger = HitchPinger(state: state, generation: generation, probe: self)
        let thread: Thread = Thread { pinger.run() }
        thread.name = "com.xfinder.hitch-probe"
        thread.qualityOfService = .utility
        thread.start()
        #endif
    }

    func stop() {
        state.endRun()
    }

    /// Called on main by the pinger once main answered a ping.
    fileprivate func record(latency: TimeInterval, sentAt: Date) {
        guard HitchRules.isHitch(latency: latency) else { return }
        let hitch: HitchRules.Hitch = HitchRules.Hitch(at: sentAt, latency: latency)
        recent = HitchRules.pruned(recent + [hitch])
        let milliseconds: Int = Int((latency * 1000).rounded())
        logger.warning("main thread hitch \(milliseconds, privacy: .public) ms")
        onHitch?(hitch)
    }
}

// MARK: - Shared state (lock-protected, Sendable without @unchecked)

/// Run generation + sample history, shared by main and the pinger thread.
private final class HitchProbeState: Sendable {
    private struct Snapshot {
        var isRunning: Bool = false
        var generation: UInt64 = 0
        var sampleDates: [Date] = []
    }

    private let lock: OSAllocatedUnfairLock<Snapshot> = OSAllocatedUnfairLock(initialState: Snapshot())

    /// Starts a new run; nil when one is already running.
    func beginRun() -> UInt64? {
        lock.withLock { (snapshot: inout Snapshot) -> UInt64? in
            guard !snapshot.isRunning else { return nil }
            snapshot.isRunning = true
            snapshot.generation &+= 1
            return snapshot.generation
        }
    }

    /// Ends the current run; a pinger of that run exits at its next check.
    func endRun() {
        lock.withLock { (snapshot: inout Snapshot) -> Void in
            snapshot.isRunning = false
        }
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        lock.withLock { (snapshot: inout Snapshot) -> Bool in
            snapshot.isRunning && snapshot.generation == generation
        }
    }

    /// Reserves a sample slot (and records it) when the hourly budget allows.
    func reserveSample(now: Date) -> Bool {
        lock.withLock { (snapshot: inout Snapshot) -> Bool in
            guard HitchRules.shouldSample(now: now, previousSamples: snapshot.sampleDates) else { return false }
            snapshot.sampleDates = snapshot.sampleDates.filter { (date: Date) -> Bool in
                abs(now.timeIntervalSince(date)) < HitchRules.sampleWindow
            } + [now]
            return true
        }
    }
}

// MARK: - Pinger (background thread)

/// The loop the background thread runs. Holds the probe weakly so the thread never keeps it alive.
private final class HitchPinger: Sendable {
    private let state: HitchProbeState
    private let generation: UInt64
    private weak let probe: MainThreadHitchProbe?

    init(state: HitchProbeState, generation: UInt64, probe: MainThreadHitchProbe) {
        self.state = state
        self.generation = generation
        self.probe = probe
    }

    func run() {
        while state.isCurrent(generation) {
            pingOnce()
            guard state.isCurrent(generation) else { return }
            Thread.sleep(forTimeInterval: HitchRules.pingInterval)
        }
    }

    private func pingOnce() {
        let answered: DispatchSemaphore = DispatchSemaphore(value: 0)
        let sentUptime: UInt64 = DispatchTime.now().uptimeNanoseconds
        let sentAt: Date = Date()
        let generation: UInt64 = self.generation
        let state: HitchProbeState = self.state
        DispatchQueue.main.async { [weak probe] in
            let latency: TimeInterval = Self.seconds(since: sentUptime)
            answered.signal()
            guard state.isCurrent(generation) else { return }
            MainActor.assumeIsolated {
                probe?.record(latency: latency, sentAt: sentAt)
            }
        }
        if answered.wait(timeout: .now() + HitchRules.threshold) == .timedOut {
            // Main is stuck right now — capture its stack while it still is.
            if state.isCurrent(generation), state.reserveSample(now: Date()) {
                HitchSampler.capture(pid: ProcessInfo.processInfo.processIdentifier, at: Date())
            }
            answered.wait()
        }
    }

    private static func seconds(since uptimeNanoseconds: UInt64) -> TimeInterval {
        let now: UInt64 = DispatchTime.now().uptimeNanoseconds
        guard now >= uptimeNanoseconds else { return 0 }
        return TimeInterval(now - uptimeNanoseconds) / 1_000_000_000
    }
}

// MARK: - sample(1)

/// Runs `/usr/bin/sample <pid> 1 -file …/Diagnostics/hitch-<ISO8601>.txt` on a utility queue.
private enum HitchSampler {
    private static let logger: Logger = Logger(subsystem: "com.xfinder.app", category: "hitch")

    static func capture(pid: Int32, at date: Date) {
        DispatchQueue.global(qos: .utility).async {
            guard let output: URL = outputURL(at: date) else { return }
            run(pid: pid, output: output)
        }
    }

    private static func outputURL(at date: Date) -> URL? {
        let fileManager: FileManager = FileManager.default
        guard let support: URL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory: URL = support
            .appendingPathComponent("XFinder", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("hitch sample: cannot create Diagnostics folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return uniqueFile(in: directory, stem: "hitch-" + timestamp(date))
    }

    /// Basic ISO 8601 (no ':' — Finder shows it as '/'), e.g. 20261026T143501Z.
    private static func timestamp(_ date: Date) -> String {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Never overwrites an earlier capture taken in the same second.
    private static func uniqueFile(in directory: URL, stem: String) -> URL {
        var candidate: URL = directory.appendingPathComponent(stem + ".txt")
        var suffix: Int = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-\(suffix).txt")
            suffix += 1
        }
        return candidate
    }

    private static func run(pid: Int32, output: URL) {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [String(pid), "1", "-file", output.path]
        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.error("hitch sample: cannot launch sample: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Read before waiting: a full pipe would otherwise block `sample` forever.
        let transcript: Data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            logger.notice("hitch sample written: \(output.lastPathComponent, privacy: .public)")
        } else {
            let message: String = String(decoding: transcript.prefix(512), as: UTF8.self)
            logger.error("hitch sample failed (\(process.terminationStatus, privacy: .public)): \(message, privacy: .public)")
        }
    }
}
