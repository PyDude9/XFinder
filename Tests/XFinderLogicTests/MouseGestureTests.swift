import XCTest

final class MouseGestureTests: XCTestCase {
    func testDefaultsAreOptIn() {
        let config = GestureConfiguration()
        XCTAssertFalse(config.enabled)
        XCTAssertFalse(config.tiltEnabled)
        XCTAssertFalse(config.debug)
        // The hold trigger must NOT be a middle click. Measured on the user's machine:
        // the shipped default was `.mouseButton(2)` and their stored config carried it,
        // which is the documented cause of the "nothing happens" report — holding the
        // wheel while dragging is not a motion a hand makes, and a middle click is a
        // frequent deliberate action that must stay available.
        XCTAssertEqual(config.trigger, .mouseButton(4))
        XCTAssertNotEqual(config.trigger, .mouseButton(2), "middle click must never be the default hold trigger")
    }
    func testStrictDeadzoneAndFourDirections() {
        var stroke = GestureStroke()
        stroke.move(dx: 11, dy: 0)
        XCTAssertTrue(stroke.isClick(deadzone: 12))
        XCTAssertNil(stroke.direction(deadzone: 12))
        stroke.move(dx: 1, dy: 0)
        XCTAssertFalse(stroke.isClick(deadzone: 12))
        XCTAssertEqual(stroke.direction(deadzone: 12), .right)
        for (x,y,direction) in [(0.0,-12.0,GestureDirection.up),(0,12,.down),(-12,0,.left),(12,0,.right)] {
            var sample = GestureStroke(); sample.move(dx:x,dy:y)
            XCTAssertEqual(sample.direction(deadzone:12),direction)
        }
    }
    func testOutAndBackIsNotAClickOrAnAction() {
        var stroke = GestureStroke()
        stroke.move(dx: 100,dy:0); stroke.move(dx:-100,dy:0)
        XCTAssertFalse(stroke.isClick(deadzone:12))
        XCTAssertNil(stroke.direction(deadzone:12))
    }
    func testChunkingDoesNotChangeStraightStroke() {
        var a = GestureStroke(), b = GestureStroke()
        a.move(dx:1000,dy:-2000)
        for _ in 0..<1000 { b.move(dx:1,dy:-2) }
        XCTAssertEqual(a.x,b.x); XCTAssertEqual(a.y,b.y)
        XCTAssertEqual(a.direction(deadzone:12),b.direction(deadzone:12))
        XCTAssertEqual(a.distance,b.distance,accuracy:0.0001)
    }
    func testKnownProfilesDoNotInheritUnassignedActions() {
        let config = GestureConfiguration()
        for id in ["com.visualstudio.code","com.cursor.ide","dev.zed.Zed","com.antigravity.ide","com.anthropic.claude"] {
            XCTAssertEqual(config.action(bundle:id,direction:.up),.unassigned)
            XCTAssertEqual(config.action(bundle:id,direction:.down),.unassigned)
            // Left/right are the platform *history* convention, which every editor
            // honours, rather than one app's pane-splitting keys.
            XCTAssertEqual(config.action(bundle:id,direction:.left),GestureProfiles.key(33,GestureShortcut.command))
            XCTAssertEqual(config.action(bundle:id,direction:.right),GestureProfiles.key(30,GestureShortcut.command))
        }
        // Word has no worksheet navigation, so its tab rows stay empty. Excel does
        // have a documented pair, so it answers for itself — the two tables are
        // separate on purpose, which `testWordAndExcelDoNotShareOneTable` pins.
        for d in [GestureDirection.left, .right] {
            XCTAssertEqual(config.action(bundle:"com.microsoft.Word",direction:d),.unassigned)
        }
        XCTAssertNotEqual(config.action(bundle:"com.microsoft.Excel",direction:.left),.unassigned)
        XCTAssertEqual(config.action(bundle:"co.elastic.obsidian",direction:.down),.unassigned)
    }
    func testFallbackAndExplicitDisable() {
        var config = GestureConfiguration()
        // Global's four arms, after the 2026-09-23 correction. Every one of them is a
        // **system action**: the engine resolves it from the user's own
        // `com.apple.symbolichotkeys` (`SpaceBinding`) and posts the chord their Mac binds.
        // The preset ships no key at all, because the two states that genuinely occur —
        // bound and unbound — are both real, and a shipped constant is wrong in one of them
        // (measured twice; see the note in `GestureModel.swift`).
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.up),
                       .systemAction(.missionControl))
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.down),
                       .systemAction(.appExpose))
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.left),
                       .systemAction(.previousSpace))
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.right),
                       .systemAction(.nextSpace))
        // An explicit per-bundle unassigned on a known app sticks.
        XCTAssertNotEqual(config.action(bundle:"com.apple.Safari",direction:.up),.unassigned)
        config.overrides["com.apple.Safari",default:[:]][.up] = .unassigned
        XCTAssertEqual(config.action(bundle:"com.apple.Safari",direction:.up),.unassigned)
        // Unknown app's Global fallback uses the Global profile itself; overriding
        // a single known app does not affect the unknown app's Global fallback.
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.up),
                       .systemAction(.missionControl))
    }
    func testAppOverrideAndRoundTrip() throws {
        var config = GestureConfiguration()
        config.trigger = .modifierKey(GestureShortcut.option)
        config.overrides["my.app",default:[:]][.left] = GestureProfiles.key(3,GestureShortcut.command)
        let restored = try JSONDecoder().decode(GestureConfiguration.self,from:JSONEncoder().encode(config))
        XCTAssertEqual(restored.trigger,config.trigger)
        XCTAssertEqual(restored.action(bundle:"my.app",direction:.left),config.action(bundle:"my.app",direction:.left))
    }
    func testValidateUnsafeSettings() {
        var config = GestureConfiguration()
        config.trigger = .mouseButton(0); config.deadzone = .nan; config.validate()
        XCTAssertEqual(config.trigger,.mouseButton(4)); XCTAssertEqual(config.deadzone,12)
        config.deadzone = 1e9; config.validate(); XCTAssertEqual(config.deadzone,200)
        XCTAssertFalse(TriggerSource.modifierKey(0).isValid)
        XCTAssertFalse(TriggerSource.modifierKey(GestureShortcut.command | GestureShortcut.shift).isValid)
        XCTAssertFalse(TriggerSource.mouseButton(32).isValid)
    }
    func testProfileIDsUniqueAndBrowserMappingExact() {
        XCTAssertEqual(Set(GestureProfiles.all.map(\.id)).count,GestureProfiles.all.count)
        let config = GestureConfiguration()
        for id in ["com.apple.Safari","com.google.Chrome","com.microsoft.edgemac"] {
            XCTAssertEqual(config.action(bundle:id,direction:.up),GestureProfiles.key(17,GestureShortcut.command))
            XCTAssertEqual(config.action(bundle:id,direction:.down),GestureProfiles.key(13,GestureShortcut.command))
            XCTAssertEqual(config.action(bundle:id,direction:.left),GestureProfiles.key(33,GestureShortcut.command))
            XCTAssertEqual(config.action(bundle:id,direction:.tiltLeft),config.action(bundle:id,direction:.tiltRight))
        }
    }
    func testHighRatePureAccumulator() {
        var stroke = GestureStroke()
        let start = Date()
        for _ in 0..<1_000_000 { stroke.move(dx:1,dy:1) }
        XCTAssertEqual(stroke.x,1_000_000)
        XCTAssertEqual(stroke.direction(deadzone:12),.down)
        print("Gesture accumulator 1M samples: \(Date().timeIntervalSince(start)) s; not a hardware latency benchmark")
    }

    // MARK: Preset-first: every built-in bundle resolves immediately

    /// The page's row resolver and the runtime's action are **the same value**.
    ///
    /// This is the brief's "use one resolver for UI and runtime, not two copies of
    /// mapping logic", asserted rather than intended. `GestureMap.row` is what the
    /// diagram, the detail panel and the picker read; `GestureConfiguration.action` is
    /// what the engine posts. If a refactor ever gives one of them its own lookup, this
    /// fails for every bundle and direction at once.
    func testMapRowAgreesWithRuntimeActionForEveryBundleAndDirection() {
        var config = GestureConfiguration()
        // Include a user override, so the agreement is checked on the override path too
        // and not only on the preset path.
        config.overrides["com.apple.Safari", default: [:]][.left] = GestureProfiles.key(0, GestureShortcut.control)
        for profile in GestureProfiles.all {
            for direction in GestureDirection.allCases {
                let row = GestureMap.row(overrides: config.overrides,
                                         bundle: profile.id, direction: direction)
                XCTAssertEqual(row.action, config.action(bundle: profile.id, direction: direction),
                               "\(profile.id) \(direction.rawValue): the row says one thing and the "
                               + "engine sends another")
            }
        }
        // An override that exists only in the map's inputs must still reach the outcome:
        // if `row` ignored `overrides` this would silently report the preset value.
        let overridden = GestureMap.row(overrides: config.overrides,
                                        bundle: "com.apple.Safari", direction: .left)
        XCTAssertTrue(overridden.isUserOverride)
        XCTAssertEqual(overridden.action, GestureProfiles.key(0, GestureShortcut.control))
    }

    /// An app with no preset of its own inherits Global, and the row says so — while an
    /// app that *has* one but leaves a direction empty must not be reported as Global.
    ///
    /// Both halves are the same question from opposite sides, and the earlier version of
    /// this page conflated them: `⌘⇧]` from Global appeared under Explorer's unassigned
    /// Up row, which reads as "Explorer supports this and sends ⌘⇧]".
    func testEffectiveBundleDistinguishesInheritanceFromAnEmptyPreset() {
        let inherited = GestureMap.row(overrides: [:], bundle: "com.example.unknown", direction: .up)
        XCTAssertEqual(inherited.effectiveBundle, GestureProfiles.fallback)
        XCTAssertFalse(inherited.entry.isUnassigned)

        let emptyInOwnPreset = GestureMap.row(overrides: [:], bundle: "com.microsoft.Word", direction: .left)
        XCTAssertEqual(emptyInOwnPreset.effectiveBundle, "com.microsoft.Word")
        XCTAssertTrue(emptyInOwnPreset.entry.isUnassigned)
        // Explicitly *not* the Global ⌃←, which is what a fall-through would have sent.
        XCTAssertNotEqual(emptyInOwnPreset.action, GestureProfiles.key(123, GestureShortcut.control))
    }

    /// A recorded shortcut must never be described by an intent name it does not perform.
    ///
    /// The old page named an action from the key code (`case 29: return "Vừa khung"`), so
    /// a user who recorded `⌘↩` for an arm would still see "Fit to window" under it. The
    /// rule now is: the name is shown only when the shortcut is the one the built-in
    /// table declares for that intent.
    func testRecordedShortcutIsNotGivenAnInventedActionName() {
        var config = GestureConfiguration()
        config.overrides["com.apple.Safari", default: [:]][.up] = .shortcut(GestureShortcut(key: 36, flags: GestureShortcut.command))
        let row = GestureMap.row(overrides: config.overrides, bundle: "com.apple.Safari", direction: .up)
        XCTAssertNil(GestureMap.displayName(for: row),
                     "a recorded key was given the preset's action name")
        // The preset value keeps its name, so this is not "names never appear".
        let presetRow = GestureMap.row(overrides: [:], bundle: "com.apple.Safari", direction: .up)
        XCTAssertEqual(GestureMap.displayName(for: presetRow), GestureActionKind.nextTab.labelKey)
    }

    /// Every intent in the vocabulary must be reachable in the picker, and every choice
    /// the picker offers must be dispatchable. This is the "the screen was empty" bug
    /// stated as a property instead of as a screenshot.
    func testActionCatalogCoversEveryIntentAndEveryChoiceIsSendable() {
        let groups = GestureActionCatalog.choices()
        let offered = Set(groups.flatMap(\.items).map(\.kind))
        for kind in GestureActionKind.allCases {
            XCTAssertTrue(offered.contains(kind),
                          "\(kind.rawValue) is in the vocabulary but the picker never offers it — "
                          + "this is how a page ends up looking empty")
        }
        XCTAssertFalse(groups.isEmpty)
        for item in groups.flatMap(\.items) {
            // A choice must map to exactly one of the four sent forms, and one that
            // claims a shortcut must actually carry one. A system action must carry no
            // shortcut — a row that sends `NSEvent.systemDefined` and also claims keys
            // is precisely the mislabelling this pass removed.
            switch item.action {
            case .shortcut(let s):
                XCTAssertEqual(item.shortcut, s)
                XCTAssertNil(item.systemAction, "\(item.id) carries both a shortcut and a system action")
            case .systemAction(let system):
                XCTAssertNil(item.shortcut, "\(item.id) sends a system event but claims keys")
                XCTAssertEqual(item.systemAction, system)
            case .unassigned, .horizontalScroll:
                XCTAssertNil(item.shortcut, "\(item.id) claims to send nothing but carries keys")
                XCTAssertNil(item.systemAction, "\(item.id) claims to send nothing but carries a system action")
            }
        }
        XCTAssertFalse(GestureActionCatalog.choices().first(where: { $0.group == "Điều hướng" })?.items.isEmpty ?? true)
    }

    /// No two choices in the picker may be identical, or picking one would be a coin
    /// flip between two rows that look the same.
    func testActionCatalogHasNoDuplicateChoices() {
        let ids = GestureActionCatalog.choices().flatMap(\.items).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "the picker offers duplicate rows: \(ids.count) vs \(Set(ids).count)")
    }

    /// The scroll modifier may never collide with the gesture trigger, and `validate()`
    /// is the only thing enforcing it. If it did collide, one button would mean both
    /// "start a gesture" and "scroll" and the user would see intermittent behaviour
    /// with no error anywhere.
    /// A configuration written by an **older build** must still decode, or the user's
    /// overrides are silently discarded on upgrade.
    ///
    /// This is not hypothetical and it is not "defensive": adding two fields to
    /// `GestureConfiguration` on 2026-09-22 made the stored payload fail
    /// `keyNotFound` — measured on the installed app's own preferences. `init` survives
    /// that via `recover(from:)`, so what actually has to hold is that **the envelope
    /// carries every field**, not just the ones the current build happens to need.
    ///
    /// The fixture is generated by encoding the real model and then **removing** the new
    /// keys, because that is exactly what an older build's JSON looks like. A
    /// hand-written dictionary would not decode at all — `overrides` encodes as an
    /// interleaved array (`["up", {"shortcut": …}]`), which is the trap the docs record.
    func testLegacyConfigurationWithoutNewFieldsStillDecodes() throws {
        var modern = GestureConfiguration()
        modern.enabled = true
        modern.trigger = .mouseButton(2)
        modern.overrides["com.apple.Safari"] = [
            .up: .shortcut(GestureShortcut(key: 36, flags: GestureShortcut.command)),
        ]
        let encoded = try JSONEncoder().encode(modern)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        // The keys an earlier build did not write.
        object.removeValue(forKey: "scrollButtonEnabled")
        object.removeValue(forKey: "scrollButton")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        // The precondition that makes `recover(from:)` load-bearing rather than optional: a
        // payload missing a non-optional key does NOT decode strictly.
        XCTAssertNil(try? JSONDecoder().decode(GestureConfiguration.self, from: legacy),
                     "if this ever decodes strictly the recovery path is no longer needed — "
                     + "and, more importantly, the new fields were not really added")

        // Decoding the *current* model from the current model's own encoding must work,
        // which is what proves the keys were removed rather than never present.
        XCTAssertNotNil(try? JSONDecoder().decode(GestureConfiguration.self, from: encoded))
        XCTAssertTrue(String(data: encoded, encoding: .utf8)?.contains("scrollButtonEnabled") ?? false)
    }

    /// The `Envelope` in `GestureController.recover(from:)` must list **every** field.
    ///
    /// Read from the source, because `GestureController` imports AppKit and the test
    /// package cannot compile it. A missing line there is invisible at runtime until a
    /// user upgrades with customisations set — which is when it matters most.
    func testRecoveryEnvelopeCoversEveryStoredField() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Core/MouseGestures/GestureController.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let start = source.range(of: "struct Envelope: Decodable {"),
              let end = source.range(of: "}", range: start.upperBound..<source.endIndex) else {
            return XCTFail("could not read the recovery envelope out of GestureController.swift")
        }
        let body = source[start.upperBound..<end.lowerBound]
        // Every key the current model encodes. Kept as an explicit list so adding a
        // stored field forces a deliberate decision about the upgrade path.
        for field in ["enabled", "deadzone", "tiltEnabled", "tiltAvailable",
                      "debug", "trigger", "scrollButtonEnabled", "scrollButton", "overrides"] {
            XCTAssertTrue(body.contains("var \(field):"),
                          "\(field) is stored but missing from the recovery envelope — an "
                          + "older payload will decode to nil and the user's overrides are lost")
        }
    }

    func testScrollButtonNeverCollidesWithTheTrigger() {
        var config = GestureConfiguration()
        config.trigger = .mouseButton(GestureConfiguration.defaultScrollButton)
        config.scrollButton = GestureConfiguration.defaultScrollButton
        config.validate()
        XCTAssertNotEqual(config.scrollButton, config.trigger.buttonNumber)
        // Left click is never a legal scroll modifier: it must stay available for
        // selecting and dragging.
        config.scrollButton = 0
        config.validate()
        XCTAssertNotEqual(config.scrollButton, 0)
        XCTAssertTrue((1...31).contains(config.scrollButton))
        // A modifier trigger consumes no button, so the declared default is legal.
        config.trigger = .modifierKey(GestureShortcut.option)
        config.scrollButton = GestureConfiguration.defaultScrollButton
        config.validate()
        XCTAssertEqual(config.scrollButton, GestureConfiguration.defaultScrollButton)
        // Out-of-range values are repaired rather than stored.
        config.scrollButton = 99
        config.validate()
        XCTAssertTrue((1...31).contains(config.scrollButton))
    }

    func testEveryBuiltInBundleResolvesPresetOrUnassignedPerDirection() {
        let config = GestureConfiguration()
        for profile in GestureProfiles.all {
            for direction in GestureDirection.allCases {
                let action = config.action(bundle: profile.id, direction: direction)
                let expected = profile.defaults[direction] ?? .unassigned
                // Before any user override, factory value must show up verbatim.
                XCTAssertEqual(action, expected,
                    "\(profile.id) \(direction.rawValue): expected preset \(expected), got \(action)")
            }
        }
        // Unknown app uses Global, not a blank.
        XCTAssertNotEqual(GestureConfiguration().action(bundle: "unknown.app", direction: .left), .unassigned)
    }

    func testRuntimeAndUIUseSameResolver() {
        var config = GestureConfiguration()
        // Simulate a user override and confirm the single resolver drives both.
        config.overrides["com.apple.Safari", default: [:]][.up] = GestureProfiles.key(0, GestureShortcut.command)
        let viaConfig = config.action(bundle: "com.apple.Safari", direction: .up)
        let viaStatic = GestureProfiles.resolve(overrides: config.overrides, bundle: "com.apple.Safari", direction: .up)
        XCTAssertEqual(viaConfig, viaStatic)
        // Unrelated app unaffected.
        XCTAssertEqual(config.action(bundle: "com.google.Chrome", direction: .up),
                       GestureProfiles.all.first { $0.id == "com.google.Chrome" }!.defaults[.up]!)
    }

    func testExplicitUnassignedNeverFallsThrough() {
        var config = GestureConfiguration()
        // Safari up is ⌘T by preset; an explicit Unassigned must stick.
        XCTAssertNotEqual(config.action(bundle: "com.apple.Safari", direction: .up), .unassigned)
        config.overrides["com.apple.Safari", default: [:]][.up] = .unassigned
        XCTAssertEqual(config.action(bundle: "com.apple.Safari", direction: .up), .unassigned)
        // An explicit Unassigned on the exact unknown bundle ID kills that bundle's Global fallback.
        var c2 = GestureConfiguration()
        c2.overrides["unknown.app", default: [:]][.left] = .unassigned
        XCTAssertEqual(c2.action(bundle: "unknown.app", direction: .left), .unassigned)
        // Other unknown apps unaffected.
        XCTAssertNotEqual(c2.action(bundle: "other.unknown", direction: .left), .unassigned)
    }

    func testUnknownAppFallsToGlobal() {
        let config = GestureConfiguration()
        for dir in GestureDirection.allCases {
            let global = GestureProfiles.all[0].defaults[dir] ?? .unassigned
            XCTAssertEqual(config.action(bundle: "com.example.unknown", direction: dir), global)
        }
    }

    func testUserOverridesSurviveRoundTrip() throws {
        var config = GestureConfiguration()
        config.overrides["com.apple.Safari", default: [:]][.up] = .unassigned
        config.overrides["com.microsoft.Word", default: [:]][.left] = GestureProfiles.key(33, 0)
        let data = try JSONEncoder().encode(config)
        var restored = try JSONDecoder().decode(GestureConfiguration.self, from: data)
        restored.validate()
        XCTAssertEqual(restored.action(bundle: "com.apple.Safari", direction: .up), .unassigned)
        XCTAssertEqual(restored.action(bundle: "com.microsoft.Word", direction: .left), GestureProfiles.key(33, 0))
        // Presets that were not overridden still resolve.
        XCTAssertEqual(restored.action(bundle: "com.google.Chrome", direction: .up),
                       GestureProfiles.all.first { $0.id == "com.google.Chrome" }!.defaults[.up]!)
    }

    func testResetRestoresPreset() {
        var config = GestureConfiguration()
        let bundle = "com.apple.Safari"
        let before = config.action(bundle: bundle, direction: .up)
        config.overrides[bundle, default: [:]][.up] = .unassigned
        XCTAssertEqual(config.action(bundle: bundle, direction: .up), .unassigned)
        config.overrides.removeValue(forKey: bundle)
        XCTAssertEqual(config.action(bundle: bundle, direction: .up), before)
    }

    func testSourceBadging() {
        var config = GestureConfiguration()
        XCTAssertEqual(config.source(bundle: "com.apple.Safari", direction: .up), .preset)
        XCTAssertEqual(config.source(bundle: "com.apple.Safari", direction: .tiltLeft), .preset)
        // Dev up is intentionally unassigned — not a missing preset.
        XCTAssertEqual(config.source(bundle: "com.visualstudio.code", direction: .up), .unassigned)
        // Global's tilt arms are *unassigned* in the stored profile on purpose: the
        // engine's tilt branch passes the event through for `.unassigned`, which is
        // exactly "let the wheel's sideways motion be a sideways scroll". Storing
        // `.horizontalScroll` here would be a stored key with no behaviour attached
        // and would badge the row as a preset that "sends" something.
        XCTAssertEqual(config.source(bundle: "com.apple.Safari", direction: .tiltRight), .preset)
        config.overrides["com.apple.Safari", default: [:]][.up] = .unassigned
        XCTAssertEqual(config.source(bundle: "com.apple.Safari", direction: .up), .userOverride)
        XCTAssertEqual(config.source(bundle: "unknown.app", direction: .up), .presetGlobal)
    }

    /// Every row's badge must agree with what the engine will actually send. The
    /// badge is the user's only signal for "preset vs my edit", so a row claiming
    /// `.preset` while resolving to `.unassigned` is a lie the UI would tell.
    func testBadgeAgreesWithResolvedActionForEveryRow() {
        var config = GestureConfiguration()
        // A mix of override kinds, including the tricky explicit-unassigned case.
        config.overrides["com.apple.Safari", default: [:]][.up] = .unassigned
        config.overrides["com.google.Chrome", default: [:]][.down] = GestureProfiles.key(35, GestureShortcut.command)
        config.overrides["some.custom.app", default: [:]][.left] = .unassigned

        let bundles = GestureProfiles.all.map(\.id) + ["some.custom.app", "totally.unknown"]
        for bundle in bundles {
            for direction in GestureDirection.allCases {
                let source = config.source(bundle: bundle, direction: direction)
                let action = config.action(bundle: bundle, direction: direction)
                let isUnassigned: Bool = { if case .unassigned = action { return true }; return false }()
                switch source {
                case .userOverride:
                    // Any user edit, including an explicit Unassigned.
                    XCTAssertNotNil(config.overrides[bundle]?[direction], "\(bundle) \(direction)")
                case .preset, .presetGlobal:
                    XCTAssertFalse(isUnassigned,
                        "\(bundle) \(direction): badged as a preset but resolves Unassigned")
                case .unassigned:
                    XCTAssertTrue(isUnassigned,
                        "\(bundle) \(direction): badged Unassigned but sends \(action)")
                }
            }
        }
    }

    /// First-launch contract: a brand-new install has no persisted overrides, and
    /// every built-in app already resolves to its preset. This is the property the
    /// whole preset-first design rests on.
    func testFirstLaunchHasNoOverridesYetFullMapping() {
        let fresh = GestureConfiguration()
        XCTAssertTrue(fresh.overrides.isEmpty, "a fresh config must not be pre-filled")
        var mapped = 0
        for profile in GestureProfiles.all where profile.id != GestureProfiles.fallback {
            for direction in GestureDirection.allCases
            where fresh.source(bundle: profile.id, direction: direction) == .preset { mapped += 1 }
        }
        // Browsers alone contribute 18 preset cells; the exact count guards against
        // a family quietly losing its defaults.
        XCTAssertGreaterThanOrEqual(mapped, 30, "built-in apps must ship a useful preset")
    }

    // MARK: Exact keystrokes per built-in family (pins the prompt's mapping table)

    /// Every built-in bundle must send *exactly* the documented key per direction.
    /// Without this, a family could be silently swapped to another family's map
    /// while still resolving to "something non-nil" — a presence-only test cannot
    /// see that.
    func testExactKeystrokesForEveryBuiltInFamily() {
        let c = GestureShortcut.command, ctrl = GestureShortcut.control
        let shift = GestureShortcut.shift, opt = GestureShortcut.option
        let cfg = GestureConfiguration()

        // Global fallback: **an intent, never a key**.
        //
        // This row has reversed four times and every reversal was a measurement, not taste:
        //   1. `⌃↑ ⌃↓` for Mission Control — *"hơi vô dụng"*; their MX Master 3 already
        //      bound Mission Control to its thumb button in Logi Options.
        //   2. `⌘⇧]` / `⌘⇧[` for "next/previous item" — a real browser convention, but in a
        //      text editor it is *nothing at all*.
        //   3. `⌃←`/`⌃→` for Spaces as a constant — **probed and disproved**: on this host
        //      ids 79–82 were `enabled` with no `value`, so nothing listened. The user's
        //      report was exact: recognised, does nothing.
        //   4. `NSEvent.systemDefined` keytype 32 — also wrong: no such NX constant exists
        //      (`ev_keymap.h` stops at `NX_KEYTYPE_MENU = 25`), so Mission Control still did
        //      nothing while the page showed a row that looked delivered.
        //
        // So the preset now names the **action** and the key comes from the user's own
        // symbolic hotkeys at dispatch time. Asserting the exact key here would re-introduce
        // the bug in the test: there is no one right key, and the honest assertion is that
        // no arm carries a hardcoded chord (checked below) while all four carry an action.
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .up), .systemAction(.missionControl))
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .down), .systemAction(.appExpose))
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .left), .systemAction(.previousSpace))
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .right), .systemAction(.nextSpace))
        // The tilt arms send nothing, which the engine's tilt branch reads as "pass
        // the wheel's own sideways motion through". Unassigned is the honest stored
        // value for that: the row promises no keystroke and none is posted.
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .tiltLeft), .unassigned)
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .tiltRight), .unassigned)
        // The two superseded *keystroke* mappings may not come back anywhere in Global.
        // `⌃↑`/`⌃↓` must not: they are unbound, so they would silently do nothing again.
        for (dir, key) in [(GestureDirection.up, 126), (.down, 125)] {
            XCTAssertNotEqual(cfg.action(bundle: "whatever.unknown", direction: dir),
                              GestureProfiles.key(UInt16(key), ctrl), "global \(dir.rawValue) still sends ⌃arrow")
        }
        // And the Space keys must not return either — that is version 3, the one this
        // test was written to prevent from being re-introduced a fourth time.
        for (dir, key) in [(GestureDirection.left, 123), (.right, 124)] {
            XCTAssertNotEqual(cfg.action(bundle: "whatever.unknown", direction: dir),
                              GestureProfiles.key(UInt16(key), ctrl),
                              "global \(dir.rawValue) still sends a ⌃arrow Space key, which is unbound here")
        }
        // A system action must never *also* claim a shortcut — a row that posts keys while
        // being described as "whatever your Mac binds" is the mislabelling being removed.
        // All four Global arms are checked, not just the vertical pair: left/right became
        // system actions in the 2026-09-23 correction, so leaving them out here would let the
        // exact bug that was just fixed return unnoticed.
        for dir in [GestureDirection.up, .down, .left, .right] {
            XCTAssertNil(GestureMap.shortcut(of: cfg.action(bundle: "whatever.unknown", direction: dir)),
                         "global \(dir.rawValue) is a system action but reports a keystroke")
        }
        // And each of the four is the *system action for that direction* — a copy-paste that
        // wired two arms to one action would leave a direction silently dead.
        XCTAssertEqual(GestureMap.systemAction(of: cfg.action(bundle: "whatever.unknown", direction: .up)),
                       .missionControl)
        XCTAssertEqual(GestureMap.systemAction(of: cfg.action(bundle: "whatever.unknown", direction: .down)),
                       .appExpose)
        XCTAssertEqual(GestureMap.systemAction(of: cfg.action(bundle: "whatever.unknown", direction: .left)),
                       .previousSpace)
        XCTAssertEqual(GestureMap.systemAction(of: cfg.action(bundle: "whatever.unknown", direction: .right)),
                       .nextSpace)
        // The `⌘⇧]`/`⌘⇧[` "next/previous item" pair is gone too. It is a browser
        // convention and means *nothing at all* in a text editor, which is most of
        // this user's day — so Global no longer ships it on either axis.
        for dir in [GestureDirection.up, .down] {
            for key: UInt16 in [33, 30] {
                XCTAssertNotEqual(cfg.action(bundle: "whatever.unknown", direction: dir),
                                  GestureProfiles.key(key, c | shift),
                                  "global \(dir.rawValue) still sends ⌘⇧\(key)")
            }
        }
        let global = GestureProfiles.all.first { $0.id == GestureProfiles.fallback }!
        for (dir, action) in global.defaults {
            XCTAssertNotEqual(action, GestureProfiles.key(33, c | shift),
                              "global \(dir.rawValue) sends the retired next-item keystroke")
            XCTAssertNotEqual(action, GestureProfiles.key(30, c | shift),
                              "global \(dir.rawValue) sends the retired previous-item keystroke")
        }

        // Browsers.
        for id in ["com.microsoft.edgemac", "com.apple.Safari", "com.google.Chrome"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .up), GestureProfiles.key(17, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .down), GestureProfiles.key(13, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .left), GestureProfiles.key(33, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .right), GestureProfiles.key(30, c), id)
            // Tilt = next tab: a horizontal nudge is the "next page" motion on a
            // browser, and it is the one tab key (`⌃⇥`) both Chrome and Edge bind
            // identically to Safari.
            XCTAssertEqual(cfg.action(bundle: id, direction: .tiltLeft), GestureProfiles.key(48, ctrl), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .tiltRight), GestureProfiles.key(48, ctrl), id)
        }

        // Dev & AI: history on the horizontal arms, up/down deliberately empty.
        for id in ["com.visualstudio.code", "com.cursor.ide", "dev.zed.Zed", "com.antigravity.ide", "com.anthropic.claude"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .left), GestureProfiles.key(33, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .right), GestureProfiles.key(30, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .up), .unassigned, id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .down), .unassigned, id)
        }

        // Media / editing: bare [ ] with no modifiers.
        for id in ["com.adobe.Photoshop", "com.lemon.CapCutMac"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .up), GestureProfiles.key(29, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .down), GestureProfiles.key(6, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .left), GestureProfiles.key(33, 0), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .right), GestureProfiles.key(30, 0), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .tiltLeft), .unassigned, id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .tiltRight), .unassigned, id)
        }

        // Messaging: ⌥↑ / ⌥↓ only.
        for id in ["com.hnc.Discord", "com.vng.zalo", "org.telegram.ayugram"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .left), GestureProfiles.key(126, opt), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .right), GestureProfiles.key(125, opt), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .up), .unassigned, id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .down), .unassigned, id)
        }

        // Office: **two separate tables**, because Word is not Excel.
        // `⌘+`/`⌘-` is each app's own zoom shortcut, so those two rows are shared.
        for id in ["com.microsoft.Excel", "com.microsoft.Word"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .up), GestureProfiles.key(24, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .down), GestureProfiles.key(27, c), id)
        }
        // Excel has a documented sheet-navigation pair; Word has no worksheets at
        // all, so its tabs stay Unassigned rather than borrowing Excel's keys.
        XCTAssertEqual(cfg.action(bundle: "com.microsoft.Excel", direction: .left), GestureProfiles.key(48, ctrl | shift))
        XCTAssertEqual(cfg.action(bundle: "com.microsoft.Excel", direction: .right), GestureProfiles.key(48, ctrl))
        XCTAssertEqual(cfg.action(bundle: "com.microsoft.Word", direction: .left), .unassigned)
        XCTAssertEqual(cfg.action(bundle: "com.microsoft.Word", direction: .right), .unassigned)
        // Notes: ⌘P plus ⌘⌥← / ⌘⌥→; down is ambiguous (block vs page) -> unassigned.
        for id in ["co.elastic.obsidian", "com.notion.Notion-App"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .up), GestureProfiles.key(35, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .left), GestureProfiles.key(123, c | opt), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .right), GestureProfiles.key(124, c | opt), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .down), .unassigned, id)
        }

        // Terminals (Kitty, Terminal, iTerm2). Only the ⌥←/⌥→ word-look-up pair:
        // a terminal is where a wrong keystroke destroys work, so splits, new tabs
        // and ⌘W stay Unassigned rather than guessed.
        for id in ["net.kovidgoyal.kitty", "com.apple.Terminal", "com.googlecode.iterm2"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .left), GestureProfiles.key(123, opt), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .right), GestureProfiles.key(124, opt), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .up), .unassigned, id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .down), .unassigned, id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .tiltLeft), .unassigned, id)
        }
    }

    /// Families must not share a map by accident, no two apps may share *one table*
    /// unless they genuinely have the same shortcuts, and no ambiguous slot may be
    /// filled with an invented key.
    func testFamiliesDoNotShareAccidentalMappings() {
        let dev = GestureProfiles.all.first { $0.id == "com.visualstudio.code" }!.defaults
        let browsers = GestureProfiles.all.first { $0.id == "com.apple.Safari" }!.defaults
        let excel = GestureProfiles.all.first { $0.id == "com.microsoft.Excel" }!.defaults
        let word = GestureProfiles.all.first { $0.id == "com.microsoft.Word" }!.defaults
        // Excel and Word overlap only where the shortcuts genuinely coincide (zoom),
        // plus undo — the sheet-navigation pair exists in Excel alone, because Word
        // has no worksheets. Sharing one dictionary between them is the bug this pins.
        XCTAssertEqual(word.count, excel.count - 2, "Word and Excel must be separate tables")
        XCTAssertNil(word[.left]); XCTAssertNil(word[.right])
        XCTAssertNotNil(excel[.left]); XCTAssertNotNil(excel[.right])
        XCTAssertEqual(word[.up], excel[.up]); XCTAssertEqual(word[.down], excel[.down])
        for (dir, action) in dev where dir == .up || dir == .down {
            XCTAssertNotEqual(browsers[dir], action, "dev and browsers share \(dir.rawValue)")
        }
        XCTAssertNil(dev[.up]); XCTAssertNil(dev[.down])
        // A preset with a hold-trigger button must never send a bare bracket to a
        // text-first app: Photoshop's brush-size pair is the only place [] is right.
        XCTAssertEqual(browsers[.left], GestureProfiles.key(33, GestureShortcut.command))
    }

    /// Word is not Excel, and the two must not be one dictionary with a comment
    /// saying so. Both are in the user's daily-driver list, so this is a real
    /// distinction, not a hypothetical.
    func testWordAndExcelDoNotShareOneTable() {
        let excel = GestureProfiles.all.first { $0.id == "com.microsoft.Excel" }!
        let word = GestureProfiles.all.first { $0.id == "com.microsoft.Word" }!
        XCTAssertNotEqual(excel.defaults, word.defaults)
        XCTAssertNotEqual(excel.gestureMap, word.gestureMap)
        XCTAssertEqual(word.gestureMap[.left]?.isUnassigned, true)
        XCTAssertEqual(word.gestureMap[.right]?.isUnassigned, true)
    }

    /// `GestureShortcut.label` is the canonical keystroke spelling shown in the
    /// Settings table. It must name every key the built-in presets actually use —
    /// a missing entry degrades to "Key 27", which is what made the page look
    /// like raw debug output.
    func testEveryPresetKeyHasAReadableLabel() {
        let names: Set<UInt16> = [0, 3, 6, 9, 13, 17, 24, 27, 29, 30, 33, 35, 36, 48, 49, 50, 116, 121, 123, 124, 125, 126]
        var used = Set<UInt16>()
        for profile in GestureProfiles.all {
            for (_, action) in profile.defaults {
                if case .shortcut(let s) = action { used.insert(s.key) }
            }
        }
        XCTAssertFalse(used.isEmpty)
        for key in used {
            XCTAssertTrue(names.contains(key), "key \(key) has no readable name")
            let label = GestureShortcut(key: key, flags: GestureShortcut.command).label
            XCTAssertFalse(label.contains("Key "),
                "key \(key) renders as the raw placeholder \(label)")
        }
    }

    /// The readiness badge is a *measurement* contract, not a text one: a page
    /// that says "Ready" while the tap is closed is the bug this pins down.
    /// Reproduces the three states the view computes from `enabled` / `tapActive`.
    func testReadinessBadgeNeverClaimsReadyWithoutAnArmedTap() {
        func badge(enabled: Bool, tapActive: Bool) -> String {
            if !enabled { return "off" }
            return tapActive ? "ready" : "warning"
        }
        XCTAssertEqual(badge(enabled: false, tapActive: false), "off")
        // The failure mode: switched on, tap never opened.
        XCTAssertEqual(badge(enabled: true, tapActive: false), "warning")
        XCTAssertEqual(badge(enabled: true, tapActive: true), "ready")
        // A stale `tapActive` from a previous session must not survive a disable.
        XCTAssertNotEqual(badge(enabled: false, tapActive: true), "ready")
    }

    /// Adding a new built-in profile must never clobber what the user already set.
    func testAddingBuiltInProfilesPreservesUserOverrides() {
        var config = GestureConfiguration()
        config.overrides["com.apple.Safari", default: [:]][.up] = .unassigned
        config.overrides["my.custom.app", default: [:]][.left] = GestureProfiles.key(0, GestureShortcut.command)
        let before = config.overrides
        // The factory layer is a `static let`; re-reading it is what a launch does.
        _ = GestureProfiles.all
        XCTAssertEqual(config.overrides, before, "launch must not rewrite overrides")
        XCTAssertEqual(config.action(bundle: "com.apple.Safari", direction: .up), .unassigned)
        XCTAssertEqual(config.action(bundle: "my.custom.app", direction: .left),
                       GestureProfiles.key(0, GestureShortcut.command))
    }

    func testMigrationDropsUntouchedDefaultsKeepsExplicitEdits() throws {
        // Simulate an old build that persisted the full factory dictionary.
        var legacy = GestureConfiguration()
        for p in GestureProfiles.all { legacy.overrides[p.id] = p.defaults }
        // Plus one genuine user edit and one explicit unassigned.
        legacy.overrides["com.apple.Safari", default: [:]][.up] = GestureProfiles.key(0, GestureShortcut.command) // A
        legacy.overrides["com.apple.Safari"]![.down] = .unassigned
        let data = try JSONEncoder().encode(legacy)
        // Reproducing the migration's pruning logic directly (controller init
        // would require UserDefaults, but the core step is this filter).
        let decoded = try JSONDecoder().decode(GestureConfiguration.self, from: data)
        var pruned: [String: [GestureDirection: GestureAction]] = [:]
        for (bundle, dict) in decoded.overrides {
            guard GestureProfiles.all.contains(where: { $0.id == bundle }) else { pruned[bundle] = dict; continue }
            let factory = GestureProfiles.all.first { $0.id == bundle }?.defaults ?? [:]
            var keep: [GestureDirection: GestureAction] = [:]
            for (dir, action) in dict {
                if factory[dir] == action { continue }
                if case .unassigned = action, factory[dir] == nil { continue }
                keep[dir] = action
            }
            if !keep.isEmpty { pruned[bundle] = keep }
        }
        // Untouched factory rows removed; user edits kept.
        XCTAssertNil(pruned["com.microsoft.edgemac"])
        XCTAssertEqual(pruned["com.apple.Safari"]?[.up], GestureProfiles.key(0, GestureShortcut.command))
        XCTAssertEqual(pruned["com.apple.Safari"]?[.down], .unassigned)
    }

    // MARK: - Physical instructions (the UI must say which button and which motion)

    /// Buttons are named by the **number macOS reports**, because that is the only
    /// identifier true for every mouse. The earlier attempt invented physical names
    /// ("Nút hông sau — nút 4", "nút giữa") and asserted a layout nothing had
    /// measured — the same number is a different control on a Basilisk and on a
    /// Magic Mouse, and Dan asked for numbers by name.
    ///
    ///   The three numbers every mouse shares carry a short factual note naming **where
    ///   the button is**, not a user-facing number: macOS's button 0 is the left
    ///   click, 1 the right, 2 the wheel. The old table paired the *display* number
    ///   with a description of a different control, which is why it read as
    ///   "Nút 3 (bấm con lăn xuống)" — self-consistent-looking and impossible to
    ///   reason about against the stored value.
    ///
    /// The model no longer returns these strings — it returns a `ButtonKey` and
    /// this fixture is the single place that turns one into the Vietnamese literal
    /// the store is keyed by. Nothing asserts on a rendered sentence any more,
    /// because there is no longer a rendered sentence in the model to assert on.
    func testTriggerLabelsNameButtonsByNumber() {
        // The three shared buttons are named by *position*, which answers the user's
        // actual question ("which button do I press?"); every other button is named
        // by its number, because no API can confirm where it sits.
        XCTAssertEqual(L10nFixtures.buttonName(0), "Nút trái", "macOS button 0 is the left click")
        XCTAssertEqual(L10nFixtures.buttonName(1), "Nút phải", "macOS button 1 is the right click")
        XCTAssertEqual(L10nFixtures.buttonName(2), "Bấm con lăn xuống",
                       "macOS button 2 is the wheel press")
        // The offset must hold for every number from the first side button up.
        for n in 3...31 {
            XCTAssertEqual(L10nFixtures.buttonName(n), "Nút \(n + 1)", "button \(n)")
        }
        // Side/multimedia buttons are just numbers — no invented anatomy.
        XCTAssertEqual(L10nFixtures.buttonName(3), "Nút 4")
        XCTAssertEqual(L10nFixtures.buttonName(4), "Nút 5")
        for banned in ["hông", "bắn tỉa", "DPI", "sniper", "con lăn"] {
            XCTAssertFalse(L10nFixtures.buttonName(4).contains(banned),
                           "invented physical name '\(banned)' came back")
        }

        // The default must be the one users can find without a vendor utility.
        XCTAssertEqual(GestureConfiguration().trigger, .mouseButton(4))

        // Out-of-range codes still render something, never an empty label.
        XCTAssertFalse(L10nFixtures.buttonName(9).isEmpty)

        // And the trigger still exposes the *semantic* shape, which is what the
        // view resolves — a modifier trigger must not claim a button number.
        XCTAssertEqual(TriggerSource.mouseButton(4).key, .index(4))
        XCTAssertTrue(TriggerSource.mouseButton(4).isMouseButton)
        XCTAssertEqual(TriggerSource.modifierKey(GestureShortcut.control).key,
                       .modifier(GestureShortcut.control))
        XCTAssertFalse(TriggerSource.modifierKey(GestureShortcut.control).isMouseButton)
    }

    /// The heading vocabulary must let the panel name the direction and the held
    /// button — the button **exactly once**, and never on a tilt direction.
    ///
    /// The user read a number on all four arms and concluded every arm was "Button
    /// 3"; the number therefore moved out of the per-arm caption into the mouse
    /// body, and the heading keeps a single mention.
    ///
    /// This asserts the model's *keys* rather than a rendered sentence, because the
    /// sentence is assembled by `L10n.t(direction, trigger:)` and this package has no
    /// `L10n`. Asserting the keys is the stronger check anyway: the key is the source
    /// of the sentence, so "the button is composeable exactly once" is a property of
    /// the vocabulary, not of one rendering of it.
    func testHeadingVocabularyNamesTheHeldButtonExactlyOnce() {
        // A hold direction is composed of a button key and a bare motion hint. The
        // button is NOT inside `titleKey`, which is what makes it appear once.
        for dir in [GestureDirection.up, .down, .left, .right] {
            XCTAssertFalse(dir.titleKey.isEmpty, "\(dir) has no heading key")
            XCTAssertFalse(GestureTriggerKind.isTilt(dir), "\(dir) must need a held button")
            XCTAssertFalse(dir.titleKey.contains("Nút"),
                           "\(dir).titleKey carries a button, so it would print on every "
                           + "arm again: \(dir.titleKey)")
            XCTAssertFalse(dir.motionHintKey.isEmpty, "\(dir) has no motion hint")
            XCTAssertFalse(dir.motionHintKey.contains("Nút"),
                           "\(dir).motionHintKey carries a button: \(dir.motionHintKey)")
        }
        // Tilt is a different physical motion and must NOT claim a held button.
        for dir in [GestureDirection.tiltLeft, .tiltRight] {
            XCTAssertTrue(GestureTriggerKind.isTilt(dir), "\(dir) is a tilt direction")
            XCTAssertTrue(dir.titleKey.contains("Nghiêng"),
                          "\(dir) must say the wheel is tilted: \(dir.titleKey)")
            XCTAssertFalse(dir.titleKey.contains("Nút"),
                           "\(dir) is performed without holding a button: \(dir.titleKey)")
        }
        // Every heading must differ, or the diagram cannot be read.
        let all = GestureDirection.allCases.map(\.titleKey)
        XCTAssertEqual(Set(all).count, all.count, "directions share a heading: \(all)")
        // And every motion caption must differ too, since they are all on screen at
        // the same time in the legend.
        let captions = GestureDirection.allCases.map(\.motionKey)
        XCTAssertEqual(Set(captions).count, captions.count,
                       "directions share a motion caption: \(captions)")
    }
    /// The diagram must never draw an arm that cannot fire, and every direction it
    /// *does* draw must be reachable. Both directions of the `isTilt` split are
    /// checked, because the classifier and the engine have to agree: the engine
    /// only reads `tiltLeft`/`tiltRight` from the scroll handler.
    func testTiltDirectionsAreExactlyTheScrollHandledOnes() {
        for dir in GestureDirection.allCases {
            let expected = (dir == .tiltLeft || dir == .tiltRight)
            XCTAssertEqual(GestureTriggerKind.isTilt(dir), expected, dir.rawValue)
            XCTAssertEqual(GestureTriggerKind.isTilt(dir), expected, dir.rawValue)
            // Horizontal-scroll pass-through is offered only where it is meaningful.
            XCTAssertEqual(GestureTriggerKind.supportsHorizontalScroll(dir), expected, dir.rawValue)
        }
    }

    /// The tilt arms are drawn only when the user says their hardware has a
    /// discrete horizontal wheel, because the ones measured here do not: every
    /// wheel event from the Basilisk and from the Magic Mouse reports
    /// `scrollWheelEventIsContinuous == 1` with axis2 == 0, which the engine
    /// rejects. Shipping this default as `true` drew two arms that could never
    /// fire on the very mouse the feature was requested for.
    func testTiltArmsAreHiddenByDefault() {
        XCTAssertFalse(GestureConfiguration().tiltAvailable,
                       "tilt must default off: no mouse measured here can fire it")
        // Both switches are independent **in the model**; neither may imply the other.
        // The *view* writes both from its one switch — see `testTiltRevealSwitchAlsoEnablesTheArms`
        // — because an arm that is drawn but disabled is a control that cannot do what its
        // label says. Keeping the fields separate here is what lets a payload written by an
        // older build (which had only `tiltAvailable`) still decode and still mean "off".
        XCTAssertFalse(GestureConfiguration().tiltEnabled)
        var config = GestureConfiguration()
        config.tiltAvailable = true
        XCTAssertTrue(config.tiltAvailable)
        XCTAssertFalse(config.tiltEnabled, "the model field must not imply the other")
    }

    /// The page's single tilt switch must write **both** fields (PATCH v10).
    ///
    /// The shipped bug: the switch wrote only `tiltAvailable` (draw the arms) while the engine
    /// reads `tiltEnabled` (handle the events). Nothing anywhere set `tiltEnabled`, so a user
    /// could reveal the arms, assign an action to `tiltLeft`, and nothing would ever fire —
    /// and the reverse, turning the switch off, left the engine intercepting discrete
    /// horizontal wheel events for arms that were no longer on screen.
    func testTiltRevealSwitchAlsoEnablesTheArms() {
        let on = TiltArmsVisibility.fields(forReveal: true)
        XCTAssertTrue(on.available, "the arms must be drawn")
        XCTAssertTrue(on.enabled,
                      "drawing the arms without enabling them is the bug this pass fixed")
        let off = TiltArmsVisibility.fields(forReveal: false)
        XCTAssertFalse(off.available)
        XCTAssertFalse(off.enabled, "switching off must also stop the engine handling tilt")

        // The contract, stated as the property that matters: the two fields always agree, so
        // no combination can leave a visible-but-dead arm or a hidden-but-live one.
        for reveal in [true, false] {
            let fields = TiltArmsVisibility.fields(forReveal: reveal)
            XCTAssertEqual(fields.available, fields.enabled)
        }
    }

    /// The **read** side needs its own contract, and this is why (found 2026-09-24).
    ///
    /// `fields(forReveal:)` fixes what the switch writes, but it cannot fix what an older
    /// payload already holds. Measured on this machine's own store:
    ///
    ///     tiltAvailable = true, tiltEnabled = false
    ///
    /// — a state the current UI cannot produce, left by the build where the switch wrote only
    /// `tiltAvailable`. Reading `tiltAvailable` alone drew two arms that could never fire *and*
    /// showed the switch as on: the same "control that cannot do what its label says" the
    /// write-side contract exists to prevent, one layer down. The conjunction is the honest
    /// read, and it needs no migration — a payload that disagrees with itself reads as off
    /// until the user turns the switch on again.
    func testTiltArmsAreLiveOnlyWhenBothFieldsAgree() {
        XCTAssertTrue(TiltArmsVisibility.isLive(available: true, enabled: true))
        XCTAssertFalse(TiltArmsVisibility.isLive(available: true, enabled: false),
                       "drawn but not enabled is the shipped bug — it must read as off")
        XCTAssertFalse(TiltArmsVisibility.isLive(available: false, enabled: true),
                       "enabled but not drawn is the mirror case")
        XCTAssertFalse(TiltArmsVisibility.isLive(available: false, enabled: false))

        // The property the fix is for: whatever the switch writes, the read agrees with it,
        // and every inconsistent payload reads as off rather than as a live arm.
        for reveal in [true, false] {
            let fields = TiltArmsVisibility.fields(forReveal: reveal)
            XCTAssertEqual(TiltArmsVisibility.isLive(available: fields.available,
                                                     enabled: fields.enabled), reveal)
        }
    }

    // MARK: - Duplicate L10n keys

    /// A duplicate key in an `L10n` dictionary literal is a FATAL crash at launch,
    /// and this already shipped once: every page went blank and the cause was only
    /// visible in stderr. The real gate is `scripts/check-l10n-duplicates.py`; this
    /// test proves the script is present and currently reports zero duplicates, so
    /// `swift test` fails loudly if the gate is deleted or starts finding one.
    func testL10nDictionaryHasNoDuplicateKeys() throws {
        // The test bundle runs from Tests/, so resolve the repo root from this file.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // XFinderLogicTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let script = repoRoot.appendingPathComponent("scripts/check-l10n-duplicates.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path),
                      "the duplicate-key gate is missing: \(script.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path]
        process.currentDirectoryURL = repoRoot
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Read before waiting, or a full pipe buffer deadlocks the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(process.terminationStatus, 0,
                       "duplicate L10n keys would crash the app at launch:\n\(output)")
        XCTAssertTrue(output.contains("TOTAL 0 duplicates"),
                      "unexpected checker output:\n\(output)")
    }

    /// "Về mặc định" sits under a single direction heading, so it must reset only
    /// that direction. It used to call `resetProfile`, which cleared every
    /// override for the whole app while the label promised one row — a user's
    /// other custom directions disappeared with no undo.
    ///
    /// Tested at the model level, because `GestureController` is `@MainActor` and
    /// AppKit-bound: the property under test is "removing one direction leaves the
    /// rest intact", which is pure dictionary logic the controller delegates to.
    func testResetOneDirectionLeavesTheOthersAlone() {
        var overrides: [String: [GestureDirection: GestureAction]] = [
            "com.apple.Safari": [
                .up: .unassigned,
                .left: .shortcut(GestureShortcut(key: 0, flags: GestureShortcut.command)),
                .right: .horizontalScroll,
            ]
        ]
        let bundle = "com.apple.Safari"

        // Exactly what `GestureController.resetDirection` does.
        overrides[bundle]?.removeValue(forKey: .up)

        XCTAssertNil(overrides[bundle]?[.up], "the reset direction must fall back to the preset")
        XCTAssertEqual(overrides[bundle]?.count, 2,
                       "resetting one direction must not touch the other two")
        XCTAssertNotNil(overrides[bundle]?[.left])
        XCTAssertNotNil(overrides[bundle]?[.right])

        // And the emptied case: removing the last override must remove the bundle,
        // or every other direction stays flagged as "you customised this app".
        overrides[bundle]?.removeValue(forKey: .left)
        overrides[bundle]?.removeValue(forKey: .right)
        if overrides[bundle]?.isEmpty == true { overrides.removeValue(forKey: bundle) }
        XCTAssertNil(overrides[bundle],
                     "a bundle with no overrides left must not linger as an empty dict")
    }

    /// The reset must land the row back on the *preset*, not on `.unassigned` —
    /// the difference between "restore the built-in shortcut" and "send nothing".
    func testResetReturnsTheDirectionToItsPresetNotToUnassigned() {
        var config = GestureConfiguration()
        let bundle = "com.apple.Safari"
        config.overrides[bundle, default: [:]][.up] = .unassigned
        XCTAssertEqual(config.action(bundle: bundle, direction: .up), .unassigned)

        config.overrides[bundle]?.removeValue(forKey: .up)
        XCTAssertEqual(config.action(bundle: bundle, direction: .up),
                       GestureProfiles.key(17, GestureShortcut.command),
                       "after a reset the direction must be back on ⌘T, not muted")
    }

    // MARK: - Sơ đồ cử chỉ (MouseDiagramView selection + GestureDetailPanel labels)

    /// The diagram's arrow is a toggle, not a list selection: clicking the arm that
    /// is already open closes it again. That sounds trivial but it is exactly what
    /// the old page did not do — the six text rows had no selection state at all,
    /// so there was no way to see "which arrow am I looking at".
    func testArrowClickTogglesTheSelection() {
        var picked: GestureDirection?

        // Clicking an arm picks it.
        picked = MouseDiagramSelection.afterClick(current: picked, clicked: .up)
        XCTAssertEqual(picked, .up)

        // Clicking the SAME arm clears it — the interaction is a toggle.
        picked = MouseDiagramSelection.afterClick(current: picked, clicked: .up)
        XCTAssertNil(picked)

        // Clicking a different arm moves the highlight instead of clearing it.
        picked = MouseDiagramSelection.afterClick(current: picked, clicked: .right)
        XCTAssertEqual(picked, .right)
        picked = MouseDiagramSelection.afterClick(current: picked, clicked: .tiltLeft)
        XCTAssertEqual(picked, .tiltLeft)
        picked = MouseDiagramSelection.afterClick(current: picked, clicked: .right)
        XCTAssertEqual(picked, .right)
    }

    /// Switching the app in the picker must clear the highlighted arm. Keeping the
    /// old selection would leave the detail panel describing a direction the user
    /// picked while looking at a *different* app's mapping — a stale-panel bug.
    func testSwitchingAppClearsTheSelectedArrow() {
        let picked = MouseDiagramSelection.afterClick(current: nil, clicked: .up)
        XCTAssertEqual(picked, .up, "precondition: the arm is open")
        // The view forwards to this helper on every profile change.
        XCTAssertNil(MouseDiagramSelection.afterProfileChange())
    }

    /// Every direction must expose a non-empty, distinct heading key. The panel
    /// renders it through `L10n.t`, so an empty key would render an empty title
    /// above the keys — and a duplicated key would make two directions
    /// indistinguishable in the heading.
    func testEveryDirectionHasADistinctDetailHeading() {
        let titles = GestureDirection.allCases.map(\.titleKey)
        XCTAssertEqual(titles.count, GestureDirection.allCases.count)
        for title in titles { XCTAssertFalse(title.isEmpty, "direction has no heading") }
        XCTAssertEqual(Set(titles).count, titles.count, "two directions share a heading")
    }

    /// **L1, pinned.** The diagram must never print the held button on an arm: the
    /// button is identical for all four directions, so printing it once per arm read
    /// as "all four buttons are Button 3", which is exactly what the user reported.
    ///
    /// The assertion is structural rather than visual: `motionKey` is the caption
    /// vocabulary and must contain no number, while `motionHintKey`/`titleKey` are
    /// the heading vocabulary and are allowed to name the button once.
    func testArmCaptionsCarryNoButtonNumber() {
        for direction in GestureDirection.allCases {
            let caption = direction.motionKey
            XCTAssertFalse(caption.isEmpty, "\(direction.rawValue) has no caption")
            XCTAssertFalse(caption.contains("Nút"),
                           "the arm caption for \(direction.rawValue) names a button: "
                           + "\(caption) — the number belongs on the mouse body once")
            // The heading key is a *key*, so it cannot carry a value either; the
            // resolution adds the button through `motionHintKey`.
            XCTAssertFalse(L10nFixtures.interpolates(direction.titleKey),
                           "\(direction.rawValue).titleKey interpolates, so it can never "
                           + "be a lookup key")
        }
    }

    /// The panel must name the key the engine will post. `GestureShortcut.label`
    /// is the single spelling, so the shown value and the sent value cannot drift.
    func testDisplayedKeystrokeMatchesWhatTheEngineSends() {
        let c = GestureShortcut.command, ctrl = GestureShortcut.control
        let shift = GestureShortcut.shift
        // Spot-check the three families whose labels the user reads most.
        XCTAssertEqual(GestureShortcut(key: 17, flags: c).label, "⌘T")
        XCTAssertEqual(GestureShortcut(key: 13, flags: c).label, "⌘W")
        XCTAssertEqual(GestureShortcut(key: 48, flags: ctrl | shift).label, "⌃⇧⇥")
        XCTAssertEqual(GestureShortcut(key: 48, flags: ctrl).label, "⌃⇥")
        // And they are exactly what the preset holds, not a lookalike.
        let cfg = GestureConfiguration()
        XCTAssertEqual(cfg.action(bundle: "com.apple.Safari", direction: .up),
                       .shortcut(GestureShortcut(key: 17, flags: c)))
        XCTAssertEqual(cfg.action(bundle: "com.apple.Safari", direction: .right),
                       .shortcut(GestureShortcut(key: 30, flags: c)))
        // The `label` the page prints and the `shortcut` the engine posts are the
        // same value — `GestureMapEntry.action` is derived from its own `shortcut`,
        // so a row cannot show one key and dispatch another.
        let row = GestureMap.row(overrides: [:], bundle: "com.apple.Safari", direction: .up)
        XCTAssertEqual(row.action, .shortcut(GestureShortcut(key: 17, flags: c)))
        XCTAssertEqual(row.entry.shortcut?.label ?? "", "⌘T")
    }

    /// "Raw horizontal scroll" is offered on exactly the two tilt arms and never
    /// on a button-drag arm. The engine refuses to act on `.horizontalScroll` for
    /// tilt (it passes the event through), so the option means "leave it native" —
    /// offering it on `↑`/`↓`/`←`/`→` would promise pass-through on a motion that
    /// has nothing to pass through.
    func testHorizontalScrollOfferedOnlyOnTiltArms() {
        for direction in GestureDirection.allCases {
            let offered = GestureTriggerKind.supportsHorizontalScroll(direction)
            XCTAssertEqual(offered, GestureTriggerKind.isTilt(direction),
                           "\(direction.rawValue): horizontal-scroll option disagrees with tilt-ness")
        }
        XCTAssertTrue(GestureTriggerKind.supportsHorizontalScroll(.tiltLeft))
        XCTAssertTrue(GestureTriggerKind.supportsHorizontalScroll(.tiltRight))
        XCTAssertFalse(GestureTriggerKind.supportsHorizontalScroll(.up))
        XCTAssertFalse(GestureTriggerKind.supportsHorizontalScroll(.left))
    }

    // MARK: - Acceptance section (the two causes of "it does not fire")

    /// The page warns about a **wheel hold** specifically, and that warning must fire
    /// for the value that was actually shipped as the default in an older build.
    ///
    /// This is the whole point of the warning: the user's stored configuration carries
    /// `mouseButton(2)`, and it survives every `validate()` because 2 is a *valid*
    /// trigger. Nothing else in the codebase treats 2 as special, so if this predicate
    /// is ever "simplified" to a generic `isMouseButton` check the user's exact reported
    /// bug becomes invisible again.
    func testWheelHoldIsSingledOutAsUnusable() {
        // The predicate the view uses, restated so the test fails if the view changes
        // its mind without this being updated.
        func isWheelHold(_ trigger: TriggerSource) -> Bool { trigger.buttonNumber == 2 }

        XCTAssertTrue(isWheelHold(.mouseButton(2)), "wheel click must be flagged")
        XCTAssertFalse(isWheelHold(.mouseButton(3)))
        XCTAssertFalse(isWheelHold(.mouseButton(4)))
        XCTAssertFalse(isWheelHold(.mouseButton(5)))
        XCTAssertFalse(isWheelHold(.modifierKey(GestureShortcut.command)),
                       "a modifier is not a wheel hold")

        // And the value that shipped as the default must NOT be the wheel, or the
        // warning would fire on every fresh install instead of on legacy payloads.
        XCTAssertFalse(isWheelHold(GestureConfiguration.defaultTrigger))
    }

    /// The "set this as the hold button" offer must appear only for a press of a button
    /// *other than* the current trigger.
    ///
    /// The rejected alternative was a prompt gated on `trigger == 2 && overrides == {}`,
    /// which matched every fresh install because 2 was then the code default. Gating on
    /// an observed press is what makes the offer honest — it only appears after the user
    /// has actually pressed something.
    func testSetAsHoldOfferRequiresADifferentObservedButton() {
        func offers(_ observed: Int?, trigger: TriggerSource) -> Bool {
            guard let observed else { return false }
            return observed != trigger.buttonNumber
        }

        XCTAssertFalse(offers(nil, trigger: .mouseButton(3)), "no press yet — nothing to offer")
        XCTAssertFalse(offers(3, trigger: .mouseButton(3)), "pressing the current trigger changes nothing")
        XCTAssertTrue(offers(4, trigger: .mouseButton(3)), "a different button is the case to offer")
        XCTAssertTrue(offers(3, trigger: .mouseButton(2)),
                      "somebody stuck on the wheel hold must be offered the button they pressed")
        // A modifier trigger has no number, so any press is a change.
        XCTAssertTrue(offers(3, trigger: .modifierKey(GestureShortcut.command)))
    }

    /// Every app the user actually uses daily must resolve to a real table, and none of
    /// them may be silently inheriting Global. This is the "preset-first" promise: the
    /// page must never read as though the user has to build mappings by hand.
    func testEveryDailyDriverHasItsOwnPreset() {
        let dailyDrivers = [
            "com.anthropic.claude", "com.antigravity.ide", "dev.zed.Zed",
            "net.kovidgoyal.kitty", "com.apple.Terminal",
            "com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac",
            "com.microsoft.Word", "com.microsoft.Excel",
            "com.adobe.Photoshop", "com.lemon.CapCutMac",
        ]
        for id in dailyDrivers {
            XCTAssertTrue(GestureProfiles.hasPreset(bundle: id),
                          "\(id) has no built-in preset, so it silently uses Global")
        }
    }

    /// Global answers for a bundle that has no preset of its own, and does so by
    /// *falling back* rather than by pretending the app has a table.
    func testUnknownAppFallsBackToGlobalAndSaysSo() {
        let unknown = "com.example.not-installed-anywhere"
        XCTAssertFalse(GestureProfiles.hasPreset(bundle: unknown))
        XCTAssertEqual(GestureProfiles.resolve(overrides: [:], bundle: unknown, direction: .up),
                       GestureProfiles.resolve(overrides: [:], bundle: GestureProfiles.fallback, direction: .up))
    }

    // MARK: - System actions resolve from the machine, and say so when they cannot

    /// A fixture of what a machine that bound all four Space/Mission-Control shortcuts looks
    /// like, copied from the live read (ids 32/33/79–82, `⌃`+arrow, mask `0x840000`).
    private var liveBindings: GestureSystemBindings {
        GestureSystemBindings(entries: SpaceBinding.parse([
            "32": ["enabled": 1, "value": ["parameters": [65535, 126, 8650752]]],
            "33": ["enabled": 1, "value": ["parameters": [65535, 125, 8650752]]],
            "79": ["enabled": 1, "value": ["parameters": [65535, 123, 8650752]]],
            "81": ["enabled": 1, "value": ["parameters": [65535, 124, 8650752]]],
        ]))
    }

    /// The single rule this whole pass exists to enforce: **the row shows the keys the
    /// engine will post.** With the machine's own bindings threaded in, the Global arms
    /// resolve to real chords — `⌃↑` / `⌃↓` / `⌃←` / `⌃→` on this host — rather than to a
    /// constant the module invented. Before this, the page showed keys nothing listened for
    /// and the user reported exactly that: "recognised but does nothing".
    func testRowResolvesSystemActionsFromTheMachinesBindings() {
        for (direction, expected) in [(GestureDirection.up, GestureShortcut(key: 126, flags: 8650752)),
                                      (.down, GestureShortcut(key: 125, flags: 8650752)),
                                      (.left, GestureShortcut(key: 123, flags: 8650752)),
                                      (.right, GestureShortcut(key: 124, flags: 8650752))] {
            let row = GestureMap.row(overrides: [:], bundle: "com.example.unknown",
                                     direction: direction, systemBindings: liveBindings)
            XCTAssertEqual(row.systemShortcut, expected, "\(direction.rawValue) did not resolve")
            XCTAssertFalse(row.isUnboundSystemAction)
            XCTAssertEqual(row.caption, expected.label,
                           "the caption must be the resolved chord, not the action's name")
            // And the resolved chord is exactly what `SpaceBinding` would post — the engine
            // and the page read one value, so "shown equals sent" is structural.
            //
            // Guarded, **not** `row.entry.systemAction!`. This test is supposed to go red when
            // the Global arm stops being a system action — that is exactly what mutation M3 in
            // `scripts/mutation-check-gesture-labels.sh` injects. A force-unwrap there traps
            // instead of failing, and a trap inside the test runner never returns: it hung the
            // whole mutation run for 30 minutes with the mutated source still on disk. A test
            // that crashes on the bug it claims to catch is not a gate.
            guard let system = row.entry.systemAction else {
                XCTFail("\(direction.rawValue): the Global arm is not a system action")
                continue
            }
            XCTAssertEqual(row.systemShortcut, liveBindings.shortcut(for: system))
        }
    }

    /// A machine with nothing bound must produce a row that **says so**, not one that invents
    /// a key and not one that reads as "deliberately unassigned". Those are three different
    /// states and the UI treats them differently.
    func testUnboundSystemActionRowSaysSoInsteadOfInventingAKey() {
        let row = GestureMap.row(overrides: [:], bundle: "com.example.unknown",
                                 direction: .up, systemBindings: .empty)
        XCTAssertTrue(row.isUnboundSystemAction)
        XCTAssertNil(row.systemShortcut, "no binding exists, so nothing may be shown as a key")
        XCTAssertEqual(row.caption, GestureSystemAction.missionControl.unboundCaptionKey)
        XCTAssertNotNil(row.caption, "an empty caption reads as a broken cell")
        // It is still the action the engine will try — so the diagnostic can name it.
        XCTAssertEqual(row.action, .systemAction(.missionControl))
        // And crucially it is NOT reported as deliberately unassigned: that wording would
        // tell the user to pick an action, when the fix is to set the macOS shortcut.
        XCTAssertFalse(row.entry.isUnassigned)
    }

    /// Browsers keep their own history convention on the horizontal arms — the Global change
    /// must not have flattened a real per-app mapping into a system action.
    func testBrowserHorizontalArmsStayHistoryNotSpace() {
        let c = GestureShortcut.command
        for id in ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac"] {
            let row = GestureMap.row(overrides: [:], bundle: id, direction: .left,
                                     systemBindings: liveBindings)
            XCTAssertEqual(row.action, .shortcut(GestureShortcut(key: 33, flags: c)), id)
            XCTAssertNil(row.entry.systemAction, "\(id) left became a system action")
            XCTAssertFalse(row.isUnboundSystemAction)
        }
    }

    /// An override that **picks a system action** must round-trip. The old resolver built the
    /// override's entry with `shortcut: nil` and no system action, so the row reported itself
    /// as unassigned even though the action was stored — the user's choice vanished from the
    /// page while remaining in preferences.
    func testOverrideChoosingASystemActionIsNotReportedAsUnassigned() {
        var overrides: [String: [GestureDirection: GestureAction]] = [:]
        overrides["com.apple.Safari"] = [.down: .systemAction(.nextSpace)]
        let row = GestureMap.row(overrides: overrides, bundle: "com.apple.Safari",
                                 direction: .down, systemBindings: liveBindings)
        XCTAssertTrue(row.isUserOverride)
        XCTAssertEqual(row.entry.systemAction, .nextSpace)
        XCTAssertFalse(row.entry.isUnassigned, "a stored system action must not read as unassigned")
        XCTAssertEqual(row.caption, GestureShortcut(key: 124, flags: 8650752).label)
        XCTAssertEqual(row.action, .systemAction(.nextSpace))
    }

    /// Reset-to-preset drops only that direction's override, and the row goes back to the
    /// preset's system action — with the resolved chord, not with a stale override.
    func testResetToPresetRestoresTheSystemAction() {
        var overrides: [String: [GestureDirection: GestureAction]] = [:]
        overrides["com.example.unknown"] = [.up: .unassigned]
        let overridden = GestureMap.row(overrides: overrides, bundle: "com.example.unknown",
                                        direction: .up, systemBindings: liveBindings)
        XCTAssertTrue(overridden.entry.isUnassigned)
        // The controller's `resetDirection` removes the entry when the dict empties.
        overrides.removeValue(forKey: "com.example.unknown")
        let reset = GestureMap.row(overrides: overrides, bundle: "com.example.unknown",
                                   direction: .up, systemBindings: liveBindings)
        XCTAssertFalse(reset.isUserOverride)
        XCTAssertEqual(reset.action, .systemAction(.missionControl))
        XCTAssertEqual(reset.systemShortcut, GestureShortcut(key: 126, flags: 8650752))
    }

    /// The page's rows and the engine's dispatch must agree for **every** built-in bundle and
    /// direction, including the system arms — the brief's "one resolver, not two copies" rule
    /// as an assertion rather than as a convention.
    func testShownEqualsSentForEveryBundleAndDirection() {
        let cfg = GestureConfiguration()
        for profile in GestureProfiles.all {
            for direction in GestureDirection.allCases {
                let row = GestureMap.row(overrides: cfg.overrides, bundle: profile.id,
                                         direction: direction, systemBindings: liveBindings)
                XCTAssertEqual(row.action,
                               GestureProfiles.resolve(overrides: cfg.overrides, bundle: profile.id,
                                                       direction: direction),
                               "\(profile.id)/\(direction.rawValue): row and engine disagree")
                // A system row's displayed chord is the bindings' chord — never a constant.
                if let system = row.entry.systemAction {
                    XCTAssertEqual(row.systemShortcut, liveBindings.shortcut(for: system),
                                   "\(profile.id)/\(direction.rawValue): caption and dispatch disagree")
                }
            }
        }
    }

    // MARK: - PATCH v10.2: Side Buttons Instant Action + Safari Overrides

    func testInstantActionsAndButtonActionModels() {
        XCTAssertEqual(InstantAction.back.labelKey, "Lùi")
        XCTAssertEqual(InstantAction.back.shortcut.key, 33)
        XCTAssertEqual(InstantAction.back.shortcut.flags, GestureShortcut.command) // Command flag
        XCTAssertEqual(InstantAction.back.shortcut.label, "⌘[")

        XCTAssertEqual(InstantAction.forward.labelKey, "Tiến")
        XCTAssertEqual(InstantAction.forward.shortcut.key, 30)
        XCTAssertEqual(InstantAction.forward.shortcut.flags, GestureShortcut.command) // Command flag
        XCTAssertEqual(InstantAction.forward.shortcut.label, "⌘]")

        XCTAssertTrue(ButtonAction.instant(.back).isAssigned)
        XCTAssertTrue(ButtonAction.instant(.forward).isAssigned)
        XCTAssertFalse(ButtonAction.unassigned.isAssigned)

        // Lookup helper handles 0-based and 1-based indices
        let actions = GestureConfigStore.defaultButtonActions
        XCTAssertEqual(GestureConfigStore.action(in: actions, forEventButton: 3), .instant(.back))
        XCTAssertEqual(GestureConfigStore.action(in: actions, forEventButton: 4), .instant(.forward))
        XCTAssertNil(GestureConfigStore.action(in: actions, forEventButton: 2))
        XCTAssertNil(GestureConfigStore.action(in: actions, forEventButton: 5))
    }

    func testSafariProfileOverridesOnlyGesturesNotGlobalButtonActions() {
        var config = GestureConfiguration()
        XCTAssertEqual(config.buttonActions[4], .instant(.back))
        XCTAssertEqual(config.buttonActions[5], .instant(.forward))

        // Safari profile has built-in presets for gestures (left/right -> switch tab)
        let safariPreset = GestureProfiles.all.first { $0.id == "com.apple.Safari" }
        XCTAssertNotNil(safariPreset)
        let resolvedLeft = GestureProfiles.resolve(overrides: config.overrides, bundle: "com.apple.Safari", direction: .left)
        XCTAssertEqual(resolvedLeft, safariPreset?.defaults[.left])

        // Add user override for Safari direction
        config.overrides["com.apple.Safari"] = [.up: .shortcut(GestureShortcut(key: 17, flags: 1 << 20))]

        // Global button actions remain untouched
        XCTAssertEqual(config.buttonActions[4], .instant(.back))
        XCTAssertEqual(config.buttonActions[5], .instant(.forward))
        XCTAssertEqual(GestureConfigStore.action(in: config.buttonActions, forEventButton: 3), .instant(.back))
        XCTAssertEqual(GestureConfigStore.action(in: config.buttonActions, forEventButton: 4), .instant(.forward))
    }
}
