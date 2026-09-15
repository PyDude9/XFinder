import Foundation
import SwiftUI

struct Pinboard: Identifiable, Codable, Sendable {
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

    static let defaultPinboards: [Pinboard] = [
        Pinboard(
            name: "Clipboard History",
            color: CodableColor(color: .blue),
            icon: "clock.fill",
            isBuiltIn: true
        ),
        Pinboard(
            name: "Code Snippets",
            color: CodableColor(color: .green),
            icon: "curlybraces",
            isBuiltIn: false
        ),
        Pinboard(
            name: "Design Assets",
            color: CodableColor(color: .purple),
            icon: "paintbrush.fill",
            isBuiltIn: false
        )
    ]
}

struct CodableColor: Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
        self.alpha = Double(converted.alphaComponent)
    }

    var color: Color {
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension CodableColor {
    /// Human label for the note color filter — matches the editor presets.
    static let presetNames = ["Vàng", "Xanh dương", "Xanh lá", "Hồng", "Tím", "Cam", "Đỏ", "Xám"]

    static func presetName(for color: CodableColor) -> String {
        let candidates: [(String, Color)] = [
            ("Vàng", .yellow), ("Xanh dương", .blue), ("Xanh lá", .green),
            ("Hồng", .pink), ("Tím", .purple), ("Cam", .orange), ("Đỏ", .red), ("Xám", .gray)
        ]
        func dist(_ a: Color) -> Double {
            let na = NSColor(a).usingColorSpace(.sRGB) ?? .black
            let dr = na.redComponent - CGFloat(color.red)
            let dg = na.greenComponent - CGFloat(color.green)
            let db = na.blueComponent - CGFloat(color.blue)
            return Double(dr * dr + dg * dg + db * db)
        }
        return candidates.min(by: { dist($0.1) < dist($1.1) })?.0 ?? "Vàng"
    }
}
