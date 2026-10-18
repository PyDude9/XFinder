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

    // MARK: - Import / export (Markdown, văn bản, JSON)

    func exportMarkdown() -> String {
        notes.map { "## \($0.displayTitle)\n\n\($0.content)\n" }
            .joined(separator: "\n\n---\n\n")
    }

    func importMarkdown(_ text: String) {
        var imported: [QuickNote] = []
        for part in text.components(separatedBy: "\n## ") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let nl = trimmed.range(of: "\n") {
                let t = String(trimmed[..<nl.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let b = String(trimmed[nl.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                imported.append(QuickNote(title: t, content: b, color: CodableColor(color: .yellow)))
            } else {
                imported.append(QuickNote(title: trimmed, content: "", color: CodableColor(color: .yellow)))
            }
        }
        replaceAll(with: imported)
    }

    func exportText() -> String {
        notes.map { "\($0.displayTitle)\n\($0.content)" }
            .joined(separator: "\n\n========\n\n")
    }

    func importText(_ text: String) {
        let blocks = text.components(separatedBy: "========")
        let imported = blocks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { block -> QuickNote in
                if let nl = block.range(of: "\n") {
                    let t = String(block[..<nl.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let b = String(block[nl.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return QuickNote(title: t, content: b, color: CodableColor(color: .yellow))
                }
                return QuickNote(title: block, content: "", color: CodableColor(color: .yellow))
            }
        replaceAll(with: imported)
    }

    // MARK: - Font & hotkeys

    enum NoteFont: String, CaseIterable, Identifiable {
        case system, serif, mono
        var id: String { rawValue }
        var titleVI: String {
            switch self {
            case .system: return L10n.t("Hệ thống")
            case .serif: return "Serif"
            case .mono: return "Mono"
            }
        }
        func font(_ size: CGFloat) -> Font {
            switch self {
            case .system: return .system(size: size)
            case .serif: return .system(size: size, design: .serif)
            case .mono: return .system(size: size, design: .monospaced)
            }
        }
    }

    /// Font toàn cục cho nội dung ghi chú, lưu ở `notes.font`.
    static func noteFont(_ size: CGFloat) -> Font {
        let raw = UserDefaults.standard.string(forKey: "notes.font") ?? "system"
        return (NoteFont(rawValue: raw) ?? .system).font(size)
    }

    var fontSize: Double {
        get { UserDefaults.standard.object(forKey: "notes.fontSize") as? Double ?? 13.5 }
        set { UserDefaults.standard.set(newValue, forKey: "notes.fontSize") }
    }

    func setFontSize(_ v: Double) {
        UserDefaults.standard.set(v, forKey: "notes.fontSize")
        onChange?()
    }

    var markdownEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notes.markdownEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notes.markdownEnabled") }
    }

    /// ⌥⌘N đặt cờ này; trang Ghi chú quan sát để mở sheet tạo mới.
    var pendingNewNote = false

    var firstActiveNote: QuickNote? { notes.first(where: { !$0.isArchived }) }

    func togglePinFirstActive() {
        guard let target = firstActiveNote else { return }
        togglePin(target)
    }

    private func persist() {
        onChange?()
        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
        backupIfNeeded()
    }

    // MARK: - XF-T24 automatic dated backup (rules: NoteBackup)

    /// The ONE reader of `notes.autoBackup` (default on — local files only, one pair per day).
    static var autoBackupEnabled: Bool { UserDefaults.standard.object(forKey: "notes.autoBackup") as? Bool ?? true }
    static var backupFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/XFinder/Notes Backups", isDirectory: true)
    }
    /// The newest backup day on disk, or nil; shown on the Notes page.
    private(set) var lastBackupDay: String?
    private(set) var lastBackupError: String?

    /// Writes today's JSON + Markdown pair if it is not there yet (or always, when `force`), then prunes past `keepDays`.
    /// A failure never blocks the save that triggered it — it is reported on the Notes page.
    func backupIfNeeded(force: Bool = false) {
        guard force || Self.autoBackupEnabled else { return }
        let fm = FileManager.default
        let dir = Self.backupFolder
        let stem = NoteBackup.stem(for: Date())
        let json = dir.appendingPathComponent(stem + ".json"), md = dir.appendingPathComponent(stem + ".md")
        if !force, fm.fileExists(atPath: json.path) { lastBackupDay = String(stem.dropFirst(NoteBackup.prefix.count)); return }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(notes).write(to: json, options: .atomic)
            try exportMarkdown().write(to: md, atomically: true, encoding: .utf8)
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in NoteBackup.filesToPrune(names) {
                try? fm.trashItem(at: dir.appendingPathComponent(name), resultingItemURL: nil)
            }
            lastBackupDay = String(stem.dropFirst(NoteBackup.prefix.count))
            lastBackupError = nil
        } catch {
            lastBackupError = error.localizedDescription
        }
    }
}
