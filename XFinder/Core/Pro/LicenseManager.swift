import Foundation
import Observation
import Security

/// XF-T29 — the app's tier, the 14-day trial and the licence key. The ONE reader of `pro.trialStart`, `pro.maxSeenDate`
/// and `pro.simulateTier`; every gate asks `allows`/`limit` here.
///
/// Owner 2026-10-24: "build ở đây thì cứ build full; sau khi final release mới free/pro" — a development (DEBUG) build is
/// never limited, unless `pro.simulateTier` is set to try the gates ("free" | "trial" | "pro").
@MainActor
@Observable
final class LicenseManager {
    static let shared = LicenseManager()

    private(set) var tier: ProTier = .pro
    private(set) var licensee: String?

    private init() { refresh() }

    /// The ONE reader of `pro.simulateTier` (DEBUG only; "" = not simulating).
    private static var simulatedTier: String {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "pro.simulateTier") ?? ""
        #else
        return ""
        #endif
    }

    /// Limits apply in a release build, or in a development build that simulates a tier.
    var isEnforced: Bool {
        #if DEBUG
        return !Self.simulatedTier.isEmpty
        #else
        return true
        #endif
    }

    func allows(_ feature: ProFeature) -> Bool { Entitlement.allows(feature, tier: tier) }
    func limit(_ limit: ProLimit) -> Int? { Entitlement.limit(limit, tier: tier) }

    /// Launch and didBecomeActive: starts the trial on the first launch, remembers the latest time seen (a clock set back
    /// does not extend the trial), re-reads the licence.
    func refresh() {
        let d = UserDefaults.standard
        let now = Date()
        // The ONE reader of `pro.trialStart` (seconds since 1970; 0 = no trial yet).
        var trialStart = d.object(forKey: "pro.trialStart") as? Double ?? 0
        if trialStart == 0 {
            trialStart = now.timeIntervalSince1970
            d.set(trialStart, forKey: "pro.trialStart")
        }
        // The ONE reader of `pro.maxSeenDate` (seconds since 1970; 0 = never).
        let maxSeen = max(d.object(forKey: "pro.maxSeenDate") as? Double ?? 0, now.timeIntervalSince1970)
        d.set(maxSeen, forKey: "pro.maxSeenDate")

        let payload = Self.storedKey().flatMap { key in LicenseKey.publicKeyRaw.flatMap { LicenseKey.verify(key, publicKey: $0) } }
        licensee = payload?.licensee

        switch Self.simulatedTier {
        case "free": tier = .free
        case "trial":
            tier = Entitlement.tier(enforced: true, licenseValid: false, trialStart: Date(timeIntervalSince1970: trialStart),
                                    now: now, maxSeen: Date(timeIntervalSince1970: maxSeen))
        case "pro": tier = .pro
        default:
            tier = Entitlement.tier(enforced: isEnforced, licenseValid: payload != nil,
                                    trialStart: Date(timeIntervalSince1970: trialStart), now: now,
                                    maxSeen: Date(timeIntervalSince1970: maxSeen))
        }
    }

    /// Checks the signature offline; a valid key is kept in the app's own Keychain item.
    @discardableResult
    func activate(_ key: String) -> Bool {
        guard let pub = LicenseKey.publicKeyRaw, LicenseKey.verify(key, publicKey: pub) != nil else { return false }
        Self.storeKey(key.filter { !$0.isWhitespace })
        refresh()
        return true
    }

    func deactivate() {
        Self.deleteKey()
        refresh()
    }

    // MARK: Keychain — the app's own generic-password item, never anyone else's

    private static let service = "com.xfinder.app.license"
    private static let account = "XFinder Pro"

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private static func storedKey() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func storeKey(_ key: String) {
        deleteKey()
        var q = query()
        q[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func deleteKey() {
        SecItemDelete(query() as CFDictionary)
    }
}
