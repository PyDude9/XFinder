import Foundation
import Observation

/// XF-T32 W2 (contract XF-T32-w23 §B) — persists `SpaceStore` and keeps `BrowserSettings.sidebarLayout` (the mirror
/// every sidebar already reads) equal to the active Space's sidebar.
///
/// Rules kept by every API:
/// - every mutation that changes the store saves it through `save` (one encoded `SpaceStore`);
/// - every change of the active Space (activate, next/previous, add, deleting the active one) calls
///   `writeLayout(active.sidebar)`;
/// - `sidebarDidChange` stores into the active Space only and never calls `writeLayout` back (the sidebar has already
///   written the mirror — writing it again would loop).
///
/// Launch reconciliation: a missing mirror must never overwrite persisted Spaces with fresh default UUIDs.
/// A mirror explicitly present is written on every activation and by every sidebar edit, so it is never older
/// than the active Space's copy. When stored data exists and the mirror differs from the active sidebar (an editor
/// wrote the mirror without telling this controller), the mirror is adopted into the active Space — nothing the
/// person last saw is lost. First launch (no data) or unreadable data ⇒ one Space wrapping the mirror.
@MainActor @Observable final class SpaceController {
    // `shared` is declared next to `BrowserSettings` (BrowserSettings.swift): this file is compiled into the test package.

    @ObservationIgnored private let loadData: () -> Data?
    @ObservationIgnored private let saveData: (Data) -> Void
    @ObservationIgnored private let legacyLayout: () -> SidebarLayout
    @ObservationIgnored private let writeLayout: (SidebarLayout) -> Void
    private(set) var store: SpaceStore

    init(load: @escaping () -> Data?, save: @escaping (Data) -> Void,
         legacyLayout: @escaping () -> SidebarLayout, writeLayout: @escaping (SidebarLayout) -> Void,
         hasLegacyLayout: () -> Bool = { false }) {
        self.loadData = load
        self.saveData = save
        self.legacyLayout = legacyLayout
        self.writeLayout = writeLayout
        let stored: Data? = load()
        let mirror: SidebarLayout = legacyLayout()
        var decoded: SpaceStore = SpaceStore.decode(stored, fallbackLayout: mirror)
        let mirrorExists = hasLegacyLayout()
        if mirrorExists && decoded.active.sidebar != mirror {
            decoded.updateActiveSidebar { $0 = mirror }
        }
        self.store = decoded
        persistIfDiffers(from: stored)
        if !mirrorExists { mirrorActive() }
    }

    // MARK: - Reading

    var active: Space { store.active }

    // MARK: - Activation

    /// Unknown id ⇒ nothing changes. Re-activating the active Space rewrites the mirror (idempotent) without saving.
    func activate(_ id: UUID) {
        let previous: UUID = store.activeID
        guard store.activate(id) else { return }
        if store.activeID != previous { persist() }
        mirrorActive()
    }

    /// Wraps from the last Space to the first; a single Space stays active.
    func activateNext() {
        changeActive { $0.activateNext() }
    }

    /// Wraps from the first Space to the last; a single Space stays active.
    func activatePrevious() {
        changeActive { $0.activatePrevious() }
    }

    // MARK: - Add / rename / delete

    /// Clones the active Space's sidebar (fresh ids), activates the new Space and mirrors its sidebar.
    @discardableResult func add(name: String) -> Space {
        let sourceID: UUID = store.active.id
        let space: Space = store.add(name: name, cloningSidebarFrom: sourceID)
        store.activate(space.id)
        persist()
        mirrorActive()
        return store.active
    }

    /// Blank, duplicate, or unknown ⇒ false and nothing is saved.
    func rename(_ id: UUID, to name: String) -> Bool {
        guard store.rename(id, to: name) else { return false }
        persist()
        return true
    }

    /// The last Space is never deleted (SpaceStore rule). Deleting the active Space mirrors its successor's sidebar.
    func delete(_ id: UUID) -> Bool {
        let previous: UUID = store.activeID
        guard store.delete(id) else { return false }
        persist()
        if store.activeID != previous { mirrorActive() }
        return true
    }

    // MARK: - Active Space content

    /// Shows the Live Group in the active Space, or hides it when already shown.
    func toggleLiveGroup(_ ref: LiveGroupRef) {
        store.toggleLiveGroup(ref)
        persist()
    }

    /// The sidebar saved `layout` into the mirror ⇒ keep it in the active Space. Never writes the mirror back.
    func sidebarDidChange(_ layout: SidebarLayout) {
        guard store.active.sidebar != layout else { return }
        store.updateActiveSidebar { $0 = layout }
        persist()
    }

    /// Saves to the Space captured when the editor opened, including after the user switches Space.
    @discardableResult
    func saveFolderLiveGroup(_ group: FolderLiveGroup, in spaceID: UUID) -> Bool {
        let before = store
        guard store.saveFolderLiveGroup(group, in: spaceID) else { return false }
        if store != before { persist() }
        return true
    }

    @discardableResult
    func removeFolderLiveGroup(_ id: UUID, from spaceID: UUID) -> Bool {
        guard store.removeFolderLiveGroup(id, from: spaceID) else { return false }
        persist()
        return true
    }

    // MARK: - Private

    private func changeActive(_ step: (inout SpaceStore) -> Void) {
        let previous: UUID = store.activeID
        step(&store)
        guard store.activeID != previous else { return }
        persist()
        mirrorActive()
    }

    private func persist() {
        saveData(store.encoded())
    }

    /// Saves only when the stored bytes are not already this store (first launch, repaired or reconciled data), so a
    /// clean launch writes nothing.
    private func persistIfDiffers(from stored: Data?) {
        // Whitespace/key ordering (and Set iteration order) do not mean the user's configuration changed.
        if let stored, let previous = try? JSONDecoder().decode(SpaceStore.self, from: stored), previous == store { return }
        let encoded: Data = store.encoded()
        guard stored != encoded else { return }
        saveData(encoded)
    }

    private func mirrorActive() {
        writeLayout(store.active.sidebar)
    }
}
