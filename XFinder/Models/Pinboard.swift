import Foundation

/// A clipboard board. Foundation-only on purpose (D, 2026-10-12): `ClipExport` writes boards into the
/// `.xfinderclip` manifest, and the test package cannot compile SwiftUI — so the SwiftUI side
/// (`Color` bridging, `defaultPinboards`, preset names) lives in `Pinboard+SwiftUI.swift`.
struct Pinboard: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    let color: CodableColor
    let icon: String
    var itemIDs: [UUID]
    let order: Int
    let createdAt: Date
    let isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        color: CodableColor,
        icon: String = "star.fill",
        itemIDs: [UUID] = [],
        order: Int = 0,
        createdAt: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.itemIDs = itemIDs
        self.order = order
        self.createdAt = createdAt
        self.isBuiltIn = isBuiltIn
    }
}

/// sRGB components, 0…1. The plain initializer is what the manifest round-trip and the tests use;
/// `init(color:)` / `var color` (SwiftUI) are in `Pinboard+SwiftUI.swift`.
struct CodableColor: Codable, Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}
