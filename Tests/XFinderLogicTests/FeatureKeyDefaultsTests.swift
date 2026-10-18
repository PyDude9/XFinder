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
        // §3b #21 — waveform
        Switch(key: "notch.nowPlaying.waveform", views: ["XFinder/Views/Detail/MediaDetailView.swift"], reader: "XFinder/Core/Notch/AudioTapMonitor.swift"),
        // §3b #33 — meeting alerts
        Switch(key: "notch.calendar.alerts", views: ["XFinder/Views/Detail/CalendarSettingsDetailView.swift"], reader: "XFinder/Core/Calendar/CalendarGlanceMonitor.swift"),
        Switch(key: "notch.calendar.alertLead", views: ["XFinder/Views/Detail/CalendarSettingsDetailView.swift"], reader: "XFinder/Core/Calendar/CalendarGlanceMonitor.swift"),
        Switch(key: "notch.calendar.alertSound", views: ["XFinder/Views/Detail/CalendarSettingsDetailView.swift"], reader: "XFinder/Core/Calendar/CalendarGlanceMonitor.swift"),
        // F4 — Chụp & chú thích
        Switch(key: "capture.enabled", views: ["XFinder/Views/Detail/CaptureDetailView.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.after", views: ["XFinder/Views/Detail/CaptureDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.cardSeconds", views: ["XFinder/Views/Detail/CaptureDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.cardEdge", views: ["XFinder/Views/Detail/CaptureDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.pauseOnHover", views: ["XFinder/Views/Detail/CaptureDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.swipeDismiss", views: ["XFinder/Views/Detail/CaptureDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.sound", views: ["XFinder/Views/Detail/CaptureDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.format", views: ["XFinder/Views/Detail/CaptureDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.keepHistory", views: ["XFinder/Views/Detail/CaptureDetailView.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.annotate.color", views: ["XFinder/Views/Detail/CaptureDetailView.swift", "XFinder/Views/Capture/AnnotateWindow.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
        Switch(key: "capture.annotate.width", views: ["XFinder/Views/Detail/CaptureDetailView.swift", "XFinder/Views/Capture/AnnotateWindow.swift"], reader: "XFinder/Core/Capture/CaptureController.swift"),
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
        Switch(key: "windowPreview.currentScreenOnly",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift"],
               reader: "XFinder/Core/WindowPreview/WindowPreviewStore.swift"),
        Switch(key: "windowPreview.commandTabEnabled",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/CommandTabController.swift"),
        Switch(key: "clipboard.globalHotkey",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/ClipboardShelfController.swift"),
        Switch(key: "notes.edgeEnabled",
               views: ["XFinder/Views/Detail/NotesDetailView.swift"],
               reader: "XFinder/Core/EdgeNotesController.swift"),
        // XF-T24
        Switch(key: "notes.globalHotkey",
               views: ["XFinder/Views/Detail/NotesDetailView.swift"],
               reader: "XFinder/Core/EdgeNotesController.swift"),
        Switch(key: "notes.autoBackup",
               views: ["XFinder/Views/Detail/NotesDetailView.swift"],
               reader: "XFinder/Core/NoteStore.swift"),
        Switch(key: "clipboard.autoPasteAfterSelection",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardShelfController.swift"),
        Switch(key: "clipboard.cleanURLs",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardManager.swift"),
        Switch(key: "clipboard.autoClearSeconds",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardManager.swift"),
        Switch(key: "menubar.readoutsEnabled",
               views: [],   // bound only through FeatureHub (popover edit mode + Features hub)
               reader: "XFinder/Core/MenuBarReadoutsController.swift"),
        Switch(key: "menubar.readoutInterval",
               views: [],
               reader: "XFinder/Core/MenuBarReadoutsController.swift"),
        Switch(key: "alerts.enabled",
               views: ["XFinder/Views/Detail/AlertsDetailView.swift"],
               reader: "XFinder/Core/AlertMonitor.swift"),
        Switch(key: "quitProtection.enabled",
               views: ["XFinder/Views/Detail/AppQuitDetailView.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],   // F3: the Thoát ứng dụng page, beside the hub
               reader: "XFinder/Core/QuitProtectionController.swift"),
        Switch(key: "quitOnClose.enabled",
               views: ["XFinder/Views/Detail/AppQuitDetailView.swift"],
               reader: "XFinder/Core/QuitOnClose/QuitOnCloseController.swift"),
        Switch(key: "quitOnClose.apps",
               views: ["XFinder/Views/Detail/AppQuitDetailView.swift"],
               reader: "XFinder/Core/QuitOnClose/QuitOnCloseController.swift"),
        Switch(key: "snapzones.notchRow",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift"],
               reader: "XFinder/Core/SnapZoneController.swift"),
        Switch(key: "snapzones.remember",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift"],
               reader: "XFinder/Core/Snap/SnapMemoryController.swift"),
        Switch(key: "snapzones.rememberFrames",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift"],
               reader: "XFinder/Core/Snap/SnapMemoryController.swift"),
        Switch(key: "notch.activities",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/LiveActivityMonitor.swift"),
        Switch(key: "notch.activity.power",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/LiveActivityMonitor.swift"),
        Switch(key: "notch.activity.network",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/LiveActivityMonitor.swift"),
        Switch(key: "notch.activity.capsLock",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/LiveActivityMonitor.swift"),
        Switch(key: "notch.activity.bluetooth",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/LiveActivityMonitor.swift"),
        Switch(key: "notch.activity.alerts",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/LiveActivityMonitor.swift"),
        Switch(key: "notch.activity.volume",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/LiveActivityMonitor.swift"),
        Switch(key: "notch.activity.brightness",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/LiveActivityMonitor.swift"),
        Switch(key: "notch.activity.hideSystemHUD",
               views: ["XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/SystemKeyInterceptor.swift"),
        Switch(key: "agents.keepFinished",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/AgentSessionMonitor.swift"),
        Switch(key: "notch.agentEdgeHover",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        Switch(key: "agents.sortMode",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/AgentSessionMonitor.swift"),
        Switch(key: "agents.notify.quietWhenFront",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/AgentSessionMonitor.swift"),
        Switch(key: "notch.hideFromCapture",
               views: ["XFinder/Views/Detail/NotchInterfaceDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        Switch(key: "notch.pillOnPlainScreens",
               views: ["XFinder/Views/Detail/NotchInterfaceDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        Switch(key: "notch.nowPlaying",
               views: ["XFinder/Views/Detail/MediaDetailView.swift"],
               reader: "XFinder/Core/Notch/NowPlayingMonitor.swift"),
        Switch(key: "agents.enabled",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/AgentSessionMonitor.swift"),
        Switch(key: "agents.opencode",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/OpenCodeMonitor.swift"),
        Switch(key: "agents.notify.permission",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/AgentSessionMonitor.swift"),
        Switch(key: "agents.notify.finished",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/AgentSessionMonitor.swift"),
        Switch(key: "agents.notify.sound",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/AgentSessionMonitor.swift"),
        Switch(key: "agents.notify.quotaBlocked",
               views: ["XFinder/Views/Detail/AIAgentsDetailView.swift"],
               reader: "XFinder/Core/Agents/AgentSessionMonitor.swift"),
        Switch(key: "notch.calendar",
               views: ["XFinder/Views/Detail/CalendarSettingsDetailView.swift"],
               reader: "XFinder/Core/Calendar/CalendarGlanceMonitor.swift"),
        Switch(key: "notch.calendar.hideAllDay",
               views: ["XFinder/Views/Detail/CalendarSettingsDetailView.swift"],
               reader: "XFinder/Core/Calendar/CalendarGlanceMonitor.swift"),
        Switch(key: "translate.hotkeyEnabled",
               views: ["XFinder/Views/Detail/SmartSelectDetailView.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/Translate/TranslateSelectionController.swift"),
        Switch(key: "smartSelect.enabled",
               views: ["XFinder/Views/Detail/SmartSelectDetailView.swift"],
               reader: "XFinder/Core/SmartSelect/SelectionWatcher.swift"),
        Switch(key: "smartSelect.minLength",
               views: ["XFinder/Views/Detail/SmartSelectDetailView.swift"],
               reader: "XFinder/Core/SmartSelect/SelectionWatcher.swift"),
        Switch(key: "smartSelect.excludedApps",
               views: ["XFinder/Views/Detail/SmartSelectDetailView.swift"],
               reader: "XFinder/Core/SmartSelect/SelectionWatcher.swift"),
        Switch(key: "smartSelect.currency",
               views: ["XFinder/Views/Detail/SmartSelectDetailView.swift"],
               reader: "XFinder/Core/SmartSelect/CurrencyRateStore.swift"),
        Switch(key: "clipboard.linkPreviews",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/Clipboard/LinkPreviewFetcher.swift"),
        Switch(key: "notch.hoverOpens",
               views: ["XFinder/Views/Detail/NotchInterfaceDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        // Notch surface (B1). These two were DEAD keys for a year — stored, never read. Now the
        // machine gates on them, and the page binds them.
        // P3: the notch master. It switches the WHOLE notch surface off, so its switch lives on Giao diện notch; Khay
        // thả declares it read-only to say "the notch is off". Two declarations, one default — exactly what this checks.
        Switch(key: "dropTray.notchEnabled",
               views: ["XFinder/Views/Detail/NotchInterfaceDetailView.swift", "XFinder/Views/Detail/DropTrayDetailView.swift",
                       "XFinder/Views/Detail/MediaDetailView.swift", "XFinder/Views/Detail/AIAgentsDetailView.swift",
                       "XFinder/Views/Detail/CalendarSettingsDetailView.swift", "XFinder/Views/Detail/LiveActivitiesDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        Switch(key: "dropTray.hoverEnabled",
               views: ["XFinder/Views/Detail/NotchInterfaceDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        Switch(key: "dropTray.notchDropEnabled",
               views: ["XFinder/Views/Detail/DropTrayDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        Switch(key: "dropTray.shakeEnabled",
               views: ["XFinder/Views/Detail/DropTrayDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        // String-valued pickers (review 2026-10-11): the same Part 0 §5 rule, a quoted literal.
        Switch(key: "dropTray.shakeSensitivity",
               views: ["XFinder/Views/Detail/DropTrayDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        // P3 review: the Phím tắt page now reads this to print ⌥Tab when the user picked it — a second declaration.
        Switch(key: "windowPreview.switcherHotkey",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/CommandTabController.swift"),
        // P3: keys the Phím tắt page reads to say whether a fixed shortcut is live — a second declaration each.
        Switch(key: "quickSearch.enabled",
               views: ["XFinder/Views/Detail/SearchDetailViews.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/QuickSearch/QuickSearchPanelController.swift"),
        Switch(key: "snapzones.hotkeysEnabled",
               views: ["XFinder/Views/Detail/WindowDetailViews.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/SnapZoneController.swift"),
        Switch(key: "finderKeyboard.cutPaste",
               views: ["XFinder/Views/Detail/FinderKeyboardDetailView.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/FinderKeyboardController.swift"),
        Switch(key: "finderKeyboard.deleteToTrash",
               views: ["XFinder/Views/Detail/FinderKeyboardDetailView.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/FinderKeyboardController.swift"),
        Switch(key: "finderKeyboard.returnOpens",
               views: ["XFinder/Views/Detail/FinderKeyboardDetailView.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/FinderKeyboardController.swift"),
        Switch(key: "notch.hoverSpeed",
               views: ["XFinder/Views/Detail/NotchInterfaceDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        // D0: where ⌘⇧V lands, and the Touch ID lock the notch page now honours (the shelf's own view
        // binds the same key with @AppStorage inside the Core file — listed as a view on purpose).
        Switch(key: "clipboard.hotkeySurface",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardShelfController.swift"),
        Switch(key: "clipboard.touchIDLock",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift",
                       "XFinder/Core/ClipboardShelfController.swift"],
               reader: "XFinder/Core/ClipboardShelfController.swift"),
        // D0c: the history cap now also decides how many rows are loaded — one reader for both.
        Switch(key: "clipboard.maxHistory",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardManager.swift"),
        // D1: pause recording (Bool) and the copy sound (String).
        Switch(key: "clipboard.paused",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardManager.swift"),
        Switch(key: "clipboard.copySound",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardPasteEngine.swift"),
        // A tap per card while a deck scrolls (2026-10-14).
        Switch(key: "clipboard.cardHaptic",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/ClipboardPasteEngine.swift"),
        // Local diagnostics log (codes only, never leaves the Mac): bound on Giới thiệu.
        Switch(key: "diagnostics.localLog",
               views: ["XFinder/Views/SettingsWindow.swift"],
               reader: "XFinder/Core/Diagnostics/DiagnosticsLog.swift"),
        // Opt-out analytics: the REFUSE switch, default off (sending on until refused — the owner's choice).
        Switch(key: "analytics.optOut",
               views: ["XFinder/Views/SettingsWindow.swift"],
               reader: "XFinder/Core/Diagnostics/AnalyticsCenter.swift"),
        // D1 group 2: page order/visibility and the notch accent (both Strings).
        Switch(key: "notch.pages",
               views: ["XFinder/Views/Detail/NotchInterfaceDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        Switch(key: "notch.accent",
               views: ["XFinder/Views/Detail/NotchInterfaceDetailView.swift"],
               reader: "XFinder/Core/Notch/NotchSurfaceController.swift"),
        // D: the ⌘⌥C shelf hotkey (off by default, user) and the MCP server (off by default).
        Switch(key: "clipboard.shelfHotkey",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift", "XFinder/Views/Detail/ShortcutsDetailView.swift"],
               reader: "XFinder/Core/ClipboardShelfController.swift"),
        Switch(key: "clipboard.mcpEnabled",
               views: ["XFinder/Views/Detail/SettingsDetailView.swift"],
               reader: "XFinder/Core/MCP/MCPServer.swift"),
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
        let k = NSRegularExpression.escapedPattern(for: key)
        // Bool / Int literal, or (review 2026-10-11) a String literal — `"medium"` and friends.
        let pattern = #"@AppStorage\(\s*""# + k + #""\s*\)[^=\n]*=\s*(true|false|-?\d+|"[^"\n]*")"#
        return matches(pattern, in: text)
    }

    /// All `object(forKey: "<key>") as? Bool|Int ?? <literal>` and `string(forKey: "<key>") ?? "<literal>"`
    /// reads in one Core file.
    static func readerDefaults(forKey key: String, in text: String) -> [String] {
        let k = NSRegularExpression.escapedPattern(for: key)
        let scalar = #"object\(forKey:\s*""# + k + #""\s*\)\s*as\?\s*(?:Bool|Int)\s*\?\?\s*(true|false|-?\d+)\b"#
        let string = #"string\(forKey:\s*""# + k + #""\s*\)\s*\?\?\s*("[^"\n]*")"#
        return matches(scalar, in: text) + matches(string, in: text)
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
    /// D4b: `clipboard.linkPreviews` is back WITH a reader (`LinkPreviewFetcher`); the Switch row above is its gate.
    /// (The Phase 1 test that asserted the key was bound nowhere is retired with the reason, not deleted silently.)
}
