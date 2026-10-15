import XCTest

/// Eight presets were keyed by bundle ids that no installed app has (measured 2026-10-15 with `mdfind` on the owner's Mac),
/// so Claude, VS Code, Cursor, Antigravity, CapCut, AyuGram, Obsidian and Notion silently used the Global table.
final class GestureBundleIDTests: XCTestCase {
    private let ids = Set(GestureProfiles.all.map(\.id))

    func testNoPresetUsesAnOldWrongBundleID() {
        XCTAssertEqual(GestureProfiles.renamedBundleIDs.count, 8, "the measured list — do not let it shrink silently")
        for (old, new) in GestureProfiles.renamedBundleIDs {
            XCTAssertFalse(ids.contains(old), "\(old) is the id that never matched an installed app")
            XCTAssertTrue(ids.contains(new), "\(new) must be a preset id")
        }
    }

    func testThePresetsCarryTheMeasuredIDs() {
        for id in ["com.anthropic.claudefordesktop", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                   "com.google.antigravity", "com.lemon.lvoverseas", "one.ayugram.AyuGramDesktop", "md.obsidian", "notion.id"] {
            XCTAssertTrue(GestureProfiles.hasPreset(bundle: id), id)
        }
    }

    func testAnOverrideSavedUnderAnOldIDMovesToTheRealID() {
        var config = GestureConfiguration()
        let mine = GestureAction.shortcut(GestureShortcut(key: 36, flags: GestureShortcut.command))
        config.overrides["com.visualstudio.code", default: [:]][.up] = mine
        config.validate()
        XCTAssertNil(config.overrides["com.visualstudio.code"], "the dead key is gone")
        XCTAssertEqual(config.overrides["com.microsoft.VSCode"]?[.up], mine)
        XCTAssertEqual(config.action(bundle: "com.microsoft.VSCode", direction: .up), mine,
                       "and it is what the resolver now sends for the real VS Code")
    }

    func testRowsAlreadyUnderTheRealIDWinAndOldOnesOnlyFillGaps() {
        var config = GestureConfiguration()
        let current = GestureAction.unassigned
        let stale = GestureAction.shortcut(GestureShortcut(key: 36, flags: GestureShortcut.command))
        let onlyOld = GestureAction.shortcut(GestureShortcut(key: 3, flags: GestureShortcut.command))
        config.overrides["notion.id", default: [:]][.up] = current
        config.overrides["com.notion.Notion-App", default: [:]][.up] = stale
        config.overrides["com.notion.Notion-App", default: [:]][.down] = onlyOld
        config.validate()
        XCTAssertEqual(config.overrides["notion.id"]?[.up], current)
        XCTAssertEqual(config.overrides["notion.id"]?[.down], onlyOld)
        XCTAssertNil(config.overrides["com.notion.Notion-App"])
        let once = config.overrides
        config.validate()
        XCTAssertEqual(config.overrides, once, "validate() is idempotent")
    }
}
