import Foundation
import Observation

/// XF-T32 W2/W3 (contract XF-T32-w23 §A) — main-actor façade over `MetadataStore`: in-memory caches the views read
/// synchronously, filled by `load(folder:)` and mutations (write-through to the actor). STUB — builder `metadata`.
@MainActor @Observable final class BrowserMetadata {
    static let shared: BrowserMetadata = BrowserMetadata(store: .shared)

    @ObservationIgnored private let store: MetadataStore
    private(set) var revision: Int = 0
    private(set) var catalog: PropertyCatalog = PropertyCatalog()

    init(store: MetadataStore) { self.store = store }

    func load(folder: String) {}
    func pins(in folder: String) -> [String] { [] }
    func nickname(for path: String) -> String? { nil }
    func emoji(for folder: String) -> String? { nil }
    func option(for path: String, property: UUID) -> PropertyOption? { nil }
    func shownProperties(in folder: String) -> [(definition: PropertyDefinition, showInView: Bool)] { [] }
    func visibleProperties(in folder: String) -> [PropertyDefinition] { [] }
    func togglePin(_ path: String, in folder: String) {}
    func setNickname(_ nickname: String?, for path: String) {}
    func setEmoji(_ emoji: String?, for folder: String) {}
    func select(path: String, property: UUID, option: UUID?) {}
    func updateCatalog(_ change: (inout PropertyCatalog) -> Void) {}
    func setFolderProperties(_ folder: String, _ list: [(property: UUID, showInView: Bool)]) {}
    func related(to folder: String) -> [String] { [] }
    func addRelation(_ a: String, _ b: String) {}
    func removeRelation(_ a: String, _ b: String) {}
    func liveGroups(_ refs: [LiveGroupRef]) -> [PropertyRules.LiveGroup] { [] }
    func itemMoved(from: String, to: String) {}
    func itemRemoved(_ path: String) {}
    func relieve(_ plan: PressureRules.Plan) {}
}
