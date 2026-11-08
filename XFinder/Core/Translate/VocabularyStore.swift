import Foundation
import Observation

/// Disk writes complete before publishing a mutation. A corrupt library is never silently replaced.
@MainActor @Observable
final class VocabularyStore {
    enum Issue: Error, Equatable, Sendable { case unreadable, corrupt, unsupportedVersion, writeFailed, backupFailed, invalidImport }
    static let shared = VocabularyStore(directory: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support"))
        .appendingPathComponent("XFinder/Wordbook", isDirectory: true))

    private(set) var library = VocabularyLibrary()
    private(set) var isLoaded = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var hasPersistedData = false
    @ObservationIgnored private var writeTail: Task<Bool, Never>?
    @ObservationIgnored private var pendingWrites = 0
    private(set) var isReadOnly = false
    private(set) var recoveredBackup = false
    private(set) var issue: Issue?
    @ObservationIgnored private let disk: VocabularyDisk
    let directory: URL

    init(directory: URL) { self.directory = directory; disk = VocabularyDisk(directory: directory) }

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    func load() async {
        if isLoaded { return }
        if let existing = loadTask {
            await existing.value
            return
        }
        let task = Task { @MainActor in
            isLoading = true
            let result = await disk.load()
            library = result.library
            issue = result.issue
            recoveredBackup = result.recovered
            isReadOnly = result.blocked
            hasPersistedData = result.persisted
            isLoaded = true
            isLoading = false
            loadTask = nil
        }
        loadTask = task
        await task.value
    }

    @discardableResult
    func saveCard(_ card: VocabularyCard, now: Date = Date()) async -> VocabularyCard? {
        var saved: VocabularyCard?
        let ok = await commit { snapshot in saved = try snapshot.upsert(card, now: now) }
        return ok ? saved : nil
    }

    @discardableResult
    func addWordbook(name: String) async -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var book: VocabularyWordbook?
        let ok = await commit { snapshot in book = try snapshot.addWordbook(name: trimmed) }
        return ok ? book?.id : nil
    }

    @discardableResult
    func reviewCard(id: UUID, rating: VocabularyRating, now: Date = Date(), calendar: Calendar = .current) async -> Bool {
        await commit { snapshot in
            guard let index = snapshot.cards.firstIndex(where: { $0.id == id }) else { throw Issue.invalidImport }
            snapshot.cards[index].review = VocabularyReviewRules.reviewed(snapshot.cards[index].review,
                rating: rating, now: now, calendar: calendar)
            snapshot.cards[index].updatedAt = now
        }
    }

    @discardableResult
    func removeCard(id: UUID) async -> Bool {
        await commit { snapshot in snapshot.cards.removeAll { $0.id == id } }
    }

    @discardableResult
    func saveBlueprint(id: String, text: String?) async -> Bool {
        await commit { snapshot in
            if let text { snapshot.blueprints[id] = text } else { snapshot.blueprints.removeValue(forKey: id) }
        }
    }

    @discardableResult
    func importJSON(_ data: Data) async -> Bool {
        do {
            let imported = try await disk.decodeImport(data)
            return await commit { snapshot in _ = try snapshot.merge(imported) }
        } catch { issue = .invalidImport; return false }
    }

    func exportJSON() async throws -> Data { try await disk.encode(library) }

    func flush() async { _ = await writeTail?.value }

    private func commit(_ mutation: @escaping @MainActor (inout VocabularyLibrary) throws -> Void) async -> Bool {
        let previous = writeTail
        pendingWrites += 1
        isSaving = true
        let task = Task { @MainActor in
            _ = await previous?.value
            defer { self.pendingWrites -= 1; self.isSaving = self.pendingWrites > 0 }
            return await self.performCommit(mutation)
        }
        writeTail = task
        return await task.value
    }

    private func performCommit(_ mutation: (inout VocabularyLibrary) throws -> Void) async -> Bool {
        if !isLoaded { await load() }
        guard isLoaded, !isReadOnly else { return false }
        var next = library
        do { try mutation(&next); try next.validate() } catch { issue = .invalidImport; return false }
        do {
            let backupWarning = try await disk.save(next)
            library = next
            hasPersistedData = true
            recoveredBackup = false
            issue = backupWarning ? .backupFailed : nil
            return true
        } catch { issue = .writeFailed; return false }
    }
}

private actor VocabularyDisk {
    struct Loaded: Sendable {
        var library: VocabularyLibrary
        var issue: VocabularyStore.Issue?
        var recovered: Bool
        var blocked: Bool
        var persisted: Bool = false
    }
    private let directory: URL
    private var lastGoodData: Data?
    private var primary: URL { directory.appendingPathComponent("library.json") }
    private var backup: URL { directory.appendingPathComponent("library.backup.json") }
    private static let maximumBytes = VocabularyLibrary.maximumImportBytes

    init(directory: URL) { self.directory = directory }

    func load() -> Loaded {
        let manager = FileManager.default
        let primaryExists = manager.fileExists(atPath: primary.path)
        let backupExists = manager.fileExists(atPath: backup.path)
        guard primaryExists || backupExists else {
            return Loaded(library: VocabularyLibrary(), issue: nil, recovered: false, blocked: false)
        }
        if primaryExists {
            do {
                let data = try read(primary)
                let decoded = try VocabularyLibrary.decode(data)
                lastGoodData = data
                return Loaded(library: decoded, issue: nil, recovered: false, blocked: false, persisted: true)
            } catch VocabularyLibrary.ValidationError.unsupportedVersion {
                return Loaded(library: VocabularyLibrary(), issue: .unsupportedVersion, recovered: false, blocked: true)
            } catch VocabularyStore.Issue.unreadable {
                return Loaded(library: VocabularyLibrary(), issue: .unreadable, recovered: false, blocked: true)
            } catch { /* A damaged primary may be recovered from an independently validated backup. */ }
        }
        if backupExists {
            do {
                let data = try read(backup)
                let decoded = try VocabularyLibrary.decode(data)
                lastGoodData = data
                return Loaded(library: decoded, issue: nil, recovered: true, blocked: false, persisted: true)
            } catch VocabularyLibrary.ValidationError.unsupportedVersion {
                return Loaded(library: VocabularyLibrary(), issue: .unsupportedVersion, recovered: false, blocked: true)
            } catch { /* Both files remain untouched for recovery. */ }
        }
        return Loaded(library: VocabularyLibrary(), issue: .corrupt, recovered: false, blocked: true)
    }

    /// The previous valid version becomes the backup before an atomic primary replacement.
    func save(_ library: VocabularyLibrary) throws -> Bool {
        let data = try library.encoded()
        guard data.count <= Self.maximumBytes else { throw VocabularyStore.Issue.writeFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let previous = lastGoodData { try previous.write(to: backup, options: .atomic) }
        try data.write(to: primary, options: .atomic)
        let firstSave = lastGoodData == nil
        lastGoodData = data
        if firstSave {
            do { try data.write(to: backup, options: .atomic) } catch { return true }
        }
        return false
    }

    func decodeImport(_ data: Data) throws -> VocabularyLibrary {
        guard data.count <= Self.maximumBytes else { throw VocabularyStore.Issue.invalidImport }
        return try VocabularyLibrary.decode(data)
    }

    func encode(_ library: VocabularyLibrary) throws -> Data { try library.encoded() }

    private func read(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Self.maximumBytes + 1
        guard size <= Self.maximumBytes else { throw VocabularyStore.Issue.unreadable }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumBytes else { throw VocabularyStore.Issue.unreadable }
        return data
    }
}
