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
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.up),GestureProfiles.key(126,GestureShortcut.control))
        // An explicit per-bundle unassigned on a known app sticks.
        XCTAssertNotEqual(config.action(bundle:"com.apple.Safari",direction:.up),.unassigned)
        config.overrides["com.apple.Safari",default:[:]][.up] = .unassigned
        XCTAssertEqual(config.action(bundle:"com.apple.Safari",direction:.up),.unassigned)
        // Unknown app's Global fallback uses the Global profile itself; overriding
        // a single known app does not affect the unknown app's Global fallback.
        XCTAssertEqual(config.action(bundle:"unknown.app",direction:.up),GestureProfiles.key(126,GestureShortcut.control))
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
}
