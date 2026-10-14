import XCTest
import Foundation

/// Opt-out analytics is only defensible while a report stays anonymous. These tests pin the exact field set, plant
/// identifying values in every input and fail if any of them reaches the JSON, and walk the send/notice decisions.
final class AnalyticsRulesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func event(_ area: String, _ code: String, _ at: TimeInterval, detail: String? = nil) -> DiagnosticsRules.Event {
        .init(time: t0.addingTimeInterval(at), area: area, code: code, detail: detail)
    }

    private func inputs(since: Date? = nil,
                        events: [DiagnosticsRules.Event] = [],
                        crashes: [DiagnosticsRules.CrashSummary] = []) -> AnalyticsRules.Inputs {
        AnalyticsRules.Inputs(appVersion: "1.4.0", build: "5", osVersion: "27.0.1", model: "Mac15,7", arch: "arm64",
                              language: "vi", featuresOn: ["snapZones", "agents"],
                              permissionsGranted: ["accessibility", "screenRecording"],
                              events: events, crashes: crashes, since: since)
    }

    // MARK: Field set — adding a field must be a deliberate, announced change

    func testTheReportCarriesExactlyTheseFields() throws {
        let crash = DiagnosticsRules.CrashSummary(source: "report", kind: "crash", time: t0, appVersion: "1.4.0",
                                                  build: "5", osVersion: "27", model: "Mac15,7", cpu: "ARM-64",
                                                  exceptionType: "EXC_BAD_ACCESS", signal: "SIGSEGV",
                                                  termination: "SIGNAL — Segmentation fault: 11",
                                                  hangSeconds: nil, frames: ["XFinder  Foo.bar() + 12"])
        let r = AnalyticsRules.report(inputs(events: [event("snap", "noWindow", 1)], crashes: [crash]))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), [
            "schema", "appVersion", "build", "osVersion", "model", "arch", "language", "featuresOn",
            "permissionsGranted", "launches", "uncleanExits", "errorCounts", "crashes",
        ], "a new field needs AnalyticsRules.schemaVersion + 1 AND the notice/page text updated to describe it")
        let crashes = try XCTUnwrap(json["crashes"] as? [[String: Any]])
        XCTAssertEqual(Set(crashes[0].keys), ["kind", "source", "exceptionType", "signal", "termination", "frames"])
        XCTAssertEqual(AnalyticsRules.schemaVersion, 1, "bumping the schema? update this test and the notice together")
    }

    // MARK: Nothing identifying survives

    func testPlantedIdentifiersNeverReachTheReport() throws {
        let planted = inputs(events: [
            event("snap", "axError", 1, detail: "/Users/alice/Desktop/secret.txt alice@example.com"),
            event("archive", "compress.tool.1", 2, detail: "123E4567-E89B-12D3-A456-426614174000"),
            event("Báo cáo", "x", 3),                       // not a safe word ⇒ never even logged, but planted anyway
        ], crashes: [
            DiagnosticsRules.CrashSummary(source: "report", kind: "crash", time: t0, appVersion: "1.4.0", build: "5",
                                          osVersion: "27", model: "Mac15,7", cpu: "ARM-64",
                                          exceptionType: "EXC_CRASH", signal: "SIGABRT",
                                          termination: "mail alice@example.com",
                                          hangSeconds: nil,
                                          frames: ["XFinder  Clip.paste(_:) + 8  (/Users/alice/github/XFinder/Clip.swift:42)",
                                                   "/Users/alice/evil  +0x10"]),
        ])
        var p = planted
        p.featuresOn.append("tính năng bí mật")
        p.permissionsGranted.append("alice@example.com")
        p.model = "/Users/alice"
        let text = AnalyticsRules.previewJSON(AnalyticsRules.report(p))
        for leak in ["alice", "/Users", "@", "secret", "123E4567", "Báo", "tính năng", "Clip.swift", ":42"] {
            XCTAssertFalse(text.contains(leak), "\(leak) reached the analytics report:\n\(text)")
        }
        XCTAssertTrue(text.contains("XFinder Clip.paste(_:)"), "the frame's symbol is the useful part and must stay")
        XCTAssertTrue(text.contains("EXC_CRASH"))
    }

    func testOnlyTokensPass() {
        XCTAssertTrue(AnalyticsRules.isToken("timeout.snapKeys"))
        XCTAssertFalse(AnalyticsRules.isToken("/Users/alice"), "a path is never a token")
        XCTAssertTrue(AnalyticsRules.isToken("SIGKILL (Code Signature Invalid)"))
        XCTAssertFalse(AnalyticsRules.isToken(""))
        XCTAssertFalse(AnalyticsRules.isToken("a\nb"))
        XCTAssertFalse(AnalyticsRules.isToken("ai@x.com"))
        XCTAssertFalse(AnalyticsRules.isToken("Tiếng Việt"))
        XCTAssertFalse(AnalyticsRules.isToken(String(repeating: "a", count: 81)))
    }

    // MARK: Counting

    func testLaunchesUncleanExitsAndErrorCodesAreCountedSinceTheLastReport() {
        let events = [
            event("app", "launch", 10), event("app", "quit", 20), event("app", "launch", 30),
            event("app", "uncleanExit", 40), event("app", "launch", 41),
            event("snap", "noWindow", 50), event("snap", "noWindow", 60), event("eventTap", "timeout.snapKeys", 70),
            event("snap", "noWindow", 5),                           // before `since` ⇒ not counted
        ]
        let r = AnalyticsRules.report(inputs(since: t0.addingTimeInterval(9), events: events))
        XCTAssertEqual(r.launches, 3)
        XCTAssertEqual(r.uncleanExits, 1)
        XCTAssertEqual(r.errorCounts, ["snap/noWindow": 2, "eventTap/timeout.snapKeys": 1])
    }

    func testAFloodOfErrorKindsKeepsTheMostFrequent() {
        var events: [DiagnosticsRules.Event] = []
        for k in 0..<60 { events.append(event("x", "c\(k)", Double(k))) }
        for _ in 0..<5 { events.append(event("x", "c59", 100)) }
        let r = AnalyticsRules.report(inputs(events: events))
        XCTAssertEqual(r.errorCounts.count, AnalyticsRules.maxErrorCodes)
        XCTAssertEqual(r.errorCounts["x/c59"], 6)
    }

    func testCrashesAreFilteredCappedAndFramesStripped() {
        let crashes = (0..<8).map { k in
            DiagnosticsRules.CrashSummary(source: "metrickit", kind: "crash", time: t0.addingTimeInterval(Double(k * 100)),
                                          appVersion: "1.4.0", build: "5", osVersion: "27", model: "m", cpu: "c",
                                          exceptionType: "EXC 6", signal: "signal 6", termination: nil, hangSeconds: nil,
                                          frames: (0..<9).map { "XFinder  +0x\($0)" })
        }
        let r = AnalyticsRules.report(inputs(since: t0.addingTimeInterval(150), crashes: crashes))
        XCTAssertEqual(r.crashes.count, AnalyticsRules.maxCrashes, "6 are newer than `since`, capped at 5")
        XCTAssertTrue(r.crashes.allSatisfy { $0.frames.count <= AnalyticsRules.maxFrames })
        XCTAssertEqual(AnalyticsRules.frameToken("XFinder  Foo.bar(_:) + 88  (Foo.swift:3)"), "XFinder Foo.bar(_:)")
        XCTAssertEqual(AnalyticsRules.frameToken("XFinder  Foo.bar()  (Foo.swift:3)"), "XFinder Foo.bar()")
    }

    // MARK: When to send

    private func state(optedOut: Bool = false, configured: Bool = true, notice: TimeInterval? = 0,
                       schema: Int? = AnalyticsRules.schemaVersion, sent: TimeInterval? = nil,
                       attempt: TimeInterval? = nil, onboarding: Bool = false) -> AnalyticsRules.State {
        .init(optedOut: optedOut, configured: configured, noticeShownAt: notice.map { t0.addingTimeInterval($0) },
              noticeSchema: schema, lastSentAt: sent.map { t0.addingTimeInterval($0) },
              lastAttemptAt: attempt.map { t0.addingTimeInterval($0) }, onboardingShowing: onboarding)
    }

    func testDecisions() {
        let day = AnalyticsRules.minimumInterval
        let now = t0.addingTimeInterval(day * 3)
        XCTAssertEqual(AnalyticsRules.nextAction(state(optedOut: true), now: now), .wait(.optedOut))
        XCTAssertEqual(AnalyticsRules.nextAction(state(optedOut: true, configured: false), now: now), .wait(.optedOut),
                       "a refusal is reported as a refusal even without a receiver")
        XCTAssertEqual(AnalyticsRules.nextAction(state(configured: false), now: now), .wait(.notConfigured))
        XCTAssertEqual(AnalyticsRules.nextAction(state(notice: nil), now: now), .showNotice)
        XCTAssertEqual(AnalyticsRules.nextAction(state(notice: nil, onboarding: true), now: now), .wait(.onboarding))
        XCTAssertEqual(AnalyticsRules.nextAction(state(schema: AnalyticsRules.schemaVersion - 1), now: now), .showNotice,
                       "a schema newer than the notice the person saw shows the notice again")
        XCTAssertEqual(AnalyticsRules.nextAction(state(notice: day * 3 - 3600), now: now), .wait(.grace))
        XCTAssertEqual(AnalyticsRules.nextAction(state(sent: day * 3 - 3600), now: now), .wait(.notDue))
        XCTAssertEqual(AnalyticsRules.nextAction(state(sent: day * 2 - 1), now: now), .send)
        XCTAssertEqual(AnalyticsRules.nextAction(state(), now: now), .send)
        // A failed attempt (offline) retries after an hour, not on every activation.
        XCTAssertEqual(AnalyticsRules.nextAction(state(attempt: day * 3 - 60), now: now), .wait(.notDue))
        XCTAssertEqual(AnalyticsRules.nextAction(state(attempt: day * 3 - AnalyticsRules.retryInterval), now: now), .send)
        // A clock set back: a "future" stamp counts as elapsed instead of blocking forever.
        XCTAssertEqual(AnalyticsRules.nextAction(state(notice: day * 10, sent: day * 10), now: now), .send)
    }

    // MARK: Receiver + body

    func testTheReceiverNeedsBothValuesAndASafeNamespace() {
        XCTAssertNotNil(AnalyticsRules.receiver(appID: "AAAA-BBBBBBBB-CCCC-DDDD", namespace: "xfinder"))
        XCTAssertNil(AnalyticsRules.receiver(appID: "", namespace: "xfinder"), "empty App ID ⇒ not configured")
        XCTAssertNil(AnalyticsRules.receiver(appID: "AAAA", namespace: nil))
        XCTAssertNil(AnalyticsRules.receiver(appID: "AAAA", namespace: "../evil"), "the namespace is a path component")
        XCTAssertNil(AnalyticsRules.receiver(appID: "AAAA", namespace: "Has Space"))
        XCTAssertNil(AnalyticsRules.receiver(appID: "a/b", namespace: "xfinder"))
        let r = AnalyticsRules.receiver(appID: "AAAA", namespace: "my-org")!
        XCTAssertEqual(AnalyticsRules.endpoint(r)?.absoluteString, "https://nom.telemetrydeck.com/v2/namespace/my-org/")
    }

    func testTheBodyIsFlatSignalsWithTheCallersClientUser() throws {
        let crash = DiagnosticsRules.CrashSummary(source: "report", kind: "crash", time: t0, appVersion: nil, build: nil,
                                                  osVersion: nil, model: nil, cpu: nil, exceptionType: "EXC_CRASH",
                                                  signal: "SIGABRT", termination: nil, hangSeconds: nil,
                                                  frames: ["XFinder  A.b() + 1", "libswiftCore.dylib  +0x10"])
        let report = AnalyticsRules.report(inputs(events: [event("snap", "noWindow", 1)], crashes: [crash]))
        let receiver = AnalyticsRules.receiver(appID: "AAAA-BBBB", namespace: "xfinder")!
        let data = try XCTUnwrap(AnalyticsRules.telemetryDeckBody(report, receiver: receiver, clientUser: "c1", testMode: true))
        let signals = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(signals.map { $0["type"] as? String }, ["Report.daily", "Report.crash"])
        for s in signals {
            XCTAssertEqual(s["appID"] as? String, "AAAA-BBBB")
            XCTAssertEqual(s["clientUser"] as? String, "c1")
            XCTAssertEqual(s["isTestMode"] as? Bool, true)
            XCTAssertNil(s["sessionID"], "a session id would link signals across sends")
            let payload = try XCTUnwrap(s["payload"] as? [String: Any])
            XCTAssertTrue(payload.values.allSatisfy { $0 is String }, "payload values are flat strings")
            XCTAssertTrue(payload.keys.allSatisfy { $0.hasPrefix("XFinder.") }, "never the reserved TelemetryDeck. scope")
        }
        let daily = try XCTUnwrap(signals[0]["payload"] as? [String: String])
        XCTAssertEqual(daily["XFinder.Errors.counts"], "snap/noWindow=1")
        XCTAssertEqual(daily["XFinder.Features.on"], "agents,snapZones")
        let crashPayload = try XCTUnwrap(signals[1]["payload"] as? [String: String])
        XCTAssertEqual(crashPayload["XFinder.Crash.frames"], "XFinder A.b() | libswiftCore.dylib +0x10")
    }

    func testEveryStatusLineIsInTheStore() throws {
        let store = try L10nFixture.load()
        XCTAssertEqual(Set(AnalyticsRules.statusKeys).count, 5, "one line per distinct state")
        for key in AnalyticsRules.statusKeys {
            let entry = store.entries[key]
            XCTAssertNotNil(entry, "\(key.debugDescription) is not in L10n.strings.json")
            if let entry { XCTAssertNotEqual(entry.en, key) }
        }
    }
}
