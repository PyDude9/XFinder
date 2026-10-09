import XCTest
import Foundation

final class FeatureCatalogTests: XCTestCase {

    private let allOn = Set(FeatureID.allCases)

    // MARK: - Catalogue shape

    func testEveryFeatureIDHasExactlyOneDefinition() {
        XCTAssertEqual(FeatureCatalog.all.count, FeatureID.allCases.count)
        XCTAssertEqual(Set(FeatureCatalog.all.map(\.id)).count, FeatureCatalog.all.count, "duplicate id")
        for id in FeatureID.allCases { XCTAssertEqual(FeatureCatalog.all.filter { $0.id == id }.count, 1, "\(id)") }
    }

    /// Part 0 #4 as a test: one key, one feature. Two features on one key would flip together.
    func testNoTwoFeaturesShareAnEnabledKey() {
        let keys = FeatureCatalog.all.map(\.enabledKey)
        XCTAssertEqual(Set(keys).count, keys.count, "two features share a key: \(keys)")
        XCTAssertFalse(keys.contains(where: \.isEmpty))
    }

    func testEveryFeatureHasTextAndAnExistingSymbol() {
        for f in FeatureCatalog.all {
            XCTAssertFalse(f.titleKey.isEmpty); XCTAssertFalse(f.subtitleKey.isEmpty)
            XCTAssertTrue(FeatureGroup.allCases.contains(f.group))
        }
        XCTAssertGreaterThanOrEqual(FeatureCatalog.all.count, 12, "the catalogue collapsed")
    }

    // MARK: - The catalogue tells the truth about the engines (source-level, like FeatureKeyDefaultsTests)

    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func allCoreSources() -> [(String, String)] {
        var out: [(String, String)] = []
        for dir in ["XFinder/Core", "XFinder/App"] {
            let root = Self.repoRoot.appendingPathComponent(dir)
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e where url.pathExtension == "swift" {
                if let t = try? String(contentsOf: url, encoding: .utf8) { out.append((url.lastPathComponent, t)) }
            }
        }
        return out
    }

    /// For every feature: the engine must read ITS key in the canonical form, and every such read
    /// must default to the catalogue's `defaultOn`. A catalogue that says "on by default" while the
    /// engine says "off" would flip the feature for everyone who never touched it (Part 0 #5).
    func testCatalogueDefaultsAgreeWithTheEnginesThatReadTheKeys() {
        let sources = allCoreSources()
        XCTAssertFalse(sources.isEmpty, "could not read the Core sources")
        for f in FeatureCatalog.all {
            // The key may be read as a literal OR through a named constant (`static let enabled = "voice.enabled"`).
            var names = [NSRegularExpression.escapedPattern(for: "\"" + f.enabledKey + "\"")]
            let constRE = try! NSRegularExpression(pattern: #"static\s+let\s+(\w+)\s*=\s*""# + NSRegularExpression.escapedPattern(for: f.enabledKey) + #"""#)
            for (_, text) in sources {
                for m in constRE.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let r = Range(m.range(at: 1), in: text) { names.append(#"(?:\w+\.)*"# + String(text[r])) }
                }
            }
            var found: [(String, String)] = []
            for n in names {
                let re = try! NSRegularExpression(pattern: #"object\(forKey:\s*"# + n + #"\s*\)\s*as\?\s*Bool\s*\?\?\s*(true|false)\b"#)
                for (file, text) in sources {
                    for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                        if let r = Range(m.range(at: 1), in: text) { found.append((file, String(text[r]))) }
                    }
                }
            }
            XCTAssertFalse(found.isEmpty, "\(f.enabledKey): no engine reads this key in the canonical form — the hub would switch nothing")
            for (file, value) in found {
                XCTAssertEqual(value, f.defaultOn ? "true" : "false",
                               "\(f.enabledKey): \(file) reads default \(value), catalogue says \(f.defaultOn)")
            }
        }
    }

    // MARK: - Permissions

    func testAFeatureThatNeedsAPermissionListsIt() {
        XCTAssertTrue(FeatureCatalog.def(.voice).permissions.contains(.microphone))
        XCTAssertTrue(FeatureCatalog.def(.quitProtection).permissions == [.accessibility])
        XCTAssertTrue(FeatureCatalog.def(.cleanURLs).permissions.isEmpty)
    }

    func testPermissionRowsCountOnlyFeaturesThatAreOn() {
        let on: Set<FeatureID> = [.quitProtection]
        let rows = FeatureCatalog.permissionRows(enabled: on, granted: [.accessibility: true])
        let ax = rows.first { $0.permission == .accessibility }!
        XCTAssertEqual(ax.activeUsers, 1)
        XCTAssertTrue(ax.usedBy.count > 1, "usedBy lists every feature that CAN use it, not only the active ones")
        XCTAssertFalse(ax.isUnneeded)
        let mic = rows.first { $0.permission == .microphone }!
        XCTAssertEqual(mic.activeUsers, 0)
    }

    /// The Vorssaint-style warning: "you granted this, but nothing that is on needs it".
    func testAGrantedPermissionNothingActiveNeedsIsFlaggedUnneeded() {
        let rows = FeatureCatalog.permissionRows(enabled: [], granted: [.accessibility: true, .microphone: true])
        XCTAssertTrue(rows.first { $0.permission == .accessibility }!.isUnneeded)
        XCTAssertTrue(rows.first { $0.permission == .microphone }!.isUnneeded)
        XCTAssertFalse(rows.first { $0.permission == .screenRecording }!.isUnneeded, "not granted ⇒ nothing to revoke")
    }

    func testAnActiveFeatureMissingItsPermissionIsFlagged() {
        let rows = FeatureCatalog.permissionRows(enabled: [.voice], granted: [.accessibility: true])
        XCTAssertTrue(rows.first { $0.permission == .microphone }!.isMissingForActive)
        XCTAssertFalse(rows.first { $0.permission == .accessibility }!.isMissingForActive)
        let blocked = FeatureCatalog.blocked(enabled: [.voice], granted: [.accessibility: true])
        XCTAssertEqual(blocked.count, 1)
        XCTAssertEqual(Set(blocked[0].1), [.microphone, .speechRecognition])
        XCTAssertTrue(FeatureCatalog.blocked(enabled: [.cleanURLs], granted: [:]).isEmpty, "a feature needing nothing is never blocked")
        XCTAssertTrue(FeatureCatalog.blocked(enabled: [], granted: [:]).isEmpty, "switched-off features are never blocked")
    }

    func testEveryPermissionHasTextASymbolAndAPaneLink() {
        for p in AppPermission.allCases {
            XCTAssertFalse(p.titleKey.isEmpty); XCTAssertFalse(p.purposeKey.isEmpty)
            XCTAssertTrue(p.settingsURL.hasPrefix("x-apple.systempreferences:com.apple.preference.security?Privacy_"))
            XCTAssertNotNil(URL(string: p.settingsURL))
        }
        XCTAssertEqual(Set(AppPermission.allCases.map(\.settingsURL)).count, AppPermission.allCases.count)
    }

    // MARK: - Bundles

    func testApplyingABundleTurnsItsFeaturesOnAndLeavesTheRestAlone() {
        let start: [FeatureID: Bool] = [.cleanURLs: false, .edgeNotes: true, .dockPreview: false]
        let windows = FeatureCatalog.bundles.first { $0.id == "windows" }!
        let after = FeatureCatalog.apply(windows, to: start)
        XCTAssertEqual(after[.dockPreview], true)
        XCTAssertEqual(after[.quitProtection], true)
        XCTAssertEqual(after[.edgeNotes], true, "not in the bundle ⇒ untouched")
        XCTAssertEqual(after[.cleanURLs], false)
    }

    /// "Quiet" is derived from the catalogue: it must switch off EXACTLY the features that keep
    /// something running, so none that listens to input or runs a timer can survive it.
    func testQuietBundleSwitchesOffEverythingThatRunsInTheBackground() {
        let quiet = FeatureCatalog.bundles.first { $0.id == "quiet" }!
        let after = FeatureCatalog.apply(quiet, to: Dictionary(uniqueKeysWithValues: FeatureID.allCases.map { ($0, true) }))
        for f in FeatureCatalog.all {
            if f.idle.isBackgroundActive {
                XCTAssertEqual(after[f.id], false, "\(f.id) listens/ticks but survived the quiet bundle")
            } else {
                XCTAssertEqual(after[f.id], true, "\(f.id) is idle and must be left as it was")
            }
        }
        XCTAssertGreaterThan(quiet.turnOff.count, 5)
    }

    func testBundlesOnlyReferenceRealFeaturesAndNeverContradictThemselves() {
        for b in FeatureCatalog.bundles {
            XCTAssertTrue(Set(b.turnOn).isDisjoint(with: Set(b.turnOff)), "\(b.id) turns the same feature both on and off")
            XCTAssertFalse(b.titleKey.isEmpty); XCTAssertFalse(b.descriptionKey.isEmpty)
        }
        XCTAssertEqual(FeatureCatalog.bundles.count, 3)
    }

    // MARK: - Idle badges must be honest

    func testNothingWithAPollingTimerIsLabelledNothingAtRest() {
        XCTAssertEqual(FeatureCatalog.def(.folderSync).idle, .timerWhileActive)
        XCTAssertEqual(IdleCost.nothingAtRest.badgeKey, "Không chạy nền")
        XCTAssertFalse(IdleCost.nothingAtRest.isBackgroundActive)
        for c: IdleCost in [.listensToKeyboard, .listensToMouse, .timerWhileActive] {
            XCTAssertTrue(c.isBackgroundActive)
            XCTAssertFalse(c.badgeKey.isEmpty)
        }
        // Anything whose engine installs an event tap or monitor must NOT claim to be idle.
        for id in [FeatureID.dockPreview, .commandTab, .snapZones, .quitProtection, .clipboardShelf, .voice] {
            XCTAssertTrue(FeatureCatalog.def(id).idle.isBackgroundActive, "\(id) installs a tap/monitor")
        }
    }

    // MARK: - Every string the hub can show resolves in the shipped store

    /// These reach the screen through `L10n.t(variable)`, which no literal sweep can see — the same
    /// shape as the SMART and gesture leaks. Walk the whole vocabulary against the real store.
    func testEveryCatalogueStringIsTranslated() throws {
        let store = try L10nFixture.load()
        var keys: [String] = []
        for f in FeatureCatalog.all { keys += [f.titleKey, f.subtitleKey] }
        for g in FeatureGroup.allCases { keys.append(g.titleKey) }
        for p in AppPermission.allCases { keys += [p.titleKey, p.purposeKey] }
        for c: IdleCost in [.nothingAtRest, .listensToKeyboard, .listensToMouse, .timerWhileActive] { keys.append(c.badgeKey) }
        for b in FeatureCatalog.bundles { keys += [b.titleKey, b.descriptionKey] }
        XCTAssertGreaterThanOrEqual(Set(keys).count, 40, "the vocabulary walk collapsed")
        let sameByDesign = try L10nFixture.allowlist()
        for k in Set(keys) {
            guard let entry = store.entries[k] else { XCTFail("not in L10n.strings.json: \(k)"); continue }
            XCTAssertFalse(entry.en.isEmpty, k)
            if !sameByDesign.contains(k) { XCTAssertNotEqual(entry.en, k, "'\(k)' is 'translated' to itself") }
        }
    }
}
