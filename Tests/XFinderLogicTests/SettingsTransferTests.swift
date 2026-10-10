import XCTest
import Foundation

final class SettingsTransferTests: XCTestCase {

    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func export(_ dict: [String: Any]) throws -> SettingsTransfer.ExportResult {
        try SettingsTransfer.export(defaults: dict, appVersion: "1.1.0", date: Date(timeIntervalSince1970: 0))
    }

    func testRoundTripPreservesEveryKindAndItsType() throws {
        let src = suite("xf.test.src"); let dst = suite("xf.test.dst")
        src.set(true, forKey: "snapzones.enabled")
        src.set(false, forKey: "clipboard.cleanURLs")
        src.set(300, forKey: "clipboard.autoClearSeconds")
        src.set(15.5, forKey: "snapzones.edgeMargin")
        src.set("english", forKey: "AppLanguage")
        src.set(Data("{\"debug\":true}".utf8), forKey: "mouseGestures.configuration.v1")
        let out = try export(src.dictionaryRepresentation().filter { ["snapzones.enabled","clipboard.cleanURLs","clipboard.autoClearSeconds","snapzones.edgeMargin","AppLanguage","mouseGestures.configuration.v1"].contains($0.key) })
        XCTAssertEqual(out.exported, 6)
        guard case .success(let plan) = SettingsTransfer.parse(out.data) else { return XCTFail("round trip failed to parse") }
        SettingsTransfer.apply(plan, to: dst)
        XCTAssertEqual(dst.object(forKey: "snapzones.enabled") as? Bool, true)
        XCTAssertEqual(dst.object(forKey: "clipboard.cleanURLs") as? Bool, false, "false must stay a Bool, not become 0")
        XCTAssertEqual(dst.object(forKey: "clipboard.autoClearSeconds") as? Int, 300)
        XCTAssertEqual(dst.object(forKey: "snapzones.edgeMargin") as? Double, 15.5)
        XCTAssertEqual(dst.string(forKey: "AppLanguage"), "english")
        XCTAssertEqual(dst.data(forKey: "mouseGestures.configuration.v1"), Data("{\"debug\":true}".utf8))
    }

    func testAnIntegerValuedDoubleDoesNotTurnIntoAnInt() throws {
        let src = suite("xf.test.dbl"); src.set(3.0, forKey: "menubar.autoHideDelay")
        let out = try export(["menubar.autoHideDelay": src.object(forKey: "menubar.autoHideDelay")!])
        guard case .success(let plan) = SettingsTransfer.parse(out.data) else { return XCTFail() }
        XCTAssertEqual(plan.settings["menubar.autoHideDelay"], .double(3.0))
    }

    func testUserDataAndPerMachineStateNeverLeaveTheMachine() throws {
        let out = try export([
            "snapzones.enabled": true,
            "XFinder.netBaselineRX": 4_691_304_448, "XFinder.QuickNotes": Data("[]".utf8), "XFinder.Pinboards": Data("[]".utf8), "XFinder.ActionHistory": Data("[]".utf8),
            "NSWindow Frame foo": "1 2 3 4", "NSStatusItem Preferred Position Item-0": 454.0,
            "onboarding.completedVersion": 1, "startPage": "ports",
            "mouseGestures.triggerMigrated.v2": true, "mouseGestures.migrated.v1": true,
            "general.automationVerified": true, "menubar.guidanceShown": true,
            "SomeBlobWeDoNotKnow": Data([1, 2, 3]),
        ])
        XCTAssertEqual(out.exported, 1, "only snapzones.enabled is a portable setting")
        let text = String(decoding: out.data, as: UTF8.self)
        for banned in ["XFinder.", "NSWindow", "NSStatusItem", "onboarding", "startPage", "Migrated", "migrated", "automationVerified", "SomeBlob"] {
            XCTAssertFalse(text.contains(banned), "the export file mentions \(banned)")
        }
    }

    func testMachineSpecificPathsAreSkippedAndCounted() throws {
        let out = try export(["sync.sourcePath": "/Users/me/Documents", "sync.dest": "~/Backup", "AppLanguage": "english"])
        XCTAssertEqual(out.exported, 1)
        XCTAssertEqual(out.skippedMachineSpecific, 2, "the user is told how many were left out")
    }

    func testOnlyAllowlistedBlobsAreConfiguration() throws {
        let out = try export(["quicklinks.data": Data("[]".utf8), "XFinder.Whatever": Data("[]".utf8), "other.blob": Data([9])])
        XCTAssertEqual(out.exported, 1)
    }

    func testExportIsDeterministic() throws {
        let d: [String: Any] = ["b.key": 1, "a.key": true, "c.key": "x"]
        XCTAssertEqual(try export(d).data, try export(d).data)
        let text = String(decoding: try export(d).data, as: UTF8.self)
        XCTAssertLessThan(text.range(of: "a.key")!.lowerBound, text.range(of: "b.key")!.lowerBound, "keys are sorted")
    }

    // MARK: Import is untrusted input

    private func hostile(_ settings: [String: [String: String]]) -> Data {
        let body = settings.map { "\"\($0.key)\": {\"t\": \"\($0.value["t"]!)\", \"v\": \"\($0.value["v"]!)\"}" }.joined(separator: ",")
        return Data("{\"format\":\"xfinder-settings\",\"version\":1,\"app\":\"x\",\"exportedAt\":\"\",\"settings\":{\(body)}}".utf8)
    }

    func testACraftedFileCannotSetKeysThatExportWouldNeverWrite() {
        let file = hostile([
            "snapzones.enabled": ["t": "bool", "v": "true"],
            "startPage": ["t": "string", "v": "ports"],
            "NSStatusItem Preferred Position Item-0": ["t": "double", "v": "1"],
            "onboarding.completedVersion": ["t": "int", "v": "99"],
            "mouseGestures.migrated.v1": ["t": "bool", "v": "true"],
            "XFinder.QuickNotes": ["t": "data", "v": "W10="],
            "sync.folder": ["t": "string", "v": "/etc"],
        ])
        guard case .success(let plan) = SettingsTransfer.parse(file) else { return XCTFail("should parse") }
        XCTAssertEqual(Set(plan.settings.keys), ["snapzones.enabled"], "everything else must be refused")
        XCTAssertEqual(plan.rejected.count, 6)
        let d = suite("xf.test.hostile")
        SettingsTransfer.apply(plan, to: d)
        XCTAssertNil(d.object(forKey: "startPage"))
        XCTAssertNil(d.object(forKey: "onboarding.completedVersion"))
        XCTAssertNil(d.object(forKey: "mouseGestures.migrated.v1"))
    }

    func testMalformedValuesAreRejectedNotCoerced() {
        let file = hostile([
            "a.flag": ["t": "bool", "v": "maybe"], "a.count": ["t": "int", "v": "12x"],
            "a.ratio": ["t": "double", "v": "nan"], "a.blob": ["t": "data", "v": "%%%"],
            "a.kind": ["t": "wat", "v": "1"], "ok.flag": ["t": "bool", "v": "true"],
        ])
        guard case .success(let plan) = SettingsTransfer.parse(file) else { return XCTFail() }
        XCTAssertEqual(Set(plan.settings.keys), ["ok.flag"])
        XCTAssertEqual(plan.rejected, ["a.blob", "a.count", "a.flag", "a.kind", "a.ratio"])
    }

    func testWrongFilesAreRefusedWithAReason() {
        XCTAssertEqual(SettingsTransfer.parse(Data("not json".utf8)), .failure(.notASettingsFile))
        XCTAssertEqual(SettingsTransfer.parse(Data("{\"format\":\"something-else\",\"version\":1,\"app\":\"\",\"exportedAt\":\"\",\"settings\":{}}".utf8)), .failure(.notASettingsFile))
        XCTAssertEqual(SettingsTransfer.parse(Data(count: SettingsTransfer.maxFileBytes + 1)), .failure(.tooLarge))
        let future = Data("{\"format\":\"xfinder-settings\",\"version\":99,\"app\":\"\",\"exportedAt\":\"\",\"settings\":{\"a\":{\"t\":\"bool\",\"v\":\"true\"}}}".utf8)
        XCTAssertEqual(SettingsTransfer.parse(future), .failure(.newerThanThisApp(99)))
        let empty = Data("{\"format\":\"xfinder-settings\",\"version\":1,\"app\":\"\",\"exportedAt\":\"\",\"settings\":{}}".utf8)
        XCTAssertEqual(SettingsTransfer.parse(empty), .failure(.empty), "nothing to import is reported, not applied silently")
    }

    func testEveryFeatureSwitchIsPortable() {
        // If a feature's on/off key were classified as non-portable, "move my setup" would silently
        // lose the most important settings.
        for f in FeatureCatalog.all {
            XCTAssertEqual(SettingsTransfer.verdict(key: f.enabledKey, value: .bool(true)), .transfer, f.enabledKey)
        }
    }
}
