import Foundation

/// Short-lived notices shown at the notch (B4): power, network, Caps Lock, Bluetooth, alerts.
/// Pure: every "did something change worth saying?" rule, and the queue that decides what shows
/// when several arrive together. Sources are event-driven (IOPS notification, NWPathMonitor,
/// flagsChanged, IOBluetooth connect notifications); nothing polls.
enum LiveActivity {

    enum Kind: String, CaseIterable {
        case power, network, capsLock, bluetooth, alert, volume, brightness, timer, meeting, agent, localMessage
        /// The answer to a key the person just pressed (the native square is swallowed for it). It cannot wait its turn
        /// behind a notice, and a stale one is worthless — see `Queue.push` and `NotchSurfaceMachine.Event.feedbackShown`.
        var isKeyFeedback: Bool { self == .volume || self == .brightness }
    }

    enum Tint: Equatable { case neutral, good, warning, bad }

    struct Item: Equatable {
        let kind: Kind
        let symbol: String
        /// Store key for the headline (the view calls L10n.t).
        let titleKey: String
        /// Already-formatted detail shown verbatim: a percentage, a device name, or an alert body the caller localised.
        let detail: String?
        let tint: Tint
        var duration: TimeInterval = 3
        /// 0…1 for a level bar (volume). nil ⇒ no bar.
        var level: Double? = nil
        /// §3b #33 — buttons on the notice (a meeting alert: Tham gia / Hoãn / Mở Lịch). Non-empty ⇒ hovering the
        /// notice must not turn it into a peek, or the buttons vanish under the pointer that came to press them.
        var buttons: [Button] = []
        var localMessageID: UUID? = nil
    }

    enum Button: Equatable {
        case join(URL)
        case snooze(key: String)
        case openCalendar
        /// P5c — an agent notice: open the hub on the Agents page.
        case openAgents
        /// P12.4 — open the handoff preview for that session, pre-set to `target`. It never sends by itself.
        case handOff(listID: String, target: AgentKind)
        /// XF-ISLAND 1B — optional hydration reminder actions.
        case hydrateAck
        case hydrateSnooze(minutes: Int)
    }

    // MARK: Power

    struct PowerState: Equatable {
        var onAC: Bool
        var percent: Int?
        var charging: Bool
        var charged: Bool
    }

    static let lowBattery = 20, criticalBattery = 10

    /// Measured on this Mac: on AC at 80 %, `IsCharging` false and `IsCharged` false — the battery is
    /// being HELD by optimised charging. So "plugged in" says whether it is charging or holding, and
    /// "full" fires only when the OS itself reports charged; nothing assumes 100 % will come.
    static func powerItems(old: PowerState?, new: PowerState) -> [Item] {
        guard let old else { return [] }                 // the first reading is a baseline, not news
        let pct = new.percent.map { "\($0)%" }
        var out: [Item] = []
        if !old.onAC && new.onAC {
            out.append(Item(kind: .power, symbol: new.charging ? "bolt.fill" : "powerplug.fill",
                            titleKey: new.charging ? "Đang sạc" : "Đã cắm sạc, đang giữ mức pin",
                            detail: pct, tint: .good))
        } else if old.onAC && !new.onAC {
            out.append(Item(kind: .power, symbol: "battery.75", titleKey: "Đang dùng pin", detail: pct, tint: .neutral))
        }
        if new.onAC && new.charged && !old.charged {
            out.append(Item(kind: .power, symbol: "battery.100.bolt", titleKey: "Pin đã đầy", detail: pct, tint: .good))
        }
        if !new.onAC, let n = new.percent, let o = old.percent {
            if n <= criticalBattery && o > criticalBattery {
                out.append(Item(kind: .power, symbol: "battery.0", titleKey: "Pin rất yếu", detail: pct, tint: .bad, duration: 5))
            } else if n <= lowBattery && o > lowBattery {
                out.append(Item(kind: .power, symbol: "battery.25", titleKey: "Pin yếu", detail: pct, tint: .warning, duration: 4))
            }
        }
        return out
    }

    // MARK: Network, Caps Lock, Bluetooth

    static func networkItem(wasOnline: Bool?, isOnline: Bool) -> Item? {
        guard let wasOnline, wasOnline != isOnline else { return nil }
        return isOnline
            ? Item(kind: .network, symbol: "wifi", titleKey: "Đã có mạng trở lại", detail: nil, tint: .good)
            : Item(kind: .network, symbol: "wifi.slash", titleKey: "Mất kết nối mạng", detail: nil, tint: .bad, duration: 4)
    }

    static func capsLockItem(wasOn: Bool?, isOn: Bool) -> Item? {
        guard let wasOn, wasOn != isOn else { return nil }
        return Item(kind: .capsLock, symbol: isOn ? "capslock.fill" : "capslock",
                    titleKey: isOn ? "Caps Lock đang bật" : "Caps Lock đã tắt", detail: nil,
                    tint: isOn ? .warning : .neutral, duration: 1.6)
    }

    static func bluetoothItem(name: String, connected: Bool) -> Item {
        Item(kind: .bluetooth, symbol: connected ? "headphones" : "headphones.slash" ,
             titleKey: connected ? "Đã kết nối" : "Đã ngắt kết nối", detail: name,
             tint: connected ? .good : .neutral)
    }

    // MARK: Volume HUD (B4b) — alongside the system's own HUD, from the real CoreAudio value

    struct VolumeState: Equatable { var level: Double; var muted: Bool }

    /// ── Corrected 2026-10-15 (the owner's HUD request) ─────────────────────────────────────────
    /// This block used to say brightness "has NO HUD on purpose" because the readable value was stuck.
    /// Re-measured on this Mac (macOS 27, 2026-10-15): the private `DisplayServicesGetBrightness` returns a
    /// system-wide 0…1 value — a `DisplayServicesSetBrightness` from one process is read back by another —
    /// and the setter really moves the panel. What is frozen is the *IOKit* `IODisplayParameters` read,
    /// which is what made the number look stuck. The brightness HUD below exists only while XFinder takes
    /// the keys itself (`HUDSuppression`), so there is exactly one readout, never two.
    static func volumeItem(old: VolumeState?, new: VolumeState) -> Item? {
        guard let old else { return nil }                                  // baseline
        let changed = old.muted != new.muted || abs(old.level - new.level) >= 0.005
        guard changed else { return nil }                                  // CoreAudio reports each change on 2 elements
        return volumeItem(new)
    }

    /// The volume bar for a state, unconditionally. Used directly when a key XFinder took could not move
    /// the level (already at 0 or 1): CoreAudio reports nothing then, and the press must still answer.
    static func volumeItem(_ state: VolumeState) -> Item {
        let level = min(max(state.level, 0), 1)
        if state.muted || level == 0 {
            return Item(kind: .volume, symbol: "speaker.slash.fill", titleKey: "Đã tắt tiếng", detail: nil,
                        tint: .neutral, duration: 1.5, level: 0)
        }
        let symbol = level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        return Item(kind: .volume, symbol: symbol, titleKey: "Âm lượng", detail: "\(Int((level * 100).rounded()))%",
                    tint: .neutral, duration: 1.5, level: level)
    }

    // MARK: Brightness HUD (owner's HUD request, 2026-10-15)

    /// The brightness bar for a level, unconditionally. Nothing observes brightness, so the only caller is
    /// the key XFinder just took — and a press must answer even at 0 or 1, where the level does not move
    /// (the system square shows its full/empty bar there too).
    static func brightnessItem(level raw: Double) -> Item {
        let level = min(max(raw, 0), 1)
        let symbol = level < 0.34 ? "sun.min.fill" : "sun.max.fill"
        return Item(kind: .brightness, symbol: symbol, titleKey: "Độ sáng",
                    detail: "\(Int((level * 100).rounded()))%", tint: .neutral, duration: 1.5, level: level)
    }

    // MARK: HUD suppression — may XFinder swallow a system media key?

    /// A system-defined key XFinder may act on (`IOKit/hidsystem/ev_keymap.h` key types).
    enum MediaKey: Int, Equatable {
        case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7

        var isVolume: Bool { self == .volumeUp || self == .volumeDown || self == .mute }
    }

    /// The owner's request (2026-10-15): when XFinder reports brightness/volume on the notch, macOS must
    /// not draw its own square as well — the notch is the only readout.
    ///
    /// Reported by the agent that built it (probe, 2026-10-15, macOS 27; not re-measured inside the app):
    /// a `.cghidEventTap` tap on `systemDefined` receives these keys, returning `nil` suppresses the native
    /// OSD for volume and brightness, and a bare programmatic change never draws it. The decision is pure so
    /// it can be tested; `SystemKeyInterceptor` only does the I/O.
    enum HUDSuppression {
        /// `data1` puts the phase in bits 8…15: 0xA down, 0xB up (probe-measured).
        enum Phase: Equatable { case down, up, other }

        struct Context: Equatable {
            /// `notch.activity.hideSystemHUD` — the user asked XFinder to be the only readout.
            var hideSystemHUD: Bool
            /// `NotchSurfaceController.canPresentActivities` — with no notch surface, swallowing the key
            /// would leave no feedback at all.
            var canPresent: Bool
            var masterOn: Bool          // notch.activities
            var volumeOn: Bool          // notch.activity.volume
            var brightnessOn: Bool      // notch.activity.brightness
            /// Whether XFinder can move the panel itself (`ScreenBrightness.canSetDirectly`). Without it,
            /// swallowing a brightness key would leave the user with no change at all.
            var brightnessWritable: Bool
            /// Whether the current output device lets XFinder set what the key asks for (volume scalar, or
            /// mute). HDMI and aggregate devices often do not; macOS then shows its own "not available" square,
            /// and swallowing the key would show nothing.
            var volumeWritable: Bool
            /// ⌥, ⇧, ⌃ or ⌘ held with the key. macOS gives those combinations their own meaning (⌥⇧ = quarter
            /// steps, ⌥ = open the Sound/Displays settings) that XFinder does not reproduce, so they pass.
            var modifiersHeld: Bool
        }

        enum Decision: Equatable {
            /// Let the key through: macOS draws its own HUD (the honest fallback).
            case passThrough
            /// Swallow the key; XFinder applies the change and the notch is the only readout.
            case consume(MediaKey)
        }

        static func phase(data1: Int) -> Phase {
            switch (data1 >> 8) & 0xFF {
            case 0xA: return .down
            case 0xB: return .up
            default: return .other
            }
        }

        /// Whether a key press may be taken over, judged on its DOWN. The UP is not decided here — it follows
        /// its DOWN (`Pairing`), whatever the context has become by then. A phase we do not recognise is never
        /// touched: `keytype 0 state 0` events exist in the wild and are not key presses.
        static func decide(keyType: Int, phase: Phase, context: Context) -> Decision {
            guard let key = MediaKey(rawValue: keyType) else { return .passThrough }
            guard phase == .down || phase == .up else { return .passThrough }
            guard context.hideSystemHUD, context.canPresent, context.masterOn else { return .passThrough }
            guard !context.modifiersHeld else { return .passThrough }
            if key.isVolume { guard context.volumeOn, context.volumeWritable else { return .passThrough } }
            else { guard context.brightnessOn, context.brightnessWritable else { return .passThrough } }
            return .consume(key)
        }

        /// Keeps a DOWN and its UP together. If the DOWN was swallowed, its UP must be too (a lone UP is a
        /// key release macOS never saw pressed); if the DOWN went through, its UP must go through as well (or
        /// macOS believes the key is still held). Deciding each half on its own breaks exactly when the
        /// context changes mid-press — a modifier released, the switch flipped — which is why this exists.
        struct Pairing: Equatable {
            private(set) var swallowed: Set<Int> = []

            mutating func resolve(keyType: Int, phase: Phase, decideDown: () -> Decision) -> Decision {
                switch phase {
                case .down:
                    let decision = decideDown()
                    if case .consume = decision { swallowed.insert(keyType) } else { swallowed.remove(keyType) }
                    return decision
                case .up:
                    guard swallowed.remove(keyType) != nil, let key = MediaKey(rawValue: keyType) else {
                        return .passThrough
                    }
                    return .consume(key)
                case .other:
                    return .passThrough
                }
            }
        }
    }

    // MARK: Countdown timer (B4b)

    /// P2: running OR paused. Running = `endsAt` set; paused = `pausedRemaining` set and the clock frozen (a paused
    /// timer is not finished, whatever the wall clock says). `duration` is the whole planned length, so `progress`
    /// stays honest across pauses and extensions.
    struct Countdown: Equatable, Codable, Sendable {
        private(set) var duration: TimeInterval
        private(set) var endsAt: Date?
        private(set) var pausedRemaining: TimeInterval?

        init(minutes: Int, now: Date) {
            duration = TimeInterval(max(minutes, 1) * 60)
            endsAt = now.addingTimeInterval(duration)
            pausedRemaining = nil
        }

        var isPaused: Bool { endsAt == nil }

        func remaining(at now: Date) -> TimeInterval {
            if let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
            return max(0, pausedRemaining ?? 0)
        }

        func isFinished(at now: Date) -> Bool { !isPaused && remaining(at: now) <= 0 }

        /// 0 at the start, 1 at the end — the elapsed share of the whole planned length.
        func progress(at now: Date) -> Double {
            guard duration > 0 else { return 1 }
            return min(1, max(0, 1 - remaining(at: now) / duration))
        }

        /// Freeze the clock. Pausing a paused timer changes nothing.
        func paused(at now: Date) -> Countdown {
            guard !isPaused else { return self }
            var c = self
            c.pausedRemaining = remaining(at: now)
            c.endsAt = nil
            return c
        }

        /// Restart the clock from where it stopped. Resuming a running timer changes nothing.
        func resumed(at now: Date) -> Countdown {
            guard isPaused else { return self }
            var c = self
            c.endsAt = now.addingTimeInterval(pausedRemaining ?? 0)
            c.pausedRemaining = nil
            return c
        }

        /// +/- whole minutes, running or paused. What is LEFT never drops below one minute (a "−5" on a timer with
        /// two minutes left must not end it instantly) nor exceeds `timerMaxMinutes`; `duration` moves by what was
        /// actually added, so the progress bar does not jump. `duration` is therefore always elapsed + left, and may pass
        /// `timerMaxMinutes` when a long timer is extended near its end — the maximum caps what is LEFT, not the history
        /// (P2 review; `testExtendingKeepsAtLeastAMinuteAndAtMostTheMaximum` pins it).
        func extended(byMinutes minutes: Int, now: Date) -> Countdown {
            let left = remaining(at: now)
            let target = min(max(left + TimeInterval(minutes * 60), 60), TimeInterval(LiveActivity.timerMaxMinutes * 60))
            let delta = target - left
            guard delta != 0 else { return self }
            var c = self
            c.duration = max(60, duration + delta)
            if let endsAt { c.endsAt = endsAt.addingTimeInterval(delta) } else { c.pausedRemaining = target }
            return c
        }

        /// "4:05", "59:59", "1:02:03" — whole seconds rounded UP, so the label never reads 0:00 early.
        func label(at now: Date) -> String {
            let t = Int(remaining(at: now).rounded(.up))
            let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
        }
    }

    static let timerPresets = [5, 10, 15, 25, 45, 60]

    /// P2 Hẹn giờ page: the idle minutes stepper (and the running "−5 / +5") moves in 5-minute steps within 5…120;
    /// 25 is the default, as in OneNotch's timer view.
    static let timerStepMinutes = 5
    static let timerMinMinutes = 5
    static let timerMaxMinutes = 120
    static let timerDefaultMinutes = 25

    /// One step of the idle stepper: snaps to the 5-minute grid first, then clamps (a stored 23 steps to 25 / 20).
    static func steppedMinutes(_ minutes: Int, by direction: Int) -> Int {
        let step = timerStepMinutes
        let snapped = direction > 0 ? (minutes / step + 1) * step : direction < 0 ? ((minutes + step - 1) / step - 1) * step : minutes
        return min(max(snapped, timerMinMinutes), timerMaxMinutes)
    }

    /// A stored draft outside the range (or garbage) reads as something the page can draw.
    static func validTimerMinutes(_ minutes: Int?) -> Int {
        guard let m = minutes else { return timerDefaultMinutes }
        return min(max(m, timerMinMinutes), timerMaxMinutes)
    }

    static func timerFinishedItem(_ c: Countdown) -> Item {
        Item(kind: .timer, symbol: "timer", titleKey: "Hết giờ", detail: String(format: "%d:00", Int(c.duration / 60)),
             tint: .warning, duration: 8)
    }

    // MARK: Queue

    /// What is on screen and what waits. Same-kind notices REPLACE each other — a network that drops
    /// and returns within a second shows only "back online", and Caps Lock tapped twice shows the
    /// final state — so a flapping source can never stack up a backlog.
    struct Queue: Equatable {
        private(set) var current: Item?
        private(set) var pending: [Item] = []
        static let maxPending = 4

        /// Returns true when `current` changed (the caller re-renders and restarts the timer).
        @discardableResult
        mutating func push(_ item: Item) -> Bool {
            if current == nil { current = item; return true }
            // Key feedback goes on screen NOW (2026-10-19: volume presses landed behind an agent notice and showed
            // nothing while the key was swallowed). The notice it interrupts comes back first; an interrupted feedback
            // item is dropped — a volume level from two presses ago is not news.
            if item.kind.isKeyFeedback, let c = current, c.kind != item.kind {
                pending.removeAll { $0.kind.isKeyFeedback }
                if !c.kind.isKeyFeedback { pending.insert(c, at: 0) }
                if pending.count > Self.maxPending { pending.removeLast(pending.count - Self.maxPending) }
                current = item
                return true
            }
            if let c = current, c.kind == item.kind {
                if Self.outranks(c, item) { enqueue(item); return false }
                current = item; return true
            }
            if let i = pending.firstIndex(where: { $0.kind == item.kind }) {
                if Self.outranks(pending[i], item) { enqueue(item) } else { pending[i] = item }
                return false
            }
            enqueue(item)
            return false
        }

        private mutating func enqueue(_ item: Item) {
            pending.append(item)
            if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
        }

        /// P12 review: an agent notice that asks for action (a limit stop, an approval) is not replaced by a lesser agent
        /// notice (a finished turn) — the lesser one waits its turn. Other kinds keep "the newest state wins" (a network
        /// flapping in a second still shows only the final state).
        static func outranks(_ a: Item, _ b: Item) -> Bool {
            guard a.kind == .agent, b.kind == .agent else { return false }
            func rank(_ t: Tint) -> Int { switch t { case .bad: return 2; case .warning: return 1; case .good, .neutral: return 0 } }
            return rank(a.tint) > rank(b.tint)
        }

        /// The shown item's time is up: advance. Returns the new current (nil ⇒ nothing left).
        @discardableResult
        mutating func advance() -> Item? {
            current = pending.isEmpty ? nil : pending.removeFirst()
            return current
        }

        /// The surface cannot draw `current` right now (the hub is open): put it back at the head of the line instead of
        /// letting its timer run unseen. `resume()` brings it back once the notch is idle again.
        mutating func hold() {
            guard let c = current else { return }
            pending.insert(c, at: 0)
            current = nil
        }

        /// Nothing is showing but something waits (it was held): make the head current. Returns it, nil ⇒ nothing to do.
        @discardableResult
        mutating func resume() -> Item? {
            guard current == nil, !pending.isEmpty else { return nil }
            current = pending.removeFirst()
            return current
        }

        var localMessageID: UUID? {
            current?.localMessageID ?? pending.lazy.compactMap(\.localMessageID).first
        }

        mutating func removePendingLocalMessage(id: UUID) {
            pending.removeAll { $0.localMessageID == id }
        }

        mutating func clear() { current = nil; pending = [] }
    }
}
