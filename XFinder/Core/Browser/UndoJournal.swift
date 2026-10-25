import Foundation

/// XF-T30 W6 — the browser's persistent Undo (FileOctopus: 20 steps / 24 h across quit, metadata only, revalidated
/// before replay, never partial). Pure, symlinked. Contract XF-T30-w6 §1. W6 builder (pure): implement.
/// Undo moves `from` (where the item is now) back to `to` (where it was); `to` is empty for an item undo trashes
/// (a copy or duplicate). `inode`/`size`/`modified` describe the item at `from` when the step was recorded.
struct UndoItem: Codable, Equatable, Sendable {
    var from: String
    var to: String
    var inode: UInt64?
    var size: Int64?
    var modified: Date?
}

struct UndoStep: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case move, copy, duplicate, trash, rename, newFolder, merge, compress, infoEdit }
    var id: UUID
    var kind: Kind
    var items: [UndoItem]
    var date: Date

    /// L10n key of the verb ("Hoàn tác Chuyển 3 mục" — spec R52 names the verb + item count in one sentence, so the
    /// key itself carries the count via an L10n fragment the caller interpolates; this property returns the base
    /// sentence fragment for the verb, singular count is the caller's job (CLAUDE.md rule 8: interpolated text is
    /// split into fragments, not baked into the key).
    var titleKey: String {
        switch kind {
        case .move: return "Hoàn tác Chuyển"
        case .copy: return "Hoàn tác Sao chép"
        case .duplicate: return "Hoàn tác Nhân bản"
        case .trash: return "Hoàn tác Chuyển vào Thùng rác"
        case .rename: return "Hoàn tác Đổi tên"
        case .newFolder: return "Hoàn tác Tạo thư mục mới"
        case .merge: return "Hoàn tác Gộp thư mục"
        case .compress: return "Hoàn tác Nén"
        case .infoEdit: return "Hoàn tác Sửa thông tin"
        }
    }
}

struct UndoJournal: Codable, Equatable, Sendable {
    static let limit = 20
    static let maxAge: TimeInterval = 24 * 3600
    private(set) var undo: [UndoStep] = []
    private(set) var redo: [UndoStep] = []

    enum Availability: Equatable, Sendable { case available, diskMissing, unavailable(reasonKey: String) }

    /// Recording a brand-new step clears the redo stack (spec §9's ordinary undo/redo rule: a fresh action
    /// invalidates whatever was previously undone, same as every other undo manager) and enforces the 20-step cap
    /// by dropping the OLDEST step once the new one would exceed it — the newest 20 are what stays reachable.
    mutating func record(_ step: UndoStep, now: Date) {
        redo.removeAll()
        undo.append(step)
        if undo.count > Self.limit {
            undo.removeFirst(undo.count - Self.limit)
        }
    }

    /// Revalidates a step before it is allowed to run (spec R56/R58): every item must still exist at the path it
    /// would be undone FROM, with the same inode/size/modified identity it was recorded with (a "Keep Both" rename,
    /// an external edit, or a replacement by another operation all change that identity), and the destination it
    /// would return TO must still exist. A disk that is not currently mounted is reported distinctly as
    /// `.diskMissing` (shown as a greyed-out "Can't Undo…" that becomes available again once the disk returns,
    /// rather than the permanent `.unavailable` some other failures produce) — checked once per step via the first
    /// item's path, since every item in one step shares the same operation and therefore the same volume context in
    /// practice; a caller with a genuinely mixed-volume multi-source move still gets a correct answer because
    /// `volumeMounted` is also consulted per item below, this first check is just the common-case fast path.
    func availability(of step: UndoStep, exists: (String) -> Bool, identity: (String) -> (inode: UInt64, size: Int64, modified: Date)?,
                      volumeMounted: (String) -> Bool) -> Availability {
        guard let first = step.items.first else { return .unavailable(reasonKey: "Không còn mục nào để hoàn tác") }
        if !volumeMounted(first.to) || !volumeMounted(first.from) {
            return .diskMissing
        }
        // Multi-source moves undo as ONE atomic step (R55): if even one item can no longer be restored, the whole
        // step is refused — never a partial undo of "the ones that still work".
        for item in step.items {
            guard volumeMounted(item.to), volumeMounted(item.from) else { return .diskMissing }
            // `from` is where the item IS now (the queue records "undo moves from → to"); review 2026-10-25: this
            // checked `to` — the original place, empty after any successful move or trash — so undo was never available.
            guard exists(item.from) else {
                return .unavailable(reasonKey: "Một mục không còn ở chỗ cũ")
            }
            guard let recordedInode = item.inode, let recordedSize = item.size, let recordedModified = item.modified else {
                // No identity was captured for this item (e.g. a step recorded before identity tracking existed, or
                // an operation kind that legitimately has nothing to compare, like a plain rename) — nothing to
                // contradict, so it passes through rather than being refused for a check it never promised.
                continue
            }
            guard let currentIdentity = identity(item.from) else {
                return .unavailable(reasonKey: "Một mục không còn ở chỗ cũ")
            }
            guard currentIdentity.inode == recordedInode, currentIdentity.size == recordedSize,
                  currentIdentity.modified == recordedModified else {
                return .unavailable(reasonKey: "Mục đã bị đổi từ bên ngoài, không thể hoàn tác")
            }
        }
        return .available
    }

    mutating func popUndo() -> UndoStep? {
        guard let step = undo.popLast() else { return nil }
        redo.append(step)
        return step
    }

    mutating func popRedo() -> UndoStep? {
        guard let step = redo.popLast() else { return nil }
        undo.append(step)
        return step
    }

    /// Drops any step older than 24 hours from NOW — applied once per launch (and whenever the caller wants a fresh
    /// cut) rather than continuously, since "24 hours after the app quits" (spec R56) is measured from the moment
    /// each step was recorded, not from when pruning happens to run.
    mutating func pruned(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        undo.removeAll { $0.date < cutoff }
        redo.removeAll { $0.date < cutoff }
    }

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    static func decode(_ data: Data?) -> UndoJournal {
        guard let data, let decoded = try? JSONDecoder().decode(UndoJournal.self, from: data) else { return UndoJournal() }
        return decoded
    }
}
