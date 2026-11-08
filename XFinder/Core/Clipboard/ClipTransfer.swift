import AppKit
import Foundation
import UniformTypeIdentifiers

/// D (2026-10-12) — the I/O half of `.xfinderclip` export/import: panels, staging, the archive runner,
/// and the hand-off to `ClipboardManager`. Every rule about WHAT travels is in `ClipExport` (pure,
/// tested); this file only moves bytes. Outcomes are structured so the settings page words them.
@MainActor
enum ClipTransfer {
    enum Failure: Equatable {
        case notAManifest
        case unsupportedVersion(Int)
        /// The engine's own text (zip/tar stderr, a path that could not be written).
        case detail(String)
    }

    enum Outcome: Equatable {
        case cancelled
        case exported(records: Int, files: Int, missing: Int, skipped: Int)
        case imported(records: Int, duplicates: Int, boards: Int, rejected: Int)
        case failed(Failure)
    }

    /// The extension is not a registered UTI, so this is a dynamic type — enough for the panels to
    /// filter by extension and to append it to a typed name.
    static var contentType: UTType { UTType(filenameExtension: ClipExport.fileExtension) ?? .zip }

    static let live = ClipExport.FileOps(
        exists: { FileManager.default.fileExists(atPath: $0) },
        copy: { try FileManager.default.copyItem(atPath: $0, toPath: $1) },
        makeDir: { try FileManager.default.createDirectory(atPath: $0, withIntermediateDirectories: true) },
        write: { try $0.write(to: URL(fileURLWithPath: $1), options: .atomic) },
        read: { try Data(contentsOf: URL(fileURLWithPath: $0)) }
    )

    // MARK: Export

    static func exportViaPanel() async -> Outcome {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ClipExport.suggestedFileName(for: Date())
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        return await export(to: url)
    }

    /// Stage (manifest + copied media) beside the destination, then zip the two top-level entries.
    static func export(to url: URL) async -> Outcome {
        let fm = FileManager.default
        let staging: URL
        do {
            staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: url.deletingLastPathComponent(), create: true)
        } catch { return .failed(.detail("\(error.localizedDescription)")) }
        defer { try? fm.removeItem(at: staging) }

        let manager = ClipboardManager.shared
        // `ClipExport` takes exact bundle ids; the manager's rule is keyword-based, so resolve it over
        // the ids actually present in the history.
        let excluded = Set(manager.history.compactMap(\.sourceBundleID).filter(ClipboardManager.isExcludedBundleID))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let staged = ClipExport.stage(records: manager.history, boards: manager.pinboards, appVersion: version,
                                      date: Date(), excludedBundleIDs: excluded, into: staging.path, ops: live)
        let report: ClipExport.StageReport
        switch staged {
        case .failure(.cannotWrite(let p)): return .failed(.detail(p))
        case .success(let r): report = r
        }
        // The panel already asked about replacing; `zip` would UPDATE an existing archive in place,
        // so the old file must go first.
        try? fm.removeItem(at: url)
        let sources = [staging.appendingPathComponent("manifest.json"), staging.appendingPathComponent("payloads")]
        switch await ArchiveRunner.compress(sources: sources, format: .zip, output: url) {
        case .success:
            return .exported(records: report.manifest.records.count, files: report.copiedFiles,
                             missing: report.missingFiles, skipped: report.skippedRecords)
        case .failure(let f):
            return .failed(.detail(describe(f)))
        }
    }

    // MARK: Import

    static func importViaPanel() async -> Outcome {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        return await importArchive(at: url)
    }

    /// Extract into a staging folder on the payload volume, plan against what the app already holds,
    /// materialise each new record under a fresh file name, and hand the batch to the manager.
    static func importArchive(at url: URL) async -> Outcome {
        let payloadDir = ClipboardPayloadStore.baseDir()
        let batch: ArchiveRunner.ExtractedBatch
        switch await ArchiveRunner.extractToStaging(archive: url, near: payloadDir) {
        case .failure(let f): return .failed(.detail(describe(f)))
        case .success(let b): batch = b
        }
        defer { ArchiveRunner.discard(batch) }
        guard let data = try? Data(contentsOf: batch.staging.appendingPathComponent("manifest.json")) else {
            return .failed(.notAManifest)
        }
        let manager = ClipboardManager.shared
        let known = Set(manager.history.map(\.id)).union(manager.pinboards.map(\.id))
        switch ClipExport.plan(manifestData: data, existingIDs: known) {
        case .failure(.notAManifest): return .failed(.notAManifest)
        case .failure(.unsupportedVersion(let v)): return .failed(.unsupportedVersion(v))
        case .failure(.corrupt(let s)): return .failed(.detail(s))
        case .success(let plan):
            var records: [ClipboardRecord] = []
            var rejected = 0
            for entry in plan.newRecords {
                do {
                    if let r = try ClipExport.materialize(entry, from: batch.staging.path, payloadDir: payloadDir.path, ops: live) {
                        records.append(r)
                    } else { rejected += 1 }
                } catch { rejected += 1 }
            }
            manager.importRecords(records, boards: plan.newBoards)
            return .imported(records: records.count, duplicates: plan.duplicates, boards: plan.newBoards.count, rejected: rejected)
        }
    }

    private static func describe(_ f: ArchiveRunner.Failure) -> String {
        switch f {
        case .nothingToDo: return "nothing to archive"
        case .missingSource(let names): return "missing: \(names.joined(separator: ", "))"
        case .staging(let s), .placement(let s), .archiveChanged(let s): return s
        case .tool(let status, let stderr): return stderr.isEmpty ? "exit \(status)" : stderr
        case .missingData(let stderr): return stderr
        case .cancelled: return "cancelled"
        case .unsafeLinks(let links): return "unsafe links: \(links.joined(separator: ", "))"
        case .unsafeArchive(_, let diagnostic): return diagnostic ?? "refused by the archive safety rules"
        case .outOfSpace(let required, let available): return "needs \(required) bytes, \(available) available"
        case .readerUnavailable: return "the system archive reader is unavailable"
        }
    }
}
