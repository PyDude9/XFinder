import XCTest

/// Pins the symbolic-hotkey parsing and the resolution of **system actions** to real
/// chords, using the measured shapes of this machine's `com.apple.symbolichotkeys`.
///
/// Two live reads are used, and the fact that they disagree is the whole reason the Global
/// preset ships no constant any more:
///
///   * `unboundShape` — the 2026-09-22 read: ids 79–82 present with `enabled = 1` and **no
///     `value` block at all**, so nothing listened for `⌃←`/`⌃→`, and Mission Control sat on
///     `vk = 232` (an NX keytype, not a `CGKeyCode`).
///   * `boundShape` — the 2026-09-23 read, after the user set the shortcuts in System
///     Settings: ids 32/33/79–82 all carry a `⌃`-arrow chord with mask `0x840000`.
///
/// Every fixture below is copied from a real read, because the failure modes this type
/// guards against are *shape* bugs: `enabled` arriving as an integer rather than a `Bool`,
/// an enabled entry with no key, a chord whose modifier mask carries the secondary-fn bit,
/// and a keycode that is not a virtual keycode. Each produces a plausibly wrong answer if
/// the parser or the resolver guesses.
final class SpaceBindingTests: XCTestCase {

    /// Verbatim from the current live read. `enabled = 1` is an integer, and `8650752` is
    /// `0x840000` = `control | maskSecondaryFn` — Apple's own encoding for these arrow
    /// shortcuts, so the fn bit must survive all the way into the posted chord.
    private let boundShape: [String: Any] = [
        "32": ["enabled": 1, "value": ["parameters": [65535, 126, 8650752], "type": "standard"]],
        "33": ["enabled": 1, "value": ["parameters": [65535, 125, 8650752], "type": "standard"]],
        "34": ["enabled": 1, "value": ["parameters": [65535, 126, 8781824], "type": "standard"]],
        "79": ["enabled": 1, "value": ["parameters": [65535, 123, 8650752], "type": "standard"]],
        "80": ["enabled": 1, "value": ["parameters": [65535, 123, 8781824], "type": "standard"]],
        "81": ["enabled": 1, "value": ["parameters": [65535, 124, 8650752], "type": "standard"]],
        "82": ["enabled": 1, "value": ["parameters": [65535, 124, 8781824], "type": "standard"]],
    ]

    /// The earlier live read: the four Space ids are `enabled` with **no `value` block**, and
    /// Mission Control is on the NX keytype 232. Both facts are load-bearing.
    private let unboundShape: [String: Any] = [
        "32": ["enabled": 1, "value": ["parameters": [65535, 232, 0], "type": "standard"]],
        "34": ["enabled": 1, "value": ["parameters": [65535, 232, 131072], "type": "standard"]],
        "79": ["enabled": 1],
        "80": ["enabled": 1],
        "81": ["enabled": 1],
        "82": ["enabled": 1],
    ]

    // MARK: the measured parsing failure modes

    /// The bug this whole type exists for: an entry the OS reports as *enabled* while it
    /// carries no key. Reading `enabled` alone would call these bound and the page would
    /// promise Spaces switching that cannot happen.
    func testEnabledWithoutAValueBlockIsNotABinding() {
        let entries = SpaceBinding.parse(unboundShape)
        let space = SpaceBinding.spaceEntries(entries)
        XCTAssertEqual(space.count, 4, "all four Space ids must be seen")
        for entry in space {
            XCTAssertTrue(entry.enabled, "fixture says enabled")
            XCTAssertNil(entry.keyCode, "fixture has no parameters")
            XCTAssertFalse(entry.isBound, "enabled with no key is NOT a binding")
        }
        XCTAssertFalse(SpaceBinding.hasAnySpaceBinding(entries),
                       "this fixture is the measured unbound state")
    }

    /// `enabled` is written by the OS as `1`/`0`, which does **not** bridge to `Bool`.
    /// A parser that only accepts `Bool` silently treats every OS-written entry as
    /// enabled — correct for a switch that is on, and wrong for one the user turned off.
    func testEnabledIsReadFromAnIntegerNotJustABool() {
        let raw: [String: Any] = [
            "79": ["enabled": 0, "value": ["parameters": [65535, 123, 262144]]],
            "81": ["enabled": 1, "value": ["parameters": [65535, 124, 262144]]],
        ]
        let entries = SpaceBinding.parse(raw)
        let left = entries.first { $0.id == 79 }
        let right = entries.first { $0.id == 81 }
        XCTAssertEqual(left?.enabled, false, "integer 0 must read as disabled")
        XCTAssertEqual(right?.enabled, true, "integer 1 must read as enabled")
        // A disabled entry is not a binding even though it has keys — this is the case the
        // `as? Bool` bug got wrong.
        XCTAssertFalse(left?.isBound ?? true, "a switched-off shortcut is not bound")
        XCTAssertTrue(SpaceBinding.hasAnySpaceBinding(entries),
                      "one Space move is bound, so the pair is not entirely dead")
    }

    func testEnabledAsNSNumberAndString() {
        XCTAssertEqual(SpaceBinding.bool(NSNumber(value: 1)), true)
        XCTAssertEqual(SpaceBinding.bool(NSNumber(value: 0)), false)
        XCTAssertEqual(SpaceBinding.bool(true), true)
        XCTAssertEqual(SpaceBinding.bool(false), false)
        XCTAssertEqual(SpaceBinding.bool("1"), true)
        XCTAssertEqual(SpaceBinding.bool("true"), true)
        XCTAssertEqual(SpaceBinding.bool("no"), false)
        XCTAssertNil(SpaceBinding.bool(nil), "absent must be distinguishable from false")
        XCTAssertNil(SpaceBinding.bool([1, 2]))
    }

    /// An absent `enabled` means the shortcut is on: that is how the OS stores one the
    /// user never touched. Defaulting it to `false` would report working shortcuts dead.
    func testAbsentEnabledDefaultsToOn() {
        let entries = SpaceBinding.parse(["79": ["value": ["parameters": [65535, 123, 262144]]]])
        XCTAssertEqual(entries.first?.enabled, true)
        XCTAssertEqual(entries.first?.keyCode, 123)
        XCTAssertEqual(entries.first?.modifiers, 262144)
    }

    // MARK: system actions resolve to this machine's own chords

    /// The fix, as a test. The four intents the Global preset uses must each resolve to the
    /// chord **this machine** binds — not to a constant the module ships. `⌃↑` is what this
    /// host happens to use; the point is that it was *read*.
    func testSystemActionsResolveFromTheMachinesOwnBindings() {
        let bindings = GestureSystemBindings(entries: SpaceBinding.parse(boundShape))
        XCTAssertEqual(bindings.shortcut(for: .missionControl),
                       GestureShortcut(key: 126, flags: 8650752))
        XCTAssertEqual(bindings.shortcut(for: .appExpose),
                       GestureShortcut(key: 125, flags: 8650752),
                       "App Exposé is id 33, a different id from Mission Control's 32")
        XCTAssertEqual(bindings.shortcut(for: .previousSpace),
                       GestureShortcut(key: 123, flags: 8650752))
        XCTAssertEqual(bindings.shortcut(for: .nextSpace),
                       GestureShortcut(key: 124, flags: 8650752))
        XCTAssertEqual(bindings.boundActions.count, 5,
                       "all five actions are bound in this fixture")
    }

    /// Apple encodes these arrows with the **secondary-fn bit** set (`0x800000`). It is part
    /// of the binding, not noise: masking it to the four "real" modifier bits would post a
    /// chord the system does not match. This pins that the mask survives intact while the
    /// control bit is still recognised.
    func testTheFnBitIsPreservedAndControlIsStillReadable() {
        let bindings = GestureSystemBindings(entries: SpaceBinding.parse(boundShape))
        let chord = bindings.shortcut(for: .missionControl)
        XCTAssertEqual(chord?.flags ?? 0, 8650752,
                       "the fn bit must survive; masking it away posts a chord macOS ignores")
        XCTAssertEqual((chord?.flags ?? 0) & GestureShortcut.modifierMask, GestureShortcut.control,
                       "the control bit is the part the label and the mask both need")
        XCTAssertEqual(chord?.label, "⌃↑",
                       "the display ignores the fn bit, so the row reads like System Settings")
    }

    /// A machine that bound only the shifted `⇧⌃←` variant (id 80) still switches Spaces.
    /// Preferring 79 and falling back to 80 is what makes that work; without the fallback
    /// the row would claim macOS has no shortcut while the user is looking at one.
    func testAlternateSpaceIdIsUsedWhenThePrimaryIsUnbound() {
        let raw: [String: Any] = [
            "80": ["enabled": 1, "value": ["parameters": [65535, 123, 8781824]]],
        ]
        let bindings = GestureSystemBindings(entries: SpaceBinding.parse(raw))
        XCTAssertEqual(bindings.shortcut(for: .previousSpace),
                       GestureShortcut(key: 123, flags: 8781824),
                       "the shifted variant 80 must be used when 79 has no key")
        XCTAssertNil(bindings.shortcut(for: .nextSpace),
                     "81/82 are absent, so next-Space is genuinely unbound")
    }

    /// An action this machine does not bind resolves to `nil`, never to a guess. That is the
    /// value the engine reads to decide to post **nothing** and record why.
    func testAnUnboundActionResolvesToNilRatherThanAGuess() {
        let bindings = GestureSystemBindings(entries: SpaceBinding.parse(unboundShape))
        XCTAssertNil(bindings.shortcut(for: .missionControl),
                     "vk 232 is an NX keytype, not a CGKeyCode, so it is not a usable chord")
        XCTAssertNil(bindings.shortcut(for: .previousSpace))
        XCTAssertNil(bindings.shortcut(for: .nextSpace))
        XCTAssertTrue(bindings.isEmpty, "the unbound fixture binds nothing at all")
        XCTAssertTrue(GestureSystemBindings.empty.isEmpty)
        XCTAssertNil(GestureSystemBindings.empty.shortcut(for: .missionControl))
    }

    /// The NX keytype 232 is stored in the same `parameters` slot a virtual keycode would
    /// be. Posting it would produce garbage, so `boundShortcut` rejects anything outside the
    /// `CGKeyCode` range. Pinned because "the dictionary had a number" looked like a binding.
    func testAnNXKeytypeIsNotTreatedAsAKeystroke() {
        XCTAssertNil(SpaceBinding.boundShortcut(for: SpaceBinding.Hotkey.missionControl,
                                                in: SpaceBinding.parse(unboundShape)))
        // The range check is inclusive of the real keycodes, so a normal chord is unaffected.
        XCTAssertEqual(SpaceBinding.boundShortcut(for: SpaceBinding.Hotkey.missionControl,
                                                  in: SpaceBinding.parse(boundShape)),
                       GestureShortcut(key: 126, flags: 8650752))
    }

    func testShowDesktopKeepsItsShift() {
        let entries = SpaceBinding.parse(boundShape)
        let sd = entries.first { $0.id == SpaceBinding.Hotkey.showDesktop.rawValue }
        XCTAssertEqual(sd?.keyCode, 126, "ids 32 and 34 share the key; only the modifier differs")
        XCTAssertEqual(sd?.modifiers, 8781824)
        XCTAssertFalse(SpaceBinding.Hotkey.showDesktop.movesASpace)
        XCTAssertFalse(SpaceBinding.Hotkey.appExpose.movesASpace)
    }

    /// `appExpose` is id **33**, not 32. The first version of the table omitted it entirely,
    /// so App Exposé could not be resolved even on a machine that had it bound.
    func testAppExposeHasItsOwnId() {
        XCTAssertEqual(SpaceBinding.Hotkey.appExpose.rawValue, 33)
        XCTAssertEqual(SpaceBinding.hotkeys(for: .appExpose), [.appExpose])
        XCTAssertEqual(SpaceBinding.hotkeys(for: .previousSpace),
                       [.moveLeftASpace, .moveLeftASpaceAlt],
                       "preference order is part of the contract, not an implementation detail")
    }

    /// A Space binding, when one exists, must be reported as the keystroke it is — and
    /// must come from the plist rather than from a constant.
    func testBoundSpaceShortcutIsReadFromThePlist() {
        let raw: [String: Any] = [
            "79": ["enabled": 1, "value": ["parameters": [65535, 123, 262144]]],
        ]
        let entries = SpaceBinding.parse(raw)
        XCTAssertTrue(SpaceBinding.hasAnySpaceBinding(entries))
        XCTAssertEqual(SpaceBinding.boundShortcut(for: .moveLeftASpace, in: entries),
                       GestureShortcut(key: 123, flags: GestureShortcut.control))
        // An id with no entry yields nil rather than a guess.
        XCTAssertNil(SpaceBinding.boundShortcut(for: .moveRightASpace, in: entries))
    }

    // MARK: the honesty property

    /// The regression guard stated as a property: no built-in preset may ship a *constant*
    /// for one of the system intents, because the correct chord is machine-dependent. The
    /// Global arms are `.systemAction` rows, whose `shortcut` is nil by construction and
    /// whose key is resolved at dispatch time — so this asserts the constant is absent, which
    /// is exactly what the round-7 report ("recognised but does nothing") was about.
    func testNoPresetShipsASpaceConstant() {
        let cfg = GestureConfiguration()
        for direction in [GestureDirection.up, .down, .left, .right] {
            let action = cfg.action(bundle: "whatever.unknown", direction: direction)
            XCTAssertEqual(GestureMap.systemAction(of: action), directionSystemAction(direction),
                           "\(direction.rawValue) must be an intent, not a key")
            XCTAssertNil(GestureMap.shortcut(of: action),
                         "\(direction.rawValue) ships a constant chord for a machine-dependent action")
        }
    }

    private func directionSystemAction(_ direction: GestureDirection) -> GestureSystemAction? {
        switch direction {
        case .up: return .missionControl
        case .down: return .appExpose
        case .left: return .previousSpace
        case .right: return .nextSpace
        case .tiltLeft, .tiltRight: return nil
        }
    }
}
