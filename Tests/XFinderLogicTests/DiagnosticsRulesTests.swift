import XCTest
import Foundation

/// The local diagnostics may hold codes, versions and crash frames — never what identifies the person, the
/// machine or the session. These tests feed a crash report full of planted identifiers and fail if any of them
/// reaches the report text the person would share.
final class DiagnosticsRulesTests: XCTestCase {
    private let home = "/Users/alice"
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testOnlySafeWordsBecomeAreasAndCodes() {
        XCTAssertTrue(DiagnosticsRules.isSafeWord("timeout.snapKeys"))
        XCTAssertTrue(DiagnosticsRules.isSafeWord("tool.-1"))
        XCTAssertFalse(DiagnosticsRules.isSafeWord(""))
        XCTAssertFalse(DiagnosticsRules.isSafeWord("/Users/alice/Desktop"))
        XCTAssertFalse(DiagnosticsRules.isSafeWord("Báo cáo"))
        XCTAssertFalse(DiagnosticsRules.isSafeWord("has space"))
        XCTAssertFalse(DiagnosticsRules.isSafeWord(String(repeating: "a", count: 49)))
        XCTAssertNil(DiagnosticsRules.event(area: "snap", code: "a b", detail: nil, at: t0, home: home))
        XCTAssertNil(DiagnosticsRules.event(area: "Report.pdf in ~/Desktop", code: "x", detail: nil, at: t0, home: home))
    }

    func testDetailIsRedactedAndTrimmed() throws {
        let e = try XCTUnwrap(DiagnosticsRules.event(
            area: "snap", code: "axError",
            detail: "at /Users/alice/x and /Users/bob/y, mail alice@example.com, id 123E4567-E89B-12D3-A456-426614174000",
            at: t0, home: home))
        let d = try XCTUnwrap(e.detail)
        XCTAssertFalse(d.contains("alice"), d)
        XCTAssertFalse(d.contains("bob"), d)
        XCTAssertFalse(d.contains("123E4567"), d)
        XCTAssertTrue(d.contains("~/x"), d)
        XCTAssertTrue(d.contains("<email>"), d)
        XCTAssertTrue(d.contains("<uuid>"), d)

        let long = try XCTUnwrap(DiagnosticsRules.event(area: "a", code: "b", detail: String(repeating: "x", count: 900), at: t0, home: home))
        XCTAssertEqual(long.detail?.count, DiagnosticsRules.maxDetail)
        XCTAssertNil(DiagnosticsRules.event(area: "a", code: "b", detail: "", at: t0, home: home)?.detail)
    }

    func testTheRingKeepsTheNewestEvents() {
        let many = (0..<(DiagnosticsRules.maxEvents + 40)).map {
            DiagnosticsRules.Event(time: t0.addingTimeInterval(Double($0)), area: "a", code: "c\($0)", detail: nil)
        }
        let kept = DiagnosticsRules.trimmed(many)
        XCTAssertEqual(kept.count, DiagnosticsRules.maxEvents)
        XCTAssertEqual(kept.first?.code, "c40")
        XCTAssertEqual(kept.last?.code, "c\(DiagnosticsRules.maxEvents + 39)")
    }

    func testLinesRoundTripAndATornLineIsSkipped() throws {
        let a = DiagnosticsRules.Event(time: t0, area: "app", code: "launch", detail: "v1.4.0 (5)")
        let b = DiagnosticsRules.Event(time: t0.addingTimeInterval(5), area: "app", code: "quit", detail: nil)
        let text = [a, b].compactMap(DiagnosticsRules.encodeLine).joined(separator: "\n") + "\n{\"time\":\"2026-"
        XCTAssertEqual(DiagnosticsRules.decodeLines(text), [a, b])
    }

    func testAnUncleanExitIsALaunchWithNoQuitAfterIt() {
        func ev(_ code: String) -> DiagnosticsRules.Event { .init(time: t0, area: "app", code: code, detail: nil) }
        XCTAssertFalse(DiagnosticsRules.previousRunEndedUncleanly([]))
        XCTAssertFalse(DiagnosticsRules.previousRunEndedUncleanly([ev("launch"), ev("quit")]))
        XCTAssertTrue(DiagnosticsRules.previousRunEndedUncleanly([ev("launch")]))
        XCTAssertTrue(DiagnosticsRules.previousRunEndedUncleanly([ev("launch"), ev("quit"), ev("launch")]))
        // A quit marker from an EARLIER run does not vouch for the last one.
        XCTAssertTrue(DiagnosticsRules.previousRunEndedUncleanly([ev("quit"), ev("launch"),
                                                                  .init(time: t0, area: "snap", code: "noWindow", detail: nil)]))
    }

    // MARK: Crash reports

    /// A crash report shaped like macOS 27's `.ips`, with every identifying field planted.
    private func plantedReport(name: String = "XFinder") throws -> String {
        let header: [String: Any] = [
            "app_name": name, "name": name, "app_version": "1.4.0", "build_version": "5", "bug_type": "309",
            "os_version": "macOS 27.0.1 (26A434)", "timestamp": "2026-10-13 05:52:12.00 +0700",
            "incident_id": "PLANTED-INCIDENT-0001", "slice_uuid": "PLANTED-SLICE-0002",
        ]
        let body: [String: Any] = [
            "procName": name, "modelCode": "Mac15,7", "cpuType": "ARM-64",
            "crashReporterKey": "PLANTED-CRK-0003", "sleepWakeUUID": "PLANTED-SLEEP-0004",
            "bootSessionUUID": "PLANTED-BOOT-0005", "userID": 50_1234, "incident": "PLANTED-INC-0006",
            "pid": 98_765, "parentProc": "PLANTEDPARENT", "responsibleProc": "PLANTEDRESPONSIBLE",
            "procPath": "/Users/alice/Applications/XFinder.app/Contents/MacOS/XFinder",
            "coalitionName": "PLANTED-COALITION", "vmSummary": "PLANTED-VMSUMMARY",
            "asi": ["CoreFoundation": ["PLANTED-ASI-TEXT secret clipboard words"]],
            "instructionByteStream": ["beforePC": "PLANTED-BYTES"],
            "trialInfo": ["rollouts": ["PLANTED-TRIAL"]], "extMods": ["PLANTED-EXTMODS": 1],
            "exception": ["type": "EXC_BREAKPOINT", "signal": "SIGTRAP"],
            "termination": ["namespace": "SIGNAL", "indicator": "Trace/BPT trap: 5"],
            "faultingThread": 0,
            "threads": [[
                "triggered": true,
                "name": "PLANTED-THREAD-NAME",
                "frames": [
                    ["imageIndex": 0, "imageOffset": 4096, "symbol": "NowPlayingMonitor.consume(_:gen:)",
                     "symbolLocation": 88, "sourceFile": "/Users/alice/github/XFinder/XFinder/Core/Notch/NowPlayingMonitor.swift",
                     "sourceLine": 42],
                    ["imageIndex": 1, "imageOffset": 255],
                ],
            ]],
            "usedImages": [
                ["name": "XFinder.debug.dylib", "path": "/Users/alice/Applications/XFinder.app/PLANTED-IMAGE-PATH"],
                ["name": "libswiftCore.dylib", "path": "/usr/lib/swift/libswiftCore.dylib"],
            ],
        ]
        let h = String(data: try JSONSerialization.data(withJSONObject: header), encoding: .utf8)!
        let b = String(data: try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted]), encoding: .utf8)!
        return h + "\n" + b
    }

    func testACrashSummaryKeepsTheAllowlistOnly() throws {
        let s = try XCTUnwrap(DiagnosticsRules.crashSummary(ipsText: try plantedReport(), processName: "XFinder", home: home))
        XCTAssertEqual(s.kind, "crash")
        XCTAssertEqual(s.appVersion, "1.4.0")
        XCTAssertEqual(s.build, "5")
        XCTAssertEqual(s.model, "Mac15,7")
        XCTAssertEqual(s.exceptionType, "EXC_BREAKPOINT")
        XCTAssertEqual(s.signal, "SIGTRAP")
        XCTAssertEqual(s.termination, "SIGNAL — Trace/BPT trap: 5")
        XCTAssertNotNil(s.time)
        XCTAssertEqual(s.frames.count, 2)
        XCTAssertEqual(s.frames[0], "XFinder.debug.dylib  NowPlayingMonitor.consume(_:gen:) + 88  (NowPlayingMonitor.swift:42)")
        XCTAssertEqual(s.frames[1], "libswiftCore.dylib  +0xff")
    }

    func testNoPlantedIdentifierReachesTheSharedReport() throws {
        let crash = try XCTUnwrap(DiagnosticsRules.crashSummary(ipsText: try plantedReport(), processName: "XFinder", home: home))
        let event = try XCTUnwrap(DiagnosticsRules.event(area: "snap", code: "axError",
                                                         detail: "/Users/alice/Desktop/x", at: t0, home: home))
        let system = DiagnosticsRules.SystemInfo(appVersion: "1.4.0", build: "5", osVersion: "27.0.1 (26A434)",
                                                 model: "Mac15,7", arch: "arm64", language: "vi",
                                                 permissions: ["accessibility: granted"], featuresOn: ["snapZones"])
        let text = DiagnosticsRules.report(system: system, events: [event], crashes: [crash], now: t0, home: home)
        XCTAssertTrue(text.contains("EXC_BREAKPOINT"))
        XCTAssertTrue(text.contains("NowPlayingMonitor.swift:42"))
        XCTAssertTrue(text.contains("snap/axError"))
        XCTAssertFalse(text.contains("alice"), "a home folder reached the report")
        XCTAssertFalse(text.contains("PLANTED"), "an identifying crash-report field reached the report")
        XCTAssertFalse(text.contains("98765"), "the pid reached the report")
        XCTAssertFalse(text.contains("501234"), "the user id reached the report")
        XCTAssertFalse(text.contains("secret clipboard"), "the asi free text reached the report")
    }

    func testOnlyReportsOfThisProcessAreRead() throws {
        XCTAssertNil(DiagnosticsRules.crashSummary(ipsText: try plantedReport(name: "Safari"), processName: "XFinder", home: home))
        XCTAssertNil(DiagnosticsRules.crashSummary(ipsText: "not a report", processName: "XFinder", home: home))
        XCTAssertNil(DiagnosticsRules.crashSummary(ipsText: "{\"name\":\"XFinder\"}\nnot json", processName: "XFinder", home: home))
    }

    func testTheReportSaysWhenThereIsNothingAndCapsWhatItShows() {
        let system = DiagnosticsRules.SystemInfo(appVersion: "1", build: "1", osVersion: "27", model: "m", arch: "arm64",
                                                 language: "en", permissions: [], featuresOn: [])
        let events = (0..<100).map { DiagnosticsRules.Event(time: t0, area: "a", code: "c\($0)", detail: nil) }
        let text = DiagnosticsRules.report(system: system, events: events, crashes: [], now: t0, home: home)
        XCTAssertTrue(text.contains("None found."))
        XCTAssertTrue(text.contains("Recent events (60 of 100)"))
        XCTAssertFalse(text.contains("a/c39\n"))
        XCTAssertTrue(text.contains("a/c99"))
    }

    func testTheIssueLinkCarriesVersionsOnly() throws {
        let system = DiagnosticsRules.SystemInfo(appVersion: "1.4.0", build: "5", osVersion: "27.0.1", model: "Mac15,7",
                                                 arch: "arm64", language: "vi",
                                                 permissions: ["accessibility: granted"], featuresOn: ["snapZones", "capture"])
        let url = try XCTUnwrap(DiagnosticsRules.issueURL(repo: "PyDude9/XFinder", system: system))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/PyDude9/XFinder/issues/new")
        let s = url.absoluteString.removingPercentEncoding ?? ""
        XCTAssertTrue(s.contains("1.4.0"))
        XCTAssertFalse(s.contains("accessibility"), "permissions do not belong in a URL")
        XCTAssertFalse(s.contains("snapZones"), "the feature list does not belong in a URL")
        XCTAssertLessThanOrEqual(url.absoluteString.count, 6_000)
    }

    func testReportDatesParse() {
        XCTAssertNotNil(DiagnosticsRules.reportDate("2026-10-13 05:52:12.00 +0700"))
        XCTAssertNotNil(DiagnosticsRules.reportDate("2026-10-13 05:52:12.5321 +0700"))
        XCTAssertNil(DiagnosticsRules.reportDate("yesterday"))
    }
}
