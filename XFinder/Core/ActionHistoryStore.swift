import Foundation
import Combine

/// Append-only log of every mutating action XFinder performs (batch rename,
/// compress/extract, PDF ops, folder lock/sync, remote uploads). Backs the
/// Lịch sử thao tác page: the user sees what happened and can undo what is
/// safely reversible (renames, deletes-to-trash); destructive or irreversible
/// entries render "Không thể hoàn tác".
@MainActor
@Observable
final class ActionHistoryStore {
    static let shared = ActionHistoryStore()

    struct Entry: Identifiable, Codable, Sendable, Equatable {
        var id: UUID = UUID()
        var timestamp: Date = Date()
        var kind: String       // "rename" | "compress" | "extract" | "pdf" | "trash" | "other"
        var summary: String    // one-line Vietnamese description
        var detail: String?    // optional paths / counts
        var reversible: Bool   // can undo() attempt this one?
        var undoPayload: UndoPayload?
    }

    /// Minimal data needed to reverse an action. Renames/trashes move items
    /// back; anything without a payload is informational only.
    ///
    /// `trashOnUndo` (added for the file browser's copy/duplicate undo, XF-T28) is additive and optional so every
    /// existing payload — which only ever moved `from` back `to` — decodes unchanged: a copy or duplicate has no
    /// "original location" to move anything back to, so undoing it means trashing the items it created instead.
    /// When `trashOnUndo` is non-nil, `from`/`to` are ignored by `undo(_:)`.
    struct UndoPayload: Codable, Sendable, Equatable {
        var from: [String]     // current paths (to move from)
        var to: [String]       // original paths (to restore to)
        var trashOnUndo: [String]? = nil   // paths to move to Trash instead, for a copy/duplicate's undo

        init(from: [String], to: [String], trashOnUndo: [String]? = nil) {
            self.from = from
            self.to = to
            self.trashOnUndo = trashOnUndo
        }
    }

    private(set) var entries: [Entry] = []
    private let key = "XFinder.ActionHistory"

    private init() { load() }

    // MARK: - Record

    func record(kind: String, summary: String, detail: String? = nil,
                reversible: Bool = false, undoPayload: UndoPayload? = nil) {
        entries.insert(Entry(kind: kind, summary: summary, detail: detail,
                             reversible: reversible, undoPayload: undoPayload), at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        persist()
    }

    /// Convenience for renames: pairs old↔new paths so undo can move them back.
    func recordRenames(pairs: [(old: URL, new: URL)]) {
        guard !pairs.isEmpty else { return }
        let first = pairs[0].new.deletingLastPathComponent().lastPathComponent
        record(kind: "rename",
               summary: "\(L10n.t("Đổi tên "))\(pairs.count)\(L10n.t(" mục trong "))“\(first)”",
               detail: pairs.prefix(5).map { "\($0.old.lastPathComponent) → \($0.new.lastPathComponent)" }.joined(separator: "\n"),
               reversible: true,
               undoPayload: UndoPayload(from: pairs.map(\.new.path), to: pairs.map(\.old.path)))
    }

    func recordTrash(urls: [URL]) {
        guard !urls.isEmpty else { return }
        record(kind: "trash",
               summary: "\(L10n.t("Chuyển "))\(urls.count)\(L10n.t(" mục vào Thùng rác"))",
               detail: urls.prefix(5).map(\.lastPathComponent).joined(separator: ", "),
               reversible: false)
    }

    func clear() {
        entries = []
        persist()
    }

    // MARK: - Undo (safe only: FileManager move-back, no shell)

    /// Returns a message describing the outcome; never throws.
    func undo(_ entry: Entry) -> String {
        guard entry.reversible, let payload = entry.undoPayload else {
            return L10n.t("Không thể hoàn tác thao tác này.")
        }
        if let trashOnUndo = payload.trashOnUndo {
            return undoByTrashing(trashOnUndo, entry: entry)
        }
        guard payload.from.count == payload.to.count else {
            return L10n.t("Không thể hoàn tác thao tác này.")
        }
        if entry.kind == "rename" {
            // XF-T37: a rename batch goes back in one two-phase pass (`BatchRenameRules.execute`). The item-by-item
            // move below skips a target that "exists" — and on the default case-insensitive volume a case-only rename's
            // old name always exists (it IS the item), as does every name in a swap; a partial undo is refused instead.
            let outcome = BatchRenameRules.execute(Array(zip(payload.from, payload.to)).map { (from: $0.0, to: $0.1) })
            guard outcome.succeeded else { return L10n.t("Không thể hoàn tác thao tác này.") }
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: i)
                record(kind: "other", summary: "\(L10n.t("Hoàn tác: khôi phục "))\(outcome.renamed.count)\(L10n.t(" mục."))", reversible: false)
            }
            return "\(L10n.t("Đã hoàn tác "))\(outcome.renamed.count)\(L10n.t(" mục."))"
        }
        var restored = 0, failed = 0
        let fm = FileManager.default
        for (fromPath, toPath) in zip(payload.from, payload.to) {
            let from = URL(fileURLWithPath: fromPath)
            let to = URL(fileURLWithPath: toPath)
            do {
                if fm.fileExists(atPath: to.path) {
                    // Target occupied (user recreated it) — skip rather than overwrite.
                    failed += 1
                    continue
                }
                try fm.moveItem(at: from, to: to)
                restored += 1
            } catch { failed += 1 }
        }
        if restored > 0, let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries.remove(at: i)
            record(kind: "other", summary: "\(L10n.t("Hoàn tác: khôi phục "))\(restored)\(L10n.t(" mục."))", reversible: false)
        }
        return failed == 0
            ? "\(L10n.t("Đã hoàn tác "))\(restored)\(L10n.t(" mục."))"
            : "\(L10n.t("Khôi phục "))\(restored)\(L10n.t(", "))\(failed)\(L10n.t(" mục thất bại."))"
    }

    /// Undo for a copy or duplicate: the items it created have no earlier location to move back to, so undoing
    /// means moving each of them to the Trash (never `removeItem` — CLAUDE.md rule 9, "never rm user data").
    /// A path already gone (the user deleted it themselves since) is not an error — there is nothing left to undo
    /// for it, so it counts neither as restored nor failed.
    private func undoByTrashing(_ paths: [String], entry: Entry) -> String {
        guard !paths.isEmpty else { return L10n.t("Không thể hoàn tác thao tác này.") }
        var trashed = 0, failed = 0
        let fm = FileManager.default
        for path in paths {
            guard fm.fileExists(atPath: path) else { continue }
            do {
                try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                trashed += 1
            } catch { failed += 1 }
        }
        if trashed > 0, let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries.remove(at: i)
            record(kind: "other", summary: "\(L10n.t("Hoàn tác: chuyển "))\(trashed)\(L10n.t(" mục vào Thùng rác."))", reversible: false)
        }
        return failed == 0
            ? "\(L10n.t("Đã hoàn tác "))\(trashed)\(L10n.t(" mục."))"
            : "\(L10n.t("Khôi phục "))\(trashed)\(L10n.t(", "))\(failed)\(L10n.t(" mục thất bại."))"
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { entries = []; return }
        entries = decoded
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
