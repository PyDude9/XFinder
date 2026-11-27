import Foundation
import Security
import os

public enum WebsiteAnalyticsSecretKind: String, CaseIterable, Hashable, Sendable {
    case dataFastAPIKey = "datafast.apiKey"
    case ga4AccessToken = "ga4.accessToken"
    case ga4RefreshToken = "ga4.refreshToken"

    public var provider: WebsiteAnalyticsProviderKind {
        switch self {
        case .dataFastAPIKey: return .dataFast
        case .ga4AccessToken, .ga4RefreshToken: return .googleAnalytics4
        }
    }
}

/// Credential storage contract for Website Analytics providers.
/// Secrets are strictly isolated by `(WebsiteAnalyticsSecretKind, accountKey)` and never persisted
/// in `UserDefaults`, logs, error strings, or telemetry.
public protocol WebsiteAnalyticsCredentialStore: Sendable {
    func secret(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> String?
    @discardableResult
    func setSecret(_ value: String, for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> Bool
    @discardableResult
    func deleteSecret(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> Bool
}

public extension WebsiteAnalyticsCredentialStore {
    func hasSecret(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> Bool {
        secret(for: kind, accountKey: accountKey)?.isEmpty == false
    }

    func maskedSecret(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> String? {
        guard let value = secret(for: kind, accountKey: accountKey), !value.isEmpty else { return nil }
        let tail = value.suffix(4)
        return "••••••••\(tail)"
    }

    @discardableResult
    func deleteAllSecrets(for provider: WebsiteAnalyticsProviderKind, accountKey: String) -> Bool {
        var ok = true
        for kind in WebsiteAnalyticsSecretKind.allCases where kind.provider == provider {
            if !deleteSecret(for: kind, accountKey: accountKey) {
                ok = false
            }
        }
        return ok
    }
}

/// Login Keychain implementation for Website Analytics secrets.
/// This file is the single place that touches `SecItem*` for Website Analytics.
public final class WebsiteAnalyticsKeychainStore: WebsiteAnalyticsCredentialStore, Sendable {
    public static let shared = WebsiteAnalyticsKeychainStore()
    public let service: String

    public init(service: String = "com.xfinder.app.website-analytics") {
        self.service = service
    }

    public static func keychainAccount(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> String? {
        let trimmed = accountKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        return "\(kind.rawValue):\(trimmed)"
    }

    public func secret(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> String? {
        guard let account = Self.keychainAccount(for: kind, accountKey: accountKey) else { return nil }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    @discardableResult
    public func setSecret(_ value: String, for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> Bool {
        guard let account = Self.keychainAccount(for: kind, accountKey: accountKey) else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return deleteSecret(for: kind, accountKey: accountKey)
        }
        guard let data = trimmed.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        insert.merge(attributes) { _, new in new }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func deleteSecret(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> Bool {
        guard let account = Self.keychainAccount(for: kind, accountKey: accountKey) else { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Deterministic in-memory credential store for unit tests (never touches the macOS Keychain).
public final class InMemoryWebsiteAnalyticsCredentialStore: WebsiteAnalyticsCredentialStore, Sendable {
    private let storage: OSAllocatedUnfairLock<[String: String]>

    public init(initial: [String: String] = [:]) {
        self.storage = OSAllocatedUnfairLock(initialState: initial)
    }

    public func secret(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> String? {
        guard let key = WebsiteAnalyticsKeychainStore.keychainAccount(for: kind, accountKey: accountKey) else {
            return nil
        }
        return storage.withLock { $0[key] }
    }

    @discardableResult
    public func setSecret(_ value: String, for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> Bool {
        guard let key = WebsiteAnalyticsKeychainStore.keychainAccount(for: kind, accountKey: accountKey) else {
            return false
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.withLock { dict in
            if trimmed.isEmpty {
                dict.removeValue(forKey: key)
            } else {
                dict[key] = trimmed
            }
        }
        return true
    }

    @discardableResult
    public func deleteSecret(for kind: WebsiteAnalyticsSecretKind, accountKey: String) -> Bool {
        guard let key = WebsiteAnalyticsKeychainStore.keychainAccount(for: kind, accountKey: accountKey) else {
            return true
        }
        _ = storage.withLock { dict in
            dict.removeValue(forKey: key)
        }
        return true
    }

    public func allStoredKeys() -> [String] {
        storage.withLock { Array($0.keys).sorted() }
    }
}

// MARK: - Non-Secret Configuration Store

public protocol WebsiteAnalyticsConfigStore: Sendable {
    func selectedProvider() -> WebsiteAnalyticsProviderKind
    func setSelectedProvider(_ provider: WebsiteAnalyticsProviderKind)

    func loadDataFastConfig() -> DataFastSiteConfig?
    func saveDataFastConfig(_ config: DataFastSiteConfig)
    func removeDataFastConfig()

    func loadGA4Config() -> GA4PropertyConfig?
    func saveGA4Config(_ config: GA4PropertyConfig)
    func removeGA4Config()
}

/// Persists non-secret Website Analytics metadata (selected provider, site label, property ID, timezone)
/// in `UserDefaults`. Never stores API keys or OAuth tokens.
public final class UserDefaultsWebsiteAnalyticsConfigStore: WebsiteAnalyticsConfigStore, Sendable {
    public static let selectedProviderKey = "xfinder.websiteAnalytics.selectedProvider.v1"
    public static let dataFastConfigKey = "xfinder.websiteAnalytics.dataFastConfig.v1"
    public static let ga4ConfigKey = "xfinder.websiteAnalytics.ga4Config.v1"

    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        return .standard
    }

    public func selectedProvider() -> WebsiteAnalyticsProviderKind {
        guard let raw = defaults.string(forKey: Self.selectedProviderKey),
              let kind = WebsiteAnalyticsProviderKind(rawValue: raw) else {
            return .dataFast
        }
        return kind
    }

    public func setSelectedProvider(_ provider: WebsiteAnalyticsProviderKind) {
        defaults.set(provider.rawValue, forKey: Self.selectedProviderKey)
    }

    public func loadDataFastConfig() -> DataFastSiteConfig? {
        guard let data = defaults.data(forKey: Self.dataFastConfigKey) else { return nil }
        return try? JSONDecoder().decode(DataFastSiteConfig.self, from: data)
    }

    public func saveDataFastConfig(_ config: DataFastSiteConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.dataFastConfigKey)
    }

    public func removeDataFastConfig() {
        defaults.removeObject(forKey: Self.dataFastConfigKey)
    }

    public func loadGA4Config() -> GA4PropertyConfig? {
        guard let data = defaults.data(forKey: Self.ga4ConfigKey) else { return nil }
        return try? JSONDecoder().decode(GA4PropertyConfig.self, from: data)
    }

    public func saveGA4Config(_ config: GA4PropertyConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.ga4ConfigKey)
    }

    public func removeGA4Config() {
        defaults.removeObject(forKey: Self.ga4ConfigKey)
    }
}

public final class InMemoryWebsiteAnalyticsConfigStore: WebsiteAnalyticsConfigStore, Sendable {
    private struct State: Sendable {
        var selectedProvider: WebsiteAnalyticsProviderKind
        var dataFastConfig: DataFastSiteConfig?
        var ga4Config: GA4PropertyConfig?
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(
        selectedProvider: WebsiteAnalyticsProviderKind = .dataFast,
        dataFastConfig: DataFastSiteConfig? = nil,
        ga4Config: GA4PropertyConfig? = nil
    ) {
        self.state = OSAllocatedUnfairLock(
            initialState: State(
                selectedProvider: selectedProvider,
                dataFastConfig: dataFastConfig,
                ga4Config: ga4Config
            )
        )
    }

    public func selectedProvider() -> WebsiteAnalyticsProviderKind {
        state.withLock { $0.selectedProvider }
    }

    public func setSelectedProvider(_ provider: WebsiteAnalyticsProviderKind) {
        state.withLock { $0.selectedProvider = provider }
    }

    public func loadDataFastConfig() -> DataFastSiteConfig? {
        state.withLock { $0.dataFastConfig }
    }

    public func saveDataFastConfig(_ config: DataFastSiteConfig) {
        state.withLock { $0.dataFastConfig = config }
    }

    public func removeDataFastConfig() {
        state.withLock { $0.dataFastConfig = nil }
    }

    public func loadGA4Config() -> GA4PropertyConfig? {
        state.withLock { $0.ga4Config }
    }

    public func saveGA4Config(_ config: GA4PropertyConfig) {
        state.withLock { $0.ga4Config = config }
    }

    public func removeGA4Config() {
        state.withLock { $0.ga4Config = nil }
    }
}
