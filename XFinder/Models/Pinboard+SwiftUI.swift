import Foundation
import SwiftUI

/// The SwiftUI half of `Pinboard` / `CodableColor` — kept out of `Pinboard.swift` so the model can be
/// symlinked into the Foundation-only test package (see the note there).
extension Pinboard {
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

extension CodableColor {
    init(color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(converted.redComponent),
                  green: Double(converted.greenComponent),
                  blue: Double(converted.blueComponent),
                  alpha: Double(converted.alphaComponent))
    }

    var color: Color {
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }

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
