import Foundation

/// XF-T32 W1 — custom select properties shared across folders (Tilde's "Status" column). Contract
/// docs/specs/XF-T32-w1-contract.md §A. Pure Foundation: the catalog is a value that `MetadataStore` persists as one
/// JSON blob; no UI strings here — `titleKey` and the default property name are L10n keys the views pass to `L10n.t`.
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
    /// L10n key used as the name of a property created with an empty name.
    static let defaultNameKey: String = "Thuộc tính"

    var schemaVersion: Int
    var definitions: [PropertyDefinition]

    init() {
        schemaVersion = Self.currentSchemaVersion
        definitions = []
    }

    // MARK: - Definitions

    /// Adds a select property. Empty / whitespace-only name ⇒ `defaultNameKey`; a name already taken (compared by NFC +
    /// case only — tone marks stay significant) gets " 2", " 3"… until it is unique.
    mutating func add(name: String) -> PropertyDefinition {
        let trimmed: String = PropertyNaming.trimmed(name)
        let base: String = trimmed.isEmpty ? Self.defaultNameKey : trimmed
        let unique: String = PropertyNaming.uniqueName(base, taken: definitions.map(\.name))
        let definition: PropertyDefinition = PropertyDefinition(id: UUID(), name: unique, kind: .select, options: [])
        definitions.append(definition)
        return definition
    }

    /// Renames a property. Unknown id or empty name ⇒ false. A name another property already uses is made unique
    /// the same way `add` does; renaming to the property's own current name (any case/normalization) is kept as typed.
    mutating func rename(_ id: UUID, to name: String) -> Bool {
        guard let index: Int = definitions.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed: String = PropertyNaming.trimmed(name)
        guard !trimmed.isEmpty else { return false }
        let others: [String] = definitions.enumerated().filter { $0.offset != index }.map(\.element.name)
        definitions[index].name = PropertyNaming.uniqueName(trimmed, taken: others)
        return true
    }

    /// Removes a property (selections pointing at it become orphans — `MetadataStore` deletes them in the same save).
    mutating func delete(_ id: UUID) {
        definitions.removeAll { $0.id == id }
    }

    // MARK: - Options

    /// Appends an option. Unknown property or empty title ⇒ nil. Two options may share a title (they are told apart by id).
    mutating func addOption(_ property: UUID, title: String, color: PropertyColor) -> PropertyOption? {
        guard let index: Int = definitions.firstIndex(where: { $0.id == property }) else { return nil }
        let trimmed: String = PropertyNaming.trimmed(title)
        guard !trimmed.isEmpty else { return nil }
        let option: PropertyOption = PropertyOption(id: UUID(), title: trimmed, color: color)
        definitions[index].options.append(option)
        return option
    }

    /// Replaces the option with the same id (title and colour). Unknown property/option or empty title ⇒ false.
    mutating func updateOption(_ property: UUID, option: PropertyOption) -> Bool {
        guard let index: Int = definitions.firstIndex(where: { $0.id == property }) else { return false }
        guard let optionIndex: Int = definitions[index].options.firstIndex(where: { $0.id == option.id }) else { return false }
        let trimmed: String = PropertyNaming.trimmed(option.title)
        guard !trimmed.isEmpty else { return false }
        definitions[index].options[optionIndex] = PropertyOption(id: option.id, title: trimmed, color: option.color)
        return true
    }

    mutating func removeOption(_ property: UUID, option: UUID) {
        guard let index: Int = definitions.firstIndex(where: { $0.id == property }) else { return }
        definitions[index].options.removeAll { $0.id == option }
    }

    /// Moves the option at `from` so it ends up at index `to`; both indices are clamped into the valid range.
    mutating func moveOption(_ property: UUID, from: Int, to: Int) {
        guard let index: Int = definitions.firstIndex(where: { $0.id == property }) else { return }
        let count: Int = definitions[index].options.count
        guard count > 1 else { return }
        let source: Int = min(max(from, 0), count - 1)
        let destination: Int = min(max(to, 0), count - 1)
        guard source != destination else { return }
        let moved: PropertyOption = definitions[index].options.remove(at: source)
        definitions[index].options.insert(moved, at: destination)
    }

    // MARK: - Lookup / persistence

    func definition(_ id: UUID) -> PropertyDefinition? { definitions.first { $0.id == id } }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// Never fails: nil / unreadable data ⇒ an empty catalog; a damaged definition (or option) is dropped on its own and
    /// every readable one is kept. Also accepts a bare definitions array (no envelope).
    static func decode(_ data: Data?) -> PropertyCatalog {
        guard let data: Data = data, !data.isEmpty else { return PropertyCatalog() }
        let decoder: JSONDecoder = JSONDecoder()
        if let envelope: LossyCatalogDTO = try? decoder.decode(LossyCatalogDTO.self, from: data) {
            return envelope.catalog()
        }
        if let bare: LossyDefinitionList = try? decoder.decode(LossyDefinitionList.self, from: data) {
            var catalog: PropertyCatalog = PropertyCatalog()
            catalog.definitions = bare.definitions
            return catalog
        }
        return PropertyCatalog()
    }
}

// MARK: - Naming helpers

/// Name normalisation for the duplicate check: NFC first (so an NFD name from the file system or a paste compares equal
/// to its NFC twin), then `EntryRules.foldBytes` (case + diacritics + "đ").
private enum PropertyNaming {
    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// NFC + case only. Diacritics stay significant: "Mã", "Má" and "Ma" are different Vietnamese words.
    static func foldedKey(_ name: String) -> [UInt8] {
        Array(name.precomposedStringWithCanonicalMapping.lowercased().utf8)
    }

    /// `base` when no folded match is taken, else the first free "base 2", "base 3"…
    static func uniqueName(_ base: String, taken: [String]) -> String {
        let takenKeys: Set<[UInt8]> = Set(taken.map(foldedKey))
        guard takenKeys.contains(foldedKey(base)) else { return base }
        var suffix: Int = 2
        while true {
            let candidate: String = "\(base) \(suffix)"
            if !takenKeys.contains(foldedKey(candidate)) { return candidate }
            suffix += 1
        }
    }
}

// MARK: - Lossy decoding

/// Decodes and throws away one JSON value of any shape, so an unkeyed container can step past a damaged element.
private struct SkippedValue: Decodable {
    init(from decoder: Decoder) throws {}
}

private struct LossyOptionDTO: Decodable {
    let option: PropertyOption?

    private enum CodingKeys: String, CodingKey { case id, title, color }

    init(from decoder: Decoder) throws {
        guard let container: KeyedDecodingContainer<CodingKeys> = try? decoder.container(keyedBy: CodingKeys.self),
              let id: UUID = try? container.decode(UUID.self, forKey: .id),
              let title: String = try? container.decode(String.self, forKey: .title) else {
            option = nil
            return
        }
        // An unknown colour index (a newer palette) keeps the option, shown gray, rather than losing the user's choice.
        let raw: Int? = try? container.decode(Int.self, forKey: .color)
        let color: PropertyColor = raw.flatMap(PropertyColor.init(rawValue:)) ?? .gray
        option = PropertyOption(id: id, title: title, color: color)
    }
}

private struct LossyDefinitionDTO: Decodable {
    let definition: PropertyDefinition?

    private enum CodingKeys: String, CodingKey { case id, name, kind, options }

    init(from decoder: Decoder) throws {
        guard let container: KeyedDecodingContainer<CodingKeys> = try? decoder.container(keyedBy: CodingKeys.self),
              let id: UUID = try? container.decode(UUID.self, forKey: .id),
              let name: String = try? container.decode(String.self, forKey: .name),
              let rawKind: String = try? container.decode(String.self, forKey: .kind),
              let kind: PropertyKind = PropertyKind(rawValue: rawKind) else {
            definition = nil
            return
        }
        var options: [PropertyOption] = []
        var seen: Set<UUID> = []
        if var list: UnkeyedDecodingContainer = try? container.nestedUnkeyedContainer(forKey: .options) {
            while !list.isAtEnd {
                if let dto: LossyOptionDTO = try? list.decode(LossyOptionDTO.self) {
                    if let option: PropertyOption = dto.option, seen.insert(option.id).inserted { options.append(option) }
                } else if (try? list.decode(SkippedValue.self)) == nil {
                    break   // cannot advance past this element: keep what was read
                }
            }
        }
        definition = PropertyDefinition(id: id, name: name, kind: kind, options: options)
    }
}

private struct LossyDefinitionList: Decodable {
    let definitions: [PropertyDefinition]

    init(from decoder: Decoder) throws {
        var list: UnkeyedDecodingContainer = try decoder.unkeyedContainer()
        definitions = Self.read(&list)
    }

    static func read(_ list: inout UnkeyedDecodingContainer) -> [PropertyDefinition] {
        var out: [PropertyDefinition] = []
        var seen: Set<UUID> = []
        while !list.isAtEnd {
            if let dto: LossyDefinitionDTO = try? list.decode(LossyDefinitionDTO.self) {
                if let definition: PropertyDefinition = dto.definition, seen.insert(definition.id).inserted {
                    out.append(definition)
                }
            } else if (try? list.decode(SkippedValue.self)) == nil {
                break
            }
        }
        return out
    }
}

private struct LossyCatalogDTO: Decodable {
    let schemaVersion: Int
    let definitions: [PropertyDefinition]

    private enum CodingKeys: String, CodingKey { case schemaVersion, definitions }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? PropertyCatalog.currentSchemaVersion
        if var list: UnkeyedDecodingContainer = try? container.nestedUnkeyedContainer(forKey: .definitions) {
            definitions = LossyDefinitionList.read(&list)
        } else {
            definitions = []
        }
    }

    func catalog() -> PropertyCatalog {
        var catalog: PropertyCatalog = PropertyCatalog()
        catalog.schemaVersion = schemaVersion
        catalog.definitions = definitions
        return catalog
    }
}
