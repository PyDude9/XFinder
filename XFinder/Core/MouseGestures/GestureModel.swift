import Foundation

// No AppKit dependencies: the test package compiles this exact file, not a copy.
/// A **semantic** reference to a mouse control. It is deliberately NOT a display
/// string: the model layer must never render, because that is how Vietnamese
/// leaked into the English UI. `L10n` resolves these (see `L10n.t(_:)` overloads)
/// and the tests assert every case resolves to a non-empty English value.
enum ButtonKey: Equatable, Hashable, Sendable {
    case index(Int)
    /// Modifier used as the hold trigger — the label is language-neutral symbols.
    case modifier(UInt64)
}

enum TriggerSource: Codable, Equatable, Sendable {
    case mouseButton(Int)
    case modifierKey(UInt64)

    /// Replaces the old `label`/`numberedName` String properties. Nothing outside
    /// this file may turn a trigger into display text without going through L10n.
    var key: ButtonKey {
        switch self {
        case .mouseButton(let n): return .index(n)
        case .modifierKey(let flags): return .modifier(flags)
        }
    }

    /// `true` when the trigger is a mouse button, i.e. when a number can be shown.
    /// A modifier trigger has no number, and printing "Button 0" for it would be
    /// a fabrication.
    var isMouseButton: Bool {
        if case .mouseButton = self { return true }
        return false
    }

    var isValid: Bool {
        switch self {
        // Left click is deliberately reserved for selecting, dragging and emergency UI access.
        case .mouseButton(let n): return (1...31).contains(n)
        case .modifierKey(let f): return [1 << 17, 1 << 18, 1 << 19, 1 << 20].contains(f)
        }
    }

    /// The raw event button number this trigger consumes, or `nil` for a modifier.
    /// Used by the collision checks that keep two features off one button.
    var buttonNumber: Int? {
        if case .mouseButton(let n) = self { return n }
        return nil
    }

    /// How this trigger reads as a *modifier-style* description, for the diagnostic
    /// ring's own log line. Semantic only — the words come from `L10n`.
    var modifierFlags: UInt64? {
        if case .modifierKey(let f) = self { return f }
        return nil
    }
}

/// Whether this direction is performed by tilting the wheel rather than by
/// holding a button. Lives with the model so the direction title and the diagram
/// cannot disagree about which arms need a held trigger.
enum GestureTriggerKind {
    static func isTilt(_ direction: GestureDirection) -> Bool {
        direction == .tiltLeft || direction == .tiltRight
    }

    /// "Raw horizontal scroll" is only a meaningful choice for the tilt arms; the
    /// four button-drag arms always send a keystroke or nothing, so offering
    /// pass-through there would promise something the motion cannot do.
    static func supportsHorizontalScroll(_ direction: GestureDirection) -> Bool {
        isTilt(direction)
    }
}

enum GestureDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right, tiltLeft, tiltRight

    /// Semantic key for the *motion*, resolved by L10n. The tilt cases are full
    /// sentences; the four drag cases are the bare motion ("pull up") because the
    /// heading composes them with the held button — see `motionKey`.
    var motionKey: String {
        switch self {
        case .up:        return "Kéo LÊN"
        case .down:      return "Kéo XUỐNG"
        case .left:      return "Kéo SANG TRÁI"
        case .right:     return "Kéo SANG PHẢI"
        case .tiltLeft:  return "Nghiêng con lăn TRÁI"
        case .tiltRight: return "Nghiêng con lăn PHẢI"
        }
    }

    /// The heading shown above the keys in the detail panel.
    ///
    /// This is a **key**, not a sentence: it names the direction on its own, with
    /// no reference to the held button. The button belongs in `motionHintKey`,
    /// which composes it with the trigger, because the trigger changes at runtime
    /// and a key cannot interpolate. The user read the same number on all four
    /// arms and concluded every arm was "Button 3"; splitting the two here is what
    /// lets the diagram state the held button exactly once.
    var titleKey: String {
        switch self {
        case .up:        return "Kéo lên"
        case .down:      return "Kéo xuống"
        case .left:      return "Kéo sang trái"
        case .right:     return "Kéo sang phải"
        case .tiltLeft:  return "Nghiêng con lăn TRÁI"
        case .tiltRight: return "Nghiêng con lăn PHẢI"
        }
    }

    /// The bare motion, used as the second half of "Button 3: pull up".
    var motionHintKey: String {
        switch self {
        case .up:        return "kéo lên"
        case .down:      return "kéo xuống"
        case .left:      return "kéo sang trái"
        case .right:     return "kéo sang phải"
        case .tiltLeft:  return "nghiêng con lăn trái"
        case .tiltRight: return "nghiêng con lăn phải"
        }
    }

    /// The direction arrow, language-neutral and printed on every arm.
    var glyph: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .tiltLeft: return "⇱"
        case .tiltRight: return "⇲"
        }
    }
}

struct GestureShortcut: Codable, Equatable, Sendable {
    var key: UInt16
    var flags: UInt64
    static let shift: UInt64 = 1 << 17
    static let control: UInt64 = 1 << 18
    static let option: UInt64 = 1 << 19
    static let command: UInt64 = 1 << 20
    static let modifierMask = shift | control | option | command
    var modifierLabel: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { flags & $0.0 != 0 }.map(\.1).joined()
    }
    var label: String {
        let names: [UInt16: String] = [0:"A", 3:"F", 9:"V", 13:"W", 17:"T", 24:"=", 27:"-",
            29:"0", 30:"]", 33:"[", 35:"P", 6:"Z", 48:"⇥", 50:"`", 116:"Page Up", 121:"Page Down",
            123:"←", 124:"→", 125:"↓", 126:"↑", 36:"↩", 49:"Space"]
        return modifierLabel + (names[key] ?? "Key \(key)")
    }
}

enum GestureAction: Codable, Equatable, Sendable {
    case unassigned
    case shortcut(GestureShortcut)
    // Explicit opt-in forwarding, not an assertion of app-specific timeline semantics.
    case horizontalScroll
    /// A **macOS system action** (Mission Control, App Exposé, Show Desktop, the two
    /// Space moves), dispatched by replaying the keystroke the user's own
    /// `com.apple.symbolichotkeys` binds to it.
    ///
    /// ── Why the delivery is indirect (measured 2026-09-22, corrected the next day) ─────
    /// This case used to post an `NSEvent.systemDefined` key of keytype 32, and asserted
    /// in three comment blocks that Mission Control "is reachable because ids 32 and 34
    /// carry `vk = 232`". Both claims were wrong, and the user reported the symptom twice
    /// ("chỉ là xuất hiện và nhận dạng cho có, không làm việc" — recognised, does nothing):
    ///
    ///   * **`NX_KEYTYPE_MISSION_CONTROL` does not exist.** `<IOKit/hidsystem/ev_keymap.h>`
    ///     defines constants only up to `NX_KEYTYPE_MENU = 25`. The invented 32 posted an
    ///     undefined keytype, which a screen-diff probe measured as changing nothing.
    ///   * Mission Control / Exposé / Spaces are **software symbolic hotkeys**. They are
    ///     not hardware keys, so no keytype can carry them; the only honest mechanism is
    ///     the binding macOS itself uses.
    ///
    /// So the case now stores an *intent*, and `SpaceBinding` resolves it to the exact
    /// keystroke in force on this machine — read at both display and dispatch time, so the
    /// keys on screen and the keys posted cannot diverge. An action this machine does not
    /// bind posts nothing and says so; it never falls back to a shipped guess.
    case systemAction(GestureSystemAction)
}

/// The macOS system actions a gesture can perform by **replaying the user's own
/// symbolic hotkey**.
///
/// ── Measured 2026-09-22, and this enum was WRONG until the next day ────────────────────
/// The first version claimed these were reachable through `NSEvent.systemDefined` from a
/// `SystemKeySender` keytype (32), and that Spaces had "no event-level API". Both halves
/// were false, and the user reported the consequence twice:
///
///   * `NX_KEYTYPE_MISSION_CONTROL` **does not exist**. `ev_keymap.h` defines constants
///     only up to `NX_KEYTYPE_MENU = 25`; the invented `32` posted an undefined keytype,
///     which a screen-diff probe measured as doing *nothing*.
///   * Mission Control, App Exposé, Show Desktop and the two Space moves are **software
///     symbolic hotkeys**, not hardware special keys — so the right mechanism is not a
///     keytype at all. It is to read the binding the user has in
///     `com.apple.symbolichotkeys` (`SpaceBinding`) and post **that** keystroke.
///
/// So every case here resolves to a real keystroke at dispatch and display time. A case
/// the machine does not bind posts nothing and is reported as such (`unboundCaptionKey`) —
/// never a fabricated key, which is the exact failure this replaced.
enum GestureSystemAction: String, Codable, CaseIterable, Equatable, Sendable {
    case missionControl
    case appExpose
    case showDesktop
    case previousSpace
    case nextSpace

    /// The intent this action implements. Lives here so `choice(for:)` can rebuild a
    /// row's kind without a lookup table that could drift from the vocabulary.
    var defaultKind: GestureActionKind {
        switch self {
        case .missionControl: return .missionControl
        case .appExpose: return .appExposé
        case .showDesktop: return .showDesktop
        case .previousSpace: return .previousSpace
        case .nextSpace: return .nextSpace
        }
    }

    /// What the row shows in place of a keystroke **when the machine has no binding for
    /// it**. A **store key**, resolved by `L10n`, never a rendered sentence.
    ///
    /// It has to exist because a row whose key is unbound still sends nothing: leaving it
    /// to fall through the `shortcut?.label` path rendered it as an empty caption, which
    /// reads as "unassigned" — the confusion this pass removes. Kept separate from
    /// `captionKey`'s action *name* so the row can say both "Mission Control" and "no key
    /// on this Mac" without inventing one of the two.
    var captionKey: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Hiện màn hình nền"
        case .previousSpace: return "Space trước"
        case .nextSpace: return "Space kế tiếp"
        }
    }

    /// The label for an action this machine does not bind. Stated in the UI so a gesture
    /// that sends nothing explains itself instead of looking broken.
    var unboundCaptionKey: String { "Chưa gán trong macOS" }
}

struct GestureProfile: Identifiable, Sendable {
    var id: String
    var name: String
    var defaults: [GestureDirection: GestureAction]

    /// The same bindings, with the **intent** and the declaring source attached.
    ///
    /// `defaults` is what the resolver stores and the engine dispatches; this is what
    /// the page reads to print "⌘T — New tab (Safari's own shortcut)" instead of
    /// guessing an action name from a key code. Both are built from one table in
    /// `GestureProfiles.map(for:then:fallback:and:)`, so a displayed key cannot drift
    /// from the dispatched one.
    var gestureMap: [GestureDirection: GestureMapEntry] = [:]
}

// Built-in presets are the immutable factory layer. The resolver is the single
// source of truth for both the Settings UI and the runtime engine:
//   1. explicit per-bundle override in `overrides[bundle]`
//   2. explicit shared overrides for the built-in profile family `overrides[profileId]`
//      (legacy alias — preserved for upgrades, not used for new saves)
//   3. built-in preset for that exact bundleId, or Global for an unknown app
//   4. `.unassigned` — and an explicit `.unassigned` override NEVER falls through.
//
// `GestureDirection` and `GestureActionKind` are declared elsewhere; these
// extensions are here so the shorthands the table below reads as (`d.up`, `k(17).c`)
// live beside the table rather than in the call sites.
extension GestureDirection {
    /// The four directions that exist on every mouse. The two tilt arms are
    /// deliberately absent: they are a separate motion, revealed only when the user
    /// says their wheel tilts (see the `tiltAvailable` note in `Claude.md`).
    static let holdDrag: [GestureDirection] = [.up, .down, .left, .right]

    /// The same four, in the order the diagram draws them clockwise from the top.
    static let clockwise: [GestureDirection] = [.up, .right, .down, .left]
}

/// A shortcut under construction, so the table below can be written as
/// `key(17).cmd` instead of nesting two enum cases and a bitmask on every line.
/// The modifiers compose, so `key(48).ctrl.shift` is `⌃⇧Tab`.
struct GestureKeyBuilder {
    let key: UInt16
    private var flags: UInt64 = 0
    var cmd: GestureKeyBuilder { adding(GestureShortcut.command) }
    var shift: GestureKeyBuilder { adding(GestureShortcut.shift) }
    var ctrl: GestureKeyBuilder { adding(GestureShortcut.control) }
    var opt: GestureKeyBuilder { adding(GestureShortcut.option) }
    /// The finished shortcut, to be wrapped in `.init(kind:shortcut:source:)`.
    var shortcut: GestureShortcut { GestureShortcut(key: key, flags: flags) }
    private var wide: GestureKeyBuilder { self }
    private func adding(_ flag: UInt64) -> GestureKeyBuilder {
        var copy = self
        copy.flags |= flag
        return copy
    }
}

enum GestureProfiles {
    static let fallback = "*"

    static func key(_ code: UInt16, _ flags: UInt64) -> GestureAction {
        .shortcut(GestureShortcut(key: code, flags: flags))
    }

    /// Start describing a binding: `map(17).cmd.convention(.nextTab)`.
    static func map(_ code: UInt16) -> GestureKeyBuilder { GestureKeyBuilder(key: code) }
}

/// The row builders. Kept as `GestureMapEntry` factories so every entry in the table
/// below states **three** things at once — the keys, the intent, and whether the keys
/// are a platform convention or one app's own shortcut. A row that states only keys
/// is what produced the "why does this say New tab?" problem.
extension GestureMapEntry {
    /// A binding that is a macOS/Windows-wide convention.
    static func convention(_ kind: GestureActionKind, _ shortcut: GestureShortcut) -> GestureMapEntry {
        GestureMapEntry(kind: kind, shortcut: shortcut, source: .platformConvention)
    }

    /// A convention delivered by a **system event** rather than a keystroke — Mission
    /// Control, App Exposé, Show Desktop. Overloads `convention` so a preset row reads
    /// the same way whichever mechanism actually sends it.
    static func convention(_ kind: GestureActionKind, _ system: GestureSystemAction) -> GestureMapEntry {
        GestureMapEntry(kind: kind, shortcut: nil, source: .platformConvention, systemAction: system)
    }

    /// A binding that is a specific app's documented shortcut.
    static func appShortcut(_ kind: GestureActionKind, _ shortcut: GestureShortcut) -> GestureMapEntry {
        GestureMapEntry(kind: kind, shortcut: shortcut, source: .appShortcut)
    }

    /// Deliberately unassigned. Never a placeholder for "we did not bother".
    static func unassigned(_ kind: GestureActionKind) -> GestureMapEntry {
        GestureMapEntry(kind: kind, shortcut: nil, source: .platformConvention)
    }

    /// Forward the mouse's own horizontal scroll instead of sending a key.
    static var nativeHorizontalScroll: GestureMapEntry {
        GestureMapEntry(kind: .horizontalScroll, shortcut: nil, source: .platformConvention)
    }
}

/// A profile plus the map it was built from.
extension GestureProfiles {
    /// Builds a profile from a map, deriving `defaults` from it so the two cannot
    /// disagree. `tilt` covers the two tilt arms, which are only revealed on hardware
    /// that declares a horizontal wheel axis and are therefore not part of the four
    /// direction table.
    static func profile(_ id: String, _ name: String,
                        up: GestureMapEntry, down: GestureMapEntry,
                        left: GestureMapEntry, right: GestureMapEntry,
                        tilt: GestureMapEntry? = nil) -> GestureProfile {
        var table: [GestureDirection: GestureMapEntry] = [
            .up: up, .down: down, .left: left, .right: right,
        ]
        if let tilt {
            table[.tiltLeft] = tilt
            table[.tiltRight] = tilt
        }
        return GestureProfile(id: id, name: name,
                              defaults: actions(in: table), gestureMap: table)
    }

    /// The storable actions for a map.
    ///
    /// Two entries are not shortcuts and are handled differently on purpose:
    ///   * a **system action** (`Mission Control`, `App Exposé`, `Show Desktop`) IS
    ///     stored — it is a real, dispatchable value, and omitting it would make the
    ///     preset fall back to `.unassigned` and silently delete the binding;
    ///   * an `.unassigned` entry is **omitted**, because the absence of a key is what
    ///     `GestureConfiguration.source()` reads as "the preset leaves this arm
    ///     empty" rather than "the user set it to nothing";
    ///   * an entry that says *forward the wheel's own sideways motion*
    ///     (`.horizontalScroll`) is omitted for the same reason. The engine's tilt
    ///     branch passes the event through for `.unassigned` **and**
    ///     `.horizontalScroll`, so the two behave identically — but only the omitted
    ///     form keeps the badge honest, and a stored `.horizontalScroll` would make the
    ///     row claim "raw scroll" on mice that have no tilt axis at all.
    static func actions(in table: [GestureDirection: GestureMapEntry]) -> [GestureDirection: GestureAction] {
        var out: [GestureDirection: GestureAction] = [:]
        for (direction, entry) in table {
            if let shortcut = entry.shortcut { out[direction] = .shortcut(shortcut) }
            else if let system = entry.systemAction { out[direction] = .systemAction(system) }
        }
        return out
    }
}

extension GestureProfiles {
    /// The built-in table. Colour is load-bearing: a `✏︎` row is one app's own
    /// shortcut (verifiable in that app), an unmarked row is a platform convention.
    ///
    /// Nothing here is inferred from a single app and shipped as a shared truth. Where
    /// two apps in one profile disagree, the row is Unassigned and the page says which
    /// app to record for.
    static let all: [GestureProfile] = {
        // -- shortcuts used more than once, named so a typo cannot hide --
        let back = GestureShortcut(key: GestureKeyCode.leftBracket, flags: GestureShortcut.command)
        let forward = GestureShortcut(key: GestureKeyCode.rightBracket, flags: GestureShortcut.command)
        let zoomIn = GestureShortcut(key: GestureKeyCode.equals, flags: GestureShortcut.command)
        let zoomOut = GestureShortcut(key: GestureKeyCode.minus, flags: GestureShortcut.command)
        let wordLeft = GestureShortcut(key: GestureKeyCode.leftArrow, flags: GestureShortcut.option)
        let wordRight = GestureShortcut(key: GestureKeyCode.rightArrow, flags: GestureShortcut.option)
        let nextSpace = GestureShortcut(key: GestureKeyCode.rightArrow, flags: GestureShortcut.control)
        let previousSpace = GestureShortcut(key: GestureKeyCode.leftArrow, flags: GestureShortcut.control)

        var result: [GestureProfile] = []

        // ── Global — the table for every app with no preset of its own.
        //
        // ── Past tense, measured 2026-09-22, corrected 2026-09-23 ────────────────────
        // An earlier version sent `⌃↑`/`⌃↓`/`⌃←`/`⌃→` here on the belief that those are
        // "the macOS Space and Mission Control keys". Probing this host disproved it twice
        // over: on the first read nothing in `com.apple.symbolichotkeys` bound `⌃←`/`⌃→`
        // (ids 79–82 were `enabled` with no `value`), and Mission Control sat on the
        // system-defined keytype 232 — which is not a `CGKeyCode` and, as it turned out,
        // not a real NX keytype either. So all four arms dispatched perfectly-formed
        // keystrokes that no part of the system listened for. The user's report was exact:
        // "chỉ là xuất hiện và nhận dạng cho có, không làm việc".
        //
        // The second attempt replaced up/down with an event-level path (`SystemKeySender`,
        // keytype 32) and left left/right as the constant `⌘[`/`⌘]`. That was also wrong:
        // keytype 32 does not exist, so Mission Control still did nothing, and the user
        // reset their own shortcut to `⌃↑` while the preset kept posting something else.
        //
        // What each arm sends now: an **intent**, never a key. `SpaceBinding` resolves it
        // from the user's own symbolic hotkeys, so the gesture posts the exact chord their
        // Mac listens for — `⌃↑` for Mission Control *on a machine that binds it*, and
        // nothing at all (with the page saying so) on one that does not. This is what makes
        // "the shortcut shown equals the shortcut sent" true by construction rather than by
        // a comment: there is only one resolver, and it reads the OS.
        //
        // Up → Mission Control, Down → App Exposé, Left/Right → previous/next Space. These
        // are exactly the four actions the user asked for and the four their machine binds.
        result.append(profile(fallback, "Global",
                              up: .convention(.missionControl, GestureSystemAction.missionControl),
                              down: .convention(.appExposé, GestureSystemAction.appExpose),
                              left: .convention(.previousSpace, GestureSystemAction.previousSpace),
                              right: .convention(.nextSpace, GestureSystemAction.nextSpace),
                              tilt: .nativeHorizontalScroll))

        // ── Browsers
        let nextTab = GestureShortcut(key: GestureKeyCode.tab, flags: GestureShortcut.control)
        let previousTab = GestureShortcut(key: GestureKeyCode.tab,
                                          flags: GestureShortcut.control | GestureShortcut.shift)
        for (id, name) in [("com.microsoft.edgemac", "Microsoft Edge"),
                           ("com.apple.Safari", "Safari"),
                           ("com.google.Chrome", "Chrome")] {
            result.append(profile(id, name,
                                  up: .convention(.nextTab, GestureShortcut(key: GestureKeyCode.t, flags: GestureShortcut.command)),
                                  down: .convention(.previousTab, GestureShortcut(key: GestureKeyCode.w, flags: GestureShortcut.command)),
                                  left: .convention(.previousPage, back),
                                  right: .convention(.nextPage, forward),
                                  tilt: .convention(.nextTab, nextTab)))
        }

        // ── Dev & AI
        //
        // Up is Mission Control (the owner's choice, 2026-10-15): a system intent resolved
        // from this Mac's own binding, exactly like Global's Up, so it is not one app's key
        // dressed up as a shared default. Down stays Unassigned and this is the row the
        // honest rule is for: "toggle terminal" is ``⌃` `` in VS Code, `⌃`` in Cursor, and
        // something else again in Zed; "AI refactor" is `⌘I` in Cursor and `⌘K` in Claude.
        // Shipping either as a shared default would be a guess that looks verified.
        // Left/Right send **editor navigation** — the platform's own history
        // convention — rather than one app's pane-splitting keys, because which
        // direction means "split" vs "focus left group" differs per app.
        for (id, name) in [("com.microsoft.VSCode", "VS Code"), ("com.todesktop.230313mzl4w4u92", "Cursor"),
                           ("dev.zed.Zed", "Zed"), ("com.google.antigravity", "Antigravity"),
                           ("com.anthropic.claudefordesktop", "Claude")] {
            result.append(profile(id, name,
                                  up: .convention(.missionControl, GestureSystemAction.missionControl),
                                  down: .unassigned(.horizontalScroll),
                                  left: .convention(.previousPage, back),
                                  right: .convention(.nextPage, forward)))
        }

        // ── Terminals
        //
        // Two rows only, and the restraint is the point. `⌥←`/`⌥→` is a real
        // convention: Kitty, Terminal and iTerm2 all ship `macos_option_as_alt`
        // **off** precisely so those arrive as Option-Left/Right, and AppKit's own
        // `moveWordBackward:`/`moveWordForward:` are standard bindings. Everything
        // else stays Unassigned because `⌘T` is a new *window* here, `⌘W` can **kill
        // a running command**, and there is no shared "next pane" key. A wrong
        // keystroke in a terminal destroys work, so Unassigned is the honest cell.
        let terminalMap = profile("net.kovidgoyal.kitty", "Kitty",
                                  up: .unassigned(.zoomIn), down: .unassigned(.zoomOut),
                                  left: .convention(.previousItem, wordLeft),
                                  right: .convention(.nextItem, wordRight))
        for (id, name) in [("com.apple.Terminal", "Terminal"), ("com.googlecode.iterm2", "iTerm2")] {
            result.append(GestureProfile(id: id, name: name,
                                         defaults: terminalMap.defaults,
                                         gestureMap: terminalMap.gestureMap))
        }
        result.append(terminalMap)

        // ── Design & video
        //
        // Photoshop and CapCut are two different applications that happen to share
        // two shortcuts, and the profile says so by marking them `appShortcut`:
        // `⌘0` is "Fit on Screen" in Photoshop and "Fit to timeline" in CapCut, `⌘Z`
        // is Undo in both. Left/Right send the bracket pair, which is a brush/tool
        // size convention in Photoshop — **not** a claim about timeline scrubbing,
        // which is why nothing in this profile is labelled with a media verb.
        for (id, name) in [("com.adobe.Photoshop", "Photoshop"), ("com.lemon.lvoverseas", "CapCut")] {
            result.append(profile(id, name,
                                  up: .appShortcut(.zoomToFit, GestureShortcut(key: GestureKeyCode.zero, flags: GestureShortcut.command)),
                                  down: .appShortcut(.undo, GestureShortcut(key: GestureKeyCode.z, flags: GestureShortcut.command)),
                                  left: .appShortcut(.zoomOut, GestureShortcut(key: GestureKeyCode.leftBracket, flags: 0)),
                                  right: .appShortcut(.zoomIn, GestureShortcut(key: GestureKeyCode.rightBracket, flags: 0))))
        }

        // ── Office
        //
        // Two apps, **two tables**, because they are not the same application. The
        // brief is explicit that Word has no worksheets, so nothing here maps
        // sheet navigation; and Excel's `⌘Z` undoes the last cell edit while Word's
        // undoes text — same keys, same intent, so those two rows are shared and
        // marked as each app's shortcut. `⌃⇧Tab` is documented in **both** as "move
        // to previous sheet/field", so it is a convention row in each table
        // separately (not a fabricated shared one).
        result.append(profile("com.microsoft.Excel", "Excel",
                              up: .appShortcut(.zoomIn, zoomIn),
                              down: .appShortcut(.zoomOut, zoomOut),
                              left: .convention(.previousTab, previousTab),
                              right: .convention(.nextTab, nextTab)))
        result.append(profile("com.microsoft.Word", "Word",
                              up: .appShortcut(.zoomIn, zoomIn),
                              down: .appShortcut(.zoomOut, zoomOut),
                              left: .unassigned(.previousTab),
                              right: .unassigned(.nextTab)))

        // ── Messaging
        for (id, name) in [("com.hnc.Discord", "Discord"), ("com.vng.zalo", "Zalo"),
                           ("one.ayugram.AyuGramDesktop", "AyuGram")] {
            result.append(profile(id, name,
                                  up: .unassigned(.previousItem),
                                  down: .unassigned(.nextItem),
                                  left: .convention(.previousItem, GestureShortcut(key: GestureKeyCode.upArrow, flags: GestureShortcut.option)),
                                  right: .convention(.nextItem, GestureShortcut(key: GestureKeyCode.downArrow, flags: GestureShortcut.option))))
        }

        // ── Notes
        //
        // Down stays Unassigned: "add a block" (Notion `/`) and "new note"
        // (`⌘N` in Obsidian, `⌘N` in Notion but for a *page*) are different actions
        // with different consequences, so one shared cell would be wrong in one app.
        for (id, name) in [("md.obsidian", "Obsidian"), ("notion.id", "Notion")] {
            result.append(profile(id, name,
                                  up: .appShortcut(.nextItem, GestureShortcut(key: GestureKeyCode.p, flags: GestureShortcut.command)),
                                  down: .unassigned(.previousItem),
                                  left: .convention(.previousPage, GestureShortcut(key: GestureKeyCode.leftArrow, flags: GestureShortcut.command | GestureShortcut.option)),
                                  right: .convention(.nextPage, GestureShortcut(key: GestureKeyCode.rightArrow, flags: GestureShortcut.command | GestureShortcut.option))))
        }

        _ = (back, forward, nextSpace, previousSpace, zoomIn, zoomOut, wordLeft, wordRight)
        return result
    }()

    /// Bundle ids the presets used until 2026-10-15, mapped to the ids the apps really have.
    ///
    /// Measured on the owner's Mac (`mdfind "kMDItemCFBundleIdentifier == '…'"` plus each app's Info.plist): none of the
    /// old ids belonged to any installed app, so eight presets never applied and those apps fell through to Global —
    /// including Claude, the app the owner works in all day. `validate()` moves an override stored under an old id to
    /// the new one, so rows a user customised under "VS Code" keep working. Photoshop and iTerm2 are not installed on
    /// that Mac, so their ids are unmeasured. `scripts/check-gesture-bundle-ids.sh` re-runs the measurement.
    static let renamedBundleIDs: [String: String] = [
        "com.visualstudio.code": "com.microsoft.VSCode",
        "com.cursor.ide": "com.todesktop.230313mzl4w4u92",
        "com.antigravity.ide": "com.google.antigravity",
        "com.anthropic.claude": "com.anthropic.claudefordesktop",
        "com.lemon.CapCutMac": "com.lemon.lvoverseas",
        "org.telegram.ayugram": "one.ayugram.AyuGramDesktop",
        "co.elastic.obsidian": "md.obsidian",
        "com.notion.Notion-App": "notion.id",
    ]

    /// Which preset governs a bundle, or nil when the app has none of its own and
    /// therefore inherits Global. Published so the UI can say "this app has no
    /// preset" without re-deriving the lookup and risking disagreement with the
    /// resolver.
    static func hasPreset(bundle: String) -> Bool {
        bundle != fallback && all.contains { $0.id == bundle }
    }

    /// Single resolver for both Settings row display and GestureWorker dispatch.
    static func resolve(overrides: [String: [GestureDirection: GestureAction]],
                        bundle: String,
                        direction: GestureDirection) -> GestureAction {
        if let explicit = overrides[bundle]?[direction] { return explicit }
        let profile = all.first { $0.id == bundle } ?? all[0]
        // Legacy alias: keep shared family overrides readable as second tier.
        if all.contains(where: { $0.id == bundle }), let shared = overrides[profile.id]?[direction] {
            return shared
        }
        return profile.defaults[direction] ?? .unassigned
    }
}

enum InstantAction: String, Codable, CaseIterable, Equatable, Sendable {
    case back
    case forward

    var labelKey: String {
        switch self {
        case .back: return "Lùi"
        case .forward: return "Tiến"
        }
    }

    var shortcut: GestureShortcut {
        switch self {
        case .back:
            return GestureShortcut(key: 33, flags: GestureShortcut.command) // [ (leftBracket)
        case .forward:
            return GestureShortcut(key: 30, flags: GestureShortcut.command) // ] (rightBracket)
        }
    }
}

enum ButtonAction: Codable, Equatable, Sendable {
    case unassigned
    case instant(InstantAction)
    case shortcut(GestureShortcut)

    var isAssigned: Bool {
        switch self {
        case .unassigned: return false
        case .instant, .shortcut: return true
        }
    }

    var labelKey: String {
        switch self {
        case .unassigned: return "Chưa gán"
        case .instant(let action): return action.labelKey
        case .shortcut: return "Phím tắt"
        }
    }
}

struct GestureConfigStore: Sendable {
    /// Default mapping (PATCH v10.2 R1):
    /// Button 4 (Upper side) -> .instant(.back)
    /// Button 5 (Lower side) -> .instant(.forward)
    static let defaultButtonActions: [Int: ButtonAction] = [
        4: .instant(.back),
        5: .instant(.forward)
    ]

    /// Resolves button action for a given event button number (0-based).
    /// Keys in `buttonActions` are user-facing button numbers (1-based: Button 4 = Upper side, Button 5 = Lower side).
    static func action(in actions: [Int: ButtonAction], forEventButton eventButton: Int) -> ButtonAction? {
        let displayButton = eventButton + 1
        if let byDisplay = actions[displayButton], byDisplay.isAssigned { return byDisplay }
        return nil
    }
}

struct GestureConfiguration: Codable, Sendable {
    /// The hold trigger used when nothing else is configured, and the value an invalid
    /// trigger is repaired to. Exposed so `validate()` and the stored property cannot
    /// disagree about what "the default" is. Default is Button 5 (Lower side button, eventButton 4).
    static let defaultTrigger: TriggerSource = .mouseButton(4)
    var enabled = false
    var trigger: TriggerSource = GestureConfiguration.defaultTrigger
    var deadzone = 12.0
    var tiltEnabled = false
    var debug = false
    var scrollButtonEnabled = false
    var scrollButton = GestureConfiguration.defaultScrollButton
    static let defaultScrollButton: Int = 3
    var tiltAvailable = false
    var overrides: [String: [GestureDirection: GestureAction]] = [:]
    var buttonActions: [Int: ButtonAction] = GestureConfigStore.defaultButtonActions
    var holdButtonSingleClickEnabled: Bool = true


    func action(bundle: String, direction: GestureDirection) -> GestureAction {
        GestureProfiles.resolve(overrides: overrides, bundle: bundle, direction: direction)
    }

    func source(bundle: String, direction: GestureDirection) -> GestureRowSource {
        if overrides[bundle]?[direction] != nil { return .userOverride }
        let isKnown = GestureProfiles.all.contains { $0.id == bundle }
        if isKnown {
            let profile = GestureProfiles.all.first { $0.id == bundle }!
            if profile.defaults[direction] != nil { return .preset }
            return .unassigned
        }
        if GestureProfiles.all[0].defaults[direction] != nil { return .presetGlobal }
        return .unassigned
    }

    mutating func validate() {
        if !trigger.isValid { trigger = Self.defaultTrigger }
        if !(1...31).contains(scrollButton) || scrollButton == trigger.buttonNumber {
            scrollButton = ScrollButtonRepair.defaultFor(trigger: trigger)
        }
        deadzone = deadzone.isFinite ? min(200, max(4, deadzone)) : 12
        if buttonActions.isEmpty {
            buttonActions = GestureConfigStore.defaultButtonActions
        }
        // Overrides saved under a bundle id the presets used to get wrong move to the real id. Where both exist, the
        // rows already under the real id win and the old ones only fill the directions it does not set.
        for (old, new) in GestureProfiles.renamedBundleIDs {
            guard let moved = overrides.removeValue(forKey: old) else { continue }
            overrides[new] = moved.merging(overrides[new] ?? [:]) { _, current in current }
        }
    }
}

enum GestureRowSource: Sendable { case preset, presetGlobal, userOverride, unassigned }

/// Keeps the scroll modifier from colliding with the gesture trigger.
///
/// A separate type because the rule is not "pick a number" — it is "pick a number
/// that is legal *and* is not the trigger", and the second half depends on a value
/// that lives elsewhere in the configuration. Having it in one place is what lets a
/// test pin that changing the trigger never leaves the two equal.
enum ScrollButtonRepair {
    /// The declared default for a given trigger: the next button up, wrapping inside
    /// the usable range. Never returns the trigger itself, and never returns 0.
    static func defaultFor(trigger: TriggerSource) -> Int {
        // A modifier trigger consumes no button, so the declared default is always
        // free and is returned as-is.
        guard let taken = trigger.buttonNumber else { return GestureConfiguration.defaultScrollButton }
        if taken != GestureConfiguration.defaultScrollButton { return GestureConfiguration.defaultScrollButton }
        return taken == 31 ? 1 : taken + 1
    }
}

struct GestureStroke: Sendable {
    private(set) var x = 0.0
    private(set) var y = 0.0
    private(set) var distance = 0.0
    mutating func move(dx: Double, dy: Double) {
        x += dx; y += dy
        distance += hypot(dx, dy)
    }
    func direction(deadzone: Double) -> GestureDirection? {
        guard distance >= deadzone, hypot(x,y) >= deadzone else { return nil }
        return abs(x) > abs(y) ? (x < 0 ? .left : .right) : (y < 0 ? .up : .down)
    }
    func isClick(deadzone: Double) -> Bool { distance < deadzone }
}
