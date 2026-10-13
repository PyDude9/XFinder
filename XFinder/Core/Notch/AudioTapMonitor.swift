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
        let want = isEnabled && Self.isSupported && waveformVisible && (snap?.playing ?? false) ? snap?.pid : nil
        if want == currentPID { return }
        stop()
        if let pid = want { start(pid: pid) }
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
    }

    /// One RMS from the IO block (already throttled to ≤ 30 per second).
    private func receive(rms: Float) {
        guard isRunning else { return }
        meter.push(level: AudioWaveform.level(rms: rms))
        silence.observe(rms: rms, at: Date())
        let denied = silence.looksDenied(now: Date())
        if denied != looksDenied { looksDenied = denied }
    }

    // MARK: CoreAudio (off the main actor)

    @available(macOS 14.2, *)
    nonisolated private static func makeTap(pid: pid_t, log: Logger) -> Handles? {
        guard let process = processObject(pid: pid) else { log.notice("no audio process object for pid=\(pid)"); return nil }
        let desc = CATapDescription(stereoMixdownOfProcesses: [process])
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
        log.notice("tap started pid=\(pid) proc=\(ps) start=\(ss)")
        guard ss == noErr else {
            AudioDeviceDestroyIOProcID(device, proc); AudioHardwareDestroyAggregateDevice(device); AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        return Handles(tap: tap, device: device, proc: proc)
    }

    nonisolated private static func processObject(pid: pid_t) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var p = pid
        var obj = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), &p, &size, &obj)
        return st == noErr && obj != kAudioObjectUnknown ? obj : nil
    }
}
