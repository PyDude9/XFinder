import Foundation

/// Export the clipboard history AND the pinboards, with their media, as one `.xfinderclip` file, and
/// import it back without touching existing data (REDESIGN_PLAN Phase D). Pure planning only — the
/// only I/O is behind the injected `FileOps`, so every rule here runs against a temp folder in tests,
/// the same house style as `SettingsTransfer` (a plan + a verdict per entry, nothing writes during
/// parse) and `ArchiveEngine` (this module plans a STAGING FOLDER LAYOUT; it does not zip — the
/// caller hands that layout to the existing archive runner, and unzips an import with the same one).
///
/// Two rules shape what travels, mirroring `SettingsTransfer`'s two rules for settings:
///
/// * **Paths never leave the machine.** `ClipboardRecord.payloadPath`/`thumbnailPath` are absolute
///   paths on this disk. The manifest stores only archive-relative names
///   (`payloads/<id>.<ext>`), so an exported file never reveals the exporter's home directory or
///   username, and an import never tries to read a path that belongs to someone else's Mac.
/// * **Secrets never travel.** Records whose `sourceBundleID` is in the caller's `excludedBundleIDs`
///   (password managers) are skipped entirely during staging — the same list `ClipboardManager`
///   already excludes from ingestion in the first place, passed in rather than hard-coded here.
enum ClipExport {

    static let fileExtension = "xfinderclip"
    static let formatVersion = 1

    // MARK: - Manifest

    /// One record as stored in the manifest: every `ClipboardRecord` field, with `payloadPath` /
    /// `thumbnailPath` rewritten to archive-relative names — never the user's absolute paths.
    struct RecordEntry: Codable, Equatable {
        var id: UUID
        var type: ContentType
        var timestamp: Date
        var sourceBundleID: String?
        var sourceAppName: String?
        var textSnippet: String?
        var thumbnailPath: String?
        var payloadPath: String?
        var ocrText: String?
        var pinboardID: UUID?
        var metadata: [String: String]
    }

    struct Manifest: Codable, Equatable {
        var version: Int
        var exportedAt: Date
        var appVersion: String
        var records: [RecordEntry]
        var boards: [Pinboard]   // `Pinboard` is Equatable (Models/Pinboard.swift is Foundation-only)
    }

    // MARK: - File operations (injectable; the only I/O in this module)

    struct FileOps {
        var exists: (String) -> Bool
        var copy: (String, String) throws -> Void
        var makeDir: (String) throws -> Void
        var write: (Data, String) throws -> Void
        var read: (String) throws -> Data
    }

    enum ExportError: Error, Equatable {
        case cannotWrite(String)
    }

    enum ImportError: Error, Equatable {
        case notAManifest
        case unsupportedVersion(Int)
        case corrupt(String)
    }

    // MARK: - Export (stage)

    struct StageReport: Equatable {
        var manifest: Manifest
        var copiedFiles: Int
        var missingFiles: Int
        var skippedRecords: Int
    }

    /// Archive-relative name for a record's payload / thumbnail: `payloads/<id>.<ext>` /
    /// `payloads/<id>.thumb.<ext>`. The extension of the ORIGINAL file is kept (so an image payload
    /// is still openable by its extension inside the archive); a path with no extension gets none.
    private static func relativeName(forRecordID id: UUID, originalPath: String, thumbnail: Bool) -> String {
        let ext = (originalPath as NSString).pathExtension
        let base = thumbnail ? "\(id.uuidString).thumb" : id.uuidString
        return ext.isEmpty ? "payloads/\(base)" : "payloads/\(base).\(ext)"
    }

    /// Plans and performs the staging: writes `manifest.json` and copies each existing payload /
    /// thumbnail into `stagingDir/payloads/`. A missing source file is skipped and counted — the
    /// record is still exported, with that one path left `nil` rather than pointing at nothing.
    /// Records whose `sourceBundleID` is excluded are dropped entirely, before anything is copied.
    static func stage(
        records: [ClipboardRecord],
        boards: [Pinboard],
        appVersion: String,
        date: Date,
        excludedBundleIDs: Set<String>,
        into stagingDir: String,
        ops: FileOps
    ) -> Result<StageReport, ExportError> {
        let payloadsDir = stagingDir.hasSuffix("/") ? "\(stagingDir)payloads" : "\(stagingDir)/payloads"
        do {
            try ops.makeDir(payloadsDir)
        } catch {
            return .failure(.cannotWrite(payloadsDir))
        }

        var entries: [RecordEntry] = []
        var copied = 0
        var missing = 0
        var skipped = 0

        for record in records {
            if let bundleID = record.sourceBundleID, excludedBundleIDs.contains(bundleID) {
                skipped += 1
                continue
            }
            // D4: a clip in a locked board never travels — not even its sealed envelope, which would
            // be unreadable anywhere else anyway (the key is in THIS Mac's Secure Enclave).
            if record.isLocked {
                skipped += 1
                continue
            }

            var relativePayload: String?
            if let payloadPath = record.payloadPath {
                if ops.exists(payloadPath) {
                    let relative = relativeName(forRecordID: record.id, originalPath: payloadPath, thumbnail: false)
                    let dest = stagingDir.hasSuffix("/") ? "\(stagingDir)\(relative)" : "\(stagingDir)/\(relative)"
                    do {
                        try ops.copy(payloadPath, dest)
                        relativePayload = relative
                        copied += 1
                    } catch {
                        missing += 1
                    }
                } else {
                    missing += 1
                }
            }

            var relativeThumbnail: String?
            if let thumbnailPath = record.thumbnailPath {
                if ops.exists(thumbnailPath) {
                    let relative = relativeName(forRecordID: record.id, originalPath: thumbnailPath, thumbnail: true)
                    let dest = stagingDir.hasSuffix("/") ? "\(stagingDir)\(relative)" : "\(stagingDir)/\(relative)"
                    do {
                        try ops.copy(thumbnailPath, dest)
                        relativeThumbnail = relative
                        copied += 1
                    } catch {
                        missing += 1
                    }
                } else {
                    missing += 1
                }
            }

            entries.append(RecordEntry(
                id: record.id,
                type: record.type,
                timestamp: record.timestamp,
                sourceBundleID: record.sourceBundleID,
                sourceAppName: record.sourceAppName,
                textSnippet: record.textSnippet,
                thumbnailPath: relativeThumbnail,
                payloadPath: relativePayload,
                ocrText: record.ocrText,
                pinboardID: record.pinboardID,
                metadata: record.metadata
            ))
        }

        // D4: locked boards stay home too — their public key is harmless, but a board whose items
        // were all skipped would import as an empty shell claiming to be locked.
        let manifest = Manifest(
            version: formatVersion,
            exportedAt: date,
            appVersion: appVersion,
            records: entries,
            boards: boards.filter { !$0.isLocked }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else {
            return .failure(.cannotWrite("manifest.json"))
        }
        let manifestPath = stagingDir.hasSuffix("/") ? "\(stagingDir)manifest.json" : "\(stagingDir)/manifest.json"
        do {
            try ops.write(data, manifestPath)
        } catch {
            return .failure(.cannotWrite(manifestPath))
        }

        return .success(StageReport(manifest: manifest, copiedFiles: copied, missingFiles: missing, skippedRecords: skipped))
    }

    // MARK: - Import (plan)

    struct ImportPlan: Equatable {
        var manifest: Manifest
        var newRecords: [RecordEntry]
        var duplicates: Int
        var newBoards: [Pinboard]
        var mergedBoards: Int
    }

    /// Reads a manifest (already unzipped by the caller) and decides per record/board. Nothing is
    /// written here — `materialize` does the actual file copying, once per accepted record.
    static func plan(manifestData: Data, existingIDs: Set<UUID>) -> Result<ImportPlan, ImportError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: manifestData) else {
            return .failure(.notAManifest)
        }
        guard manifest.version <= formatVersion else {
            return .failure(.unsupportedVersion(manifest.version))
        }

        var newRecords: [RecordEntry] = []
        var duplicates = 0
        for entry in manifest.records {
            if existingIDs.contains(entry.id) {
                duplicates += 1
            } else {
                newRecords.append(entry)
            }
        }

        // Board merge rule: a board sharing an id with something the app already knows about is
        // `merged` (the caller folds its item ids into the existing board); a fresh id is `newBoards`.
        // Built-in boards are never imported — they are identity, not data, and every install already
        // has its own — so they are skipped and counted as merged, same as an id collision.
        var newBoards: [Pinboard] = []
        var merged = 0
        for board in manifest.boards {
            if board.isBuiltIn || existingIDs.contains(board.id) {
                merged += 1
                continue
            }
            newBoards.append(board)
        }

        return .success(ImportPlan(
            manifest: manifest,
            newRecords: newRecords,
            duplicates: duplicates,
            newBoards: newBoards,
            mergedBoards: merged
        ))
    }

    // MARK: - Import (materialize)

    /// Turns an entry back into a `ClipboardRecord`, copying its files from `unzippedDir` into
    /// `payloadDir` under FRESH names — never overwriting anything that already exists there.
    /// Returns `nil` when the entry's type needs a file (image) and that file is missing from the
    /// archive, since a record claiming to be an image with no bytes behind it is worse than no
    /// record at all.
    static func materialize(
        _ entry: RecordEntry,
        from unzippedDir: String,
        payloadDir: String,
        ops: FileOps
    ) throws -> ClipboardRecord? {
        /// Whether a referenced file was absent (`entry` named it but the archive does not have it,
        /// which is distinct from `entry` never having named one) or present and copied.
        enum MaterializedFile { case none, missing, copied(String) }

        func freshDestination(forRelative relative: String) -> String {
            let name = (relative as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension
            let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
            var candidate = payloadDir.hasSuffix("/") ? "\(payloadDir)\(name)" : "\(payloadDir)/\(name)"
            var n = 2
            while ops.exists(candidate) {
                let newName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
                candidate = payloadDir.hasSuffix("/") ? "\(payloadDir)\(newName)" : "\(payloadDir)/\(newName)"
                n += 1
            }
            return candidate
        }

        func copyIfPresent(relative: String?) throws -> MaterializedFile {
            guard let relative else { return .none }
            let source = unzippedDir.hasSuffix("/") ? "\(unzippedDir)\(relative)" : "\(unzippedDir)/\(relative)"
            guard ops.exists(source) else { return .missing }
            let dest = freshDestination(forRelative: relative)
            try ops.copy(source, dest)
            return .copied(dest)
        }

        let payload = try copyIfPresent(relative: entry.payloadPath)
        let thumbnail = try copyIfPresent(relative: entry.thumbnailPath)

        // An image record with no bytes behind it (payload AND thumbnail both absent from the
        // archive, or the one path it had is missing) is worse than no record — refuse it rather
        // than materialize a card that can never show anything.
        if entry.type == .image {
            let payloadOK = { if case .missing = payload { return false }; return true }()
            let thumbnailOK = { if case .missing = thumbnail { return false }; return true }()
            guard payloadOK, thumbnailOK else { return nil }
        }

        func path(_ file: MaterializedFile) -> String? {
            if case .copied(let p) = file { return p }
            return nil
        }

        return makeRecord(entry, payloadPath: path(payload), thumbnailPath: path(thumbnail))
    }

    private static func makeRecord(_ entry: RecordEntry, payloadPath: String?, thumbnailPath: String?) -> ClipboardRecord {
        ClipboardRecord(
            id: entry.id,
            type: entry.type,
            timestamp: entry.timestamp,
            sourceBundleID: entry.sourceBundleID,
            sourceAppName: entry.sourceAppName,
            textSnippet: entry.textSnippet,
            thumbnailPath: thumbnailPath,
            payloadPath: payloadPath,
            ocrText: entry.ocrText,
            pinboardID: entry.pinboardID,
            metadata: entry.metadata
        )
    }

    // MARK: - Naming

    /// "XFinder Clipboard 2026-10-12.xfinderclip" — date in the user's calendar, yyyy-MM-dd.
    static func suggestedFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return "XFinder Clipboard \(formatter.string(from: date)).\(fileExtension)"
    }
}
