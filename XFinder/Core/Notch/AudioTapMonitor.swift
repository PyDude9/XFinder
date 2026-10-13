import Foundation
import CoreAudio
import AudioToolbox
import os

/// §3b #21 — the live half of the waveform: a CoreAudio process tap on the PLAYER's process only (the Now Playing
/// helper reports its pid), so notification sounds never move the bars. ONE reader of `notch.nowPlaying.waveform`
/// (default off: it needs the system-audio recording permission, asked by macOS the first time the tap starts).
///
/// Cost rules: the tap exists only while the switch is on, a waveform is on screen and the track is playing; every
/// CoreAudio call runs off the main actor (the first start blocks ~40 s on the permission prompt — measured); the IO
/// block computes one RMS per buffer and hops to the main actor at most 30 times a second with a plain Float.
@MainActor
@Observable
final class AudioTapMonitor {
    static let shared = AudioTapMonitor()
    private init() {}

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "notch.nowPlaying.waveform") as? Bool ?? false }

    private(set) var meter = AudioWaveform.Meter()
    private(set) var looksDenied = false
    private(set) var isRunning = false
    /// macOS 14.2 added process taps; below that the switch explains itself.
    static var isSupported: Bool { if #available(macOS 14.2, *) { return true } else { return false } }

    @ObservationIgnored private var visible = false
    @ObservationIgnored private var currentPID: pid_t?
    @ObservationIgnored private var silence = AudioWaveform.SilenceWatch()
    /// The pid already given its one rebuild (see `scheduleRetry`).
    @ObservationIgnored private var retriedPID: pid_t?
    /// Bumped to cancel a pending linger stop.
    @ObservationIgnored private var lingerToken = 0
    @ObservationIgnored private var lingering = false
    /// How long a hidden waveform keeps its tap while the same track plays.
    static let linger: TimeInterval = 8
    @ObservationIgnored private let log = Logger(subsystem: "com.xfinder.app", category: "Waveform")
    /// The running tap's CoreAudio objects — touched only on `ioQueue`.
    nonisolated private static let ioQueue = DispatchQueue(label: "com.xfinder.waveform.io", qos: .userInteractive)
    nonisolated private static let handles = OSAllocatedUnfairLock<Handles?>(initialState: nil)
    nonisolated private static let lastSent = OSAllocatedUnfairLock<Double>(initialState: 0)

    struct Handles: Sendable {
        let tap: AudioObjectID
        let device: AudioObjectID
        let proc: AudioDeviceIOProcID
    }

    /// Called by the notch controller whenever what is on screen or what is playing changes.
    func update(waveformVisible: Bool) {
        visible = waveformVisible
        let snap = NowPlayingMonitor.shared.liveSnapshot
        let playing = isEnabled && Self.isSupported && (snap?.playing ?? false) ? snap?.pid : nil
        let want = waveformVisible ? playing : nil
        if want != nil, want == currentPID { cancelLinger(); return }
        // Hidden while the same track still plays: keep the tap a few seconds. The peek comes and goes with the
        // pointer, and each rebuild costs a TCC check and a new aggregate device — measured live 2026-10-13: four
        // rebuilds in 18 s while the pointer moved around the notch.
        if want == nil, let cur = currentPID, playing == cur {
            if !lingering {
                lingering = true
                lingerToken += 1
                let token = lingerToken
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger) {
                    MainActor.assumeIsolated { AudioTapMonitor.shared.lingerExpired(token) }
                }
            }
            return
        }
        cancelLinger()
        if want == currentPID { return }
        stop()
        retriedPID = nil
        if let pid = want { start(pid: pid) }
    }

    private func cancelLinger() { lingering = false; lingerToken += 1 }

    private func lingerExpired(_ token: Int) {
        guard token == lingerToken, lingering else { return }
        lingering = false
        if !visible { stop() }
    }

    private func start(pid: pid_t) {
        currentPID = pid
        isRunning = true
        meter.reset(); silence.reset(); looksDenied = false
        guard #available(macOS 14.2, *) else { return }
        let log = self.log
        Self.ioQueue.async {
            guard let h = Self.makeTap(pid: pid, log: log) else {
                Task { @MainActor in AudioTapMonitor.shared.startFailed(pid: pid) }
                return
            }
            Self.handles.withLock { $0 = h }
            // The clock starts when the tap RUNS: the first start blocks on the permission prompt (measured ~40 s, and
            // the live run on 2026-10-13 rebuilt the tap mid-prompt when the delay was counted from the request).
            Task { @MainActor in AudioTapMonitor.shared.scheduleRetry(pid: pid, after: 3) }
        }
    }

    /// One rebuild per track: the tap's process list is fixed when it is created, and a browser's audio helper can
    /// appear a moment after the player reports "playing". No buffer within `delay` of the tap running (or of a failed
    /// start) ⇒ resolve the processes again, once. A one-shot timer, never a poll.
    private func scheduleRetry(pid: pid_t, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let m = AudioTapMonitor.shared
            guard m.currentPID == pid || (m.currentPID == nil && m.visible), m.retriedPID != pid,
                  m.silence.firstBuffer == nil else { return }
            let snap = NowPlayingMonitor.shared.liveSnapshot
            guard m.isEnabled, m.visible, snap?.playing == true, snap?.pid == pid else { return }
            m.retriedPID = pid
            m.log.notice("no buffers after \(delay, privacy: .public) s — rebuilding the tap for pid=\(pid)")
            m.stop()
            m.start(pid: pid)
        }
    }

    private func stop() {
        currentPID = nil
        if isRunning { isRunning = false; meter.reset() }
        Self.ioQueue.async {
            guard let h = Self.handles.withLock({ s -> Handles? in defer { s = nil }; return s }) else { return }
            AudioDeviceStop(h.device, h.proc)
            AudioDeviceDestroyIOProcID(h.device, h.proc)
            AudioHardwareDestroyAggregateDevice(h.device)
            if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(h.tap) }
        }
    }

    private func startFailed(pid: pid_t) {
        guard currentPID == pid else { return }
        currentPID = nil; isRunning = false
        if retriedPID != pid { scheduleRetry(pid: pid, after: 1.5) }
    }

    /// One RMS from the IO block (already throttled to ≤ 30 per second).
    private func receive(rms: Float) {
        guard isRunning else { return }
        meter.push(level: AudioWaveform.level(rms: rms))
        let first = silence.firstBuffer == nil, hadSignal = silence.sawSignal
        silence.observe(rms: rms, at: Date())
        // Once per tap: the only evidence, outside the view, that buffers arrive and carry sound (no audio is logged).
        if first { log.notice("first buffer rms=\(rms, privacy: .public)") }
        if !hadSignal && silence.sawSignal { log.notice("first signal rms=\(rms, privacy: .public)") }
        let denied = silence.looksDenied(now: Date())
        if denied != looksDenied { looksDenied = denied; log.notice("looksDenied=\(denied, privacy: .public)") }
    }

    // MARK: CoreAudio (off the main actor)

    @available(macOS 14.2, *)
    nonisolated private static func makeTap(pid: pid_t, log: Logger) -> Handles? {
        let processes = AudioWaveform.playerProcesses(audioProcesses(), player: pid)
        guard !processes.isEmpty else { log.notice("no audio process object for pid=\(pid)"); return nil }
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        let ts = AudioHardwareCreateProcessTap(desc, &tap)
        guard ts == noErr else { log.notice("create tap failed status=\(ts)"); return nil }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let us = withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, $0) }
        guard us == noErr else { AudioHardwareDestroyProcessTap(tap); return nil }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "XFinder Waveform",
            kAudioAggregateDeviceUIDKey: "com.xfinder.waveform.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uid as String]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else {
            AudioHardwareDestroyProcessTap(tap); return nil
        }
        var proc: AudioDeviceIOProcID?
        let ps = AudioDeviceCreateIOProcIDWithBlock(&proc, device, ioQueue) { _, input, _, _, _ in
            var sum: Float = 0
            var n = 0
            for b in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let count = Int(b.mDataByteSize) / MemoryLayout<Float>.size
                for i in 0..<count { sum += p[i] * p[i] }
                n += count
            }
            let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
            let now = CFAbsoluteTimeGetCurrent()
            let send = lastSent.withLock { last -> Bool in
                guard now - last >= 1.0 / 30 else { return false }
                last = now; return true
            }
            if send { DispatchQueue.main.async { MainActor.assumeIsolated { AudioTapMonitor.shared.receive(rms: rms) } } }
        }
        guard ps == noErr, let proc else {
            AudioHardwareDestroyAggregateDevice(device); AudioHardwareDestroyProcessTap(tap); return nil
        }
        let ss = AudioDeviceStart(device, proc)
        log.notice("tap started pid=\(pid) objects=\(processes.count) proc=\(ps) start=\(ss)")
        guard ss == noErr else {
            AudioDeviceDestroyIOProcID(device, proc); AudioHardwareDestroyAggregateDevice(device); AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        return Handles(tap: tap, device: device, proc: proc)
    }

    /// Every CoreAudio process object with its pid, responsible pid and parent pid.
    nonisolated private static func audioProcesses() -> [AudioWaveform.AudioProcess] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let responsible = responsibleLookup()
        return ids.compactMap { id in
            var pa = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = -1
            var ps = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(id, &pa, 0, nil, &ps, &pid) == noErr, pid > 0 else { return nil }
            let r = responsible.map { $0(pid) }
            return AudioWaveform.AudioProcess(object: id, pid: pid, responsiblePID: (r ?? 0) > 0 ? r : nil, parentPID: parentPID(pid))
        }
    }

    /// `responsibility_get_pid_responsible_for_pid` — exported by libquarantine but undocumented, so resolved at run
    /// time; missing ⇒ nil and the resolver falls back to the parent pid. Measured: Chrome's helper → Chrome, Safari's
    /// WebKit.GPU → Safari, OneNotch's WebKit.GPU → OneNotch.
    nonisolated private static func responsibleLookup() -> (@convention(c) (pid_t) -> pid_t)? {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (pid_t) -> pid_t).self)
    }

    nonisolated private static func parentPID(_ pid: pid_t) -> Int32? {
        var info = proc_bsdshortinfo()
        let n = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdshortinfo>.size))
        return n > 0 ? Int32(info.pbsi_ppid) : nil
    }
}
