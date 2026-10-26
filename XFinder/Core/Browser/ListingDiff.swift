import Foundation

/// How a refreshed listing is applied to the outline that already shows the old one. Pure (Foundation only),
/// symlinked into the test package.
///
/// FileOctopus 1.0.4 (measured 2026-10-26: `insertItemsAtIndexes:inParent:withAnimation:`, `removeItemsAtIndexes:…`,
/// `reloadItem:reloadChildren:`, `beginUpdates`/`endUpdates` are all referenced by the binary) patches its list in
/// place; a `reloadData()` after every watcher event is what rebuilt XFinder's whole table — selection, scroll,
/// disclosure and an in-flight click with it.
enum ListingDiff {
    enum Plan: Equatable {
        /// Remove `removed` (indices in the OLD list), then insert `inserted` (indices in the NEW list). Items common
        /// to both keep their relative order, so NSOutlineView's batch update is valid.
        case patch(removed: IndexSet, inserted: IndexSet)
        /// The kept items changed order (a resort, a rename that moves a row): rebuild.
        case reload
    }

    /// `old`/`new` are stable identities (paths) in display order. Duplicate identities fall back to `.reload` —
    /// an outline cannot address two rows with one item.
    static func plan(old: [String], new: [String]) -> Plan {
        if old == new { return .patch(removed: IndexSet(), inserted: IndexSet()) }
        let oldSet = Set(old), newSet = Set(new)
        guard oldSet.count == old.count, newSet.count == new.count else { return .reload }
        var removed = IndexSet()
        var keptOld: [String] = []
        keptOld.reserveCapacity(min(old.count, new.count))
        for (i, id) in old.enumerated() {
            if newSet.contains(id) { keptOld.append(id) } else { removed.insert(i) }
        }
        var inserted = IndexSet()
        var keptNew: [String] = []
        keptNew.reserveCapacity(keptOld.count)
        for (i, id) in new.enumerated() {
            if oldSet.contains(id) { keptNew.append(id) } else { inserted.insert(i) }
        }
        guard keptOld == keptNew else { return .reload }
        return .patch(removed: removed, inserted: inserted)
    }

    /// A patch worth applying as one: past this many row changes a reload is cheaper than hundreds of animated
    /// inserts (NSOutlineView batch updates are O(changes × visible rows)).
    static let maxPatchedRows: Int = 500

    static func shouldPatch(_ plan: Plan) -> Bool {
        guard case .patch(let removed, let inserted) = plan else { return false }
        return removed.count + inserted.count <= maxPatchedRows
    }
}
