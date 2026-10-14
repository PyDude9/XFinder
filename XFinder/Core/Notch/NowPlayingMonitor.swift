import AppKit
import Foundation
import os

/// Runs the Now Playing helper and owns what it reports (B6). The helper is `XFinderNowPlaying.dylib`
/// (built from `Helpers/NowPlaying/nowplaying-adapter.c`) hosted by Apple-signed `/usr/bin/perl` —
/// the only process type mediaremoted still answers for third parties since macOS 15.4 (measured on
/// this Mac, 2026-10-10: nothing for the app, everything inside perl). Data comes back as JSON lines
/// on the child's stdout; the child exits when its stdin closes, so quitting XFinder ends it.
///
/// Cost model: ONE child process (~18 MB RSS measured) alive only while `notch.nowPlaying` is on;
/// it sleeps until mediaremoted notifies it. No timer here. Commands (play/pause/next/previous) go
/// straight from this process — sending was measured to work without the helper.
@MainActor
@Observable
final class NowPlayingMonitor {
    static let shared = NowPlayingMonitor()

    private(set) var snapshot: NowPlaying.Snapshot?
    private(set) var artwork: NSImage?
    private(set) var availability: NowPlaying.Availability = .off
    /// Called on every change (Observation has no publishers; the controller re-renders from this).
    var onChange: (@MainActor () -> Void)?

    private var process: Process?
    /// Bumped per launch; handlers carry it instead of the (non-Sendable) Process so a stale child's
    /// EOF or exit can never be mistaken for the current one.
    private var generation = 0
    private var stopping: [Int: Process] = [:]
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var buffer = Data()
    private var supervisor = NowPlaying.Supervisor()
    private var startedAt: Date?
    private var helloWork: DispatchWorkItem?
    private var restartWork: DispatchWorkItem?

    private init() {}

    private let log = Logger(subsystem: "com.xfinder.app", category: "nowplaying")

    // MARK: Settings (the ONE reader of this key — FeatureKeyDefaultsTests)

    var enabled: Bool { UserDefaults.standard.object(forKey: "notch.nowPlaying") as? Bool ?? false }

    func applySettings() {
        log.info("applySettings enabled=\(self.enabled) process=\(self.process != nil) availability=\(String(describing: self.availability))")
        if enabled { start() } else { stop() }
    }

    /// A track is known AND the helper that reported it is alive — the badge and the hover peek may
    /// show it. Gated on `availability.isLive` so nothing from a dead helper is ever drawn as live.
    var hasTrack: Bool { availability.isLive && snapshot?.hasTrack == true }
    /// The snapshot to display: nil unless the helper is live.
    var liveSnapshot: NowPlaying.Snapshot? { availability.isLive ? snapshot : nil }
    var liveArtwork: NSImage? { availability.isLive ? artwork : nil }

    /// A single stdout line (metadata + base64 artwork) never legitimately approaches this; a line
    /// that does is a runaway publisher, and the buffer is dropped rather than grown without bound.
    static let maxLineBytes = 16 * 1024 * 1024

    static let perlPath = "/usr/bin/perl"
    static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/XFinderNowPlaying.dylib")
    }

    // MARK: Lifecycle

    private func start() {
        guard process == nil, restartWork == nil else { return }
        supervisor = NowPlaying.Supervisor()
        launch()
    }

    private func launch() {
        restartWork = nil
        let helper = Self.helperURL
        guard FileManager.default.fileExists(atPath: helper.path) else { log.error("helper missing at \(helper.path)"); fail(.missingHelper); return }
        guard FileManager.default.isExecutableFile(atPath: Self.perlPath) else { log.error("no perl"); fail(.missingPerl); return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.perlPath)
        p.arguments = ["-e", NowPlaying.hostScript(), helper.path]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        generation += 1
        let gen = generation
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF. Clear the handler HERE or GCD keeps calling it forever at 100 % CPU (a documented
                // bug in another app using the same technique).
                handle.readabilityHandler = nil
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.helperEnded(gen) } }
                return
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(data, gen: gen) } }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.helperEnded(gen) } }
        }
        do { try p.run() } catch { log.error("perl run failed: \(error.localizedDescription)"); fail(.gaveUp); return }
        log.info("helper launched pid=\(p.processIdentifier) gen=\(gen)")
        process = p
        stdinPipe = input
        stdoutPipe = output
        buffer.removeAll()
        startedAt = Date()
        setAvailability(.starting)
        // No hello within 5 s ⇒ the helper is wedged; treat it as an exit (the supervisor decides).
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen, self.availability == .starting else { return }
                self.process?.terminate()
            }
        }
        helloWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func stop() {
        log.info("stop() process=\(self.process != nil) availability=\(String(describing: self.availability))")
        restartWork?.cancel(); restartWork = nil
        helloWork?.cancel(); helloWork = nil
        if let p = process {
            process = nil
            let gen = generation
            stopping[gen] = p
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            try? stdinPipe?.fileHandleForWriting.close()          // the helper exits on EOF
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated {
                    if let late = self?.stopping.removeValue(forKey: gen), late.isRunning { late.terminate() }
                }
            }
        }
        stdinPipe = nil; stdoutPipe = nil
        supervisor = NowPlaying.Supervisor()
        snapshot = nil; artwork = nil
        setAvailability(.off)
    }

    private func fail(_ a: NowPlaying.Availability) {
        snapshot = nil; artwork = nil
        setAvailability(a)
    }

    private func helperEnded(_ gen: Int) {
        guard gen == generation, process != nil else { return }   // a stale handler from a replaced child
        process = nil
        helloWork?.cancel(); helloWork = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdinPipe = nil; stdoutPipe = nil
        guard enabled else { setAvailability(.off); return }
        let uptime = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        log.info("helper ended after \(uptime, format: .fixed(precision: 1)) s")
        // Whatever the helper last said is no longer known — a dead helper reports nothing. Clear
        // BEFORE announcing the restart, or the badge keeps the old track at "playing" opacity.
        snapshot = nil; artwork = nil
        switch supervisor.helperExited(afterUptime: uptime) {
        case .restart(let delay):
            setAvailability(.starting)
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.launch() } }
            restartWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        case .giveUp:
            fail(.gaveUp)
        }
    }

    // MARK: Input

    private func consume(_ data: Data, gen: Int) {
        guard gen == generation, process != nil else { return }
        buffer.append(data)
        if buffer.count > Self.maxLineBytes, !buffer.contains(0x0A) {
            log.error("dropping a \(self.buffer.count)-byte line with no newline — runaway publisher?")
            buffer.removeAll(keepingCapacity: false)
            return
        }
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            handle(NowPlaying.parse(line))
        }
    }

    private func handle(_ line: NowPlaying.Line) {
        switch line {
        case .hello:
            log.info("hello from helper")
            helloWork?.cancel(); helloWork = nil
            setAvailability(.ready)
        case .empty:
            if snapshot != nil || artwork != nil { snapshot = nil; artwork = nil; onChange?() }
        case .snapshot(let s, let art):
            var changed = false
            if let art, let image = NSImage(data: art) { artwork = image; changed = true }
            else if s.artworkID != snapshot?.artworkID, artwork != nil, art == nil, s.artworkID != nil {
                artwork = nil; changed = true                   // a new track whose artwork has not arrived yet
            }
            if s != snapshot { snapshot = s; changed = true }
            if changed { onChange?() }
        case .error:
            // The helper reports its own failure to load; it exits right after, which the supervisor sees.
            break
        case .other:
            break
        }
    }

    private func setAvailability(_ a: NowPlaying.Availability) {
        guard a != availability else { return }
        availability = a
        onChange?()
    }

    // MARK: Commands — MRMediaRemoteSendCommand works from the app itself (measured: toggle/next/previous
    // reached the player from an ad-hoc process while reading was denied)

    enum Command: UInt32 { case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5 }

    private typealias SendFn = @convention(c) (UInt32, CFDictionary?) -> Bool
    private static let send: SendFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let sym = dlsym(h, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(sym, to: SendFn.self)
    }()

    @discardableResult
    func send(_ c: Command) -> Bool {
        Self.send?(c.rawValue, nil) ?? false
    }

    // N8 — seek / shuffle / repeat: three more MediaRemote entry points, resolved the same way and measured to reach
    // the player from an ad-hoc process (NowPlaying.ShuffleMode / RepeatMode carry the numbering).
    private typealias SetDoubleFn = @convention(c) (Double) -> Void
    private typealias SetU32Fn = @convention(c) (UInt32) -> Void
    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let s = dlsym(h, name) else { return nil }
        return unsafeBitCast(s, to: type)
    }
    private static let setElapsed: SetDoubleFn? = symbol("MRMediaRemoteSetElapsedTime", SetDoubleFn.self)
    private static let setShuffle: SetU32Fn? = symbol("MRMediaRemoteSetShuffleMode", SetU32Fn.self)
    private static let setRepeat: SetU32Fn? = symbol("MRMediaRemoteSetRepeatMode", SetU32Fn.self)

    func seek(to seconds: Double) {
        guard let d = snapshot?.duration, d > 0 else { return }
        Self.setElapsed?(min(max(seconds, 0), d))
    }
    func setShuffle(_ m: NowPlaying.ShuffleMode) { Self.setShuffle?(m.rawValue) }
    func setRepeat(_ m: NowPlaying.RepeatMode) { Self.setRepeat?(m.rawValue) }

    /// The app that is playing, from the pid the helper reports.
    var playerApp: NSRunningApplication? {
        guard let pid = snapshot?.pid, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    func openPlayer() {
        // activate(options:) is ignored when called from the notch (not the active app, macOS 14+): open via LaunchServices.
        guard let app = playerApp else { return }
        if let bid = app.bundleIdentifier {
            AgentSessionMonitor.bringForward(bundleID: bid)
        } else if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
    }
}
