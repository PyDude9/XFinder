import Foundation
import Observation

/// Local persistent store for the Dynamic Island scratchpad.
///
/// Pure `Foundation` + `Observation` (no `AppKit` / `SwiftUI`), so unit tests run directly in
/// `XFinderLogicTests` without a window server or pasteboard. Never reads the system clipboard.
///
/// Guarantees:
/// - Unreadable / corrupted disk content (`readFailed`): blocks editing, clearing, and flushing
///   so the original bytes on disk remain strictly preserved until a successful `reload()`.
/// - Finite character limit (`maxCharacters`): edits past the limit stay visible in the editor
///   so the user can trim or copy them, while the previously saved file on disk is left untouched.
/// - Atomic UTF-8 writes: a failed write never corrupts or truncates the last saved file, and
///   `lastSavedText` continues to reflect what is actually on disk.
/// - Debounced autosave with synchronous `flush()` on disappear / close so rapid typing right
///   before closing is never lost.
/// - Explicit two-step clear (`requestClear()` → `confirmClear()` or `cancelClear()`).
@MainActor
@Observable
final class NotchScratchpadStore {

    enum Status: Equatable, Sendable {
        case idle
        case saved
        case overLimit(count: Int, limit: Int)
        case readFailed(String)
        case saveFailed(String)
    }

    static let shared = NotchScratchpadStore()

    nonisolated static let defaultMaxCharacters = 10_000
    nonisolated static let defaultDebounceNanoseconds: UInt64 = 250_000_000

    nonisolated static var defaultFileURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return appSupport
            .appendingPathComponent("XFinder", isDirectory: true)
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("scratchpad.txt", isDirectory: false)
    }

    let fileURL: URL
    let maxCharacters: Int

    private(set) var text: String = ""
    private(set) var lastSavedText: String = ""
    private(set) var status: Status = .idle
    private(set) var confirmingClear: Bool = false
    private(set) var hasPendingSave: Bool = false

    private let debounceNanoseconds: UInt64
    private let readData: (URL) throws -> Data?
    private let writeData: (Data, URL) throws -> Void
    private var pendingSaveTask: Task<Void, Never>?

    var isReadBlocked: Bool {
        if case .readFailed = status { return true }
        return false
    }

    var isEmpty: Bool { text.isEmpty }
    var characterCount: Int { text.count }
    var isOverLimit: Bool { text.count > maxCharacters }
    var hasUnsavedChanges: Bool { !isReadBlocked && text != lastSavedText }
    var canCopy: Bool { !isReadBlocked && !text.isEmpty }
    var canClear: Bool { !isReadBlocked && !text.isEmpty }

    init(
        fileURL: URL = NotchScratchpadStore.defaultFileURL,
        maxCharacters: Int = NotchScratchpadStore.defaultMaxCharacters,
        debounceNanoseconds: UInt64 = NotchScratchpadStore.defaultDebounceNanoseconds,
        readData: ((URL) throws -> Data?)? = nil,
        writeData: ((Data, URL) throws -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.maxCharacters = max(1, maxCharacters)
        self.debounceNanoseconds = debounceNanoseconds
        self.readData = readData ?? Self.defaultReadData
        self.writeData = writeData ?? Self.defaultWriteData
        loadFromDisk()
    }

    /// Updates the draft text. Refuses to edit or overwrite while disk content is unreadable.
    /// Valid edits schedule a debounced save; over-limit edits set `.overLimit` and leave
    /// the on-disk copy intact.
    func updateText(_ newValue: String) {
        guard !isReadBlocked else {
            cancelPendingSave()
            confirmingClear = false
            return
        }
        guard newValue != text else { return }
        confirmingClear = false
        text = newValue

        if text.count > maxCharacters {
            cancelPendingSave()
            status = .overLimit(count: text.count, limit: maxCharacters)
            return
        }

        if case .overLimit = status {
            status = .idle
        }
        scheduleSave()
    }

    /// Cancels any pending debounce timer and persists the current text immediately if valid.
    /// Returns `true` when the current text is durably saved on disk.
    @discardableResult
    func flush() -> Bool {
        cancelPendingSave()

        guard !isReadBlocked else {
            return false
        }

        if text.count > maxCharacters {
            status = .overLimit(count: text.count, limit: maxCharacters)
            return false
        }

        if text == lastSavedText {
            if case .saveFailed = status {
                return false
            }
            return true
        }

        return persistCurrentText()
    }

    /// Enters inline confirmation before clearing. No-op when empty or read-blocked.
    func requestClear() {
        guard !isReadBlocked, !text.isEmpty else {
            confirmingClear = false
            return
        }
        confirmingClear = true
    }

    /// Cancels clear confirmation without touching text or disk.
    func cancelClear() {
        confirmingClear = false
    }

    /// Clears the draft only after `requestClear()` was called and disk is readable.
    /// If persisting the cleared state fails, the previous saved text stays intact and `.saveFailed` is reported.
    @discardableResult
    func confirmClear() -> Bool {
        guard !isReadBlocked, confirmingClear else {
            confirmingClear = false
            return false
        }
        confirmingClear = false
        cancelPendingSave()

        do {
            try writeData(Data(), fileURL)
            text = ""
            lastSavedText = ""
            status = .idle
            return true
        } catch {
            status = .saveFailed(error.localizedDescription)
            return false
        }
    }

    /// Copies the current draft using the caller-provided clipboard writer.
    /// Never reads from the clipboard; returns `false` when empty or read-blocked.
    @discardableResult
    func copy(using writer: (String) -> Bool) -> Bool {
        guard canCopy else { return false }
        return writer(text)
    }

    /// Reloads the draft from disk, discarding any pending unsaved debounce.
    /// Recovers from `.readFailed` once the underlying file is readable again.
    func reload() {
        cancelPendingSave()
        confirmingClear = false
        loadFromDisk()
    }

    // MARK: - Private

    private func loadFromDisk() {
        do {
            guard let data = try readData(fileURL) else {
                text = ""
                lastSavedText = ""
                status = .idle
                return
            }
            guard let decoded = String(data: data, encoding: .utf8) else {
                text = ""
                lastSavedText = ""
                status = .readFailed("Invalid UTF-8 scratchpad data")
                return
            }
            text = decoded
            lastSavedText = decoded
            if decoded.count > maxCharacters {
                status = .overLimit(count: decoded.count, limit: maxCharacters)
            } else {
                status = .idle
            }
        } catch {
            text = ""
            lastSavedText = ""
            status = .readFailed(error.localizedDescription)
        }
    }

    private func scheduleSave() {
        cancelPendingSave()
        guard !isReadBlocked else { return }
        if debounceNanoseconds == 0 {
            _ = persistCurrentText()
            return
        }
        hasPendingSave = true
        let delay = debounceNanoseconds
        pendingSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingSaveTask = nil
            self.hasPendingSave = false
            _ = self.persistCurrentText()
        }
    }

    private func cancelPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        hasPendingSave = false
    }

    @discardableResult
    private func persistCurrentText() -> Bool {
        guard !isReadBlocked else {
            return false
        }
        guard text.count <= maxCharacters else {
            status = .overLimit(count: text.count, limit: maxCharacters)
            return false
        }
        do {
            try writeData(Data(text.utf8), fileURL)
            lastSavedText = text
            status = .saved
            return true
        } catch {
            status = .saveFailed(error.localizedDescription)
            return false
        }
    }

    private static func defaultReadData(from url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func defaultWriteData(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
    }
}
