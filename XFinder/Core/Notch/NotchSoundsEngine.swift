import AppKit
import AVFoundation
import CoreAudio
import Foundation
import Observation
import os

/// Abstraction over `AVAudioEngine` so `NotchSoundsEngine` can be tested deterministically
/// without opening live audio hardware or touching the owner's sound output.
@MainActor
protocol SoundsAudioBackend: AnyObject {
    var isRunning: Bool { get }
    var isAllocated: Bool { get }
    func hasOutputDevice() -> Bool
    func start(
        gains: NotchSoundsRules.MixGains,
        onConfigurationChange: @escaping @Sendable () -> Void
    ) throws
    func updateGains(_ gains: NotchSoundsRules.MixGains)
    func teardown()
}

/// Abstraction over one-shot timer scheduling so sleep/fade timers are deterministic in tests
/// and guaranteed to hold zero timers while idle.
@MainActor
protocol SoundsTickScheduler: AnyObject {
    var isScheduled: Bool { get }
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

/// Production one-shot scheduler backed by `DispatchWorkItem` on the main queue.
@MainActor
final class DispatchSoundsScheduler: SoundsTickScheduler {
    private var workItem: DispatchWorkItem?

    var isScheduled: Bool { workItem != nil }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.workItem = nil
                action()
            }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.005, delay), execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

/// Production `AVAudioEngine` backend using `AVAudioSourceNode` only.
///
/// Never accesses `AVAudioEngine.inputNode`, so macOS never requests microphone permission
/// or shows the orange microphone indicator. Tears down the engine completely when idle.
@MainActor
final class AVSoundsAudioBackend: SoundsAudioBackend {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var configObserver: NSObjectProtocol?
    private let gainsLock = OSAllocatedUnfairLock(initialState: NotchSoundsRules.MixGains.zero)

    var isRunning: Bool { engine?.isRunning == true }
    var isAllocated: Bool { engine != nil }

    func hasOutputDevice() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown
    }

    func start(
        gains: NotchSoundsRules.MixGains,
        onConfigurationChange: @escaping @Sendable () -> Void
    ) throws {
        teardown()
        guard hasOutputDevice() else {
            throw NotchSoundsRules.EngineError.noOutputDevice
        }

        let audioEngine = AVAudioEngine()
        // Query output format only — never touch `audioEngine.inputNode`.
        let outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        guard outputFormat.sampleRate > 0, outputFormat.channelCount > 0 else {
            throw NotchSoundsRules.EngineError.noOutputDevice
        }

        let renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: outputFormat.sampleRate,
            channels: min(outputFormat.channelCount, 2)
        ) ?? outputFormat

        gainsLock.withLock { $0 = gains }
        let sharedGains = gainsLock
        let dspLock = OSAllocatedUnfairLock(initialState: NotchSoundsRules.NoiseMixerDSP())

        let node = AVAudioSourceNode(format: renderFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let currentGains = sharedGains.withLock { $0 }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            if currentGains.isSilent {
                for buffer in ablPointer {
                    if let data = buffer.mData {
                        memset(data, 0, Int(buffer.mDataByteSize))
                    }
                }
                return noErr
            }

            var localDSP = dspLock.withLock { $0 }
            for frame in 0..<frames {
                let sample = localDSP.renderSample(gains: currentGains)
                for buffer in ablPointer {
                    guard let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    ptr[frame] = sample
                }
            }
            let updatedDSP = localDSP
            dspLock.withLock { $0 = updatedDSP }
            return noErr
        }

        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: renderFormat)
        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            audioEngine.stop()
            audioEngine.reset()
            throw NotchSoundsRules.EngineError.engineStartFailed
        }

        self.engine = audioEngine
        self.sourceNode = node
        self.configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { _ in
            onConfigurationChange()
        }
    }

    func updateGains(_ gains: NotchSoundsRules.MixGains) {
        gainsLock.withLock { $0 = gains }
    }

    func teardown() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        gainsLock.withLock { $0 = .zero }
        if let audioEngine = engine {
            audioEngine.stop()
            if let node = sourceNode {
                audioEngine.detach(node)
            }
            audioEngine.reset()
        }
        sourceNode = nil
        engine = nil
    }
}

/// Long-lived Dynamic Island ambient-sound engine.
///
/// Lifecycle guarantees:
/// - Playback continues when the notch collapses or switches pages (independent of SwiftUI view lifetime).
/// - Idle state holds zero timers and zero allocated audio nodes (`isAudioEngineAllocated == false`, `hasActiveTimer == false`).
/// - Disabling the Sounds tab, system sleep, output-device loss, engine errors, or app termination
///   intentionally releases audio resources and cancels timers.
/// - Output device changes while playing rebuild the audio graph on the new output (or release cleanly if lost).
@MainActor
@Observable
final class NotchSoundsEngine {
    static let shared = NotchSoundsEngine()

    private(set) var channels: [NotchSoundsRules.NoiseKind: NotchSoundsRules.ChannelState] =
        NotchSoundsRules.defaultChannels()
    private(set) var isPlaying = false
    private(set) var sleepTimer: NotchSoundsRules.SleepTimer?
    private(set) var selectedPreset: NotchSoundsRules.SleepPreset = .off
    private(set) var timerNow: Date
    private(set) var masterGain: Float = 1.0
    private(set) var lastError: NotchSoundsRules.EngineError?
    private(set) var lastStopReason: NotchSoundsRules.StopReason?

    private let backend: SoundsAudioBackend
    private let scheduler: SoundsTickScheduler
    private let nowProvider: () -> Date
    private var timerGeneration: UInt64 = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []

    init(
        backend: SoundsAudioBackend? = nil,
        scheduler: SoundsTickScheduler? = nil,
        now: @escaping () -> Date = Date.init,
        registerSystemObservers: Bool = true
    ) {
        self.backend = backend ?? AVSoundsAudioBackend()
        self.scheduler = scheduler ?? DispatchSoundsScheduler()
        self.nowProvider = now
        self.timerNow = now()
        if registerSystemObservers {
            installSystemObservers()
        }
    }

    // MARK: - Derived Read-Only State

    var activeKinds: [NotchSoundsRules.NoiseKind] {
        NotchSoundsRules.NoiseKind.allCases.filter { channels[$0]?.isActive == true }
    }

    var activeCount: Int { activeKinds.count }

    var isFadingOut: Bool {
        guard let timer = sleepTimer else { return false }
        return timer.phase(at: timerNow) == .fadingOut
    }

    var remainingTimerText: String? {
        guard let timer = sleepTimer else { return nil }
        return timer.label(at: timerNow)
    }

    var effectiveGains: NotchSoundsRules.MixGains {
        NotchSoundsRules.effectiveGains(channels: channels, masterGain: masterGain)
    }

    var hasActiveTimer: Bool { scheduler.isScheduled }
    var isAudioEngineRunning: Bool { backend.isRunning }
    var isAudioEngineAllocated: Bool { backend.isAllocated }

    func isActive(_ kind: NotchSoundsRules.NoiseKind) -> Bool {
        channels[kind]?.isActive == true
    }

    func volume(for kind: NotchSoundsRules.NoiseKind) -> Double {
        channels[kind]?.volume ?? NotchSoundsRules.NoiseKind.defaultVolume
    }

    // MARK: - Playback Controls

    func toggle(_ kind: NotchSoundsRules.NoiseKind) {
        setActive(kind, active: !isActive(kind))
    }

    func setActive(_ kind: NotchSoundsRules.NoiseKind, active: Bool) {
        var state = channels[kind] ?? NotchSoundsRules.ChannelState()
        guard state.isActive != active else { return }
        state.isActive = active
        channels[kind] = state

        if active {
            lastError = nil
            lastStopReason = nil
            // If user turns a channel on while a previous fade was finishing, keep playback clean:
            // if the timer was already finished, clear it.
            if let timer = sleepTimer, timer.phase(at: nowProvider()) == .finished {
                clearTimerInternal(resetMasterGain: true)
            }
            if !isPlaying {
                startAudioIfNeeded()
            } else {
                syncBackendGains()
            }
        } else {
            if activeKinds.isEmpty {
                stopAll(reason: .user)
            } else {
                syncBackendGains()
            }
        }
    }

    func setVolume(_ volume: Double, for kind: NotchSoundsRules.NoiseKind) {
        let clamped = NotchSoundsRules.clampVolume(volume)
        var state = channels[kind] ?? NotchSoundsRules.ChannelState()
        guard state.volume != clamped else { return }
        state.volume = clamped
        channels[kind] = state
        if isPlaying {
            syncBackendGains()
        }
    }

    // MARK: - Sleep / Fade-Out Timer Controls

    func setSleepPreset(_ preset: NotchSoundsRules.SleepPreset) {
        selectedPreset = preset
        if preset == .off {
            cancelSleepTimer()
        } else {
            setSleepTimer(duration: preset.durationSeconds, fadeDuration: NotchSoundsRules.defaultFadeDuration)
        }
    }

    func setSleepTimer(
        duration: TimeInterval,
        fadeDuration: TimeInterval = NotchSoundsRules.defaultFadeDuration
    ) {
        guard duration.isFinite, duration > 0 else {
            cancelSleepTimer()
            return
        }
        let now = nowProvider()
        timerNow = now
        let timer = NotchSoundsRules.SleepTimer(
            startedAt: now,
            duration: duration,
            fadeDuration: fadeDuration
        )
        sleepTimer = timer
        // Only arm the timer loop when audio is playing; if idle, don't keep a timer running.
        guard isPlaying else {
            clearTimerInternal(resetMasterGain: true)
            return
        }
        masterGain = timer.fadeGain(at: now)
        syncBackendGains()
        armNextTick(for: timer, at: now)
    }

    func cancelSleepTimer() {
        selectedPreset = .off
        clearTimerInternal(resetMasterGain: true)
        if isPlaying {
            syncBackendGains()
        }
    }

    // MARK: - Stop & Lifecycle APIs (Integrator / Controller Hooks)

    /// Stops all active channels, cancels any sleep/fade timer, and tears down `AVAudioEngine`.
    /// Preserves per-channel volume preferences so resuming later restores the user's mix levels.
    func stopAll(reason: NotchSoundsRules.StopReason = .user) {
        for kind in NotchSoundsRules.NoiseKind.allCases {
            var state = channels[kind] ?? NotchSoundsRules.ChannelState()
            state.isActive = false
            channels[kind] = state
        }
        selectedPreset = .off
        clearTimerInternal(resetMasterGain: true)
        backend.teardown()
        isPlaying = false
        lastStopReason = reason
        if reason == .user || reason == .sleepTimerFinished || reason == .tabDisabled || reason == .systemSleep || reason == .appWillTerminate {
            lastError = nil
        }
    }

    /// Integrator hook: call when the Sounds tab is hidden/disabled or the master notch is turned off.
    func handleTabDisabled() {
        stopAll(reason: .tabDisabled)
    }

    /// Integrator hook: mirrors XFinder's `applySettings()` pattern.
    func applyTabVisibility(isEnabled: Bool) {
        if !isEnabled {
            handleTabDisabled()
        }
    }

    /// System sleep hook: intentionally release audio hardware and cancel active timers so the Mac
    /// sleeps cleanly and does not blast unexpected sound on wake.
    func handleSystemWillSleep() {
        guard isPlaying || isAudioEngineAllocated || hasActiveTimer else { return }
        stopAll(reason: .systemSleep)
    }

    /// System wake hook: verify idle invariant; never auto-start sound unexpectedly after sleep.
    func handleSystemDidWake() {
        if !isPlaying {
            clearTimerInternal(resetMasterGain: true)
            if backend.isAllocated {
                backend.teardown()
            }
        }
    }

    /// Output-device / audio-configuration change hook.
    /// - Idle: ignored (never allocates audio engine).
    /// - Playing + output available: rebuilds graph on the new output device seamlessly.
    /// - Playing + no output (or restart fails): releases engine and surfaces honest error.
    func handleOutputConfigurationChanged() {
        let decision = NotchSoundsRules.onOutputChange(
            isPlaying: isPlaying,
            hasOutputDevice: backend.hasOutputDevice()
        )
        switch decision {
        case .ignore:
            return
        case .stopDeviceLost:
            stopAll(reason: .outputDeviceLost)
            lastError = .noOutputDevice
        case .restart:
            let gains = effectiveGains
            do {
                try backend.start(gains: gains) { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.handleOutputConfigurationChanged()
                    }
                }
                lastError = nil
            } catch let err as NotchSoundsRules.EngineError {
                stopAll(reason: err == .noOutputDevice ? .outputDeviceLost : .engineError)
                lastError = err
            } catch {
                stopAll(reason: .engineError)
                lastError = .engineStartFailed
            }
        }
    }

    /// App termination hook: releases audio hardware, timers, and notification observers.
    func handleAppWillTerminate() {
        stopAll(reason: .appWillTerminate)
        removeSystemObservers()
    }

    // MARK: - Internal Audio & Timer Plumbing

    private func startAudioIfNeeded() {
        guard !activeKinds.isEmpty else { return }
        let gains = effectiveGains
        do {
            try backend.start(gains: gains) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleOutputConfigurationChanged()
                }
            }
            isPlaying = true
            lastError = nil
        } catch let err as NotchSoundsRules.EngineError {
            stopAll(reason: err == .noOutputDevice ? .outputDeviceLost : .engineError)
            lastError = err
        } catch {
            stopAll(reason: .engineError)
            lastError = .engineStartFailed
        }
    }

    private func syncBackendGains() {
        guard isPlaying else { return }
        backend.updateGains(effectiveGains)
    }

    private func clearTimerInternal(resetMasterGain: Bool) {
        timerGeneration &+= 1
        scheduler.cancel()
        sleepTimer = nil
        if resetMasterGain {
            masterGain = 1.0
        }
    }

    private func armNextTick(for timer: NotchSoundsRules.SleepTimer, at now: Date) {
        timerGeneration &+= 1
        let generation = timerGeneration
        guard let delay = timer.nextTickInterval(at: now) else {
            stopAll(reason: .sleepTimerFinished)
            return
        }
        scheduler.schedule(after: delay) { [weak self] in
            self?.handleTimerTick(expectedGeneration: generation)
        }
    }

    private func handleTimerTick(expectedGeneration: UInt64) {
        guard expectedGeneration == timerGeneration else { return }
        guard isPlaying, let timer = sleepTimer else {
            clearTimerInternal(resetMasterGain: true)
            return
        }
        let now = nowProvider()
        timerNow = now
        let phase = timer.phase(at: now)
        switch phase {
        case .inactive, .finished:
            stopAll(reason: .sleepTimerFinished)
        case .countingDown, .fadingOut:
            masterGain = timer.fadeGain(at: now)
            syncBackendGains()
            armNextTick(for: timer, at: now)
        }
    }

    private func installSystemObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSystemWillSleep()
                }
            }
        )
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSystemDidWake()
                }
            }
        )
        appObservers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppWillTerminate()
                }
            }
        )
    }

    private func removeSystemObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            wsCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appObservers.removeAll()
    }
}
