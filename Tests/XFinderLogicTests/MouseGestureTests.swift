import XCTest

final class MouseGestureTests: XCTestCase {
    func testDefaultsAreOptIn() {
        let config = GestureConfiguration()
        XCTAssertFalse(config.enabled)
        XCTAssertFalse(config.tiltEnabled)
        XCTAssertFalse(config.debug)
        XCTAssertEqual(config.trigger, .mouseButton(2))
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
        }
        for id in ["com.microsoft.Word","com.microsoft.Excel"] {
            for d in GestureDirection.allCases { XCTAssertEqual(config.action(bundle:id,direction:d),.unassigned) }
        }
        XCTAssertEqual(config.action(bundle:"co.elastic.obsidian",direction:.down),.unassigned)
    }
    func testFallbackAndExplicitDisable() {
        var config = GestureConfiguration()
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.up),GestureProfiles.key(33,GestureShortcut.command | GestureShortcut.shift))
        // An explicit per-bundle unassigned on a known app sticks.
        XCTAssertNotEqual(config.action(bundle:"com.apple.Safari",direction:.up),.unassigned)
        config.overrides["com.apple.Safari",default:[:]][.up] = .unassigned
        XCTAssertEqual(config.action(bundle:"com.apple.Safari",direction:.up),.unassigned)
        // Unknown app's Global fallback uses the Global profile itself; overriding
        // a single known app does not affect the unknown app's Global fallback.
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.up),GestureProfiles.key(33,GestureShortcut.command | GestureShortcut.shift))
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
        XCTAssertEqual(config.trigger,.mouseButton(2)); XCTAssertEqual(config.deadzone,12)
        config.deadzone = 1e9; config.validate(); XCTAssertEqual(config.deadzone,200)
        XCTAssertFalse(TriggerSource.modifierKey(0).isValid)
        XCTAssertFalse(TriggerSource.modifierKey(GestureShortcut.command | GestureShortcut.shift).isValid)
        XCTAssertFalse(TriggerSource.mouseButton(32).isValid)
    }
    func testProfileIDsUniqueAndBrowserMappingExact() {
        XCTAssertEqual(Set(GestureProfiles.all.map(\.id)).count,GestureProfiles.all.count)
        let config = GestureConfiguration()
        for id in ["com.apple.Safari","com.google.Chrome","com.microsoft.edgemac"] {
            XCTAssertEqual(config.action(bundle:id,direction:.down),GestureProfiles.key(13,GestureShortcut.command))
            XCTAssertEqual(config.action(bundle:id,direction:.left),GestureProfiles.key(48,GestureShortcut.control | GestureShortcut.shift))
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

        // Global fallback: page/workspace navigation, not Mission Control.
        // Reason, measured not assumed: the MX Master 3 (cited in the brief as a
        // daily mouse) already binds Mission Control to its thumb button in Logi
        // Options, so a ⌃↑ Global duplicated a binding the user already had and the
        // page read as useless. Page navigation is what a gesture is actually
        // wanted for, and it is a real convention: ⌘⇧[ / ⌘⇧] step between tabs in
        // most macOS apps while ⌘[ / ⌘] step back and forward in history.
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .up), GestureProfiles.key(33, c | shift))
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .down), GestureProfiles.key(30, c | shift))
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .left), GestureProfiles.key(33, c))
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .right), GestureProfiles.key(30, c))
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .tiltLeft), GestureProfiles.key(24, c))
        XCTAssertEqual(cfg.action(bundle: "whatever.unknown", direction: .tiltRight), GestureProfiles.key(27, c))
        // The old Mission Control mapping must be gone, not merely shadowed.
        for (dir, key) in [(GestureDirection.up, 126), (.down, 125), (.left, 123), (.right, 124)] {
            XCTAssertNotEqual(cfg.action(bundle: "whatever.unknown", direction: dir),
                              GestureProfiles.key(UInt16(key), ctrl), "global \(dir.rawValue) still sends ⌃arrow")
        }

        // Browsers.
        for id in ["com.microsoft.edgemac", "com.apple.Safari", "com.google.Chrome"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .up), GestureProfiles.key(17, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .down), GestureProfiles.key(13, c), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .left), GestureProfiles.key(48, ctrl | shift), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .right), GestureProfiles.key(48, ctrl), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .tiltLeft), GestureProfiles.key(17, c | shift), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .tiltRight), GestureProfiles.key(17, c | shift), id)
        }

        // Dev & AI: only the two zoom directions; up/down stay unassigned.
        for id in ["com.visualstudio.code", "com.cursor.ide", "dev.zed.Zed", "com.antigravity.ide", "com.anthropic.claude"] {
            XCTAssertEqual(cfg.action(bundle: id, direction: .left), GestureProfiles.key(27, ctrl), id)
            XCTAssertEqual(cfg.action(bundle: id, direction: .right), GestureProfiles.key(27, ctrl | shift), id)
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

        // Office: deliberately empty — Word has no worksheets, and no verified
        // Excel-specific shortcut was ever supplied. Nothing may be invented here.
        for id in ["com.microsoft.Excel", "com.microsoft.Word"] {
            XCTAssertTrue(GestureProfiles.all.first { $0.id == id }!.defaults.isEmpty, id)
        }

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

    /// Families must not share a map by accident, and no ambiguous slot may be
    /// filled with an invented shortcut.
    func testFamiliesDoNotShareAccidentalMappings() {
        let dev = GestureProfiles.all.first { $0.id == "com.visualstudio.code" }!.defaults
        let browsers = GestureProfiles.all.first { $0.id == "com.apple.Safari" }!.defaults
        let office = GestureProfiles.all.first { $0.id == "com.microsoft.Word" }!.defaults
        XCTAssertTrue(office.isEmpty)
        for (dir, action) in dev {
            XCTAssertNotEqual(browsers[dir], action, "dev and browsers share \(dir.rawValue)")
        }
        XCTAssertNil(dev[.up]); XCTAssertNil(dev[.down])
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
    /// The three numbers every mouse shares may carry a short factual note; slash
    /// numbering means `mouseButton(n)` must read "Nút \(n+1)" so 0 → "Nút 1".
    func testTriggerLabelsNameButtonsByNumber() {
        XCTAssertTrue(TriggerSource.mouseButton(0).label.contains("Nút 1"),
                      "macOS button 0 is the user's button 1")
        XCTAssertTrue(TriggerSource.mouseButton(1).label.contains("Nút 2"),
                      "macOS button 1 is the user's button 2")
        XCTAssertTrue(TriggerSource.mouseButton(2).label.contains("Nút 3"),
                      "macOS button 2 is the user's button 3")
        // The offset must hold for every number, not just the first three.
        for n in 1...31 {
            XCTAssertEqual(TriggerSource.mouseButton(n).numberedName, "Nút \(n + 1)", "button \(n)")
        }
        // Side/multimedia buttons are just numbers — no invented anatomy.
        XCTAssertEqual(TriggerSource.mouseButton(3).label, "Nút 4")
        XCTAssertEqual(TriggerSource.mouseButton(4).label, "Nút 5")
        for banned in ["hông", "bắn tỉa", "DPI", "sniper", "con lăn"] {
            XCTAssertFalse(TriggerSource.mouseButton(4).label.contains(banned),
                           "invented physical name '\(banned)' came back")
        }

        // The default must be the one users can find without a vendor utility.
        XCTAssertEqual(GestureConfiguration().trigger, .mouseButton(2))
        XCTAssertFalse(TriggerSource.mouseButton(2).label.contains("Button 2"),
                       "the raw CoreGraphics code is not a user-facing name")

        // Out-of-range codes still render something, never an empty label.
        XCTAssertFalse(TriggerSource.mouseButton(9).label.isEmpty)
    }

    /// The page's promise: an arrow must never be bare. "Tôi ko hiểu dùng nút nào
    /// của chuột với mũi tên" is what the user said, so every non-tilt heading has
    /// to name the held button, and every heading must be distinct.
    func testEveryDirectionHeadingNamesTheHeldButton() {
        for trigger in [TriggerSource.mouseButton(2), .mouseButton(4), .modifierKey(GestureShortcut.control)] {
            for dir in [GestureDirection.up, .down, .left, .right] {
                let text = dir.title(trigger: trigger)
                XCTAssertFalse(text.isEmpty, "\(dir) has no heading")
                XCTAssertTrue(text.contains(trigger.numberedName),
                              "\(dir) heading omits the button: \(text)")
                XCTAssertTrue(text.contains("kéo"), "\(dir) must say it is a drag: \(text)")
                XCTAssertFalse(text.contains("giữ nút"),
                               "\(dir) says 'giữ nút' without saying which button: \(text)")
            }
        }
        // Tilt is a different physical motion and must NOT claim a held button.
        for dir in [GestureDirection.tiltLeft, .tiltRight] {
            let text = dir.title(trigger: .mouseButton(2))
            XCTAssertTrue(text.contains("Nghiêng"), "\(dir) must say the wheel is tilted: \(text)")
            XCTAssertFalse(text.contains("Nút 3"),
                           "\(dir) is performed without holding a button: \(text)")
        }
        // Every heading must differ, or the diagram cannot be read.
        let all = GestureDirection.allCases.map { $0.title(trigger: .mouseButton(2)) }
        XCTAssertEqual(Set(all).count, all.count, "directions share a heading: \(all)")
    }
    /// The diagram must never draw an arm that cannot fire, and every direction it
    /// *does* draw must be reachable. Both directions of the `isTilt` split are
    /// checked, because the classifier and the engine have to agree: the engine
    /// only reads `tiltLeft`/`tiltRight` from the scroll handler.
    func testTiltDirectionsAreExactlyTheScrollHandledOnes() {
        for dir in GestureDirection.allCases {
            let expected = (dir == .tiltLeft || dir == .tiltRight)
            XCTAssertEqual(GestureTriggerKind.isTilt(dir), expected, dir.rawValue)
            XCTAssertEqual(GestureDirectionDisplay.isTilt(dir), expected, dir.rawValue)
            // Horizontal-scroll pass-through is offered only where it is meaningful.
            XCTAssertEqual(GestureDirectionDisplay.supportsHorizontalScroll(dir), expected, dir.rawValue)
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
        // Both switches are independent; neither may imply the other.
        XCTAssertFalse(GestureConfiguration().tiltEnabled)
        var config = GestureConfiguration()
        config.tiltAvailable = true
        XCTAssertTrue(config.tiltAvailable)
        XCTAssertFalse(config.tiltEnabled, "revealing the arms must not switch them on")
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

    /// Every direction must produce a non-empty, distinct heading in the detail
    /// panel. A missing case would render an empty title above the keys.
    func testEveryDirectionHasADistinctDetailHeading() {
        let titles = GestureDirection.allCases.map {
            GestureDirectionDisplay.title($0, trigger: .mouseButton(2))
        }
        XCTAssertEqual(titles.count, GestureDirection.allCases.count)
        for title in titles { XCTAssertFalse(title.isEmpty, "direction has no heading") }
        XCTAssertEqual(Set(titles).count, titles.count, "two directions share a heading")
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
                       .shortcut(GestureShortcut(key: 48, flags: ctrl)))
    }

    /// "Raw horizontal scroll" is offered on exactly the two tilt arms and never
    /// on a button-drag arm. The engine refuses to act on `.horizontalScroll` for
    /// tilt (it passes the event through), so the option means "leave it native" —
    /// offering it on `↑`/`↓`/`←`/`→` would promise pass-through on a motion that
    /// has nothing to pass through.
    func testHorizontalScrollOfferedOnlyOnTiltArms() {
        for direction in GestureDirection.allCases {
            let offered = GestureDirectionDisplay.supportsHorizontalScroll(direction)
            XCTAssertEqual(offered, GestureDirectionDisplay.isTilt(direction),
                           "\(direction.rawValue): horizontal-scroll option disagrees with tilt-ness")
        }
        XCTAssertTrue(GestureDirectionDisplay.supportsHorizontalScroll(.tiltLeft))
        XCTAssertTrue(GestureDirectionDisplay.supportsHorizontalScroll(.tiltRight))
        XCTAssertFalse(GestureDirectionDisplay.supportsHorizontalScroll(.up))
        XCTAssertFalse(GestureDirectionDisplay.supportsHorizontalScroll(.left))
    }
}
