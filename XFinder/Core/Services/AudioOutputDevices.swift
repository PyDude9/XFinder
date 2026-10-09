import Foundation
import CoreAudio
import Observation

/// Live sound-output list and switcher. Public CoreAudio HAL only — no entitlement, no private
/// framework.
///
/// Cost model: event-driven and demand-driven. Two system-object listeners (device list changed,
/// default output changed) exist only while a view that shows the picker is on screen
/// (`retain()`/`release()`, the same ref-count `VolumeObserver` uses); no timer, no polling, and
/// nothing at all when no such view is visible.
@MainActor
@Observable
final class AudioOutputDevices {
    static let shared = AudioOutputDevices()

    private(set) var devices: [AudioOutputDevice] = []
    /// The current default output device, 0 when none.
    private(set) var currentID: UInt32 = 0
    /// Set when the last `select` failed, so the UI says so instead of silently showing the old device.
    private(set) var lastError: String?

    private var refCount = 0
    private var devicesBlock: AudioObjectPropertyListenerBlock?
    private var defaultBlock: AudioObjectPropertyListenerBlock?

    // Internal, not private: a standalone harness builds its own instance to drive the real code.
    init() {}

    var current: AudioOutputDevice? { devices.first { $0.id == currentID } }

    // MARK: Lifecycle

    func retain() {
        refCount += 1
        if refCount == 1 { start() }
    }

    func release() {
        refCount = max(0, refCount - 1)
        if refCount == 0 { stop() }
    }

    private func start() {
        refresh()
        guard devicesBlock == nil else { return }
        // Main queue ⇒ main thread ⇒ `assumeIsolated` is valid.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        devicesBlock = block
        defaultBlock = block
        var a = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main, block)
        var b = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &b, DispatchQueue.main, block)
    }

    private func stop() {
        guard let block = devicesBlock else { return }
        var a = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main, block)
        var b = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &b, DispatchQueue.main, block)
        devicesBlock = nil
        defaultBlock = nil
    }

    // MARK: Read

    func refresh() {
        devices = AudioOutputList.build(from: Self.readRawDevices())
        currentID = Self.defaultOutputID()
    }

    // MARK: Switch

    /// Make `device` the default output (and the alert-sound output too, when the user had left
    /// the two unified — see `AudioOutputList.shouldMoveSystemOutput`). Returns whether the
    /// default output actually changed; on failure `lastError` says why.
    @discardableResult
    func select(_ device: AudioOutputDevice) -> Bool {
        lastError = nil
        let previousDefault = Self.defaultOutputID()
        let previousSystem = Self.systemOutputID()
        var id = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let system = AudioObjectID(kAudioObjectSystemObject)

        var a = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(system, &a, 0, nil, size, &id)
        if status == noErr,
           AudioOutputList.shouldMoveSystemOutput(previousDefault: previousDefault, previousSystem: previousSystem) {
            var b = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
            _ = AudioObjectSetPropertyData(system, &b, 0, nil, size, &id)
        }
        refresh()
        guard status == noErr else {
            lastError = "OSStatus \(status)"
            return false
        }
        // Trust the readback, not the return code: a device can accept the write and not become default.
        if currentID != device.id {
            lastError = "default output is still \(currentID)"
            return false
        }
        return true
    }

    // MARK: CoreAudio plumbing (static so the harness and tests of the plumbing share it)

    nonisolated static func address(_ selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    nonisolated static func defaultOutputID() -> UInt32 {
        readU32(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice)) ?? 0
    }

    nonisolated static func systemOutputID() -> UInt32 {
        readU32(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultSystemOutputDevice)) ?? 0
    }

    nonisolated static func readRawDevices() -> [RawAudioDevice] {
        var size: UInt32 = 0
        var addr = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            RawAudioDevice(
                id: id,
                uid: readString(id, address(kAudioDevicePropertyDeviceUID)) ?? "",
                name: readString(id, address(kAudioObjectPropertyName))
                    ?? readString(id, address(kAudioDevicePropertyDeviceNameCFString)) ?? "",
                outputChannels: outputChannelCount(id),
                isHidden: (readU32(id, address(kAudioDevicePropertyIsHidden)) ?? 0) != 0,
                isAlive: (readU32(id, address(kAudioDevicePropertyDeviceIsAlive)) ?? 1) != 0,
                transport: readU32(id, address(kAudioDevicePropertyTransportType)).map(fourCC) ?? "")
        }
    }

    nonisolated private static func readU32(_ id: AudioObjectID, _ a: AudioObjectPropertyAddress) -> UInt32? {
        var addr = a
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    nonisolated private static func readString(_ id: AudioObjectID, _ a: AudioObjectPropertyAddress) -> String? {
        var addr = a
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == noErr,
              let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }

    nonisolated private static func outputChannelCount(_ id: AudioObjectID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    nonisolated private static func fourCC(_ v: UInt32) -> String {
        let bytes = [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(v)"
    }
}
