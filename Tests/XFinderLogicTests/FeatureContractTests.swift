import XCTest
import Foundation

/// The feature-module contract (REDESIGN_PLAN §2.1) as a gate: every feature in `FeatureCatalog`
/// must put its rules in pure, Foundation-only code that this package compiles and tests — or carry
/// an explicit, written exemption.
///
/// Why a declared table instead of a naming convention: measured on 2026-10-10, the convention the
/// plan proposed (`Core/<Feature>/<Feature>Model.swift`) matched 2 of 14 features, and the mapping
/// cannot be inferred from names (hold-to-quit's rules live in `QuitHold.swift`, Alerts' in
/// `AlertRules.swift`). A name-guessing gate would be red for no reason or green over nothing.
/// So the mapping is data, and every row is checked against the tree.
///
/// What fails: a catalog feature missing from the table (a new feature cannot slip in untested), a
/// stale row, a listed file that is missing, not symlinked into this package, importing SwiftUI, or
/// never mentioned by any test; an exemption with no reason or no named fix; a new exemption.
final class FeatureContractTests: XCTestCase {

    enum Contract {
        /// Pure files (paths under `XFinder/`) that hold the feature's rules.
        case pure([String])
        /// No symlinked pure model yet — the reason must say why, and what would fix it.
        case exempt(String)
    }

    static let contract: [FeatureID: Contract] = [
        .dropTray: .pure(["Core/Notch/NotchSurfaceMachine.swift", "Core/Notch/NotchSurfaceLayout.swift",
                          "Core/Notch/NotchDragSession.swift"]),
        .nowPlaying: .pure(["Core/Notch/NowPlaying.swift"]),
        .agents: .pure(["Core/Agents/AgentEvents.swift", "Core/Agents/AgentHookInstaller.swift", "Core/Agents/AgentUsage.swift", "Core/Agents/CrewGate.swift"]),
        .calendar: .pure(["Core/Calendar/GlanceRules.swift"]),
        .translateSelection: .pure(["Core/Translate/TranslateSelectionRules.swift"]),
        .quitOnClose: .pure(["Core/QuitOnClose/QuitOnCloseRules.swift"]),
        .capture: .pure(["Core/Capture/CaptureRules.swift", "Core/Capture/Annotation.swift", "Core/Capture/ScrollStitch.swift"]),
        .smartSelect: .pure(["Core/SmartSelect/SmartSelectionRules.swift", "Core/SmartSelect/UnitConversion.swift",
                             "Core/SmartSelect/TimeZoneConversion.swift", "Core/SmartSelect/CurrencyConversion.swift"]),
        .linkPreviews: .pure(["Core/Clipboard/LinkPreviewRules.swift"]),
        .quitProtection: .pure(["Core/QuitHold.swift"]),
        .cleanURLs: .pure(["Core/URLCleaner.swift"]),
        .alerts: .pure(["Core/AlertRules.swift"]),
        .menuBarReadouts: .pure(["Core/MenuBarReadouts.swift"]),
        .systemHUD: .pure(["Core/Notch/LiveActivity.swift"]),   // LiveActivity.HUDSuppression decides every key
        .voice: .pure(["Core/Voice/VoiceRefiner.swift", "Core/Voice/VoiceTrigger.swift",
                       "Core/Voice/DictationMode.swift", "Core/Voice/VoiceSettingsKeys.swift"]),
        .dockPreview: .pure(["Core/WindowPreview/WindowPreviewStore.swift", "Core/WindowPreview/PreviewItem.swift"]),
        .commandTab: .pure(["Core/WindowPreview/WindowPreviewStore.swift"]),

        .snapZones: .pure(["Core/Snap/SnapLayout.swift"]),
        .snapMemory: .pure(["Core/Snap/SnapMemory.swift"]),
        .smoothScroll: .pure(["Core/SmoothScroll/SmoothScrollRules.swift"]),
        .fileBrowser: .pure(["Core/Browser/PaneTree.swift", "Core/Browser/PaneHistory.swift", "Core/Browser/BrowserPath.swift",
                             "Core/Browser/DirectoryEntry.swift", "Core/Browser/SearchQuery.swift",
                             "Core/Browser/FileOperationRules.swift", "Core/Browser/BrowserCommands.swift",
                             "Core/Browser/CloudBadge.swift", "Core/Browser/BrowserWorkspace.swift",
                             "Core/Browser/SidebarLayout.swift", "Core/Browser/FileInfoRules.swift",
                             "Core/Browser/PaneTabs.swift", "Core/Browser/GroupBy.swift", "Core/Browser/NameMatcher.swift",
                             "Core/Browser/SearchIndexRules.swift", "Core/Browser/SavedSearch.swift"]),
        .clipboardShelf: .exempt("Classification and the privacy filter are tested through duplicated copies (ClipboardClassifierTests). Fix: extract them from ClipboardManager into a symlinked file."),
        .suggestions: .exempt("ClipboardIntelligenceEngine's ranking lives inside ClipboardPasteEngine.swift with AppKit imports. Fix: extract the scoring into a pure file."),
        .quickSearch: .exempt("Calculator / quicklink matching live in Core/QuickSearch beside AppKit code and are untested. Fix: symlink the calculator and fuzzy matcher."),
        .edgeNotes: .pure(["Core/EdgeNotesLayout.swift", "Core/NoteBackup.swift"]),   // XF-T24 paid this exemption down
        .quickShare: .pure(["Core/ConnectRules.swift"]),      // XF-T21
        .remoteConnect: .pure(["Core/ConnectRules.swift"]),
        .folderSync: .exempt("The source==dest / nested-destination guards live in FolderSyncController. Fix: extract the guards and the schedule into a pure file — they protect user data."),
    ]

    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var testsDir: URL { repoRoot.appendingPathComponent("Tests/XFinderLogicTests") }

    /// Real paths of every source symlinked into this package.
    static func symlinkedTargets() -> Set<String> {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: testsDir.path)) ?? []
        return Set(names.compactMap { name -> String? in
            let p = testsDir.appendingPathComponent(name).path
            guard (try? fm.destinationOfSymbolicLink(atPath: p)) != nil else { return nil }
            return URL(fileURLWithPath: p).resolvingSymlinksInPath().path
        })
    }

    static func testSources() -> String {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: testsDir.path)) ?? []
        return names.filter { $0.hasSuffix("Tests.swift") }
            .compactMap { try? String(contentsOf: testsDir.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }

    /// Top-level type names declared in a source file (`enum X`, `struct X`, `final class X`, …).
    static func declaredTypes(in source: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"(?m)^(?:public |internal |final |@\w+ )*(?:enum|struct|class|actor|protocol) ([A-Z]\w+)"#)
        let ns = source as NSString
        return re.matches(in: source, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    func testEveryCatalogFeatureHasAContractRow() {
        let catalog = Set(FeatureCatalog.all.map(\.id))
        XCTAssertGreaterThanOrEqual(catalog.count, 14, "the catalog collapsed — the gate would be checking nothing")
        for id in catalog where Self.contract[id] == nil {
            XCTFail("\(id) is in FeatureCatalog but not in FeatureContractTests.contract — declare its pure model or an exemption")
        }
        for id in Self.contract.keys where !catalog.contains(id) {
            XCTFail("stale contract row: \(id) is no longer a catalog feature")
        }
    }

    func testEveryDeclaredPureFileIsRealSymlinkedFrameworkFreeAndTested() {
        let links = Self.symlinkedTargets()
        let tests = Self.testSources()
        XCTAssertGreaterThan(links.count, 20, "found almost no symlinks — the directory scan is broken")
        var checked = 0
        for (id, c) in Self.contract {
            guard case .pure(let files) = c else { continue }
            XCTAssertFalse(files.isEmpty, "\(id): a pure contract must list at least one file")
            for rel in files {
                let url = Self.repoRoot.appendingPathComponent("XFinder").appendingPathComponent(rel)
                guard let src = try? String(contentsOf: url, encoding: .utf8) else {
                    XCTFail("\(id): \(rel) does not exist"); continue
                }
                checked += 1
                XCTAssertTrue(links.contains(url.resolvingSymlinksInPath().path),
                              "\(id): \(rel) is not symlinked into Tests/XFinderLogicTests, so no test compiles it")
                // AppKit / IOKit imports are allowed ON PURPOSE: measured, 12 symlinked files import them and
                // this macOS package compiles them fine. The package's real limit is that it cannot link the app
                // target or exercise anything needing a running app or a permission. A rules file importing
                // SwiftUI, however, means view code moved into the model — that stays a failure.
                XCTAssertFalse(src.contains("import SwiftUI"), "\(id): \(rel) imports SwiftUI — view code does not belong in a rules file")
                let types = Self.declaredTypes(in: src)
                XCTAssertFalse(types.isEmpty, "\(id): \(rel) declares no type the parser can see")
                XCTAssertTrue(types.contains { tests.contains($0) },
                              "\(id): no test mentions any type declared in \(rel) (\(types.prefix(4)))")
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 10, "the gate checked almost no files")
    }

    func testEveryExemptionSaysWhyAndWhatWouldFixIt() {
        var exempt = 0
        for (id, c) in Self.contract {
            guard case .exempt(let reason) = c else { continue }
            exempt += 1
            XCTAssertGreaterThan(reason.count, 40, "\(id): an exemption needs a real reason")
            XCTAssertTrue(reason.contains("Fix:"), "\(id): an exemption must name the fix, so it can be paid down")
        }
        // Exemptions may only shrink. Raise this number only with a reason in the commit message.
        XCTAssertLessThanOrEqual(exempt, 4, "a new exemption was added — a new feature must ship with a pure, tested model")
    }
}
