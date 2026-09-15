import Foundation
import SwiftUI
import Combine

/// Single source of truth for Quick Notes. SideNotesPanel, the menubar flyout,
/// and the Ghi chú detail page all read through this store (UserDefaults key
/// `XFinder.QuickNotes`), which also fixes the editor sheet's Save no-op —
/// sheets call `save(_:)` / `update(_:)` instead of just dismissing.
@MainActor
@Observable
final class NoteStore {
    static let shared = NoteStore()

    private(set) var notes: [QuickNote] = []

    /// Called after every mutation. `@Observable` exposes no Combine
    /// publisher, so observers that are not SwiftUI views (the screen-edge
    /// panel controller) get told directly.
    var onChange: (() -> Void)?
    private let key = "XFinder.QuickNotes"

    private init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([QuickNote].self, from: data)
        else { notes = []; return }
        notes = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func create(title: String?, content: String, color: CodableColor) {
        let note = QuickNote(title: title?.isEmpty == true ? nil : title,
                             content: content, color: color)
        notes.insert(note, at: 0)
        persist()
    }

    func update(_ note: QuickNote, title: String?, content: String, color: CodableColor) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let old = notes[i]
        notes[i] = QuickNote(id: old.id, title: title?.isEmpty == true ? nil : title,
                             content: content, color: color,
                             createdAt: old.createdAt, updatedAt: Date(),
                             isPinned: old.isPinned, isArchived: old.isArchived)
        notes.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(_ note: QuickNote) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    func togglePin(_ note: QuickNote) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i].isPinned.toggle()
        persist()
    }

    func toggleArchive(_ note: QuickNote) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i].isArchived.toggle()
        persist()
    }

    func replaceAll(with imported: [QuickNote]) {
        notes = imported.sorted { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private func persist() {
        onChange?()
        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
