import Foundation
import AppKit
import IOKit
import Darwin

/// Screen brightness — **readable and, through a private framework, writable**.
///
/// Correcting an earlier wrong claim, twice over.
///
/// 1. The first version said "macOS has no public API to read screen brightness" and shipped −/+ buttons with
///    no feedback. The registry disproved it: `AppleARMBacklight → IODisplayParameters` carries
///    `brightness = { value: 32768, min: 0, max: 65536 }`, readable with no permission at all.
/// 2. This file then said writing "genuinely has no public path", and that the *readable* value is stuck on
///    Apple Silicon so a bar would have to invent its number. **Both halves were re-measured on 2026-10-15
///    (probe, macOS 27) and corrected here:**
///      * `IODisplayGetFloatParameter` / `SetFloatParameter` do return `kIOReturnUnsupported` (-536870201) on
///        every display service — that part was right;
///      * but the private **`DisplayServices`** framework both *reads* (a live 0…1 value that tracks the
///        keys) and *writes* (`DisplayServicesSetBrightness` really moves the panel; the WindowServer logs
///        the swap). It loads from an ordinary unsigned process with no entitlement.
///      * What was actually frozen is the **IOKit** `IODisplayParameters` snapshot under the new backlight
///        architecture — which is why the old reader looked stuck, and why the slider never tracked the keys.
///
/// So: `DisplayServices` when it answers, IOKit otherwise, NX brightness keys as the last resort.
@MainActor
@Observable
final class ScreenBrightness {
    static let shared = ScreenBrightness()

    /// 0…1, read from `DisplayServices` (live) or IOKit. Nil when no internal display reports brightness
    /// (external-only setups), in which case the UI hides the number.
    private(set) var level: Double?

    private var timer: Timer?
    private var consumers = 0
    /// Giá trị lần đọc gần nhất — để phân biệt "đổi thật" với "kẹt".
    private var lastRegistry: Double?

    /// Whether XFinder can move the panel **itself** (no key events). `SystemKeyInterceptor` reads this from
    /// the tap thread, so it must stay `nonisolated` and touch only the thread-safe shim below.
    nonisolated static var canSetDirectly: Bool {
        guard let d = DisplayServices.builtInDisplay() else { return false }
        return DisplayServices.canChange(d) && DisplayServices.read(d) != nil
    }

    private init() {
        level = Self.readLevel()
        lastRegistry = level
    }

    /// Demand-driven like the other monitors: no page open ⇒ no timer ⇒ idle
    /// CPU stays at zero.
    func retain() {
        consumers += 1
        guard consumers == 1 else { return }
        refresh()
        // Polling is the only way to notice the *hardware* keys: nothing publishes a notification for this
        // property. 1 s is enough to feel live without being a busy loop. (With the live `DisplayServices`
        // read this now actually tracks the keys, instead of re-reading a frozen registry value.)
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func release() {
        consumers = max(0, consumers - 1)
        guard consumers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard let r = Self.readLevel() else { return }
        // Chỉ nhận re-read khi nó THỰC SỰ đổi, để không kéo % ngược về số ảo.
        if let prev = lastRegistry, abs(r - prev) < 0.001 { return }
        lastRegistry = r
        level = r
    }

    /// Moves brightness toward `target` (0…1). With `DisplayServices` this sets the panel exactly and reads
    /// the result back; without it, the old path — NX brightness keys, then trust the requested position,
    /// because the hardware only has ~16 steps and cannot be read back to an exact %.
    func setLevel(_ target: Double) {
        let clamped = min(max(target, 0), 1)
        if let d = DisplayServices.builtInDisplay(), DisplayServices.write(d, Float(clamped)) {
            level = clamped
            lastRegistry = clamped
            return
        }
        guard let current = level else { return }
        let steps = Int(((clamped - current) * 16).rounded())
        guard steps != 0 else { return }
        for _ in 0..<abs(steps) {
            SystemControls.adjustBrightness(up: steps > 0)
        }
        level = clamped
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Read

    /// `DisplayServices` first (live), IOKit as the fallback for anything it will not answer for.
    private static func readLevel() -> Double? {
        if let d = DisplayServices.builtInDisplay(), let v = DisplayServices.read(d) {
            return Double(min(max(v, 0), 1))
        }
        return readLevelFromIOKit()
    }

    private static func readLevelFromIOKit() -> Double? {
        for name in ["AppleARMBacklight", "AppleBacklightDisplay", "IODisplayConnect"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                      IOServiceMatching(name))
            guard service != 0 else { continue }
            defer { IOObjectRelease(service) }

            guard let raw = IORegistryEntryCreateCFProperty(
                    service, "IODisplayParameters" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
            else { continue }

            // `brightness` (16-bit) LUÔN đứng yên ở 32768 = max/2 trên Apple Silicon — đã đo: value/max = 0.5
            // bất chấp độ sáng thật, chính là bug "% luôn 50". Nguồn bám theo phím tăng/giảm là
            // `rawBrightness` (PWM 0–2047). Ưu tiên rawBrightness, fallback brightness.
            for key in ["rawBrightness", "brightness"] {
                guard let b = raw[key] as? [String: Any],
                      let value = b["value"] as? Int,
                      let max = b["max"] as? Int, max > 0
                else { continue }
                let min = b["min"] as? Int ?? 0
                return Double(value - min) / Double(max - min)
            }
        }
        return nil
    }
}

/// dlopen shim for the private **DisplayServices** framework — the only path that both reads and writes the
/// built-in panel's brightness. Measured 2026-10-15 (macOS 27): loads with no entitlement, `GetBrightness`
/// returns a live 0…1 value, `SetBrightness` really moves the panel, and `CanChangeBrightness` gates it.
///
/// Everything here is `nonisolated` and side-effect free so the event-tap thread can ask "can we set it?"
/// without hopping to the main actor. Each call re-`dlsym`s, which is cheap and keeps the code obvious.
enum DisplayServices {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool

    private nonisolated(unsafe) static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    /// The built-in panel, not "the main display" — on an external-only desk they are not the same thing.
    static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func canChange(_ display: CGDirectDisplayID) -> Bool {
        guard let fn: CanFn = symbol("DisplayServicesCanChangeBrightness") else { return false }
        return fn(display)
    }

    static func read(_ display: CGDirectDisplayID) -> Float? {
        guard let fn: GetFn = symbol("DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        return fn(display, &value) == 0 ? value : nil
    }

    @discardableResult
    static func write(_ display: CGDirectDisplayID, _ level: Float) -> Bool {
        guard let fn: SetFn = symbol("DisplayServicesSetBrightness") else { return false }
        return fn(display, level) == 0
    }
}
