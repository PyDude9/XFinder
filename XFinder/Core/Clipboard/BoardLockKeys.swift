import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// D4 "Bảng khoá" — Piece B: the Secure Enclave key lifecycle and the real file I/O that
/// `BoardLock` (Piece A, Foundation + CryptoKit only) plans against through `BoardLock.FileOps`.
/// This file is the ONLY place that imports Security/LocalAuthentication for the lock feature —
/// `BoardLock` itself stays testable without a keychain or a biometric prompt.
///
/// Measured on this Mac (2026-10-12, macOS 27): `SecureEnclave.isAvailable == true`;
/// `SecAccessControlCreateWithFlags(kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
/// [.privateKeyUsage, .userPresence])` succeeds; `SecureEnclave.P256.KeyAgreement.PrivateKey`
/// restores from its 284-byte `dataRepresentation`; `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)
/// == true` (Touch ID configured). HPKE.Ciphersuite.P256_SHA256_AES_GCM_256 round-trips against it.
enum BoardLockKeys {
    enum Error: Swift.Error {
        case enclaveUnavailable
        case cancelled
        case authenticationFailed(String)
        case keyCreation(String)
        case keyRestore(String)
    }

    static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Creates the enclave key with access control `[.privateKeyUsage, .userPresence]`
    /// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). No prompt at creation time — the
    /// flag only gates *use* of the resulting private key, not its generation.
    static func createKey() throws -> (keyData: Data, publicKeyX963: Data) {
        guard SecureEnclave.isAvailable else { throw Error.enclaveUnavailable }

        var cfError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            &cfError
        ) else {
            let message = cfError.map { String(describing: $0.takeRetainedValue()) } ?? "SecAccessControlCreateWithFlags failed"
            throw Error.keyCreation(message)
        }

        do {
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: accessControl)
            return (keyData: key.dataRepresentation, publicKeyX963: key.publicKey.x963Representation)
        } catch {
            throw Error.keyCreation(String(describing: error))
        }
    }

    /// Restores the enclave key with a FRESH `LAContext` every call — `touchIDAuthenticationAllowableReuseDuration
    /// = 0` so a prior successful unlock is never silently reused, and each call to this function prompts on
    /// its own. `reason` is the sheet's message; the caller (the UI layer) supplies it already localized.
    static func recipient(keyData: Data, reason: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        guard SecureEnclave.isAvailable else { throw Error.enclaveUnavailable }

        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.localizedReason = reason

        do {
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keyData, authenticationContext: context)
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                throw Error.cancelled
            default:
                throw Error.authenticationFailed(String(describing: laError.code))
            }
        } catch {
            if isCancellation(error) { throw Error.cancelled }
            throw Error.keyRestore(String(describing: error))
        }
    }

    /// The user dismissing the Touch ID sheet can surface from three layers — LocalAuthentication
    /// (`LAError.userCancel`), Security (`errSecUserCanceled` as an OSStatus), or a CryptoTokenKit /
    /// CryptoKit error wrapping either — depending on whether the prompt fired at key restore or at
    /// first use inside HPKE. UNVERIFIED which one this API produces (measuring it means putting a
    /// sheet on the user's screen); recognise all three so a cancel never reads as a failure notice.
    static func isCancellation(_ error: Swift.Error) -> Bool {
        if let la = error as? LAError {
            return [.userCancel, .appCancel, .systemCancel].contains(la.code)
        }
        let ns = error as NSError
        if ns.domain == LAError.errorDomain, [LAError.userCancel.rawValue, LAError.appCancel.rawValue, LAError.systemCancel.rawValue].contains(ns.code) { return true }
        if ns.domain == NSOSStatusErrorDomain, ns.code == Int(errSecUserCanceled) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying !== ns { return isCancellation(underlying) }
        return ns.localizedDescription.lowercased().contains("cancel")
    }

    /// `<Application Support>/XFinder/Clipboard/Locked`, created `0700` on first use. Sibling of
    /// `ClipboardPayloadStore.baseDir()` (`.../XFinder/Clipboard`), kept in its own subdirectory so a
    /// plain directory listing of the Clipboard folder does not mix sealed and plain files.
    static func lockedDir() -> String {
        let fm = FileManager.default
        let base = ClipboardPayloadStore.baseDir()
        let dir = base.appendingPathComponent("Locked", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            // Directory may already exist from an older run without the restricted mode; tighten it.
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        return dir.path
    }

    /// Real `FileOps` over `FileManager`. Every write is `0600` (owner read/write only) — sealed
    /// envelopes and payloads hold ciphertext, but the file's own permissions are a second,
    /// independent fence against another local account reading them off disk.
    // Computed, not stored: FileOps holds closures and is not Sendable, so a stored global would be shared mutable state to Swift 6.
    static var fileOps: BoardLock.FileOps { BoardLock.FileOps(
        read: { path in
            try Data(contentsOf: URL(fileURLWithPath: path))
        },
        write: { data, path in
            let fm = FileManager.default
            let url = URL(fileURLWithPath: path)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        },
        remove: { path in
            let fm = FileManager.default
            guard fm.fileExists(atPath: path) else { return }
            try fm.removeItem(atPath: path)
        },
        exists: { path in
            FileManager.default.fileExists(atPath: path)
        }
    ) }
}
