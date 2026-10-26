import Foundation

/// XF-T32 W1 — stub (builder `properties`): custom select properties shared across folders. Contract
/// docs/specs/XF-T32-w1-contract.md §A.
enum PropertyColor: Int, Codable, CaseIterable, Sendable {
    case gray, red, orange, yellow, green, blue, purple

    var titleKey: String {
        switch self {
        case .gray: return "Xám"
        case .red: return "Đỏ"
        case .orange: return "Cam"
        case .yellow: return "Vàng"
        case .green: return "Lục"
        case .blue: return "Lam"
        case .purple: return "Tím"
        }
    }
}

struct PropertyOption: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var color: PropertyColor
}

enum PropertyKind: String, Codable, Sendable { case select }

struct PropertyDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var kind: PropertyKind
    var options: [PropertyOption]
}

struct LiveGroupRef: Codable, Equatable, Hashable, Sendable {
    var propertyID: UUID
    var optionID: UUID
}

struct PropertyCatalog: Codable, Equatable, Sendable {
    static let currentSchemaVersion: Int = 1
    var schemaVersion: Int
    var definitions: [PropertyDefinition]

    init() { schemaVersion = Self.currentSchemaVersion; definitions = [] }

    mutating func add(name: String) -> PropertyDefinition {
        let d = PropertyDefinition(id: UUID(), name: name, kind: .select, options: [])
        definitions.append(d)
        return d
    }
    mutating func rename(_ id: UUID, to name: String) -> Bool { false }
    mutating func delete(_ id: UUID) {}
    mutating func addOption(_ property: UUID, title: String, color: PropertyColor) -> PropertyOption? { nil }
    mutating func updateOption(_ property: UUID, option: PropertyOption) -> Bool { false }
    mutating func removeOption(_ property: UUID, option: UUID) {}
    mutating func moveOption(_ property: UUID, from: Int, to: Int) {}
    func definition(_ id: UUID) -> PropertyDefinition? { definitions.first { $0.id == id } }
    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ data: Data?) -> PropertyCatalog { PropertyCatalog() }
}
