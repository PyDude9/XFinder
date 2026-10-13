import XCTest
import Foundation

/// P2 — install rules for Claude Code's `statusLine` setting, and the rate-limit cache parser.
final class ClaudeStatusLineTests: XCTestCase {
    let scriptPath = "/Users/me/Library/Application Support/XFinder/Agents/claude/bin/xfinder-claude-statusline.sh"

    // MARK: Paths

    func testPathsMatchAgentSessionMonitorsSupportDir() {
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(ClaudeStatusLine.supportDir(home: home).path, "/Users/me/Library/Application Support/XFinder/Agents/claude")
        XCTAssertEqual(ClaudeStatusLine.scriptURL(home: home).path, "/Users/me/Library/Application Support/XFinder/Agents/claude/bin/xfinder-claude-statusline.sh")
        XCTAssertEqual(ClaudeStatusLine.cacheURL(home: home).path, "/Users/me/Library/Application Support/XFinder/Agents/claude/rate-limits.json")
        XCTAssertEqual(ClaudeStatusLine.previousCommandURL(home: home).path, "/Users/me/Library/Application Support/XFinder/Agents/claude/statusline-before")
        XCTAssertEqual(ClaudeStatusLine.previousJSONURL(home: home).path, "/Users/me/Library/Application Support/XFinder/Agents/claude/statusline-before.json")
    }

    // MARK: Quoting (same shape as AgentHookInstaller.command(forHookAt:))

    func testCommandQuotingSurvivesSpacesAndQuotes() {
        XCTAssertEqual(ClaudeStatusLine.command(forScriptAt: "/a b/c'd"), "'/a b/c'\\''d'")
    }

    func testQuotedPathSurvivesABinShC() throws {
        let path = "/tmp/a dir with 'quote/script.sh"
        let quoted = ClaudeStatusLine.command(forScriptAt: path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "echo \(quoted)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(out, path)
    }

    // MARK: isOurs

    func testIsOursLooksAtTheCommandString() {
        XCTAssertTrue(ClaudeStatusLine.isOurs(["type": "command", "command": "'\(scriptPath)'"], scriptPath: scriptPath))
        XCTAssertFalse(ClaudeStatusLine.isOurs(["type": "command", "command": "'/other/tool.sh'"], scriptPath: scriptPath))
        XCTAssertFalse(ClaudeStatusLine.isOurs(nil, scriptPath: scriptPath))
        XCTAssertFalse(ClaudeStatusLine.isOurs("not a dict", scriptPath: scriptPath))
        XCTAssertFalse(ClaudeStatusLine.isOurs(["type": "command"], scriptPath: scriptPath), "no command key")
    }

    // MARK: installing() — over nothing

    func testInstallingOverNoStatusLineSavesNothingAndWritesOurBareCommand() {
        let install = ClaudeStatusLine.installing(["model": "opus"], scriptPath: scriptPath)
        XCTAssertNil(install.previous)
        XCTAssertNil(install.previousCommand)
        let sl = install.settings["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["type"] as? String, "command")
        XCTAssertEqual(sl?["command"] as? String, "'\(scriptPath)'")
        XCTAssertEqual(install.settings["model"] as? String, "opus", "the rest of settings.json is untouched")
        XCTAssertEqual(Set((sl?.keys).map(Array.init) ?? []), ["type", "command"], "nothing to carry over when there was no previous object")
    }

    // MARK: installing() — over another tool

    func testInstallingOverAnotherToolsCommandSavesItVerbatimAndKeepsItsOtherKeys() {
        let other: [String: Any] = ["type": "command", "command": "'/other/tool.sh'", "padding": 0, "refreshInterval": 300]
        let install = ClaudeStatusLine.installing(["statusLine": other], scriptPath: scriptPath)
        XCTAssertEqual(install.previous as? NSDictionary, other as NSDictionary, "saved verbatim")
        XCTAssertEqual(install.previousCommand, "'/other/tool.sh'")
        let sl = install.settings["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["type"] as? String, "command")
        XCTAssertEqual(sl?["command"] as? String, "'\(scriptPath)'")
        XCTAssertEqual(sl?["padding"] as? Int, 0, "every other key of the previous object survives")
        XCTAssertEqual(sl?["refreshInterval"] as? Int, 300)
    }

    func testInstallingOverANonCommandStatusLineHasNoPreviousCommandButStillSavesTheObject() {
        // Claude Code's statusLine can in principle be something other than {"type":"command",...}; previousCommand
        // only makes sense for a command we can chain to.
        let other: [String: Any] = ["type": "module", "padding": 2]
        let install = ClaudeStatusLine.installing(["statusLine": other], scriptPath: scriptPath)
        XCTAssertEqual(install.previous as? NSDictionary, other as NSDictionary)
        XCTAssertNil(install.previousCommand)
        let sl = install.settings["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["padding"] as? Int, 2)
    }

    func testPreviousCommandPointingBackAtUsIsNilSoTheChainCannotRecurse() {
        // A statusLine whose "command" CONTAINS our scriptPath is recognised as ours by isOurs() (substring
        // match), so installing() takes the already-installed branch: settings are untouched and nothing new
        // is saved — which is itself the guarantee that a chain back to us is never (re)written as a
        // previousCommand. Confirmed from both ends: the object is "ours" and installing() over it is a no-op.
        let backReferencing = "/bin/sh -c " + ClaudeStatusLine.command(forScriptAt: scriptPath)
        let other: [String: Any] = ["type": "command", "command": backReferencing, "padding": 5]
        XCTAssertTrue(ClaudeStatusLine.isOurs(other, scriptPath: scriptPath), "sanity: this command DOES contain scriptPath")
        let settings: [String: Any] = ["statusLine": other]
        let install = ClaudeStatusLine.installing(settings, scriptPath: scriptPath)
        XCTAssertNil(install.previousCommand, "a command resolving back to us must never be chained to")
        XCTAssertNil(install.previous, "already-ours ⇒ nothing new is saved over whatever is on disk")
        XCTAssertEqual(install.settings as NSDictionary, settings as NSDictionary, "settings are left exactly as found")
    }

    // MARK: installing() — over our own

    func testInstallingOverOurOwnLeavesSettingsAndSavedFilesAlone() {
        let ours: [String: Any] = ["type": "command", "command": "'\(scriptPath)'"]
        let settings: [String: Any] = ["statusLine": ours, "model": "opus"]
        let install = ClaudeStatusLine.installing(settings, scriptPath: scriptPath)
        XCTAssertNil(install.previous, "the caller must not overwrite whatever it saved at the FIRST install")
        XCTAssertNil(install.previousCommand)
        XCTAssertEqual(install.settings as NSDictionary, settings as NSDictionary, "nothing changes")
    }

    // MARK: status()

    func testStatus() {
        let ours: [String: Any] = ["type": "command", "command": "'\(scriptPath)'"]
        let other: [String: Any] = ["type": "command", "command": "'/other.sh'"]
        XCTAssertEqual(ClaudeStatusLine.status(of: ["statusLine": ours], scriptPath: scriptPath, previousSaved: true), .installed)
        XCTAssertEqual(ClaudeStatusLine.status(of: ["statusLine": ours], scriptPath: scriptPath, previousSaved: false), .installed)
        XCTAssertEqual(ClaudeStatusLine.status(of: ["statusLine": other], scriptPath: scriptPath, previousSaved: true), .replaced)
        XCTAssertEqual(ClaudeStatusLine.status(of: ["statusLine": other], scriptPath: scriptPath, previousSaved: false), .notInstalled)
        XCTAssertEqual(ClaudeStatusLine.status(of: [:], scriptPath: scriptPath, previousSaved: false), .notInstalled)
        XCTAssertEqual(ClaudeStatusLine.status(of: [:], scriptPath: scriptPath, previousSaved: true), .replaced, "no statusLine at all, but we installed before — someone deleted the key")
    }

    // MARK: removing()

    func testRemovingRestoresThePreviousObjectVerbatim() {
        let ours: [String: Any] = ["type": "command", "command": "'\(scriptPath)'"]
        let previous: [String: Any] = ["type": "command", "command": "'/other.sh'", "padding": 7]
        let settings: [String: Any] = ["statusLine": ours, "model": "opus"]
        let result = ClaudeStatusLine.removing(settings, scriptPath: scriptPath, previous: previous)
        XCTAssertEqual(result["statusLine"] as? NSDictionary, previous as NSDictionary)
        XCTAssertEqual(result["model"] as? String, "opus")
    }

    func testRemovingWithNoPreviousDeletesTheKey() {
        let ours: [String: Any] = ["type": "command", "command": "'\(scriptPath)'"]
        let result = ClaudeStatusLine.removing(["statusLine": ours, "model": "opus"], scriptPath: scriptPath, previous: nil)
        XCTAssertNil(result["statusLine"])
        XCTAssertEqual(result["model"] as? String, "opus")
    }

    func testRemovingWhenNotOursChangesNothing() {
        let other: [String: Any] = ["type": "command", "command": "'/someone-else.sh'"]
        let settings: [String: Any] = ["statusLine": other, "model": "opus"]
        let result = ClaudeStatusLine.removing(settings, scriptPath: scriptPath, previous: ["type": "command", "command": "'/irrelevant.sh'"])
        XCTAssertEqual(result as NSDictionary, settings as NSDictionary, "another tool owns the slot now; never overwrite it")
    }

    // MARK: parseQuota

    let capturedAt = Date(timeIntervalSince1970: 1_792_000_500)

    func testParseQuotaBothWindows() throws {
        let json = #"{"five_hour":{"used_percentage":37.5,"resets_at":1792000000},"seven_day":{"used_percentage":12,"resets_at":1792500000}}"#
        let q = try XCTUnwrap(ClaudeStatusLine.parseQuota(Data(json.utf8), capturedAt: capturedAt))
        XCTAssertEqual(q.fiveHour?.usedPercent, 37.5)
        XCTAssertEqual(q.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_792_000_000))
        XCTAssertEqual(q.sevenDay?.usedPercent, 12)
        XCTAssertEqual(q.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1_792_500_000))
        XCTAssertEqual(q.capturedAt, capturedAt)
    }

    func testParseQuotaOneWindowOnly() throws {
        let json = #"{"five_hour":{"used_percentage":10}}"#
        let q = try XCTUnwrap(ClaudeStatusLine.parseQuota(Data(json.utf8), capturedAt: capturedAt))
        XCTAssertEqual(q.fiveHour?.usedPercent, 10)
        XCTAssertNil(q.fiveHour?.resetsAt, "no resets_at field at all")
        XCTAssertNil(q.sevenDay)
    }

    func testParseQuotaIntVsDoubleUsedPercentage() throws {
        let json = #"{"five_hour":{"used_percentage":42}}"#
        let q = try XCTUnwrap(ClaudeStatusLine.parseQuota(Data(json.utf8), capturedAt: capturedAt))
        XCTAssertEqual(q.fiveHour?.usedPercent, 42.0, "an Int used_percentage reads the same as a Double")
    }

    func testParseQuotaWindowMissingUsedPercentageIsAbsent() {
        let json = #"{"five_hour":{"resets_at":1792000000},"seven_day":{"used_percentage":5}}"#
        let q = ClaudeStatusLine.parseQuota(Data(json.utf8), capturedAt: capturedAt)
        XCTAssertNil(q?.fiveHour, "no used_percentage ⇒ not a 0%, just absent")
        XCTAssertEqual(q?.sevenDay?.usedPercent, 5)
    }

    func testParseQuotaEmptyObjectIsNil() {
        XCTAssertNil(ClaudeStatusLine.parseQuota(Data("{}".utf8), capturedAt: capturedAt))
    }

    func testParseQuotaGarbageIsNil() {
        XCTAssertNil(ClaudeStatusLine.parseQuota(Data("not json".utf8), capturedAt: capturedAt))
        XCTAssertNil(ClaudeStatusLine.parseQuota(Data("[1,2,3]".utf8), capturedAt: capturedAt), "a JSON array, not an object")
        XCTAssertNil(ClaudeStatusLine.parseQuota(Data("42".utf8), capturedAt: capturedAt))
        XCTAssertNil(ClaudeStatusLine.parseQuota(Data(), capturedAt: capturedAt), "empty data")
    }

    func testParseQuotaResetsAtIsEpochSeconds() throws {
        // 1792000000 s since epoch, NOT ms — a common unit bug. Confirm the resulting Date lands in 2026, not 1970.
        let json = #"{"five_hour":{"used_percentage":1,"resets_at":1792000000}}"#
        let q = try XCTUnwrap(ClaudeStatusLine.parseQuota(Data(json.utf8), capturedAt: capturedAt))
        let year = Calendar(identifier: .gregorian).component(.year, from: try XCTUnwrap(q.fiveHour?.resetsAt))
        XCTAssertEqual(year, 2026)
    }

    // MARK: isCurrent

    func testIsCurrent() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        XCTAssertTrue(ClaudeStatusLine.isCurrent(.init(usedPercent: 1, resetsAt: now.addingTimeInterval(1)), now: now))
        XCTAssertFalse(ClaudeStatusLine.isCurrent(.init(usedPercent: 1, resetsAt: now.addingTimeInterval(-1)), now: now), "resetsAt already passed")
        XCTAssertTrue(ClaudeStatusLine.isCurrent(.init(usedPercent: 1, resetsAt: nil), now: now), "no resetsAt at all ⇒ treated as current")
    }

    // MARK: - P2 review: a previous value of ANY JSON type survives install → remove

    func testANonObjectStatusLineIsSavedVerbatimAndRestored() throws {
        let scriptPath = "/Users/me/Library/Application Support/XFinder/Agents/claude/bin/xfinder-claude-statusline.sh"
        for legacy: Any in ["my-script.sh", 3, ["a", "b"], NSNull()] {
            let settings: [String: Any] = ["statusLine": legacy, "model": "opus"]
            let install = ClaudeStatusLine.installing(settings, scriptPath: scriptPath)
            XCTAssertTrue(ClaudeStatusLine.jsonEqual(install.previous, legacy), "the old value is kept, whatever its type: \(legacy)")
            XCTAssertNil(install.previousCommand, "nothing to chain to")
            XCTAssertTrue(ClaudeStatusLine.isOurs(install.settings["statusLine"], scriptPath: scriptPath))
            let data = try ClaudeStatusLine.encodePrevious(try XCTUnwrap(install.previous))
            let decoded = ClaudeStatusLine.decodePrevious(data)
            XCTAssertTrue(ClaudeStatusLine.jsonEqual(decoded, legacy), "survives the file round trip")
            let removed = ClaudeStatusLine.removing(install.settings, scriptPath: scriptPath, previous: decoded)
            XCTAssertTrue(ClaudeStatusLine.jsonEqual(removed["statusLine"], legacy), "Gỡ puts back exactly what was there")
            XCTAssertEqual(removed["model"] as? String, "opus")
        }
    }

    func testAnUnreadableSaveIsReportedNotTakenAsNothing() {
        XCTAssertNil(ClaudeStatusLine.decodePrevious(Data("{\"statusLine\": ".utf8)), "truncated")
        XCTAssertNil(ClaudeStatusLine.decodePrevious(Data("not json".utf8)))
        XCTAssertNil(ClaudeStatusLine.decodePrevious(Data("{\"type\": \"command\"}".utf8)), "a bare object is not a save")
        XCTAssertNil(ClaudeStatusLine.decodePrevious(Data("{\"statusLine\": 1, \"x\": 2}".utf8)), "exactly one key")
        let dict: [String: Any] = ["type": "command", "command": "'/a b.sh'", "padding": 2]
        XCTAssertTrue(ClaudeStatusLine.jsonEqual(ClaudeStatusLine.decodePrevious(try! ClaudeStatusLine.encodePrevious(dict)), dict))
    }
}
