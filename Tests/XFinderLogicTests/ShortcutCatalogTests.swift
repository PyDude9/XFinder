import XCTest
import Foundation

/// P3 D1 — tests for `ShortcutCatalog`. Three kinds of check, per CLAUDE.md's rule that a mutation must be able to
/// fail: (1) pure logic on the catalog's own data (conflict detection), (2) every `titleKey`/`ownerPage` resolves
/// against real data the test package can see (the L10n store, `SidebarDestination`), (3) a SOURCE check that each
/// fixed key code still appears in the engine file that fires it, so a future rewrite of that engine cannot drift
/// silently from this catalog's claims.
final class ShortcutCatalogTests: XCTestCase {

    // MARK: - Conflict detection

    func testConflictDetectsCaptureCtrlOptDVsSnapLeftThird() {
        // Capture's recorder lets a user record ANY chord for `.area`, including one that collides with an
        // already-fixed Snap Zones shortcut the recorder has never heard of (survey finding D.4).
        let ctrlOptD = ShortcutCatalog.Chord(keyCode: 2, modifiers: [.control, .option])
        let recorded: [String: ShortcutCatalog.Chord] = [
            "snap.leftThird": ctrlOptD,
        ]
        let result = ShortcutCatalog.conflicts(for: ctrlOptD, owner: "capture.area", recorded: recorded) { _ in true }
        XCTAssertEqual(result.owners, ["snap.leftThird"])
        XCTAssertFalse(result.isEmpty)
    }

    func testInactiveOwnerIsIgnored() {
        // A shortcut whose feature is switched off cannot actually fire, so recording the same chord elsewhere is
        // not a real clash — `isActive` must gate the owners list, not just exist for show.
        let chord = ShortcutCatalog.Chord(keyCode: 12, modifiers: [.command, .shift])
        let recorded: [String: ShortcutCatalog.Chord] = ["other.owner": chord]
        let result = ShortcutCatalog.conflicts(for: chord, owner: "me", recorded: recorded) { id in id != "other.owner" }
        XCTAssertTrue(result.owners.isEmpty)
    }

    func testOwnEntryNeverConflictsWithItself() {
        let chord = ShortcutCatalog.Chord(keyCode: 9, modifiers: [.command, .shift])
        let recorded: [String: ShortcutCatalog.Chord] = ["clipboard.shelf": chord]
        let result = ShortcutCatalog.conflicts(for: chord, owner: "clipboard.shelf", recorded: recorded) { _ in true }
        XCTAssertTrue(result.owners.isEmpty, "an entry re-recorded to its own current chord is not a clash")
    }

    func testFindNextCollisionIsAWarningNotASystemReservedClash() {
        let shiftCmdG = ShortcutCatalog.Chord(keyCode: 5, modifiers: [.command, .shift])
        let result = ShortcutCatalog.conflicts(for: shiftCmdG, owner: "translate.selection", recorded: [:]) { _ in true }
        XCTAssertEqual(result.conventions.count, 1)
        XCTAssertTrue(result.conventions[0].isConventionOnly, "Find Next is an app convention, not an OS reservation")
    }

    func testSystemReservedScreenshotChordsAreFlaggedNotWarningOnly() {
        // ⇧⌘4 — macOS's own screen-region screenshot, from CaptureRules.systemReserved.
        let shiftCmd4 = ShortcutCatalog.Chord(keyCode: 21, modifiers: [.command, .shift])
        let result = ShortcutCatalog.conflicts(for: shiftCmd4, owner: "capture.area", recorded: [:]) { _ in true }
        XCTAssertFalse(result.conventions.isEmpty)
        XCTAssertFalse(result.conventions[0].isConventionOnly)
    }

    func testNoConflictWhenNothingSharesTheChord() {
        let unique = ShortcutCatalog.Chord(keyCode: 40, modifiers: [.command, .control, .option, .shift])
        let result = ShortcutCatalog.conflicts(for: unique, owner: "nobody", recorded: [:]) { _ in true }
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Chord label

    func testChordLabelOrdersModifiersControlOptionShiftCommand() {
        let c = ShortcutCatalog.Chord(keyCode: 21, modifiers: [.command, .control, .option, .shift])
        XCTAssertEqual(c.label, "⌃⌥⇧⌘Key 21")
    }

    func testChordLabelKnownLetterAndNamedKeys() {
        XCTAssertEqual(ShortcutCatalog.Chord(keyCode: 9, modifiers: [.command, .shift]).label, "⇧⌘V")
        XCTAssertEqual(ShortcutCatalog.Chord(keyCode: 123, modifiers: [.control, .option]).label, "⌃⌥←")
        XCTAssertEqual(ShortcutCatalog.Chord(keyCode: 36, modifiers: []).label, "↩")
    }

    // MARK: - Every owner page is real

    func testEveryFixedEntryOwnerPageIsARealSidebarDestination() {
        for entry in ShortcutCatalog.fixedEntries {
            XCTAssertNotNil(SidebarDestination(rawValue: entry.ownerPage),
                             "\(entry.id) names an owner page that does not exist: \(entry.ownerPage)")
        }
    }

    // MARK: - Every titleKey (and system-convention nameKey) is in the shipped store

    private func storeEntries() throws -> [String: Any] {
        let url = ShortcutCatalogTests.repoRoot.appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (root["entries"] as? [String: Any]) ?? root
    }

    func testEveryFixedEntryTitleKeyIsTranslated() throws {
        let store = try storeEntries()
        let keys = ShortcutCatalog.fixedEntries.map(\.titleKey)
        XCTAssertGreaterThan(keys.count, 10, "a collapsed list would pass as a clean one")
        for k in keys {
            let en = (store[k] as? [String: Any])?["en"] as? String
            XCTAssertFalse((en ?? "").isEmpty, "not translated: \(k)")
        }
    }

    func testEverySystemConventionNameKeyIsTranslated() throws {
        let store = try storeEntries()
        let keys = ShortcutCatalog.systemConventions.map(\.nameKey)
        XCTAssertGreaterThan(keys.count, 3, "a collapsed list would pass as a clean one")
        for k in keys {
            let en = (store[k] as? [String: Any])?["en"] as? String
            XCTAssertFalse((en ?? "").isEmpty, "not translated: \(k)")
        }
    }

    // MARK: - Fixed entries are unique by id

    func testFixedEntryIDsAreUnique() {
        let ids = ShortcutCatalog.fixedEntries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate id in fixedEntries")
    }

    // MARK: - Source checks: every fixed key code still appears in its engine

    /// `Tests/XFinderLogicTests/<this file>` → repo root. Never force-unwrap: a missing file must FAIL the test,
    /// not crash the test runner (CLAUDE.md's "never force-unwrap a value a mutation could remove" rule, applied
    /// here to "a value a future refactor could remove").
    static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // XFinderLogicTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.repoRoot.appendingPathComponent(relativePath)
        return try XCTUnwrap(try? String(contentsOf: url, encoding: .utf8),
                              "cannot read \(relativePath) from \(Self.repoRoot.path)")
    }

    /// A gate that reads nothing must fail, never pass silently — every `source(...)` call below asserts the
    /// substring is present, so a rotted anchor (the engine renamed/removed the literal) turns this test red
    /// instead of leaving the catalog's claim unverified.
    // P3 integration: these used to check a HAND-WRITTEN list of key codes against the engines, so the catalog — the
    // thing under test — could drift freely (mutation C4: leftThird 2 → 3 stayed green, because 3 is wired… to
    // centerThird). Each now takes the value FROM the catalog and checks the engine maps it to the same action.

    private func entry(_ id: String) throws -> ShortcutCatalog.Entry {
        try XCTUnwrap(ShortcutCatalog.fixedEntries.first { $0.id == id }, "catalog entry \(id) is missing")
    }

    func testBrowserLauncherAlternateAndCorruptPreferenceResolveConsistently() throws {
        let launcher = try entry("fileBrowser.open")
        let alternate = ShortcutCatalog.browserLauncherChord(setting: "controlShiftCommandF")
        XCTAssertEqual(alternate.keyCode, 3)
        XCTAssertEqual(alternate.modifiers, [.control, .shift, .command])
        XCTAssertEqual(ShortcutCatalog.liveChord(of: launcher, switcherSetting: "commandTab",
                                               browserLauncherSetting: "controlShiftCommandF"), alternate)
        XCTAssertEqual(ShortcutCatalog.browserLauncherChord(setting: "corrupt"), launcher.chord)
        let reader = try source("XFinder/Core/Browser/BrowserSettings.swift")
        XCTAssertTrue(reader.contains("ShortcutCatalog.browserLauncherChord(setting: Self.launcherShortcut)"))
    }

    func testBrowserLauncherMatchesRegisteredChordAndDoesNotConflictWithSnap() throws {
        let launcher = try entry("fileBrowser.open")
        XCTAssertEqual(launcher.chord.keyCode, 3)
        XCTAssertEqual(launcher.chord.modifiers, [.control, .option, .command])
        XCTAssertEqual(launcher.gateKey, "fileBrowser.globalHotkey")
        XCTAssertEqual(ShortcutCatalog.fixedEntries.filter { $0.gateKey == "fileBrowser.globalHotkey" }.count, 1)
        let snaps = Dictionary(uniqueKeysWithValues: ShortcutCatalog.fixedEntries.filter { $0.id.hasPrefix("snap.") }.map { ($0.id, $0.chord) })
        XCTAssertTrue(ShortcutCatalog.conflicts(for: launcher.chord, owner: launcher.id, recorded: snaps, isActive: { _ in true }).owners.isEmpty)
    }

    func testEverySnapChordInTheCatalogIsTheEnginesChordForThatTarget() throws {
        let text = try source("XFinder/Core/Snap/SnapLayout.swift")
        // `case 2:   target = .leftThird` → [2: "leftThird"]
        let rx = try NSRegularExpression(pattern: #"case\s+(\d+):\s*target\s*=\s*\.(\w+)"#)
        var engine: [UInt16: String] = [:]
        for m in rx.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let c = Range(m.range(at: 1), in: text), let n = Range(m.range(at: 2), in: text), let code = UInt16(text[c]) {
                engine[code] = String(text[n])
            }
        }
        XCTAssertGreaterThanOrEqual(engine.count, 8, "the engine parse found too few snap keys — the anchor rotted")
        let snaps = ShortcutCatalog.fixedEntries.filter { $0.id.hasPrefix("snap.") }
        XCTAssertEqual(snaps.count, engine.count, "every engine snap key needs exactly one catalog row, and back")
        for e in snaps {
            let target = String(e.id.dropFirst("snap.".count))
            XCTAssertEqual(engine[e.chord.keyCode], target,
                           "\(e.id): the catalog says key code \(e.chord.keyCode), the engine maps that code to \(engine[e.chord.keyCode] ?? "nothing")")
            XCTAssertEqual(e.chord.modifiers, [.control, .option], "\(e.id): the engine requires exactly ⌃⌥")
        }
    }

    func testTheClipboardChordsInTheCatalogAreTheEnginesComparisons() throws {
        let text = try source("XFinder/Core/ClipboardShelfController.swift")
        for id in ["clipboard.shelf", "clipboard.shelfAlt"] {
            let code = try entry(id).chord.keyCode
            XCTAssertTrue(text.contains("keyCode == \(code)"), "\(id): the catalog says key code \(code), the tap compares no such code")
        }
        XCTAssertNotEqual(try entry("clipboard.shelf").chord, try entry("clipboard.shelfAlt").chord)
    }

    func testTheQuitChordInTheCatalogIsQuitHoldsKey() throws {
        let controllerText = try source("XFinder/Core/QuitProtectionController.swift")
        XCTAssertTrue(controllerText.contains("QuitHold.keyCodeQ"),
                      "QuitProtectionController no longer compares against QuitHold.keyCodeQ")
        let holdText = try source("XFinder/Core/QuitHold.swift")
        let code = try entry("quit.hold").chord.keyCode
        XCTAssertTrue(holdText.contains("keyCodeQ = \(code)"), "the catalog's ⌘Q key code \(code) is not QuitHold.keyCodeQ")
        XCTAssertEqual(try entry("quit.hold").chord.modifiers, [.command])
    }

    func testFinderKeyboardRewritesStillWireTheirThreeKeys() throws {
        let text = try source("XFinder/Core/FinderKeyboardController.swift")
        for key in ["finderKeyboard.cutPaste", "finderKeyboard.deleteToTrash", "finderKeyboard.returnOpens"] {
            XCTAssertTrue(text.contains(key), "FinderKeyboardController no longer reads \(key)")
        }
    }

    func testTheLocalChordsInTheCatalogAreTheKeysTheAppMonitorMatches() throws {
        let text = try source("XFinder/App/XFinderApp.swift")
        // The local monitors switch on `charactersIgnoringModifiers`, so compare the catalog chord's own letter.
        for id in ["notes.new", "notes.library", "notes.pin", "clipboard.pasteStack"] {
            let e = try entry(id)
            let letter = ShortcutCatalog.Chord.keyName(for: e.chord.keyCode).lowercased()
            XCTAssertEqual(letter.count, 1, "\(id): a local chord must be a letter key")
            XCTAssertTrue(text.contains("\"\(letter)\""), "\(id): the catalog says '\(letter)', XFinderApp's monitor has no such case")
            XCTAssertEqual(e.scope, .whenXFinderFrontmost, "\(id) is a LOCAL monitor — it only fires while XFinder is in front")
        }
    }

    func testTranslateSelectionUsesTheSharedRulesKeyCode() throws {
        let text = try source("XFinder/Core/Translate/TranslateSelectionController.swift")
        XCTAssertTrue(text.contains("TranslateSelectionRules.keyCodeG"),
                      "TranslateSelectionController no longer uses the shared keyCodeG constant")
    }

    // MARK: - Every gate key default matches its reader source (same technique as FeatureKeyDefaultsTests)

    func testEveryFixedEntryGateDefaultMatchesItsReaderSource() throws {
        // Map of gate key -> (relative path to the ONE Core reader, expected literal substring).
        let readers: [String: (path: String, literal: String)] = [
            "clipboard.globalHotkey": ("XFinder/Core/ClipboardShelfController.swift", "true"),
            "clipboard.shelfHotkey": ("XFinder/Core/ClipboardShelfController.swift", "false"),
            TranslateSelectionRules.enabledKey: ("XFinder/Core/Translate/TranslateSelectionController.swift", "false"),
            "snapzones.hotkeysEnabled": ("XFinder/Core/SnapZoneController.swift", "true"),
            "quitProtection.enabled": ("XFinder/Core/QuitProtectionController.swift", "false"),
            "windowPreview.commandTabEnabled": ("XFinder/Core/CommandTabController.swift", "false"),
            "finderKeyboard.cutPaste": ("XFinder/Core/FinderKeyboardController.swift", "false"),
            "finderKeyboard.deleteToTrash": ("XFinder/Core/FinderKeyboardController.swift", "false"),
            "finderKeyboard.returnOpens": ("XFinder/Core/FinderKeyboardController.swift", "false"),
            "notes.globalHotkey": ("XFinder/Core/EdgeNotesController.swift", "false"),     // XF-T24
            "fileBrowser.downloadsHotkey": ("XFinder/Core/Browser/BrowserSettings.swift", "false"),
            "fileBrowser.globalHotkey": ("XFinder/Core/Browser/BrowserSettings.swift", "false"),   // XF-T28
        ]
        var checked = 0
        for entry in ShortcutCatalog.fixedEntries {
            guard let gateKey = entry.gateKey, let gateDefault = entry.gateDefault else { continue }
            guard let (path, literal) = readers[gateKey] else {
                XCTFail("\(entry.id): no reader registered in this test for gate key \(gateKey)")
                continue
            }
            let text = try source(path)
            let pattern = #"object\(forKey:\s*""# + NSRegularExpression.escapedPattern(for: gateKey)
                + #""\s*\)\s*as\?\s*Bool\s*\?\?\s*(true|false)"#
            let regex = try XCTUnwrap(try? NSRegularExpression(pattern: pattern))
            let range = NSRange(text.startIndex..., in: text)
            let found = regex.matches(in: text, range: range).compactMap { m -> String? in
                guard let r = Range(m.range(at: 1), in: text) else { return nil }
                return String(text[r])
            }
            XCTAssertFalse(found.isEmpty, "\(entry.id): gate key \(gateKey) has no `object(forKey:) as? Bool ?? <lit>` reader in \(path)")
            for readerDefault in found {
                XCTAssertEqual(readerDefault, literal, "\(entry.id): reader default for \(gateKey) is \(readerDefault), expected \(literal)")
            }
            XCTAssertEqual(gateDefault ? "true" : "false", literal,
                            "\(entry.id): catalog's own gateDefault disagrees with the expected reader literal for \(gateKey)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 5, "a gate that checked nothing must fail, not pass silently")
    }

    // P3 integration — the ⌘K recorder stores NSEvent.ModifierFlags raw bits; it used to sit outside the clash check.
    func testNSEventFlagBitsDecodeToTheCatalogModifiers() {
        // AppKit's published device-independent values: shift 1<<17, control 1<<18, option 1<<19, command 1<<20.
        XCTAssertEqual(ShortcutCatalog.Modifiers(nsEventRaw: 1 << 20), [.command])
        XCTAssertEqual(ShortcutCatalog.Modifiers(nsEventRaw: (1 << 20) | (1 << 17)), [.command, .shift])
        XCTAssertEqual(ShortcutCatalog.Modifiers(nsEventRaw: (1 << 18) | (1 << 19)), [.control, .option])
        // Caps Lock (1<<16) and the numeric-pad/function bits are not chord modifiers.
        XCTAssertEqual(ShortcutCatalog.Modifiers(nsEventRaw: (1 << 16) | (1 << 21) | (1 << 23) | (1 << 20)), [.command])
    }

    func testThePaletteChordClashesWithACaptureShortcutOnTheSameKeys() {
        let cmdK = ShortcutCatalog.Chord(keyCode: 40, modifiers: ShortcutCatalog.Modifiers(nsEventRaw: 1 << 20))
        let recorded = ["quickSearch.palette": cmdK, "capture.area": cmdK]
        let fromPalette = ShortcutCatalog.conflicts(for: cmdK, owner: "quickSearch.palette", recorded: recorded) { _ in true }
        XCTAssertEqual(fromPalette.owners, ["capture.area"])
        let fromCapture = ShortcutCatalog.conflicts(for: cmdK, owner: "capture.area", recorded: recorded) { _ in true }
        XCTAssertEqual(fromCapture.owners, ["quickSearch.palette"])
    }

    func testTheSwitcherChordFollowsTheUsersHotkeySetting() throws {
        let e = try entry("switcher.commandTab")
        XCTAssertEqual(ShortcutCatalog.liveChord(of: e, switcherSetting: "commandTab").label, "⌘Tab")
        XCTAssertEqual(ShortcutCatalog.liveChord(of: e, switcherSetting: "optionTab").label, "⌥Tab")
        XCTAssertEqual(ShortcutCatalog.liveChord(of: e, switcherSetting: "anything else").label, "⌘Tab", "the reader's default")
        let snap = try entry("snap.leftThird")
        XCTAssertEqual(ShortcutCatalog.liveChord(of: snap, switcherSetting: "optionTab"), snap.chord, "only the switcher varies")
        let src = try source("XFinder/Core/CommandTabController.swift")
        XCTAssertTrue(src.contains("\"optionTab\""), "CommandTabController no longer knows the optionTab value this follows")
    }
}
