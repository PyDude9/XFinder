import Foundation
import Observation

/// XF-T32 W2 (contract XF-T32-w23 §B) — persists `SpaceStore` and keeps `BrowserSettings.sidebarLayout` equal to the
/// active Space's sidebar. STUB — builder `spaces`.
@MainActor @Observable final class SpaceController {
    // `shared` is declared next to `BrowserSettings` (BrowserSettings.swift): this file is compiled into the test package.

    @ObservationIgnored private let loadData: () -> Data?
    @ObservationIgnored private let saveData: (Data) -> Void
    @ObservationIgnored private let legacyLayout: () -> SidebarLayout
    @ObservationIgnored private let writeLayout: (SidebarLayout) -> Void
    private(set) var store: SpaceStore

    init(load: @escaping () -> Data?, save: @escaping (Data) -> Void,
         legacyLayout: @escaping () -> SidebarLayout, writeLayout: @escaping (SidebarLayout) -> Void) {
        self.loadData = load
        self.saveData = save
        self.legacyLayout = legacyLayout
        self.writeLayout = writeLayout
        self.store = SpaceStore.decode(load(), fallbackLayout: legacyLayout())
    }

    var active: Space { store.active }
    func activate(_ id: UUID) {}
    func activateNext() {}
    func activatePrevious() {}
    @discardableResult func add(name: String) -> Space { store.active }
    func rename(_ id: UUID, to name: String) -> Bool { false }
    func delete(_ id: UUID) -> Bool { false }
    func toggleLiveGroup(_ ref: LiveGroupRef) {}
    func sidebarDidChange(_ layout: SidebarLayout) {}
}
