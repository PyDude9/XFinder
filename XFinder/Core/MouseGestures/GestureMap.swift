import Foundation

// The **vocabulary** of what a mouse can be asked to do, and the single file that
// names every built-in binding.
//
// Why this exists as its own Foundation-only file
// -----------------------------------------------
// Before this, a mapping was a bare `GestureShortcut` and the page had to guess an
// action name from the key code:
//
//     case 17: return L10n.t("Tab mới")     // ← what if ⌘T was the user's own binding?
//     case 29: return L10n.t("Vừa khung")
//
// That table lived in the SwiftUI file `GestureDetailPanel.swift`, so no test could
// reach it, and it answered "what is key 17?" — a question with a different answer per
// app. A gesture has an **intent** ("go back"), and only the intent is stable across
// apps. `GestureMapEntry` carries the intent; the UI asks which app it is describing
// and names the shortcut accordingly.
//
// This file imports nothing but Foundation, is symlinked into the test package, and
// contains **no display strings** — `labelKey` is a store key, resolved by `L10n`.

// MARK: - Key codes

/// The virtual key codes and modifier bits the map needs, named.
///
/// Spelled as plain numbers rather than Carbon constants so this file stays free of
/// any framework import; the values are the documented `kVK_*` codes and the bits
/// match `CGEventFlags`' modifier positions, which is what `GestureShortcut` stores.
enum GestureKeyCode {
    static let a: UInt16 = 0
    static let b: UInt16 = 11
    static let c: UInt16 = 8
    static let d: UInt16 = 2
    static let e: UInt16 = 14
    static let f: UInt16 = 3
    static let g: UInt16 = 5
    static let h: UInt16 = 4
    static let i: UInt16 = 34
    static let j: UInt16 = 38
    static let k: UInt16 = 40
    static let l: UInt16 = 37
    static let m: UInt16 = 46
    static let n: UInt16 = 45
    static let o: UInt16 = 31
    static let p: UInt16 = 35
    static let q: UInt16 = 12
    static let r: UInt16 = 15
    static let s: UInt16 = 1
    static let t: UInt16 = 17
    static let u: UInt16 = 32
    static let v: UInt16 = 9
    static let w: UInt16 = 13
    static let x: UInt16 = 7
    static let y: UInt16 = 16
    static let z: UInt16 = 6
    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let three: UInt16 = 20
    static let four: UInt16 = 21
    static let five: UInt16 = 23
    static let six: UInt16 = 22
    static let seven: UInt16 = 26
    static let eight: UInt16 = 28
    static let nine: UInt16 = 25
    static let zero: UInt16 = 29
    static let equals: UInt16 = 24
    static let minus: UInt16 = 27
    static let leftBracket: UInt16 = 33
    static let rightBracket: UInt16 = 30
    static let semicolon: UInt16 = 41
    static let quote: UInt16 = 39
    static let comma: UInt16 = 43
    static let period: UInt16 = 47
    static let slash: UInt16 = 44
    static let backslash: UInt16 = 42
    static let grave: UInt16 = 50
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let pageUp: UInt16 = 116
    static let pageDown: UInt16 = 121
}

// MARK: - Intent

/// What a gesture is *for*, independent of which keys an app binds to it.
///
/// This is the type the page renders and the type the tests pin. Keying off the
/// intent rather than the key is what lets Safari's `⌘T` and a user's remapped `⌘⇧N`
/// both read "New tab" — and lets a *wrong* shortcut read as its own honest name
/// instead of borrowing a neighbour's.
enum GestureActionKind: String, CaseIterable, Sendable {
    // Navigation
    case back
    case forward
    case nextTab
    case previousTab
    case reopenTab
    case nextPage
    case previousPage
    case nextItem
    case previousItem
    // Editing
    case undo
    case redo
    // View
    case zoomIn
    case zoomOut
    case zoomToFit
    // System
    case missionControl
    case appExposé
    case previousSpace
    case nextSpace
    case showDesktop
    case screenshot
    // Natural horizontal scrolling, forwarded untouched.
    case horizontalScroll

    /// A store key, resolved by `L10n`. Never a rendered sentence: a `String`
    /// member here is exactly how Vietnamese reached the English page before.
    var labelKey: String {
        switch self {
        case .back: return "Lùi"
        case .forward: return "Tiến"
        case .nextTab: return "Tab kế tiếp"
        case .previousTab: return "Tab trước"
        case .reopenTab: return "Mở lại tab vừa đóng"
        case .nextPage: return "Trang kế tiếp"
        case .previousPage: return "Trang trước"
        case .nextItem: return "Mục kế tiếp"
        case .previousItem: return "Mục trước"
        case .undo: return "Hoàn tác"
        case .redo: return "Làm lại"
        case .zoomIn: return "Phóng to"
        case .zoomOut: return "Thu nhỏ"
        case .zoomToFit: return "Vừa khung"
        case .missionControl: return "Mission Control"
        case .appExposé: return "App Exposé"
        case .previousSpace: return "Space trước"
        case .nextSpace: return "Space kế tiếp"
        case .showDesktop: return "Hiện màn hình nền"
        case .screenshot: return "Chụp màn hình"
        case .horizontalScroll: return "Cuộn ngang nguyên bản"
        }
    }

    /// Which section of a list this belongs to. Grouping is by **what the user is
    /// doing**, so the four navigation items do not sit beside the system actions.
    var groupKey: String {
        switch self {
        case .back, .forward, .nextTab, .previousTab, .reopenTab,
             .nextPage, .previousPage, .nextItem, .previousItem:
            return "Điều hướng"
        case .undo, .redo:
            return "Soạn thảo"
        case .zoomIn, .zoomOut, .zoomToFit, .horizontalScroll:
            return "Xem"
        case .missionControl, .appExposé, .previousSpace, .nextSpace, .showDesktop, .screenshot:
            return "Hệ thống"
        }
    }
}

// MARK: - Entry

/// One binding: the *intent*, the exact shortcut that performs it, and whether the
/// shortcut is a platform convention or a claim about a specific app.
enum GestureBindingSource: String, Sendable {
    /// macOS/Windows-wide convention: `⌘[` is Back in every app with history, ⌘Z is
    /// Undo in every app with an edit stack. Safe to ship as a default, because an
    /// app without the concept simply ignores the keystroke.
    case platformConvention
    /// A specific app's own documented shortcut. Testable by the user in that app;
    /// named as such so a mismatch is diagnosable rather than mysterious.
    case appShortcut
}

/// One choice in the action picker: an intent, and the shortcut that will be sent
/// for it. A choice with no `shortcut` is a **deliberate "send nothing"** and is
/// labelled as such rather than as a missing value.
struct GestureActionChoice: Identifiable, Equatable, Sendable {
    var kind: GestureActionKind
    var shortcut: GestureShortcut?
    /// Set instead of `shortcut` for the intents delivered by a system event
    /// (Mission Control, App Exposé, Show Desktop). Exactly one of the two is
    /// non-nil, or both are nil for "send nothing" — `action` enforces it.
    var systemAction: GestureSystemAction?

    init(kind: GestureActionKind, shortcut: GestureShortcut?, systemAction: GestureSystemAction? = nil) {
        self.kind = kind; self.shortcut = shortcut; self.systemAction = systemAction
    }

    var id: String {
        let key = shortcut.map { "\($0.key)-\($0.flags)" }
            ?? systemAction.map { "sys-\($0.rawValue)" }
            ?? "none"
        return "\(kind.rawValue).\(key)"
    }

    var action: GestureAction {
        if let systemAction { return .systemAction(systemAction) }
        guard let shortcut else { return .unassigned }
        return .shortcut(shortcut)
    }
}

/// The picker's catalogue. Built from two inputs only — the intent vocabulary and the
/// keystrokes this module is willing to name — so a choice cannot exist in the list
/// without the engine being able to send it.
enum GestureActionCatalog {

    /// The keystrokes worth offering per intent, in the order the picker lists them.
    /// The **first** entry is the one a preset uses.
    static func keystrokes(for kind: GestureActionKind) -> [GestureShortcut] {
        let c = GestureShortcut.command, ctrl = GestureShortcut.control
        let s = GestureShortcut.shift, o = GestureShortcut.option
        func k(_ code: UInt16, _ flags: UInt64) -> GestureShortcut {
            GestureShortcut(key: code, flags: flags)
        }
        switch kind {
        case .back:
            return [k(GestureKeyCode.leftBracket, c), k(GestureKeyCode.leftArrow, c)]
        case .forward:
            return [k(GestureKeyCode.rightBracket, c), k(GestureKeyCode.rightArrow, c)]
        case .nextTab:
            return [k(GestureKeyCode.tab, ctrl), k(GestureKeyCode.tab, ctrl | s)]
        case .previousTab:
            return [k(GestureKeyCode.tab, ctrl | s), k(GestureKeyCode.tab, ctrl)]
        case .reopenTab:
            return [k(GestureKeyCode.t, c | s)]
        case .nextPage:
            return [k(GestureKeyCode.pageDown, 0), k(GestureKeyCode.downArrow, 0)]
        case .previousPage:
            return [k(GestureKeyCode.pageUp, 0), k(GestureKeyCode.upArrow, 0)]
        case .nextItem:
            return [k(GestureKeyCode.rightBracket, c), k(GestureKeyCode.downArrow, o), k(GestureKeyCode.tab, ctrl)]
        case .previousItem:
            return [k(GestureKeyCode.leftBracket, c), k(GestureKeyCode.upArrow, o), k(GestureKeyCode.tab, ctrl | s)]
        case .undo:
            return [k(GestureKeyCode.z, c)]
        case .redo:
            return [k(GestureKeyCode.z, c | s)]
        case .zoomIn:
            return [k(GestureKeyCode.equals, c), k(GestureKeyCode.rightBracket, 0)]
        case .zoomOut:
            return [k(GestureKeyCode.minus, c), k(GestureKeyCode.leftBracket, 0)]
        case .zoomToFit:
            return [k(GestureKeyCode.zero, c), k(GestureKeyCode.one, c)]
        case .previousSpace:
            // The literal `⌃←` stays an **offer**, not the default: the Global row uses the
            // system action below, which resolves to whatever this Mac actually binds, but
            // a user who prefers raw keys can still pick them here and the label will say
            // so honestly instead of claiming to be "your Mac's shortcut".
            return [k(GestureKeyCode.leftArrow, ctrl)]
        case .nextSpace:
            return [k(GestureKeyCode.rightArrow, ctrl)]
        case .missionControl, .appExposé, .showDesktop:
            // Offered as system actions only (see `systemAction(for:)`). A keystroke here
            // would be a constant this module invents, and the whole point of the system
            // action is that the key is the *user's* binding, read from the OS.
            return []
        case .screenshot:
            return GestureMap.systemKeystroke(kind).map { [$0] } ?? []
        case .horizontalScroll:
            // Not a keystroke: the choice means "forward the wheel's own sideways
            // motion". Returned as a **cat marker** so the intent is present in the
            // list for the property test that asserts no intent is unreachable; the
            // picker itself renders it as its own labelled row rather than as a
            // keystroke, because it sends no keys.
            return []
        }
    }

    /// Everything the picker shows, grouped by intent. Every intent is present, so the
    /// list can never be "emptier than the vocabulary" — the shape of the bug where the
    /// screen offered fewer options than the engine could actually perform.
    ///
    /// An intent with no keystroke (`.horizontalScroll`) still contributes a choice, so
    /// the coverage property holds: `choices()` covers `GestureActionKind.allCases`
    /// exactly. The picker renders that one as a labelled row rather than as keys.
    static func choices() -> [(group: String, items: [GestureActionChoice])] {
        var buckets: [String: [GestureActionChoice]] = [:]
        var order: [String] = []
        for kind in GestureActionKind.allCases {
            let group = kind.groupKey
            if buckets[group] == nil { order.append(group) }
            var emitted = false
            // A system-action intent (Mission Control / App Exposé / Show Desktop / the two
            // Space moves) is offered as one row labelled by its mechanism. It is checked
            // **before** the keystroke list because the engine resolves these from the
            // user's own symbolic hotkeys rather than from a shipped key.
            //
            // It is *added alongside* literal keystrokes rather than replacing them: the
            // old `continue` dropped the `⌃←`/`⌃→` alternatives entirely, so a user who
            // wanted raw keys had no way to pick them. "Whatever your Mac binds" and
            // "literally ⌃←" are genuinely different choices and both belong in the list.
            if let system = GestureMap.systemAction(for: kind) {
                buckets[group, default: []].append(GestureActionChoice(kind: kind, shortcut: nil, systemAction: system))
                emitted = true
            }
            for shortcut in keystrokes(for: kind) {
                buckets[group, default: []].append(GestureActionChoice(kind: kind, shortcut: shortcut))
                emitted = true
            }
            if !emitted {
                // Deliberately nothing to send. Present as its own row so the coverage
                // property holds — the list can never be emptier than the vocabulary —
                // and the cell is never blank.
                buckets[group, default: []].append(GestureActionChoice(kind: kind, shortcut: nil))
            }
        }
        return order.map { (group: $0, items: buckets[$0] ?? []) }
    }

    /// The choice a stored action corresponds to, so the picker can show the current
    /// value. A keystroke that is not in the catalogue still resolves: a key the user
    /// recorded is never silently replaced by one we happen to list.
    static func choice(for action: GestureAction, kind: GestureActionKind?) -> GestureActionChoice {
        switch action {
        case .unassigned:
            return GestureActionChoice(kind: kind ?? .back, shortcut: nil)
        case .horizontalScroll:
            return GestureActionChoice(kind: .horizontalScroll, shortcut: nil)
        case .shortcut(let shortcut):
            return GestureActionChoice(kind: kind ?? .back, shortcut: shortcut)
        case .systemAction(let system):
            // Round-trips a system action back to the row that produced it, so opening
            // the picker on a preset row does not silently show "send nothing".
            return GestureActionChoice(kind: kind ?? system.defaultKind, shortcut: nil, systemAction: system)
        }
    }
}

/// A single row of the gesture map.
struct GestureMapEntry: Equatable, Sendable {
    var kind: GestureActionKind
    /// `nil` = **deliberately unassigned**, because no single shortcut performs this
    /// action across the apps in the profile. Never invented to fill a cell.
    var shortcut: GestureShortcut?
    var source: GestureBindingSource
    /// Set instead of `shortcut` for the intents macOS delivers through a system event
    /// (Mission Control, App Exposé, Show Desktop). Mutually exclusive with `shortcut`
    /// by construction — see `action`.
    var systemAction: GestureSystemAction?

    init(kind: GestureActionKind, shortcut: GestureShortcut?, source: GestureBindingSource,
         systemAction: GestureSystemAction? = nil) {
        self.kind = kind; self.shortcut = shortcut; self.source = source
        self.systemAction = systemAction
    }

    /// `true` when this row sends **no key at all**: either deliberately unassigned, or
    /// delivered by a system event. Both render as "not a keystroke", and conflating
    /// them is what previously let a system event be labelled with fake keys.
    var isUnassigned: Bool { shortcut == nil && systemAction == nil }

    /// The action the resolver stores and the engine dispatches. Unassigned has a
    /// representable value (`.unassigned`), which is what keeps "intentionally
    /// empty" distinguishable from "missing".
    var action: GestureAction {
        if let systemAction { return .systemAction(systemAction) }
        guard let shortcut else { return .unassigned }
        return .shortcut(shortcut)
    }
}

/// A row plus where its value came from for the app currently on screen.
struct ResolvedGestureRow: Equatable, Sendable {
    var direction: GestureDirection
    var entry: GestureMapEntry
    /// The bundle ID the entry was actually read from. For an app with no preset of
    /// its own this is `GestureProfiles.fallback`, which is how the page can say
    /// "this is the Global table, not a preset for your app" without re-deriving it.
    var effectiveBundle: String
    var isUserOverride: Bool
    /// The keystroke this machine's own symbolic hotkeys bind to the row's system action,
    /// resolved from `com.apple.symbolichotkeys`. `nil` for a non-system row, and also for
    /// a system row this machine does not bind — the two are distinguished by
    /// `isUnboundSystemAction`, because "sends nothing because it is unassigned" and
    /// "sends nothing because your Mac has no shortcut for it" need different copy and
    /// different advice.
    var systemShortcut: GestureShortcut? = nil
    /// `true` when the row *is* a system action whose key could not be resolved. The UI
    /// uses this to explain the missing shortcut instead of drawing a blank cell.
    var isUnboundSystemAction: Bool = false

    /// The exact value the engine will dispatch. Derived from `entry` — never stored
    /// separately, which is what makes "shown equals sent" structural rather than a
    /// convention someone has to remember.
    var action: GestureAction { entry.action }

    /// What this arm sends, as a **store key** for `L10n` — or `nil` when it sends
    /// nothing at all.
    ///
    /// Four cases, and keeping them distinct is the point:
    ///   * a keystroke → its `label` (language-neutral symbols, so it returns as-is);
    ///   * a **system action bound on this machine** → the resolved keystroke's `label`, so
    ///     the row shows the real keys (`⌃↑`) rather than an invented constant;
    ///   * a **system action this machine does not bind** → `unboundCaptionKey`, so the row
    ///     says "no shortcut set in macOS" instead of an empty box that reads as a bug;
    ///   * `.unassigned` / passing the wheel through → `nil`, so the caller prints its own
    ///     "not assigned" wording rather than an empty box.
    var caption: String? {
        if let shortcut = entry.shortcut { return shortcut.label }
        if let system = entry.systemAction {
            if let resolved = systemShortcut { return resolved.label }
            return system.unboundCaptionKey
        }
        return nil
    }
}

// MARK: - Map

/// The one resolver the Settings page **and** the runtime engine read.
///
/// The brief's rule — "the shortcut shown in Settings must be exactly the shortcut
/// dispatched by the engine; use one resolver, not two copies of mapping logic" — is
/// enforced structurally here: `action` is derived from `shortcut`, so a row cannot
/// display one key and dispatch another.
enum GestureMap {

    /// The built-in entry for `direction` under `bundle`, following the inheritance
    /// rule that the whole module uses:
    ///
    /// 1. an app with its own preset answers for itself, and a direction it leaves
    ///    unassigned stays unassigned — it never falls through to Global, because a
    ///    preset that deliberately omits an action must not silently acquire a
    ///    different, possibly destructive one;
    /// 2. an app with no preset of its own inherits Global;
    /// 3. `*` (Global) answers for itself.
    ///
    /// A direction with no row at all is `nil` rather than an invented entry: a
    /// profile that does not carry the row simply has nothing to say about that arm,
    /// and the caller renders it as Unassigned.
    static func builtIn(bundle: String, direction: GestureDirection) -> GestureMapEntry? {
        let profile = GestureProfiles.all.first { $0.id == bundle }
            ?? GestureProfiles.all[0]
        return profile.gestureMap[direction]
    }

    /// Which bundle's table actually answers for `bundle`.
    static func effectiveBundle(for bundle: String) -> String {
        GestureProfiles.all.contains { $0.id == bundle } ? bundle : GestureProfiles.fallback
    }

    /// The full picture for one direction: the entry, its provenance, and whether the
    /// user has overridden it.
    static func row(overrides: [String: [GestureDirection: GestureAction]],
                    bundle: String,
                    direction: GestureDirection,
                    systemBindings: GestureSystemBindings = .empty) -> ResolvedGestureRow {
        let effective = effectiveBundle(for: bundle)
        let base = builtIn(bundle: bundle, direction: direction)
        // The system shortcut is resolved from the *same* bindings for a preset row and for
        // a user override that picked a system action, so the two cannot show different keys.
        func systemResolution(_ entry: GestureMapEntry) -> (GestureShortcut?, Bool) {
            guard let system = entry.systemAction else { return (nil, false) }
            if let resolved = systemBindings.shortcut(for: system) { return (resolved, false) }
            return (nil, true)
        }
        if let override = overrides[bundle]?[direction] {
            // An override replaces the *shortcut*, but the intent it renders under
            // still comes from the app's own table — the user changed which keys are
            // sent, not what the gesture is for. A system action keeps its own mechanism,
            // so `systemAction(of:)` restores what the override chose — without it, an
            // override that picked "Mission Control" rendered as "not assigned".
            let entry = GestureMapEntry(kind: actionKind(for: override, fallback: base?.kind),
                                        shortcut: shortcut(of: override),
                                        source: base?.source ?? .platformConvention,
                                        systemAction: systemAction(of: override))
            let (resolved, unbound) = systemResolution(entry)
            return ResolvedGestureRow(direction: direction, entry: entry,
                                      effectiveBundle: effective, isUserOverride: true,
                                      systemShortcut: resolved, isUnboundSystemAction: unbound)
        }
        let entry = base ?? .unassigned(.horizontalScroll)
        let (resolved, unbound) = systemResolution(entry)
        return ResolvedGestureRow(direction: direction,
                                  entry: entry,
                                  effectiveBundle: effective,
                                  isUserOverride: false,
                                  systemShortcut: resolved, isUnboundSystemAction: unbound)
    }

    /// Every direction's row, in the canonical order the diagram draws them.
    static func rows(overrides: [String: [GestureDirection: GestureAction]],
                     bundle: String,
                     directions: [GestureDirection] = GestureDirection.allCases,
                     systemBindings: GestureSystemBindings = .empty) -> [ResolvedGestureRow] {
        directions.map { row(overrides: overrides, bundle: bundle, direction: $0, systemBindings: systemBindings) }
    }

    /// The four button-drag directions, in the order the diagram places them.
    static let holdDragDirections: [GestureDirection] = [.up, .down, .left, .right]
    /// What to call the shortcut when the page knows the app it is for.
    ///
    /// The intent name is only correct when the shortcut is the one this app binds to
    /// that intent. A user who records `⌘↩` for "Up" in Safari has not invented a new
    /// meaning for the arrow; they have pointed it at their own key. So the honest
    /// rule is: show the **intent** when the shortcut matches the built-in one, and
    /// otherwise show **only the keys**. That is why a recorded binding cannot produce
    /// a confident-looking wrong name.
    static func displayName(for row: ResolvedGestureRow) -> String? {
        guard let shortcut = row.entry.shortcut else { return nil }
        if row.isUserOverride {
            let builtIn = builtIn(bundle: row.effectiveBundle, direction: row.direction)
            return builtIn?.shortcut == shortcut ? row.entry.kind.labelKey : nil
        }
        return row.entry.kind.labelKey
    }

    // System actions, and the one intent that is a plain keystroke.
    //
    // ── Measured 2026-09-22, corrected 2026-09-23 ────────────────────────────────
    // This table used to *invent* keys: it returned `⌃↑` for Mission Control, `⌃↓` for
    // App Exposé and `⌃←`/`⌃→` for Spaces, on the belief that those are "the same keys the
    // keyboard uses". Two probes disproved it, and the user reported the symptom twice
    // ("nhận dạng cho có, không làm việc" — recognised, does nothing):
    //   * an early read showed ids 79–82 present with `enabled = true` but **no `value`
    //     block** — the switch on with no key assigned, so nothing listened for
    //     `⌃←`/`⌃→`;
    //   * Mission Control stored `vk = 232`, an NX system-defined keytype with no
    //     `CGKeyCode`, which no `CGEvent` can express — and `NX_KEYTYPE_MISSION_CONTROL`
    //     is not even a real constant (`ev_keymap.h` stops at `NX_KEYTYPE_MENU = 25`).
    // A later read of the same machine showed the user had since bound ids 32/33/79–82 to
    // `⌃↑`/`⌃↓`/`⌃←`/`⌃→` with mask `0x840000`. So **both states occur**, and a shipped
    // constant is wrong in at least one of them — which is exactly why a constant is the
    // wrong shape.
    //
    // So nothing here names a system key any more. Those intents are `.systemAction` rows
    // and their key is resolved from the user's own `com.apple.symbolichotkeys` at both
    // display and dispatch time (`SpaceBinding`). This function now answers only for
    // `.screenshot`, which genuinely is a fixed macOS shortcut with no symbolic-hotkey id.
    //
    // `⌘⇧Q` is Log Out and must never appear here.
    static func systemKeystroke(_ kind: GestureActionKind) -> GestureShortcut? {
        switch kind {
        case .screenshot:
            return GestureShortcut(key: GestureKeyCode.three, flags: GestureShortcut.command | GestureShortcut.shift)
        case .missionControl, .appExposé, .showDesktop, .previousSpace, .nextSpace:
            // Not keystrokes: each resolves from the machine's own hotkeys — see
            // `GestureAction.systemAction`. A constant here would be a fabricated key.
            return nil
        default:
            return nil
        }
    }

    /// The system action an intent is dispatched through, for the intents that have one.
    /// The counterpart to `systemKeystroke`, so the picker and the engine agree about
    /// which intents are resolved from the user's hotkeys rather than from a constant.
    static func systemAction(for kind: GestureActionKind) -> GestureSystemAction? {
        switch kind {
        case .missionControl: return .missionControl
        case .appExposé: return .appExpose
        case .showDesktop: return .showDesktop
        case .previousSpace: return .previousSpace
        case .nextSpace: return .nextSpace
        default: return nil
        }
    }

    /// The system action stored in an action, or nil.
    ///
    /// Needed when an **override** holds a system action. Without it the resolver built an
    /// entry with `shortcut: nil` and `systemAction: nil`, so a user who picked "Mission
    /// Control" from the picker saw the row report itself as *not assigned* — the action
    /// was stored but the resolver could not see it.
    static func systemAction(of action: GestureAction) -> GestureSystemAction? {
        if case .systemAction(let system) = action { return system }
        return nil
    }

    /// What a system action's row shows in place of keys.
    ///
    /// Used by the picker, whose rows are the whole catalogue rather than one direction's
    /// `ResolvedGestureRow`, so it cannot read `systemShortcut` and would otherwise have to
    /// re-resolve the bindings (a second copy of the resolution logic — the thing the
    /// "one resolver" rule forbids).
    static func systemCaption(for system: GestureSystemAction,
                              bindings: GestureSystemBindings) -> String {
        bindings.shortcut(for: system)?.label ?? system.unboundCaptionKey
    }

    /// Shortcut recoverable from any action, so `displayName(for:)` can match an
    /// override against its built-in without a second lookup path.
    static func shortcut(of action: GestureAction) -> GestureShortcut? {
        if case .shortcut(let s) = action { return s }
        return nil
    }

    private static func actionKind(for action: GestureAction,
                                   fallback: GestureActionKind?) -> GestureActionKind {
        switch action {
        case .horizontalScroll: return .horizontalScroll
        case .unassigned: return fallback ?? .horizontalScroll
        case .shortcut: return fallback ?? .horizontalScroll
        // A system action knows its own intent, so the fallback is only a last resort.
        case .systemAction(let system): return system.defaultKind
        }
    }
}
