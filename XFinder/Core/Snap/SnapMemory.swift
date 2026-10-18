import Foundation
import CoreGraphics

/// Window-layout memory for the snap zones (SNAPMEM, 2026-10-18). Pure rules — `SnapMemoryController` (AppKit)
/// feeds it displays, AX events and the clock, and applies what it decides.
///
/// Job: "I arranged Chrome once (left half / full screen) on THIS set of displays; when Chrome opens again, or the
/// external display comes back, it goes to the same place without me doing it again."
///
/// Spaces of a rule: `NormalizedRect` is relative to a display's visible frame and carries no origin convention of
/// its own — the controller normalises and denormalises in ONE space (the AX top-left space it reads and writes).
enum SnapMemory {

    enum Key {
        /// Master switch — default OFF: the feature puts observers on other apps and moves their windows at launch.
        static let remember = "snapzones.remember"
        /// Also remember hand-dragged frames of a remembered app (default OFF: XFinder snaps and full screen only).
        static let frames = "snapzones.rememberFrames"
        /// JSON of `Store`.
        static let store = "snapzones.memory.v1"
    }

    // MARK: Displays

    /// One display, identified the way it survives a reconnect. `uuid` is `CGDisplayCreateUUIDFromDisplayID`, which
    /// macOS derives from vendor/model/serial — measured 2026-10-18: the external HC-L200A reports serial 1, so two
    /// monitors of one model may share a uuid. The page says so.
    struct DisplayKey: Codable, Hashable, Sendable {
        var uuid: String
        var name: String
        var pixelWidth: Int
        var pixelHeight: Int
        var isBuiltin: Bool
    }

    /// The set of displays attached. Order-insensitive: enumeration order changes with the cable, the set does not.
    struct Arrangement: Codable, Hashable, Sendable {
        private(set) var displays: [DisplayKey]

        init(displays: [DisplayKey]) {
            self.displays = displays.sorted { a, b in
                if a.isBuiltin != b.isBuiltin { return a.isBuiltin }
                return a.uuid < b.uuid
            }
        }

        var id: String { displays.map(\.uuid).joined(separator: "+") }
        var isSingleDisplay: Bool { displays.count == 1 }
        /// Short label for a rule row: "Màn trong" alone, or every name joined.
        var names: [String] { displays.map(\.name) }
        func contains(_ key: DisplayKey) -> Bool { displays.contains { $0.uuid == key.uuid } }
    }

    // MARK: Layouts

    /// A window frame as a fraction of the display's visible frame, so a resolution change on the same display
    /// keeps the layout. All four values in 0…1 (clamped on creation).
    struct NormalizedRect: Codable, Equatable, Sendable {
        var x: Double, y: Double, width: Double, height: Double

        /// nil when the visible frame is empty (nothing to be a fraction of).
        static func normalized(_ rect: CGRect, in visible: CGRect) -> NormalizedRect? {
            guard visible.width > 0, visible.height > 0 else { return nil }
            func clamp(_ v: CGFloat) -> Double { Double(min(max(v, 0), 1)) }
            return NormalizedRect(x: clamp((rect.minX - visible.minX) / visible.width),
                                  y: clamp((rect.minY - visible.minY) / visible.height),
                                  width: clamp(rect.width / visible.width),
                                  height: clamp(rect.height / visible.height))
        }

        func denormalized(in visible: CGRect) -> CGRect {
            CGRect(x: visible.minX + CGFloat(x) * visible.width,
                   y: visible.minY + CGFloat(y) * visible.height,
                   width: CGFloat(width) * visible.width,
                   height: CGFloat(height) * visible.height)
        }
    }

    enum Layout: Codable, Equatable, Sendable {
        case snap(SnapLayout.Target)
        case fullscreen
        case frame(NormalizedRect)

        /// Store key for the row (the view calls L10n.t).
        var titleKey: String {
            switch self {
            case .snap(let t): return t.titleKey
            case .fullscreen: return "Toàn màn hình (Space riêng)"
            case .frame: return "Vị trí tự kéo"
            }
        }
    }

    /// Where a window frame belongs: a snap target when it matches one within `tolerance` points on every edge
    /// (what macOS tiling or a hand drag produced), else the frame itself. `allCases` order decides a tie; the targets
    /// differ by far more than 4 pt on any real screen.
    static func classify(frame: CGRect, visible: CGRect, tolerance: CGFloat = 4) -> Layout {
        for t in SnapLayout.Target.allCases where matches(frame, t.rect(in: visible), tolerance: tolerance) {
            return .snap(t)
        }
        guard let n = NormalizedRect.normalized(frame, in: visible) else { return .snap(.maximize) }
        return .frame(n)
    }

    static func matches(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// The target of a remembered layout on `visible`; nil for full screen (applied through AXFullScreen, not a rect).
    static func rect(for layout: Layout, visible: CGRect) -> CGRect? {
        switch layout {
        case .snap(let t): return t.rect(in: visible)
        case .frame(let n): return n.denormalized(in: visible)
        case .fullscreen: return nil
        }
    }

    // MARK: Rules

    enum Outcome: String, Codable, Equatable, Sendable {
        case applied, notTrusted, noWindow, notSettable, failed, appNotRunning

        var titleKey: String {
            switch self {
            case .applied: return "Đã áp"
            case .notTrusted: return "Thiếu quyền Trợ năng"
            case .noWindow: return "Không thấy cửa sổ"
            case .notSettable: return "App không cho đặt toàn màn hình qua Trợ năng"
            case .failed: return "Không đặt được"
            case .appNotRunning: return "App chưa chạy"
            }
        }
    }

    struct Rule: Codable, Equatable, Identifiable, Sendable {
        var bundleID: String
        var appName: String
        var arrangement: Arrangement
        /// The display the window lives on (one of `arrangement.displays`).
        var display: DisplayKey
        var layout: Layout
        var updatedAt: Date
        var lastOutcome: Outcome?
        var lastAppliedAt: Date?

        /// One rule per app per set of displays.
        var id: String { Rule.id(bundleID: bundleID, arrangement: arrangement) }
        static func id(bundleID: String, arrangement: Arrangement) -> String { bundleID + "|" + arrangement.id }
    }

    struct Store: Codable, Equatable, Sendable {
        var version = 1
        var rules: [Rule] = []

        static let maxRules = 200

        /// Tolerant: nothing stored, or a payload this build cannot read, is an empty store — never a crash.
        static func decode(_ data: Data?) -> Store {
            guard let data, let s = try? JSONDecoder().decode(Store.self, from: data) else { return Store() }
            return s
        }

        func encode() -> Data {
            (try? JSONEncoder().encode(self)) ?? Data()
        }

        func rule(bundleID: String, arrangement: Arrangement) -> Rule? {
            rules.first { $0.id == Rule.id(bundleID: bundleID, arrangement: arrangement) }
        }

        func rules(for arrangement: Arrangement) -> [Rule] {
            rules.filter { $0.arrangement == arrangement }
        }

        /// Replace the rule with the same id (or add), then keep the newest `maxRules`.
        mutating func remember(_ rule: Rule) {
            rules.removeAll { $0.id == rule.id }
            rules.append(rule)
            if rules.count > Store.maxRules {
                rules.sort { $0.updatedAt < $1.updatedAt }
                rules.removeFirst(rules.count - Store.maxRules)
            }
        }

        mutating func forget(id: String) { rules.removeAll { $0.id == id } }
        mutating func forgetAll() { rules.removeAll() }

        /// Record how the last replay of a rule went (does not bump `updatedAt` — that is the layout's date).
        mutating func noteOutcome(_ outcome: Outcome, ruleID: String, at date: Date) {
            guard let i = rules.firstIndex(where: { $0.id == ruleID }) else { return }
            rules[i].lastOutcome = outcome
            rules[i].lastAppliedAt = date
        }
    }

    // MARK: Recording

    enum ChangeKind: Equatable, Sendable {
        /// XFinder itself snapped the window (drag, hotkey, notch row, "Bắt dính ngay").
        case snapByXFinder
        /// AXFullScreen flipped on the remembered app's main window.
        case fullscreenToggled(Bool)
        /// The main window moved or resized (hand drag, macOS tiling, the app itself).
        case movedOrResized
    }

    /// Our own AX writes echo back as moved/resized notifications for a moment — ignore events inside this window.
    static let ownWriteGrace: TimeInterval = 1.5
    /// Hand drags produce a burst of events; record once the burst is over.
    static let recordDebounce: TimeInterval = 0.6

    /// Whether an observed change becomes (or updates) a rule. Full-screen toggles are always remembered — that is
    /// half of what the owner asked for — while hand-dragged frames need the second switch.
    static func shouldRecord(kind: ChangeKind, eventAt: TimeInterval, lastOwnWriteAt: TimeInterval?,
                             pointerDown: Bool, framesEnabled: Bool) -> Bool {
        if kind != .snapByXFinder, let own = lastOwnWriteAt, eventAt - own < ownWriteGrace { return false }
        switch kind {
        case .snapByXFinder: return true
        case .fullscreenToggled: return !pointerDown
        case .movedOrResized: return framesEnabled && !pointerDown
        }
    }

    // MARK: Replay

    enum Trigger: Equatable, Sendable {
        /// The app's first window after launch (apps that restore their own geometry need a settle + one re-check).
        case windowAppeared
        /// Displays were attached/detached — the system needs a moment, then one pass.
        case displayChanged
        /// The master switch was just turned on, or a rule was just recorded by hand.
        case switchedOn
    }

    struct ReplayPlan: Equatable, Sendable {
        var rule: Rule
        /// Seconds from now for each attempt; the LAST entry is a re-check that sets again only if the window drifted.
        var delays: [TimeInterval]
    }

    /// Settle, then one re-check — never a loop (rule 4 of the spec).
    static func delays(for trigger: Trigger) -> [TimeInterval] {
        switch trigger {
        case .windowAppeared: return [0.5, 2.0]
        case .displayChanged: return [1.0, 3.0]
        case .switchedOn: return [0, 2.0]
        }
    }

    /// nil = nothing to do: the rule belongs to another set of displays, the app is not running, or this launch was
    /// already handled (a second window of the same launch is not a new launch).
    static func replay(rule: Rule, trigger: Trigger, arrangementNow: Arrangement,
                       appRunning: Bool, alreadyAppliedThisLaunch: Bool) -> ReplayPlan? {
        guard appRunning, rule.arrangement == arrangementNow, arrangementNow.contains(rule.display) else { return nil }
        if trigger == .windowAppeared && alreadyAppliedThisLaunch { return nil }
        return ReplayPlan(rule: rule, delays: delays(for: trigger))
    }

    /// The re-check: set again only when the window is not where the rule says (within tolerance).
    static func needsReapply(current: CGRect, target: CGRect, tolerance: CGFloat = 4) -> Bool {
        !matches(current, target, tolerance: tolerance)
    }

    /// Which display a window belongs to: the one holding its centre; else the one it overlaps most; nil when it
    /// touches none (off-screen).
    static func displayIndex(for frame: CGRect, visibleFrames: [CGRect]) -> Int? {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        if let i = visibleFrames.firstIndex(where: { $0.contains(centre) }) { return i }
        var best: (Int, CGFloat)?
        for (i, v) in visibleFrames.enumerated() {
            let a = v.intersection(frame)
            let area = a.isNull ? 0 : a.width * a.height
            if area > 0, best.map({ area > $0.1 }) ?? true { best = (i, area) }
        }
        return best?.0
    }
}

extension SnapLayout.Target: Codable {}
