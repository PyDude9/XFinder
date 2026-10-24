import Foundation
import CryptoKit

/// XF-T29 — an offline-checkable licence (symlinked into the test package). The owner signs a small JSON payload with an
/// Ed25519 private key that never leaves their Mac (`scripts/make-license.swift`); the app checks the signature against
/// the public key compiled in. No network, no account, nothing to phone home.
struct LicensePayload: Codable, Equatable, Sendable {
    let id: String
    let licensee: String
    let edition: String
    let issued: Date
}

enum LicenseKey {
    static let prefix = "XF1-"

    /// The owner's Ed25519 public key (32 raw bytes), pasted in after `make-license.swift init` (Q-PRO-5). nil ⇒ every
    /// key is invalid; the 14-day trial still works, and development builds are full anyway.
    static let publicKeyRaw: Data? = nil

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// "XF1-" + base64url(payload JSON) + "." + base64url(64-byte signature over the payload bytes).
    static func make(payload: LicensePayload, privateKey: Data) -> String? {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey),
              let json = try? encoder().encode(payload),
              let signature = try? key.signature(for: json) else { return nil }
        return prefix + base64url(json) + "." + base64url(signature)
    }

    /// The payload when `text` is a well-formed key whose signature verifies with `publicKey`; nil for anything else
    /// (a typo, one changed character, another product's key, a pasted e-mail around it is tolerated only as spaces and
    /// line breaks).
    static func verify(_ text: String, publicKey: Data) -> LicensePayload? {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.hasPrefix(prefix) else { return nil }
        let body = compact.dropFirst(prefix.count)
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let json = unbase64url(String(parts[0])), let signature = unbase64url(String(parts[1])),
              signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: json) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LicensePayload.self, from: json)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func unbase64url(_ text: String) -> Data? {
        guard !text.isEmpty, text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
