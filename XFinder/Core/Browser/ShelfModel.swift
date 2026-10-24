import Foundation

/// XF-T28 (2026-10-24) — the Shelf (`Views/Browser` §2.11): a window-scoped holding area for file references dragged
/// in from any pane, so a user can gather items from several folders before picking one destination action (Chép/Di
/// chuyển/Đổi tên hàng loạt). Pure model only: it holds *paths*, not file handles, so a Shelf item can outlive the
/// source being deleted, renamed or ejected underneath it — `refreshMissing` is how the AppKit layer (which owns the
/// `FileManager`/`DispatchSource` calls) tells this model what still exists, after which `missing` items are skipped
/// by `totalBytes`/`targets` but kept visible (contract: "Bỏ" removes them explicitly, nothing here does it silently).
struct ShelfItem: Hashable, Codable, Sendable, Identifiable {
    var id: String { path }
    let path: String
    var size: Int64?
    var missing: Bool
}

struct ShelfModel: Codable, Equatable, Sendable {
    private(set) var items: [ShelfItem]

    init() {
        items = []
    }

    /// Normalized path used for de-duplication: `standardizingPath` both resolves `.`/`..`/`~` and drops a trailing
    /// "/", so "/Users/a/Docs" and "/Users/a/Docs/" collapse to the same Shelf entry (spec: "bỏ trùng theo đường dẫn
    /// chuẩn hoá"). This is a string transform only — it never touches the file system, so it works for paths whose
    /// target has since vanished.
    private static func normalize(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Adds `paths` in order, skipping any whose normalized form is already on the Shelf (existing items keep their
    /// original position — a second drag of the same file doesn't reorder it). `sizes` is keyed by the *input* path
    /// (whatever the caller already measured) so this stays a pure string/dictionary operation with no disk access.
    /// Returns how many entries were actually appended, for a UI toast like "Đã thêm 2 mục" vs. "đã có trong Shelf".
    @discardableResult
    mutating func add(_ paths: [String], sizes: [String: Int64]) -> Int {
        var seen = Set(items.map { Self.normalize($0.path) })
        var added = 0
        for path in paths {
            let key = Self.normalize(path)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            items.append(ShelfItem(path: path, size: sizes[path], missing: false))
            added += 1
        }
        return added
    }

    /// Removes every item whose normalized path is in `paths` (the caller may pass raw, un-normalized paths — e.g.
    /// straight from a selection set — since matching also normalizes).
    mutating func remove(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        let keys = Set(paths.map(Self.normalize))
        items.removeAll { keys.contains(Self.normalize($0.path)) }
    }

    mutating func clear() {
        items.removeAll()
    }

    /// Re-stamps every item's `missing` flag from a caller-supplied existence check. Takes a closure (not a
    /// `FileManager` call) so this file stays Foundation-only and testable without touching disk.
    mutating func refreshMissing(exists: (String) -> Bool) {
        for index in items.indices {
            items[index].missing = !exists(items[index].path)
        }
    }

    var count: Int { items.count }

    /// Sum of known sizes, skipping missing items (a vanished file's last-known size is not real disk usage to
    /// report) and items whose size was never supplied (`nil` means "unknown", not "zero").
    var totalBytes: Int64 {
        items.reduce(into: Int64(0)) { total, item in
            guard !item.missing, let size = item.size else { return }
            total += size
        }
    }

    /// What an action (Chép/Di chuyển vào ngăn đang chọn…) should operate on: the selected subset if any path in
    /// `selection` is actually on the Shelf, else every item — both cases dropping `missing` entries and preserving
    /// Shelf order (not selection order), so a batch action is reproducible regardless of click order.
    ///
    /// The branch choice itself — "có mục nào được chọn trên Shelf" — is decided against *every* Shelf item
    /// (missing or not), not just the present ones: a user who selects precisely one grayed-out/missing row and
    /// hits "Chép" picked something, even if it can no longer be copied, so the result is empty (nothing to act
    /// on) rather than silently falling back to copying every *other*, unselected item on the Shelf. Dropping
    /// `missing` only happens once the branch is chosen.
    func targets(selection: Set<String>) -> [String] {
        let selectedKeys = Set(selection.map(Self.normalize))
        let selected = items.filter { selectedKeys.contains(Self.normalize($0.path)) }
        let base = selected.isEmpty ? items : selected
        return base.filter { !$0.missing }.map(\.path)
    }
}
