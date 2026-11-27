import Foundation

/// XF-T25 — the pure half of smooth mouse scrolling (symlinked into the test package): which wheel events are smoothed, how
/// far one notch travels, and how the remaining distance is spread over frames. The engine (`SmoothScrollController`) only
/// feeds event fields in and posts what comes out.
///
/// Job: *"the mouse wheel glides like the trackpad instead of jumping notch by notch — the trackpad and the Magic Mouse stay
/// untouched."*
enum SmoothScrollRules {

    // MARK: Settings (keys read ONCE, by SmoothScrollController)

    enum Key {
        static let enabled = "smoothScroll.enabled"
        static let speed = "smoothScroll.speed"
        static let smoothness = "smoothScroll.smoothness"
        static let reverse = "smoothScroll.reverse"
        static let linear = "smoothScroll.linear"
    }

    static let speedRange = 50...300           // percent
    static let smoothnessRange = 80...600      // ms
    static let defaultSpeed = 100
    static let defaultSmoothness = 220

    struct Settings: Equatable, Sendable {
        var enabled = false
        var speed = SmoothScrollRules.defaultSpeed
        var smoothness = SmoothScrollRules.defaultSmoothness
        var reverse = false
        var linear = false

        /// Out-of-range values (an old build, `defaults write`) are pulled back in, never trusted.
        var clamped: Settings {
            var s = self
            s.speed = min(max(speed, SmoothScrollRules.speedRange.lowerBound), SmoothScrollRules.speedRange.upperBound)
            s.smoothness = min(max(smoothness, SmoothScrollRules.smoothnessRange.lowerBound), SmoothScrollRules.smoothnessRange.upperBound)
            return s
        }
    }

    // MARK: Which events are smoothed

    /// `eventSourceUserData` of the events this feature posts ("XFSMTH").
    static let tag: Int64 = 0x5846534D5448
    /// The mouse-gesture engine's own synthetic scroll ("XFGEST"): already a deliberate scroll, never smoothed twice.
    static let gestureTag: Int64 = 0x584647455354

    /// The scroll-wheel fields the decision needs, read by the engine from the CGEvent.
    struct WheelEvent: Equatable {
        var userData: Int64 = 0
        var isContinuous = false
        var scrollPhase: Int64 = 0
        var momentumPhase: Int64 = 0
        /// Line deltas (`scrollWheelEventDeltaAxis1/2`), positive = up / left.
        var lineY: Int64 = 0
        var lineX: Int64 = 0
        /// Pixel deltas (`scrollWheelEventPointDeltaAxis1/2`).
        var pointY: Int64 = 0
        var pointX: Int64 = 0
        /// ⌘, ⌥ or ⌃ held — many apps zoom on ⌘/⌥-wheel and need the original event.
        var commandOptionOrControl = false
    }

    enum Kind: String, Equatable, Sendable {
        /// A mouse wheel: smoothed.
        case wheel
        /// A trackpad or Magic Mouse gesture (it carries a scroll or momentum phase): passed through.
        case gesture
    }

    enum Decision: Equatable {
        /// Leave the event alone.
        case pass
        /// Swallow it and glide this many pixels (positive = up / left, the event's own sign).
        case smooth(dx: Double, dy: Double)
    }

    /// Pixels one wheel LINE travels at 100 % speed. macOS itself maps a line to ~10 px for pixel-unit consumers, which
    /// feels like crawling once eased; 40 px is about three text lines, the step the reference smoothers land near.
    static let pixelsPerLine = 40.0

    /// Measured on this Mac (DeviceCapabilityTypes): the Razer Basilisk and the Magic Mouse BOTH report
    /// `scrollWheelEventIsContinuous == 1`, so `isContinuous` cannot tell a wheel from a touch surface. Touch scrolling
    /// always carries a scroll phase (began/changed/ended) or a momentum phase; a wheel never does.
    static func kind(_ e: WheelEvent) -> Kind { e.scrollPhase != 0 || e.momentumPhase != 0 ? .gesture : .wheel }

    static func decide(_ e: WheelEvent, settings: Settings) -> Decision {
        guard settings.enabled, e.userData != tag, e.userData != gestureTag, !e.commandOptionOrControl,
              kind(e) == .wheel else { return .pass }
        let s = settings.clamped
        let factor = Double(s.speed) / 100 * (s.reverse ? -1 : 1)
        // A line wheel says how many lines; a pixel wheel without phases (high-resolution wheels) says how many pixels.
        let rawY = e.isContinuous ? Double(e.pointY) : Double(e.lineY) * pixelsPerLine
        let rawX = e.isContinuous ? Double(e.pointX) : Double(e.lineX) * pixelsPerLine
        let dy = s.linear ? (rawY == 0 ? 0 : (rawY > 0 ? pixelsPerLine : -pixelsPerLine)) : rawY
        let dx = s.linear ? (rawX == 0 ? 0 : (rawX > 0 ? pixelsPerLine : -pixelsPerLine)) : rawX
        guard dx != 0 || dy != 0 else { return .pass }
        return .smooth(dx: dx * factor, dy: dy * factor)
    }

    // MARK: Spreading a distance over frames

    /// One axis's glide: what is left to travel and the fraction of a pixel not yet posted.
    struct Axis: Equatable {
        var remaining = 0.0
        var carry = 0.0

        /// A new notch. Turning around drops what was left of the old direction at once — gliding on against the
        /// hand is the "rubber" feel smoothers are blamed for.
        mutating func add(_ delta: Double) {
            if delta != 0, remaining != 0, (delta > 0) != (remaining > 0) { remaining = 0; carry = 0 }
            remaining += delta
        }

        /// The whole pixels to post for a frame of `dt` seconds with time constant `tau`. Exponential approach:
        /// `remaining × (1 − e^(−dt/τ))`; the fraction is carried so the posted pixels add up to the distance exactly,
        /// and the last half pixel is posted at once instead of creeping.
        mutating func step(dt: Double, tau: Double) -> Int32 {
            guard remaining != 0 || carry != 0 else { return 0 }
            let share = tau > 0 ? 1 - exp(-max(dt, 0) / tau) : 1
            var move = remaining * share
            if abs(remaining - move) < 0.5 { move = remaining }
            remaining -= move
            let exact = move + carry
            var whole = exact.rounded(.towardZero)
            carry = exact - whole
            if remaining == 0 { whole += carry.rounded(); carry = 0 }   // the glide ends on the exact total
            return Int32(clamping: Int(whole))
        }

        var isIdle: Bool { remaining == 0 && carry == 0 }
    }

    /// Both axes of one glide.
    struct Glide: Equatable {
        var x = Axis()
        var y = Axis()

        mutating func add(dx: Double, dy: Double) { x.add(dx); y.add(dy) }

        /// Pixels to post for one frame, (dx, dy).
        mutating func step(dt: Double, smoothnessMs: Int) -> (dx: Int32, dy: Int32) {
            let tau = Double(smoothnessMs) / 1000 / 3   // ~95 % of the distance within the chosen smoothness
            return (x.step(dt: dt, tau: tau), y.step(dt: dt, tau: tau))
        }

        var isIdle: Bool { x.isIdle && y.isIdle }
        mutating func reset() { self = Glide() }
    }

    /// The frame period of the glide timer. A 120 Hz tick on a 60 Hz screen only means some events arrive between frames,
    /// which the app coalesces — cheaper than a display link, and it runs only while a glide is in flight.
    static let framePeriod = 1.0 / 120.0

    // MARK: Other smoothers

    /// Running any of these alongside would smooth twice; the engine pauses and the page names the app. Only bundle ids
    /// measured on this Mac are listed (Mos 4.3.0, 2026-10-22); add one when it is measured, never from memory.
    static let conflictingBundleIDs: [String: String] = [
        "com.caldis.Mos": "Mos",
    ]

    static func conflict(running bundleIDs: [String]) -> String? {
        bundleIDs.lazy.compactMap { conflictingBundleIDs[$0] }.first
    }
}
