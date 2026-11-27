import Foundation
import Security

/// Account-scoped secret storage contract for Revenue connectors.
/// Secrets are strictly isolated by `(RevenueSourceKind, accountId)` and are never persisted in `UserDefaults` or logs.
public protocol RevenueCredentialStore: Sendable {
    func token(for source: RevenueSourceKind, accountId: String) -> String?
    @discardableResult
    func setToken(_ token: String, for source: RevenueSourceKind, accountId: String) -> Bool
    @discardableResult
    func deleteToken(for source: RevenueSourceKind, accountId: String) -> Bool
    func maskedToken(for source: RevenueSourceKind, accountId: String) -> String?
}

public extension RevenueCredentialStore {
    func hasToken(for source: RevenueSourceKind, accountId: String) -> Bool {
        token(for: source, accountId: accountId)?.isEmpty == false
    }

    func maskedToken(for source: RevenueSourceKind, accountId: String) -> String? {
        guard let value = token(for: source, accountId: accountId), !value.isEmpty else { return nil }
        let tail = value.suffix(4)
        return "••••••••\(tail)"
    }
}

/// Login Keychain implementation for Stripe & Shopify read-only tokens.
/// This file is the single place that touches `SecItem*` for Revenue credentials.
public final class RevenueKeychainStore: RevenueCredentialStore, Sendable {
    public static let shared = RevenueKeychainStore()
    public let service: String

    public init(service: String = "com.xfinder.app.revenue") {
        self.service = service
    }

    public static func keychainAccount(for source: RevenueSourceKind, accountId: String) -> String? {
        let trimmed = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        if source == .shopify, let canonicalHost = RevenueHostPolicy.normalizedShopifyHost(from: trimmed) {
            return "\(source.rawValue):\(canonicalHost)"
        }
        return "\(source.rawValue):\(trimmed)"
    }

    public func token(for source: RevenueSourceKind, accountId: String) -> String? {
        guard let account = Self.keychainAccount(for: source, accountId: accountId) else { return nil }
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
    public func setToken(_ token: String, for source: RevenueSourceKind, accountId: String) -> Bool {
        guard let account = Self.keychainAccount(for: source, accountId: accountId) else { return false }
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return deleteToken(for: source, accountId: accountId)
        }
        guard let data = value.data(using: .utf8) else { return false }
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
    public func deleteToken(for source: RevenueSourceKind, accountId: String) -> Bool {
        guard let account = Self.keychainAccount(for: source, accountId: accountId) else { return true }
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
public final class InMemoryRevenueCredentialStore: RevenueCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String] = [:]

    public init(initial: [String: String] = [:]) {
        self.tokens = initial
    }

    public func token(for source: RevenueSourceKind, accountId: String) -> String? {
        guard let key = RevenueKeychainStore.keychainAccount(for: source, accountId: accountId) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return tokens[key]
    }

    @discardableResult
    public func setToken(_ token: String, for source: RevenueSourceKind, accountId: String) -> Bool {
        guard let key = RevenueKeychainStore.keychainAccount(for: source, accountId: accountId) else { return false }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); defer { lock.unlock() }
        if trimmed.isEmpty {
            tokens.removeValue(forKey: key)
        } else {
            tokens[key] = trimmed
        }
        return true
    }

    @discardableResult
    public func deleteToken(for source: RevenueSourceKind, accountId: String) -> Bool {
        guard let key = RevenueKeychainStore.keychainAccount(for: source, accountId: accountId) else { return true }
        lock.lock(); defer { lock.unlock() }
        tokens.removeValue(forKey: key)
        return true
    }
}

/// Persists non-secret `SourceAccountConfig` metadata in `UserDefaults`.
/// Starts empty (disconnected) by default and never stores API keys or access tokens.
public final class UserDefaultsRevenueAccountStore: RevenueAccountStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "xfinder.revenue.accounts.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func loadConfigs() -> [RevenueSourceKind: SourceAccountConfig] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SourceAccountConfig].self, from: data) else {
            return [:]
        }
        var result: [RevenueSourceKind: SourceAccountConfig] = [:]
        for item in decoded {
            result[item.source] = item
        }
        return result
    }

    public func saveConfig(_ config: SourceAccountConfig) {
        var current = loadConfigs()
        current[config.source] = config
        persist(current)
    }

    public func removeConfig(for source: RevenueSourceKind) {
        var current = loadConfigs()
        current.removeValue(forKey: source)
        persist(current)
    }

    public func clearAll() {
        defaults.removeObject(forKey: key)
    }

    private func persist(_ configs: [RevenueSourceKind: SourceAccountConfig]) {
        let ordered = RevenueSourceKind.allCases.compactMap { configs[$0] }
        if ordered.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(ordered) else { return }
        defaults.set(data, forKey: key)
    }
}
