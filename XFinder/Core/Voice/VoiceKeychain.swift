import Foundation
import Security

/// Stores provider API keys in the login keychain.
///
/// The rule from the brief — and from the app's own privacy promise — is that a key is never
/// written to `UserDefaults`, a config file, or a log. `UserDefaults` is a plist that any
/// process running as the user can read and that ends up in backups; the keychain is the
/// platform's own answer to this and is the only place a secret belongs.
///
/// This file is deliberately the *only* place that touches `SecItem*`, so an audit is one
/// file long.
public enum VoiceKeychain {
    public static let service = "com.xfinder.app.voice"

    /// Reads a key. Returns `nil` for "no key stored" and for "keychain unavailable" alike:
    /// both mean the provider cannot be used, and the UI treats them the same way.
    public static func apiKey(for kind: APIProviderKind) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    public static func hasKey(for kind: APIProviderKind) -> Bool {
        apiKey(for: kind)?.isEmpty == false
    }

    /// Stores (or replaces) a key. An empty value deletes it, so clearing the field in the
    /// UI genuinely removes the secret rather than storing an empty string.
    @discardableResult
    public static func setAPIKey(_ key: String, for kind: APIProviderKind) -> Bool {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return deleteAPIKey(for: kind) }

        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.keychainAccount,
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
    public static func deleteAPIKey(for kind: APIProviderKind) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// A value safe to show in the UI: never the key, only its last four characters.
    public static func maskedKey(for kind: APIProviderKind) -> String? {
        guard let key = apiKey(for: kind), !key.isEmpty else { return nil }
        let tail = key.suffix(4)
        return "••••••••\(tail)"
    }
}
