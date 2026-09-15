import Foundation
import SwiftUI

struct QuickNote: Identifiable, Codable, Sendable {
    let id: UUID
    let title: String?
    let content: String
    let color: CodableColor
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String? = nil,
        content: String = "",
        color: CodableColor = CodableColor(color: .yellow),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
    }

    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return content.split(separator: "\n").first.map(String.init) ?? "Untitled Note"
    }

    var timeString: String {
        return updatedAt.relativeString()
    }
}

struct NoteColor: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let color: Color

    static let presets: [NoteColor] = [
        NoteColor(name: "Yellow", color: .yellow),
        NoteColor(name: "Blue", color: .blue),
        NoteColor(name: "Green", color: .green),
        NoteColor(name: "Pink", color: .pink),
        NoteColor(name: "Purple", color: .purple),
        NoteColor(name: "Orange", color: .orange),
        NoteColor(name: "Red", color: .red),
        NoteColor(name: "Gray", color: .gray)
    ]
}
