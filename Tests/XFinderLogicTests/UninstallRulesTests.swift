import XCTest
import Foundation

/// F2 — the fixtures are the names six real apps left in this Mac's ~/Library (measured 2026-10-13, names only).
final class UninstallRulesTests: XCTestCase {
    typealias U = Uninstall

    let keka = U.AppInfo(path: "/Applications/Keka.app", bundleID: "com.aone.keka", name: "Keka")
    let wireguard = U.AppInfo(path: "/Applications/WireGuard.app", bundleID: "com.wireguard.macos", name: "WireGuard")
    let sentinel = U.AppInfo(path: "/Applications/Sentinel.app", bundleID: "com.alienator88.Sentinel", name: "Sentinel")

    /// A slice of the real Library, plus names that must NOT match.
    let library: [U.Location: [String]] = [
        .applicationSupport: ["Sentinel", "com.aone.keka.backup", "Google", "SentinelPro"],
        .caches: ["com.alienator88.Sentinel", "com.aone.kekaX"],
        .preferences: ["com.aone.keka.plist", "com.alienator88.Sentinel.plist", "com.pyrolyse.Fluor.plist", "com.aone.kek.plist"],
        .byHostPreferences: ["com.aone.keka.8F2B5A1C-0000-4000-8000-000000000000.plist"],
        .containers: ["com.aone.keka", "com.aone.keka.KekaFinderIntegration", "com.wireguard.macos", "com.wireguard.macos.network-extension",
                      "com.wireguard.macos.login-item-helper", "com.alienator88.Sentinel"],
        .groupContainers: ["4FG648TM2A.group.com.aone.keka", "L82V4Y2P3C.group.com.wireguard.macos", "group.com.alienator88.Sentinel",
                           "4FG648TM2A.group.com.aone.kekaplus", "4FG648TM2A.group.notcom.aone.keka"],
        .applicationScripts: ["com.aone.keka", "com.aone.keka.KekaFinderIntegration"],
        .httpStorages: ["com.alienator88.Sentinel"],
        .launchAgents: ["com.aone.keka.helper.plist", "com.other.agent.plist"],
    ]

    func plan(_ app: U.AppInfo, installed: [String] = []) -> [String] {
        U.plan(app: app, listing: { library[$0] ?? [] }, installed: installed).map { "\($0.location.rawValue)/\($0.fileName) [\($0.match.rawValue)]" }
    }

    func testKekaLeftoversAsMeasured() {
        XCTAssertEqual(plan(keka), [
            "Application Support/com.aone.keka.backup [helper]",
            "Preferences/com.aone.keka.plist [exact]",
            "Preferences/ByHost/com.aone.keka.8F2B5A1C-0000-4000-8000-000000000000.plist [exact]",
            "Containers/com.aone.keka [exact]",
            "Containers/com.aone.keka.KekaFinderIntegration [helper]",
            "Group Containers/4FG648TM2A.group.com.aone.keka [group]",
            "Application Scripts/com.aone.keka [exact]",
            "Application Scripts/com.aone.keka.KekaFinderIntegration [helper]",
            "LaunchAgents/com.aone.keka.helper.plist [launchAgent]",
        ])
    }

    func testANamePrefixIsNotAMatch() {
        let all = plan(keka).joined(separator: "\n")
        XCTAssertFalse(all.contains("com.aone.kekaX"), "only <bid> or <bid>.<more>, never <bid><more>")
        XCTAssertFalse(all.contains("com.aone.kek.plist"))
        XCTAssertFalse(all.contains("kekaplus"))
        XCTAssertFalse(all.contains("notcom"), "a group name must end in \".<bid>\", not just in <bid>")
    }

    func testWireGuardHelpersAndGroup() {
        XCTAssertEqual(plan(wireguard), [
            "Containers/com.wireguard.macos [exact]",
            "Containers/com.wireguard.macos.login-item-helper [helper]",
            "Containers/com.wireguard.macos.network-extension [helper]",
            "Group Containers/L82V4Y2P3C.group.com.wireguard.macos [group]",
        ])
    }

    func testAFolderNamedAfterTheAppIsAGuessAndStartsUnticked() {
        let c = U.plan(app: sentinel, listing: { library[$0] ?? [] }, installed: [])
        let byName = c.first { $0.match == .name }
        XCTAssertEqual(byName?.fileName, "Sentinel")
        XCTAssertEqual(byName?.selectedByDefault, false)
        XCTAssertFalse(c.contains { $0.fileName == "SentinelPro" })
        XCTAssertEqual(c.first { $0.location == .preferences }?.selectedByDefault, true)
    }

    func testProtectedLocationsStartUnticked() {
        for c in U.plan(app: keka, listing: { library[$0] ?? [] }, installed: []) where c.location.isProtected {
            XCTAssertFalse(c.selectedByDefault, "\(c.location.rawValue)/\(c.fileName): XFinder cannot move it (measured 513)")
        }
        XCTAssertTrue(U.Location.containers.isProtected)
        XCTAssertFalse(U.Location.applicationSupport.isProtected)
        XCTAssertEqual(U.Location.allCases.filter(\.alwaysRefused), [.containers], "only what was measured is called always refused")
    }

    func testAnotherInstalledAppsFilesAreNeverOffered() {
        let chrome = U.AppInfo(path: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome", name: "Google Chrome")
        let lib: [U.Location: [String]] = [.containers: ["com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.canary.helper",
                                                         "com.google.Chrome.helper"]]
        let c = U.plan(app: chrome, listing: { lib[$0] ?? [] }, installed: ["com.google.Chrome", "com.google.Chrome.canary"]).map(\.fileName)
        XCTAssertEqual(c, ["com.google.Chrome", "com.google.Chrome.helper"])
    }

    func testRefusals() {
        let own = "com.xfinder.app"
        XCTAssertEqual(U.refusal(.init(path: "/Applications/Safari.app", bundleID: "com.apple.Safari", name: "Safari"), ownBundleID: own, running: []), .apple)
        XCTAssertEqual(U.refusal(.init(path: "/System/Applications/Foo.app", bundleID: "com.foo", name: "Foo"), ownBundleID: own, running: []), .system)
        XCTAssertEqual(U.refusal(.init(path: "/Applications/XFinder.app", bundleID: own, name: "XFinder"), ownBundleID: own, running: []), .itself)
        XCTAssertEqual(U.refusal(keka, ownBundleID: own, running: ["com.aone.keka"]), .running)
        XCTAssertEqual(U.refusal(.init(path: "/Applications/Foo", bundleID: "com.foo", name: "Foo"), ownBundleID: own, running: []), .notAnApp)
        XCTAssertEqual(U.refusal(.init(path: "/Applications/Foo.app", bundleID: "", name: "Foo"), ownBundleID: own, running: []), .notAnApp)
        XCTAssertNil(U.refusal(keka, ownBundleID: own, running: []))
    }

    func testErrorsReadAsTheUserCanActOnThem() {
        XCTAssertEqual(U.outcome(domain: NSCocoaErrorDomain, code: 513, message: "x"), .protected, "the measured container refusal")
        XCTAssertEqual(U.outcome(domain: NSPOSIXErrorDomain, code: Int(EPERM), message: "x"), .protected)
        XCTAssertEqual(U.outcome(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, message: "x"), .missing)
        XCTAssertEqual(U.outcome(domain: NSCocoaErrorDomain, code: 640, message: "disk full"), .failed("disk full"))
    }

    func testBaseNames() {
        XCTAssertEqual(U.baseName("com.foo.App.plist"), "com.foo.App")
        XCTAssertEqual(U.baseName("com.foo.App.savedState"), "com.foo.App")
        XCTAssertEqual(U.baseName("com.foo.App.binarycookies"), "com.foo.App")
        XCTAssertEqual(U.baseName(".plist"), ".plist")
        XCTAssertEqual(U.baseName("com.foo.App"), "com.foo.App")
    }
}
