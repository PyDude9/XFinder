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
    struct UndoPayload: Codable, Sendable, Equatable {
        var from: [String]     // current paths (to move from)
        var to: [String]       // original paths (to restore to)
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
        guard entry.reversible, let payload = entry.undoPayload,
              payload.from.count == payload.to.count else {
            return L10n.t("Không thể hoàn tác thao tác này.")
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
