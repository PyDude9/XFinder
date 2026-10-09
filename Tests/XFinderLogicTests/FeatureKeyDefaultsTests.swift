import XCTest
import Foundation

/// Part 0 §5 as a gate: a feature key's `@AppStorage` default in the view must equal the
/// default its engine reads with. When they differ, every user who never touched the switch
/// has the feature silently flipped — and the build stays green, which is why a test reads
/// the *source* of both sides (the SwiftUI views are not compilable in this package, and
/// `UserDefaults` at test time would only show the default of whichever side ran first).
///
/// The parse is deliberately narrow and must FAIL on zero matches: a key that resolves to
/// no declaration means the anchor rotted, and "found nothing" must never read as green.
final class FeatureKeyDefaultsTests: XCTestCase {

    /// One feature switch: the key, the view files that bind it, the ONE Core file that reads it.
    struct Switch {
        let key: String
        let views: [String]
        let reader: String
    }

    /// Every boolean switch whose reader is written in the canonical form
    /// `UserDefaults.standard.object(forKey: "<key>") as? Bool ?? <literal>`.
    /// Keys bound in more than one view are listed with every view on purpose — until a
    /// registry owns the default, all copies must agree.
    static let switches: [Switch] = [
        Switch(key: "windowPreview.showHiddenWindows",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift"],
               reader: "XFinder/Core/WindowPreview/WindowPreviewStore.swift"),
        Switch(key: "clipboard.intelligentSuggestions",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardPasteEngine.swift"),
        Switch(key: "windowPreview.hoverEnabled",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift",
                       "XFinder/Views/Detail/DashboardDetailView.swift"],
               reader: "XFinder/Core/DockPreviewController.swift"),
        Switch(key: "windowPreview.commandTabEnabled",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift"],
               reader: "XFinder/Core/CommandTabController.swift"),
        Switch(key: "clipboard.globalHotkey",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardShelfController.swift"),
        Switch(key: "notes.edgeEnabled",
               views: ["XFinder/Views/Detail/NotesDetailView.swift"],
               reader: "XFinder/Core/EdgeNotesController.swift"),
        Switch(key: "clipboard.cleanURLs",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardManager.swift"),
        Switch(key: "clipboard.autoClearSeconds",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardManager.swift"),
        Switch(key: "quitProtection.enabled",
               views: [],   // bound only through FeatureHub now (the old page was merged away)
               reader: "XFinder/Core/QuitProtectionController.swift"),
    ]

    // MARK: - Source access

    /// `Tests/XFinderLogicTests/<this file>` → repo root.
    static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // XFinderLogicTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo
    }()

    static func source(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) -> String? {
        let url = repoRoot.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("cannot read \(relativePath) from \(repoRoot.path)", file: file, line: line)
            return nil
        }
        return text
    }

    /// All `@AppStorage("<key>") … = <literal>` defaults declared in one view file. The literal is
    /// `true`/`false` or an integer, kept as text so Bool and Int keys share one gate.
    static func viewDefaults(forKey key: String, in text: String) -> [String] {
        let pattern = #"@AppStorage\(\s*""# + NSRegularExpression.escapedPattern(for: key)
            + #""\s*\)[^=\n]*=\s*(true|false|-?\d+)\b"#
        return matches(pattern, in: text)
    }

    /// All `object(forKey: "<key>") as? Bool|Int ?? <literal>` reads in one Core file.
    static func readerDefaults(forKey key: String, in text: String) -> [String] {
        let pattern = #"object\(forKey:\s*""# + NSRegularExpression.escapedPattern(for: key)
            + #""\s*\)\s*as\?\s*(?:Bool|Int)\s*\?\?\s*(true|false|-?\d+)\b"#
        return matches(pattern, in: text)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { m in
            guard let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    // MARK: - The gate

    func testEverySwitchHasExactlyOneReaderAndEveryViewDefaultAgreesWithIt() {
        for sw in Self.switches {
            guard let readerText = Self.source(sw.reader) else { continue }
            let readerDefaults = Self.readerDefaults(forKey: sw.key, in: readerText)
            XCTAssertEqual(readerDefaults.count, 1,
                           "\(sw.key): expected exactly ONE canonical reader in \(sw.reader), found \(readerDefaults.count) — "
                           + "zero means the anchor rotted or the key is dead; more than one means two readers that can drift")
            guard let readerDefault = readerDefaults.first else { continue }

            for view in sw.views {
                guard let viewText = Self.source(view) else { continue }
                let viewDefaults = Self.viewDefaults(forKey: sw.key, in: viewText)
                XCTAssertFalse(viewDefaults.isEmpty,
                               "\(sw.key): no @AppStorage declaration found in \(view) — the table is stale")
                for v in viewDefaults {
                    XCTAssertEqual(v, readerDefault,
                                   "\(sw.key): view default \(v) in \(view) disagrees with reader default \(readerDefault) in \(sw.reader) (Part 0 §5)")
                }
            }
        }
    }

    /// The gate itself must not pass on an empty table or a rotted anchor.
    func testGateParsesRealDeclarationsNotNothing() {
        XCTAssertGreaterThanOrEqual(Self.switches.count, 9, "the switch table collapsed")

        let fixtureView = """
        struct V: View {
            @AppStorage("a.b") private var ab = true
            @AppStorage("a.b")  var again = false
        }
        """
        XCTAssertEqual(Self.viewDefaults(forKey: "a.b", in: fixtureView), ["true", "false"])
        XCTAssertEqual(Self.viewDefaults(forKey: "a.c", in: fixtureView), [])

        let fixtureReader = """
        var on: Bool { UserDefaults.standard.object(forKey: "a.b") as? Bool ?? false }
        let other = UserDefaults.standard.object(forKey: "a.b") as? Double ?? 3
        """
        XCTAssertEqual(Self.readerDefaults(forKey: "a.b", in: fixtureReader), ["false"],
                       "a read of a different type (Double here) is not a switch reader")

        // Integer-valued settings (seconds, counts) go through the same gate.
        let intView = "@AppStorage(\"n.k\") private var k = 30\n@AppStorage(\"n.neg\") private var neg = -1"
        XCTAssertEqual(Self.viewDefaults(forKey: "n.k", in: intView), ["30"])
        XCTAssertEqual(Self.viewDefaults(forKey: "n.neg", in: intView), ["-1"])
        let intReader = "let k = UserDefaults.standard.object(forKey: \"n.k\") as? Int ?? 30"
        XCTAssertEqual(Self.readerDefaults(forKey: "n.k", in: intReader), ["30"])
    }

    // MARK: - Dead switches stay dead

    /// `clipboard.linkPreviews` had a toggle and no reader; it was removed rather than wired
    /// (fetching every copied URL would also break the local-only promise). This pins the removal.
    func testRemovedLinkPreviewsKeyIsBoundNowhere() {
        let dirs = ["XFinder/Views", "XFinder/Core", "XFinder/App"]
        var hits: [String] = []
        for dir in dirs {
            let root = Self.repoRoot.appendingPathComponent(dir)
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e where url.pathExtension == "swift" {
                if let t = try? String(contentsOf: url, encoding: .utf8), t.contains("\"clipboard.linkPreviews\"") {
                    hits.append(url.lastPathComponent)
                }
            }
        }
        XCTAssertEqual(hits, [], "clipboard.linkPreviews is back without a reader: \(hits)")
    }
}
