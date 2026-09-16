import Foundation
import AppKit
import IOKit

/// Screen brightness — **readable**, and changed via the system brightness keys.
///
/// Correcting an earlier wrong claim. I told the user "macOS has no public API
/// to read screen brightness" and shipped −/+ buttons with no feedback. The
/// registry disproves it: `AppleARMBacklight → IODisplayParameters` carries
///
///     brightness = { value: 32768, min: 0, max: 65536 }
///
/// which `IORegistryEntryCreateCFProperty` reads with no permission at all.
/// That is why the slider never tracked the keyboard keys — nothing was ever
/// reading the real value.
///
/// Writing is the part that genuinely has no public path: measured on macOS
/// 27, `IODisplayGetFloatParameter` / `SetFloatParameter` return
/// `kIOReturnUnsupported` (-536870201) on **every** display service
/// (AppleARMBacklight, IOMobileFramebuffer ×3). So changes still go through the
/// NX brightness key events, and the slider then re-reads the registry to show
/// where it actually landed.
@MainActor
@Observable
final class ScreenBrightness {
    static let shared = ScreenBrightness()

    /// 0…1, read from IOKit. Nil when no internal display reports brightness
    /// (external-only setups), in which case the UI hides the number.
    private(set) var level: Double?

    private var timer: Timer?
    private var consumers = 0
    /// Giá trị registry lần đọc gần nhất — để phân biệt "đổi thật" với "kẹt".
    private var lastRegistry: Double?

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
        // Polling is the only way to notice the hardware keys: IOKit publishes
        // no notification for this property. 1 s is enough to feel live without
        // being a busy loop.
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
        // Trên Apple Silicon, IODisplayParameters có thể kẹt ở một giá trị cố
        // định (vd rawBrightness luôn ~72%) dù phần cứng đã đổi. Chỉ nhận
        // re-read khi nó THỰC SỰ đổi, để không kéo % ngược về số ảo, còn phím
        // tăng/giảm do người dùng bấm thì vẫn được cập nhật khi registry phản
        // ánh.
        if let prev = lastRegistry, abs(r - prev) < 0.001 { return }
        lastRegistry = r
        level = r
    }

    /// Moves brightness toward `target` (0…1) by sending system brightness
    /// keys, then keeps track of the requested level as the displayed value —
    /// macOS cannot be read back to an exact %, and on Apple Silicon the
    /// registry read is often *stuck*, so the slider position is the honest
    /// source of truth (the NX keys really did move the hardware near it).
    func setLevel(_ target: Double) {
        guard let current = level else { return }
        let clamped = min(max(target, 0), 1)
        let delta = clamped - current
        let steps = Int((delta * 16).rounded())
        guard steps != 0 else { return }
        for _ in 0..<abs(steps) {
            SystemControls.adjustBrightness(up: steps > 0)
        }
        level = clamped
        // Re-read chỉ để bắt phím phần cứng nếu registry có đổi; không ghi đè
        // vị trí người dùng kéo khi registry kẹt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - IOKit read

    private static func readLevel() -> Double? {
        for name in ["AppleARMBacklight", "AppleBacklightDisplay", "IODisplayConnect"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                      IOServiceMatching(name))
            guard service != 0 else { continue }
            defer { IOObjectRelease(service) }

            guard let raw = IORegistryEntryCreateCFProperty(
                    service, "IODisplayParameters" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
            else { continue }

            // `brightness` (16-bit) LUÔN đứng yên ở 32768 = max/2 trên Apple
            // Silicon — đã đo: value/max = 0.5 bất chấp độ sáng thật, chính là
            // bug "% luôn 50". Nguồn bám theo phím tăng/giảm là `rawBrightness`
            // (PWM 0–2047). Ưu tiên rawBrightness, fallback brightness.
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
