import AppKit
import Foundation

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

    // MARK: Settings (the ONE reader of this key — FeatureKeyDefaultsTests)

    var enabled: Bool { UserDefaults.standard.object(forKey: "notch.nowPlaying") as? Bool ?? false }

    func applySettings() {
        if enabled { start() } else { stop() }
    }

    /// A track is known — the badge and the hover peek may show it.
    var hasTrack: Bool { snapshot?.hasTrack == true }

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
        guard FileManager.default.fileExists(atPath: helper.path) else { fail(.missingHelper); return }
        guard FileManager.default.isExecutableFile(atPath: Self.perlPath) else { fail(.missingPerl); return }

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
        do { try p.run() } catch { fail(.gaveUp); return }
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
        restartWork?.cancel(); restartWork = nil
        helloWork?.cancel(); helloWork = nil
        if let p = process {
            process = nil
            let gen = generation
            stopping[gen] = p
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            try? stdinPipe?.fileHandleForWriting.close()          // the helper exits on EOF
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    if let late = self.stopping.removeValue(forKey: gen), late.isRunning { late.terminate() }
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

    /// The app that is playing, from the pid the helper reports.
    var playerApp: NSRunningApplication? {
        guard let pid = snapshot?.pid, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    func openPlayer() {
        playerApp?.activate(options: [.activateAllWindows])
    }
}
