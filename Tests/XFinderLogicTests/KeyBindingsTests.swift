import XCTest
import Foundation

/// XF-T30 W4 — tests for `KeyBindings`. Covers: (1) the three bulk-rebind profiles (Finder/Windows Explorer/Total
/// Commander) bind what the contract §2 table requires, (2) `validate` rejects the required categories (no ⌘/⌃,
/// system-reserved, view-reserved) and allows the exceptions (function keys, a profile's own claimed reserved
/// chord), (3) conflict detection + `assign` ("Use Anyway" moves the key, stripping it from the loser), (4)
/// restore one/all, (5) export/import round trip, and (6) malformed/malicious import data reports every problem
/// and applies nothing.
final class KeyBindingsTests: XCTestCase {

    // MARK: - Profiles

    func testFinderProfileFallsBackToBrowserCommandsDefaults() {
        let bindings = KeyBindings()
        XCTAssertEqual(bindings.profile, .finder)
        XCTAssertEqual(bindings.binding(for: .newWindow).primary, KeyChord("n", command: true))
        XCTAssertEqual(bindings.binding(for: .rename).primary, KeyChord("return"))
        XCTAssertFalse(bindings.tabSwitchesPanes)
    }

    func testWindowsExplorerProfileBindings() {
        var bindings = KeyBindings()
        bindings.apply(.explorer)
        XCTAssertEqual(bindings.binding(for: .open).primary, KeyChord("return"))
        XCTAssertEqual(bindings.binding(for: .rename).primary, KeyChord("f2"))
        XCTAssertEqual(bindings.binding(for: .cut).primary, KeyChord("x", command: true))
        // "Delete does not move to Trash" (contract §2): the Finder chord (⌘⌫) is unbound under this profile.
        XCTAssertNil(bindings.binding(for: .moveToTrash).primary)
        XCTAssertFalse(bindings.tabSwitchesPanes)
    }

    func testTotalCommanderProfileBindings() {
        var bindings = KeyBindings()
        bindings.apply(.commander)
        XCTAssertEqual(bindings.binding(for: .copyToOtherPane).primary, KeyChord("f5"))
        XCTAssertEqual(bindings.binding(for: .moveToOtherPane).primary, KeyChord("f6"))
        XCTAssertEqual(bindings.binding(for: .newFolder).primary, KeyChord("f7"))
        XCTAssertEqual(bindings.binding(for: .moveToTrash).primary, KeyChord("f8"))
        XCTAssertEqual(bindings.binding(for: .open).primary, KeyChord("return"))
        XCTAssertTrue(bindings.tabSwitchesPanes, "Total Commander profile switches panes via Tab")
    }

    func testApplyingAProfileClearsPriorOverridesButStaysEditable() {
        var bindings = KeyBindings()
        bindings.assign(KeyChord("j", command: true, control: true), to: .showViewOptions, extra: false)
        XCTAssertEqual(bindings.binding(for: .showViewOptions).primary, KeyChord("j", command: true, control: true))

        bindings.apply(.explorer)
        // Prior custom override is gone; the profile's own defaults are now in effect...
        XCTAssertEqual(bindings.binding(for: .showViewOptions).primary, BrowserCommands.chord(for: .showViewOptions))
        // ...but the table is still freely editable afterward (contract: "áp hồ sơ rồi vẫn sửa được").
        bindings.assign(KeyChord("j", command: true, shift: true), to: .showViewOptions, extra: false)
        XCTAssertEqual(bindings.binding(for: .showViewOptions).primary, KeyChord("j", command: true, shift: true))
    }

    func testCustomProfileHasNoBulkOverridesOfItsOwn() {
        let bindings = KeyBindings(profile: .custom)
        XCTAssertEqual(bindings.binding(for: .open).primary, BrowserCommands.chord(for: .open))
    }

    // MARK: - Validation: needs ⌘ or ⌃ except function keys

    func testValidateRejectsChordWithoutCommandOrControl() {
        let bindings = KeyBindings()
        XCTAssertEqual(bindings.validate(KeyChord("k")), .needsCommandOrControl)
        XCTAssertEqual(bindings.validate(KeyChord("k", shift: true)), .needsCommandOrControl)
        XCTAssertEqual(bindings.validate(KeyChord("k", option: true)), .needsCommandOrControl)
    }

    func testValidateAllowsCommandOrControlAlone() {
        let bindings = KeyBindings()
        XCTAssertNil(bindings.validate(KeyChord("k", command: true)))
        XCTAssertNil(bindings.validate(KeyChord("k", control: true)))
    }

    func testValidateAllowsBareFunctionKeysExceptF2WhichStaysReserved() {
        // Contract §2: "trừ F1–F12 trong hồ sơ" for the ⌘/⌃ requirement, but F2 is separately named among the
        // reserved-by-views keys ("Return/Space/Tab/mũi tên/F2") unless a profile claims it (Windows Explorer's
        // own F2-renames). Under the plain Finder profile, F2 alone must still be refused.
        let bindings = KeyBindings()
        for n in 1...12 where n != 2 {
            XCTAssertNil(bindings.validate(KeyChord("f\(n)")), "F\(n) alone must be allowed")
        }
        XCTAssertEqual(bindings.validate(KeyChord("f2")), .reservedByViews, "F2 alone stays reserved outside a profile that claims it")
    }

    func testValidateAllowsBareF2UnderWindowsExplorerProfile() {
        var bindings = KeyBindings()
        bindings.apply(.explorer)
        XCTAssertNil(bindings.validate(KeyChord("f2")), "Windows Explorer profile claims F2 for rename")
    }

    // MARK: - Validation: system-reserved chords

    func testValidateRejectsSystemReservedChords() {
        let bindings = KeyBindings()
        let reserved: [KeyChord] = [
            KeyChord("q", command: true),
            KeyChord("h", command: true),
            KeyChord("m", command: true),
            KeyChord("tab", command: true),
            KeyChord("space", command: true),
            KeyChord("`", command: true),
        ]
        for chord in reserved {
            XCTAssertEqual(bindings.validate(chord), .reservedBySystem, "\(chord) must be rejected as system-reserved")
        }
    }

    func testSystemReservedChordIsRejectedUnderEveryProfile() {
        for profile in KeyProfile.allCases {
            var bindings = KeyBindings()
            bindings.apply(profile)
            XCTAssertEqual(bindings.validate(KeyChord("q", command: true)), .reservedBySystem, "\(profile) must still reject ⌘Q")
        }
    }

    // MARK: - Validation: view-reserved chords (Return/Space/Tab/arrows/F2) unless a profile claims them

    func testValidateRejectsViewReservedChordsUnderFinderProfile() {
        let bindings = KeyBindings()   // default profile == .finder, claims none of these
        let reserved: [KeyChord] = [
            KeyChord("return"), KeyChord("space"), KeyChord("tab"),
            KeyChord("left"), KeyChord("right"), KeyChord("up"), KeyChord("down"),
            KeyChord("f2"),
        ]
        for chord in reserved {
            XCTAssertEqual(bindings.validate(chord), .reservedByViews, "\(chord) must be rejected under Finder profile")
        }
    }

    func testValidateAllowsReturnUnderWindowsExplorerProfile() {
        var bindings = KeyBindings()
        bindings.apply(.explorer)
        // The profile's own claimed chords validate clean (re-validating its own bulk rebind must not fail).
        XCTAssertNil(bindings.validate(KeyChord("return")))
        XCTAssertNil(bindings.validate(KeyChord("f2")))
        // Chords this profile does NOT claim stay reserved.
        XCTAssertEqual(bindings.validate(KeyChord("tab")), .reservedByViews)
        XCTAssertEqual(bindings.validate(KeyChord("space")), .reservedByViews)
    }

    func testValidateAllowsTabAndReturnUnderTotalCommanderProfile() {
        var bindings = KeyBindings()
        bindings.apply(.commander)
        XCTAssertNil(bindings.validate(KeyChord("tab")))
        XCTAssertNil(bindings.validate(KeyChord("return")))
        // F2 is not this profile's business, so it stays reserved.
        XCTAssertEqual(bindings.validate(KeyChord("f2")), .reservedByViews)
    }

    func testValidateStillRejectsArrowsUnderEveryProfile() {
        for profile in KeyProfile.allCases {
            var bindings = KeyBindings()
            bindings.apply(profile)
            for chord in [KeyChord("left"), KeyChord("right"), KeyChord("up"), KeyChord("down")] {
                XCTAssertEqual(bindings.validate(chord), .reservedByViews, "\(profile)/\(chord) must stay reserved")
            }
        }
    }

    // MARK: - Lookup / round trip through command(for:)

    func testCommandForChordRoundTripsThroughBindingFor() {
        let bindings = KeyBindings()
        for command in BrowserCommand.allCases {
            guard let chord = bindings.binding(for: command).primary else { continue }
            XCTAssertEqual(bindings.command(for: chord), command, "\(chord) must resolve back to \(command)")
        }
    }

    func testCommandForChordFindsExtraBindingToo() {
        var bindings = KeyBindings()
        let extra = KeyChord("j", command: true, control: true)
        bindings.assign(extra, to: .showViewOptions, extra: true)
        XCTAssertEqual(bindings.command(for: extra), .showViewOptions)
    }

    func testCommandForUnboundChordIsNil() {
        let bindings = KeyBindings()
        XCTAssertNil(bindings.command(for: KeyChord("k", command: true, shift: true, option: true, control: true)))
    }

    // MARK: - Conflict + assign ("Use Anyway" moves the key)

    func testConflictDetectsTheCommandAlreadyHoldingAChord() {
        let bindings = KeyBindings()
        let newWindowChord = KeyChord("n", command: true)
        XCTAssertEqual(bindings.conflict(for: newWindowChord, excluding: .newFolder), .newWindow)
    }

    func testConflictExcludesTheCommandBeingEdited() {
        let bindings = KeyBindings()
        let newWindowChord = KeyChord("n", command: true)
        XCTAssertNil(bindings.conflict(for: newWindowChord, excluding: .newWindow))
    }

    func testConflictIsNilForAnUnusedChord() {
        let bindings = KeyBindings()
        XCTAssertNil(bindings.conflict(for: KeyChord("k", command: true, shift: true, option: true, control: true), excluding: .newWindow))
    }

    func testAssignUseAnywayMovesTheKeyAwayFromTheLoser() {
        var bindings = KeyBindings()
        let chord = KeyChord("n", command: true)   // currently .newWindow's primary
        XCTAssertEqual(bindings.conflict(for: chord, excluding: .newFolder), .newWindow)

        bindings.assign(chord, to: .newFolder, extra: false)

        XCTAssertEqual(bindings.binding(for: .newFolder).primary, chord)
        XCTAssertNil(bindings.binding(for: .newWindow).primary, "losing command must give the key up")
        XCTAssertNil(bindings.conflict(for: chord, excluding: .newFolder), "no longer contested after the move")
    }

    func testAssignStripsBothPrimaryAndExtraFromTheLoser() {
        var bindings = KeyBindings()
        let chord = KeyChord("j", command: true, control: true)
        bindings.assign(chord, to: .showViewOptions, extra: true)   // showViewOptions now holds it as `extra`
        XCTAssertEqual(bindings.binding(for: .showViewOptions).extra, chord)

        bindings.assign(chord, to: .find, extra: false)

        XCTAssertEqual(bindings.binding(for: .find).primary, chord)
        XCTAssertNil(bindings.binding(for: .showViewOptions).extra, "extra slot must be cleared too")
    }

    func testAssignNilClearsASlotWithoutTouchingOtherCommands() {
        var bindings = KeyBindings()
        bindings.assign(nil, to: .newWindow, extra: false)
        XCTAssertNil(bindings.binding(for: .newWindow).primary)
        // Unrelated command untouched.
        XCTAssertEqual(bindings.binding(for: .newFolder).primary, KeyChord("n", command: true, shift: true))
    }

    func testAssignOnlyStealsFromOtherCommandsNeverFromNilInput() {
        var bindings = KeyBindings()
        // Clearing a slot (nil) must not scan-and-steal from anyone.
        bindings.assign(nil, to: .open, extra: false)
        XCTAssertEqual(bindings.binding(for: .back).primary, KeyChord("[", command: true), "unrelated bindings must survive clearing a slot")
    }

    // MARK: - Restore one / all

    func testRestoreDefaultRevertsOnlyThatCommand() {
        var bindings = KeyBindings()
        bindings.assign(KeyChord("k", command: true, shift: true), to: .find, extra: false)
        bindings.assign(KeyChord("k", command: true, option: true), to: .getInfo, extra: false)

        bindings.restoreDefault(.find)

        XCTAssertEqual(bindings.binding(for: .find).primary, BrowserCommands.chord(for: .find))
        XCTAssertEqual(bindings.binding(for: .getInfo).primary, KeyChord("k", command: true, option: true), "unrelated override must survive")
    }

    func testRestoreAllDefaultsClearsEveryOverrideButKeepsProfileAndOptions() {
        var bindings = KeyBindings()
        bindings.apply(.explorer)
        bindings.assign(KeyChord("k", command: true, shift: true), to: .find, extra: false)
        bindings.mouse = .swapped

        bindings.restoreAllDefaults()

        XCTAssertEqual(bindings.binding(for: .find).primary, BrowserCommands.chord(for: .find))
        XCTAssertEqual(bindings.profile, .explorer, "restoreAllDefaults must not reset the profile itself")
        XCTAssertEqual(bindings.mouse, .swapped, "restoreAllDefaults must not touch mouse options")
        // Explorer's OWN profile default (not Finder's) must still apply after a full restore.
        XCTAssertEqual(bindings.binding(for: .rename).primary, KeyChord("f2"))
    }

    // MARK: - Export / Import round trip

    func testExportImportRoundTrip() {
        var bindings = KeyBindings()
        bindings.apply(.commander)
        bindings.assign(KeyChord("k", command: true, shift: true), to: .find, extra: false)
        bindings.mouse = .swapped

        let data = bindings.export()
        switch KeyBindings.importing(data) {
        case .success(let imported):
            XCTAssertEqual(imported, bindings)
        case .failure(let failure):
            XCTFail("round trip must succeed, got \(failure.errors)")
        }
    }

    func testExportIncludesTabSwitchesPanesAndMouseSetting() {
        var bindings = KeyBindings()
        bindings.tabSwitchesPanes = true
        bindings.mouse = .off
        let data = bindings.export()
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("tabSwitchesPanes"), "export must carry the pane-switch option")
        XCTAssertTrue(text.contains("mouse") || text.contains("off"), "export must carry the mouse option")
    }

    func testImportOfDefaultExportIsIdempotent() {
        let bindings = KeyBindings()
        let data = bindings.export()
        switch KeyBindings.importing(data) {
        case .success(let imported):
            XCTAssertEqual(imported, bindings)
        case .failure(let failure):
            XCTFail("default export must import cleanly, got \(failure.errors)")
        }
    }

    // MARK: - Import validation: everything checked up front, nothing applied on any error

    func testImportRejectsUnknownCommandAndAppliesNothing() throws {
        let bindings = KeyBindings()
        var raw = try JSONSerialization.jsonObject(with: bindings.export()) as! [String: Any]
        var overrides = (raw["overrides"] as? [String: Any]) ?? [:]
        overrides["notACommand"] = ["primary": ["key": "k", "command": true, "shift": false, "option": false, "control": false]]
        raw["overrides"] = overrides
        let data = try JSONSerialization.data(withJSONObject: raw)

        switch KeyBindings.importing(data) {
        case .success:
            XCTFail("must not succeed with an unknown command")
        case .failure(let failure):
            XCTAssertTrue(failure.errors.contains(.unknownCommand("notACommand")))
        }
    }

    func testImportRejectsAKeyUsedTwice() throws {
        let bindings = KeyBindings()
        var raw = try JSONSerialization.jsonObject(with: bindings.export()) as! [String: Any]
        let chordJSON: [String: Any] = ["key": "k", "command": true, "shift": false, "option": false, "control": false]
        raw["overrides"] = [
            "find": ["primary": chordJSON],
            "getInfo": ["primary": chordJSON],
        ]
        let data = try JSONSerialization.data(withJSONObject: raw)

        switch KeyBindings.importing(data) {
        case .success:
            XCTFail("must not succeed when two commands claim the same key")
        case .failure(let failure):
            XCTAssertTrue(failure.errors.contains { if case .keyUsedTwice = $0 { return true }; return false })
        }
    }

    func testImportRejectsAReservedKey() throws {
        let bindings = KeyBindings()
        var raw = try JSONSerialization.jsonObject(with: bindings.export()) as! [String: Any]
        raw["overrides"] = [
            "find": ["primary": ["key": "q", "command": true, "shift": false, "option": false, "control": false]],
        ]
        let data = try JSONSerialization.data(withJSONObject: raw)

        switch KeyBindings.importing(data) {
        case .success:
            XCTFail("must not succeed with a system-reserved key (⌘Q)")
        case .failure(let failure):
            XCTAssertTrue(failure.errors.contains { if case .reservedKey = $0 { return true }; return false })
        }
    }

    func testImportListsEveryErrorAtOnceNotJustTheFirst() throws {
        let bindings = KeyBindings()
        var raw = try JSONSerialization.jsonObject(with: bindings.export()) as! [String: Any]
        raw["overrides"] = [
            "notACommand": ["primary": ["key": "k", "command": true, "shift": false, "option": false, "control": false]],
            "find": ["primary": ["key": "q", "command": true, "shift": false, "option": false, "control": false]],
        ]
        let data = try JSONSerialization.data(withJSONObject: raw)

        switch KeyBindings.importing(data) {
        case .success:
            XCTFail("must not succeed with multiple problems present")
        case .failure(let failure):
            XCTAssertTrue(failure.errors.contains(.unknownCommand("notACommand")))
            XCTAssertTrue(failure.errors.contains { if case .reservedKey = $0 { return true }; return false })
            XCTAssertGreaterThanOrEqual(failure.errors.count, 2, "every problem must be reported, not just the first")
        }
    }

    func testImportOfGarbageBytesFailsWithUnreadableAndAppliesNothing() {
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF, 0x13, 0x37])
        switch KeyBindings.importing(garbage) {
        case .success:
            XCTFail("garbage bytes must never decode into bindings")
        case .failure(let failure):
            XCTAssertEqual(failure.errors, [.unreadable])
        }
    }

    func testImportOfTruncatedJsonFails() {
        let truncated = Data("{\"profile\":\"finder\",\"overrides\":{".utf8)
        switch KeyBindings.importing(truncated) {
        case .success:
            XCTFail("truncated JSON must never decode into bindings")
        case .failure(let failure):
            XCTAssertEqual(failure.errors, [.unreadable])
        }
    }

    func testImportOfWrongShapeJsonFails() {
        // Valid JSON, but not the KeyBindings shape at all (an array instead of an object).
        let wrongShape = Data("[1, 2, 3]".utf8)
        switch KeyBindings.importing(wrongShape) {
        case .success:
            XCTFail("a JSON array must never decode into bindings")
        case .failure(let failure):
            XCTAssertEqual(failure.errors, [.unreadable])
        }
    }

    func testImportNeverExecutesAnythingItIsPureDataDecoding() {
        // Spec R30 / guide note: "A profile only holds keys and options, so importing one can't run anything."
        // A string that LOOKS like a shell/code payload must just fail validation like any other bad command name,
        // never be interpreted.
        let malicious = Data("""
        {"profile":"finder","overrides":{"$(rm -rf ~)":{"primary":{"key":"k","command":true,"shift":false,"option":false,"control":false}}},"tabSwitchesPanes":false,"mouse":"on"}
        """.utf8)
        switch KeyBindings.importing(malicious) {
        case .success:
            XCTFail("must not succeed with an unknown/malicious command key")
        case .failure(let failure):
            XCTAssertTrue(failure.errors.contains(.unknownCommand("$(rm -rf ~)")))
        }
    }

    // MARK: - Equatable / Codable plumbing

    func testKeyBindingsDefaultIsStable() {
        XCTAssertEqual(KeyBindings(), KeyBindings())
    }

    func testTwoProfilesWithSameOverridesAreNotEqualWhenProfileDiffers() {
        var a = KeyBindings()
        var b = KeyBindings()
        b.apply(.explorer)
        XCTAssertNotEqual(a.profile, b.profile)
        a.profile = .explorer
        XCTAssertEqual(a, b)
    }
}
