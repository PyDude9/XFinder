import Foundation
import CryptoKit

/// D4 "Bảng khoá" — sealing and opening clips that belong to a LOCKED pinboard.
///
/// Foundation + CryptoKit only: no AppKit, no Security, no LocalAuthentication. The Secure Enclave
/// key itself (creation, Touch-ID-gated restoration, real file I/O) lives in `BoardLockKeys.swift`,
/// which is why every function here is generic over `some HPKEDiffieHellmanPrivateKey` — this file
/// never asks "is this key allowed to be used right now", it only knows how to seal/open bytes once
/// it has been handed a key, and how to plan which files move where. That split is what makes the
/// crypto and file-layout rules below testable with a plain software `P256.KeyAgreement.PrivateKey`
/// and an in-memory `FileOps`, with no Touch ID prompt anywhere in the test run.
///
/// ## Blob format
///
/// `seal(_:publicKeyX963:)` produces:
///
/// ```
/// [0]        version byte, 0x01
/// [1...65]   HPKE encapsulated key (X9.63 uncompressed P-256 point, 65 bytes)
/// [66...]    HPKE AEAD ciphertext (plaintext.count + 16 bytes — AES-256-GCM's 16-byte tag)
/// ```
///
/// The version byte exists so a future format change can be told apart from this one without
/// guessing from length; `open` rejects anything that is not exactly `0x01` as `.badBlob` rather
/// than attempting to decapsulate garbage. The HPKE suite is `P256_SHA256_AES_GCM_256`, measured on
/// this machine to round-trip with a 65-byte encapsulated key and a 16-byte AEAD expansion (see
/// CLAUDE.md "MEASURED ON THIS MAC" note for this feature) — sealing therefore produces a blob
/// exactly `1 + 65 + plaintext.count + 16` bytes long, and `seal`/`open` do not need per-call nonce
/// bookkeeping: HPKE derives the nonce from the encapsulated shared secret, and a fresh sender
/// context is created for every `seal`, so there is no nonce-reuse risk even though the same public
/// key is used to seal many clips over the board's lifetime.
///
/// ## What leaves the row, and why only flags stay
///
/// A locked clip's content must not be readable from the SQLite row or from the plain files on disk
/// — that is the whole point of "someone copies xfinder.db cannot read them". So everything that
/// carries the clip's CONTENT (`textSnippet`, `ocrText`, the payload/thumbnail files, and any
/// metadata that describes the content — `customTitle`, `url`, `path`, `dimensions`, or anything
/// else not in `keptMetadataKeys`) is moved into the `Envelope` and sealed. What stays on the row is
/// only what the clipboard UI needs to RENDER THE LIST without decrypting anything: `isPinned`,
/// `usageCount`, `isSaved` are counters/flags, not content, plus the two lock keys that mark the row
/// as sealed and say which board it belongs to. `type`, `timestamp`, `sourceBundleID`/`sourceAppName`
/// are not metadata entries at all (they are top-level `ClipboardRecord` fields) and are deliberately
/// never touched by `lock`/`unlock` — a locked row still sorts, groups, and shows its source app icon
/// exactly like a plain one. This is the honesty-rule boundary for this feature: a flag is not
/// content, so keeping it is not a lock that "mostly" works.
///
/// ## The fence
///
/// `fenced(_:)` is the single place every "this reader cannot unlock anything" call site goes
/// through (MCP server, `.xfinderclip` export) to drop locked rows before the data leaves XFinder's
/// process. It is intentionally a static pure filter so both fences call the exact same rule instead
/// of each re-deriving "is this safe to hand out" from `ClipboardRecord` by hand.
enum BoardLock {
    static let suite: HPKE.Ciphersuite = .P256_SHA256_AES_GCM_256
    static let info: Data = Data("xfinder.board-lock.v1".utf8)

    /// `ClipboardRecord.metadata` key marking a row as sealed. Value is always the string `"1"`.
    static let lockedFlagKey = "locked"
    /// `ClipboardRecord.metadata` key holding the owning board's UUID string.
    static let lockedBoardKey = "lockedBoard"
    /// L10n key for where a preview would be shown (card bodies, inspector placeholders, …). This
    /// file never calls `L10n.t` itself — it is Foundation-only — but exposes the Vietnamese literal
    /// as the single source of truth for the key, the same pattern every other Core file in this
    /// module (`ClipboardFilterToken`, `ClipboardLibraryRules`) already uses for UI-facing keys that
    /// originate in Core.
    static let placeholderKey = "Đã khoá"
    /// File extension for a sealed envelope: `<id>.env`.
    static let envelopeExtension = "env"

    private static let blobVersion: UInt8 = 0x01
    private static let encapsulatedKeyLength = 65

    enum Error: Swift.Error, Equatable {
        /// The blob is too short, has an unknown version byte, or otherwise cannot be a sealed blob.
        case badBlob
        /// The blob parsed, but the supplied key could not open it (wrong key, or corrupted AEAD
        /// ciphertext — HPKE's authenticated encryption cannot tell those apart, which is correct:
        /// a decryption oracle that distinguishes "wrong key" from "tampered ciphertext" is a bug).
        case wrongKey
        /// `unlock`/`restorePlain` was asked to act on a row that is not locked.
        case notLocked
        /// `lock` was asked to act on a row that is already locked.
        case alreadyLocked
        /// A file `lock`/`unlock` needed to read does not exist. Associated value is the path.
        case missingFile(String)
    }

    // MARK: - Seal / open primitives

    /// Seals `plain` to `publicKeyX963` (65-byte X9.63 uncompressed P-256 point). No key material is
    /// needed beyond the public key, so this never prompts — it is what runs on every capture into a
    /// locked board.
    static func seal(_ plain: Data, publicKeyX963: Data) throws -> Data {
        let publicKey: P256.KeyAgreement.PublicKey
        do {
            publicKey = try P256.KeyAgreement.PublicKey(x963Representation: publicKeyX963)
        } catch {
            throw Error.badBlob
        }
        var sender: HPKE.Sender
        let ciphertext: Data
        do {
            sender = try HPKE.Sender(recipientKey: publicKey, ciphersuite: suite, info: info)
            ciphertext = try sender.seal(plain)
        } catch {
            throw Error.badBlob
        }
        var blob = Data(capacity: 1 + sender.encapsulatedKey.count + ciphertext.count)
        blob.append(blobVersion)
        blob.append(sender.encapsulatedKey)
        blob.append(ciphertext)
        return blob
    }

    /// Opens a blob produced by `seal(_:publicKeyX963:)`. Generic over the recipient's private-key
    /// type so tests use a software `P256.KeyAgreement.PrivateKey` and the shipped app uses
    /// `SecureEnclave.P256.KeyAgreement.PrivateKey` — both conform to `HPKEDiffieHellmanPrivateKey`.
    static func open(_ blob: Data, with recipient: some HPKEDiffieHellmanPrivateKey) throws -> Data {
        guard blob.count > 1 + encapsulatedKeyLength else { throw Error.badBlob }
        guard blob.first == blobVersion else { throw Error.badBlob }
        let body = blob.dropFirst()
        let encapsulatedKey = Data(body.prefix(encapsulatedKeyLength))
        let ciphertext = Data(body.dropFirst(encapsulatedKeyLength))
        do {
            var hpkeRecipient = try HPKE.Recipient(
                privateKey: recipient,
                ciphersuite: suite,
                info: info,
                encapsulatedKey: encapsulatedKey
            )
            return try hpkeRecipient.open(ciphertext)
        } catch is CryptoKitError {
            // CryptoKit's own failures (authenticationFailure for a wrong key or corrupted ciphertext,
            // incorrectParameterSize for a malformed encapsulated key) collapse to one outcome from
            // this module's point of view: the blob could not be opened with this key. `.badBlob` is
            // reserved for shapes detected before ever touching HPKE.
        } catch is HPKE.Errors {
            // same — HPKE's protocol-level refusals
        } catch {
            // Anything else is NOT a crypto verdict: an enclave key that demands user presence
            // reports a dismissed Touch ID sheet from here, through Security/CryptoTokenKit. Let it
            // through so the caller can tell "cancelled" from "wrong key" (BoardLockKeys.isCancellation).
            throw error
        }
        throw Error.wrongKey
    }

    // MARK: - Envelope

    /// Everything that must leave the SQLite row and the plain files when a clip is locked.
    struct Envelope: Codable, Equatable {
        var textSnippet: String?
        var ocrText: String?
        /// Every `metadata` entry NOT in `keptMetadataKeys` — e.g. `customTitle`, `url`, `path`,
        /// `dimensions`. Keyed the same as `ClipboardRecord.metadata` so restoring is a merge.
        var hiddenMetadata: [String: String]
        /// Original file name of the payload file, if the record had one, so `restorePlain` can
        /// write it back under a name that still carries its extension.
        var payloadFileName: String?
        /// Original file name of the thumbnail file, if the record had one.
        var thumbnailFileName: String?
    }

    /// Metadata keys that stay on a locked row. Everything else is content or describes content and
    /// moves into the `Envelope`. Flags only — see the type's doc comment for why that boundary is
    /// the one the honesty rule requires.
    static let keptMetadataKeys: Set<String> = ["isPinned", "usageCount", "isSaved"]

    // MARK: - File I/O seam

    /// Injected file operations so `lock`/`unlock`/`restorePlain` are pure plans over an abstract
    /// filesystem in tests, and real `FileManager` calls (0600-permission writes) in
    /// `BoardLockKeys.fileOps`.
    struct FileOps {
        var read: (String) throws -> Data
        var write: (Data, String) throws -> Void
        var remove: (String) throws -> Void
        var exists: (String) -> Bool
    }

    // MARK: - Lock

    private static func envelopePath(id: UUID, lockedDir: String) -> String {
        "\(lockedDir)/\(id.uuidString).\(envelopeExtension)"
    }

    private static func sealedPayloadPath(id: UUID, lockedDir: String) -> String {
        "\(lockedDir)/\(id.uuidString).payload"
    }

    private static func sealedThumbnailPath(id: UUID, lockedDir: String) -> String {
        "\(lockedDir)/\(id.uuidString).thumb"
    }

    /// Seals `record` for `boardID`/`publicKeyX963`, writing the sealed envelope (and sealed
    /// payload/thumbnail copies when those files exist) under `lockedDir`, and removing the plain
    /// payload/thumbnail files. Throws `.alreadyLocked` if `record.isLocked`.
    ///
    /// The returned row has `textSnippet`/`ocrText`/`thumbnailPath` cleared, `payloadPath` pointing
    /// at the sealed envelope (so `sealedFiles(of:)` / delete logic has one path to find the
    /// envelope from), and `metadata` reduced to `keptMetadataKeys` plus the two lock keys.
    static func lock(
        _ record: ClipboardRecord,
        boardID: UUID,
        publicKeyX963: Data,
        lockedDir: String,
        ops: FileOps
    ) throws -> ClipboardRecord {
        guard !record.isLocked else { throw Error.alreadyLocked }

        var hiddenMetadata: [String: String] = [:]
        var keptMetadata: [String: String] = [:]
        for (key, value) in record.metadata {
            if keptMetadataKeys.contains(key) {
                keptMetadata[key] = value
            } else {
                hiddenMetadata[key] = value
            }
        }

        var payloadFileName: String?
        if let payloadPath = record.payloadPath, ops.exists(payloadPath) {
            let plain = try ops.read(payloadPath)
            let sealed = try seal(plain, publicKeyX963: publicKeyX963)
            try ops.write(sealed, sealedPayloadPath(id: record.id, lockedDir: lockedDir))
            try ops.remove(payloadPath)
            payloadFileName = (payloadPath as NSString).lastPathComponent
        }

        var thumbnailFileName: String?
        if let thumbnailPath = record.thumbnailPath, ops.exists(thumbnailPath) {
            let plain = try ops.read(thumbnailPath)
            let sealed = try seal(plain, publicKeyX963: publicKeyX963)
            try ops.write(sealed, sealedThumbnailPath(id: record.id, lockedDir: lockedDir))
            try ops.remove(thumbnailPath)
            thumbnailFileName = (thumbnailPath as NSString).lastPathComponent
        }

        let envelope = Envelope(
            textSnippet: record.textSnippet,
            ocrText: record.ocrText,
            hiddenMetadata: hiddenMetadata,
            payloadFileName: payloadFileName,
            thumbnailFileName: thumbnailFileName
        )
        let envelopeData = try JSONEncoder().encode(envelope)
        let sealedEnvelope = try seal(envelopeData, publicKeyX963: publicKeyX963)
        let envPath = envelopePath(id: record.id, lockedDir: lockedDir)
        try ops.write(sealedEnvelope, envPath)

        keptMetadata[lockedFlagKey] = "1"
        keptMetadata[lockedBoardKey] = boardID.uuidString

        return ClipboardRecord(
            id: record.id,
            type: record.type,
            timestamp: record.timestamp,
            sourceBundleID: record.sourceBundleID,
            sourceAppName: record.sourceAppName,
            textSnippet: nil,
            thumbnailPath: nil,
            payloadPath: envPath,
            ocrText: nil,
            pinboardID: record.pinboardID,
            metadata: keptMetadata
        )
    }

    // MARK: - Unlock

    /// In-memory result of opening a locked clip. Nothing here is ever written back to disk by this
    /// function — the caller decides whether to keep it only in memory (D4's per-card unlock) or to
    /// call `restorePlain` (D4's board-wide "Gỡ khoá").
    struct UnlockedClip: Equatable {
        var record: ClipboardRecord
        var payloadData: Data?
        var thumbnailData: Data?
        var originalPayloadFileName: String?
        var originalThumbnailFileName: String?
    }

    /// Opens `record`'s sealed envelope (and sealed payload/thumbnail, if present) with `recipient`.
    /// Throws `.notLocked` if `!record.isLocked`, `.missingFile(path)` if the envelope is gone.
    static func unlock(
        _ record: ClipboardRecord,
        with recipient: some HPKEDiffieHellmanPrivateKey,
        ops: FileOps
    ) throws -> UnlockedClip {
        guard record.isLocked else { throw Error.notLocked }
        guard let envPath = record.payloadPath else { throw Error.missingFile("") }
        guard ops.exists(envPath) else { throw Error.missingFile(envPath) }

        let sealedEnvelope = try ops.read(envPath)
        let envelopeData = try open(sealedEnvelope, with: recipient)
        let envelope = try JSONDecoder().decode(Envelope.self, from: envelopeData)

        var payloadData: Data?
        if envelope.payloadFileName != nil {
            let lockedDir = (envPath as NSString).deletingLastPathComponent
            let sealedPayloadPath = sealedPayloadPath(id: record.id, lockedDir: lockedDir)
            guard ops.exists(sealedPayloadPath) else { throw Error.missingFile(sealedPayloadPath) }
            let sealed = try ops.read(sealedPayloadPath)
            payloadData = try open(sealed, with: recipient)
        }

        var thumbnailData: Data?
        if envelope.thumbnailFileName != nil {
            let lockedDir = (envPath as NSString).deletingLastPathComponent
            let sealedThumbnailPath = sealedThumbnailPath(id: record.id, lockedDir: lockedDir)
            guard ops.exists(sealedThumbnailPath) else { throw Error.missingFile(sealedThumbnailPath) }
            let sealed = try ops.read(sealedThumbnailPath)
            thumbnailData = try open(sealed, with: recipient)
        }

        var restoredMetadata = record.metadata
        restoredMetadata.removeValue(forKey: lockedFlagKey)
        restoredMetadata.removeValue(forKey: lockedBoardKey)
        for (key, value) in envelope.hiddenMetadata {
            restoredMetadata[key] = value
        }

        let restoredRecord = ClipboardRecord(
            id: record.id,
            type: record.type,
            timestamp: record.timestamp,
            sourceBundleID: record.sourceBundleID,
            sourceAppName: record.sourceAppName,
            textSnippet: envelope.textSnippet,
            thumbnailPath: nil,
            payloadPath: nil,
            ocrText: envelope.ocrText,
            pinboardID: record.pinboardID,
            metadata: restoredMetadata
        )

        return UnlockedClip(
            record: restoredRecord,
            payloadData: payloadData,
            thumbnailData: thumbnailData,
            originalPayloadFileName: envelope.payloadFileName,
            originalThumbnailFileName: envelope.thumbnailFileName
        )
    }

    // MARK: - Restore plain (board-wide "Gỡ khoá")

    /// Inverse of `lock`, for "Gỡ khoá (giải mã lại)": writes `clip`'s bytes back to
    /// `<plainDir>/<original name>` (or `<plainDir>/<id>.bin` / `<plainDir>/<id>.thumb.png` when the
    /// original name is unknown — this can only happen if a future caller hand-builds a `clip`
    /// whose envelope omitted the name, since `unlock` always carries it through), removes the
    /// sealed files, and returns the fully plain row (no lock metadata, paths set).
    static func restorePlain(
        _ clip: UnlockedClip,
        lockedRecord: ClipboardRecord,
        plainDir: String,
        ops: FileOps
    ) throws -> ClipboardRecord {
        guard lockedRecord.isLocked else { throw Error.notLocked }

        var payloadPath: String?
        if let data = clip.payloadData {
            let name = safeFileName(clip.originalPayloadFileName, fallback: "\(lockedRecord.id.uuidString).bin")
            let path = "\(plainDir)/\(name)"
            try ops.write(data, path)
            payloadPath = path
        }

        var thumbnailPath: String?
        if let data = clip.thumbnailData {
            let name = safeFileName(clip.originalThumbnailFileName, fallback: "\(lockedRecord.id.uuidString).thumb.png")
            let path = "\(plainDir)/\(name)"
            try ops.write(data, path)
            thumbnailPath = path
        }

        for path in sealedFiles(of: lockedRecord) where ops.exists(path) {
            try ops.remove(path)
        }

        var metadata = clip.record.metadata
        metadata.removeValue(forKey: lockedFlagKey)
        metadata.removeValue(forKey: lockedBoardKey)

        return ClipboardRecord(
            id: clip.record.id,
            type: clip.record.type,
            timestamp: clip.record.timestamp,
            sourceBundleID: clip.record.sourceBundleID,
            sourceAppName: clip.record.sourceAppName,
            textSnippet: clip.record.textSnippet,
            thumbnailPath: thumbnailPath,
            payloadPath: payloadPath,
            ocrText: clip.record.ocrText,
            pinboardID: clip.record.pinboardID,
            metadata: metadata
        )
    }

    /// A restored file name comes out of the envelope, and the envelope was sealed with a PUBLIC key
    /// anyone holding the plist can read — so a planted envelope could carry "../x" or an absolute
    /// path. Only a plain, single-component name is honoured; anything else gets the fallback.
    static func safeFileName(_ name: String?, fallback: String) -> String {
        guard let name, !name.isEmpty, !name.contains("/"), name != ".", name != "..", !name.hasPrefix("~") else { return fallback }
        return name
    }

    /// Paths of the sealed files a locked row owns (envelope, and sealed payload/thumbnail if they
    /// exist on disk) — for delete. Does not check `ops.exists`; callers that need to know whether a
    /// path is actually present should check themselves (as `restorePlain` does).
    static func sealedFiles(of record: ClipboardRecord) -> [String] {
        guard record.isLocked, let envPath = record.payloadPath else { return [] }
        let lockedDir = (envPath as NSString).deletingLastPathComponent
        return [
            envPath,
            sealedPayloadPath(id: record.id, lockedDir: lockedDir),
            sealedThumbnailPath(id: record.id, lockedDir: lockedDir),
        ]
    }

    // MARK: - Fence

    /// Rows that may leave the machine, or be shown by a reader that cannot unlock (MCP,
    /// `.xfinderclip` export). Drops every `isLocked` row; order of the rest is preserved.
    static func fenced(_ records: [ClipboardRecord]) -> [ClipboardRecord] {
        records.filter { !$0.isLocked }
    }
}
